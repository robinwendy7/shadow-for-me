-- 第八关返程：只有陆地/尚存在的冰面可步行，外围砖环提供绕水域的连通路线。
local R={}
local function platform(p)
 local m=TheWorld.Map
 return m.GetPlatformAtPoint and m:GetPlatformAtPoint(p.x,p.z)
end
local function ice(p)
 local m=TheWorld.Map
 return WORLD_TILES and WORLD_TILES.OCEAN_ICE and m.GetTileAtPoint
  and m:GetTileAtPoint(p.x,0,p.z)==WORLD_TILES.OCEAN_ICE
end
function R.Stable(p)
 local m=TheWorld.Map
 return not platform(p) and not ice(p) and m:IsPassableAtPoint(p.x,0,p.z)
  and not m:IsOceanAtPoint(p.x,0,p.z)
end
local function land(p)
 local m=TheWorld.Map
 local platform=m.GetPlatformAtPoint and m:GetPlatformAtPoint(p.x,p.z)
 if platform then return platform.prefab=="boat_ice_crabking" end
 return m:IsPassableAtPoint(p.x,0,p.z) and (not m:IsOceanAtPoint(p.x,0,p.z)
  or WORLD_TILES and WORLD_TILES.OCEAN_ICE and m:GetTileAtPoint(p.x,0,p.z)==WORLD_TILES.OCEAN_ICE)
end
-- 只看真实攻击动画；普通挥击18帧命中，旋转前摇之后以8码/秒冲刺0.7秒。
function R.Dodge(player,entities,goal)
 local p=player:GetPosition();local zones={}
 for _,e in ipairs(entities or {}) do
  if (e.prefab=="crabking_mob" or e.prefab=="crabking_mob_knight") and e:IsValid()
   and not e:HasTag("dead") and not e:HasTag("isdead") and not e:HasTag("INLIMBO")
   and not e:HasTag("sleeping") and not e:HasTag("frozen") and e.AnimState then
   local spin=e.AnimState:IsCurrentAnimation("atk_pre") or e.AnimState:IsCurrentAnimation("atk_loop")
   if spin or e.AnimState:IsCurrentAnimation("atk1") then
    local combat=e.replica and e.replica.combat
    local radius=spin and 2.9 or (combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)
     +(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)+.5
    radius=radius+(player.GetPhysicsRadius and player:GetPhysicsRadius(0) or .5)
    local angle=e.Transform and e.Transform:GetRotation()*math.pi/180 or 0
    zones[#zones+1]={p=e:GetPosition(),radius=radius,length=spin and 5.6 or 0,x=math.cos(angle),z=-math.sin(angle)}
   end
  end
 end
 local function risk(q)
  local total=0
  for _,v in ipairs(zones) do
   local dx,dz=q.x-v.p.x,q.z-v.p.z
   local along=math.max(0,math.min(v.length,dx*v.x+dz*v.z))
   total=total+math.max(0,v.radius-math.sqrt((dx-along*v.x)^2+(dz-along*v.z)^2))^2
  end
  return total
 end
 local initial=risk(p);local danger=initial>0
 if goal then
  local d=math.sqrt(p:DistSq(goal));local length=math.min(3,d)
  for i=1,6 do
   local f=d>0 and length*i/6/d or 0
   if risk(Vector3(p.x+(goal.x-p.x)*f,0,p.z+(goal.z-p.z)*f))>0 then danger=true end
  end
 end
 if not danger then return nil,false end
 local best,score
 for _,length in ipairs({3,5}) do for i=0,23 do
  local angle=i*math.pi/12;local q=Vector3(p.x+math.cos(angle)*length,0,p.z+math.sin(angle)*length)
  if R.Clear(p,q) and risk(q)<math.max(.001,initial) then
   local peak=initial;local exposure=0
   for j=1,10 do
    local r=risk(Vector3(p.x+(q.x-p.x)*j/10,0,p.z+(q.z-p.z)*j/10))
    peak=math.max(peak,r);exposure=exposure+r
   end
   if peak<=initial+.01 then
    local value=exposure*100+length+(goal and math.sqrt(q:DistSq(goal)) or 0)
    if not score or value<score then best,score=q,value end
   end
  end
 end end
 return best,true
end
function R.Clear(a,b,stable)
 local d=math.sqrt(a:DistSq(b));local n=math.max(1,math.ceil(d/.5))
 local temporary=false
 for i=0,n do
  local p=Vector3(a.x+(b.x-a.x)*i/n,0,a.z+(b.z-a.z)*i/n)
  if not land(p) or stable and not R.Stable(p) then return false end
  temporary=temporary or ice(p) or platform(p)~=nil
 end
 local path=TheWorld.Pathfinder
 return not path or platform(a) and platform(a).prefab=="boat_ice_crabking"
  or platform(b) and platform(b).prefab=="boat_ice_crabking" or path:IsClear(a.x,0,a.z,b.x,0,b.z,{ignorecreep=true,ignorewalls=false,allowocean=temporary or false})
end
-- 融冰时优先最近可达的永久陆地；局部网格允许沿弯曲冰面撤离。
local function trace(player,center,goal)
 local p=player:GetPosition()
 if not goal and R.Stable(p) then return p end
 local nodes={p};local grid={};local links={}
 for x=-22,22,2 do
  grid[x]={}
  for z=-22,22,2 do
   local q=Vector3(center.x+x,0,center.z+z)
   if land(q) then nodes[#nodes+1]=q;grid[x][z]=#nodes end
  end
 end
 for x,row in pairs(grid) do for z,id in pairs(row) do
  links[id]={}
  for dx=-2,2,2 do for dz=-2,2,2 do
   local other=grid[x+dx] and grid[x+dx][z+dz]
   if other and other~=id then links[id][#links[id]+1]=other end
  end end
 end end
 links[1]={}
 for i=2,#nodes do
  if p:DistSq(nodes[i])<=3^2 then links[1][#links[1]+1]=i end
 end
 local destination
 if goal and land(goal) then
  nodes[#nodes+1]=goal;destination=#nodes;links[destination]={}
  for i=1,destination-1 do
   if nodes[i]:DistSq(goal)<=3^2 then links[i][#links[i]+1]=destination end
  end
 end
 local costs={[1]=0};local prev={};local visited={}
 while true do
  local at,best
  for i,value in pairs(costs) do if not visited[i] and (not best or value<best) then at,best=i,value end end
  if not at then return end
  if destination and at==destination or not goal and at~=1 and R.Stable(nodes[at]) then
   local chain={};local id=at
   while id~=1 do table.insert(chain,1,nodes[id]);id=prev[id] end
   local point=chain[1]
   for _,q in ipairs(chain) do if R.Clear(p,q) then point=q else break end end
   return point
  end
  visited[at]=true
  for _,i in ipairs(links[at] or {}) do
   if not visited[i] and R.Clear(nodes[at],nodes[i]) then
    local value=best+math.sqrt(nodes[at]:DistSq(nodes[i]))
    if not costs[i] or value<costs[i] then costs[i]=value;prev[i]=at end
   end
  end
 end
end
function R.Escape(player,center) return trace(player,center) end
function R.Point(player,goal,center)
 local p=player:GetPosition()
 local function clear(a,b) return R.Clear(a,b) end
 if clear(p,goal) then return goal end
 local interior=trace(player,center,goal)
 if interior then return interior end
 local nodes={p,goal}
 for i=0,7 do nodes[#nodes+1]=Vector3(center.x-20+i*5,0,center.z-20) end
 for i=0,7 do nodes[#nodes+1]=Vector3(center.x+20,0,center.z-20+i*5) end
 for i=0,7 do nodes[#nodes+1]=Vector3(center.x+20-i*5,0,center.z+20) end
 for i=0,7 do nodes[#nodes+1]=Vector3(center.x-20,0,center.z+20-i*5) end
 local costs={[1]=0};local prev={};local visited={}
 while true do
  local at,best
  for i,value in pairs(costs) do if not visited[i] and (not best or value<best) then at,best=i,value end end
  if not at then return end
  if at==2 then break end
  visited[at]=true
  for i,q in ipairs(nodes) do
   -- 外圈相邻点相连；起点和入场点只连接可直达的节点。
   local adjacent=at<=2 or i<=2 or math.abs(at-i)==1 or at==3 and i==34 or at==34 and i==3
   if not visited[i] and adjacent and clear(nodes[at],q) then
    local value=best+math.sqrt(nodes[at]:DistSq(q))
    if not costs[i] or value<costs[i] then costs[i]=value;prev[i]=at end
   end
  end
 end
 local chain={};local at=2
 while at and at~=1 do table.insert(chain,1,nodes[at]);at=prev[at] end
 local point=chain[1]
 for _,q in ipairs(chain) do if clear(p,q) then point=q else break end end
 return point
end
return R
