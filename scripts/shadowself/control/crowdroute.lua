-- 群战短程联合避让。只在原生躲避选点时调用，不创建第二个移动线程。
local Nav=require("shadowself/control/navigation")
local Incoming=require("shadowself/control/incoming")
local Status=require("shadowself/control/status")
local M={}
local function penetration(q,p,r) return math.max(0,r-math.sqrt(q:DistSq(p))) end
function M.Choose(s,goal,primary,accept)
 local p=s.player:GetPosition();local c=s.c;local now=GetTime();local threats={}
 local primaryRadius=math.sqrt(goal:DistSq(primary:GetPosition()))
 local playerRadius=s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5
 local primaryLane=Incoming.Lane(c,primary)
 local function allowed(q)
  if accept then return accept(q) end
  if primaryLane then return Incoming.Risk(primaryLane,q)==0 end
  return q:DistSq(primary:GetPosition())+.01>=primaryRadius^2
 end
 for _,e in ipairs(s.enemies) do
  if e:IsValid() and not Status.Sleeping(e) and not Status.Frozen(e) then
   local data=s.data and s.data[e]
   local motion=s.motion and s.motion[e]
   threats[#threats+1]={e=e,pos=e:GetPosition(),data=data,lane=Incoming.Lane(c,e),motion=motion,
    radius=e==primary and primaryRadius or Nav.Radius(e)+.3,
    body=(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)+playerRadius+.2}
  end
 end
 local speed=math.max(3.5,c.Speed and c:Speed() or 6)
 local latency=c.Latency and c:Latency() or .1
 local function future(t,seconds)
  if not t.motion or t.lane then return t.pos end
  return Vector3(t.pos.x+t.motion.vx*seconds,0,t.pos.z+t.motion.vz*seconds)
 end
 local function risk(q,seconds)
  local value=0
  for _,t in ipairs(threats) do
   local pos=future(t,seconds or 0)
   -- 肉身碰撞始终避免；待机怪攻击圈是软代价，不再把整片空地全封死。
   value=value+math.max(penetration(q,t.pos,t.body),penetration(q,pos,t.body))^2*50
   if t.lane then value=value+Incoming.Risk(t.lane,q)^2*12
   elseif t.data and t.data.safe then value=value+(t.data.safe(q) and 0 or 12)
   else value=value+math.max(penetration(q,t.pos,t.radius),penetration(q,pos,t.radius))^2*(t.data and 8 or 1) end
  end
  for _,h in ipairs(s.hazards or {}) do value=value+penetration(q,h.pos,h.radius)^2*20 end
  return value
 end
 local initial=risk(p)
 local interfering=#(s.hazards or {})>0
 for _,t in ipairs(threats) do
  if t.e~=primary and (t.lane or math.sqrt(p:DistSq(t.pos))<t.radius+math.sqrt(p:DistSq(goal))+1) then interfering=true;break end
 end
 if not interfering then s.crowd_commit=nil;return goal end
 local function edgecost(q)
  local map=TheWorld and TheWorld.Map
  if not map or not map.IsPassableAtPoint or not map.IsOceanAtPoint then return 0 end
  if s.player.GetCurrentPlatform and s.player:GetCurrentPlatform() then return 0 end
  local blocked=0
  for _,d in ipairs({{2.5,0},{-2.5,0},{0,2.5},{0,-2.5}}) do
   local x,z=q.x+d[1],q.z+d[2]
   if not map:IsPassableAtPoint(x,0,z) or map:IsOceanAtPoint(x,0,z) then blocked=blocked+1 end
  end
  return blocked*16
 end
 local function evaluate(q)
  if not allowed(q) or not s.actions:SafePoint(q) then return end
  local duration=math.sqrt(p:DistSq(q))/speed
  local final=risk(q,math.min(.45,duration+latency));local peak,exposure=initial,0;local monotonic=true
  local n=math.max(3,math.ceil(math.sqrt(p:DistSq(q))/.4))
  for i=1,n do
   local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
   if not s.actions:SafePoint(v) then return end
   local map=TheWorld and TheWorld.Map
   if map and map.IsPassableAtPoint and not (s.player.GetCurrentPlatform and s.player:GetCurrentPlatform())
    and (not map:IsPassableAtPoint(v.x,0,v.z) or map.IsOceanAtPoint and map:IsOceanAtPoint(v.x,0,v.z)) then return end
   local ahead=math.min(.45,duration*i/n+latency)
   local r=risk(v,ahead);peak=math.max(peak,r);exposure=exposure+r/n
   for _,t in ipairs(threats) do
    if penetration(v,t.pos,t.body)>penetration(p,t.pos,t.body)+.02 then return end
    if t.motion and penetration(v,future(t,ahead),t.body)>penetration(p,t.pos,t.body)+.02 then return end
    if t.lane and Incoming.Risk(t.lane,v)>Incoming.Risk(t.lane,p)+.02 then return end
    if penetration(v,t.pos,t.radius)>penetration(p,t.pos,t.radius)+.02 then monotonic=false end
   end
   for _,h in ipairs(s.hazards or {}) do
    if penetration(v,h.pos,h.radius)>penetration(p,h.pos,h.radius)+.02 then return end
   end
  end
  -- 夹击时允许总风险下降的脱身路线，但不能为了躲A冲进更危险的B。
  if peak>initial+.25 or initial>0 and final>=initial-.01 or initial==0 and final>0 then return end
  local overshoot=0
  if not accept and not primaryLane then overshoot=math.max(0,math.sqrt(q:DistSq(primary:GetPosition()))-primaryRadius) end
  return peak*25+exposure*3+final*45+q:DistSq(goal)*.12+p:DistSq(q)*.15+edgecost(q)+overshoot^2*4,monotonic
 end
 local commit=s.crowd_commit
 if commit and now<commit.untiltime and p:DistSq(commit.point)>.25^2 and evaluate(commit.point) then return commit.point end
 local best,score;local exact,exactscore;local strict,strictscore
 local candidates={goal}
 for i=0,23 do
  local a=i*math.pi/12;local ep=primary:GetPosition()
  candidates[#candidates+1]=Vector3(ep.x+math.cos(a)*primaryRadius,0,ep.z+math.sin(a)*primaryRadius)
 end
 for _,length in ipairs({1.5,2.5,4,6}) do for i=0,23 do
  local a=i*math.pi/12;candidates[#candidates+1]=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
 end end
 for _,q in ipairs(candidates) do
  local value,monotonic=evaluate(q)
  if value then
   if commit then
    local ax,az=commit.point.x-p.x,commit.point.z-p.z;local bx,bz=q.x-p.x,q.z-p.z
    local n=math.sqrt((ax*ax+az*az)*(bx*bx+bz*bz))
    if n>.01 then value=value+(1-(ax*bx+az*bz)/n)*2 end
   end
   if not score or value<score then best,score=q,value end
   if not accept and not primaryLane and math.abs(math.sqrt(q:DistSq(primary:GetPosition()))-primaryRadius)<.01
    then
     if not exactscore or value<exactscore then exact,exactscore=q,value end
     if monotonic and (not strictscore or value<strictscore) then strict,strictscore=q,value end
    end
  end
 end
 best=strict or exact or best
 if best then s.crowd_commit={point=best,untiltime=now+.3};return best end
 s.crowd_commit=nil -- 无可行联合路线时，交回已有原生安全选点。
end
return M
