-- 沿用拾取调用者的调度；真实装备确认后才发送走向物品的动作。
local M={}
function M.Release(state)
 if state.pickup_gear and state.pickup_gear.support_hand==state.pickup_hand then state.pickup_gear.support_hand=nil end
 state.pickup_gear=nil;state.pickup_hand=nil;state.pickup_target=nil;state.cane_retry=nil
end
function M.Ready(state,player,wave,target,c)
 if not wave or wave<3 then M.Release(state);return true end
 if state.pickup_target and state.pickup_target~=target then M.Release(state) end
 state.pickup_target=target
 local A=require("shadowself/control/actions");local cane
 for _,item in ipairs(A.Items(player)) do
  if item.prefab=="cane" and require("shadowself/control/arena_tools").Usable(item) then cane=item;break end
 end
 if not cane then M.Release(state);return true end
 if c and c.gear then
  if c.gear.support_hand and c.gear.support_hand~=state.pickup_hand then return false end
  if not state.pickup_hand then
   local start_wave=wave
   state.pickup_hand={item=cane,valid=function()
    if not target:IsValid() or c.plan.arena_wave()~=start_wave then return false end
    for _,item in ipairs(require("shadowself/control/actions").Items(player)) do if item==target then return false end end
    return true
   end}
   state.pickup_gear=c.gear;c.gear.support_hand=state.pickup_hand
  end
 end
 if player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==cane then state.cane_retry=nil;return true end
 if player.components.playercontroller:IsBusy() or GetTime()<(state.cane_retry or 0) then return false end
 if A.Self(player,cane,ACTIONS.EQUIP) then state.cane_retry=GetTime()+1.2 else state.cane_retry=GetTime()+.3 end
 return false
end
return M
