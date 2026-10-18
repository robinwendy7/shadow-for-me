-- 蜂后一阶段/三阶段solo绕蜜：按需重算，短路线复用，直线拉蜂另由dashroute负责。
local Nav=require("shadowself/control/navigation")
local Debug=require("shadowself/control/queendebug")
local R={INTERVAL=.2}
function R.Clear(q) q.first_route=nil end
function R.Move(q,goal,label,queen)
 local c=q.c;local p=c.player:GetPosition();local qp=queen:GetPosition();local now=GetTime()
 local cache=q.first_route
 if cache and now<cache.expires then
  -- 实际攻击由更高优先级的guarddefence处理并清掉缓存；此处不重复整段寻路。
  local point=cache.point
  if point and p:DistSq(point)>.5^2 then
   q.travelling=true;c.bridge.chasing=true
   if c.travel then c.travel.chasing=true end
   c:Move(point,label);return
  end
  if not point then c.blocked=true;c.status=label;return end
 end
 local home=math.sqrt(p:DistSq(q.anchor));local distance=math.sqrt(p:DistSq(qp))
 local function bounded(v)
  local hd=math.sqrt(v:DistSq(q.anchor));local qd=math.sqrt(v:DistSq(qp))
  local home_limit=q.late and 40 or 18;local queen_limit=q.late and 18 or 12
  return (hd<=home_limit and home<=home_limit or hd<home-.1) and (qd<=queen_limit and distance<=queen_limit or qd<distance-.1)
 end
 local best,score;local tested=0
 local function consider(v)
  tested=tested+1
  if p:DistSq(v)<.75^2 or not bounded(v) or not Nav.Safe(c,v,queen) then return end
  local value=v:DistSq(goal)
  if not score or value<score then best,score=v,value end
 end
 local dx,dz=goal.x-p.x,goal.z-p.z;local len=math.sqrt(dx*dx+dz*dz)
 if len>=.75 then
  local step=math.min(4,len);consider(Vector3(p.x+dx/len*step,0,p.z+dz/len*step))
 end
 -- 直线可用直接走，不枚举；受阻才检查两个短环，共24个候选。
 if not best then
  for _,step in ipairs({1.5,3}) do for i=0,11 do
   local angle=i*math.pi/6;consider(Vector3(p.x+math.cos(angle)*step,0,p.z+math.sin(angle)*step))
  end end
 end
 local point=best or Nav.Escape(c,goal,queen,bounded)
 if point and p:DistSq(point)<.75^2 then point=nil end
 q.first_route={point=point,expires=now+R.INTERVAL}
 Debug.Throttle(c,"queen_route_plan",.5,"queen_route_plan",{candidates=tested,goal=Debug.Point(goal),selected=Debug.Point(point)})
 if point then
  q.travelling=true;c.bridge.chasing=true
  if c.travel then c.travel.chasing=true;c.travel:BeginDodge(c.snapshot) end
  c:Move(point,label)
 else
  c.blocked=true;c.status="蜂后 · 路线受阻，保持攻击预警"
  Debug.Throttle(c,"queen_route_blocked",1,"queen_route_blocked",{pos=Debug.Point(p),goal=Debug.Point(goal)})
 end
end
return R
