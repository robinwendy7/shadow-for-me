-- 角斗场蝙蝠王：解除套头优先，普通武器反击；原版SGbat共用，但套头是hair_attack。
local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local B={}
local function scoped(c)
 local p=c.plan;local w=p and p.arena_wave and p.arena_wave()
 return p and p.arena and (w==6 or w==7 or w==13 and p.arena_route=="shadow")
end
local function king(e) return e and (e.prefab=="bat_boss" or e.prefab=="bat_boss_shadow") end
local function live(e)
 local h=e.replica and e.replica.health
 return e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
function B.Active(c)
 if not scoped(c) then return false end
 if c.bat_scene then return true end
 local inv=c.player.replica and c.player.replica.inventory
 local head=inv and inv.GetEquippedItem and inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 if king(head) then c.bat_scene=true;return true end
 local roster=c.plan.arena_entities and c.plan.arena_entities() or c.enemies or {}
 for _,e in ipairs(roster) do if king(e) and live(e) then c.bat_scene=true;return true end end
 return false
end
function B.Detach(c)
 if not B.Active(c) then return false end
 local p=c.player;local inv=p.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD);local s=c.bat_detach
 if king(head) then
  if not s or s.item~=head then
   s={item=head};c.bat_detach=s;print("[ShadowSelf][bat] phase=detach")
   if c.h then c.h.guid=0;c.h.shadowself_dodging=nil end
   if c.gear then c.gear.pending=nil;c.gear.protected_slots=nil end
   if c.arena_wind then c.arena_wind:Stop() end
   if c.healing then c.healing:Interrupt(c) end
  end
  c.bridge:PauseAttack();c.status="蝙蝠王 · 先卸下套头目标"
  if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_drop or 0) then inv:DropItemFromInvTile(head,false);s.next_drop=GetTime()+.35 end
  return true
 end
 if not s then return false end
 local e=s.item;local ii=e.replica and e.replica.inventoryitem
 if e:IsValid() and (e:HasTag("INLIMBO") or ii and ii:IsHeld()) then
  c.bridge:PauseAttack();c.status="蝙蝠王 · 等待实际落地"
  if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_drop or 0) then inv:DropItemFromInvTile(e,false);s.next_drop=GetTime()+.35 end
  return true
 end
 if not s.ground then
  s.ground=true;s.gear_until=GetTime()+2
  if c.travel then c.travel:EndDodge(c.snapshot) end
  if e:IsValid() and live(e) then c.bridge.priority_target=e;c.bridge.resume_target=e end
  print("[ShadowSelf][bat] phase=ground_confirmed")
 end
 -- 套头会挤掉原头盔；只取真实头部护甲，不能把活的蝙蝠王当成装备。
 if not head and GetTime()<s.gear_until then
  local best,score
  for _,item in ipairs(A.Items(p)) do
   local eq=item.replica and item.replica.equippable
   local value=eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and require("shadowself/control/arena_policy").ArmorScore(item,EQUIPSLOTS.HEAD,c.enemies or {})
   if item:IsValid() and value and require("shadowself/control/arena_inventory").Condition(item)>0 and (not score or value>score) then best,score=item,value end
  end
  if best then
   c.bridge:PauseAttack();c.status="蝙蝠王 · 恢复实际头盔后反击"
   if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_equip or 0) then A.Self(p,best,ACTIONS.EQUIP);s.next_equip=GetTime()+.4 end
   return true
  end
 end
 c.bat_detach=nil
 if c.travel then c.travel:EndDodge(c.snapshot) end
 if e:IsValid() and live(e) then c.bridge.priority_target=e;c.bridge.resume_target=e end
 return false
end
function B.Tick(boss,target)
 local c=boss.c
 if not B.Active(c) then return end
 if c.arena_wind then c.arena_wind:Stop() end
 local picked;local roster=c.plan.arena_entities and c.plan.arena_entities() or c.enemies or {}
 for _,e in ipairs(roster) do if king(e) and live(e) and not e:HasTag("INLIMBO") and c.bridge.allowed(e) then picked=e;break end end
 if picked then boss:Release();return "attack",boss:Select(picked) end
 if target and target.prefab=="bat" then boss:Release();return "attack",target end
end
function B.Dodge(c,e,base)
 if not scoped(c) or not king(e) then return base end
 local a=e.AnimState;if not a then return base end
 local name=a:IsCurrentAnimation("hair_attack") and "hair_attack" or a:IsCurrentAnimation("hair_attack_fail") and "hair_attack_fail" or a:IsCurrentAnimation("atk") and "atk"
 if not name then c.bat_dodge=nil;return false end
 local f=a:GetCurrentAnimationFrame()
 if name=="atk" and f>=12 or name=="hair_attack_fail" and f>=6 then return false end
 local s=c.bat_dodge
 if not s or s.target~=e or s.name~=name or f<(s.frame or 0) then
  s={target=e,name=name};c.bat_dodge=s
  local ep=e:GetPosition();local pp=c.player:GetPosition();local rot=e.Transform:GetRotation()*math.pi/180
  s.side=((pp.x-ep.x)*math.sin(rot)+(pp.z-ep.z)*math.cos(rot))<0 and -1 or 1
 end
 s.frame=f
 return {atkanim=name,point="player",dist=4.8,update=true,exclusive=true,noattack=true,fn=function()
  local pp=c.player:GetPosition();local ep=e:GetPosition();local radius=math.max(4.8,math.sqrt(pp:DistSq(ep)))
  local theta=math.atan2(pp.z-ep.z,pp.x-ep.x)+s.side*.65
  return Nav.Select(c,Vector3(ep.x+math.cos(theta)*radius,0,ep.z+math.sin(theta)*radius),e)
 end}
end
return B
