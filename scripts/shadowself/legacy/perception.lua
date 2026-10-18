local AIPLAYER=require("shadowself/legacy/registry")
-- 感知层只读取 replica、classified、世界标签及本地可见实体。
local Perception = Class(function(self, player, config, model)
    self.player, self.config, self.model = player, config, model
    self.snapshot = nil
    self.next_scan = 0
end)

-- 可选 replica/模组接口安全读取，未知数据保持 nil，不伪造正常数值。
function Perception:Read(object, method, fallback, ...)
    if object and type(object[method]) == "function" then
        local ok, value = pcall(object[method], object, ...)
        if ok and value ~= nil then return value end
    end
    return fallback
end

-- 主背包、背包容器及已装备物品去重；总数基于服务器同步的 stackable。
function Perception:Inventory()
    local items, counts, seen = {}, {}, {}
    local inv = self.player.replica.inventory
    local function add(list)
        for _, item in pairs(list or {}) do
            if item:IsValid() and not seen[item] then
                seen[item] = true
                items[#items+1] = item
                local n = self:Read(item.replica.stackable, "StackSize", 1)
                counts[item.prefab] = (counts[item.prefab] or 0) + n
            end
        end
    end
    add(self:Read(inv, "GetItems", {}))
    local active=self:Read(inv,"GetActiveItem",nil)
    if active then add({active}) end
    add(self:Read(inv, "GetEquips", {}))
    local overflow = self:Read(inv, "GetOverflowContainer", nil)
    add(self:Read(overflow, "GetItems", {}))
    local free = self:Read(inv, "GetNumSlots", 0)
    for _ in pairs(self:Read(inv, "GetItems", {})) do free = free - 1 end
    if overflow then
        free=free+self:Read(overflow,"GetNumSlots",0)
        for _ in pairs(self:Read(overflow,"GetItems",{})) do free=free-1 end
    end
    return items, counts, free
end

-- 不将队友和己方随从误判为怪物；可读取战斗目标的实体优先使用实际目标。
function Perception:IsThreat(entity)
    if not entity:IsValid() or entity == self.player or entity:HasTag("player") or entity:HasTag("playerghost") or entity:HasTag("INLIMBO") then return false end
    if entity:HasTag("companion") or entity:HasTag("shadowminion") then return false end
    local target = self:Read(entity.replica and entity.replica.combat, "GetTarget", nil)
    if target == self.player then return true end
    if self.player:HasTag("spiderwhisperer") and entity:HasTag("spider") then return false end
    if self.player:HasTag("merm") and entity:HasTag("merm") then return false end
    if entity.HostileToPlayerTest then
        local ok, hostile = pcall(entity.HostileToPlayerTest, entity, self.player)
        if ok then return hostile == true end
    end
    return entity:HasTag("hostile") and not entity:HasTag("isdead")
end

-- 紧急检测每0.05秒运行，完整资源扫描每0.4秒运行。
function Perception:Threats()
    local p = self.player:GetPosition()
    local result = {}
    for _, e in ipairs(TheSim:FindEntities(p.x, 0, p.z, 12, nil, {"INLIMBO", "FX", "NOCLICK", "DECOR"})) do
        if self:IsThreat(e) then result[#result+1] = e end
    end
    table.sort(result, function(a,b) return self.player:GetDistanceSqToInst(a) < self.player:GetDistanceSqToInst(b) end)
    return result
end

-- 收集完整快照；有危险时强制刷新生命值以避免旧数据延迟急救。
function Perception:Scan(force)
    local now = GetTime()
    if not force and self.snapshot and now < self.next_scan then return self.snapshot end
    local player, world = self.player, TheWorld
    local p = player:GetPosition()
    local entities = TheSim:FindEntities(p.x, 0, p.z, self.config.scan_radius, nil, {"INLIMBO", "FX", "NOCLICK", "DECOR"})
    table.sort(entities, function(a,b) return player:GetDistanceSqToInst(a) < player:GetDistanceSqToInst(b) end)
    local items, counts, free = self:Inventory()
    local classified = player.player_classified
    local moisture = classified and classified.moisture and classified.moisture:value() or nil
    local light = nil
    if TheSim.GetLightAtPoint then
        local ok, value = pcall(TheSim.GetLightAtPoint, TheSim, p.x, p.y, p.z)
        if ok then light = value end
    end
    local state = world and world.state or {}
    self.snapshot = {
        pos=p, entities=entities, items=items, counts=counts, free=free,
        health=self:Read(player.replica.health,"GetPercent",nil),
        hunger=self:Read(player.replica.hunger,"GetPercent",nil),
        hunger_max=self:Read(player.replica.hunger,"Max",nil),
        sanity=self:Read(player.replica.sanity,"GetPercent",nil),
        temperature=classified and classified.currenttemperature or nil,
        moisture=moisture, light=light,
        night=state.isnight == true or (world:HasTag("cave") and light ~= nil and light < .15),
        dusk=state.isdusk == true, season=state.season,
        season_days=state.remainingdaysinseason, time=state.time,
        threats=self:Threats(),
    }
    self.model:Observe(entities)
    self.next_scan = now + self.config.scan_interval
    return self.snapshot
end

-- 按 prefab 获取本地可见物品，后续动作仍交给动作选择器检查权限。
function Perception:FindItem(prefab, snapshot)
    for _, item in ipairs((snapshot or self.snapshot).items) do if item.prefab == prefab then return item end end
end

AIPLAYER.Perception = Perception

return true
