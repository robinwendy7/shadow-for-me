-- 第四关麋鹿鹅/熊大缴械恢复；借用现有拾取和装备确认，不另起控制线程。
local A=require("shadowself/control/actions")
local Inventory=require("shadowself/control/arena_inventory")
local Tools=require("shadowself/control/arena_tools")
local Nav=require("shadowself/control/navigation")
local M={}
local function boss(c)
 for _,e in ipairs(c.enemies or {}) do
  local health=e.replica and e.replica.health
  if (e.prefab=="moose" or e.prefab=="bearger") and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead")
   and not (health and health.IsDead and health:IsDead()) then return e end
 end
end
local function pickup_window(c,item)
 local e=boss(c)
 return e and e.prefab=="moose" and require("shadowself/control/arena_moose").PickupSafe(c,item) or false
end
local function hand(c)
 local inv=c.player.replica and c.player.replica.inventory
 return inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
end
local function trace(c,phase)
 if c.disarm_phase~=phase then c.disarm_phase=phase;print("[ShadowSelf][disarm] phase="..phase) end
end
function M.Tick(c)
 local plan=c.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=4 or not boss(c) then
  c.disarm_item=nil;c.disarm_phase=nil;return false
 end
 local owned={};local best,score;local cane_owned=false
 for _,item in ipairs(A.Items(c.player)) do
  owned[item]=true
  if item.prefab=="cane" and Tools.Usable(item) then cane_owned=true end
  if Inventory.Weapon(item,c.player) and Tools.Usable(item) then
   local value=Inventory.Physical(item)
   if not score or value>score then best,score=item,value end
  end
 end
 if c.disarm_item and owned[c.disarm_item] then
  if c.h and c.h.shadowself_dodging and not pickup_window(c,c.disarm_item) then return false end
  trace(c,"equip_confirm")
  c.bridge:PauseAttack()
  local weapon=Inventory.Weapon(c.disarm_item,c.player) and Tools.Usable(c.disarm_item) and c.disarm_item or best
  if weapon then c.mechanisms:Equip(weapon) end
  if weapon and hand(c)==weapon and Inventory.Weapon(weapon,c.player) then
   if c.arena_tool_travel then require("shadowself/control/arena_pickup_travel").Release(c.arena_tool_travel);c.arena_tool_travel=nil end
   c.disarm_item=nil;trace(c,"recovered");return false
  end
  if weapon then return true end
  c.disarm_item=nil;trace(c,"combat_weapon_missing")
 end
 -- 熊大缴械后即使已经拿回背包，也不能把手杖/火把当作战斗装备确认。
 local enemy=boss(c)
 if enemy.prefab=="bearger" and best and not Inventory.Weapon(hand(c) or {prefab=""},c.player)
  and not (c.h and c.h.shadowself_dodging) and not (c.travel and (c.travel.dodging or c.travel.chasing))
  and not c.bridge.chasing then
  c.bridge:PauseAttack();trace(c,"equip_confirm")
  c.mechanisms:Equip(best)
  if hand(c)~=best then return true end
  trace(c,"recovered")
 end
 local floor,damage
 for _,item in ipairs(plan.arena_ground and plan.arena_ground() or {}) do
  local ii=item.replica and item.replica.inventoryitem
  if ii and not ii:IsHeld() and Tools.Usable(item) then
   if item.prefab=="cane" and not cane_owned then
    if not floor or floor.prefab~="cane" then floor,damage=item,math.huge end
   elseif Inventory.Weapon(item,c.player) then
    local value=Inventory.Physical(item)
    if (not score or value>score) and (not damage or value>damage) then floor,damage=item,value end
   end
  end
 end
 if not floor then c.disarm_item=nil;return false end
 local function safe(item)
  return Nav.Safe(c,item:GetPosition()) or pickup_window(c,item)
 end
 if c.h and c.h.shadowself_dodging and not pickup_window(c,floor) then return false end
 if Tools.Recover(c,floor.prefab,function(item)
  return c.plan==plan and plan.arena_wave()==4 and boss(c) and item==floor
 end,safe) then
  c.disarm_item=floor;trace(c,"pickup_weapon");return true
 end
 if not best then
  c.bridge:PauseAttack();trace(c,"clear_pickup_danger")
  if not c.player.components.playercontroller:IsBusy() then
   local point=Nav.Escape(c,c.player:GetPosition())
   if point then c.travel:BeginDodge(c.snapshot);c:Move(point,"麋鹿鹅 · 先拉开危险区，再补捡缴械武器") end
  end
  return true
 end
 return false
end
return M
