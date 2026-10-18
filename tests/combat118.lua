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



-- Eye regrowth, not merely arm regrowth, ends ordinary-deer combat.
local deer=entity("mutateddeerclops");c.enemies={deer};c.h.ent=deer;deer.anim="stagger";b:Crystal(deer)
deer.anim="ice_grow";deer.frame=13;assert(b:Crystal(deer)=="attack" and b.crystal.eye_bare)
deer.anim="stagger_pst";deer.frame=100;b:Crystal(deer)
deer.anim="idle_loop";assert(b:Crystal(deer)=="attack","arm crystals with a bare eye do not cause another 9.5-unit retreat")
deer.anim="ice_grow_2";deer.frame=3;assert(b:Crystal(deer)=="move" and not b.crystal.eye_bare)
-- Actual fume event payload and child fallback cover missing spatial/parent lookup.
local events={};p.ListenForEvent=function(_,name,fn) events[name]=fn end
local bombs=require("shadowself/bombs");bombs.tracked=setmetatable({},{__mode="k"});p._shadowself_bomb_watch=nil;bombs.Bind(p)
local bomb=entity("sporebomb");bomb.entity.GetParent=function() return nil end
bomb.components.timer={GetTimeLeft=function() return 3.4 end};events.startfumedebuff(p,bomb)
p.pos=Vector3(7,0,0);assert(bombs.Near(p)[1]==bomb and bomb._shadowself_bomb_owner==p)
assert(#b:Zones({})==0 and not b.bomb_imminent,"head-attached bomb does not cause premature running")
bombs.tracked[bomb]=nil
local child=entity("sporebomb");p.children={[child]=true};assert(bombs.Near(p)[1]==child,"already-attached bomb found after takeover")
p.children=nil;bombs.tracked[child]=nil
-- Execute the real mechanisms tick: support movement is issued repeatedly, not a dormant zone.
events.startfumedebuff(p,bomb);bomb.components.timer.GetTimeLeft=function() return .4 end;c.enemies={};c.h.ent=nil
package.loaded["shadowself/control/mechanisms"]=nil
local Mechanisms=require("shadowself/control/mechanisms");local m=Mechanisms(c)
for i=1,8 do
 now=now+.1;c.moved=nil
 assert(m:Tick() and c.moved and c.moved:DistSq(p.pos)>1,"active bomb must issue a movement action every tick")
 p.pos=Vector3(p.pos.x+(c.moved.x-p.pos.x)*.15,0,p.pos.z+(c.moved.z-p.pos.z)*.15)
end
bombs.tracked[bomb]=nil;b.bomb_run=nil;b.bomb_imminent=nil;c.hazards={};b:Zones({})
-- Queen movement has a single gear owner; ending a specialist move cannot restore weapon mid-chase.
package.loaded["shadowself/control/beequeen"]=nil
local queen=entity("beequeen");c.enemies={queen};c.h.ent=queen;c.bridge.wrappers={PreTheLoop={old=function() end}}
local roles={};c.gear={AttackRange=function() return 2 end,Swap=function(_,role) roles[#roles+1]=role;return true end}
local Travel=require("shadowself/control/travel");c.travel=Travel(p,c.gear)
p.pos=Vector3(10,0,0);now=20
local Q=require("shadowself/control/beequeen")(c);Q:Anchor(queen)
Q:Move(Vector3(12,0,0),"test",queen);assert(c.bridge.chasing and c.travel.chasing and roles[1]=="move")
for i=1,5 do now=now+.3;Q:Strike(queen,p.pos,queen.pos,10) end
for _,role in ipairs(roles) do assert(role~="attack","queen release cannot equip weapon until supervisor ends pursuit") end
-- Ten guards choose sustained straight lure, not a 12-unit ring or guard farming.
local pack={queen};for i=1,10 do pack[#pack+1]=entity("beeguard",2+i*.1,0) end
c.enemies=pack;p.pos=Vector3(8,0,0);Q=require("shadowself/control/beequeen")(c);now=30
for _,x in ipairs({12,16,17}) do
 Q:Tick();assert(Q.late and Q.allow==queen and Q.stage=="lure")
 assert(math.abs(c.moved.z)<.01 and math.abs(c.moved.x-x)<.01,"late queen must keep one straight pull beyond old 12-unit bound")
 p.pos=c.moved;now=now+.2
end
Q:Tick();assert(Q.stage=="lure" and c.moved:DistSq(queen.pos)<=18^2,"at leash boundary keep a safe long leg, do not dive into an unseparated pack")
queen.replica.health={GetPercent=function() return 1 end};c.enemies={queen,pack[2]};Q:Tick();assert(Q.late and Q.allow==queen,"once ten guards confirm phase two, partial scan/unknown health cannot revert to clearing guards");queen.replica.health=nil
-- Antlion compares future arc room, and both blocked sides allow backing out.
local ant=entity("antlion");c.enemies={ant};c.h.ent=ant;p.pos=Vector3(3,0,0)
local routes=b.routes;c.hazards={{pos=Vector3(1.5,0,2.6),radius=1.6}}
local q=routes:AntPoint(ant);assert(q.z<0,"choose the clearer side instead of a fixed counterclockwise preference")
c.hazards={};routes.anttrail={Vector3(6,0,0)}
c.actions.SafePoint=function(_,q) return q.x>2.85 and math.abs(q.z)<.2 end
q=routes:AntPoint(ant);assert(q.x>=3 and math.abs(q.z)<.2 and not routes.ant_exit,"both arcs blocked uses ordinary local avoidance without a committed recovery route")
c.actions.SafePoint=function() return true end
-- Weak brightshade idle fallback cannot trigger hit/step rhythm.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.anim="tired_loop_large"
c.enemies={head};c.h.ent=head;p.pos=Vector3(2,0,0)
assert(not b:Dodge(head,{atkanim=head.anim,dist=8}),"ignore generic idle dodge while head vulnerable")
local pauses_before=pauses;for i=1,8 do assert(b:Tick(head)=="attack") end
assert(pauses==pauses_before,"vulnerable head alone does not schedule movement between hits")
-- Same-radius bishop arc exits actual mark circle without stepping away from boss.
local bishop=entity("bishop");bishop.anim="atk2_loop";c.enemies={bishop};p.pos=Vector3(3,0,0);now=50
local mark=entity("bishop_targeting_fx",3,0);b.entities={mark};routes.bishop=nil
for i=1,8 do
 local data=b:Dodge(bishop,false);q=data:fn();assert(math.abs(q:DistSq(bishop.pos)-9)<.001)
 p.pos=q;now=now+.03
end
assert(p.pos:DistSq(mark.pos)>=3.2^2,"arc actually exits marked damage circle")
-- Pair completion rather than a turning lane controls lunar dodge handoff.
local guardian=entity("alterguardian_phase2");p.pos=Vector3(9,0,0);c.enemies={guardian};c.h.ent=guardian
local ga,gb=entity("smallguard_alterguardian_projectile",4,0),entity("smallguard_alterguardian_projectile",4,3.5)
b.ghosts={ga,gb};b.moon_hold=true;c.hazards={}
for i=1,5 do q=b:MoonPair(guardian);assert(q and b.moon_pair.a==ga and b.moon_pair.b==gb);p.pos=q end
ga.anim="mutate";gb.anim="mutate";b:MoonPair(guardian);assert(not b.moon_pair)
b.moon_hold=nil
-- All four variants use shared bite timing. Only possessed variant actually plays breath states.
for _,name in ipairs({"warg","claywarg","gingerbreadwarg","mutatedwarg"}) do
 local wolf=entity(name);wolf.anim="atk";wolf.frame=10
 assert(b:Dodge(wolf,false).noattack,name.." bite dodge")
 wolf.frame=12+require("shadowself/control/nettiming").Frames(c);assert(not b:Dodge(wolf,false),name.." recovery after replication margin")
end
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: bare eye vs arm regrowth, fume event/child fallback and real bomb movement ticks, exclusive queen gear owner, ten-guard long straight pull, antlion clear-side/backtracking, continuous weak-head output, bishop circle exit, fixed lunar lane and four warg variants")
