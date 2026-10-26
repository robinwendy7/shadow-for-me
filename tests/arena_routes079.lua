local oldWorld,oldTime=TheWorld,GetTime
local oldNav=package.loaded['shadowself/control/navigation'];local oldA=package.loaded['shadowself/control/actions']
local now=0;GetTime=function() return now end
local function entity(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),replica={},rotation=0,anim='idle',frame=0}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.prefab=='junk_pile_big' and 3.6 or self.prefab=='wilson' and .5 or 1 end
 e.Transform={GetRotation=function() return e.rotation end}
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local blocked,upper=false,false
TheWorld={Map={IsPassableAtPoint=function(_,x,_,z) return not blocked and (not upper or z<=0) end,IsOceanAtPoint=function() return false end},
 Pathfinder={IsClear=function() return true end}}
local player=entity('wilson',20);local pile=entity('junk_pile_big');local other=entity('junk_pile_big',25)
local boss=entity('daywalker2');boss.replica.combat={GetAttackRangeWithWeapon=function() return 40 end}
local center=Vector3(0,0,0);local goal;local stops=0
local arena={player=player,bridge={},encounters={FindCenter=function() return center end,Move=function(_,q) goal=q end}}
function arena:StopCombat() end;function arena:Say() end
local s={player=player,arena=arena,boss=boss,context={player=player,enemies={boss},hazards={}}}
package.loaded['shadowself/control/navigation']={Safe=function() return false end,Select=function() error('generic escape must never own this ring') end}
package.loaded['shadowself/control/actions']={Stop=function() stops=stops+1 end}
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
for i=1,30 do
 now=now+.2;goal=nil
 assert(Finish.Orbit(s,{other,pile})=='hold' and goal,'cannon static range and rejected generic Nav.Safe cannot stop dedicated junk ring')
 local before=player.pos
 for j=0,20 do
  local q=Vector3(before.x+(goal.x-before.x)*j/20,0,before.z+(goal.z-before.z)*j/20)
  assert(q:DistSq(center)>4.1^2,'approach and short arc never cross central junk collision')
 end
 player.pos=goal
 if i>=7 then assert(math.abs(math.sqrt(goal:DistSq(center))-4.4)<.001,'all later legs remain at central pile edge rather than arena perimeter') end
end
assert(s.junk_center:DistSq(pile.pos)<.001,'select central crumbling junk pile, never first noncentral pile in scan')
player.pos=Vector3(4.4,0,0);s.junk_side=1;upper=true;Finish.Orbit(s,{pile})
assert(goal.z<0,'terrain obstruction reverses on the same central ring')
blocked=true;Finish.Orbit(s,{pile});Finish.Orbit(s,{pile})
assert(stops==1,'physically blocked ring stops once and replans without generic outside escape')
package.loaded['shadowself/control/navigation']=oldNav;package.loaded['shadowself/control/actions']=oldA
blocked=false;upper=false
-- 实际鲨鱼Prepare入口和同一绕背规划，模拟6码/秒每帧移动。
local R=require('shadowself/control/sharkroute');local p=entity('wilson',1.8);local shark=entity('sharkboi');shark.anim='atk1'
local c={player=p,enemies={shark},hazards={},observed={},plan={arena=true,arena_wave=function() return 7 end},
 actions={SafePoint=function() return true end},snapshot={},bridge={PauseAttack=function() end},
 travel={BeginDodge=function() end,EndDodge=function() end}}
function c:Move(q) self.moved=q end
local b=require('shadowself/control/bosses')(c)
assert(R.Prepare(b,shark)=='move','actual swipe immediately owns movement before native attack loop can finish another swing')
for f=2,16 do
 shark.frame=f
 local data=R.Dodge(c,shark,false);assert(data and data.noattack)
 local q=data:fn();local d=math.sqrt(p.pos:DistSq(q));local step=math.min(.2,d)
 if d>0 then p.pos=Vector3(p.pos.x+(q.x-p.pos.x)*step/d,0,p.pos.z+(q.z-p.pos.z)*step/d) end
 assert(p.pos:DistSq(shark.pos)>1.5^2,'swipe route does not chord through shark physics')
end
assert(not R.SwipeDanger(c,shark,p.pos),'early close-range orbit exits actual forward-offset swipe before frame16 at simulated6-speed')
p.pos=Vector3(4.7,0,0);shark.frame=0
assert(R.SwipeDanger(c,shark,p.pos),'logged4.7 forward distance is still inside real swipe geometry')
local far=R.SwipePoint(c,shark)
assert(not R.SwipeDanger(c,shark,far) and far:DistSq(shark.pos)>p.pos:DistSq(shark.pos),'far front position exits actual hit circle rather than diving inward to1.8')
GetTime,TheWorld=oldTime,oldWorld
print('PASS: central-only junk approach/ring despite generic cannon radius, collision-safe legs, central prefab selection, terrain reversal and bounded stop; shark early ownership/frame16 motion and real4.7-range swipe geometry')
