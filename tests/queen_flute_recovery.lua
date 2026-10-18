-- 日志复现回归：吹奏前摇受击、中断空等、并发换装、战吼唤醒与零距离目标。
local oldA=package.loaded["shadowself/control/actions"]
local oldN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
TUNING={BEEQUEEN_HIT_RANGE=6,BEEQUEEN_SPEED=4,BEEGUARD_SPEED=3,BEEGUARD_ATTACK_RANGE=1.5,PANFLUTE_SLEEPRANGE=15}
EQUIPSLOTS={HANDS="hands"};ACTIONS={PLAY={},ATTACK={}}
local function vec(x,z) local v={x=x,y=0,z=z};function v:DistSq(p) return (self.x-p.x)^2+(self.z-p.z)^2 end;return v end
Vector3=function(x,y,z) return vec(x,z) end
local function ent(prefab,x,z)
 local e={prefab=prefab,GUID=x*100+z,tags={},pos=vec(x,z),frame=0,anim="idle",components={},replica={}}
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent("wilson",10,0);local queen=ent("beequeen",0,0);local bee=ent("beeguard",15,0);local flute=ent("panflute",0,1)
local busy=false;local held;local plays,moves,stops,pauses=0,0,0,0
p.replica.inventory={GetEquippedItem=function() return held end}
p.components.playercontroller={IsBusy=function() return busy end}
TheWorld={state={}};TheNet={GetPing=function() return 0 end}
local c={player=p,enemies={queen,bee},hazards={},observed={},snapshot={},gear={},travel={},bridge={}}
c.actions={SafePoint=function() return true end,Stop=function() stops=stops+1 end}
c.Latency=function() return .1 end;c.bridge.PauseAttack=function() pauses=pauses+1 end
c.travel.EndDodge=function() error("flute handoff must not trigger weapon restoration") end
c.Move=function(self,v,label) assert(v:DistSq(p.pos)>.15);moves=moves+1;self.point=v;self.blocked=true;self.status=label end
c.travel.BeginDodge=function() end
local q={c=c,queen=queen,phase=2,stage="flute",anchor=queen.pos};c.beequeen=q
q.Target=function() c.blocked=false end
q.Move=function(_,v,label) assert(v:DistSq(p.pos)>.15,"must actually move, not target current position");moves=moves+1;c.point=v;c.blocked=true;c.status=label end
q.Strike=function() c.blocked=false;q.stage="strike";return true end
q.Lure=function() q.stage="lure" end
package.loaded["shadowself/control/actions"]={Self=function() plays=plays+1;p.anim="flute";busy=true;return true end}
require("shadowself/native").context={POS_util={GoToPoint=function() moves=moves+1 end},ENT_util={GetAnimation=function(_,e) return e.anim end}}
local F=require("shadowself/control/queenflute")
local S=require("shadowself/control/queenflutesafety")
local function reset()
 F.Reset(q);q.spawn_wait=nil;c.gear={};c.hazards={};q.stage="flute";q.travelling=nil
 p.pos=vec(10,0);p.anim="idle";queen.anim="idle";queen.frame=0;bee.pos=vec(15,0);bee.anim="idle";busy=false;now=now+5
end
local function tick() return F.Tick(q,queen,{bee},flute,now) end
reset();p.pos=vec(4,0);queen.anim="atk";queen.frame=10;local before=plays;tick()
assert(plays==before and moves>0 and c.blocked,"queen windup preempts unsafe full-coverage PLAY")
reset();bee.pos=vec(11,0);before=plays;tick();assert(plays==before and c.point:DistSq(p.pos)>.15,"nearby awake guard forbids a standing cast")
reset();before=plays;tick();assert(plays==before+1 and q.flute_cycle.pending and c.gear.action_hold and pauses>0 and stops>0)
require("shadowself/legacy/combat_equipment");local R=require("shadowself/legacy/registry")
local gear=R.CombatEquipment(c);gear.action_hold=c.gear.action_hold
assert(gear:Swap("move",{})==false and gear:Swap("attack",{})==false,"actual gear gate cannot emit either equip during PLAY")
now=now+.7;p.anim="hit";busy=true;F.Interrupt(c,"attacked:beeguard")
assert(not q.flute_cycle.pending and not c.gear.action_hold,"actual damage callback cancels pending and releases gear immediately")
before=moves;tick();assert(moves>before and plays>0,"next tick moves to escape instead of waiting four seconds")
reset();tick();now=now+.7;p.anim="run_loop";busy=false;tick()
assert(not q.flute_cycle.pending and not c.gear.action_hold,"aborted player animation cancels old PLAY")
reset();tick();now=now+.1;bee.pos=vec(11,0);bee.anim="atk";bee.frame=0;tick()
assert(not q.flute_cycle.pending,"new guard windup before sleep settles cancels into movement")
reset();queen.anim="screech";queen.frame=30;before=plays;tick();assert(plays==before,"wait past final frame34 soldier wake")
queen.frame=35;tick();assert(plays==before+1,"frame35 plus one-second PLAY finishes after queen no-sleep release")
now=now+1;F.OnAction(c,{action=ACTIONS.PLAY});assert(q.flute_cycle.performed==now)
 F.OnAction(c,{action={action=ACTIONS.PLAY}});assert(q.flute_cycle.performed==now)
 queen.anim="sleep_loop";bee.anim="sleep_loop";tick()
assert(q.flute_cycle.pending and q.flute_cycle.confirmed and c.gear.action_hold,"real effect still waits for player's busy release")
bee.anim="sleep_pst";busy=false;now=now+.1;tick()
assert(not q.flute_cycle.solo and c.blocked,"a wake before handoff invalidates previously confirmed sleep")
reset();tick();now=now+1;F.Performed(c);queen.anim="sleep_loop";bee.anim="sleep_loop";busy=false;tick()
assert(q.flute_cycle.solo and not c.blocked and not c.gear.action_hold,"current full sleep restores queen attacks and releases equip lock")
queen.anim="idle";now=now+.2;before=plays;tick();assert(plays==before and not c.blocked,"attacking queen awake does not waste another flute while guard sleeps")
reset();c.gear.pending={item=flute,role="move",untiltime=now+1.2,senttime=now};held=nil;before=plays;tick()
assert(plays==before and not q.flute_cycle.pending,"wait for previously submitted equip before PLAY")
held=flute;tick();assert(plays==before+1 and not c.gear.pending,"acknowledged hand releases exactly one PLAY")
now=now+.2
local Co=require("shadowself/control/coordinator")
Co.Move(c,vec(14,4),"蜂后 · 先走出减速蜂蜜")
assert(not q.flute_cycle.pending and not c.gear.action_hold,"actual movement entry cancels PLAY before navigation")
reset();tick();F.Reset(q);assert(not q.flute_cycle and not c.gear.action_hold,"phase/queen change cannot leave lock latched")
-- 0.12.8实战回归：安全余量足够但远处守卫未被覆盖，不能奖励继续远离。
reset();q.flute_cycle={};p.pos=vec(15.2,0);bee.pos=vec(-8,0);before=plays
local initial=S.Coverage(p.pos,queen,{bee},15)
local point=S.Point(q,queen,{bee},vec(12.2,0),now,14.4)
assert(point and S.Coverage(point,queen,{bee},15)<initial,"safe route must shrink missing coverage, rather than orbit at 15 units")
local reached=false
for i=1,25 do
 c.point=nil;tick()
 if plays>before then reached=true;break end
 assert(c.point,"reachable coverage must produce progress")
 p.pos=c.point;now=now+.2
end
assert(reached and F.Covered(p.pos,queen,{bee},15),"multi-tick fixed roster converges to actual PLAY, not endless safe walking")
-- 再通过实际Queen.Move的边界/导航选点验证，不只验证一个移动桩。
local oldMove=q.Move;local oldCMove=c.Move
q.Move=require("shadowself/control/beequeen").Move;q.late=true
c.travel.BeginDodge=function() end
c.Move=function(self,v,label) self.point=v;self.blocked=true;self.status=label end
reset();q.flute_cycle={};p.pos=vec(15.2,0);bee.pos=vec(-8,0);before=plays;reached=false
for i=1,25 do
 c.point=nil;tick()
 if plays>before then reached=true;break end
 assert(c.point and c.point:DistSq(p.pos)>.15,"actual queen route must make coverage progress")
 p.pos=c.point;now=now+.2
end
assert(reached,"actual Queen.Move and safety selector converge to PLAY together")
q.Move=oldMove;c.Move=oldCMove
-- 日志162.533已结算，162.667动画不同/蜂后仍spawn，守卫已睡：不可误判失败。
reset();tick();now=now+1;F.OnAction(c,{action=ACTIONS.PLAY})
queen.anim="spawn";bee.anim="sleep_pre";p.anim="idle";busy=true;tick()
assert(q.spawn_wait and q.stage=="spawn_wait" and not q.flute_cycle and c.blocked,"spawn preempts old PLAY handoff; wait for the entire new batch")
busy=false;now=now+.2;tick();assert(q.spawn_wait and c.blocked,"do not attack or blow flute during spawning")
queen.anim="idle";now=now+.5;tick();assert(not q.spawn_wait,"release only after spawn animation and roster settle")
-- 日志171.733推测性追击不该中断已有吹奏，只有真实atk前摇可抢占。
reset();tick();now=now+.1;bee.pos=vec(11,0);bee.anim="walk_loop";tick()
assert(q.flute_cycle.pending,"moving closer alone does not cancel a committed cast")
bee.anim="atk";bee.frame=0;tick();assert(not q.flute_cycle.pending,"actual incoming strike still preempts before frame30")
-- 中间点规划限频：完整Safety.Point每秒不超过6次，但新攻击当帧使缓存失效。
reset();p.pos=vec(15.2,0);bee.pos=vec(-8,0)
local original=S.Point;local plans=0
S.Point=function(...) plans=plans+1;return original(...) end
for i=1,60 do now=now+1/60;tick() end
assert(plans<=6,"60 ticks must reuse a safe midpoint path; plans="..plans)
local previous=plans;queen.anim="atk";queen.frame=1;p.pos=vec(4,0);tick()
assert(plans>previous and c.blocked,"new queen windup invalidates cached standing route immediately")
S.Point=original
print("PASS: phase2 60-tick midpoint full plans="..previous.."; new windup invalidates cache immediately; spawn blocks PLAY until animation/roster settle")
package.loaded["shadowself/control/actions"]=oldA;require("shadowself/native").context=oldN
print("PASS: phase2 unsafe queen/guard window, cast lock vs actual gear, hit and animation/incoming/movement cancellation, immediate escape, screech timing, fresh all-sleep handoff, prior equip ack, cleanup")
