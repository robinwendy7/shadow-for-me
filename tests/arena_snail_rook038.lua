local savedTime,savedWorld=GetTime,TheWorld
local native=require('shadowself/native');local oldNative=native.context
local oldA=package.loaded['shadowself/control/actions'];local oldSnails=package.loaded['shadowself/control/arena_snails']
local oldPack=package.loaded['shadowself/control/arena_snailpack'];local oldBoss=package.loaded['shadowself/control/bosses']
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local id=99900
local function e(name,x,z)
 id=id+1;local v={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},anim='idle',frame=0,replica={},valid=true}
 function v:IsValid() return self.valid end;function v:HasTag(t) return self.tags[t] or false end
 function v:GetPosition() return self.pos end;function v:GetPhysicsRadius() return .5 end
 v.AnimState={IsCurrentAnimation=function(_,n) return n==v.anim end,GetCurrentAnimationFrame=function() return v.frame end}
 v.Transform={GetRotation=function() return 0 end};return v
end
native.context={ENT_util={GetAnimation=function(_,v) return v.anim end}}
local p=e('wilson',2);local rook=e('rook');local knight=e('knight',0,-15)
p.replica.inventory={GetEquippedItem=function() end};p.components={playercontroller={IsBusy=function() return false end}}
local c={player=p,enemies={rook,knight},hazards={},observed={},snapshot={},actions={SafePoint=function() return true end,Stop=function() end},
 travel={BeginDodge=function() end,EndDodge=function() end},gear={AttackRange=function() return 2 end},
 h={ent=rook,IsHitingFrame=function() return p.frame>=8 end},bridge={PauseAttack=function() end,allowed=function() return true end}}
c.plan={arena=true,arena_wave=function() return 3 end,arena_remaining=function() return c.enemies end};c.bridge.plan=c.plan
function c:Move(q) self.moved=q end
local B=require('shadowself/control/bosses');local b=B(c);c.bosses=b
local window=require('shadowself/control/arena_rook_window');local charge=require('shadowself/control/charge')
for _,name in ipairs({'rook','rook_nightmare'}) do
 rook.prefab=name;rook.anim='atk_pre';rook.frame=0;c.rook_window=nil;b.rooks[rook]=nil;p.tags.attack=nil;p.frame=0;now=0
 assert(b:Rook(rook)=='attack' and not b:AttackBlocked(rook) and not charge(c,rook,{}),'in-range preparation starts two-swing output without an immediate dodge')
 p.tags.attack=true;p.anim='atk';p.frame=1;b:Rook(rook)
 p.frame=8;assert(b:Rook(rook)=='attack' and c.rook_window.hits==1)
 b:Rook(rook);assert(c.rook_window.hits==1,'same impact frame cannot count twice')
 p.frame=1;b:Rook(rook);p.frame=8
 assert(b:Rook(rook)=='move' and c.rook_window.hits==2 and b:AttackBlocked(rook),'second completed swing immediately closes the preparation window and side-dodges')
 c.rook_window=nil;b.rooks[rook]=nil;p.tags.attack=nil;now=0;b:Rook(rook);now=1.99
 assert(b:Rook(rook)=='attack','preparation still allows the unfinished two-hit budget immediately before two seconds')
 now=2
 assert(b:Rook(rook)=='move','two-second cap cannot wait forever for two swings')
 c.rook_window=nil;b.rooks[rook]=nil;now=0;rook.anim='atk_pre';assert(b:Rook(rook)=='attack')
 rook.anim='atk';assert(b:Rook(rook)=='move' and b:AttackBlocked(rook),'actual early charge preempts an incomplete swing budget')
 rook.anim='atk_pre';c.rook_window=nil;b.rooks[rook]=nil;p.pos=Vector3(4,0,0);now=0
 assert(b:Rook(rook)=='attack' and not b:AttackBlocked(rook),'short safe gap uses the attack action to close instead of remaining on the cane sideline')
 c.charge_target=rook;c.charge_data={};c.charge_point=Vector3(8,0,0)
 assert(not charge(c,rook,{}) and not c.charge_target and not c.charge_data,'reopened preparation clears stale charge ownership')
 p.tags.attack=true;p.frame=8;window.Allow(c,rook)
 assert(c.rook_window.hits==0,'an impact animation outside real reach is not a completed in-range swing')
 p.tags.attack=nil;now=1.8
 assert(b:Rook(rook)=='move','late preparation cannot start a short approach without time for a swing')
 c.rook_window=nil;b.rooks[rook]=nil;now=0;p.pos=Vector3(8,0,0)
 assert(b:Rook(rook)=='move' and b:AttackBlocked(rook),'far targets do not trigger unsafe chasing during preparation')
 local old_dodge=charge(c,rook,{});p.pos=Vector3(4,0,0)
 assert(old_dodge and old_dodge.breakdodgefn(rook),'a captured old charge dodge exits when a safe preparation attack approach opens')
 c.rook_window=nil;b.rooks[rook]=nil;p.pos=Vector3(3.5,0,0);knight.pos=Vector3(3,0,0)
 assert(not window.Allow(c,rook),'nearby knight attack radius still takes priority over the preparation output window')
 knight.pos=Vector3(0,0,-15);p.pos=Vector3(2,0,0)
end
-- Recovery and the following preparation share a hard two-hit stop until a real new charge.
b.rooks[rook]=nil;c.rook_window=nil;c.h.ent=rook;p.pos=Vector3(2,0,0);p.tags.attack=nil;rook.anim='atk';b:Rook(rook)
rook.anim='atk_skid';b:Rook(rook)
for i=1,2 do
 p.tags.attack=true;p.anim='atk';p.frame=1;b:AttackBlocked(rook);p.frame=8
 local blocked=b:AttackBlocked(rook)
 assert(blocked==(i==2),'actual native attack gate closes on the second recovered impact before another attack request')
 p.tags.attack=nil;b:AttackBlocked(rook)
end
rook.anim='idle';p.pos=Vector3(0,0,3.5)
assert(b:Rook(rook)=='support' and b.rooks[rook].hits==2,'at the safe side point wait without extra move or attack requests')
rook.anim='atk_pre';rook.frame=0;c.rook_window=nil
assert(b:AttackBlocked(rook) and b:Rook(rook)=='support' and b.rooks[rook].wait,'preparation cannot reopen two more swings after recovery quota was used')
rook.anim='atk';b:Rook(rook);assert(not b.rooks[rook].wait,'only actual next charge unlocks the waiting budget')
rook.anim='atk_skid';b:Rook(rook);assert(b.rooks[rook].ready and b.rooks[rook].hits==0,'next actual stop opens a new two-hit cycle')
b.rooks[rook]=nil;p.tags.attack=nil
-- 不在冲撞终点等车：真实伤害半径、整段侧移路线、障碍备选也必须避开冲撞线。
local follow=require('shadowself/control/arena_rook');local nav=require('shadowself/control/navigation')
local originalRadius=rook.GetPhysicsRadius
rook.GetPhysicsRadius=function() return 1.5 end
rook.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
local rotation=0;rook.Transform.GetRotation=function() return rotation end
local function outside(point)
 local r=rotation*math.pi/180;local dx,dz=point.x-rook.pos.x,point.z-rook.pos.z
 local along=dx*math.cos(r)-dz*math.sin(r);local side=dx*math.sin(r)+dz*math.cos(r)
 return along < 0 or side*side >= 3.1^2
end
for _,angle in ipairs({0,90,180,270}) do
 rotation=angle;local r=angle*math.pi/180
 rook.pos=Vector3(0,0,0);p.pos=Vector3(math.cos(r)*10,0,-math.sin(r)*10)
 local point=follow(c,rook,{},true)
 assert(point and outside(point),'predicted end of charge is never a waiting position, rotation '..angle)
 p.pos=point
 for step=1,8 do
  rook.pos=Vector3(math.cos(r)*step,0,-math.sin(r)*step)
  local from=p.pos;local goal=follow(c,rook,{},true)
  assert(goal and outside(goal),'follow remains outside actual ram hit radius')
  for i=0,10 do
   assert(outside(Vector3(from.x+(goal.x-from.x)*i/10,0,from.z+(goal.z-from.z)*i/10)),'side-follow path never cuts across the endpoint or charge line')
  end
  p.pos=goal
  assert(math.sqrt(p.pos:DistSq(rook.pos))<=c.gear:AttackRange()+rook:GetPhysicsRadius()+1,'safe waiting point stays near melee approach range')
 end
end
-- 实际Boss入口：准备窗结束后尚未冲刺也必须提前前移，而非站在侧后方等车。
for _,angle in ipairs({0,90,180,270}) do
 rotation=angle;local r=angle*math.pi/180
 rook.pos=Vector3(0,0,0);p.pos=Vector3(-math.sin(r)*4,0,-math.cos(r)*4)
 for _,pre in ipairs({'atk_pre','paw_loop'}) do
  rook.anim=pre;rook.frame=0;c.rook_window={target=rook,anim=pre,frame=0,since=now-2,hits=0};p.tags.attack=nil
  assert(b:Rook(rook)=='move','expired preparation window immediately advances along the side')
  local dx,dz=c.moved.x-rook.pos.x,c.moved.z-rook.pos.z
  assert(dx*math.cos(r)-dz*math.sin(r)>0 and outside(c.moved),'preparation moves ahead in actual facing direction while outside ram damage')
 end
 rook.anim='atk';assert(b:Rook(rook)=='move' and outside(c.moved),'actual charge retains the safe forward side route')
end
rotation=0;rook.pos=Vector3(0,0,0);p.pos=Vector3(0,0,4)
local oldSafe=nav.Safe
nav.Safe=function(_,point) return math.abs(point.z)<1 end
local blocked=follow(c,rook,{},true)
assert(blocked:DistSq(p.pos)<.001,'blocked side route never uses a generic fallback back onto the ram line')
nav.Safe=oldSafe
rook.anim='atk_skid';p.tags.attack=nil
assert(b:Rook(rook)=='attack' and not b:AttackBlocked(rook),'confirmed skid hands directly to attack approach, no walking to the endpoint first')
rook.GetPhysicsRadius=originalRadius;rook.replica.combat=nil;rook.pos=Vector3(0,0,0)
-- Real Boss:Tick owns the whole snail/slurper encounter, bypassing normal crowd wind and torch openers.
local bag={};local held;local fire=0;local pickups=0
local function weapon(name)
 local v=e(name);v.tags.weapon=true
 v.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end}
 v.replica.inventoryitem={IsHeld=function() return true end,GetWalkSpeedMult=function() return 1 end}
 return v
end
local ham,sword,torch,staff=weapon('hambat'),weapon('nightsword'),weapon('torch'),weapon('staff_tornado');bag={ham,sword,torch,staff};held=ham
p.replica.inventory.GetEquippedItem=function() return held end
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 Attack=function(_,target,guard) assert(guard());fire=fire+1;return true end,Scene=function() pickups=pickups+1;return true end}
for _,k in ipairs({'arena_snails','arena_snailpack','bosses'}) do package.loaded['shadowself/control/'..k]=nil end
B=require('shadowself/control/bosses')
local snail1,snail2=e('slurtle',0,0),e('snurtle',0,2)
local slurpers={e('slurper',0,20),e('slurper',4,20),e('slurper',8,20),e('slurper',12,20)}
local roster={snail1,snail2};for _,v in ipairs(slurpers) do roster[#roster+1]=v end
c.enemies=roster;c.h.ent=slurpers[1];c.plan.arena_wave=function() return 5 end;c.plan.arena_remaining=function() return roster end
c.plan.arena_center=function() return Vector3(0,0,0) end;c.plan.arena_entities=function() return roster end
c.owner={perception={Inventory=function() return bag end}}
require('shadowself/legacy/combat_equipment');c.gear=require('shadowself/legacy/registry').CombatEquipment(c)
c.mechanisms={Equip=function(_,item) held=item;return true end};c.bridge.wrappers={PreTheLoop={old=function() end}}
b=B(c);c.bosses=b;p.pos=Vector3(0,0,5)
local stopped=0;c.arena_wind={Stop=function() stopped=stopped+1;c.arena_wind=nil end}
assert(b:Tick(snail1)=='move' and fire==0 and stopped==1,'close snail takes perimeter-escape priority and cancels old wind without lighting snails')
p.pos=Vector3(0,0,18)
assert(b:Tick(snail1)=='support' and b.snailpack.phase=='bait' and fire==0,'after six-unit separation wait for slurper to attack first')
local current=b.snailpack.target;current.anim='atk';current.frame=0
assert(b:Tick(snail1)=='attack' and not b.snailpack:CanAttack(current),'native dodge executes the bait attack while all premature strikes remain blocked')
current.frame=31;assert(b:Tick(snail1)=='attack' and require('shadowself/control/arena_attackwindows').Block(c,current),'late attack animation still owns its dodge window')
current.anim='headslurp';current.frame=0
assert(b:Tick(snail1)=='attack' and not b.snailpack:CanAttack(current),'rolling-to-head-pounce transition cannot grant a premature melee strike')
current.frame=25;assert(b:Tick(snail1)=='attack' and not b.snailpack:CanAttack(current),'pounce damage frame is not proof of a missed completed attack')
current.anim='headslurpmiss';current.frame=0
assert(b:Tick(snail1)=='attack' and b.snailpack.phase=='fight' and c.gear.forced_weapon==sword,'actual missed pounce immediately permits better-than-hambat melee rather than tornado')
local windows=require('shadowself/control/arena_attackwindows')
assert(windows.Committed(c,current) and windows.Dodge(c,current,{atkanim='idle'})==false,'confirmed miss suppresses generic idle dodge fallback')
current.anim='atk';current.frame=0
assert(b:Tick(snail1)=='attack' and not b.snailpack:CanAttack(current) and not windows.Committed(c,current),'next actual lock immediately closes melee even after the opening bait is complete')
current.anim='headslurpmiss';b:Tick(snail1)
b.snailpack.phase='bait';b.snailpack.bait_seen=nil
assert(b:Tick(snail1)=='attack' and b.snailpack.phase=='fight','observing an explicit missed pounce does not require witnessing the whole previous roll')
assert(b.snailpack:CanAttack(current) and not b.snailpack:CanAttack(snail1),'only the selected slurper is an attack target')
local star=weapon('nightstick');local normalBag=bag;bag={ham,star}
assert(b.snailpack:Weapon(current) and c.gear.forced_weapon==ham,'dry slurper cannot force a nightstick over the carried hambat')
current.tags.wet=true
assert(b.snailpack:Weapon(current) and c.gear.forced_weapon==star,'wet slurper with no electric buff can use the actual stronger electric weapon')
local oldBuff=p._shadowself_combat_buffs;p._shadowself_combat_buffs={electric_until=now+10}
assert(b.snailpack:Weapon(current) and c.gear.forced_weapon==ham,'existing electric buff prevents redundant forced nightstick selection')
p._shadowself_combat_buffs=oldBuff;current.tags.wet=nil;bag=normalBag;b.snailpack:Weapon(current)
local other=current==slurpers[1] and slurpers[2] or slurpers[1]
assert(not b.snailpack:CanAttack(other),'do not switch between living slurpers mid-kill')
snail1.pos=Vector3(0,0,13)
assert(b:Tick(current)=='move' and not b.snailpack:CanAttack(current),'snail closing within six units immediately interrupts melee')
snail1.pos=Vector3(0,0,0)
for _,v in ipairs(slurpers) do
 v.tags.dead=true;b:Tick(snail1)
 assert(fire==0,'no torch strike until every source-configured slurper is confirmed dead')
 v.valid=false -- once confirmed, unloaded corpses must not revive the death counter.
end
assert(b.snailpack.phase=='torch' and c.gear.forced_weapon==torch,'all confirmed slurper deaths release normal torch handling')
p.pos=Vector3(1,0,0);now=20
assert(b:Tick(snail1)=='support' and fire==1 and held==torch,'only now approach and ignite the snail with a real torch attack')
-- Start the next ignition before the first burning slurtle explodes.
snail1.tags.fire=true;snail2.pos=Vector3(8,0,0);now=20.2
local zone=require('shadowself/control/arena_fire').Zone(snail1,p)
assert(zone.fire and not zone.explosive_snail,'fresh ignition creates burning danger before the explosion window')
assert(b:Tick(snail1)=='move' and fire==1,'first escape burning contact before approaching the second snail')
p.pos=Vector3(5,0,0);now=20.4
local chain=b:Tick(snail1);assert(chain=='move' and fire==1,'confirmed first ignition immediately approaches the unlit snurtle')
p.pos=c.moved;now=21.5
assert(b:Tick(snail1)=='support' and fire==2 and snail1:IsValid() and snail1.tags.fire,'second snail receives a real torch strike before first explosion')
assert(p.pos:DistSq(snail2.pos)<1.07^2,'snurtle ignition requires actual body-contact distance')
snail2.tags.fire=true;now=21.7;assert(b:Tick(snail2)=='move','both ignited means immediate blast withdrawal, not continued torch attacks')
now=26;assert(require('shadowself/control/arena_fire').Zone(snail1,p),'late fuse restores normal explosion danger before detonation')
local unknown=e('snurtle',10,0);unknown.tags.fire=true
assert(require('shadowself/control/arena_fire').Zone(unknown,p),'already burning unknown-age snail never gets a fabricated eight-second timer')
-- Same subtype: two slurtles in the user's sixth-wave scene also chain without waiting for the first blast.
c.plan.arena_wave=function() return 6 end
snail1.tags.fire=nil;snail2.tags.fire=nil;snail1._shadowself_snail_fire=nil;snail2._shadowself_snail_fire=nil
snail2.prefab='slurtle';p.pos=Vector3(1,0,0);now=40;b.next_snail_fire=nil
local beforePair=fire;assert(b:Tick(snail1)=='support' and fire==beforePair+1)
snail1.tags.fire=true;now=40.2;assert(b:Tick(snail1)=='move')
p.pos=Vector3(5,0,0);now=40.4;assert(b:Tick(snail1)=='move')
p.pos=c.moved;now=41.5;assert(b:Tick(snail1)=='support' and fire==beforePair+2 and snail1.tags.fire and snail1:IsValid(),'a second slurtle ignites before the first one dies')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/arena_snails']=oldSnails
package.loaded['shadowself/control/arena_snailpack']=oldPack;package.loaded['shadowself/control/bosses']=oldBoss
native.context=oldNative;GetTime,TheWorld=savedTime,savedWorld
print('PASS: rook preparation two real swing frames/2-second cap/range and early-charge release; snail perimeter separation, bait-first locked melee and source-counted deaths before torch')
