local savedA=package.loaded['shadowself/control/actions'];local savedH=package.loaded['shadowself/control/arena_healing'];local savedF=package.loaded['shadowself/control/arena_food']
local savedCooking=package.loaded.cooking;local oldTime,oldWorld,oldNet,oldSim=GetTime,TheWorld,TheNet,TheSim
local now=0;GetTime=function() return now end;TheNet={GetPing=function() return 22 end}
local constants={HEALING_TINY=1,HEALING_SMALL=3,HEALING_MEDSMALL=8,HEALING_MED=20,HEALING_MEDLARGE=30,HEALING_LARGE=40,HEALING_HUGE=60,HEALING_MOREHUGE=75,HEALING_SUPERHUGE=100}
setmetatable(constants,{__index=function() return 0 end})
local strings={};setmetatable(strings,{__index=function() return strings end})
local env=setmetatable({TUNING=constants,FOODTYPE={MEAT='MEAT',VEGGIE='VEGGIE'},STRINGS=strings},{__index=_G})
local function recipes(path) local fn=assert(loadstring(read_source(path)));setfenv(fn,env);return fn() end
local official=recipes('preparedfoods.lua');local warly=recipes('preparedfoods_warly.lua')
package.loaded.cooking={recipes={cookpot=official,portablecookpot=warly}}
package.loaded['shadowself/control/arena_food']=nil
local Food=require('shadowself/control/arena_food')
local id=97000;local bag={};local hp=80;local busy=false;local attacks=false
local eats,picks,pauses,moves,stops=0,0,0,0,0
local function entity(name,x,tags)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,0),replica={},components={},tags=tags or {}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.Transform={GetRotation=function() return 0 end}
 e.AnimState={IsCurrentAnimation=function(_,name) return name==e.anim end,GetCurrentAnimationFrame=function() return 20 end}
 return e
end
local p=entity('wilson');p.replica.health={GetCurrent=function() return hp end,MaxWithPenalty=function() return 150 end}
p.replica.inventory={GetEquippedItem=function() end}
p.components.playercontroller={IsBusy=function() return busy end}
local tag=p.HasTag;function p:HasTag(t) if t=='attack' then return attacks end;return tag(self,t) end
local function food(name,percent,tags)
 local item=entity(name,0,tags)
 item.replica.inventoryitem={classified={perish={value=function() return percent or 62 end}}}
 return item
end
local waffle=food('waffles');local pie=food('dragonpie');local ham=food('honeyham',62,{edible_MEAT=true});local ball=food('meatballs')
assert(Food.Health(waffle,p)==official.waffles.health and Food.Health(pie,p)==40)
assert(Food.Health(food('sweettea'),p)==3,'actual tea health, not sanity value15')
assert(Food.Duration(ham)>Food.Duration(pie),'official meat vs quick-eat timing')
assert(math.abs(Food.Health(food('waffles',25),p)-60*(TUNING.STALE_FOOD_HEALTH or .333))<.01)
assert(Food.Health(food('waffles',5),p)==0 and Food.Health(food('mandrakesoup'),p)==0 and Food.Health(food('nightmarepie'),p)==0)
assert(Food.Health(food('dragonpie_spice_chili'),p)==40,'seasoned meals resolve base recipe')
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Self=function(_,item,action) assert(action==ACTIONS.EAT);eats=eats+1;return true end,
 Scene=function(_,item,action) assert(action==ACTIONS.PICKUP);picks=picks+1;return true end,Stop=function() stops=stops+1 end}
package.loaded['shadowself/control/arena_healing']=nil
local Healing=require('shadowself/control/arena_healing')
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheSim={FindEntities=function() return {} end}
local c={player=p,plan={arena=true},enemies={},observed={},hazards={},gear={},snapshot={},h={},
 actions={SafePoint=function() return true end},
 bridge={PauseAttack=function() pauses=pauses+1 end},
 travel={BeginDodge=function(self) self.dodging=true end,EndDodge=function(self) self.dodging=nil end},
 Latency=function() return .122 end,Speed=function() return 7.5 end}
c.Move=function(_,q) moves=moves+1;c.goal=q end
local h=Healing(p);bag={pie,waffle,ball};hp=110
assert(h:Choose(c)==pie,'40 missing selects40-heal rather than wasting60 or repeatedly eating3')
hp=140;c.intermission=true;assert(h:Choose(c)==ball,'small deficit reserves large recovery meal')
hp=150;assert(not h:Choose(c));c.intermission=nil
hp=80;bag={waffle};attacks=true
local before=pauses;assert(not h:Tick(c) and eats==0 and pauses==before,'do not cut a swing before impact to eat')
assert(h:BlockAttack('CloseAndAttack') and not h:BlockAttack('OnKeyFrame'),'drain blocks next attack while retaining current original post-hit step')
attacks=false;now=.04;assert(h:Tick(c) and eats==1 and h.pending)
now=.1;h:Tick(c);assert(eats==1 and h.pending,'no optimistic healing or repeated EAT while inventory unchanged')
hp=81;now=1.1;h:Tick(c);assert(h.pending,'unrelated regeneration without eating evidence cannot acknowledge meal')
hp=140;bag={};now=1.2;h:Tick(c);assert(not h.pending,'real inventory decrease still acknowledges a late interrupted meal')
assert(not p._shadowself_combat_buffs,'healing cannot fabricate electric buff bookkeeping')

local enemy=entity('hound',9,{hostile=true});enemy.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
c.enemies={enemy};c.observed[enemy.GUID]={neutral=true};hp=30;bag={waffle};h:Reset();now=2
local count=eats;assert(h:Tick(c) and h.seeking and moves>0 and eats==count,'critical health finds reachable safe gap rather than eats in melee range')
local seeking=h.seeking;c.travel.dodging=true;c.travel.restore_dodge=true
h:Release(c,true);assert(c.travel.dodging and c.travel.restore_dodge,'healing release cannot clear another dodge owner flags')
c.travel.dodging=nil;c.travel.restore_dodge=nil;h.seeking=seeking
p.pos=c.goal;now=2.2;assert(h:Tick(c) and eats==count+1 and not h.seeking and not c.travel.dodging,'cane retreat releases without extra equip before meal')
-- New side charge during a pending meal must yield to the normal dodge thread.
local rook=entity('rook',p.pos.x-10);rook.pos.z=p.pos.z;rook.anim='atk';rook.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
c.enemies={rook};c.observed={};now=2.3
assert(not h:Tick(c) and h.pending and eats==count+1,'side charge preempts pending meal without resending')
assert(h.pending.interrupted,'interrupted meal never reacquires control when danger disappears')
c.enemies={};now=2.4;assert(not h:Tick(c),'no ghost waiting after urgent dodge interrupted meal')
c.healing=h;p.anim='hit';require('shadowself/control/coordinator').HitRecovery(c)
assert(not h.seeking and not h.draining_until and h.pending.interrupted,'real hit-recovery entry releases healing intent')
p.anim=nil;c.healing=nil
h:Reset();p.pos=Vector3(0,0,0);enemy.pos=Vector3(3,0,0);c.enemies={enemy};c.observed={[enemy.GUID]={dodge={atkanim='atk'}}};enemy.anim='atk';now=3
assert(not h:Tick(c) and not h.seeking,'urgent primary windup retains original dodge, not healing retreat')
enemy.anim=nil;enemy.pos=Vector3(20,0,0);c.observed={[enemy.GUID]={neutral=true}};c.hazards={{pos=Vector3(0,0,0),radius=2}}
hp=90;h:Reset();assert(not h:Tick(c),'unsafe floor vetoes even otherwise distant enemies')
c.hazards={};busy=true;assert(not h:Tick(c));busy=false
enemy.pos=Vector3(1,0,0);enemy.tags.frozen=true
assert(not h:Safe(c,p:GetPosition(),1),'near frozen unit has unknown remaining freeze time and can wake during meal')
enemy.tags.frozen=nil;enemy.pos=Vector3(20,0,0)
local cloud=entity('sporecloud',0,{sporecloud=true});TheSim.FindEntities=function() return {cloud} end;h.next_floor_scan=nil
assert(not h:Tick(c),'persistent spore cloud vetoes eating even without a live enemy')
TheSim.FindEntities=function() return {} end;h.next_floor_scan=nil
p.pos=Vector3(-5,0,0);enemy.pos=Vector3(0,0,0)
assert(not h:Path(c,Vector3(5,0,0)),'healing approach cannot cross an idle secondary enemy attack circle')
p.pos=Vector3(0,0,0);enemy.pos=Vector3(20,0,0)
c.gear.action_hold={kind='queen_flute'};assert(not h:Tick(c),'flute/freeze support holds take priority');c.gear.action_hold=nil

-- Nearby ground food is picked only across a safe short path, then eaten after ownership sync.
h:Reset();hp=30;bag={};waffle.pos=Vector3(.5,0,0);c.plan.arena_ground=function() return {waffle} end;now=4
assert(h:Tick(c) and h.pending.kind=='pickup' and picks==1)
now=4.1;assert(h:Tick(c) and picks==1 and #bag==0,'pickup request is not ownership')
bag={waffle};now=4.2;assert(h:Tick(c) and not h.pending)
now=4.4;local fed=eats;assert(h:Tick(c) and eats==fed+1 and h.pending.name=='waffles')
now=8;h:Tick(c);assert(not h.pending and h.failed[waffle.GUID]>now,'rejected or interrupted EAT backs off')

-- Between waves uses the same meal state but cancels its own outstanding pickup movement.
h:Reset();c.enemies={};c.observed={};c.intermission=true;hp=100;bag={waffle};now=9
local stopped=stops;assert(h:Tick(c) and stops==stopped+1)
local combatFile=assert(io.open('scripts/shadowself/control/combat.lua','r'));local combatSource=combatFile:read('*a');combatFile:close()
local mechanism=combatSource:find('local support=c.mechanisms:Tick()',1,true)
local boss=combatSource:find('c.bosses:Tick(target)',mechanism,true)
local healing=combatSource:find('support=c.healing:Tick(c)',mechanism,true)
assert(boss<healing,'real combat integration evaluates boss mechanisms before healing')
-- Slow network/rejection without any eat animation cannot hold control for the whole timeout.
h:Reset();hp=80;bag={waffle};now=14;p.anim=nil;assert(h:Tick(c))
now=14.4;assert(not h:Tick(c) and h.pending.interrupted,'no-animation request releases ownership after start grace')
h:Reset();hp=80;now=15;assert(h:Tick(c));hp=70;p.anim='hit';now=15.1
assert(not h:Tick(c) and h.pending.interrupted,'intermission detects damage itself without a live native target')
p.anim=nil
-- Infinite server food needs actual eating evidence plus health change, not count alone.
h:Reset();hp=80;now=16;assert(h:Tick(c));p.anim='quick_eat';now=16.1;h:Tick(c)
hp=140;now=17.1;h:Tick(c);assert(not h.pending,'observed eating plus delayed health change acknowledges infinite food')
p.anim=nil;c.intermission=nil
-- Replay movement gradually while a monster also moves, rather than teleporting to a safe point.
h:Reset();hp=30;now=20;p.pos=Vector3(0,0,0);enemy.pos=Vector3(9,0,0)
c.enemies={enemy};c.observed={[enemy.GUID]={neutral=true}};assert(h:Tick(c) and h.seeking)
local anchor=h.seeking.anchor;local goal=h.seeking.point
for i=1,3 do
 now=20+i*.2;p.pos=Vector3(-1.5*i,0,0);enemy.pos=Vector3(9-1.2*i,0,0)
 local prev=eats;h:Tick(c)
 if h.seeking then assert(h.seeking.point:DistSq(anchor)<=8^2) end
 if i<3 then assert(eats==prev,'do not start meal before real moving separation is sufficient') end
end
assert(h.pending and h.pending.name=='waffles','predicted travel and actual separation open a meal window')
-- A slower character cannot plan a fictitious gap against a faster advancing target.
h:Reset();now=22;p.pos=Vector3(0,0,0);enemy.pos=Vector3(4,0,0)
c.Speed=function() return 6 end;assert(not h:Tick(c) and not h.seeking,'unreachable safe endpoint must not create endless retreat')
-- Use the real gear state machine and a delayed hand-slot acknowledgement.
require('shadowself/legacy/combat_equipment')
local sword=entity('nightsword',0,{weapon=true});local cane=entity('cane',0,{weapon=true})
for _,item in ipairs({sword,cane}) do
 item.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end,IsRestricted=function() return false end}
 item.replica.inventoryitem={GetEquipRestrictedTag=function() end,GetWalkSpeedMult=function() return item==cane and 1.25 or 1 end}
end
local equipped=sword;local equipment={}
p.replica.inventory.GetEquippedItem=function() return equipped end
c.owner={perception={Inventory=function() return bag end}};c.roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end}
c.actions.FindAction=function(_,name,_,item) return {name=name,invobject=item} end
c.actions.Execute=function(_,act) equipment[#equipment+1]=act.invobject;return true end
c.actions.Stop=function() end;c.gear=require('shadowself/legacy/registry').CombatEquipment(c)
c.Speed=function() return 7.5 end;c.target=enemy;c.snapshot={night=false}
bag={sword,cane,waffle};h:Reset();hp=30;enemy.pos=Vector3(9,0,0);now=24
assert(h:Tick(c) and c.gear.pending.item==cane and #equipment==1)
for i=1,3 do now=24+i*.03;local support=h:Tick(c);if not support then c.gear:Swap('attack',c.snapshot) end end
assert(#equipment==1 and c.gear.pending.item==cane,'delayed cane ack cannot trigger contrary weapon equip on next supervisor frame')
equipped=cane;now=24.12;assert(h:Tick(c) and not c.gear.pending and #equipment==1)
p.anim=nil;require('shadowself/control/coordinator').HitRecovery(c)
p.pos=c.goal;now=24.2;assert(h:Tick(c) and h.pending and #equipment==1,'meal does not restore weapon and eat concurrently')
c.healing=h;p.anim='hit';require('shadowself/control/coordinator').HitRecovery(c)
now=24.3;local support=h:Tick(c);assert(not support)
if not support then c.gear:Swap('attack',c.snapshot) end
assert(#equipment==2 and equipment[2]==sword,'after hurt normal combat restores weapon once')
equipped=sword;p.anim=nil
for i=1,3 do now=24.3+i*.03;local active=h:Tick(c);if not active then c.gear:Swap('attack',c.snapshot) end end
assert(#equipment==2,'interrupted meal cannot start cane/weapon ping-pong')
package.loaded['shadowself/control/actions']=savedA;package.loaded['shadowself/control/arena_healing']=savedH;package.loaded['shadowself/control/arena_food']=savedF;package.loaded.cooking=savedCooking
GetTime=oldTime;TheWorld=oldWorld;TheNet=oldNet;TheSim=oldSim
print('PASS: official recipe recovery, spoilage/seasoning, meat/quick timings, deficit choice, safe low-health retreat, side-charge and ground danger priority, swing drain, authoritative pickup/eat confirmation, retry and intermission healing')
