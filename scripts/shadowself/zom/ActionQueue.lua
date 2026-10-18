local Config = require("shadowself/zom/Config")
local Aliases = require("shadowself/control/aliases")
local Reporter = require("shadowself/zom/StateReporter")

local Queue = {}
Queue.__index = Queue

local function CopySteps(steps)
    local result = {}
    for _, step in ipairs(steps or {}) do
        local entry = {}
        for key, value in pairs(step) do entry[key] = value end
        result[#result + 1] = entry
    end
    return result
end

local repeatable = { pickup = true, drop = true, equip = true, unequip = true,
    eat = true, use = true, craft = true, attack = true, chop = true, mine = true,
    harvest = true, hammer = true, dig = true, use_on = true, place = true }

function Queue.SupportsCount(kind)
    return repeatable[kind] == true
end

local function ExpandSteps(steps)
    local expanded = {}
    for _, step in ipairs(steps) do
        local count = repeatable[step.kind] and math.min(step.count or 1, Config.MAX_REPEAT) or 1
        for i = 1, count do
            local copy = CopySteps({ step })[1]
            copy.count = 1
            if count > 1 then copy.repeat_index, copy.repeat_total = i, count end
            expanded[#expanded + 1] = copy
        end
    end
    return expanded
end

function Queue.new(G, reply, move, stop, danger, result)
    return setmetatable({ G = G, reply = reply, result = result or reply,
        move = move, stop = stop, danger = danger,
        steps = {}, last = {}, paused = {}, current = nil, sender = nil, last_item = nil }, Queue)
end

function Queue:Cancel(player)
    self.generation=(self.generation or 0)+1
    if self.current ~= nil then
        self.paused = { self.current }
        for _, step in ipairs(self.steps) do self.paused[#self.paused + 1] = step end
    end
    self.steps, self.current = {}, nil
    self.stop(player)
end

function Queue:Set(steps, sender, player)
    self:Cancel(player)
    self.paused = {}
    self.failure=nil
    self.steps, self.last, self.sender = ExpandSteps(steps), ExpandSteps(steps), sender
    for _, step in ipairs(self.steps) do step.sender = sender end
end

-- 装备命令插到队首；原任务及其发令者保留，装备失败也继续原任务。
function Queue:InterruptEquip(steps, sender, player)
    local old = {}
    if self.current ~= nil then
        self.current.sender = self.current.sender or self.sender
        old[#old + 1] = self.current
    end
    for _, step in ipairs(self.steps) do
        step.sender = step.sender or self.sender
        old[#old + 1] = step
    end
    local urgent = ExpandSteps(steps)
    local token = {}
    for _, step in ipairs(urgent) do
        step.sender, step.priority_equip = sender, token
    end
    for _, step in ipairs(old) do urgent[#urgent + 1] = step end
    self.steps, self.current = urgent, nil
    self.stop(player)
end

function Queue:Continue()
    if #self.paused == 0 then return false end
    self.steps, self.current, self.paused = CopySteps(self.paused), nil, {}
    return true
end

function Queue:Repeat()
    if #self.last == 0 then return false end
    self.steps, self.current = CopySteps(self.last), nil
    return true
end

function Queue:Replace(text)
    if #self.last == 0 then return false end
    self.steps, self.current = CopySteps(self.last), nil
    for _, step in ipairs(self.steps) do if step.text ~= nil then step.text = text end end
    self.last = CopySteps(self.steps)
    return true
end

function Queue:Task()
    local step = self.current or self.steps[1]
    return step and ((step.kind or "任务") .. (step.text and " " .. step.text or "")) or nil
end

function Queue:IsPassive()
    local step = self.current or self.steps[1]
    return step ~= nil and (step.kind == "status" or step.kind == "say")
end

function Queue:IsPortal()
    local step = self.current or self.steps[1]
    return step ~= nil and step.kind == "jump_wormhole"
end

function Queue:IsSit()
    local step = self.current or self.steps[1]
    return step ~= nil and step.kind == "sit"
end

function Queue:IsEquip()
    local step = self.current or self.steps[1]
    return step ~= nil and step.kind == "equip"
end

function Queue:IsTargetMove()
    local step = self.current or self.steps[1]
    return step ~= nil and (step.kind == "cuddle" or step.kind == "approach")
end

function Queue:Suspend(now)
    if self.current ~= nil and self.suspended_at == nil then self.suspended_at = now end
end

local function InventoryItem(player, prefab, predicate)
    local inv = player.replica.inventory
    if prefab == "__food__" then
        for _, ent in pairs(inv:GetItems()) do
            if ent:HasTag("edible") then return ent end
        end
        return nil
    end
    local function Match(ent)
        return ent.prefab == prefab and (predicate == nil or predicate(ent))
    end
    local item = inv:FindItem(Match)
    if item ~= nil then return item end
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then
        for _, ent in pairs(overflow:GetItems()) do if Match(ent) then return ent end end
    end
    for _, ent in pairs(inv:GetEquips()) do if Match(ent) then return ent end end
    return nil
end

local function CountItem(player, prefab)
    local count, seen = 0, {}
    local function Add(item)
        if item ~= nil and item:IsValid() and item.prefab == prefab and not seen[item.GUID] then
            seen[item.GUID] = true
            local stack = item.replica ~= nil and item.replica.stackable
            count = count + (stack ~= nil and stack:StackSize() or 1)
        end
    end
    local inv = player.replica.inventory
    for _, item in pairs(inv:GetItems()) do Add(item) end
    for _, item in pairs(inv:GetEquips()) do Add(item) end
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then for _, item in pairs(overflow:GetItems()) do Add(item) end end
    return count
end

local function IsEquipped(player, item)
    for _, equipped in pairs(player.replica.inventory:GetEquips()) do
        if equipped == item then return true end
    end
    return false
end

local function FindEntity(G, player, prefabs, radius, ground)
    local x, _, z = player.Transform:GetWorldPosition()
    local nearest, best = nil, radius * radius
    for _, ent in ipairs(G.TheSim:FindEntities(x, 0, z, radius, nil, { "INLIMBO", "playerghost" })) do
        if ent:IsValid() and prefabs[ent.prefab]
            and (not ground or (ent.replica ~= nil and ent.replica.inventoryitem ~= nil))
            and not ent:HasTag("dead") then
            local d = player:GetDistanceSqToInst(ent)
            if d < best then nearest, best = ent, d end
        end
    end
    return nearest
end

local function FindSeat(G, player, prefab)
    local x, _, z = player.Transform:GetWorldPosition()
    local nearest, best = nil, Config.SEARCH_RADIUS ^ 2
    for _, ent in ipairs(G.TheSim:FindEntities(x, 0, z, Config.SEARCH_RADIUS,
        { "cansit" }, { "INLIMBO", "fire" })) do
        if ent:IsValid() and (prefab == nil or ent.prefab == prefab) then
            local distance = player:GetDistanceSqToInst(ent)
            if distance < best then nearest, best = ent, distance end
        end
    end
    return nearest
end

local function FindWormhole(G, origin, radius)
    local x, _, z = origin:Get()
    radius = radius or Config.PORTAL_OWNER_RADIUS
    local nearest, best = nil, radius ^ 2
    for _, ent in ipairs(G.TheSim:FindEntities(x, 0, z, radius,
        nil, { "INLIMBO" })) do
        if ent:IsValid() and ent.prefab == "wormhole" then
            local ex, _, ez = ent.Transform:GetWorldPosition()
            local d = (ex - x) ^ 2 + (ez - z) ^ 2
            if d < best then nearest, best = ent, d end
        end
    end
    return nearest
end

local function FindDeployPoint(G, player, item, attempt)
    local boat = item:HasTag("boatbuilder")
    local radius = boat and Config.BOAT_PLACE_SEARCH_RADIUS or Config.PLACE_SEARCH_RADIUS
    local x, _, z = player.Transform:GetWorldPosition()
    local valid = {}
    for distance = 0, radius, 2 do
        for angle = 0, (distance == 0 and 0 or 15) do
            local theta = angle * math.pi / 8
            local pt = G.Vector3(x + distance * math.cos(theta), 0,
                z + distance * math.sin(theta))
            if (not boat or (G.TheWorld.Map:IsOceanAtPoint(pt:Get())
                and G.TheWorld.Map:GetPlatformAtPoint(pt.x, pt.z) == nil))
                and item.replica.inventoryitem:CanDeploy(pt, nil, player, 0) then
                valid[#valid + 1] = pt
            end
        end
    end
    return #valid > 0 and valid[(attempt % #valid) + 1] or nil
end

local function SceneAction(G, player, target, wanted)
    local controller = player.components.playercontroller
    local picker = player.components.playeractionpicker
    local pos = target:GetPosition()
    local left = picker:GetLeftClickActions(pos, target)
    local right = picker:GetRightClickActions(pos, target)
    -- 服务器重新取鼠标动作时只认各键的第一项，不能选客户端列表后面的动作。
    local act, is_right = left[1], false
    if act == nil or act.action ~= wanted then act, is_right = right[1], true end
    if act == nil or act.action ~= wanted then return false end
    if not controller.ismastersim then
        -- 原版 DoAction 在客户端只预演；没有点击回调就不会把 PICKUP 等动作送到服务器。
        local platform, x, z = controller:GetPlatformRelativePosition(pos.x, pos.z)
        local mods = controller:EncodeControlMods()
        local function Send()
            local released = controller.locomotor ~= nil or nil
            local noforce = controller.locomotor == nil and wanted.canforce or nil
            if is_right then
                G.SendRPCToServer(G.RPC.RightClick, wanted.code, x, z, target,
                    act.rotation ~= 0 and act.rotation or nil, released, mods,
                    noforce, wanted.mod_name, platform, platform ~= nil)
            else
                G.SendRPCToServer(G.RPC.LeftClick, wanted.code, x, z, target,
                    released, mods, noforce, wanted.mod_name, platform, platform ~= nil)
            end
        end
        if controller.locomotor == nil then act.non_preview_cb = Send
        else act.preview_cb = Send end
    end
    controller:DoAction(act)
    return true
end

Queue.SceneAction = SceneAction -- 复用原版动作选择，供主控制层处理鬼手和作祟。

local function PointAction(G, player, point, item, wanted)
    local controller = player.components.playercontroller
    local act = player.components.playeractionpicker:GetPointActions(point, item, true, nil)[1]
    if act == nil or act.action ~= wanted then return false end
    if not controller.ismastersim then
        local platform, x, z = controller:GetPlatformRelativePosition(point.x, point.z)
        local mods = controller:EncodeControlMods()
        local function Send()
            G.SendRPCToServer(G.RPC.RightClick, wanted.code, x, z, nil,
                act.rotation ~= 0 and act.rotation or nil,
                controller.locomotor ~= nil or nil, mods,
                controller.locomotor == nil and wanted.canforce or nil,
                wanted.mod_name, platform, platform ~= nil)
        end
        if controller.locomotor == nil then act.non_preview_cb = Send
        else act.preview_cb = Send end
    end
    controller:DoAction(act)
    return true
end

Queue.PointAction = PointAction

local function SelfAction(G, player, item, wanted)
    local picker = player.components.playeractionpicker
    local controller = player.components.playercontroller
    for _, right in ipairs({ true, false }) do
        for _, act in ipairs(picker:GetInventoryActions(item, right)) do
            if act.action == wanted then
                if controller.ismastersim then controller:DoAction(act)
                else controller:RemoteControllerUseItemOnSelfFromInvTile(act, item) end
                return true
            end
        end
    end
    return false
end

function Queue:Done(message)
    if self.current ~= nil and (self.current.repeat_total or 1) > 1 then
        if self.current.repeat_index < self.current.repeat_total then
            self.current = nil
            return -- 重复任务只在最后播报一次，避免“捡10个”刷10条。
        end
        message = string.format("%d/%d：%s", self.current.repeat_index,
            self.current.repeat_total, message)
    end
    local recipient = self.sender
    if self.current ~= nil and (self.current.kind == "status" or self.current.report)
        and recipient ~= nil then
        recipient = { userid = recipient.userid, name = recipient.name,
            entity = recipient.entity, whisper = recipient.whisper,
            task_reply_whisper = false } -- 状态汇报遵循提问者原来的聊天频道。
    end
    if type(message) == "table" then
        for _, line in ipairs(message) do self.result(recipient, line) end
    else
        self.result(recipient, message)
    end
    self.current = nil
end

function Queue:Fail(message)
    self.failure=message
    if self.current ~= nil and (self.current.repeat_total or 1) > 1
        and self.current.repeat_index > 1 then
        message = string.format("已完成%d/%d，随后中断：%s",
            self.current.repeat_index - 1, self.current.repeat_total, message)
    end
    self.result(self.sender, message)
    if self.current ~= nil and self.current.priority_equip then
        while self.steps[1] ~= nil
            and self.steps[1].priority_equip == self.current.priority_equip do
            table.remove(self.steps, 1)
        end
        self.current = nil
        return
    end
    self.steps, self.current = {}, nil
end

function Queue:Working(message)
    if self.current == nil or (self.current.repeat_index or 1) == 1 then
        self.reply(self.sender, message)
    end
end

function Queue:Update(player, now)
    if self.suspended_at ~= nil then
        if self.current ~= nil then self.current.started = self.current.started + now - self.suspended_at end
        self.suspended_at = nil
    end
    if self.current == nil then
        self.current = table.remove(self.steps, 1)
        if self.current == nil then return false end
        self.sender = self.current.sender or self.sender
        self.current.started = now
    end
    local step = self.current
    local generation=self.generation
    local real=self.realG or self.G;self.realG=real
    self.G=setmetatable({SendRPCToServer=function(...)
        if self.generation==generation and self.current==step then return real.SendRPCToServer(...) end
    end},{__index=real})
    local timeout = step.kind == "pickup_nearby" and 120
        or step.kind == "place" and math.huge
        or step.kind == "jump_wormhole" and Config.PORTAL_WAIT_TIMEOUT or Config.STEP_TIMEOUT
    if now - step.started > timeout then self:Fail("等待太久了，没能完成这次任务。"); return false end
    if step.kind == "cuddle" or step.kind == "approach" then
        local target = step.target
        if target == nil or not target:IsValid() then
            self:Fail("附近找不到" .. (step.text or "目标") .. "，没法靠近。"); return false
        end
        if player:GetDistanceSqToInst(target) <= 2.25 ^ 2 then
            self.stop(player)
            self:Done(step.kind == "cuddle"
                and ("到" .. (step.text or "你") .. "旁边啦，贴贴～")
                or ("已走到" .. (step.text or "目标") .. "附近。"))
            return true
        end
        if not step.announced then
            self:Working(step.kind == "cuddle"
                and ("正在去找" .. (step.text or "你") .. "贴贴…")
                or ("正在走向" .. (step.text or "目标") .. "附近…"))
            step.announced = true
        end
        if now - (step.last_move or -100) >= Config.MOVE_RETRY then
            self.move(player, target:GetPosition()); step.last_move = now
        end
        return true
    end
    if step.kind == "status" then
        local next_step = self.steps[1]
        local task = next_step and ((next_step.kind or "任务") .. (next_step.text or "")) or nil
        self:Done(Reporter.Get(self.G, player, step.topic, task)); return true
    elseif step.kind == "say" then
        self:Done(step.text); return true
    end
    if step.kind == "pickup_nearby" then
        if step.targets == nil then
            local x, _, z = player.Transform:GetWorldPosition()
            step.targets = {}
            for _, ent in ipairs(self.G.TheSim:FindEntities(x, 0, z,
                Config.PICKUP_ALL_RADIUS, nil, { "INLIMBO", "playerghost" })) do
                if ent:IsValid() and ent.replica ~= nil
                    and ent.replica.inventoryitem ~= nil then
                    step.targets[#step.targets + 1] = ent
                end
            end
            table.sort(step.targets, function(a, b)
                return player:GetDistanceSqToInst(a) < player:GetDistanceSqToInst(b)
            end)
            step.collected, step.skipped = 0, 0
            if #step.targets > 0 then
                self:Working("开始拾取脚边5码内的物品。")
            end
        end
        if step.target ~= nil then
            local ent = step.target
            if CountItem(player, step.prefab) > step.before then
                step.collected = step.collected + 1
                step.target = nil
            elseif not ent:IsValid() or ent:HasTag("INLIMBO")
                or now - step.sent > Config.PICKUP_ALL_ITEM_TIMEOUT then
                step.skipped = step.skipped + 1
                step.target = nil
            else
                return true
            end
        end
        if #step.targets == 0 then
            self:Done("脚边拾取完成：捡起" .. step.collected .. "堆"
                .. (step.skipped > 0 and "，跳过" .. step.skipped .. "堆无法拾取的物品。" or "。"))
            return true
        end
        if player.replica.inventory:IsFull() then
            self:Fail("背包满了；已捡起" .. step.collected .. "堆，剩下的先不捡。")
            return false
        end
        while #step.targets > 0 do
            local ent = table.remove(step.targets, 1)
            if ent:IsValid() and not ent:HasTag("INLIMBO")
                and not self.danger(player, ent:GetPosition()) then
                local prefab = ent.prefab
                local before = CountItem(player, prefab)
                if SceneAction(self.G, player, ent, self.G.ACTIONS.PICKUP) then
                    step.target, step.prefab, step.before, step.sent = ent, prefab, before, now
                    return true
                end
            end
            step.skipped = step.skipped + 1
        end
        self:Done("脚边拾取完成：捡起" .. step.collected .. "堆"
            .. (step.skipped > 0 and "，跳过" .. step.skipped .. "堆无法拾取的物品。" or "。"))
        return true
    end
    if step.kind == "jump_wormhole" then
        local owner = step.follow
        if step.arena then step.owner_pos = player:GetPosition()
        elseif owner ~= nil and owner:IsValid() then step.owner_pos = owner:GetPosition() end
        if step.owner_pos == nil then self:Fail("我看不到跟随主人的位置。"); return false end
        if step.sent ~= nil and step.start_pos ~= nil
            and player:GetDistanceSqToPoint(step.start_pos:Get()) > 20 * 20 then
            self:Done("已经跟你跳过虫洞啦！"); return true
        end
        local portal = step.portal ~= nil and step.portal:IsValid() and step.portal
            or FindWormhole(self.G, step.owner_pos,
                step.arena and Config.ARENA_WORMHOLE_RADIUS or nil)
        if portal == nil then
            if step.arena then self:Fail("角斗场附近没有加载到虫洞。"); return false end
            if owner ~= nil and owner:IsValid() and player:GetDistanceSqToInst(owner) > 5 * 5
                and now - (step.last_move or -100) >= Config.MOVE_RETRY then
                if not player:HasTag("playerghost") and self.danger(player, owner:GetPosition()) then
                    self:Fail("主人那边有怪物，暂时不敢靠近虫洞。"); return false
                end
                self.move(player, owner:GetPosition()); step.last_move = now
            end
            return true
        end
        step.portal = portal
        if not step.arena and not player:HasTag("playerghost")
            and self.danger(player, portal:GetPosition()) then
            self:Fail("虫洞边太危险了，等清怪后再叫我哦。"); return false
        end
        if player:GetDistanceSqToInst(portal) > 4 * 4 then
            if now - (step.last_move or -100) >= Config.MOVE_RETRY then
                self.move(player, portal:GetPosition()); step.last_move = now
            end
            return true
        end
        if now - (step.sent or -100) >= 2 then
            if (step.attempts or 0) >= 3 then self:Fail("虫洞暂时进不去，我先停在这里。"); return false end
            if not SceneAction(self.G, player, portal, self.G.ACTIONS.JUMPIN) then
                self:Fail("现在无法跳进这个虫洞。"); return false
            end
            step.start_pos = player:GetPosition()
            step.sent, step.attempts = now, (step.attempts or 0) + 1
            if not step.announced then
                self:Working("找到虫洞啦，我跟着跳进去！")
                step.announced = true
            end
        end
        return true
    end
    local kind, name = step.kind, step.text or self.last_item
    local prefab = step.prefab or (name and Aliases.Resolve(name, self.G) or nil)
    local worktags={chop="CHOP_workable",mine="MINE_workable",hammer="HAMMER_workable",dig="DIG_workable",harvest="pickable"}
    local worktag=worktags[kind]
    if step.target and worktag and step.last_attempt and step.target:IsValid() and not step.target:HasTag(worktag) then
        self:Done("这个目标已处理。");return true
    end
    local generic=(kind=="chop" and (name=="树" or name=="树木")) or (kind=="mine" and (name=="矿石" or name=="石头" or not name))
    if generic and not step.target then
        local x,y,z=player.Transform:GetWorldPosition();local best=Config.SEARCH_RADIUS^2
        for _,e in ipairs(self.G.TheSim:FindEntities(x,y,z,Config.SEARCH_RADIUS,{worktag},{"INLIMBO","FX"})) do
            if e:IsValid() and e:HasTag(worktag) and player:GetDistanceSqToInst(e)<best then
                step.target=e;prefab=e.prefab;step.prefab=prefab;best=player:GetDistanceSqToInst(e)
            end
        end
    end
    if kind == "use" and prefab ~= nil and InventoryItem(player, prefab) == nil then
        local nearby = FindEntity(self.G, player, { [prefab] = true }, Config.SEARCH_RADIUS)
        if nearby ~= nil and nearby:HasTag("structure") then kind = "interact"; step.target = nearby end
    end
    if kind == "interact" then
        local target = step.target
        if target == nil then
            if prefab ~= nil then
                target = FindEntity(self.G, player, { [prefab] = true }, Config.SEARCH_RADIUS)
            else
                -- 魔改建筑可能只有实体显示名，没有登记到 STRINGS.NAMES。
                local x, _, z = player.Transform:GetWorldPosition()
                local best = Config.SEARCH_RADIUS ^ 2
                for _, ent in ipairs(self.G.TheSim:FindEntities(x, 0, z, Config.SEARCH_RADIUS,
                    nil, { "INLIMBO", "playerghost" })) do
                    if ent:IsValid() and ent:GetBasicDisplayName() == name then
                        local distance = player:GetDistanceSqToInst(ent)
                        if distance < best then target, best = ent, distance end
                    end
                end
            end
            step.target = target
        end
        if target == nil or not target:IsValid() then self:Fail("附近找不到" .. name .. "。"); return false end
        if step.sent ~= nil and now - step.sent < 1 then return true end
        if target.prefab == "nightlight" and step.intent ~= "关闭"
            and target:HasTag("shadow_fire") then self:Done("暗夜灯已经亮着。"); return true end
        -- 优先选择目标实际暴露的左右键动作，不能用 prefab 推断魔改建筑的行为。
        local picker = player.components.playeractionpicker
        local left = picker:GetLeftClickActions(target:GetPosition(), target)
        local right = picker:GetRightClickActions(target:GetPosition(), target)
        local candidates = {}
        for _, list in ipairs({ right, left }) do
            local act = list[1]
            if act ~= nil then
                local action = act.action
                local id = action.id or ""
                local label = act:GetActionString() or ""
                if action ~= self.G.ACTIONS.LOOKAT and action ~= self.G.ACTIONS.WALKTO
                    and action ~= self.G.ACTIONS.ATTACK and action ~= self.G.ACTIONS.HAMMER
                    and action ~= self.G.ACTIONS.CHOP and action ~= self.G.ACTIONS.MINE
                    and action ~= self.G.ACTIONS.DIG and action ~= self.G.ACTIONS.HAUNT
                    and not id:find("DESTROY") and not id:find("DISMANTLE")
                    and not label:find("拆", 1, true) and not label:find("攻击", 1, true)
                    and not (step.intent == "打开" and action == self.G.ACTIONS.EXTINGUISH) then
                    candidates[action] = act
                end
            end
        end
        local chosen, count = nil, 0
        for action, act in pairs(candidates) do
            local id = action.id or ""
            local label = act:GetActionString() or ""
            local wanted = step.intent == "打开" and (id == "TURNON" or id == "ACTIVATE" or id == "OPEN")
                or step.intent == "关闭" and (id == "TURNOFF" or id == "DEACTIVATE" or id == "CLOSE")
                or step.intent ~= nil and label:find(step.intent, 1, true) ~= nil
            if wanted then chosen, count = action, 1; break end
            chosen, count = action, count + 1
        end
        if count > 1 then
            self:Fail("这个建筑有多个交互，请明确要打开、关闭，还是使用哪个功能。"); return false
        elseif chosen ~= nil then
            if step.intent == "关闭" and (chosen == self.G.ACTIONS.TURNON or chosen == self.G.ACTIONS.ACTIVATE) then
                self:Fail("当前只能打开，不能关闭这个建筑。"); return false
            elseif step.intent == "打开" and chosen == self.G.ACTIONS.TURNOFF then
                self:Done("这个建筑已经打开。"); return true
            end
            if step.sent ~= nil then self:Done("已向" .. name .. "发送交互请求。"); return true end
            if not SceneAction(self.G, player, target, chosen) then
                self:Fail("交互条件已经变化，请重新尝试。"); return false
            end
        elseif prefab == "nightlight" then
            if step.intent == "关闭" then self:Fail("当前没有关闭暗夜灯的可用动作。"); return false end
            if target:HasTag("shadow_fire") then self:Done("暗夜灯已经亮着。"); return true end
            local fuel = InventoryItem(player, "nightmarefuel")
            if fuel == nil then self:Fail("没有噩梦燃料，无法点亮暗夜灯。"); return false end
            local act = player.components.playercontroller:GetItemUseAction(fuel, target)
            if act == nil or act.action ~= self.G.ACTIONS.ADDFUEL then
                self:Fail("暗夜灯当前不能添加燃料。"); return false
            end
            player.components.playercontroller:RemoteControllerUseItemOnSceneFromInvTile(act, fuel)
        else
            if step.sent ~= nil then self:Done("已与" .. name .. "交互。"); return true end
            self:Fail("这个建筑当前没有可用交互，请指定燃料或所需物品。"); return false
        end
        step.sent = now
        return true
    end
    if kind == "sit" then
        if player:HasTag("sitting_on_chair") then
            self:Done("已经坐好啦。"); return true
        end
        local seat = FindSeat(self.G, player, prefab)
        if seat == nil then self:Fail("附近没有空着的" .. (name or "椅子") .. "。"); return false end
        if not step.announced then
            self:Working("正在去" .. (name or "椅子") .. "坐下…")
            step.announced = true
        end
        if now - (step.last_attempt or -100) >= 2 then
            if not SceneAction(self.G, player, seat, self.G.ACTIONS.SITON) then
                self:Fail("这张椅子现在不能坐。"); return false
            end
            step.last_attempt = now
        end
        return true
    end
    if kind == "craft" then
        if prefab == nil then self:Fail("我不认识“" .. tostring(name) .. "”这个东西，能不能换个说法？"); return false end
        local recipe = self.G.GetValidRecipe ~= nil and self.G.GetValidRecipe(prefab) or nil
        local builder = player.replica.builder
        if recipe ~= nil and recipe.placer ~= nil then self:Fail("建筑配方需要放置位置，请使用自主任务 build 坐标指令。"); return false end
        if recipe == nil or builder == nil or not builder:KnowsRecipe(recipe) or not builder:HasIngredients(recipe) then
            self:Fail("没有材料或还不会做" .. name .. "。"); return false
        end
        if step.before == nil then
            step.before = CountItem(player, prefab)
            builder:MakeRecipeFromMenu(recipe)
            self:Working("正在制作" .. name .. "…")
        elseif CountItem(player, prefab) > step.before then
            self:Done("做好了：" .. name); return true
        end
        return true
    end
    if kind == "goto" then
        local point
        if step.x ~= nil then point = self.G.Vector3(step.x, 0, step.z)
        elseif name == "基地" and Config.BASE_POINT ~= nil then
            point = self.G.Vector3(Config.BASE_POINT.x, 0, Config.BASE_POINT.z)
        else
            local choices = Config.LANDMARKS[name] or {}
            local prefabs = {}
            for _, p in ipairs(choices) do prefabs[p] = true end
            local ent = FindEntity(self.G, player, prefabs, Config.SEARCH_RADIUS * 2)
            if ent ~= nil then point = ent:GetPosition() end
        end
        if point == nil then self:Fail("我现在看不到" .. (name or "那里") .. "的位置，没法盲走过去。"); return false end
        if player:GetDistanceSqToPoint(point:Get()) < Config.ARRIVE_DISTANCE ^ 2 then
            self.stop(player); self:Done("已经到达" .. (name or "目标") .. "。"); return true
        end
        if self.danger(player, point) then self:Fail("太危险了，我不敢过去…"); return false end
        if not step.announced then self:Working("正在前往" .. (name or "目标") .. "…"); step.announced = true end
        if now - (step.last_move or -100) >= Config.MOVE_RETRY then
            self.move(player, point); step.last_move = now
        end
        return true
    end
    if kind == "place" then
        if prefab == nil then
            self:Fail("我不认识“" .. tostring(name) .. "”这个东西，能不能换个说法？")
            return false
        end
        if step.before ~= nil and CountItem(player, prefab) < step.before then
            self:Done("已经放置" .. name .. "。")
            return true
        end
        local item = InventoryItem(player, prefab)
        if item == nil then self:Fail("背包里没有" .. name .. "。"); return false end
        if item.replica == nil or item.replica.inventoryitem == nil
            or not item.replica.inventoryitem:IsDeployable(player) then
            self:Fail(name .. "不是可放置物品，不能当成部署来操作。")
            return false
        end
        if not step.announced then
            self:Working(item:HasTag("boatbuilder")
                and ("正在找最近能放" .. name .. "的海面…")
                or ("正在脚边找能放" .. name .. "的位置…"))
            step.announced = true
        end
        if step.sent ~= nil and now - step.sent < (step.wait or 8) then return true end
        if now - (step.last_search or -100) < Config.PLACE_RETRY then return true end
        step.last_search = now
        local point = FindDeployPoint(self.G, player, item, step.attempt or 0)
        if point == nil then return true end -- 继续找，直到找到合法位置或玩家取消。
        local controller = player.components.playercontroller
        step.before, step.sent = CountItem(player, prefab), now
        step.wait = 5 + math.sqrt(player:GetDistanceSqToPoint(point:Get())) / 4
        step.attempt = (step.attempt or 0) + 1
        if controller.ismastersim then
            controller:DoAction(self.G.BufferedAction(player, nil, self.G.ACTIONS.DEPLOY,
                item, point))
        else
            local platform, x, z = controller:GetPlatformRelativePosition(point.x, point.z)
            self.G.SendRPCToServer(self.G.RPC.ControllerActionButtonDeploy, item,
                x, z, nil, true, platform, platform ~= nil)
        end
        return true
    end
    if kind == "use_on" then
        if prefab == nil then
            self:Fail("我不认识“" .. tostring(name) .. "”这个东西，能不能换个说法？")
            return false
        end
        local target_prefab = Aliases.Resolve(step.target, self.G)
        if target_prefab == nil then
            self:Fail("我不认识“" .. tostring(step.target) .. "”这个目标。")
            return false
        end
        local item = InventoryItem(player, prefab)
        local target = FindEntity(self.G, player, { [target_prefab] = true }, Config.SEARCH_RADIUS)
        if item == nil then self:Fail("背包里没有" .. name .. "。"); return false end
        if target == nil then self:Fail("附近找不到" .. step.target .. "。"); return false end
        if self.danger(player, target:GetPosition()) then
            self:Fail("太危险了，我不敢过去…"); return false
        end
        if player:GetDistanceSqToInst(target) > 5 * 5 then
            if not step.announced then
                self:Working("正在前往" .. step.target .. "…"); step.announced = true
            end
            if now - (step.last_move or -100) >= Config.MOVE_RETRY then
                self.move(player, target:GetPosition()); step.last_move = now
            end
            return true
        end
        if step.sent == nil then
            local act = player.components.playercontroller:GetItemUseAction(item, target)
            if act == nil or act.target ~= target or act.invobject ~= item then
                self:Fail(name .. "现在不能对" .. step.target .. "使用。"); return false
            end
            player.components.playercontroller:RemoteControllerUseItemOnSceneFromInvTile(act, item)
            self:Working("正在对" .. step.target .. "使用" .. name .. "…")
            step.sent = now
        elseif now - step.sent > 1 then
            self:Done("已尝试对" .. step.target .. "使用" .. name .. "，请看游戏内结果。")
            return true
        end
        return true
    end
    if prefab == nil and kind ~= "retreat" then
        self:Fail(name and ("我不认识“" .. name .. "”这个东西，能不能换个说法？") or "你说的是哪个东西呀？")
        return false
    end
    if kind == "pickup" or kind == "find" or kind == "attack" or kind == "chop"
        or kind == "mine" or kind == "harvest" or kind == "hammer" or kind == "dig" then
        if kind == "find" and InventoryItem(player, prefab) ~= nil then
            self.last_item = name; self:Done("背包里有" .. name .. "。"); return true
        end
        if kind == "pickup" and step.before ~= nil and CountItem(player, prefab) > step.before then
            self.last_item = name; self:Done("捡到" .. name .. "了！"); return true
        end
        if step.target ~= nil and (not step.target:IsValid() or step.target:HasTag("dead")
            or (step.target.replica ~= nil and step.target.replica.health ~= nil
                and step.target.replica.health:IsDead())) then
            if kind == "pickup" then self:Fail("目标不见了，没有捡到手。")
            else self:Done("目标已处理。") end
            return true
        end
        local targets = { [prefab] = true }
        local ent = step.target or FindEntity(self.G, player, targets, Config.SEARCH_RADIUS, kind == "pickup")
        if ent == nil then self:Fail("呜…找不到" .. name .. "。"); return false end
        if kind == "attack" and ent:HasTag("player") then
            self:Fail("不要让我打玩家啦，我会被讨厌的。"); return false
        end
        step.target = ent
        if kind == "find" then self.last_item = name; self:Done("找到你要的" .. name .. "啦！"); return true end
        if kind == "pickup" and player.replica.inventory:IsFull() then
            self:Fail("背包满了，先帮我清一下嘛。"); return false
        end
        if self.danger(player, ent:GetPosition()) and kind ~= "attack" then
            self:Fail("太危险了，我不敢过去…"); return false
        end
        if not step.announced then
            self:Working(kind == "pickup" and ("找到" .. name .. "了，马上捡起来！")
                or ("正在" .. (kind == "attack" and "攻击" or "处理") .. name .. "…"))
            step.announced = true
        end
        local action = ({ pickup = self.G.ACTIONS.PICKUP, attack = self.G.ACTIONS.ATTACK,
            chop = self.G.ACTIONS.CHOP, mine = self.G.ACTIONS.MINE, harvest = self.G.ACTIONS.PICK,
            hammer = self.G.ACTIONS.HAMMER, dig = self.G.ACTIONS.DIG })[kind]
        if now - (step.last_attempt or -100) >= 1.2 then
            if kind == "pickup" and step.before == nil then step.before = CountItem(player, prefab) end
            if not SceneAction(self.G, player, ent, action) then
                if worktag and action then
                    local inv=player.replica.inventory;local hand=inv:GetEquippedItem(self.G.EQUIPSLOTS.HANDS)
                    local lists={inv:GetItems(),inv:GetEquips()}
                    local overflow=inv:GetOverflowContainer();if overflow then lists[#lists+1]=overflow:GetItems() end
                    for _,list in ipairs(lists) do for _,tool in pairs(list) do
                        if tool~=hand and tool:HasTag(action.id.."_tool") and SelfAction(self.G,player,tool,self.G.ACTIONS.EQUIP) then
                            step.last_attempt=now;return true
                        end
                    end end
                end
                self:Fail("这个目标暂时不能执行该动作，检查工具与动作条件。"); return false
            end
            step.last_attempt = now
        end
        return true
    end
    if kind == "use" and prefab == "pocketwatch_heal" and step.sent ~= nil then
        if step.watch ~= nil and step.watch:IsValid()
            and not step.watch:HasTag("pocketwatch_inactive") then
            self:Done("已使用不老表。"); return true
        end
        if now - step.sent > 3 then self:Fail("不老表没有成功施放，请稍后重试。"); return false end
        return true
    end
    local is_heal_watch = kind == "use" and prefab == "pocketwatch_heal"
    local item = step.equip_item or InventoryItem(player, prefab,
        is_heal_watch and function(ent) return ent:HasTag("pocketwatch_inactive") end or nil)
    if item == nil and step.sent ~= nil and now - step.sent > .6
        and (kind == "drop" or kind == "give" or kind == "store" or kind == "heal"
            or kind == "eat" or kind == "use") then
        self:Done("已完成" .. name .. "的操作。"); return true
    end
    if item == nil then
        self:Fail(is_heal_watch and InventoryItem(player, prefab) ~= nil
            and "身上的不老表都在冷却。" or ("背包里没有" .. name .. "。"))
        return false
    end
    if prefab == "__food__" then
        prefab, name = item.prefab, item:GetBasicDisplayName()
        step.prefab = prefab
    end
    self.last_item = name
    if kind == "drop" then
        if step.sent == nil then
            step.before = CountItem(player, prefab)
            self:Working("正在丢下" .. name .. "…")
            -- 原版 single=false 会丢当前格的整组；普通数量命令仍一次丢一个。
            player.components.playercontroller:RemoteDropItemFromInvTile(item,
                not step.whole_stack)
            step.sent = now
        end
        if now - step.sent > 1 and CountItem(player, prefab) < step.before then
            self:Done("已经丢下" .. name .. "。"); return true
        end
        return true
    elseif kind == "equip" or (kind == "use"
        and (prefab == "torch" or prefab == "hammer" or prefab == "shovel")) then
        -- “装备3次”是三次真实的装备动作；已装备时先卸下，等服务器同步后再装。
        if step.phase == nil then
            step.equip_item = item -- 多件同类装备时始终确认本次提交的那件。
            if (step.repeat_total or 1) == 1 and IsEquipped(player, item) then
                self:Done(name .. "已经装备好了。"); return true
            end
            step.phase = IsEquipped(player, item) and "remove" or "wear"
        end
        if step.phase == "remove" then
            if not SelfAction(self.G, player, item, self.G.ACTIONS.UNEQUIP) then
                self:Fail("暂时卸不下" .. name .. "，不能重复装备。"); return false
            end
            step.phase, step.sent = "wait_remove", now
            return true
        elseif step.phase == "wait_remove" then
            if IsEquipped(player, item) then return true end
            step.phase, step.sent = "wear", nil
        end
        if step.phase == "wear" then
            if not SelfAction(self.G, player, item, self.G.ACTIONS.EQUIP) then
                self:Fail("现在无法装备" .. name .. "。"); return false
            end
            self:Working("正在装备" .. name .. "…")
            step.phase, step.sent = "wait_wear", now
            return true
        elseif step.phase == "wait_wear" and IsEquipped(player, item) then
            self:Done("搞定！" .. name .. "装备好了。"); return true
        elseif step.phase == "wait_wear" and now - step.sent > .8 then
            step.phase = "wear" -- 请求被忙碌状态忽略时重试，不一直等到超时。
        end
        return true
    elseif kind == "eat" or kind == "unequip" or kind == "use" then
        local action = kind == "eat" and self.G.ACTIONS.EAT
            or kind == "use" and self.G.ACTIONS.PLAY or self.G.ACTIONS.UNEQUIP
        if kind == "use" and prefab ~= "panflute" then
            -- 让原版为该物品选动作；拒绝装备/丢弃等与“使用”含义不同的动作。
            action = nil
            for _, right in ipairs({ true, false }) do
                for _, candidate in ipairs(player.components.playeractionpicker:GetInventoryActions(item, right)) do
                    local selected = candidate.action
                    if selected ~= self.G.ACTIONS.LOOKAT and selected ~= self.G.ACTIONS.EQUIP
                        and selected ~= self.G.ACTIONS.UNEQUIP and selected ~= self.G.ACTIONS.DROP then
                        action = selected; break
                    end
                end
                if action ~= nil then break end
            end
            if action == nil then
                self:Fail("这个物品需要指定目标或落点，我不能盲用。"); return false
            end
        end
        if not step.sent then
            step.before = CountItem(player, prefab)
            if kind == "use" and item.replica.finiteuses ~= nil then
                step.uses = item.replica.finiteuses:GetPercent()
            end
            if not SelfAction(self.G, player, item, action) then
                self:Fail("不能这样使用" .. name .. "。"); return false
            end
            if is_heal_watch then step.watch = item end
            self:Working(kind == "eat" and ("正在吃" .. name .. "…") or ("正在处理" .. name .. "…"))
            step.sent = now
        elseif now - step.sent > .6 then
            local equipped = player.replica.inventory:GetEquippedItem(self.G.EQUIPSLOTS.HANDS)
            if kind == "unequip" then
                local body = player.replica.inventory:GetEquippedItem(self.G.EQUIPSLOTS.BODY)
                local head = player.replica.inventory:GetEquippedItem(self.G.EQUIPSLOTS.HEAD)
                if equipped == item or body == item or head == item then return true end
            elseif kind == "eat" and CountItem(player, prefab) >= step.before then
                return true
            elseif kind == "use" and item:IsValid() and item.replica.finiteuses ~= nil
                and item.replica.finiteuses:GetPercent() >= (step.uses or 0) then
                return true
            end
            self:Done("搞定！" .. name .. "已经处理好啦～"); return true
        end
        return true
    elseif kind == "give" or kind == "store" or kind == "heal" then
        local target = (kind == "give" or kind == "heal") and self.sender.entity or nil
        if kind == "store" then
            local boxprefab = Aliases.Resolve(step.box, self.G)
            if boxprefab == nil then self:Fail("我不认识“" .. tostring(step.box) .. "”这个容器。"); return false end
            target = FindEntity(self.G, player, { [boxprefab] = true }, Config.SEARCH_RADIUS)
        end
        if target == nil or not target:IsValid() then self:Fail("目标不见了。"); return false end
        if player:GetDistanceSqToInst(target) > 5 * 5 then
            if not step.announced then
                self:Working("正在前往" .. target:GetBasicDisplayName() .. "…")
                step.announced = true
            end
            if now - (step.last_move or -100) >= Config.MOVE_RETRY then
                self.move(player, target:GetPosition()); step.last_move = now
            end
            return true
        end
        if not step.sent then
            local action = player.components.playercontroller:GetItemUseAction(item, target)
            local wanted = kind == "give" and self.G.ACTIONS.GIVE
                or kind == "heal" and self.G.ACTIONS.HEAL or self.G.ACTIONS.STORE
            if action == nil or action.action ~= wanted then
                self:Fail("现在不能把" .. name .. "交给这个目标。"); return false
            end
            step.before = CountItem(player, prefab)
            self:Working("正在" .. (kind == "heal" and "治疗" or "交付") .. name .. "…")
            player.components.playercontroller:RemoteControllerUseItemOnSceneFromInvTile(action, item)
            step.sent = now
        elseif now - step.sent > .8 then
            if CountItem(player, prefab) < step.before then
                self:Done("已经把" .. name .. "交出去了。"); return true
            end
        end
        return true
    end
    self:Fail("这个动作目前不能由客户端安全执行。")
    return false
end

return Queue
