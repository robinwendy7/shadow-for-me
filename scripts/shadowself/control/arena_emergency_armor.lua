-- 战斗中破甲只换真实背包备用；骨甲继续交给原有维修/护盾流程。
local M={}
function M.Best(player,slot,minimum)
 local I=require("shadowself/control/arena_inventory");local best
 for _,item in ipairs(require("shadowself/control/actions").Items(player)) do
  local eq=item.replica and item.replica.equippable
  if eq and eq:EquipSlot()==slot and item.prefab~="armorskeleton" and item:IsValid() and not item:HasTag("broken")
   and I.Condition(item)>0 and I.Protection(item)>0 and I.Protection(item)>=(minimum or 0) then
   if not best or I.Protection(item)>I.Protection(best) or I.Protection(item)==I.Protection(best) and I.Condition(item)>I.Condition(best) then best=item end
  end
 end
 return best
end
function M.Tick(c)
 if not c or not c.plan or not c.plan.arena then return false end
 local p=c.player;local inv=p.replica.inventory;local I=require("shadowself/control/arena_inventory")
 local pending=p._shadowself_armor_replacement
 if pending then
  if inv:GetEquippedItem(pending.slot)==pending.item or not pending.item:IsValid() or GetTime()>=pending.deadline then p._shadowself_armor_replacement=nil
  else c.bridge:PauseAttack();return true end
 end
 for _,slot in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
  local current=inv:GetEquippedItem(slot)
  local parasite=current and (current.prefab=="slurper" or current.prefab=="bat_boss" or current.prefab=="bat_boss_shadow")
  if not parasite and (not current or current.prefab~="armorskeleton" and (not current:IsValid() or current:HasTag("broken") or I.Condition(current)<=0)) then
   local item=M.Best(p,slot)
   if item and item~=current then
    c.bridge:PauseAttack()
    if c.gear and c.gear.protected_slots then c.gear.protected_slots[slot]=nil end
    if require("shadowself/control/actions").Self(p,item,ACTIONS.EQUIP) then p._shadowself_armor_replacement={item=item,slot=slot,deadline=GetTime()+.5} end
    return true
   end
  end
 end
 return false
end
return M
