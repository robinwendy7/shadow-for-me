-- 卸下套头啜食者并等待真实落地；借用现有监督循环，不启动第二套战斗线程。
local M={}
function M.Nearest(c,pool,accept,preferred)
 if not c.plan or not c.plan.arena then return end
 local p=c.player:GetPosition();local best,distance
 for key,value in pairs(pool or c.enemies or {}) do
  local e=type(key)=="table" and key or value
  if e and e.prefab=="slurper" and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead")
   and not e:HasTag("INLIMBO") and not e:HasTag("notarget") and not e:HasTag("NOCLICK") then
   local h=e.replica and e.replica.health;local ii=e.replica and e.replica.inventoryitem
   if not (h and h.IsDead and h:IsDead()) and not (ii and ii.IsHeld and ii:IsHeld())
    and (not c.bridge.allowed or c.bridge.allowed(e)) and (not accept or accept(e)) then
    local d=p:DistSq(e:GetPosition())
    if not distance or d<distance-.001 or math.abs(d-distance)<=.001 and e==preferred then best,distance=e,d end
   end
  end
 end
 return best
end
function M.Tick(c)
 if not c.plan or not c.plan.arena then return false end
 local p=c.player;local inv=p.replica.inventory
 if not inv or not inv.GetEquippedItem then return false end
 local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD);local state=c.slurper_detach
 if head and head.prefab=="slurper" then
  if not state or state.item~=head then
   state={item=head};c.slurper_detach=state
   c.bridge:PauseAttack()
   if c.h then c.h.guid=0;c.h.shadowself_dodging=nil end
   if c.gear then c.gear.pending=nil;c.gear.next_request=GetTime() end
   if c.healing then c.healing:Interrupt(c) end
  end
  c.bridge:PauseAttack();c.status="啜食者 · 卸下套头目标，等待服务器确认"
  if not p.components.playercontroller:IsBusy() and GetTime()>=(state.next_drop or 0) then
   inv:DropItemFromInvTile(head,false);state.next_drop=GetTime()+.5
  end
  return true
 end
 if not state then return false end
 c.bridge:PauseAttack()
 local item=state.item
 local ii=item:IsValid() and item.replica and item.replica.inventoryitem
 if item:IsValid() and (item:HasTag("INLIMBO") or ii and ii:IsHeld()) then
  if not p.components.playercontroller:IsBusy() and GetTime()>=(state.next_drop or 0) then
   inv:DropItemFromInvTile(item,false);state.next_drop=GetTime()+.5
  end
  return true
 end
 c.slurper_detach=nil
 if c.h then c.h.guid=0;c.h.shadowself_dodging=nil end
 if c.gear then
  c.gear.pending=nil;c.gear.next_request=GetTime()
  if c.gear.protected_slots then c.gear.protected_slots[EQUIPSLOTS.HEAD]=nil end
 end
 if c.travel and c.travel.EndDodge then c.travel:EndDodge(c.snapshot) end
 local pack=c.arena_snailpack
 if item:IsValid() and not item:HasTag("dead") and not item:HasTag("isdead") then
  local pool={item};for _,e in ipairs(c.enemies or {}) do pool[#pool+1]=e end
  local target=M.Nearest(c,pool)
  c.bridge.priority_target=target;c.bridge.resume_target=target
  if pack and pack.active then pack.target=target;pack.phase="bait";pack.bait_seen=nil;pack.standing=nil end
 end
 c.status="啜食者 · 已卸下，恢复近战索敌"
 return false
end
return M
