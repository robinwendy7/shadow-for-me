local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local M={}
function M.Usable(item)
 if not item or not item:IsValid() or item:HasTag("broken") then return false end
 local uses=item.components and item.components.finiteuses
 if uses and uses.GetUses and uses:GetUses()<=0 then return false end
 local ii=item.replica and item.replica.inventoryitem
 local net=ii and ii.classified and ii.classified.percentused
 return not net or net:value()~=0
end
function M.Owned(c,name)
 for _,item in ipairs(A.Items(c.player)) do if item.prefab==name and M.Usable(item) then return item end end
end
function M.Recover(c,name,permit,safety)
 local Travel=require("shadowself/control/arena_pickup_travel")
 if c.arena_tool_travel then
  local state=c.arena_tool_travel;local held=false
  for _,item in ipairs(A.Items(c.player)) do if item==state.target then held=true;break end end
  if held or not state.target:IsValid() or state.target.prefab~=name then Travel.Release(state);c.arena_tool_travel=nil end
 end
 if not c.plan or not c.plan.arena_ground or M.Owned(c,name) then return false end
 local Policy=require("shadowself/control/arena_policy")
 if c.plan.arena and not Policy.PickupAllowed({prefab=name},c.plan.arena_wave and c.plan.arena_wave() or 1,c.player) then return false end
 local best,dist;local p=c.player:GetPosition()
 for _,item in ipairs(c.plan.arena_ground()) do
  local ii=item.replica and item.replica.inventoryitem
  if item.prefab==name and M.Usable(item) and (not c.plan.arena or Policy.PickupAllowed(item,c.plan.arena_wave and c.plan.arena_wave() or 1,c.player)) and ii and not ii:IsHeld() and (not permit or permit(item)) and (safety and safety(item) or not safety and Nav.Safe(c,item:GetPosition())) then
   local d=p:DistSq(item:GetPosition());if not dist or d<dist then best,dist=item,d end
  end
 end
 if not best then if c.arena_tool_travel then Travel.Release(c.arena_tool_travel);c.arena_tool_travel=nil end;return false end
 c.arena_tool_retry=c.arena_tool_retry or {}
 c.bridge:PauseAttack()
 if c.player.components.playercontroller:IsBusy() or GetTime()<(c.arena_tool_retry[name] or 0) then return true end
 local inv=c.player.replica.inventory;local bag=A.Items(c.player);local spent
 for _,item in ipairs(bag) do if item.prefab==name and not M.Usable(item) then spent=item;break end end
 local used=0;for _ in pairs(inv:GetItems() or {}) do used=used+1 end
 if spent then
  inv:DropItemFromInvTile(spent,false);c.arena_tool_retry[name]=GetTime()+.5;return true
 end
 if used>=(inv.GetNumSlots and inv:GetNumSlots() or 15) then
  local old=require("shadowself/control/arena_inventory").Discard(bag,c.player,c.plan.arena_wave and c.plan.arena_wave() or 1,best)
  if not old then return false end
  inv:DropItemFromInvTile(old,false);c.arena_tool_retry[name]=GetTime()+.5;return true
 end
 local wave=c.plan.arena_wave and c.plan.arena_wave() or 1
 if wave>=3 then
  if c.arena_tool_travel and c.arena_tool_travel.target~=best then Travel.Release(c.arena_tool_travel);c.arena_tool_travel=nil end
  c.arena_tool_travel=c.arena_tool_travel or {target=best}
  if not Travel.Ready(c.arena_tool_travel,c.player,wave,best,c) then return true end
 end
 if A.Scene(c.player,best,ACTIONS.PICKUP,function() return M.Usable(best) and not best.replica.inventoryitem:IsHeld()
  and (not c.plan.arena or Policy.PickupAllowed(best,c.plan.arena_wave and c.plan.arena_wave() or 1,c.player)) and (not permit or permit(best))
  and (not safety or safety(best)) end) then
  c.arena_tool_retry[name]=GetTime()+1;return true
 end
 return false -- 没有可执行的拾取动作，不能永久占用战斗支持阶段。
end
return M
