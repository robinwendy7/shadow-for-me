-- 冒险猪币测向和旺达裂隙表：只使用客户端可见实体及原版背包动作。
local Tools = {}
Tools.__index = Tools
local Config = require("shadowself/zom/Config")

local grades = { "旅者", "专家", "大师", "传奇" }
local sectors = Config.ADVENTURE_SECTORS

function Tools.Sector(x, z)
    local best, distance = nil, math.huge
    for i, p in ipairs(sectors) do
        local d = (x - p[1]) ^ 2 + (z - p[2]) ^ 2
        if d < distance then best, distance = i, d end
    end
    return best
end

function Tools.Intersect(a, b)
    local cross = a.dx * b.dz - a.dz * b.dx
    if math.abs(cross) < Config.PIG_COIN_MIN_CROSS then
        return nil, "两条测线太接近平行，请走远些再投。"
    end
    local ox, oz = b.x - a.x, b.z - a.z
    local t = (ox * b.dz - oz * b.dx) / cross
    local u = (ox * a.dz - oz * a.dx) / cross
    if t < 0 or u < 0 then return nil, "箭头没有在前方相交，请重新测量。" end
    return a.x + t * a.dx, a.z + t * a.dz
end

local function Inv(player)
    return player ~= nil and player.replica ~= nil and player.replica.inventory or nil
end

local function Pack(player)
    local inv = Inv(player)
    if inv == nil then return nil end
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then return overflow end
    local back = inv:GetEquippedItem(_G.EQUIPSLOTS.BACK)
    return back ~= nil and back.replica ~= nil and back.replica.container or nil
end

local function Charge(item)
    local c = item.replica ~= nil and item.replica.inventoryitem ~= nil
        and item.replica.inventoryitem.classified or nil
    if c == nil or c.recharge == nil or c.rechargetime == nil then return 0 end
    local pct = math.min(1, (c._recharge or c.recharge:value()) / 180)
    return math.ceil(math.max(0, 1 - pct) * math.max(0, c.rechargetime:value()))
end

function Tools.new(G, reply, move, stop, result)
    return setmetatable({ G = G, reply = reply, result = result or reply, move = move, stop = stop,
        search = nil, watch = nil, revive = nil }, Tools)
end

function Tools:IsActive()
    return self.search ~= nil or self.watch ~= nil or self.revive ~= nil
end

local function EndSearch(self)
    local search = self.search
    self.search = nil
    -- 只撤销本任务临时打开的延迟补偿，保留玩家原本的移动设置。
    local player = search ~= nil and search.player or nil
    if search ~= nil and search.enabled_prediction
        and player ~= nil and player:IsValid() then
        player:EnableMovementPrediction(false)
    end
end

function Tools:Cancel(player)
    if player ~= nil then self.stop(player) end
    EndSearch(self)
    self.watch, self.revive = nil, nil
end

local function ReviveWatch(player)
    local inv = Inv(player)
    if inv == nil then return end
    local candidates = { inv }
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then candidates[#candidates + 1] = overflow end
    local cooling
    for _, container in ipairs(candidates) do
        for _, item in pairs(container:GetItems()) do
            if item ~= nil and item.prefab == "pocketwatch_revive" then
                if item:HasTag("pocketwatch_inactive") then return item, 0 end
                cooling = math.min(cooling or math.huge, Charge(item))
            end
        end
    end
    return nil, cooling
end

function Tools:StartRevive(player, sender, now, target, target_name)
    if not player:HasTag("pocketwatchcaster") then
        return false, "只有旺达能使用第二次机会表救人。"
    end
    local ghost = target or sender.entity
    if ghost == nil or not ghost:IsValid() or ghost.userid == nil
        or target == nil and ghost.userid ~= sender.userid then
        return false, "我看不到你的灵魂；请在同一世界、客户端加载范围内呼救。"
    end
    if not ghost:HasTag("playerghost") or ghost:HasTag("reviving") then
        return false, (target_name or "你") .. "现在不是可复活的灵魂。"
    end
    local watch, cooldown = ReviveWatch(player)
    if watch == nil then
        return false, cooldown ~= nil and cooldown > 0
            and ("第二次机会表还在冷却，约" .. cooldown .. "秒。")
            or "身上没有可用的第二次机会表。"
    end
    self:Cancel(player)
    self.revive = { ghost = ghost, userid = ghost.userid, sender = sender,
        name = target_name or sender.name or "你",
        started = now, last_move = -100 }
    return true, "收到！正在赶去用第二次机会表复活" .. self.revive.name .. "。"
end

local function Coin(player, grade)
    local inv = Inv(player)
    if inv == nil then return nil end
    local containers = { inv }
    local back = inv:GetEquippedItem(_G.EQUIPSLOTS.BACK)
    if back ~= nil and back.replica ~= nil and back.replica.container ~= nil then
        containers[#containers + 1] = back.replica.container
    end
    for _, container in ipairs(containers) do
        for i = 1, container:GetNumSlots() do
            local item = container:GetItemInSlot(i)
            if item ~= nil and item.prefab == "pig_coin" then
                local count = item.replica.stackable ~= nil and item.replica.stackable:StackSize() or 1
                if grade == nil or count == grade or grade == 4 and count >= 4 then
                    return item, math.min(4, count)
                end
            end
        end
    end
end

local function SplitSlots(player, grade)
    if grade == 4 then return end
    local inv = Inv(player)
    if inv == nil then return end
    local source, empty
    for i = 1, inv:GetNumSlots() do
        local item = inv:GetItemInSlot(i)
        if item == nil and empty == nil then empty = i end
        if item ~= nil and item.prefab == "pig_coin" and item.replica.stackable ~= nil
            and item.replica.stackable:StackSize() > grade then source = i end
    end
    return source, empty
end

function Tools:CanSearchGrade(player, grade)
    if Coin(player, grade) ~= nil then return true end
    local inv = Inv(player)
    local source, empty = SplitSlots(player, grade)
    return inv ~= nil and inv.classified ~= nil and inv:GetActiveItem() == nil
        and source ~= nil and empty ~= nil
end

local function Markers(G, player)
    local x, _, z = player.Transform:GetWorldPosition()
    local result = {}
    for _, ent in ipairs(G.TheSim:FindEntities(x, 0, z, 6, nil, { "INLIMBO" })) do
        if ent.prefab == "archive_resonator_base" then result[ent.GUID] = ent end
    end
    return result
end

local function Ray(ent)
    local x, _, z = ent.Transform:GetWorldPosition()
    -- 冒险服务端把指向 Boss 的角度设为 angle+90；DST 地面 Z 轴方向需取负 sin。
    local rad = math.rad(ent.Transform:GetRotation() + 90)
    return { x = x, z = z, dx = math.cos(rad), dz = -math.sin(rad) }
end

local function MovePoint(G, player, ray)
    local x, _, z = player.Transform:GetWorldPosition()
    for _, dist in ipairs(Config.PIG_COIN_BASELINES) do
        for _, side in ipairs({ 1, -1 }) do
            local px, pz = x - ray.dz * dist * side, z + ray.dx * dist * side
            local clear = true
            for step = 5, dist, 5 do
                if not G.TheWorld.Map:IsPassableAtPoint(
                    x - ray.dz * step * side, 0, z + ray.dx * step * side) then
                    clear = false; break
                end
            end
            if clear and G.TheWorld.Map:IsPassableAtPoint(px, 0, pz) then
                return G.Vector3(px, 0, pz)
            end
        end
    end
end

function Tools:StartSearch(player, sender, grade, now)
    if grade == nil then
        local _, detected = Coin(player)
        if detected == nil then return false, "身上没有猪币，没法定位Boss。" end
        grade = detected
    end
    if grade == nil or grade < 1 or grade > 4 then
        return false, "请说找旅者、专家、大师或传奇Boss。"
    end
    local source, empty = SplitSlots(player, grade)
    if Coin(player, grade) == nil and (Inv(player):GetActiveItem() ~= nil
        or Inv(player).classified == nil) then
        return false, "要拆出指定枚数猪币，请先放下鼠标上的物品；当前客户端无法自动拆叠时请手动准备。"
    end
    if Coin(player, grade) == nil and (source == nil or empty == nil) then
        return false, "身上没有对应的猪币堆叠：" .. grades[grade]
            .. "需要" .. grade .. (grade == 4 and "枚或更多。" or "枚；或留一个空格让我拆币。")
    end
    self:Cancel(player)
    self.search = { grade = grade, sender = sender, started = now,
        phase = Coin(player, grade) ~= nil and "cast" or "prepare", index = 1,
        source = source, empty = empty, rays = {}, player = player }
    if player.EnableMovementPrediction ~= nil and player.components.locomotor == nil then
        player:EnableMovementPrediction(true)
        self.search.enabled_prediction = true
    end
    return true, "开始用" .. grades[grade] .. "猪币测向；第一次投币后横移约1码，再投第二次。"
end

function Tools:StartWatch(player, sender, sector, now)
    if sector == nil or sector < 1 or sector > 10 then return false, "板块编号只支持1到10。" end
    if not player:HasTag("pocketwatchcaster") then return false, "这项裂隙表能力需要旺达。" end
    if Pack(player) == nil then return false, "没有可访问的背包栏，无法读取第" .. sector .. "格。" end
    if self.search ~= nil then self.stop(player); EndSearch(self) end
    self.watch = { sector = sector, sender = sender, started = now, phase = "check" }
    return true, "正在检查背包第" .. sector .. "格的裂隙表。"
end

function Tools:Update(player, now, wanda_mode)
    local rescue = self.revive
    if rescue ~= nil then
        local ghost = rescue.ghost
        if rescue.sent ~= nil then
            if ghost:IsValid() and not ghost:HasTag("playerghost") then
                self.result(rescue.sender, "第二次机会表已生效，" .. rescue.name .. "复活了！")
                self.revive = nil
            elseif not ghost:IsValid() then
                self.result(rescue.sender, "复活请求已发出；" .. rescue.name .. "的灵魂离开了当前世界，请确认结果。")
                self.revive = nil
            elseif now - rescue.sent > 8 then
                self.result(rescue.sender, "第二次机会表没有确认复活成功，请检查游戏状态。")
                self.revive = nil
            end
            return true
        end
        if now - rescue.started > 45 or not ghost:IsValid()
            or ghost.userid ~= rescue.userid or not ghost:HasTag("playerghost") then
            self.result(rescue.sender, "呼救目标已消失或赶路超时，救援停止。")
            self:Cancel(player)
            return true
        end
        if player:GetDistanceSqToInst(ghost) > 4.5 ^ 2 then
            if now - rescue.last_move > 1 then
                self.move(player, ghost:GetPosition()); rescue.last_move = now
            end
            return true
        end
        local watch = ReviveWatch(player)
        if watch == nil then
            self.result(rescue.sender, "赶到后第二次机会表已不可用，没法施放。")
            self:Cancel(player)
            return true
        end
        local controller = player.components.playercontroller
        local action = controller:GetItemUseAction(watch, ghost)
        if action == nil or action.action ~= self.G.ACTIONS.CAST_POCKETWATCH
            or action.target ~= ghost or action.invobject ~= watch then
            self.result(rescue.sender, "原版动作无法对" .. rescue.name .. "的灵魂施放第二次机会表。")
            self:Cancel(player)
            return true
        end
        self.stop(player)
        if controller.ismastersim then controller:DoAction(action)
        else controller:RemoteControllerUseItemOnSceneFromInvTile(action, watch) end
        rescue.sent = now
        return true
    end
    local s = self.search
    if s ~= nil then
        if now - s.started > 120 then
            self.result(s.sender, "猪币测向超时，已停止。"); self:Cancel(player); return true
        end
        if s.phase == "prepare" then
            local inv = Inv(player)
            if Coin(player, s.grade) ~= nil then s.phase = "cast"; return true end
            if inv:GetActiveItem() == nil and s.preparing == nil then
                inv.classified:TakeActiveItemFromCountOfSlot(s.source, s.grade)
                s.preparing, s.prepared_at = "take", now
            elseif s.preparing == "take" and inv:GetActiveItem() ~= nil then
                inv:PutAllOfActiveItemInSlot(s.empty)
                s.preparing = "put"
            elseif s.preparing == "put" and now - s.prepared_at > 3 then
                self.result(s.sender, "猪币拆叠没成功，请手动叠成" .. s.grade .. "枚。")
                self:Cancel(player)
            end
            return true
        elseif s.phase == "cast" then
            local coin = Coin(player, s.grade)
            if coin == nil then
                self.result(s.sender, "猪币堆叠数变了，请重新准备对应等级。"); self:Cancel(player); return true
            end
            s.before = Markers(self.G, player)
            Inv(player):UseItemFromInvTile(coin)
            s.cast_at, s.phase = now, "marker"
            return true
        elseif s.phase == "marker" then
            for guid, ent in pairs(Markers(self.G, player)) do
                if s.before[guid] == nil then
                    s.rays[s.index] = Ray(ent)
                    if s.index == 1 then
                        s.destination = MovePoint(self.G, player, s.rays[1])
                        if s.destination == nil then
                            self.result(s.sender, "附近没有安全的第二测量点。"); self:Cancel(player)
                        else
                            s.move_origin = player:GetPosition()
                            s.phase = "move"
                            self.reply(s.sender, "第一条方向已记下，正横移约1码后投第二次。")
                        end
                    else
                        local x, z = Tools.Intersect(s.rays[1], s.rays[2])
                        if x == nil then
                            self.result(s.sender, z); self:Cancel(player)
                        else
                            local sector = Tools.Sector(x, z)
                            self.stop(player)
                            EndSearch(self)
                            self.result(s.sender, string.format("%sBoss预计在%d号板块附近（约 %.0f, %.0f）。",
                                grades[s.grade], sector, x, z))
                            self.result(s.sender,string.format("%sBoss预计在%d号板块附近。", grades[s.grade], sector))
                            if wanda_mode and player:HasTag("pocketwatchcaster") then
                                local ok, msg = self:StartWatch(player, s.sender, sector, now)
                                if ok then self.reply(s.sender, msg) end
                            end
                        end
                    end
                    return true
                end
            end
            if now - s.cast_at > 3 then
                self.result(s.sender, "投币后没看到新箭头；可能附近没有该等级Boss。")
                self:Cancel(player)
            end
            return true
        elseif s.phase == "move" then
            -- 必须真的离开第一次投币点，不能只因目标点接近就提前投第二次。
            if player:GetDistanceSqToPoint(s.move_origin:Get()) >= .75 ^ 2 then
                self.stop(player); s.index, s.phase = 2, "cast"
            elseif now - (s.last_move or -100) > 1 then
                self.move(player, s.destination); s.last_move = now
            end
            return true
        end
    end
    local w = self.watch
    if w == nil then return false end
    if w.phase == "converted" then
        local bag_now = Pack(player)
        local current = bag_now ~= nil and bag_now:GetItemInSlot(w.sector) or nil
        if current ~= nil and current.prefab == "pocketwatch_portal" then
            w.phase = "check" -- 只以服务端同步后的新表确认成功。
        elseif now - w.changed > 8 then
            self.result(w.sender, "紫宝石未能插入溯源表，请检查背包是否打开、人物是否忙碌。")
            self.watch = nil
            return true
        elseif Inv(player):GetActiveItem() ~= nil and now - w.last_give > .8
            and (w.give_count or 0) < 4 then
            w.phase = "gem_active" -- 第一次请求可能被原版背包忙碌状态忽略，重试。
        else
            return true
        end
    end
    local inv = Inv(player)
    local bag = Pack(player)
    local item = bag ~= nil and bag:GetItemInSlot(w.sector) or nil
    if item == nil or item.prefab ~= "pocketwatch_portal" and item.prefab ~= "pocketwatch_recall" then
        self.result(w.sender, "背包第" .. w.sector .. "格没有裂隙表或溯源表。")
        self.watch = nil; return true
    end
    if item.prefab == "pocketwatch_recall" then
        if item:HasTag("recall_unmarked") then
            self.result(w.sender, "第" .. w.sector .. "格的溯源表还没记录目的地，不能当板块裂隙表使用。")
            self.watch = nil; return true
        end
        local gem = inv:GetActiveItem()
        if gem ~= nil and gem.prefab ~= "purplegem" then
            self.result(w.sender, "鼠标上拿着别的东西，请先放回背包。")
            self.watch = nil
            return true
        end
        if gem == nil then
            if w.phase == "gem_active" then
                if now - w.changed > 3 then
                    self.result(w.sender, "紫宝石没有成功拿起，请手动检查背包。")
                    self.watch = nil
                end
                return true
            end
            local holder, gemslot
            for _, container in ipairs({ inv, bag }) do
                for i = 1, container:GetNumSlots() do
                    local candidate = container:GetItemInSlot(i)
                    if candidate ~= nil and candidate.prefab == "purplegem" then
                        holder, gemslot = container, i
                        break
                    end
                end
                if holder ~= nil then break end
            end
            if holder == nil then
                if w.phase ~= "wait_gem" then
                    self.result(w.sender, "已经没有紫宝石了；拿到后我会继续激活第" .. w.sector .. "格。")
                end
                w.phase = "wait_gem"
                return true
            end
            -- 主物品栏和背包栏使用各自的取物接口，只取一颗紫宝石。
            if holder == inv then
                if inv.classified ~= nil then
                    inv.classified:TakeActiveItemFromCountOfSlot(gemslot, 1)
                else
                    self.result(w.sender, "当前无法从物品栏拿起紫宝石。")
                    self.watch = nil
                    return true
                end
            else
                holder:TakeActiveItemFromCountOfSlot(gemslot, 1)
            end
            w.phase, w.changed = "gem_active", now
            return true
        end
        -- 取出宝石后 inventory_classified 会短暂忙碌；此时给予接口会静默忽略请求。
        local controller = player.components.playercontroller
        if inv.classified ~= nil and inv.classified._busy
            or player:HasTag("busy")
            or player.sg ~= nil and player.sg:HasStateTag("busy")
            or controller:IsBusy() then
            if now - w.changed > 8 then
                self.result(w.sender, "物品栏一直忙碌，紫宝石没有插入溯源表。")
                self.watch = nil
            end
            return true
        end
        -- 原版溯源表是 trader；紫宝石对它的动作必须是 GIVE。
        local action = controller:GetItemUseAction(gem, item)
        if action == nil or action.action ~= self.G.ACTIONS.GIVE then
            if now - w.changed > 5 then
                self.result(w.sender, "紫宝石无法给予背包里的溯源表，请检查背包是否可访问。")
                self.watch = nil
            end
            return true
        end
        inv:ControllerUseItemOnItemFromInvTile(item, gem)
        w.phase, w.changed = "converted", w.give_count == nil and now or w.changed
        w.last_give, w.give_count = now, (w.give_count or 0) + 1
        return true
    end
    local cooldown = Charge(item)
    if cooldown > 0 then
        self.result(w.sender, "第" .. w.sector .. "格的表仍在冷却，约" .. cooldown .. "秒。")
        self.watch = nil; return true
    end
    if not item:HasTag("pocketwatch_inactive") then
        self.result(w.sender, "第" .. w.sector .. "格暂时不能施放裂隙表。")
        self.watch = nil; return true
    end
    inv:UseItemFromInvTile(item)
    self.result(w.sender, "已施放第" .. w.sector .. "格裂隙表，等时空洞生成后由自动跳洞接管。")
    self.watch = nil
    return true
end

return Tools
