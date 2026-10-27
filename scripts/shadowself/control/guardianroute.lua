-- 仅第九关：柱后路线输出已验证的短腿，禁止再经通用Nav.Select改写。
local Nav=require("shadowself/control/navigation")
local R={}
function R.Aligned(boss,pillar,goal)
 local a,b= boss:GetPosition(),goal;local q=pillar:GetPosition()
 local x,z=b.x-a.x,b.z-a.z;local d=x*x+z*z
 if d<.01 then return false end
 local t=((q.x-a.x)*x+(q.z-a.z)*z)/d
 local margin=pillar:GetPhysicsRadius(0)+boss:GetPhysicsRadius(0)-.3
 return t>0 and t<1 and (q.x-a.x-x*t)^2+(q.z-a.z-z*t)^2<math.max(.2,margin)^2
end
function R.Point(c,goal,pillar,boss)
 local p=c.player:GetPosition();local map=TheWorld and TheWorld.Map
 local columns=TheSim:FindEntities(p.x,0,p.z,12,{"charge_barrier"})
 local obstacles={boss};for _,e in ipairs(columns) do
  if e:IsValid() and e:HasTag("charge_barrier") and not e:HasTag("NOBLOCK") and not e:HasTag("INLIMBO") and not e:HasTag("FX")
   and (e:GetPosition().y or 0)<.5 then obstacles[#obstacles+1]=e end
 end
 local function pass(q)
  if not Nav.Safe(c,q,boss) then return false end
  local n=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.25))
  for i=1,n do
   local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
   if map and (not map:IsPassableAtPoint(v.x,0,v.z) or map:IsOceanAtPoint(v.x,0,v.z)
    or map.IsPointNearHole and map:IsPointNearHole(v)) then return false end
   for _,e in ipairs(obstacles) do
    local r=e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.2;local ep=e:GetPosition()
    if v:DistSq(ep)<r*r and v:DistSq(ep)<=p:DistSq(ep)+.01 then return false end
   end
  end
  return not TheWorld or not TheWorld.Pathfinder or TheWorld.Pathfinder:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false})
 end
 local function step(q)
  local d=math.sqrt(p:DistSq(q));local f=d>3 and 3/d or 1
  return Vector3(p.x+(q.x-p.x)*f,0,p.z+(q.z-p.z)*f)
 end
 local direct=step(goal);if pass(direct) then return direct end
 local best,score;local bp=pillar:GetPosition();local theta=math.atan2(p.z-bp.z,p.x-bp.x)
 local radius=math.max(pillar:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.5,math.sqrt(p:DistSq(bp)))
 local candidates={}
 for _,r in ipairs({radius,radius+1}) do for _,a in ipairs({-.25,.25,-.5,.5}) do
  candidates[#candidates+1]=step(Vector3(bp.x+math.cos(theta+a)*r,0,bp.z+math.sin(theta+a)*r))
 end end
 for _,q in ipairs(candidates) do if p:DistSq(q)>.2^2 and pass(q) then
  local value=q:DistSq(goal)+p:DistSq(q)*.2
  if not score or value<score then best,score=q,value end
 end end
 return best
end
return R
