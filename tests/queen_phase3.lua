-- 预计结束前1秒直穿回击 -> 守卫追回后等下一轮，不攻击守卫。
local savedN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
TUNING={BEEGUARD_SPEED=3,BEEQUEEN_DEAGGRO_DIST=60}
Vector3=function(x,y,z) local v={x=x,y=y,z=z};function v:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return v end
local function entity(prefab,x,z)
 local e={prefab=prefab,pos=Vector3(x,0,z),tags={},components={},replica={},anim="idle",frame=0,build="bee_guard_puffy_build",length=2}
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end,
 GetBuild=function() return e.build end,GetCurrentAnimationLength=function() return e.length end}
 return e
end
local queen=entity("beequeen",0,0);local bee=entity("beeguard",18,0);local p=entity("wilson",20,0)
local paused,stopped,attacks=0,0,0
local c={player=p,enemies={queen,bee},hazards={},observed={},snapshot={},gear={AttackRange=function() return 2 end},travel={}}
c.actions={SafePoint=function() return true end,Stop=function() stopped=stopped+1 end}
c.bridge={PauseAttack=function() paused=paused+1 end}
c.travel.BeginDodge=function(self) self.dodging=true end
c.Move=function(self,point,label) self.moved=point;self.status=label;self.blocked=true end
local q={c=c,queen=queen,anchor=queen.pos,phase=3};c.beequeen=q
q.Target=function(_,target) assert(target==queen);c.target=target;c.blocked=false end
q.ReleaseTravel=function() q.travelling=nil end
q.Strike=function() attacks=attacks+1;c.blocked=false;q.stage="strike";return true end
require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
TheWorld={state={}}
local D=require("shadowself/control/queendash");local Wave=require("shadowself/control/queenwave")
queen.anim="command2";queen.frame=18;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_pull" and c.moved.x>p.pos.x and c.moved.z==0)
queen.anim="command1";queen.frame=0;now=.1;D.Tick(q,queen,{bee},now)
queen.anim="command2";queen.frame=0;now=.2;D.Tick(q,queen,{bee},now)
queen.anim="command1";queen.frame=52;now=.3;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_pull","last command still has more than a second, keep pulling")
queen.frame=54;now=.333;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_return" and D.Dashing(bee) and c.moved.x==16 and c.moved.z==0,"return about one second early directly through still-boosted guard")
local Nav=require("shadowself/control/navigation")
assert(not Nav.Safe(c,c.moved,queen),"ordinary navigation still sees guard collision circle; only dedicated return allows this crossing")
assert(c.enemies[2]==bee,"crossing does not mutate shared threat list")
p.pos=Vector3(2,0,0);now=.4;D.Tick(q,queen,{bee},now)
assert(q.stage=="strike" and attacks==1 and c.target==queen,"arriving at queen immediately opens solo, even before boost visually ends")
bee.pos=Vector3(5,0,0);now=.5;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_wait" and c.blocked and paused==1 and stopped==1 and attacks==1,"guards catch up: stop output and space, not guard fighting or another old-wave pull")
bee.build="bee_guard_build";bee.pos=Vector3(12,0,0);now=.6;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_wait" and attacks==1,"normal-form guards returning never restart solo or pull before the next command")
bee.build="bee_guard_puffy_build";queen.anim="command2";queen.frame=18;now=1;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_pull" and attacks==1,"new actual boost starts a fresh straight pull cycle")
-- 缺少前两轮观察时，command3开始已在一秒窗口内，可直接返回。
local state={};Wave.Start(state);queen.anim="command3";queen.frame=0
local left=Wave.Remaining(state,queen);assert(math.abs(left-23/30)<.001 and left<Wave.LEAD)
-- 三阶段折返缓存：60个固定位置更新仅重新检查少数次直线路径。
local R=require("shadowself/control/queendashroute")
p.pos=Vector3(20,0,0);bee.pos=Vector3(18,0,0);q.dash_cycle={mode="return"};local cycle=q.dash_cycle
local oldSafe=Nav.Safe;local checks=0;Nav.Safe=function(...) checks=checks+1;return oldSafe(...) end
for i=1,60 do now=2+i/60;R.Return(q,cycle,queen,2.2,now) end
Nav.Safe=oldSafe;assert(checks<=6,"cached straight return should not inspect guard rings every frame, checks="..checks)
-- 实体以外的危险仍生效，不为穿蜂忽略地面蜂蜜。
c.hazards={{pos=Vector3(18,0,0),radius=1,honey=true}};cycle.route=nil;now=4
R.Return(q,cycle,queen,2.2,now)
assert(not cycle.route.point or cycle.route.point.z~=0 or cycle.route.point.x>=19,"honey in return lane must detour or hold")
-- 缓存路线期间也重试先前因busy未执行的赶路换装，使用Travel自己的限频队列。
local retries=0;c.travel.dodging=true;c.travel.UpdateDodge=function() retries=retries+1 end
R.Begin(q,cycle);assert(retries==1,"cached movement must retry an initially busy cane equip")
-- 实战home约53.9的卡住：在边缘换一段可通行直线，不提前穿回蜂群。
c.hazards={};queen.pos=Vector3(20,0,0);queen.anim="command2";queen.frame=12
p.pos=Vector3(53.9,0,0);bee.pos=Vector3(52,0,0);q.dash_cycle={mode="pull",was_dash=true,seen_dash=true,dir={x=1,z=0}}
now=10;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_pull" and c.moved:DistSq(q.anchor)<p.pos:DistSq(q.anchor) and D.Dashing(bee),"arena edge changes escape leg but must not return through still-boosted guards")
-- 等待远离场心时，在保留蜂群6码/蜂后8码间距的条件下向内回收空间。
p.pos=Vector3(50,0,0);bee.pos=Vector3(50,0,10);q.debug_bees={bee};q.dash_cycle={mode="wait",was_dash=false}
now=11;R.Wait(q,q.dash_cycle,queen,bee,now)
assert(c.moved:DistSq(q.anchor)<p.pos:DistSq(q.anchor) and c.moved:DistSq(bee.pos)>=36 and c.moved:DistSq(queen.pos)>=64,"safe wait recenters instead of accumulating outer-edge drift")
assert(q.dash_cycle.route.purpose=="recenter")
-- 四个原版血量阶段，后两段共享同一冲锋策略，没有另开第四套移动。
local prefab=read_source("prefabs/beequeen.lua")
assert(prefab:find("local PHASE2_HEALTH = .75",1,true) and prefab:find("local PHASE3_HEALTH = .5",1,true) and prefab:find("local PHASE4_HEALTH = .25",1,true))
p.pos=Vector3(20,0,0);queen.pos=Vector3(0,0,0);bee.pos=Vector3(18,0,0);queen.anim="command2";queen.frame=18
q.phase=4;q.dash_cycle=nil;now=12;D.Tick(q,queen,{bee},now)
assert(q.stage=="dash_pull","native health phase4 continues the same boosted-guard tactic")
require("shadowself/native").context=savedN
print("PASS: source-order wave timing, one-second early straight return through boosted guards, immediate queen output, catch-up spacing until new boost, no guard attacks, honey protection and 60-tick return path checks="..checks)
