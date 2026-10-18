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

-- A single circular-direction sidestep ends; a blocked arc reverses direction.
local ant=entity("antlion");ant.anim="cast_pre";c.enemies={ant};c.h.ent=ant;p.pos=Vector3(3,0,0)
local data=b:Dodge(ant,false);assert(data.exclusive and data.noattack)
local step=data:fn();assert(math.abs(math.sqrt(step:DistSq(ant.pos))-3)<.001);p.pos=step
assert(not b:Dodge(ant,false),"one safe sidestep ends the dodge and permits damage")
p.pos=Vector3(3,0,0);b.routes.sides[ant]=1;c.hazards={{pos=Vector3(3*math.cos(.5),0,3*math.sin(.5)),radius=1.2}}
b.routes.antlion=nil;data=b:Dodge(ant,false);local q=data:fn();assert(q.z<0 and math.abs(math.sqrt(q:DistSq(ant.pos))-3)<.001)
c.hazards={}
local pig=entity("daywalker");pig.anim="run_loop";local original={dist=8};assert(b:Dodge(pig,original)==original,"daywalker passes native table through unchanged")
pig.anim="atk3";local old={dist=5};assert(b:Dodge(pig,old)==old,"pounce uses native table without custom lateral override")
local tower=entity("vault_pillar_guard");tower.anim="atk_1";p.pos=Vector3(3,0,0);c.enemies={tower}
data=b:Dodge(tower,false);q=data:fn();assert(q.z~=0 and math.abs(math.sqrt(q:DistSq(tower.pos))-3)<.001)
p.pos=Vector3(-2,0,2);assert(not b:Dodge(tower,false),"rear is an attack opening")
-- Pre-spin immediately chooses a corridor without glass, rather than waiting for the loop.
local guardian=entity("alterguardian_phase2");guardian.anim="attk_spin_pre";p.pos=Vector3(3,0,0);c.enemies={guardian};c.h.ent=guardian
local glass=entity("alterguardian_phase2spike",9,0);glass.anim="spike_pre"
c.hazards=b:Zones({glass});data=b:Dodge(guardian,{dist=20});q=data:fn()
assert(data.exclusive and q.z~=0 and q:DistSq(glass.pos)>1.85^2)
assert(require("shadowself/control/navigation").Safe(c,q,guardian))
-- Remain outside attack range on one fixed lateral lane, without crossing ghost rows.
local ga,gb=entity("smallguard_alterguardian_projectile",4,0),entity("smallguard_alterguardian_projectile",4,3.5)
p.pos=Vector3(9,0,0);guardian.anim="attk_chop";guardian.frame=28;c.observed[guardian.GUID]={neutral=true}
c.hazards=b:Zones({ga,gb});b.entities={ga,gb};b:MoonHolding()
assert(not b:Dodge(guardian,{dist=40}))
q=b:MoonPair(guardian);assert(q and math.abs(q.x-9)<.01 and q.z~=0,"lateral lane stays outside attack range")
p.pos=q;now=.2;q=b:MoonPair(guardian);assert(q and b.moon_pair.a==ga and b.moon_pair.b==gb,"pair stays locked while both ghosts attack")
b.moon_hold=nil;b.moon_lane=nil;c.hazards={}
local deer=entity("mutateddeerclops");deer.anim="throw";deer.frame=30;p.pos=Vector3(8,0,0);c.enemies={deer};c.h.ent=deer;c.hazards={};b.icemarks={}
b:Crystal(deer);local fixed=c.moved;assert(fixed:DistSq(p.pos)>6.5^2)
p.pos=Vector3(8,0,1);deer.frame=40;b:Crystal(deer);assert(c.moved:DistSq(fixed)<.001,"throw exit cannot drift with player movement")
p.pos=Vector3(8,0,0);deer.anim="throw_2";deer.frame=30;b:Crystal(deer)
assert(c.moved.x<8 and c.moved:DistSq(p.pos)>6.5^2)
local rhino=entity("minotaur");local tent=entity("bigshadowtentacle",3,0);tent.anim="breach_loop";b.entities={tent};c.enemies={rhino};c.h.ent=rhino
for _,name in ipairs({"jump_atk_pre","jump_atk_loop","jump_atk_pst"}) do rhino.anim=name;rhino.frame=0;assert(b:Tick(rhino)=="attack",name) end
rhino.anim="idle";assert(b:Tick(rhino)=="move","bait only after leap ends")
local bomb=entity("sporebomb");bomb.components.timer={GetTimeLeft=function() return .8 end};assert(#b:Zones({bomb})==1)
bomb.components.timer.GetTimeLeft=function() return 1.4 end;assert(#b:Zones({bomb})==0)
package.loaded["shadowself/control/encounters"]=nil;local Enc=require("shadowself/control/encounters");local enc=Enc(c)
local walrus=entity("walrus");local opponent=p;walrus.replica.combat={GetTarget=function() return opponent end};walrus.anim="walk_loop";c.enemies={walrus};p.pos=Vector3(10,0,0);now=10
assert(enc:Tick(walrus)=="move");now=100;p.pos=Vector3(40,0,0);assert(enc:Tick(walrus)=="move","no timer/distance-only return")
opponent=nil;walrus.anim="abandon";assert(enc:Tick(walrus)=="move")
walrus.anim="walk_loop";assert(enc:Tick(walrus)=="support");now=100.3;assert(enc:Tick(walrus)=="attack")
-- Real action bridge carries the equipped staff in ordinary ATTACK, bypassing unrelated picker candidates.
package.loaded["shadowself/control/actions"]=nil;local RealA=require("shadowself/control/actions")
local staff=entity("icestaff");held.hands=staff;local invoked
BufferedAction=function(doer,target,action,item) return {doer=doer,target=target,action=action,invobject=item,rotation=0} end
p.components.playercontroller={ismastersim=true,DoAction=function(_,act) invoked=act end}
assert(RealA.Attack(p,walrus) and invoked.action==ACTIONS.ATTACK and invoked.invobject==staff)
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: one antlion sidestep, fan flank, early glass-free spin, fixed lateral lunar lane, full crystal blast, leap-before-bait, early bomb, real walrus target loss and staff ATTACK")
