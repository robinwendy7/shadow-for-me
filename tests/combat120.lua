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



-- Reproduce the actual scheduler contract from the crash log, not a mock Sleep.
local env=setmetatable({GetTime=function() return 0 end,GetStaticTime=function() return 0 end,GetTick=function() return 0 end,GetStaticTick=function() return 0 end,GetTickTime=function() return 1/30 end,require=function(n) if n=="class" then return Class end;return require(n) end},{__index=_G})
local load=assert(loadstring(read_source("scheduler.lua")));setfenv(load,env);load()
local Bridge=require("shadowself/control/combat");local bridge=Bridge(p);local tune={};bridge.tuning=tune;bridge.native=_G
local stopped=0;bridge.h={StopHitAndRun=function() stopped=stopped+1;env.KillThreadsWithID("test_native");tune.Cheatthread=nil end}
local task=env.StartThread(function()
 bridge:PauseAttack();assert(bridge.pause_requested and stopped==0)
 env.Sleep(1/30) -- Used to fail with scheduler.tasks[co] already removed.
end,"test_native")
bridge.thread=task;tune.Cheatthread=task;local co=task.co
local ok,why=coroutine.resume(co);assert(ok,why);assert(env.scheduler.tasks[co] and bridge.pause_requested)
local replayed=0;bridge.coordinator={blocked=true,last_point=Vector3(4,0,2)};local oldPos=POS_util;POS_util={GoToPoint=function(_,x,z) assert(x==4 and z==2);replayed=replayed+1 end}
bridge:PauseAttack();assert(stopped==1 and not bridge.thread and not env.scheduler.tasks[co],"supervisor removes sleeping attack task safely");assert(replayed==1 and bridge.coordinator.next_move>GetTime(),"deferred stop replays external escape before movement throttle");POS_util=oldPos
-- Weak-head refresh inside native coroutine is pure selection, never a movement/stop call.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.anim="tired_loop_large"
c.enemies={head};c.h.ent=head;c.brightshade_target=head;c.bridge.supervisor={};c.bridge.wrappers={PreTheLoop={old=function() end}}
c.gear.AttackRange=function() return 2 end;c.travel.dodging=true
local savedBright=b.Brightshade;b.Brightshade=function() error("native pulse must not call movement-capable boss dispatcher") end
require("shadowself/control/coordinator").NativePulse(c);assert(c.brightshade_target==head)
b.Brightshade=savedBright;c.travel.dodging=nil;c.brightshade_target=nil
-- Actual ground explosives and poison-cloud debuff remain different entities.
local bomb=entity("mushroombomb",1,0);bomb.anim="land";p.pos=Vector3(0,0,0);assert(#b:Zones({bomb})==0)
bomb.anim="grow2";bomb.AnimState.GetCurrentAnimationLength=function() return 2 end;bomb.frame=0;assert(#b:Zones({bomb})==0)
bomb.frame=40;assert(#b:Zones({bomb})==0,"grow2 must not block toad attacks")
bomb.prefab="mushroombomb_dark";bomb.anim="explode_pre";bomb.frame=24;assert(#b:Zones({bomb})==1)
local projectile=entity("mushroombomb_projectile");assert(#b:Zones({projectile})==0,"airborne mushroom is not a landed blast")
local cloud=entity("sporecloud");cloud.tags.sporecloud=true;assert(#b:Zones({cloud})==1)
-- Swept off-target lanes are seen even while the current target has another attack.
local target=entity("bishop",2,0);local rook=entity("rook",8,0);rook.anim="atk";rook.Transform.GetRotation=function() return 180 end
local incoming=require("shadowself/control/incoming");c.enemies={target,rook};c.h.ent=target;c.observed={[target.GUID]={dodge=true},[rook.GUID]={neutral=true}};c.hazards={}
local lane=incoming.Lane(c,rook);assert(incoming.Risk(lane,p.pos)>0)
local q=incoming.Point(c,c.enemies);assert(q and math.abs(q.z)>2 and incoming.Risk(lane,q)==0,"side rook is dodged before its current melee circle reaches us")
local king=entity("rabbitking_aggressive",8,0);king.anim="dropkick_loop";king.Transform.GetRotation=function() return 180 end
c.enemies={target,king};q=incoming.Point(c,c.enemies);assert(q and math.abs(q.z)>2,"rabbit king kick is observed during minion/other-target combat")
-- Pair locks remain, but the endpoint is strictly lateral and never closer to guardian.
local guardian=entity("alterguardian_phase2");local ga,gb=entity("smallguard_alterguardian_projectile",4,0),entity("smallguard_alterguardian_projectile",4,3.5)
c.enemies={guardian};c.h.ent=guardian;c.hazards={};p.pos=Vector3(9,0,0);b.ghosts={ga,gb};b.moon_hold=true;b.moon_pair=nil
q=b:MoonPair(guardian);assert(math.abs(q.x-9)<.01 and q:DistSq(guardian.pos)>=p.pos:DistSq(guardian.pos))
p.pos=q;q=b:MoonPair(guardian);assert(math.abs(q.x-9)<.01,"after aligning, wait for pair completion instead of walking toward boss")
ga.anim="mutate";gb.anim="mutate";b:MoonPair(guardian);b.moon_hold=nil
-- Second crystal throw never retreats outward while waiting for its lock.
local deer=entity("mutateddeerclops");deer.anim="throw_2";deer.frame=20;c.enemies={deer};c.h.ent=deer;p.pos=Vector3(8,0,0);c.moved=nil
assert(b:Crystal(deer)=="support" and not c.moved)
deer.frame=30;b.icemarks={};items={entity("firestaff")};b:Crystal(deer);assert(c.moved:DistSq(deer.pos)<p.pos:DistSq(deer.pos),"even with firestaff second exit stays on boss side of the impact")
b.crystal.eye_bare=true;deer.anim="atk";deer.frame=32;p.pos=Vector3(-2,0,3)
local normal={atkanim="atk",atk_start_frame=14,atk_stop_frame=35,point="player",update=false,angle=-80*math.pi/180,dist=6}
require("shadowself/native").context.HitAndRun={targetanimtable={deerclops={normal}}}
assert(b:Dodge(deer,false)==normal,"ordinary deer owns timing and aim")
deer.frame=36;assert(not b:Dodge(deer,false))
-- Honey forces an exit before attack/lure, and an unseparated ten-bee pack never opens melee.
package.loaded["shadowself/control/mechanisms"]=nil;local m=require("shadowself/control/mechanisms")(c)
local queen=entity("beequeen",-8,0);c.enemies={queen};c.h.ent=queen;p.pos=Vector3(0,0,0);c.hazards={{pos=p.pos,radius=2,honey=true}}
assert(m:Honey() and c.moved:DistSq(p.pos)>=2^2)
package.loaded["shadowself/control/beequeen"]=nil;queen.pos=Vector3(0,0,0);c.enemies={queen};c.hazards={};items={}
for i=1,10 do c.enemies[#c.enemies+1]=entity("beeguard",3+i*.1,0) end
c.Move=function(self,q,label) self.moved=q;self.status=label;self.blocked=true end
p.pos=Vector3(8,0,0);local Q=require("shadowself/control/beequeen")(c)
for i=1,20 do
 for _,guard in ipairs(c.enemies) do if guard.prefab=="beeguard" then guard.pos=Vector3(p.pos.x*.5,0,p.pos.z*.5) end end
 now=now+.2;Q:Tick();assert(Q.late and Q.stage=="lure" and c.blocked,"unseparated pack at tick "..i)
 p.pos=c.moved;assert(p.pos:DistSq(queen.pos)>7^2 and p.pos:DistSq(queen.pos)<=18^2,"leash at tick "..i)
end
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: actual scheduler self-pause/Sleep reproduction, pure weak-head pulse, distinct ground mushroom explosives, off-target rook/kick lanes, lateral-only pair lock, inward second crystal throw, complete-swipe hold, honey exit and persistent ten-guard lure")
