-- 三阶段移动只在短步到达或0.2秒缓存到期时重选路径。
local Nav=require("shadowself/control/navigation")
local R={INTERVAL=.2}
function R.Begin(q,state)
 local c=q.c;q.travelling=true;c.bridge.chasing=true
 if c.travel then
  c.travel.chasing=true
  if not c.travel.dodging then c.travel:BeginDodge(c.snapshot)
  elseif c.travel.UpdateDodge then c.travel:UpdateDodge(c.snapshot) end
 end
end
function R.Reuse(q,state,label,now)
 local cache=state.route
 if cache and cache.mode==state.mode and now<cache.expires then
  local pos=q.c.player:GetPosition()
  if cache.point and pos:DistSq(cache.point)>.5^2 and pos:DistSq(cache.start)<=6^2
      and (cache.point.x-pos.x)*(cache.point.x-cache.start.x)+(cache.point.z-pos.z)*(cache.point.z-cache.start.z)>0 then
   R.Begin(q,state);q.c:Move(cache.point,label);return true
  elseif not cache.point then q.c.blocked=true;q.c.status=label;return true end
 end
 return false
end
function R.Commit(q,state,point,label,now)
 state.route={mode=state.mode,point=point,start=q.c.player:GetPosition(),expires=now+R.INTERVAL}
 q.c.blocked=true;q.c.status=label
 if point then R.Begin(q,state);q.c:Move(point,label) end
end
function R.Return(q,state,queen,reach,now)
 local c=q.c;local p=c.player:GetPosition();local qp=queen:GetPosition()
 local label="蜂后冲锋阶段 · 冲刺结束前提前直穿蜂群，回击蜂后"
 if R.Reuse(q,state,label,now) then return end
 -- 仅此折返路线忽略守卫的近身圆；仍检查其他敌人、地形、海岸和蜂蜜。
 local enemies={};for _,e in ipairs(c.enemies or {}) do if e.prefab~="beeguard" then enemies[#enemies+1]=e end end
 local view=setmetatable({enemies=enemies},{__index=c})
 local d=math.max(.01,math.sqrt(p:DistSq(qp)));local step=math.min(4,math.max(0,d-reach))
 local goal=Vector3(p.x+(qp.x-p.x)/d*step,0,p.z+(qp.z-p.z)/d*step)
 local point=Nav.Safe(view,goal,queen) and goal or Nav.Select(view,goal,queen)
 if point and p:DistSq(point)<.01 then point=nil end
 R.Commit(q,state,point,label,now)
end
-- 等待时若已被带到外缘，安全地向场内收回空间，避免下一轮一开始就触边。
local function recenter(q,state,queen,now,label)
 local c=q.c;local p=c.player:GetPosition();local home=q.anchor or queen:GetPosition()
 if p:DistSq(home)<=36^2 then return false end
 if state.route and state.route.purpose=="recenter" and R.Reuse(q,state,label,now) then return true end
 state.route=nil
 local best,score;local status=require("shadowself/control/status")
 for i=0,11 do
  local a=i*math.pi/6;local point=Vector3(p.x+math.cos(a)*3,0,p.z+math.sin(a)*3)
  if point:DistSq(home)<p:DistSq(home)-.1 and point:DistSq(queen:GetPosition())>=8^2 then
   local clear=true
   for _,bee in ipairs(q.debug_bees or c.enemies or {}) do
    if bee.prefab=="beeguard" and bee:IsValid() and not status.Sleeping(bee) and not status.Frozen(bee) and point:DistSq(bee:GetPosition())<6^2 then clear=false;break end
   end
   if clear and Nav.Safe(c,point,queen) then
    local value=point:DistSq(home)
    if not score or value<score then best,score=point,value end
   end
  end
 end
 R.Commit(q,state,best,label,now);state.route.purpose="recenter"
 if best then require("shadowself/control/queendebug").Throttle(c,"dash_recenter",1,"dash_recenter",{home=math.sqrt(p:DistSq(home)),goal_home=math.sqrt(best:DistSq(home))}) end
 return best~=nil
end
local function hold(q,state,label)
 if state.wait_moving and q.c.actions.Stop then q.c.actions:Stop() end
 state.wait_moving=nil;state.route=nil;q.c.blocked=true;q.c.status=label
end
function R.Wait(q,state,queen,nearest,now)
 local c=q.c;local p=c.player:GetPosition()
 local label="蜂后冲锋阶段 · 保持蜂群距离，等待下一次号令"
 if not nearest or p:DistSq(nearest:GetPosition())>=6^2 then
  if recenter(q,state,queen,now,"蜂后冲锋阶段 · 保持安全间距，收回场内跑动空间") then state.wait_moving=true;return end
  hold(q,state,label);return
 end
 if state.route and state.route.purpose=="recenter" then state.route=nil end
 if R.Reuse(q,state,label,now) then state.wait_moving=true;return end
 local bp=nearest:GetPosition();local dx,dz=p.x-bp.x,p.z-bp.z;local d=math.sqrt(dx*dx+dz*dz)
 if d<.01 then dx,dz,d=1,0,1 end
 local goal=Vector3(p.x+dx/d*3,0,p.z+dz/d*3)
 local point=Nav.Select(c,goal,queen)
 if point and p:DistSq(point)<.01 then point=nil end
 R.Commit(q,state,point,label,now);state.route.purpose="space";state.wait_moving=point~=nil
end
return R
