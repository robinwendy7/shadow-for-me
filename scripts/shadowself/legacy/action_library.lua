local AIPLAYER=require("shadowself/legacy/registry")
-- 所有动作采用游戏已有动作定义与 RPC，绝不注册需要服务端安装的 ModRPC。
local ActionLibrary = Class(function(self, player, config, perception)
    self.player, self.config, self.perception = player, config, perception
    self.generation = 0
    self.has_request = false
end)

-- 统一动作可用性查询；根据 SCENE、USEITEM、EQUIPPED、INVENTORY、POINT 动态覆盖原版及模组动作。
function ActionLibrary:FindAction(name, target, item, point)
    local definition = ACTIONS[name]
    local picker = self.player.components.playeractionpicker
    if not definition or not picker then return nil end
    local inventory = self.player.replica.inventory
    local equipped = inventory and inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    for _, right in ipairs({false, true}) do
        local list = {}
        if target and target:IsValid() then
            if item then list = picker:GetUseItemActions(target, item, right)
            else
                list = picker:GetSceneActions(target, right)
                if equipped then
                    for _, act in ipairs(picker:GetEquippedItemActions(target, equipped, right)) do list[#list+1] = act end
                end
            end
        elseif point then list = picker:GetPointActions(point, item, right, nil)
        elseif item then list = picker:GetInventoryActions(item, right) end
        for _, action in ipairs(list) do
            if action.action == definition then
                action._aiplayer_right = right
                action._aiplayer_route = target and item and "useitem" or (not target and not point and item and "inventory" or "click")
                return action
            end
        end
    end
end

-- 校验地面以及整条直线路径，避免无地图信息下走进海中或跨越不可通行的地形。
function ActionLibrary:SafePoint(point)
    local map = TheWorld and TheWorld.Map
    if not map then return false end
    local boat=self.player.GetCurrentPlatform and self.player:GetCurrentPlatform()
    local function passable(x,z)
        if boat then return map.GetPlatformAtPoint and map:GetPlatformAtPoint(x,z)==boat end
        return map:IsPassableAtPoint(x,0,z) and not map:IsOceanAtPoint(x,0,z)
    end
    if not passable(point.x,point.z) then return false end
    local start = self.player:GetPosition()
    local length = math.sqrt((point.x-start.x)^2 + (point.z-start.z)^2)
    if length>64 then return false end -- 长距离任务应分段，避免单周期检查数万个未知坐标。
    for n = 1, math.max(1, math.ceil(length)) do
        local t = n / math.max(1, math.ceil(length))
        local x, z = start.x+(point.x-start.x)*t, start.z+(point.z-start.z)*t
        if not passable(x,z) then return false end
    end
    return true
end

-- WALKTO 使用原版 BufferedAction，并通过与鼠标操作一致的预测回调发送请求。
function ActionLibrary:Walk(point)
    if not self:SafePoint(point) then return nil end
    return BufferedAction(self.player, nil, ACTIONS.WALKTO, nil, point)
end

-- 根据官方 playercontroller:OnLeftClick/OnRightClick 参数发送，处理平台坐标与禁用预测模式。
function ActionLibrary:SendClick(action)
    local pc = self.player.components.playercontroller
    local point = action.target and action.target:GetPosition() or action:GetActionPoint() or self.player:GetPosition()
    local platform, x, z = pc:GetPlatformRelativePosition(point.x, point.z)
    local mods = pc:EncodeControlMods()
    local generation=self.generation
    local sent=false
    local function send()
        if sent or self.generation~=generation or not self.player:IsValid() then return end
        sent=true
        action._aiplayer_sent_at=GetTime()
        if action._aiplayer_right then
            SendRPCToServer(RPC.RightClick, action.action.code, x, z, action.target, action.rotation ~= 0 and action.rotation or nil, true, mods, action.action.canforce, action.action.mod_name, platform, platform ~= nil)
        else
            SendRPCToServer(RPC.LeftClick, action.action.code, x, z, action.target, true, mods, action.action.canforce, action.action.mod_name, platform, platform ~= nil)
        end
    end
    if pc.ismastersim then
        pc:DoAction(action)
        action._aiplayer_sent_at=GetTime()
    else
        -- 客户端只负责预览；non_preview_cb 支持关闭移动预测的玩家。
        action.preview_cb = send
        action.non_preview_cb = send
        pc:DoAction(action)
    end
end

-- 路由背包动作与使用物品动作，主机也走游戏官方控制器入口。
function ActionLibrary:Execute(action)
    if action then action._shadowself_native=true end
    local pc = self.player.components.playercontroller
    if not action or not pc or not pc:IsEnabled() or pc:IsBusy() then return false, "角色忙碌" end
    if action.target and not action.target:IsValid() then return false, "目标消失" end
    self.has_request=true
    if action._aiplayer_route == "inventory" then
        if pc.ismastersim then pc:DoAction(action)
        else pc:RemoteUseItemFromInvTile(action, action.invobject) end
    elseif action._aiplayer_route == "useitem" then
        if pc.ismastersim then pc:DoAction(action)
        else pc:RemoteControllerUseItemOnSceneFromInvTile(action, action.invobject) end
    else self:SendClick(action) end
    -- 官方背包接口在预测模式下自行创建回调，也必须在手动接管时失效。
    if action._aiplayer_route=="inventory" or action._aiplayer_route=="useitem" then
        local generation=self.generation
        local callback=action.preview_cb
        if callback then
            local fired=false
            action.preview_cb=function(...)
                if fired or self.generation~=generation or not self.player:IsValid() then return end
                fired=true; return callback(...)
            end
        end
    end
    return true
end

-- 不直接给服务器实体添加或删除组件；停止走原版停止 RPC 和本地预测清理。
function ActionLibrary:Stop()
    local pc = self.player.components.playercontroller
    self.generation=self.generation+1
    if pc and not pc.ismastersim and self.has_request then
        -- 一次统一释放按键，一次停止走路；不再追加脚下点击。
        SendRPCToServer(RPC.StopAllControls)
        SendRPCToServer(RPC.StopWalking)
        pc.remote_controls = {}
    end
    self.has_request=false
    if self.player.ClearBufferedAction then self.player:ClearBufferedAction() end
    if pc and pc.locomotor then pc.locomotor:Stop() end
    self:ReleaseActive()
end

-- POINT 类物品动作需要物品真正进入服务器同步的鼠标手持槽；先等待拿取确认再发送部署。
function ActionLibrary:PrepareActive(item)
    local inventory=self.player.replica.inventory
    local active=inventory:GetActiveItem()
    if active==item then return true end
    if active then return false,"鼠标已有其他物品，请先放回背包" end
    if self.active_item==item then return false,"等待手持物品同步" end
    for slot, candidate in pairs(inventory:GetItems()) do
        if candidate==item then
            self.active_item=item; inventory:TakeActiveItemFromAllOfSlot(slot)
            return false,"等待手持物品同步"
        end
    end
    local overflow=inventory:GetOverflowContainer()
    if overflow then
        for slot, candidate in pairs(overflow:GetItems()) do
            if candidate==item then
                self.active_item=item; overflow:TakeActiveItemFromAllOfSlot(slot)
                return false,"等待手持物品同步"
            end
        end
    end
    return false,"物品不在可拿取的背包槽"
end

-- 只归还 AI 自己拿起的物品，手动玩家接管的其他物品绝不移动。
function ActionLibrary:ReleaseActive()
    local inventory=self.player.replica.inventory
    if self.active_item and inventory and inventory:GetActiveItem()==self.active_item then inventory:ReturnActiveItem() end
    self.active_item=nil
end

-- 能学会或已解锁且有材料的配方才可排队，不能通过 CanBuild 绕过科技条件。
function ActionLibrary:CanCraft(name)
    local builder = self.player.replica.builder
    local recipe = AllRecipes[name]
    if not builder or not recipe then return false end
    return builder:IsBuildBuffered(name) or (builder:KnowsRecipe(name) and builder:HasIngredients(recipe))
end

-- 建筑先检查部署位置，物品通过制作菜单的同一接口处理。
function ActionLibrary:Craft(name, point)
    local recipe = AllRecipes[name]
    local builder = self.player.replica.builder
    if not self:CanCraft(name) or builder:IsBusy() then return false end
    if recipe.placer then
        if not point or not self:SafePoint(point) or not builder:CanBuildAtPoint(point, recipe, 0) then return false end
        builder:MakeRecipeAtPoint(recipe, point, 0)
    else builder:MakeRecipeFromMenu(recipe) end
    self.has_request=true
    return true
end

-- 对任务目标尝试当前工具；缺工具时先通过 EQUI P 动作装备匹配物品或制作基础工具。
function ActionLibrary:Work(name, target, snapshot)
    local act = self:FindAction(name, target)
    if act then return {kind="action", action=act, name=name, target=target} end
    local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if snapshot.night and hand and (hand.prefab=="torch" or hand.prefab=="lantern" or hand.prefab=="lighter") then return nil end
    for _, item in ipairs(snapshot.items) do
        if item:HasTag(name .. "_tool") then
            local equip = self:FindAction("EQUIP", nil, item)
            if equip then return {kind="action", action=equip, name="EQUIP", item=item, setup=true} end
        end
    end
    local recipes = {CHOP="axe", MINE="pickaxe", DIG="shovel"}
    if recipes[name] and self:CanCraft(recipes[name]) then return {kind="craft", recipe=recipes[name], name="制作工具", setup=true} end
end

-- 容器存取通过已有 replica 转移方法，服务器仍负责权限、容量及实际结果。
function ActionLibrary:Transfer(direction, prefab, target)
    local container = target and target.replica.container
    local inventory = self.player.replica.inventory
    if not container or not container:IsOpenedBy(self.player) then return false end
    if direction == "take" then
        for slot, item in pairs(container:GetItems()) do
            if item.prefab == prefab then self.has_request=true; container:MoveItemFromAllOfSlot(slot, self.player); return true end
        end
    else
        for slot, item in pairs(inventory:GetItems()) do
            if item.prefab == prefab then self.has_request=true; inventory:MoveItemFromAllOfSlot(slot, target); return true end
        end
        local overflow = inventory:GetOverflowContainer()
        if overflow then
            for slot, item in pairs(overflow:GetItems()) do
                if item.prefab == prefab then self.has_request=true; overflow:MoveItemFromAllOfSlot(slot, target); return true end
            end
        end
    end
    return false
end

-- 实际行动完成判据：使用与观察目标有关的变化，不把 RPC 发送成功当作动作完成。
function ActionLibrary:DropSingle(item)
    local inv=self.player.replica.inventory
    local pc=self.player.components.playercontroller
    if not item or not item:IsValid() or not inv or not inv.DropItemFromInvTile or not pc or pc:IsBusy() then return false end
    self.has_request=true;inv:DropItemFromInvTile(item,true);return true
end

function ActionLibrary:Stamp(plan, snapshot)
    local target, item = plan.target or (plan.action and plan.action.target), plan.item or (plan.action and plan.action.invobject)
    local stamp = {counts={}, targets={}, tags={}, itemtags={}, pos=snapshot.pos, hunger=snapshot.hunger, health=snapshot.health, sanity=snapshot.sanity}
    for prefab, count in pairs(snapshot.counts) do stamp.counts[prefab] = count end
    if item then
        stamp.item = item; stamp.item_prefab = item.prefab; stamp.item_count = snapshot.counts[item.prefab] or 0
        local ii=item.replica and item.replica.inventoryitem
        local used=ii and ii.classified and ii.classified.percentused
        stamp.item_used=used and used.value and used:value() or nil
        for _, tag in ipairs({"turnedon","pocketwatch_inactive","deployable","baited"}) do stamp.itemtags[tag] = item:HasTag(tag) end
    end
    if target and target:IsValid() then
        stamp.target = target
        stamp.prefab = target.prefab
        for _, tag in ipairs({"pickable","harvestable","CHOP_workable","MINE_workable","DIG_workable","burning","fire","cooking","donecooking","opened","turnedon","isdead"}) do stamp.tags[tag] = target:HasTag(tag) end
        local health = target.replica and target.replica.health
        stamp.target_health = health and health:GetPercent() or nil
    end
    if plan.recipe then
        local product = AllRecipes[plan.recipe] and AllRecipes[plan.recipe].product or plan.recipe
        stamp.product = product
        stamp.product_count = snapshot.counts[product] or 0
        for _, entity in ipairs(snapshot.entities) do if entity.prefab == product then stamp.targets[entity.GUID] = true end end
    end
    return stamp
end

-- 只用观察到的相关物品、目标标签或生命变化确认；缺少确认的动作进入有限重试并报错。
function ActionLibrary:Confirmed(plan, before, snapshot)
    if plan.kind == "wait" then return true end
    if plan.kind == "move" then return snapshot.pos:DistSq(plan.point) < 2.25 end
    if plan.kind == "craft" then
        if (snapshot.counts[before.product] or 0) > before.product_count then return true end
        for _, entity in ipairs(snapshot.entities) do if entity.prefab == before.product and not before.targets[entity.GUID] then return true end end
        return false
    end
    if plan.kind == "transfer" then return (snapshot.counts[plan.prefab] or 0) ~= (before.counts[plan.prefab] or 0) end
    local target, item = before.target, before.item
    local name = plan.name
    local inv = self.player.replica.inventory
    if name=="SING" and item and item.songdata then
        local classified=self.player.player_classified
        for _,song in ipairs(classified and classified.inspirationsongs or {})do
            if song:value()==item.songdata.battlesong_netid then return true end
        end
        return false
    elseif name=="READ" and item and before.item_used then
        local ii=item.replica and item.replica.inventoryitem
        local used=ii and ii.classified and ii.classified.percentused
        if used and used.value and used:value()<before.item_used then return true end
    end
    if name == "EQUIP" then
        for _, equipped in pairs(inv:GetEquips()) do if equipped == item then return true end end
        return false
    elseif name == "UNEQUIP" then
        for _, equipped in pairs(inv:GetEquips()) do if equipped == item then return false end end
        return true
    elseif name == "PICKUP" then
        return target and (snapshot.counts[before.prefab] or 0) > (before.counts[before.prefab] or 0)
    elseif name == "RUMMAGE" or name == "OPEN_CRAFTING" then
        return target and target:IsValid() and target.replica.container and target.replica.container:IsOpenedBy(self.player)
    elseif name == "LOOKAT" then return GetTime() - (plan.sent or GetTime()) > .5
    end
    if item and ((snapshot.counts[before.item_prefab] or 0) < before.item_count or not item:IsValid()) then return true end
    if item and item:IsValid() then
        for tag, value in pairs(before.itemtags) do if item:HasTag(tag) ~= value then return true end end
    end
    if target then
        if not target:IsValid() or target.prefab ~= before.prefab then return true end
        if name == "ATTACK" and before.target_health then
            local health = target.replica and target.replica.health
            if health and health:GetPercent() < before.target_health then return true end
        end
        for tag, value in pairs(before.tags) do if target:HasTag(tag) ~= value then return true end end
    end
    return false
end

AIPLAYER.ActionLibrary = ActionLibrary

return true
