local savedTime,savedWorld,savedSim,savedNet=GetTime,TheWorld,TheSim,TheNet
local now=0;GetTime=function() return now end
TheNet={GetPing=function() return 35 end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
local id=95000
local function ent(name,x,z)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={},components={},anim='idle',frame=0}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e:ListenForEvent() end;function e:RemoveEventCallback() end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent('wilson',5);p.components.playercontroller={IsBusy=function() return false end}
local bone=ent('armorskeleton');bone.components.fueled={GetPercent=function() return .8 end};bone.components.cooldown={GetTimeToCharged=function() return 5 end}
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.BODY and bone end,GetNumSlots=function() return 15 end,GetItemInSlot=function() end}
local pig=ent('daywalker2');pig.anim='rummage_loop'
local box=ent('chest_mimic',18,18);local opened=false
box.replica.container={IsOpenedBy=function() return opened end,Close=function() opened=false end,GetItems=function() return {} end,IsEmpty=function() return true end}
local entities={pig,box};TheSim={FindEntities=function() return entities end}
local goal;local sent={};local key='shadowself/control/actions';local oldA=package.loaded[key]
package.loaded[key]={Items=function() return {} end,Stop=function() end,Scene=function(_,e,_,guard) sent[#sent+1]={entity=e,guard=guard} end}
local P=require('shadowself/control/arena_scrappig');local Route=require('shadowself/control/arena_reward_route')
local arena={running=true,wave=11,instance='pig095',generation=1,enemies={pig},bridge={},StopCombat=function() end,Say=function() end,
 encounters={Move=function(_,q) goal=q end,FindCenter=function() return Vector3(0,0,0) end}}
local context={player=p,enemies={pig},hazards={},actions={SafePoint=function() return true end},plan={arena=true,arena_center=function() return Vector3(0,0,0) end}}
local stage={player=p,boss=pig,context=context,arena=arena,buffs={Check=function() end},Observe=function() end}
arena.stage11=stage
local Rewards=assert(loadfile('scripts/shadowself/control/arena_rewards.lua'))();local reward=Rewards(stage,false);stage.reward=reward
assert(not Route.Near(reward,entities,box),'digging scrappig five units away no longer restarts perimeter patrol')
box.pos=Vector3(2,0,0);assert(Route.Near(reward,entities,box),'box inside digging body radius remains unsafe');box.pos=Vector3(18,0,18)
local shadow=ent('daywalker',5);assert(Route.Near(reward,{pig,shadow},box),'shadow pig and other live monsters keep their ordinary gate')
arena.healing={Safe=function(_,c) assert(#c.enemies==0 and #c.hazards==1);return true end,Path=function() return true end}
reward:Tick(entities);assert(#sent==1 and sent[1].guard() and not reward.reward_route,'real reward flow dispatches guarded opening while pig is digging')
pig.anim='laser_pre';assert(not sent[1].guard(),'new cannon windup invalidates delayed open before it can execute')
stage.finish=true;bone.components.cooldown.GetTimeToCharged=function() return 0 end
now=1.1;reward:Tick(entities)
assert(#sent==2 and sent[2].guard() and not (reward.reward_route and reward.reward_route.patrol),'observed ready shield cancels repeated seven-second patrol and permits actual cannon-time opening')
reward.opened=box;opened=true;goal=nil
assert(not P.Dodge(stage,entities) and opened and not goal,'ready shield continues container use through cannon without dodging')
pig.anim='throw';assert(not P.Dodge(stage,entities) and opened,'ready shield also permits opening during targeted junk throw')
bone.components.cooldown.GetTimeToCharged=function() return 5 end
pig.anim='laser_pre';assert(not sent[2].guard(),'shield consumption restores late opening threat validation immediately')
reward.reward_route=nil;reward.opened=box;opened=true;reward.pending={item=ent('lunar_seed')};local pending=reward.pending
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage11.lua'))()
assert(Stage.Tick(stage,entities)=='hold' and goal and not opened and reward.pending==pending and not stage.target,'real stage cancels container use for cannon but preserves outstanding transfer ACK')
assert(p:GetPosition():DistSq(goal)>=6^2 and math.abs(goal.z-p.pos.z)>=6,'cannon movement uses long lateral escape rather than a short backward step')
assert(pig.pos:DistSq(goal)>15^2,'tracking cannon escape also exits full beam range rather than circling in front of the muzzle')
pig.anim='throw';pig.frame=20;goal=nil
assert(P.Dodge(stage,entities) and goal,'observed targeted junk throw preempts looting before frame21')
pig.anim='idle';pig.frame=0;goal=nil
assert(not P.Dodge(stage,entities),'idle scrappig does not manufacture another attack or movement loop')
pig.anim='rummage_loop';box.pos=Vector3(-18,0,0);goal=nil
arena.healing.Path=function(_,_,q) return p.pos:DistSq(q)<=4.1^2 end
local approach=Rewards(stage,false);approach:Tick(entities)
assert(goal and p.pos:DistSq(goal)>.25^2 and not approach.reward_route,'blocked direct approach uses a safe short waypoint around the pile instead of restarting seven seconds')
assert(goal:DistSq(pig.pos)>3.5^2,'approach waypoint respects digging pig body clearance')
local oldWave=arena.wave;arena.wave=5;goal=nil
pig.anim='laser_pre';assert(not P.Dodge(stage,entities) and not goal,'scrappig override does not run in other waves');arena.wave=oldWave
pig.anim='rummage_pre';stage.pig_dig=nil;now=10
assert(P.AttackWindow(stage),'digging has an output window even with bone armor cooling')
now=10.8;assert(not P.AttackWindow(stage),'dig output stops with reserve for the next weapon windup')
pig.anim='laser_pre';assert(not P.AttackWindow(stage),'weapon windup immediately ends digging permission')
-- Exercise actual pig scheduler and attack gate with confirmed armor but cooling shield.
local R=require('shadowself/control/arena_late_runtime');local oldHealth,oldEquip=R.Health,R.Equip
R.Health=function() return 500 end;R.Equip=function() return true end
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
stage.Cleared=function() return true end;stage.route='lunar';stage.phase='pig_orbit';stage.reward=nil;stage.finish=nil
pig.anim='rummage_pre';stage.pig_dig=nil;now=20
assert(Finish.Pig(stage,entities)=='fight' and stage.phase=='pig_dig_attack' and Finish.Allowed(stage,pig),'scheduler and Allowed both permit reserved digging output while shield cools')
pig.anim='laser_pre';assert(not Finish.Allowed(stage,pig),'delayed attack cannot keep digging permission into laser preparation')
stage.phase='pig_four';assert(not Finish.Allowed(stage,pig),'ordinary four-hit authorization cannot revive a queued attack during cannon avoidance')
R.Health,R.Equip=oldHealth,oldEquip
-- Completed real looting starts withdrawal immediately, then observes follow vs pile.
stage.finish=true;stage.reward=Rewards(stage,false);reward=stage.reward
pig.anim='rummage_loop';pig.pos=Vector3(0,0,0);p.pos=Vector3(5,0,0);context.enemies={pig}
box.pos=Vector3(18,0,18);opened=true;arena.healing=nil;goal=nil;now=30
reward:Tick(entities);now=30.9;reward:Tick(entities)
assert(reward.visited['18:18'] and reward.retreat and goal and not opened,'confirmed empty box completion immediately closes and withdraws before another chest')
p.pos=goal;pig.pos=Vector3(.5,0,0);pig.anim='run_pre'
P.Dodge(stage,entities)
assert(not reward.retreat and reward.reward_route and reward.reward_route.patrol,'observed pursuit after actual separation returns to safe waiting instead of another unguarded box')
reward:Stop();p.pos=Vector3(5,0,0);pig.pos=Vector3(0,0,0);pig.anim='rummage_loop'
P.AfterBox(reward,entities);p.pos=goal;P.Dodge(stage,entities)
assert(not reward.retreat and not reward.reward_route,'observed return to digging ends withdrawal without an unnecessary seven-second patrol')
P.AfterBox(reward,entities);reward:Stop();assert(not reward.retreat,'stopping takeover releases post-box withdrawal ownership')
pig.prefab='daywalker';p.pos=Vector3(5,0,0);pig.pos=Vector3(0,0,0);pig.anim='idle';box.pos=Vector3(18,0,18)
stage.reward=Rewards(stage,false);local shadowReward=stage.reward
bone.components.cooldown.GetTimeToCharged=function() return 0 end;now=40;opened=false
Route.Begin(shadowReward,'shadow regression');shadowReward:Tick(entities)
assert(shadowReward.opened==box and sent[#sent].guard() and not (shadowReward.reward_route and shadowReward.reward_route.patrol),'shadow daywalker gets the same observed-shield opening window instead of endless seven-second patrol')
opened=true;shadowReward.pending={kind='awaiting_inventory'};bone.components.cooldown.GetTimeToCharged=function() return 5 end;goal=nil
assert(Route.Tick(shadowReward,entities) and not opened and shadowReward.pending and shadowReward.reward_route.patrol and goal,'shadow shield consumption aborts open use, retains ACK and moves toward perimeter')
shadowReward:Stop()
-- Real rabbit state: a second minion in its damage frame interrupts bait recovery.
local Rabbit=require('shadowself/control/arena_rabbit');local king=ent('rabbitking_aggressive',12)
local a,b,spare=ent('rabbitkingminion_bunnyman',2),ent('rabbitkingminion_bunnyman',1,1),ent('rabbitkingminion_bunnyman',10)
p.pos=Vector3(0,0,0);a.anim='atk';a.frame=25;b.anim='atk';b.frame=13
local roster={king,a,b,spare};local c={player=p,enemies=roster,gear={},actions={SafePoint=function() return true end},bridge={PauseAttack=function() end},
 plan={arena=true,arena_wave=function() return 5 end,arena_entities=function() return roster end,arena_center=function() return Vector3(0,0,0) end}}
local owner={c=c,Release=function() end,Target=function(_,e) return e end,Move=function(_,q) goal=q;return 'move' end,Away=function() return 'move' end}
local rabbit=Rabbit(owner);rabbit.king=king;rabbit.phase='bait';rabbit.spare=spare;rabbit.bait_target=a;rabbit.bait_seen=true
goal=nil;assert(rabbit:Tick()=='move' and rabbit.phase=='bait' and goal,'other minion damage frame prevents an early turn toward recovered bait target')
p.pos=goal;b.anim='idle'
assert(rabbit:Tick()=='attack' and rabbit.phase=='adds','once all actual strike windows finish, resume attack rather than another four-second patrol')
rabbit.target=a;a.anim='idle';b.pos=Vector3(.5,0,0);p.pos=Vector3(0,0,0)
assert(rabbit:Tick()=='attack' and rabbit.target==a,'nearer second minion cannot steal focus before the selected minion dies')
a.anim='atk';a.frame=25;rabbit.bait_recovery=nil;rabbit.recovery_frame=nil
assert(rabbit:Tick()=='attack' and rabbit.phase=='adds' and rabbit.target==a,'already-finished strike resumes output instead of another full patrol')
a.frame=2
assert(rabbit:Tick()=='move' and rabbit.phase=='kite' and rabbit.bait_target==a,'real next strike restarts four-second bait cycle while preserving the same kill focus')
rabbit.phase='bait';rabbit.bait_seen=true;rabbit.bait_target=a;p.pos=Vector3(0,0,0);a.frame=13
assert(rabbit:Tick()=='move' and rabbit.phase=='bait','exact damage frame is not mistaken for a safe recovery')
rabbit:Stop()
package.loaded[key]=oldA;GetTime,TheWorld,TheSim,TheNet=savedTime,savedWorld,savedSim,savedNet
print('PASS: digging box gate and actual opening, body/other-monster safety, cannon late cancellation and long lateral dodge, pending inventory preservation, reserved cooldown digging output, multi-minion simultaneous damage frame and immediate recovery attack')
