local saved={world=TheWorld,sim=TheSim,time=GetTime,net=TheNet}
local now=0;GetTime=function() return now end;TheNet={GetPing=function() return 30 end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},
 Pathfinder={IsClear=function() return true end}}
local function ent(name,x,z,radius)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),radius=radius or .5,anim='idle',frame=0,replica={}}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius end
 e.AnimState={IsCurrentAnimation=function(_,n) return n==e.anim end,GetCurrentAnimationFrame=function() return e.frame end,
  SetMultColour=function() end,GetMultColour=function() return 1,1,1,1 end}
 return e
end
local p=ent('wilson',5,0);p.replica.inventory={GetEquippedItem=function() end}
local ant=ent('antlion',0,0,4);local entities={}
TheSim={FindEntities=function() return entities end}
local c={player=p,enemies={ant},hazards={},observed={},snapshot={},h={ent=ant},
 gear={AttackRange=function() return 2 end},actions={SafePoint=function() return true end},
 travel={BeginDodge=function() end,EndDodge=function() end},bridge={PauseAttack=function() end}}
function c:Latency() return .03 end;function c:Speed() return 7.5 end
function c:Move(q) self.moved=q end
local Boss=require('shadowself/control/bosses');local b=Boss(c);c.bosses=b
local planner=require('shadowself/control/antnavigation');local routes=b.routes
-- Multiple casts retain the same direction and radius instead of spiralling outward.
for cycle=1,12 do
 ant.anim='cast_pre';ant.frame=0
 local start=p.pos;local data=routes:Dodge(ant,false);assert(data and data.noattack)
 for i=1,30 do
  local q=data:fn()
  assert(math.abs(math.sqrt(q:DistSq(ant.pos))-5)<.001,'every waypoint remains on the antlion ring')
  assert(p.pos:DistSq(q)<=1.1^2,'movement looks ahead far enough for actual update timing without a long chord through the body')
  assert(planner.Corridor(c,p.pos,q,ant),'executed segment has a clear corridor')
  p.pos=q;now=now+1/30
  data=routes:Dodge(ant,false)
  if not data then break end
 end
 assert(not data and p.pos:DistSq(start)>1.7^2,'complete one actual sidestep and immediately restore attacking')
 ant.anim='idle';assert(not routes:Dodge(ant,false))
end
-- 实际坐标更新会超过0.36码分段，不会每帧精确落在路径节点上。
p.pos=Vector3(5,0,0);routes.antlion=nil;routes.ant_path=nil;ant.anim='cast_pre';ant.frame=0
local start=p.pos;local data=routes:Dodge(ant,false);local completed=false
for tick=1,20 do
 if not data then completed=true;break end
 local q=data:fn();assert(q,'open arena always has an actual escape point')
 local theta=math.atan2(p.pos.z,p.pos.x);local delta=(math.atan2(q.z,q.x)-theta+math.pi)%(2*math.pi)-math.pi
 theta=theta+(delta<0 and -1 or 1)*(.75/5) -- 7.5码/s、0.1秒一次的实际推进。
 p.pos=Vector3(5*math.cos(theta),0,5*math.sin(theta));now=now+.1;ant.frame=math.min(34,tick*3)
 data=routes:Dodge(ant,false)
end
assert(completed and p.pos:DistSq(start)>1.9^2,'overshot waypoints progress around the ring and release attacks instead of ping-ponging')
assert(routes.antlion.lock_origin and p.pos:DistSq(routes.antlion.lock_origin)>1.9^2,'cast exit clears the actual frame-three lock position rather than only the original frame-zero point')
-- A new spike in a later segment invalidates the whole route before it is reached.
p.pos=Vector3(5,0,0);routes.sides[ant]=-1;routes:AntPoint(ant)
local future=routes.ant_path.goal
c.hazards={{pos=future,radius=.6}}
local q=routes:AntStep(ant)
assert(q.z>0 and routes.sides[ant]==1,'a newly blocked clockwise route switches to the clear counterclockwise ring')
c.hazards={}
-- A spike beneath the player permits a monotone exit rather than a stationary dodge.
c.hazards={{pos=p.pos,radius=1.2}}
routes:AntPoint(ant);assert(routes.ant_path,'underfoot spike still permits a circular exit')
for i=1,10 do
 local q=routes:AntStep(ant)
 assert(planner.Corridor(c,p.pos,q,ant),'underfoot escape never moves deeper into the spike')
 p.pos=q
end
assert(require('shadowself/control/navigation').Risk(c,p.pos,ant)==0,'actual arc exits the underfoot spike')
-- Both circular directions are sealed; follow a real narrow outward passage before rejoining the ring.
p.pos=Vector3(5,0,0);c.hazards={}
TheWorld.Map.IsPassableAtPoint=function(_,x,_,z) return x>=7.5 or math.abs(z)<.2 end
routes:AntPoint(ant)
assert(routes.ant_path and routes.ant_path.kind=='detour','two sealed rings select the existing connected local graph instead of standing still')
local exit=routes:AntStep(ant)
assert(exit.x>p.pos.x and planner.Corridor(c,p.pos,exit,ant),'detour follows the open neck and never cuts across its walls')
TheWorld.Map.IsPassableAtPoint=function() return true end
-- Sand spike impact is pst frame 2, and mature spikes/blocks remain obstacles.
c.hazards={};local tall=ent('sandspike_tall',7,0);local block=ent('sandblock',9,0)
entities={tall,block};local M=require('shadowself/control/mechanisms');local m=M(c)
tall.anim='tall_pre';m:Scan();local pre=m.zones[1].radius
tall.anim='tall_pst';tall.frame=2;m:Scan()
assert(m.zones[1].radius==pre and m.zones[1].radius>=1.6,'pst impact remains in the damage exclusion zone')
tall.frame=20;m:Scan()
assert(m.zones[1].radius<pre and m.zones[1].radius>=1.3,'mature spike shrinks to collision clearance, never disappears from routing')
assert(m.zones[2].source==block and m.zones[2].radius>=1.8,'sandblock collision remains represented even when visually hidden')
tall.anim='tall_break';block.anim='block_break';m:Scan();assert(#m.zones==0,'destroyed spike/block no longer blocks the ring')
-- Idle return to melee cannot walk straight through a fresh spike pile.
p.pos=Vector3(8,0,0);ant.anim='idle';c.mechanisms={zones={{pos=Vector3(7,0,0),radius=1.5}}}
assert(routes:AntRecover(ant)=='move' and c.moved,'blocked melee corridor follows the ring instead of attacking through spikes')
c.mechanisms=nil;c.hazards={};assert(not routes:AntRecover(ant),'clear approach immediately releases movement ownership')
TheWorld,TheSim,GetTime,TheNet=saved.world,saved.sim,saved.time,saved.net
print('PASS: antlion twelve casts without radial drift; sampled body-safe circle; future spike reversal; underfoot escape; pst impact and mature obstacle lifetime; safe attack reentry')
