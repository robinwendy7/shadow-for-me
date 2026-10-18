-- 状态机场景模拟；不代替引擎物理、延迟和联网确认的实测。
local savedA=package.loaded["shadowself/control/actions"]
local now=0;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
EQUIPSLOTS={HANDS="hands",BODY="body",HEAD="head"}
ACTIONS={EQUIP={},UNEQUIP={},USEITEM={},BLINK={},PICKUP={},WALKTO={},JUMPIN={},JUMPOFF={}}
TUNING={MOONSPORE_ATTACK_RANGE=3,ARMOR_SKELETON_FIRST_COOLDOWN=1,ARMOR_SKELETON_COOLDOWN=5}
local guid=100
local function ent(name,x,z)
 guid=guid+1
 local e={GUID=guid,prefab=name,pos=Vector3(x or 0,0,z or 0),tags={},frame=0,replica={},entity={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e.entity:GetParent() return e.owner end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end,
 GetHistoryData=function() return nil,e.anim end,SetMultColour=function(_,...) e.colour={...} end,GetMultColour=function() return 1,1,1,1 end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=ent("wilson",0,0);local equipped={};local inventory={};local entities={};local blinks,uses,pickups=0,0,0
p.replica.inventory={GetEquippedItem=function(_,slot) return equipped[slot] end}
p.components={playercontroller={IsBusy=function() return false end}}
local A={Items=function() return inventory end,
 Self=function(_,i,action)
  if action==ACTIONS.EQUIP then equipped[i.replica.equippable:EquipSlot()]=i
  elseif action==ACTIONS.UNEQUIP then equipped[i.replica.equippable:EquipSlot()]=nil
  elseif action==ACTIONS.USEITEM then uses=uses+1;p.tags.shell=true;p.anim="shell_idle" end;return true
 end,
 Ground=function(_,q,action) assert(action==ACTIONS.BLINK);blinks=blinks+1;p.pos=q;return true end,
 Scene=function(_,i,action) assert(action==ACTIONS.PICKUP);pickups=pickups+1;i.owner=p;inventory[#inventory+1]=i;return true end}
package.loaded["shadowself/control/actions"]=A
TheSim={FindEntities=function() return entities end}
local c={player=p,enemies={},hazards={},observed={},bridge={},actions={SafePoint=function() return true end},
 gear={Owned=function(_,item) for _,i in ipairs(inventory) do if i==item then return true end end;return false end,Swap=function() return true end},
 travel={BeginDodge=function() end,EndDodge=function() end},Move=function(self,q) self.moved=q end,Speed=function() return 6 end}
local Mechanisms=require("shadowself/control/mechanisms");local m=Mechanisms(c)
local spore=ent("spore_moon",2,0);spore.anim="rumble";entities={spore}
m:Scan();assert(#m.zones==0,"not all idle spores cause endless fleeing")
now=.4;m:Scan();assert(#m.zones==1 and m:Escape() and c.moved,"move before timed spore explosion")
spore.anim="idle_flight_loop";m:Scan();assert(#m.zones==0)
local spike=ent("sandspike_tall",.5,0);spike.anim="tall_pre";entities={spike}
m:Scan();assert(#m.zones==1,"visible spike is a route obstacle before its damage frame");spike.frame=24;m:Scan();assert(#m.zones==1 and m:Escape(),"sand spike escapes during pre-animation")
local wall=ent("sandblock",8,0);entities={wall};m:Scan();assert(wall.colour[4]==0);m:Stop();assert(wall.colour[4]==1,"sand wall visuals restore; collision entity is not removed")
local shark=ent("sharkboi",0,0);shark.anim="atk1";p.pos=Vector3(3,0,0)
local dodge=m:Dodge(shark,false);assert(dodge and dodge.fn)
local point=dodge:fn();assert(point.z~=0 and point:DistSq(shark.pos)>=2.2^2-.001 and point:DistSq(shark.pos)<=2.5^2+.001,"shark route follows circumference instead of a chord through its body")
shark.frame=17;assert(m:Dodge(shark,false)==false,"shark hit window ends and allows attack")
local function item(name,slot)
 local i=ent(name);i.replica.equippable={EquipSlot=function() return slot end,IsRestricted=function() return false end};return i
end
local bone=item("armorskeleton",EQUIPSLOTS.BODY);inventory={bone};equipped.body=bone;entities={};now=1;m:Scan()
local existing=Mechanisms(c);assert(existing.bone_ready==now+5,"unknown pre-takeover bone cooldown waits a full cooldown")
local klaus=ent("klaus");klaus.anim="attack_chomp";klaus.frame=20;local native={native=true}
assert(m:Dodge(klaus,native).noattack,"unknown cooldown uses outward dodge, never native push-in")
now=2.1;assert(m:Dodge(klaus,native)==false,"ready bone permits attacks during chomp windup")
klaus.frame=35;assert(m:Dodge(klaus,native)==false,"hold armored position through actual bite until shield feedback or next frame")
local shield=ent("shadow_shield3");shield.owner=p.entity;entities={shield};m:Scan();klaus.frame=20
assert(m:Dodge(klaus,native).noattack,"observed shield starts outward exit without old push-in table")
local staff=item("orangestaff",EQUIPSLOTS.HANDS);local shell=item("armorsnurtleshell",EQUIPSLOTS.BODY)
inventory={bone,staff,shell};equipped.body=bone;equipped.hands=nil;p.pos=Vector3(5,0,0)
local robot=ent("wagboss_robot");robot.anim="atk_missile_pre1";local missile=ent("wagboss_missile");entities={robot,missile};now=10
for i=1,10 do m:Scan();assert(m:Missile());now=now+.1 end
assert(blinks==1 and equipped.body==shell and uses==1,"one blink then equip and activate shell")
robot.anim="idle";entities={robot,missile};now=12;m:Scan();assert(m:Missile(),"remaining missiles keep shell locked after casting ends")
entities={robot};m:Scan();m:Missile();now=13;m:Scan();assert(not m:Missile() and equipped.body==bone and c.bridge.resume_target==robot,"return only after missile-clear interval, restore armour and resume boss")
-- Recover a known disarmed weapon, then put it back in hand after ownership acknowledgement.
p.tags.shell=nil;p.anim=nil;p.pos=Vector3(0,0,0);equipped.hands=nil
local dropped=item("nightsword",EQUIPSLOTS.HANDS);dropped.tags.weapon=true;dropped.pos=Vector3(2,0,0)
m.last_weapon=dropped;inventory={};entities={dropped};now=20;m:Scan();assert(m:Pickup() and pickups==1)
now=21;m:Scan();m:Pickup();assert(c.gear:Owned(dropped),"dropped weapon pickup confirmed in inventory")
local hat=item("footballhat",EQUIPSLOTS.HEAD);entities={hat};now=22;m:Scan();assert(m:Pickup());now=23;m:Pickup();assert(equipped.head==hat,"ground helmet is picked and equipped")
-- Crowd selection uses range; at four or fewer enemies damage wins.
require("shadowself/legacy/combat_equipment")
local Registry=require("shadowself/legacy/registry")
local sword=item("nightsword",EQUIPSLOTS.HANDS);sword.tags.weapon=true
local whip=item("whip",EQUIPSLOTS.HANDS);whip.tags.weapon=true
local star=item("nightstick",EQUIPSLOTS.HANDS);star.tags.weapon=true
for _,i in ipairs({sword,whip,star}) do i.replica.inventoryitem={GetWalkSpeedMult=function() return 1 end,AttackRange=function() return 0 end} end
local context={player=p,owner={perception={Inventory=function() return inventory end}},enemies={},actions={},roles={}}
local gear=Registry.CombatEquipment(context);inventory={sword,whip,star}
for i=1,4 do context.enemies[i]=ent("hound") end
assert(gear:Weapon()==sword,"four enemies still choose high damage")
context.enemies[5]=ent("hound");assert(gear:Weapon()==whip,"five enemies prefer ranged melee whip")
inventory={sword,star};assert(gear:Weapon()==sword,"crowd alone no longer promotes morning star")
-- Native attack thread is stopped throughout chase, resumed only after weapon hand acknowledgement.
local Bridge=require("shadowself/control/combat")
local oldNative=require("shadowself/native").context
local h={};local tuning={};local stopped,started,moved=0,0,0;local target=ent("hound",12,0)
h.GetAttackTargets=function() end;h.GetClosestTarget=function() return target end
h.PreTheLoop=function() end;h.IsAttackPre=function() return false end
h.StopHitAndRun=function() stopped=stopped+1;tuning.Cheatthread=nil end
h.StartHitAndRun=function() started=started+1;tuning.Cheatthread={id=80,SetList=function() end} end
local pc=p.components.playercontroller;pc.DoAction=function() end;pc.IsHopping=function() return false end
local co={player=p,gear={AttackRange=function() return 2 end,Swap=function() return true end,Weapon=function() return nil end},
 travel={Tick=function() end,EndDodge=function() end},mechanisms={Tick=function() return false end},
 actions=c.actions,enemies={},hazards={},Scan=function() end,HitRecovery=function() end}
local n={HitAndRun=h,TUNING=tuning,POS_util={GoToPoint=function() moved=moved+1 end},KEY_util={MoveKeyDown=function() return false end}}
require("shadowself/native").context=n
local routines={};StartThread=function(fn) local t={id=90,SetList=function() end};routines[t]=coroutine.create(fn);return t end
Sleep=function() coroutine.yield() end;FRAMES=1/30;KillThreadsWithID=function() end
local bridge=Bridge(p);bridge.h=h;bridge.native=n;bridge.tuning=tuning;bridge.coordinator=co;co.bridge=bridge;bridge.allowed=function() return true end;bridge.wrappers={PreTheLoop={old=h.PreTheLoop}};p.replica.combat=p.replica.combat or {};ThePlayer=p
bridge.thread={};tuning.Cheatthread=bridge.thread
bridge:Supervise();assert(coroutine.resume(routines[bridge.supervisor]));assert(stopped==1 and started==0 and moved==1 and bridge.chasing,"far target suspends original attack thread before movement")
assert(coroutine.resume(routines[bridge.supervisor]));assert(stopped==1 and moved==2,"chase cannot repeatedly start attack/equip fighting")
target.pos=Vector3(2,0,0);assert(coroutine.resume(routines[bridge.supervisor]));assert(started==1 and not bridge.chasing,"near target resumes attack exactly once")
pc:DoAction({action=ACTIONS.WALKTO});assert(not tuning.Cheatthread and bridge:ManualAction(),"manual shore/boat walk suspends attacks immediately")
bridge.supervisor=nil;pc.DoAction=bridge.action_old
require("shadowself/native").context=oldNative
package.loaded["shadowself/control/actions"]=savedA
print("PASS: timed spore/spike defence, shark arc, bone chomp window, single blink/shell/missile drain, loot and exclusive chase/attack/manual boat phases")
