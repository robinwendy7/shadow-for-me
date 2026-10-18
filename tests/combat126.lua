local savedA=package.loaded["shadowself/control/actions"]
local savedN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"};ACTIONS={ATTACK={},EQUIP={},PICKUP={},CHOP={},PLAY={}}
TUNING={TOADSTOOL_SPOREBOMB_TIMER=3.5,TOADSTOOL_SPORECLOUD_RADIUS=3.5,TENTACLE_STOPATTACK_DIST=4}
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=0
local function entity(name,x,z)
 guid=guid+1;local e={prefab=name,GUID=guid,pos=Vector3(x or 0,0,z or 0),frame=0,tags={},replica={},components={},entity={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};e.entity.GetParent=function() return e.parent end;return e
end
local p=entity("wilson",2,0);local held={};local items={};local commands={};local entities={}
p.replica.inventory={GetEquippedItem=function(_,slot) return held[slot] end,DropItemFromInvTile=function(_,item) commands[#commands+1]={drop=item} end}
p.replica.combat={};p.components.playercontroller={IsBusy=function() return false end}
ThePlayer=p;TheWorld={state={}};TheSim={FindEntities=function() return entities end}
local A={Items=function() return items end,Self=function(_,item,action) held.hands=item;commands[#commands+1]={item=item,action=action};return true end,
 Attack=function(_,target) commands[#commands+1]={target=target,action=ACTIONS.ATTACK};return true end,
 Scene=function(_,target,action) commands[#commands+1]={target=target,action=action};return true end}
package.loaded["shadowself/control/actions"]=A
require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local pauses=0;local stop=0
local c={player=p,enemies={},observed={},hazards={},snapshot={},gear={},h={IsHitingFrame=function() return p.frame>=8 end},
 bridge={PauseAttack=function() pauses=pauses+1 end,allowed=function() return true end},
 actions={SafePoint=function() return true end,Stop=function() stop=stop+1 end},
 travel={BeginDodge=function() end,EndDodge=function() end},Move=function(self,q,label) self.moved=q;self.status=label end}
c.mechanisms={Equip=function(_,item) held.hands=item;return true end}
package.loaded["shadowself/control/bosses"]=nil
local Boss=require("shadowself/control/bosses");local b=Boss(c);c.bosses=b
c.Latency=function() return .1 end;c.Speed=function() return 6 end



-- Real Gear + real Travel + real Queen, with delayed authoritative hand-slot acknowledgements.
require("shadowself/legacy/combat_equipment");local R=require("shadowself/legacy/registry")
local function equipment(name,speed)
 local item=entity(name);item.tags.weapon=true
 item.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end,IsRestricted=function() return false end}
 item.replica.inventoryitem={GetWalkSpeedMult=function() return speed or 1 end,AttackRange=function() return name=="icestaff" and 8 or 0 end}
 return item
end
local cane,ice,sword=equipment("cane",1.25),equipment("icestaff"),equipment("nightsword")
local twin=equipment("icestaff")
items={ice,twin,cane,sword};held.hands=cane
-- Real actions.Items puts inventory before equips; equipping one staff moves the other to the front.
local nativeItems=assert(loadfile("scripts/shadowself/control/actions.lua"))().Items
p.replica.inventory.GetItems=function()
 local out={};for _,item in ipairs(items) do if item~=held.hands then out[#out+1]=item end end;return out
end
p.replica.inventory.GetEquips=function() return {hands=held.hands} end
p.replica.inventory.GetOverflowContainer=function() return nil end
A.Items=nativeItems
assert(A.Items(p)[1]==ice)
local inflight;local delay=.3;local requests={};local attacks=0;local moved=0
c.owner={perception={Inventory=function() return A.Items(p) end}}
c.roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end}
c.actions={SafePoint=function() return true end,Stop=function() end,FindAction=function(_,action,target,item) return {item=item} end,
 Execute=function(_,action)
  assert(not inflight,"never submit a second equip before the first authoritative hand acknowledgement")
  requests[#requests+1]=action.item;inflight={item=action.item,due=now+delay};return true
 end}
c.gear=R.CombatEquipment(c);c.travel=require("shadowself/control/travel")(p,c.gear)
c.Move=function(self,point,label) self.blocked=true;self.moved=point;self.status=label;moved=moved+1 end
p.replica.combat.GetAttackRangeWithWeapon=function() return held.hands==ice and 8 or 2 end
A.Self=function(_,item,action) assert(action~=ACTIONS.EQUIP,"queen cannot bypass Gear with direct EQUIP");return true end
A.Attack=function(_,victim) assert((held.hands==ice or held.hands==twin) and victim.prefab=="beeguard");attacks=attacks+1;return true end
package.loaded["shadowself/control/beequeen"]=nil
local queen=entity("beequeen");local bee=entity("beeguard",6,0)
c.enemies={queen,bee};c.bridge.wrappers={PreTheLoop={old=function() end}};p.pos=Vector3(4,0,2)
local Q=require("shadowself/control/beequeen")(c);c.beequeen=Q;now=100
local function deliver()
 if inflight and now>=inflight.due-.0001 then held.hands=inflight.item;inflight=nil end
end
local function conflicting_events()
 -- Original walk_hands/fight callbacks and repeated move/attack retries used to fight the direct ice EQUIP.
 c.travel:BeginDodge(c.snapshot);c.travel:UpdateDodge(c.snapshot);c.travel:EndDodge(c.snapshot)
 c.gear:Swap("move",c.snapshot);c.gear:Swap("attack",c.snapshot)
end
Q:Tick();assert(#requests==1 and requests[1]==ice and c.gear.pending)
for i=1,12 do now=100+i*.05;deliver();conflicting_events();Q:Tick() end
assert(#requests==1 and held.hands==ice and attacks>0,"cast phase rejects travel cane requests, including in-flight role changes")
-- A real queen windup owns cane for its entire escape, despite fight events.
now=101;queen.anim="atk";queen.frame=0;Q:Tick()
assert(#requests==2 and requests[2]==cane and c.gear.support_hand.phase=="escape")
local prior=attacks
for i=1,15 do
 now=101+i/30;queen.frame=i;deliver();conflicting_events();Q:Tick()
 assert(#requests==2 and attacks==prior,"escape cannot keep re-equipping ice or submit duplicate cane requests at frame "..i)
end
assert(moved>=15 and held.hands==cane,"equipment acknowledgement never gates escape movement")
now=101.7;queen.anim="idle";c.hazards={};deliver();Q:Tick()
assert(#requests==3 and requests[3]==ice and c.gear.support_hand.phase=="freeze")
for i=1,10 do now=101.7+i*.05;deliver();conflicting_events();Q:Tick() end
assert(#requests==3 and held.hands==ice and attacks>prior,"exactly one ice restoration and then freezing resumes")
-- Late cane acknowledgement crosses the phase boundary: wait for it, then restore ice once.
delay=.9;now=103;queen.anim="atk";queen.frame=0;Q:Tick();assert(#requests==4 and requests[4]==cane)
now=103.65;queen.anim="idle";c.hazards={};deliver();Q:Tick();conflicting_events()
assert(#requests==4 and c.gear.pending.item==cane and c.gear.support_hand.item==ice,"new phase must not cancel an unacknowledged cane and issue a conflicting ice EQUIP")
now=103.91;deliver();Q:Tick();assert(#requests==5 and requests[5]==ice)
for i=1,21 do now=103.91+i*.05;deliver();conflicting_events();Q:Tick() end
assert(#requests==5 and held.hands==ice and not c.gear.pending,"delayed packets settle without endless alternation")

-- Removing/breaking the selected copy switches exactly once to the other copy.
items={twin,cane,sword};held.hands=cane;now=107;Q:Tick()
assert(Q.item_choice.icestaff==twin and requests[#requests]==twin)
now=108;deliver();Q:Tick();local count=#requests
for i=1,20 do now=108+i*.05;Q:Tick() end
assert(#requests==count and held.hands==twin,"replacement copy stays selected")
-- Same issue for firestaff: use fresh copies and begin already holding the second one.
bee.anim="idle";items={cane,sword};held.hands=cane;Q:Tick()
local fire1,fire2=equipment("firestaff"),equipment("firestaff")
items={fire1,fire2,cane,sword};held.hands=fire2
A.Attack=function(_,victim) assert(held.hands==fire2 or held.hands==fire1);attacks=attacks+1;return true end
p.replica.combat.GetAttackRangeWithWeapon=function() return (held.hands==fire1 or held.hands==fire2) and 8 or 2 end
now=110;Q:Tick();assert(Q.item_choice.firestaff==fire2,"initial same-prefab choice prefers the already-held staff over inventory-first copy")
count=#requests
for i=1,40 do
 now=110+i*.05
 -- Simulate slot-order changes while carrying two copies.
 if i%2==0 then items={fire2,cane,fire1,sword} else items={fire1,sword,fire2,cane} end
 Q:Tick()
end
assert(#requests==count and held.hands==fire2,"two firestaff copies cannot alternate across actual inventory/equip iteration")
-- Staff choice persists across cane escape, including delayed restoration.
queen.anim="atk";queen.frame=0;now=113;Q:Tick();assert(requests[#requests]==cane)
now=114;deliver();queen.anim="idle";c.hazards={};Q:Tick();assert(requests[#requests]==fire2,"cane escape restores the exact selected firestaff")
now=115;deliver();Q:Tick()
-- Broken selected staff is replaced, then remains stable.
fire2.tags.broken=true;now=116;Q:Tick();assert(Q.item_choice.firestaff==fire1 and requests[#requests]==fire1)
now=117;deliver();Q:Tick();count=#requests
for i=1,20 do now=117+i*.05;Q:Tick() end
assert(#requests==count and held.hands==fire1)
-- Crystal-deer ignition uses the same stable selection rather than repeating the mistake.
local boss=require("shadowself/control/bosses")(c);fire2.tags.broken=nil;held.hands=fire2
assert(boss:Item("firestaff")==fire2)
held.hands=cane;items={fire1,fire2,cane,sword};assert(boss:Item("firestaff")==fire2)
items={fire1,cane,sword};assert(boss:Item("firestaff")==fire1)
-- Pending choice is preferred when neither selected nor held and order changes before acknowledgement.
local Pick=require("shadowself/control/itemchoice").Pick
assert(Pick({},"firestaff",{fire1,fire2},cane,{item=fire2})==fire2)
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/beequeen"]=nil
print("PASS: real inventory-first/equip-last enumeration with two ice/fire staffs; delayed cane restore retains exact selected entity; held/pending preference, broken/missing replacement and crystal support selection")
