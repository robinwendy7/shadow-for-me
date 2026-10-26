-- 动作预演/原版点击回调流程参考用户自己的 zombie-maxwell-client/ActionQueue.lua。
-- 这些是正常游戏动作同步，不新增 Mod RPC，也不需要服务器 Mod。
local M={}
local Throttle=require("shadowself/control/rpc_throttle")
local function DoScene(player,target,act,isright,guard)
    if guard and not guard() then return false end
    local pc=player.components.playercontroller
    local pos=target:GetPosition();local wanted=act.action
    if not Throttle.Action(player,wanted,target,act.invobject,pos) then return false end
    if not pc.ismastersim then
        local platform,x,z=pc:GetPlatformRelativePosition(pos.x,pos.z)
        local mods=pc:EncodeControlMods()
        local sent=false
        local function send()
            if sent or guard and not guard() then return end
            sent=true
            local released=pc.locomotor~=nil or nil
            local noforce=pc.locomotor==nil and wanted.canforce or nil
            if isright then
                SendRPCToServer(RPC.RightClick,wanted.code,x,z,target,
                    act.rotation~=0 and act.rotation or nil,released,mods,noforce,wanted.mod_name,platform,platform~=nil)
            else
                SendRPCToServer(RPC.LeftClick,wanted.code,x,z,target,released,mods,noforce,wanted.mod_name,platform,platform~=nil)
            end
        end
        if pc.locomotor then act.preview_cb=send else act.non_preview_cb=send end
    end
    pc:DoAction(act)
    return true
end
function M.Attack(player,target,guard)
    if not target or not target:IsValid() or guard and not guard() then return false end
    local inv=player.replica.inventory
    return DoScene(player,target,BufferedAction(player,target,ACTIONS.ATTACK,inv:GetEquippedItem(EQUIPSLOTS.HANDS)),false,guard)
end
function M.Scene(player,target,wanted,guard)
    local pc=player.components.playercontroller
    local picker=player.components.playeractionpicker
    local pos=target:GetPosition()
    local left=picker:GetLeftClickActions(pos,target) or {}
    local right=picker:GetRightClickActions(pos,target) or {}
    local act,isright=left[1],false
    if not act or act.action~=wanted then act,isright=right[1],true end
    if not act or act.action~=wanted then return false end
    return DoScene(player,target,act,isright,guard)
end

-- 原版2033的收菜也是显式BufferedAction；不依赖鼠标当前第一候选动作。
-- 池塘收竿需要显式携带当前钓竿；不依赖鼠标第一候选动作。
function M.ReelPond(player,rod,target,guard)
    if not rod:IsValid() or not target:IsValid() or guard and not guard() then return false end
    return DoScene(player,target,BufferedAction(player,target,ACTIONS.REEL,rod),false,guard)
end

function M.HarvestCooked(player,target,guard)
    local function valid()
        return target:IsValid() and target:HasTag("donecooking") and not target:HasTag("burnt")
            and (not guard or guard())
    end
    if not valid() then return false end
    local rider=player.replica and player.replica.rider
    if rider and rider:IsRiding() then return false end
    return DoScene(player,target,BufferedAction(player,target,ACTIONS.HARVEST),false,valid)
end

-- 装备物品的地面右键动作（海钓抛竿/收线），沿用原版预演回调。
function M.Ground(player,point,wanted,guard)
    if guard and not guard() then return false end
    local pc=player.components.playercontroller
    for _,act in ipairs(player.components.playeractionpicker:GetRightClickActions(point,nil) or {}) do
        if act.action==wanted then
            if not Throttle.Action(player,wanted,nil,act.invobject,point) then return false end
            if not pc.ismastersim then
                local platform,x,z=pc:GetPlatformRelativePosition(point.x,point.z)
                local sent=false
                local function send()
                    if not sent and (not guard or guard()) then sent=true;SendRPCToServer(RPC.RightClick,wanted.code,x,z,nil,nil,true,pc:EncodeControlMods(),nil,wanted.mod_name,platform,platform~=nil) end
                end
                if pc.locomotor then act.preview_cb=send else act.non_preview_cb=send end
            end
            pc:DoAction(act);return true
        end
    end
    return false
end
-- 船套沿用原版手柄放置请求；未收到船实体不算部署成功。
function M.Deploy(player,item,point)
 local pc=player.components.playercontroller
 local ii=item.replica and item.replica.inventoryitem
 if pc:IsBusy() or not item:IsValid() or not ii or not ii:CanDeploy(point,nil,player,0) then return false end
 if not Throttle.Take(player,"item","deploy:"..tostring(item),point) then return false end
 if pc.ismastersim then pc:OnRemoteControllerActionButtonDeploy(item,point,0,true)
 else
  local platform,x,z=pc:GetPlatformRelativePosition(point.x,point.z)
  SendRPCToServer(RPC.ControllerActionButtonDeploy,item,x,z,0,true,platform,platform~=nil)
 end
 return true
end
-- 风向标必须先确认在手，再走原版右键点击；不把背包控制器静默拒绝当成已施法。
function M.CastStaff(player,item,target,guard)
 local pc=player.components.playercontroller;local inv=player.replica.inventory
 local function valid()
  return item:IsValid() and target:IsValid() and not target:HasTag("dead") and not target:HasTag("isdead")
   and inv:GetEquippedItem(EQUIPSLOTS.HANDS)==item and (not guard or guard())
 end
 if pc:IsBusy() or not valid() then return false end
 local picker=player.components.playeractionpicker
 for _,act in ipairs(picker:GetUseItemActions(target,item,true) or {}) do
  if act.action==ACTIONS.CASTSPELL then return DoScene(player,target,act,true,valid) end
 end
 return false
end
function M.UseOn(player,item,target,wanted)
    local picker=player.components.playeractionpicker;local pc=player.components.playercontroller
    for _,right in ipairs({true,false}) do
        for _,act in ipairs(picker:GetUseItemActions(target,item,right) or {}) do
            if act.action==wanted then
                if not Throttle.Action(player,wanted,target,item) then return false end
                if pc.ismastersim then pc:DoAction(act) else pc:RemoteControllerUseItemOnSceneFromInvTile(act,item) end
                return true
            end
        end
    end
    return false
end
-- 原版背包补燃料动作；预演发出前重新检查维护线程的所有权。
function M.RefuelArmor(player,fuel,armor,guard)
 local pc=player.components.playercontroller
 local function valid() return fuel:IsValid() and armor:IsValid() and (not guard or guard()) end
 if pc:IsBusy() or not valid() then return false end
 for _,right in ipairs({true,false}) do
  for _,act in ipairs(player.components.playeractionpicker:GetUseItemActions(armor,fuel,right) or {}) do
   if act.action==ACTIONS.ADDFUEL or act.action==ACTIONS.ADDWETFUEL then
    if not Throttle.Action(player,act.action,armor,fuel) then return false end
    if pc.ismastersim then pc:DoAction(act)
    else
     local sent=false
     local function send()
      if not sent and valid() then sent=true;SendRPCToServer(RPC.ControllerUseItemOnItemFromInvTile,act.action.code,armor,fuel,act.action.mod_name) end
     end
     if pc.locomotor then
      if not pc:CanLocomote() then return false end
      act.preview_cb=send;pc.locomotor:PreviewAction(act,true)
     else
      if act.action.pre_action_cb then act.action.pre_action_cb(act) end
      send()
     end
    end
    return true
   end
  end
 end
 return false
end
function M.Self(player,item,wanted)
    local pc=player.components.playercontroller
    for _,right in ipairs({true,false}) do
        for _,act in ipairs(player.components.playeractionpicker:GetInventoryActions(item,right) or {}) do
            if act.action==wanted then
                if not Throttle.Action(player,wanted,nil,item) then return false end
                if pc.ismastersim then pc:DoAction(act)
                else pc:RemoteControllerUseItemOnSelfFromInvTile(act,item) end
                return true
            end
        end
    end
    return false
end
-- 原版暗影秘典轮盘流程：选择法术 -> execute选点 -> 查询CASTAOE -> 正常点击。
function M.CastBook(player,book,point,id)
    local pc=player.components.playercontroller
    local spellbook=book.components and book.components.spellbook
    if not spellbook or pc:IsBusy() or not pc:IsEnabled() then return false end
    local inv=player.replica.inventory
    if inv:GetActiveItem() then return false end
    -- 不覆盖玩家自己正在操作的选点模式。
    if pc:IsAOETargeting() then return false end
    if not Throttle.Action(player,ACTIONS.CASTAOE,nil,book,point) then return false end
    if not spellbook:SelectSpell(id) then return false end
    local spell=spellbook.items[id]
    if not spell or not spell.execute then return false end
    spell.execute(book)
    local left,right=pc:GetGroundUseAction(point,book)
    local act=left and left.action==ACTIONS.CASTAOE and left or right and right.action==ACTIONS.CASTAOE and right
    if not act then
        if pc:IsAOETargeting() and pc:GetActiveSpellBook()==book then pc:CancelAOETargeting() end
        return false
    end
    if pc.ismastersim then pc:DoAction(act)
    else
        local platform,x,z=pc:GetPlatformRelativePosition(point.x,point.z)
        SendRPCToServer(RPC.LeftClick,ACTIONS.CASTAOE.code,x,z,nil,true,nil,nil,nil,platform,platform~=nil,book,id)
    end
    -- 已编码的法术请求不依赖本地准星；关闭自己的选点，释放正常走A输入。
    if pc:IsAOETargeting() and pc:GetActiveSpellBook()==book then pc:CancelAOETargeting() end
    return true
end
-- 参考203极速模式：直接连续提交原版移动请求，绕过逐次客户端预演忙碌锁。
-- 只操作玩家确实打开的容器；精确移动一份，避免调味站收到整组原料。
function M.TransferBatch(player,target,steps,guard)
    if guard and not guard() then return false end
    if not target:IsValid() or not target.replica.container:IsOpenedBy(player) then return false end
    if #steps<1 or #steps>4 then return false end
    for _,step in ipairs(steps) do
        if not step.inventory and (not step.inst or not step.inst:IsValid()
            or not step.source:IsOpenedBy(player)) then return false end
    end
    local host=player.components.playercontroller.ismastersim
    local key=tostring(target)
    for _,step in ipairs(steps) do key=key..":"..tostring(step.inst)..":"..tostring(step.slot) end
    if not Throttle.Take(player,"item",key) then return false end
    for _,step in ipairs(steps) do
        if host then step.source:MoveItemFromCountOfSlot(step.slot,target,1)
        elseif step.inventory then SendRPCToServer(RPC.MoveInvItemFromCountOfSlot,step.slot,target,1)
        else SendRPCToServer(RPC.MoveItemFromCountOfSlot,step.slot,step.inst,target,1) end
    end
    return true
end

function M.Move(player,point)
    if not Throttle.Move(player,point) then return false end
    local arena=player._shadowself_arena_move_owner
    if arena and arena.running and arena.instance then require("shadowself/control/arena_late_travel").Tick(player,arena.wave) end
    local pc=player.components.playercontroller
    if pc.locomotor then pc.locomotor:GoToPoint(point,nil,true)
    else
        local platform,x,z=pc:GetPlatformRelativePosition(point.x,point.z)
        SendRPCToServer(RPC.LeftClick,ACTIONS.WALKTO.code,x,z,nil,true,nil,nil,nil,platform,platform~=nil)
    end
end
function M.Stop(player)
    local pc=player.components and player.components.playercontroller
    if not pc then return end
    if pc.ClearActionHold then pc:ClearActionHold() end
    if player.ClearBufferedAction then player:ClearBufferedAction() end
    if pc.locomotor then pc.locomotor:Stop();pc.locomotor:Clear() end
    if not pc.ismastersim and Throttle.Stop(player) then
        SendRPCToServer(RPC.StopControl,CONTROL_PRIMARY)
        SendRPCToServer(RPC.StopControl,CONTROL_SECONDARY)
        SendRPCToServer(RPC.StopWalking)
        -- 无预测时 StopWalking 只清 remote_vector，不会取消点击后排队的寻路。
        -- 与手动点击脚下一样，覆盖服务器上尚未完成的移动/工作目标。
        local pos=player:GetPosition()
        local platform,x,z=pc:GetPlatformRelativePosition(pos.x,pos.z)
        SendRPCToServer(RPC.LeftClick,ACTIONS.WALKTO.code,x,z,nil,true,nil,nil,nil,platform,platform~=nil)
    end
end
function M.Items(player)
    local result={};local inv=player.replica.inventory
    if not inv then return result end
    for _,v in pairs(inv:GetItems()) do result[#result+1]=v end
    for _,v in pairs(inv:GetEquips()) do result[#result+1]=v end
    local overflow=inv:GetOverflowContainer()
    if overflow then for _,v in pairs(overflow:GetItems()) do result[#result+1]=v end end
    return result
end
function M.Count(player,prefab)
    local n=0
    for _,v in ipairs(M.Items(player)) do
        if not prefab or v.prefab==prefab then
            n=n+(v.replica.stackable and v.replica.stackable:StackSize() or 1)
        end
    end
    return n
end
return M
