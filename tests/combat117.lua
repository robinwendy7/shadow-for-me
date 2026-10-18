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


-- A second locked throw can be ignited before landing, from ranged distance.
local deer=entity("mutateddeerclops");deer.anim="throw_2";deer.frame=30
c.enemies={deer};c.h.ent=deer;p.pos=Vector3(8,0,0);b:Crystal(deer)
local fire=entity("firestaff");items={fire};p.pos=Vector3(0,0,7);deer.frame=34;now=1
local before=#commands;assert(b:Crystal(deer)=="support")
assert(#commands==before+1 and commands[#commands].action==ACTIONS.ATTACK and commands[#commands].target==deer,"firestaff shoots outside blast before frame60")
assert(held.hands==fire and p.pos:DistSq(deer.pos)==49,"ranged ignition does not require closing to the feet")
local torch=entity("torch");items={torch};p.pos=Vector3(0,0,2);now=2
before=#commands;assert(b:Crystal(deer)=="support" and #commands==before+1,"torch attacks during throw rather than walking back outside")
deer.tags.fire=true;assert(b:Crystal(deer)=="attack" and not c.gear.forced_weapon)
deer.tags.fire=nil;deer.anim="stagger";b:Crystal(deer);deer.anim="atk"
local normal={atkanim="atk",atk_start_frame=14,atk_stop_frame=35,point="player",update=false,angle=-80*math.pi/180,dist=6};require("shadowself/native").context.HitAndRun={targetanimtable={deerclops={normal}}}
p.pos=Vector3(2,0,0);deer.frame=16;assert(b:Dodge(deer,false)==normal,"crystal reuses ordinary deer data without rewriting the aim")
deer.anim="ice_grow";deer.frame=13;b:Crystal(deer);assert(b.crystal.eye_bare,"arm regrowth must not fake eye armour")
deer.anim="ice_grow_2";deer.frame=3;b:Crystal(deer);assert(not b.crystal.eye_bare and not b.crystal.bare,"eye regrowth re-enables bait/ignite cycle")
-- Bomb follower is absent from spatial scan; registry still locates its owner.
local bomb=entity("sporebomb");bomb.parent=p;bomb.pos=Vector3(0,0,0)
bomb.components.timer={GetTimeLeft=function() return .6 end}
local registry=require("shadowself/bombs");registry.Track(bomb)
p.pos=Vector3(17,0,9);c.enemies={};c.h.ent=nil
local zones=b:Zones({});assert(#zones==1 and zones[1].pos==p.pos and b.bomb_imminent==bomb)
c.hazards=zones;local run=b:BombPoint();assert(run and run:DistSq(p.pos)>1,"own attached bomb triggers sustained escape")
registry.tracked[bomb]=nil;c.hazards={};b:Zones({});assert(b:BombPoint(),"keep moving through bomb removal and cloud replication gap");now=now+1;assert(not b:BombPoint())
-- Whole lunar-ghost wave suppresses attacks, including intervals between gaps.
local ghost=entity("smallguard_alterguardian_projectile",10,9);p.pos=Vector3(17,0,9)
b:Zones({ghost});assert(b:MoonHolding() and b:AttackBlocked(deer))
b:Zones({});now=now+.1;assert(b:MoonHolding(),"brief gap between ghosts cannot reopen attack")
now=now+.4;assert(not b:MoonHolding() and not b:AttackBlocked(deer))
-- Tired plant is attacked, wakeup stops greed, and unrelated vine whip is recognized.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.anim="tired_loop_large"
local vine=entity("lunarthrall_plant_vine_end",7,0);vine.tags.lunarthrall_plant_end=true
c.enemies={head,vine};c.h.ent=head;p.pos=Vector3(2,0,0)
local mode,target=b:Brightshade(vine);assert(mode=="attack" and target==head)
head.anim="tired_wakeup_loop_large";assert(b:AttackBlocked(head))
mode=b:Brightshade(head);assert(mode=="move","waking head must not finish animation under attack")
head.anim="idle";head.tags.retaliates=true
local middle=entity("lunarthrall_plant_vine",5,0);middle.tags.weakvine=true;middle.tags.lunarthrall_plant_segment=true
c.enemies={head,vine,middle};mode,target=b:Brightshade(head);assert(mode=="attack" and target==middle)
vine.anim="atk";vine.frame=10;local data=b:Dodge(vine,false);assert(data.noattack and data.dist>=4.8)
assert(require("shadowself/control/navigation").Radius(vine)>=4.8)
-- Shell entry and emerge are blocked; idle resumes output.
local turtle=entity("slurtle");c.enemies={turtle}
for _,name in ipairs({"hide","hide_loop","emerge"}) do turtle.anim=name;assert(b:Shell(turtle)=="support" and b:AttackBlocked(turtle)) end
turtle.anim="idle";assert(not b:Shell(turtle) and not b:AttackBlocked(turtle))
-- Bishop responds from first charge frame and keeps the same melee radius.
local bishop=entity("bishop");bishop.anim="atk2_pre";bishop.frame=0;c.enemies={bishop};p.pos=Vector3(3,0,0);now=10
assert(b:Dodge(bishop,false),"begin at first charge frame");now=10.5;data=b:Dodge(bishop,false)
local q=data:fn();assert(math.abs(q:DistSq(bishop.pos)-p.pos:DistSq(bishop.pos))<.01,"bishop step follows same-radius arc")
p.pos=q;assert(math.abs(data:fn():DistSq(bishop.pos)-9)<.01,"bishop continues on the same radius")
-- Possessed varg flame is flanked; rear position opens attacks during breath.
local varg=entity("mutatedwarg");varg.anim="atk_breath_pre";c.enemies={varg};p.pos=Vector3(3,0,0)
assert(b:Dodge(varg,false).noattack);p.pos=Vector3(-3,0,0);assert(not b:Dodge(varg,false))
-- Last bee: separation -> normal ATTACK with staff -> actual queen target and weapon ownership.
package.loaded["shadowself/control/beequeen"]=nil
local queen=entity("beequeen");local guard=entity("beeguard",3,0);local ice=entity("icestaff")
c.enemies={queen,guard};c.bridge.wrappers={PreTheLoop={old=function() end}};c.h.ent=guard;c.gear={};items={ice};p.pos=Vector3(5,0,0);now=20
c.gear.Swap=function(self)
 local item=self.support_hand and self.support_hand.item or self.forced_weapon
 if item and held.hands~=item then A.Self(p,item,ACTIONS.EQUIP) end
 return not item or held.hands==item
end
c.gear.Mobile=function(self) return self.forced_weapon end
local Q=require("shadowself/control/beequeen")(c);Q:Tick();assert(c.blocked and c.gear.forced_weapon==ice,"idle queen range permits preparing the staff")
p.pos=Vector3(11,0,0);now=21;Q:Tick();assert(held.hands==ice and c.gear.forced_weapon==ice)
now=22;before=#commands;Q:Tick();assert(#commands==before+1 and commands[#commands].action==ACTIONS.ATTACK)
guard.tags.frozen=true;Q:Tick();assert(c.h.ent==queen and c.bridge.priority_target==queen and not c.blocked and not c.gear.forced_weapon)
c.bridge.chasing=true;c.travel.chasing=true;Q:Tick();assert(c.bridge.chasing and c.travel.chasing,"frozen guard must not reset pursuit every tick")
-- Real equipment ranking, with planar resistance and electric jelly.
require("shadowself/legacy/combat_equipment");local R=require("shadowself/legacy/registry")
local function weapon(name)
 local e=entity(name);e.tags.weapon=true
 e.replica.equippable={EquipSlot=function() return "hands" end}
 e.replica.inventoryitem={GetWalkSpeedMult=function() return 1 end,AttackRange=function() return 0 end}
 return e
end
local star,sword,night=weapon("nightstick"),weapon("sword_lunarplant"),weapon("nightsword")
local context={player=p,target=varg,enemies={varg},owner={perception={Inventory=function() return items end}}}
local gear=R.CombatEquipment(context);items={night,sword};held.hands=night
assert(gear:Weapon()==sword,"planar resistance favors physical plus planar output")
local damage=require("shadowself/control/weapon_damage")
assert(damage.Score(p,sword,38,varg)>damage.Score(p,night,68,varg))
items={night,star};context.enemies={varg,head,vine,middle,turtle};p._shadowself_combat_buffs=nil
assert(gear:Weapon()==night,"crowd no longer overrides damage ranking with morningstar")
p._shadowself_combat_buffs={electric_until=now+50};assert(gear:Weapon()==night,"active jelly excludes morningstar even for crowd")
now=now+51;assert(gear:Weapon()==night,"expired buff still uses damage ranking without the old crowd bonus")
p._shadowself_combat_buffs=nil
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: ranged/torch early ignition, bare/regrown crystal, attached bomb registry and moving escape, wave-wide attack hold, tired/wake/vine/shell, bishop arc flank, possessed varg, bee freeze/queen pursuit and real planar/jelly weapon ranking")
