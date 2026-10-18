local AIPLAYER=require("shadowself/legacy/registry")
-- 只保存坐标、任务描述等普通数据，不持久化实体 GUID 或自动运行状态。
local json = require("json")
local WorldModel = Class(function(self, player, report)
    self.player = player
    self.report = report
    self.resources = {}
    self.tasks = {}
    self.food_history = {}
    self.combat_memory = {}
    self.base = nil
    self.last_decision = "停止"
    self.ready = false
    self.saving = false
    self.save_again = false
    -- 会话区分服务器、地表/洞穴和存档；避免使用同一地图的旧 GUID。
    local session = TheWorld and TheWorld.meta and TheWorld.meta.session_identifier or "unknown"
    local server = TheNet and TheNet:GetServerName() or "local"
    local shard = TheWorld and TheWorld:HasTag("cave") and "cave" or "forest"
    local identity = tostring(session) .. "|" .. tostring(server) .. "|" .. shard .. "|" .. tostring(player.userid or player.prefab)
    local hash = 5381
    for i=1,#identity do hash = (hash*33 + identity:byte(i)) % 2147483647 end
    self.key = "shadowself_ai_v1_" .. tostring(hash)
end)

-- 位置合法性与数量限制同时用于加载本地 JSON。
function WorldModel:ValidPoint(p)
    return type(p) == "table" and type(p.x) == "number" and type(p.z) == "number"
        and p.x == p.x and p.z == p.z and math.abs(p.x) < 100000 and math.abs(p.z) < 100000
end

-- 异步加载；控制器会等待 ready，避免加载覆盖新任务。
function WorldModel:Load()
    local ok = pcall(function()
        TheSim:GetPersistentString(self.key, function(success, text)
            if self.ready then return end -- 超时之后的旧回调不得覆盖新任务。
            if success and text and #text < 250000 then
                local decoded, data = pcall(json.decode, text)
                if decoded and type(data) == "table" and data.version == 1 then
                    if self:ValidPoint(data.base) then self.base = data.base end
                    for _, resource in ipairs(type(data.resources) == "table" and data.resources or {}) do
                        if #self.resources < 300 and self:ValidPoint(resource) and type(resource.prefab) == "string" then
                            self.resources[#self.resources + 1] = resource
                        end
                    end
                    for _, task in ipairs(type(data.tasks) == "table" and data.tasks or {}) do
                        if #self.tasks < 32 and type(task) == "table" and type(task.kind) == "string" then
                            self.tasks[#self.tasks + 1] = task
                        end
                    end
                    local memories=0
                    for key,r in pairs(type(data.combat_memory)=="table" and data.combat_memory or {})do
                        if memories<128 and type(key)=="string" and #key<160 and type(r)=="table" then
                            local clean={hits={},count=type(r.count)=="number" and math.max(0,math.min(999,r.count)) or 0}
                            for _,hit in ipairs(type(r.hits)=="table" and r.hits or {})do
                                if #clean.hits<8 and type(hit)=="table" and type(hit.time)=="number" and hit.time>=0 and hit.time<30 and type(hit.radius)=="number" and hit.radius>0 and hit.radius<=40 then
                                    clean.hits[#clean.hits+1]={time=hit.time,radius=hit.radius}
                                end
                            end
                            if #clean.hits>0 then self.combat_memory[key]=clean;memories=memories+1 end
                        end
                    end
                    self.last_decision = type(data.last_decision) == "string" and data.last_decision or "停止"
                    local count=0
                    for prefab, day in pairs(type(data.food_history)=="table" and data.food_history or {}) do
                        if count<100 and type(prefab)=="string" and type(day)=="number" then self.food_history[prefab]=day; count=count+1 end
                    end
                end
            end
            self.ready = true
        end)
    end)
    if not ok then self.ready = true end
    -- 损坏或没有回调的存储接口不阻止手动使用。
    self.player:DoTaskInTime(5, function() self.ready = true end)
end

-- 有界的空间网格记录；每个资源类型、4单位网格只保留一个位置。
function WorldModel:Observe(entities)
    local indexed = {}
    for i, p in ipairs(self.resources) do indexed[p.prefab .. ":" .. math.floor(p.x/4) .. ":" .. math.floor(p.z/4)] = i end
    for _, e in ipairs(entities) do
        if e:IsValid() and e.prefab and (e:HasTag("pickable") or e:HasTag("CHOP_workable") or e:HasTag("MINE_workable") or e:HasTag("campfire")) then
            local p = e:GetPosition()
            local k = e.prefab .. ":" .. math.floor(p.x/4) .. ":" .. math.floor(p.z/4)
            local value = {prefab=e.prefab, x=p.x, z=p.z, work=e:HasTag("CHOP_workable") and "CHOP" or (e:HasTag("MINE_workable") and "MINE" or nil)}
            if indexed[k] then self.resources[indexed[k]] = value
            elseif #self.resources < 300 then self.resources[#self.resources + 1] = value; indexed[k] = #self.resources end
        end
    end
end

-- 托管结束、任务变化和定时检查点保存；串行写入防止旧内容覆盖新内容。
function WorldModel:Save()
    if not self.ready then return end
    if self.saving then self.save_again = true; return end
    local ok, text = pcall(json.encode, {version=1, base=self.base, resources=self.resources, tasks=self.tasks, food_history=self.food_history, combat_memory=self.combat_memory, last_decision=self.last_decision})
    if not ok then self.report("本地记忆编码失败"); return end
    self.saving = true
    local sent = pcall(function()
        TheSim:SetPersistentString(self.key, text, false, function(success)
            self.saving = false
            if success == false then self.report("本地记忆写入失败") end
            if self.save_again then self.save_again = false; self:Save() end
        end)
    end)
    if not sent then self.saving = false; self.report("本地记忆接口不可用") end
end

-- 基地以手动设置为准，首次启用时可取玩家当前位置。
function WorldModel:SetBase(point)
    self.base = {x=point.x, z=point.z}
    self:Save()
end

AIPLAYER.WorldModel = WorldModel

return true
