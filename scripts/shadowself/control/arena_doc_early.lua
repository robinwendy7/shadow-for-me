-- Document tactics limited to the named arena waves. No extra action thread.
local M={}
local A=require("shadowself/control/actions")
local function wave(c) return c and c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave() end
local function live(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
function M.Armor90(arena,slot)
 local p=arena.player;local inv=p.replica.inventory
 local best=require("shadowself/control/arena_emergency_armor").Best(p,slot,.9)
 if not best then
  local I=require("shadowself/control/arena_inventory")
  for _,item in ipairs(arena.items or {}) do
   local eq=item.replica and item.replica.equippable
   if eq and eq:EquipSlot()==slot and item.prefab~="armorskeleton" and live(item) and not item:HasTag("broken") and I.Condition(item)>0 and I.Protection(item)>=.9 then
    arena.doc_armor_needed=item.prefab;arena:Loot({item},false);return false
   end
  end
  arena:Say("等待90%及以上减伤的备用装备");return false
 end
 if arena.doc_armor_needed==best.prefab then arena.doc_armor_needed=nil end
 if inv:GetEquippedItem(slot)==best then return true,best end
 arena:StopCombat()
 if GetTime()>=(arena.next_doc_armor or 0) then
  if A.Self(p,best,ACTIONS.EQUIP) then arena.next_doc_armor=GetTime()+.4 end
 end
 return false,best
end
function M.Equip(arena,name,slot)
 local item=require("shadowself/control/arena_tools").Owned({player=arena.player},name)
 if not item then arena.doc_armor_needed=name;arena:Say("等待装备 "..name)
  for _,e in ipairs(arena.items or {}) do if e.prefab==name then arena:Loot({e},false);break end end
  return false
 end
 if arena.player.replica.inventory:GetEquippedItem(slot)==item then arena.doc_armor_needed=nil;return true,item end
 arena:StopCombat()
 if GetTime()>=(arena.next_doc_armor or 0) then if A.Self(arena.player,item,ACTIONS.EQUIP) then arena.next_doc_armor=GetTime()+.4 end end
 return false,item
end
function M.Priority(arena)
 if arena.wave==5 and arena.doc_slurpers5 then
  local head=arena.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
  if head and head.prefab=="slurper" then return head end
 end
 if arena.wave~=5 or not arena.doc_slurpers5 then return end
 for _,e in ipairs(arena.enemies or {}) do if live(e) and e.prefab=="slurper" then return e end end
end
function M.Allowed(c,e)
 local a=c.player and c.player._shadowself_arena_move_owner
 local target=a and M.Priority(a)
 return not target or e and e.prefab=="slurper" or false
end
function M.Prepare(arena)
 if arena.wave==4 then
  for _,e in ipairs(arena.enemies or {}) do if e.prefab=="antlion" and live(e) then
   return not M.Equip(arena,"armormarble",EQUIPSLOTS.BODY)
  end end
 elseif arena.wave==5 then
  local turtle,slurper=false,false
  for _,e in ipairs(arena.entities or {}) do if live(e) then turtle=turtle or e.prefab=="slurtle" or e.prefab=="snurtle";slurper=slurper or e.prefab=="slurper" end end
  if turtle and slurper then arena.doc_slurpers5=true end
  if M.Priority(arena) then return not M.Equip(arena,"hambat",EQUIPSLOTS.HANDS) end
 end
 return false
end
function M.Stage11Allowed(s,e)
 if s.doc_phase=="shadow_fish" or s.doc_phase=="lunar_tank" or s.doc_phase=="shadow_boss" then
  return e~=nil and e==s.target and live(e) and not s.doc_eating
 end
end
function M.Stage11(s,entities)
 if s.route~="shadow" and s.route~="lunar" then return end
 local arena=s.arena;local p=s.player
 if s.route=="lunar" then
  local hp=p.replica.health and p.replica.health.GetCurrent and p.replica.health:GetCurrent()
  if s.doc_eating then
   local pending=s.doc_eating;local count=require("shadowself/control/actions").Count(p,pending.name)
   if count<pending.before or not pending.item:IsValid() then s.doc_eating=nil
   elseif GetTime()<pending.deadline then arena:StopCombat();return "hold" else s.doc_eating=nil end
  end
  if hp and hp<50 then
   local Food=require("shadowself/control/arena_food");local best,score
   for _,item in ipairs(A.Items(p)) do local value=Food.Health(item,p)
    if item:IsValid() and item.prefab~="sweettea" and value>0 and (not score or value>score) then best,score=item,value end
   end
   if best and not p.components.playercontroller:IsBusy() then
    arena:StopCombat()
    if A.Self(p,best,ACTIONS.EAT,function() return arena.running and arena.stage11==s and s.route=="lunar" and best:IsValid() end) then s.doc_eating={item=best,name=best.prefab,before=A.Count(p,best.prefab),deadline=GetTime()+3.5} end
    return "hold"
   end
  end
 end
 if not M.Armor90(arena,EQUIPSLOTS.HEAD) then return "hold" end
 local cleared=s:Cleared()
 if s.route=="shadow" and cleared then
  if not M.Equip(arena,"armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
  s.doc_phase="shadow_boss"
 else
  if not M.Armor90(arena,EQUIPSLOTS.BODY) then return "hold" end
  s.doc_phase=s.route=="shadow" and "shadow_fish" or "lunar_tank"
 end
 local target,dist;local marker=s.route=="shadow" and "mermguard_shadow" or "mermguard_lunar"
 if not cleared then
  for _,e in ipairs(entities or {}) do if e.prefab==marker and live(e) then local d=p:GetPosition():DistSq(e:GetPosition());if not dist or d<dist then target,dist=e,d end end end
 else target=s.boss end
 s.target=target;arena.bridge.priority_target=target
 if not target or not live(target) then arena:StopCombat();return "hold" end
 return "fight"
end
function M.Protect(c)
 if not c.gear then return end
 local arena=c.player._shadowself_arena_move_owner
 local inv=c.player.replica.inventory
 local slots={}
 if arena and arena.wave==4 then
  for _,e in ipairs(arena.enemies or {}) do if live(e) and e.prefab=="antlion" then
   local body=inv:GetEquippedItem(EQUIPSLOTS.BODY)
   if body and body.prefab=="armormarble" then slots[EQUIPSLOTS.BODY]=true end
  end end
 elseif arena and arena.wave==11 and arena.stage11 and arena.stage11.doc_phase then
  local s=arena.stage11
  for _,slot in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
   local item=inv:GetEquippedItem(slot)
   if item and (require("shadowself/control/arena_inventory").Protection(item)>=.9 or slot==EQUIPSLOTS.BODY and s.doc_phase=="shadow_boss" and item.prefab=="armorskeleton") then slots[slot]=true end
  end
 end
 c.gear.protected_slots=c.gear.protected_slots or {}
 for slot in pairs(c.gear._docearly_slots or {}) do c.gear.protected_slots[slot]=nil end
 for slot in pairs(slots) do c.gear.protected_slots[slot]=true end
 c.gear._docearly_slots=slots
 if arena and M.Priority(arena) then
  local weapon=require("shadowself/control/arena_tools").Owned(c,"hambat")
  if weapon then c.gear.forced_weapon=weapon;c.gear._doc_slurper_weapon=weapon end
 elseif c.gear._doc_slurper_weapon then
  if c.gear.forced_weapon==c.gear._doc_slurper_weapon then c.gear.forced_weapon=nil end
  c.gear._doc_slurper_weapon=nil
 end
end
function M.Continuous(c,e)
 local w=wave(c)
 if not live(e) then return false end
 local s=c.plan and c.plan.arena_stage11
 if w==11 and s then return M.Stage11Allowed(s,e) and (s.doc_phase=="shadow_fish" or s.doc_phase=="lunar_tank") or false end
 if w==4 and e.prefab=="antlion" then local body=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY);return body and body.prefab=="armormarble" or false end
 if w==5 and e.prefab=="slurper" then
  local a=c.player._shadowself_arena_move_owner;local head=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
  return a and a.doc_slurpers5 and not (head and head.prefab=="slurper") or false
 end
 if w~=1 and w~=3 and w~=5 then return false end
 if not live(e) then return false end
 if w==1 then return e.prefab=="penguin" end
 if w==3 then return c.plan.arena_clockwork_cleanup and c.plan.arena_clockwork_cleanup(e) or false end
 if w==5 and e.prefab=="prime_mate" and (e:HasTag("fire") or e:HasTag("burning")) then
  -- Let the existing pirate owner acknowledge ignition and release its torch
  -- before the continuous-output fast path is allowed to skip its Tick.
  local hunt=c.encounters and c.encounters.arena_hunts
  if hunt and hunt.pirates and hunt.pirates.torch_owner then return false end
  for _,other in ipairs(c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies or {}) do
   if live(other) and other.prefab=="powder_monkey" then return false end
  end
  return true
 end
 return false
end
-- After a wave4 dodge, approach using the attack action and its weapon. Do not let
-- the supervisor start a second cane pursuit over the native attack approach.
function M.AfterDodge(c,e)
 if wave(c)~=4 or not live(e) then return end
 c.doc_attack_approach=e
 if c.bridge then c.bridge.chasing=nil end
 if c.travel then c.travel.chasing=nil;c.travel:EndDodge(c.snapshot) end
 if c.gear then c.gear:Swap("attack",c.snapshot) end
 return e
end
function M.AttackApproach(c,e)
 if wave(c)~=4 or not live(e) or c.doc_attack_approach~=e then return false end
 if c.player:HasTag("attack") then c.doc_attack_approach=nil;return false end
 return true
end
function M.Discard(arena,item)
 return arena and arena.wave and arena.wave>=6 and item and item.prefab=="torch" or false
end
-- Call only on the crab return branch, before submitting its next walking step.
-- Wait for a real equip acknowledgement, but do not strand the player when no cane exists.
function M.ReturnCane(arena)
 if not arena or arena.wave~=8 then return false end
 local p=arena.player;local inv=p.replica.inventory;local cane
 for _,item in ipairs(A.Items(p)) do
  if item.prefab=="cane" and require("shadowself/control/arena_tools").Usable(item) then cane=item;break end
 end
 if not cane or inv:GetEquippedItem(EQUIPSLOTS.HANDS)==cane then arena.doc_return_cane=nil;return false end
 local now=GetTime();local pending=arena.doc_return_cane
 if pending and pending.item==cane and now<pending.until_time then return true end
 arena.doc_return_cane=nil
 if p.components.playercontroller:IsBusy() or p:HasTag("attack") then return false end
 if now<(arena.doc_next_return_cane or 0) then return false end
 local instance,generation=arena.instance,arena.generation
 if A.Self(p,cane,ACTIONS.EQUIP,function() return arena.running and arena.wave==8 and arena.instance==instance and arena.generation==generation end) then
  arena.doc_return_cane={item=cane,until_time=now+.7};arena.doc_next_return_cane=now+.7;return true
 end
 return false
end
return M
