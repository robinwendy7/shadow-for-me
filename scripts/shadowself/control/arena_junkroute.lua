-- daywalker2专属：只规划中央垃圾堆附近的接近/环绕，不调用任意方向的通用逃离。
local J={}
function J.Anchor(s,entities)
 local known=s.arena.encounters:FindCenter();local pile,near
 for _,e in ipairs(entities or {}) do if e:IsValid() and e.prefab=="junk_pile_big" and not e:HasTag("INLIMBO") then
  local d=known and known:DistSq(e:GetPosition()) or 0
  if not near or d<near then pile,near=e,d end
 end end
 if pile and (not known or near<=4^2) then
  s.junk_center=pile:GetPosition();s.junk_radius=math.max(3.6,pile.GetPhysicsRadius and pile:GetPhysicsRadius(0) or 3.6)
 end
 return s.junk_center or known
end
function J.Point(s,center)
 local p=s.player:GetPosition();local c=s.context;local map=TheWorld.Map
 local body=(s.junk_radius or 3.6)+(s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5)
 local ring=body+.3;local d=math.sqrt(p:DistSq(center));local angle=math.atan2(p.z-center.z,p.x-center.x)
 local radius=d>ring+.6 and math.max(ring,d-3) or ring
 local preferred=s.junk_side or 1;local best,score
 local boss=s.boss;local bp=boss and boss:IsValid() and boss:GetPosition()
 local now=GetTime();local vx,vz=0,0;local old=s.junk_boss_motion
 if bp and old and now>old.time and now-old.time<=.5 then
  vx=(bp.x-old.pos.x)/(now-old.time);vz=(bp.z-old.pos.z)/(now-old.time)
  if vx*vx+vz*vz>12^2 then vx,vz=0,0 end
 end
 if bp then s.junk_boss_motion={pos=bp,time=now} end
 local a=boss and boss.AnimState
 local swing=a and a:IsCurrentAnimation("atk_object")
 -- 实际挥击DoArcAttack半径4.5，不能只避开疯猪肉身；平时预测其追近，仍沿垃圾堆绕行。
 local danger=swing and 4.5+(s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5)+.4 or 3.2
 local function clear(q)
  local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.25))
  local before=math.sqrt(p:DistSq(center))
  for i=0,steps do
   local v=Vector3(p.x+(q.x-p.x)*i/steps,0,p.z+(q.z-p.z)*i/steps)
   if not map:IsPassableAtPoint(v.x,0,v.z) or map:IsOceanAtPoint(v.x,0,v.z)
    or map.IsPointNearHole and map:IsPointNearHole(v) then return false end
   local dist=math.sqrt(v:DistSq(center))
   if dist<body+.04 and dist<before-.01 then return false end
   before=dist
   for _,h in ipairs(c.hazards or {}) do
    local radius=(h.radius or 0)+.2
    local initial=math.max(0,radius-math.sqrt(p:DistSq(h.pos)))
    if math.max(0,radius-math.sqrt(v:DistSq(h.pos)))>initial+.01 then return false end
   end
   local boss=s.boss
   if boss and boss:IsValid() then
    local r=(boss.GetPhysicsRadius and boss:GetPhysicsRadius(0) or 1)+(s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5)+.2
    local initial=math.max(0,r-math.sqrt(p:DistSq(boss:GetPosition())))
    if math.max(0,r-math.sqrt(v:DistSq(boss:GetPosition())))>initial+.01 then return false end
    local prediction=Vector3(bp.x+vx*.3*i/steps,0,bp.z+vz*.3*i/steps)
    local before=math.max(0,danger-math.sqrt(p:DistSq(bp)))
    if math.max(0,danger-math.sqrt(v:DistSq(prediction)))>before+.01 then return false end
   end
  end
  for _,h in ipairs(c.hazards or {}) do
   local r=(h.radius or 0)+.2;local initial=math.max(0,r-math.sqrt(p:DistSq(h.pos)))
   if initial>0 and math.max(0,r-math.sqrt(q:DistSq(h.pos)))>=initial-.01 then return false end
  end
  local path=TheWorld.Pathfinder
  return not path or path:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false})
 end
 -- 直接向内接近被Boss挡住时先在当前半径侧绕，不能因此停在原地等挨打。
 local radii={radius}
 if d>ring+.6 then radii[#radii+1]=d end
 if bp and bp:DistSq(center)>(s.junk_radius or 3.6)^2 and p:DistSq(bp)<(danger+1)^2 then radii[#radii+1]=math.max(ring,d)+.8 end
 for _,r in ipairs(radii) do for _,side in ipairs({preferred,-preferred}) do for _,step in ipairs({.35,.22,.5,.7}) do
  local a=angle+side*step;local q=Vector3(center.x+math.cos(a)*r,0,center.z+math.sin(a)*r)
  if clear(q) then
   local value=(side==preferred and 0 or 1)+math.max(0,r-ring)*5
   -- 只把真实本体碰撞当硬约束；炮的攻击距离不是全圆禁行区。
   local boss=s.boss
   if boss and boss:IsValid() then
    local collision=(boss.GetPhysicsRadius and boss:GetPhysicsRadius(0) or 1)+(s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5)+.3
    local initial=math.sqrt(p:DistSq(boss:GetPosition()));local after=math.sqrt(q:DistSq(boss:GetPosition()))
    if after<collision and after<initial then value=value+100 end
    value=value+math.max(0,5-after)*4
   end
   if not score or value<score then best,score=q,value;s.junk_next_side=side end
  end
 end end end
 if best then s.junk_side=s.junk_next_side end
 return best
end
return J
