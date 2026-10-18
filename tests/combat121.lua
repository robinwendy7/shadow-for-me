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



-- Read the exact ordinary deer entry from the shipped engine instead of copying test constants.
local src=read_3014_dodge();local start=assert(src:find("addcreature('deerclops'",1,true));local finish=assert(src:find("\n\t})",start,true));local standard
local env=setmetatable({DEGREES=math.pi/180,addcreature=function(prefab,animation,calculate,first,last,aim)
 assert(prefab=="deerclops");standard=aim;standard.atkanim=animation;standard.atk_start_frame=first;standard.atk_stop_frame=last
end},{__index=_G})
local load=assert(loadstring(src:sub(start,finish+3)));setfenv(load,env);load()
require("shadowself/native").context.HitAndRun={targetanimtable={deerclops={standard}}}
local deer=entity("mutateddeerclops");c.enemies={deer};c.h.ent=deer;b.crystal={target=deer,eye_bare=true,bare=true}
deer.anim="atk"
for _,f in ipairs({14,20,35}) do deer.frame=f;assert(b:Dodge(deer,false)==standard,"ordinary data identity at frame "..f) end
for _,f in ipairs({0,13,36,50}) do deer.frame=f;assert(not b:Dodge(deer,false),"ordinary end/start timing at "..f) end
assert(standard.point=="player" and standard.update==false and standard.angle==-80*math.pi/180 and standard.dist==6)
-- Eye ignition animation immediately gives up the torch/staff, before stagger proper.
local staff=entity("firestaff");c.gear.forced_weapon=staff;b.crystal={target=deer,throws=2};now=10
for _,name in ipairs({"struggle_pre","struggle_loop","struggle_pst"}) do
 deer.anim=name;c.gear.forced_weapon=staff;local count=#commands
 assert(b:Crystal(deer)=="attack" and not c.gear.forced_weapon and #commands==count,name.." is melee handoff, not repeated ignition")
end
assert(not b.crystal.eye_bare,"ignition struggle is not falsely recorded as eye already shattered")
-- Active head with missing/stale retaliates tag cannot lock out visible coarse vine.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.anim="idle_large"
local vine=entity("lunarthrall_plant_vine",1,0);vine.tags.NOCLICK=true;vine.AnimState.GetBuild=function() return "lunarthrall_plant_vine_big" end
c.enemies={head,vine};c.h.ent=head;c.brightshade_target=head;p.pos=Vector3(2,0,0)
assert(not b:WeakHead())
local mode,picked=b:Brightshade(head);assert(mode=="attack" and picked==vine and not c.brightshade_target)
assert(not b:AttackBlocked(vine),"former weak-head lock is released before attacks reach the segment")
head.anim="tired_loop_large";mode,picked=b:Brightshade(vine);assert(picked==head and c.brightshade_target==head)
head.anim="idle_large";assert(not b:AttackBlocked(vine) and not c.brightshade_target)
mode,picked=b:Brightshade(head);assert(picked==vine,"recovered body returns to middle-cut phase")
-- Actual supervisor resumes attacks with growing mushrooms present, dodges only near fuse end.
local oldStart,oldSleep,oldKill,oldPaused=StartThread,Sleep,KillThreadsWithID,IsSimPaused
local Bridge=require("shadowself/control/combat");local tuning={};local h={};local starts,stops=0,0
local toad=entity("toadstool",2,0);local bomb=entity("mushroombomb",1,0);bomb.AnimState.GetCurrentAnimationLength=function() return 4 end
entities={toad,bomb};p.pos=Vector3(0,0,0);c.enemies={toad};c.target=toad;c.brightshade_target=nil;b.crystal=nil;b.moon_hold=nil;b.moon_pair=nil;c.hazards={}
h.ent=toad;h.GetClosestTarget=function() return toad end;h.GetAttackTargets=function() end;h.PreTheLoop=function() end;h.IsAttackPre=function() return false end
h.StartHitAndRun=function() starts=starts+1;tuning.Cheatthread={id=81,SetList=function() end} end
h.StopHitAndRun=function() stops=stops+1;tuning.Cheatthread=nil end
local n={HitAndRun=h,TUNING=tuning,ENT_util=require("shadowself/native").context.ENT_util,POS_util={GoToPoint=function() end},KEY_util={MoveKeyDown=function() return false end}}
require("shadowself/native").context=n
local pc=p.components.playercontroller;pc.DoAction=function() end;pc.IsHopping=function() return false end
c.h=h;c.gear={AttackRange=function() return 2 end,Weapon=function() return nil end,Swap=function() return true end}
c.Scan=function() end;c.HitRecovery=function() end
c.travel={BeginDodge=function() end,EndDodge=function() end}
local bridge=Bridge(p);bridge.native=n;bridge.tuning=tuning;bridge.h=h;bridge.coordinator=c;c.bridge=bridge
bridge.allowed=function() return true end;bridge.wrappers={PreTheLoop={old=h.PreTheLoop}}
package.loaded["shadowself/control/mechanisms"]=nil;c.mechanisms=require("shadowself/control/mechanisms")(c)
local routines={};StartThread=function(fn) local task={id=91,SetList=function() end};routines[task]=coroutine.create(fn);return task end
Sleep=function() coroutine.yield() end;KillThreadsWithID=function() end;IsSimPaused=function() return false end
bridge:Supervise()
for _,name in ipairs({"land","grow1","grow2"}) do bomb.anim=name;bomb.frame=80;now=now+.2;assert(coroutine.resume(routines[bridge.supervisor]));assert(starts==1 and stops==0 and bridge:OwnsThread(),"attacks continue through mushroom "..name) end
bomb.anim="explode_pre";bomb.frame=0;now=now+.2;assert(coroutine.resume(routines[bridge.supervisor]));assert(stops==0,"early explode_pre has not reached earliest random fuse")
bomb.frame=45;now=now+.2;assert(coroutine.resume(routines[bridge.supervisor]));assert(stops==1 and not bridge:OwnsThread(),"near earliest explosion suspends attacks to escape")
bomb.anim="explode";now=now+.2;assert(coroutine.resume(routines[bridge.supervisor]));assert(starts==2 and bridge:OwnsThread(),"finished explosion immediately permits attacking toad again")
-- 追击主目标的DoDodge必须在原线程，监督协程不能被整段躲避阻塞。
c.bosses=nil;c.encounters=nil;c.supplies=nil;c.crabking={Tick=function() end};toad.pos=Vector3(10,0,0)
local dodge_calls,checks,updates=0,0,0;local side=false
h.IsAttackPre=function() return {atkanim="atk"} end
h.DoDodge=function() dodge_calls=dodge_calls+1;coroutine.yield("supervisor_blocked") end
c.travel.UpdateDodge=function() updates=updates+1 end
c.mechanisms={c=c,Tick=function(self)
 checks=checks+1
 if side then return require("shadowself/control/mechanisms").Incoming(self) end
 return false
end}
bridge:PauseAttack();local before_start=starts;now=now+.2
local ok,reason=coroutine.resume(routines[bridge.supervisor]);assert(ok and reason~="supervisor_blocked" and dodge_calls==0 and starts==before_start+1 and bridge:OwnsThread(),"pursuit yields to native thread without blocking supervisor")
h.shadowself_dodging=toad;local before_stop=stops;now=now+.04
assert(coroutine.resume(routines[bridge.supervisor]));assert(stops==before_stop and updates==1,"long-distance active native dodge is not killed by pursuit/gear branch")
local rook=entity("rook",-7,0);rook.anim="atk_pre";rook.frame=15;c.enemies={toad,rook};side=true;c.moved=nil;now=now+.04
assert(coroutine.resume(routines[bridge.supervisor]));assert(checks>=3 and c.moved and math.abs(c.moved.z)>2 and not bridge:OwnsThread(),"actual off-target charge preempts an in-flight primary dodge on the next supervisor frame")
bridge.supervisor=nil;pc.DoAction=bridge.action_old
StartThread=oldStart;Sleep=oldSleep;KillThreadsWithID=oldKill;IsSimPaused=oldPaused
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: actual shipped ordinary-deer entry and exact frame window, struggle-pre weapon release, visual weak-head/middle recovery and actual supervisor attack/dodge/resume across mushroom growth and fuse")
