-- 第九关撞晕后的回身接近；复用原Boss移动所有权，抵达后交回普通攻击。
local R={}
function R.Point(c,boss,state)
 local Nav=require("shadowself/control/navigation")
 local p,ep=c.player:GetPosition(),boss:GetPosition()
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or 2)+boss:GetPhysicsRadius(0)-.25
 local map=TheWorld.Map;local player_radius=c.player:GetPhysicsRadius(0)
 local blocks={{pos=ep,radius=boss:GetPhysicsRadius(0)+player_radius+.15,target=true}}
 local radius=math.min(32,math.sqrt(p:DistSq(ep))*.5+8)
 for _,e in ipairs(TheSim:FindEntities((p.x+ep.x)/2,0,(p.z+ep.z)/2,radius,nil,{"INLIMBO","FX","DECOR"})) do
  if e~=boss and e~=c.player and e:IsValid() and not e:HasTag("NOBLOCK") and not e:HasTag("INLIMBO")
   and (e:HasTag("charge_barrier") or e:HasTag("wall") or e.Physics and e.Physics.GetMass and e.Physics:GetMass()==0)
   and e:GetPhysicsRadius(0)>0 then
   blocks[#blocks+1]={pos=e:GetPosition(),radius=e:GetPhysicsRadius(0)+player_radius+.25}
  end
 end
 local function clear(a,b,attack)
  for _,v in ipairs(blocks) do
   local dx,dz=b.x-a.x,b.z-a.z;local length=dx*dx+dz*dz
   local t=length>0 and math.max(0,math.min(1,((v.pos.x-a.x)*dx+(v.pos.z-a.z)*dz)/length)) or 0
   if not (attack and v.target) and (a.x+dx*t-v.pos.x)^2+(a.z+dz*t-v.pos.z)^2<v.radius^2 then return false end
  end
  local n=math.max(1,math.ceil(math.sqrt(a:DistSq(b))/.4))
  for i=0,n do local q=Vector3(a.x+(b.x-a.x)*i/n,0,a.z+(b.z-a.z)*i/n)
   if not map:IsPassableAtPoint(q.x,0,q.z) or map:IsOceanAtPoint(q.x,0,q.z)
    or map.IsPointNearHole and map:IsPointNearHole(q) then return false end
  end
  local path=TheWorld.Pathfinder
  return not path or path:IsClear(a.x,0,a.z,b.x,0,b.z,{ignorecreep=true,ignorewalls=false})
 end
 -- 不仅检查距离：隔着柱子即使距离够，也不能直接挥刀。
 if clear(p,ep,true) then state.attack_path=nil;return nil,true end
 local function step(q)
  local d=math.sqrt(p:DistSq(q));local t=d>3 and 3/d or 1
  return Vector3(p.x+(q.x-p.x)*t,0,p.z+(q.z-p.z)*t)
 end
 local cached=state.attack_path
 if cached and cached.ep:DistSq(ep)<.5^2 and math.abs(cached.reach-reach)<.1 then
  while #cached.points>0 and p:DistSq(cached.points[1])<.4^2 do table.remove(cached.points,1) end
  if cached.points[1] then local q=step(cached.points[1])
   if clear(p,q) and Nav.Safe(c,q,boss) then return q,false end
  end
 end
 state.attack_path=nil
 if GetTime()<(state.attack_retry or 0) then return end
 state.attack_retry=GetTime()+.25
 local nodes={p};local goals={}
 local theta=math.atan2(p.z-ep.z,p.x-ep.x)
 for i=0,11 do local a=theta+i*math.pi/6
  local q=Vector3(ep.x+math.cos(a)*reach,0,ep.z+math.sin(a)*reach)
  if clear(q,ep,true) then nodes[#nodes+1]=q;goals[#nodes]=true end
 end
 table.sort(blocks,function(a,b) return p:DistSq(a.pos)<p:DistSq(b.pos) end)
 -- 所有障碍都参与碰撞校验，仅最近八个提供绕行节点，限制单次规划工作量。
 for i=1,math.min(8,#blocks) do local v=blocks[i]
  for j=0,11 do local a=j*math.pi/6
   nodes[#nodes+1]=Vector3(v.pos.x+math.cos(a)*(v.radius+.4),0,v.pos.z+math.sin(a)*(v.radius+.4))
  end
 end
 local costs={[1]=0};local prev={};local visited={}
 while true do
  local at,best
  for i,value in pairs(costs) do if not visited[i] and (not best or value<best) then at,best=i,value end end
  if not at then return end
  if goals[at] then
   local chain={};local id=at
   while id~=1 do table.insert(chain,1,nodes[id]);id=prev[id] end
   state.attack_path={points=chain,ep=Vector3(ep.x,0,ep.z),reach=reach}
   local q=step(chain[1]);if clear(p,q) and Nav.Safe(c,q,boss) then return q,false end
   state.attack_path=nil;return
  end
  visited[at]=true
  for i,q in ipairs(nodes) do if not visited[i] and clear(nodes[at],q) then
   local value=best+math.sqrt(nodes[at]:DistSq(q))
   if not costs[i] or value<costs[i] then costs[i]=value;prev[i]=at end
  end end
 end
end
return R
