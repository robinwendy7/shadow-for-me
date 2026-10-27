-- 蚁狮圆周分段路线；整段净空校验，双向被堵时才使用局部连通图。
local Nav=require("shadowself/control/navigation")
local M={}
local function dist(a,b) return math.sqrt(a:DistSq(b)) end
local function point(c,q)
 local map=TheWorld and TheWorld.Map
 if map and map.IsPassableAtPoint and map.IsOceanAtPoint then
  return map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and (not map.IsPointNearHole or not map:IsPointNearHole(q))
 end
 return c.actions:SafePoint(q)
end
function M.Corridor(c,a,b,ant)
 if not point(c,b) then return false end
 local path=TheWorld and TheWorld.Pathfinder
 if path and not path:IsClear(a.x,0,a.z,b.x,0,b.z,{ignorecreep=true,ignorewalls=false}) then return false end
 local ep=ant:GetPosition();local body=(ant.GetPhysicsRadius and ant:GetPhysicsRadius(0) or .5)+(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)+.2
 local steps=math.max(1,math.ceil(dist(a,b)/.4));local initial=Nav.Risk(c,a,ant)
 local inside=math.min(body,dist(a,ep))
 for i=1,steps do
  local q=Vector3(a.x+(b.x-a.x)*i/steps,0,a.z+(b.z-a.z)*i/steps)
  if not point(c,q) or dist(q,ep)<inside-.02 or Nav.Risk(c,q,ant)>initial+.02 then return false end
 end
 return initial==0 or Nav.Risk(c,b,ant)<initial-.01
end
function M.Valid(c,ant,route)
 local p=c.player:GetPosition()
 for i=route.index or 1,#route.points do
  local q=route.points[i]
  if not M.Corridor(c,p,q,ant) then return false end
  p=q
 end
 return true
end
function M.Orbit(c,ant,side,offset)
 local p=c.player:GetPosition();local ep=ant:GetPosition();local radius=dist(p,ep)
 local body=ant:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.2
 local wanted=math.max(radius,body)+ (offset or 0)
 if wanted<body or wanted<.5 then return end
 local theta=math.atan2(p.z-ep.z,p.x-ep.x);local points={};local last=p
 local function add(q)
  if not M.Corridor(c,last,q,ant) then return false end
  points[#points+1]=q;last=q;return true
 end
 -- 半径变化也拆段，不能斜穿蚁狮碰撞体或中途沙刺。
 local radial=math.max(1,math.ceil(math.abs(wanted-radius)/.4))
 for i=1,math.abs(wanted-radius)>.01 and radial or 0 do
  local r=radius+(wanted-radius)*i/radial
  if not add(Vector3(ep.x+math.cos(theta)*r,0,ep.z+math.sin(theta)*r)) then return end
 end
 local length=2.6;local steps=math.ceil(length/.4)
 for i=1,steps do
  local a=theta+side*length/wanted*i/steps
  if not add(Vector3(ep.x+math.cos(a)*wanted,0,ep.z+math.sin(a)*wanted)) then return end
 end
 if Nav.Risk(c,last,ant)>0 then return end
 return {points=points,index=1,goal=last,side=side,kind="orbit"}
end
-- 已在爆发区内时允许先作风险下降的短步，不要求一步就到完全零风险区域。
function M.Exit(c,ant)
 local p=c.player:GetPosition();local initial=Nav.Risk(c,p,ant)
 if initial<=0 then return end
 local best,score
 for _,length in ipairs({2,3,4}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
  local risk=Nav.Risk(c,q,ant)
  if risk<initial-.01 and M.Corridor(c,p,q,ant) then
   local value=risk*100+length
   if not score or value<score then best,score=q,value end
  end
 end end
 return best
end
function M.Plan(c,ant,preferred)
 -- 原半径两侧都不通才短暂变更环半径，正常走位不累计向外漂移。
 for _,offset in ipairs({0,1,-1,2}) do
  for _,side in ipairs({preferred,-preferred}) do
   local route=M.Orbit(c,ant,side,offset)
   if route then return route end
  end
 end
 local p=c.player:GetPosition();local ep=ant:GetPosition();local r=dist(p,ep)
 local a=math.atan2(p.z-ep.z,p.x-ep.x)+preferred*.6
 local hint=Vector3(ep.x+math.cos(a)*r,0,ep.z+math.sin(a)*r)
 local waypoint,goal=M.Route(c,ant,hint)
 if waypoint then return {points={waypoint},index=1,goal=waypoint,exit=goal,kind="detour",side=preferred} end
 local escape=M.Exit(c,ant)
 if escape then return {points={escape},index=1,goal=escape,kind="escape",side=preferred} end
end
function M.Room(c,q,ant,from)
 local open,forward=0,0;local dx,dz=from and q.x-from.x or 0,from and q.z-from.z or 0
 for i=0,7 do
  local a=i*math.pi/4;local x,z=math.cos(a)*1.4,math.sin(a)*1.4
  if M.Corridor(c,q,Vector3(q.x+x,0,q.z+z),ant) then
   open=open+1;if dx*x+dz*z>=-.01 then forward=forward+1 end
  end
 end
 return open,forward
end
-- 脱困后的落点还须有一条返回攻击圈的净空通道，不能停在沙刺堆背后。
function M.Approach(c,p,ant)
 local ep=ant:GetPosition();local distance=dist(p,ep)
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or 2)+(ant.GetPhysicsRadius and ant:GetPhysicsRadius(0) or .5)-.15
 local radius=math.max(2.2,reach)
 if distance<=radius+.2 then return Nav.Risk(c,p,ant)==0 and p or nil end
 local q=Vector3(ep.x+(p.x-ep.x)/distance*radius,0,ep.z+(p.z-ep.z)/distance*radius)
 return M.Corridor(c,p,q,ant) and q or nil
end
function M.Route(c,ant,hint)
 local p=c.player:GetPosition();local nodes={};local step=1.4
 local function key(x,z) return (x+4)*9+z+5 end
 for x=-4,4 do for z=-4,4 do
  local q=Vector3(p.x+x*step,0,p.z+z*step)
  if x==0 and z==0 or point(c,q) and Nav.Risk(c,q,ant)==0 and dist(q,ant:GetPosition())>(ant.GetPhysicsRadius and ant:GetPhysicsRadius(0) or .5)+.8 then
   nodes[key(x,z)]={x=x,z=z,q=q}
  end
 end end
 local emergency=Nav.Risk(c,p,ant)>0
 local root=nodes[key(0,0)];root.depth=0
 local queue={root};local index=1;local best,score
 while index<=#queue do
  local n=queue[index];index=index+1;local degree,room=0,0
  for dx=-2,2 do for dz=-2,2 do
   if dx*dx+dz*dz<=5 and nodes[key(n.x+dx,n.z+dz)] and math.abs(n.x+dx)<=4 and math.abs(n.z+dz)<=4 then room=room+1 end
  end end
  for dx=-1,1 do for dz=-1,1 do if dx~=0 or dz~=0 then
   local x,z=n.x+dx,n.z+dz
   local v=math.abs(x)<=4 and math.abs(z)<=4 and nodes[key(x,z)]
   if v and M.Corridor(c,n.q,v.q,ant) then
    degree=degree+1
    if not v.depth then v.depth=n.depth+1;v.parent=n;queue[#queue+1]=v end
   end
  end end end
  -- If a new spike appeared directly below us, allow a monotone exit beyond one cell.
  if n==root and Nav.Risk(c,p,ant)>0 then
   for dx=-1,1 do for dz=-1,1 do if dx~=0 or dz~=0 then
    local v=nodes[key(dx*2,dz*2)]
    if v and not v.depth and M.Corridor(c,p,v.q,ant) then v.depth=1;v.parent=n;queue[#queue+1]=v end
   end end end
  end
  if n~=root and (degree>=3 or emergency and degree>=1) then
   local value=room*4+degree*3+Nav.Clearance(c,n.q)-n.depth*.6
   if hint then value=value-n.q:DistSq(hint)*5
   elseif M.Approach(c,n.q,ant) then value=value+80 end
   if not score or value>score then best,score=n,value end
  end
 end
 if not best then return end
 local chain={};local n=best
 while n and n~=root do table.insert(chain,1,n.q);n=n.parent end
 local waypoint=chain[1]
 for _,q in ipairs(chain) do
  if p:DistSq(q)<=4.5^2 and M.Corridor(c,p,q,ant) then waypoint=q else break end
 end
 return waypoint,best.q
end
return M
