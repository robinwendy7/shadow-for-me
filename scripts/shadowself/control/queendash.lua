-- 战吼阶段：直线带走，预计结束前一秒直穿回击，守卫追回后等新号令。
local Status=require("shadowself/control/status")
local Nav=require("shadowself/control/navigation")
local Route=require("shadowself/control/queendashroute")
local Wave=require("shadowself/control/queenwave")
local D={}
function D.Dashing(bee)
 if Status.Sleeping(bee) or Status.Frozen(bee) then return false end
 local a=bee.AnimState
 if a and a.GetBuild and a:GetBuild()=="bee_guard_puffy_build" then return true end
 local loco=bee.components and bee.components.locomotor
 return loco and loco.walkspeed and loco.walkspeed>(TUNING.BEEGUARD_SPEED or 3) or false
end
local function enter(q,state,queen,pos)
 state.mode="pull";state.seen_dash=true;state.route=nil;state.edge_leg=nil;Wave.Start(state);require("shadowself/control/queenroute").Clear(q)
 local qp=queen:GetPosition();local dx,dz=pos.x-qp.x,pos.z-qp.z;local d=math.sqrt(dx*dx+dz*dz)
 if d<.01 then dx,dz,d=1,0,1 end
 state.dir={x=dx/d,z=dz/d};q.stage="dash_pull"
 require("shadowself/control/queendebug").Event(q.c,"dash_start",{pos=require("shadowself/control/queendebug").Point(pos),direction=string.format("%.2f,%.2f",dx/d,dz/d),reason="guard_boost"})
end
-- 拉蜂使用固定外移直线，不复用 Queen:Move 的18码边界/切线候选。
function D.Pull(q,state,queen,pos)
 local c=q.c;local qp=queen:GetPosition();local dir=state.dir;local now=GetTime()
 local label="蜂后冲锋阶段 · 固定直线远离蜂后带蜂"
 local homepoint=q.anchor or qp;local leashpoint=math.max(4,(TUNING.BEEQUEEN_DEAGGRO_DIST or 60)-6)
 local nextpoint=Vector3(pos.x+dir.x*4,0,pos.z+dir.z*4)
 if nextpoint:DistSq(homepoint)>leashpoint^2 and now>=(state.next_edge or 0) then
  state.next_edge=now+.2
  local best,score
  -- 到场边只更换下一段逃跑直线，不把仍在冲锋的蜂当成已恢复。
  for i=0,15 do
   local a=i*math.pi/8;local point=Vector3(pos.x+math.cos(a)*4,0,pos.z+math.sin(a)*4)
   if point:DistSq(homepoint)<pos:DistSq(homepoint)-.1 and point:DistSq(qp)>=8^2 and Nav.Safe(c,point,queen) then
    local clearance=math.huge
    for _,bee in ipairs(q.debug_bees or {}) do clearance=math.min(clearance,point:DistSq(bee:GetPosition())) end
    local value=math.min(clearance,100)*4+point:DistSq(qp)-point:DistSq(homepoint)*.1
    if not score or value>score then best,score=point,value end
   end
  end
  if best then
   state.dir={x=(best.x-pos.x)/4,z=(best.z-pos.z)/4};dir=state.dir;state.edge_leg=true;state.route=nil
   require("shadowself/control/queendebug").Throttle(c,"dash_boundary_leg",1,"dash_boundary_leg",{home=math.sqrt(pos:DistSq(homepoint))})
  end
 end
 if Route.Reuse(q,state,label,now) then return end
 local distance=math.sqrt(pos:DistSq(qp));local home=q.anchor or qp
 local leash=math.max(4,(TUNING.BEEQUEEN_DEAGGRO_DIST or 60)-6)
 local function forward(point)
  return (point.x-pos.x)*dir.x+(point.z-pos.z)*dir.z>.2
   and (state.edge_leg and point:DistSq(qp)>=8^2 or not state.edge_leg and point:DistSq(qp)>(distance+.1)^2) and point:DistSq(home)<=leash^2
 end
 local straight=Vector3(pos.x+dir.x*4,0,pos.z+dir.z*4);local goal;local route="straight"
 if forward(straight) and Nav.Safe(c,straight,queen) then goal=straight end
 if not goal then
  -- 障碍只允许向原外移方向前进的小角度绕行，不选绕蜂后的圆周路线。
  for _,angle in ipairs({15,-15,30,-30,45,-45,60,-60}) do
   local a=angle*math.pi/180
   local dx,dz=dir.x*math.cos(a)-dir.z*math.sin(a),dir.x*math.sin(a)+dir.z*math.cos(a)
   local point=Vector3(pos.x+dx*4,0,pos.z+dz*4)
   if forward(point) and Nav.Safe(c,point,queen) then goal=point;route="outward_detour";break end
  end
 end
 if not goal then goal=Nav.Escape(c,straight,queen,forward);route=goal and "escape" or "blocked" end
 require("shadowself/control/queendebug").Throttle(c,"dash_route:"..route,1,"dash_route",{route=route,pos=require("shadowself/control/queendebug").Point(pos),goal=require("shadowself/control/queendebug").Point(goal),distance=distance,home=math.sqrt(pos:DistSq(home)),leash=leash})
 Route.Commit(q,state,goal,label,now)
end
function D.Tick(q,queen,bees,now)
 local c=q.c;local p=c.player;local pos=p:GetPosition();local qp=queen:GetPosition()
 local state=q.dash_cycle or {mode="solo"};q.dash_cycle=state
 local a=queen.AnimState
 local frame=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
 local ending=a:IsCurrentAnimation("command3") and frame>=23
 local dashing=false;local awake=false;local nearest;local near=math.huge
 for _,bee in ipairs(bees) do
  dashing=D.Dashing(bee) or dashing
  if not Status.Sleeping(bee) and not Status.Frozen(bee) then
   awake=true;local d=pos:DistSq(bee:GetPosition());if d<near then near=d;nearest=bee end
  end
 end
 local new_dash=dashing and not state.was_dash
 state.was_dash=dashing
 q:Target(queen)
 if not awake then state.mode="solo";state.route=nil end
 -- 只在守卫实际进入冲刺时带走。普通守卫追近不重新拉扯、不切换攻击目标。
 if awake and new_dash and not ending then enter(q,state,queen,pos) end
 if state.mode=="pull" then
  if dashing then state.seen_dash=true end
  local remaining,timing=Wave.Remaining(state,queen)
  local early=remaining and remaining<=Wave.LEAD
  local home=math.sqrt(pos:DistSq(q.anchor or qp))
  local finished=early or ending or state.seen_dash and not dashing
  if finished then
   state.mode="return";state.route=nil;q.stage="dash_return";c.next_move=nil
   require("shadowself/control/queendebug").Event(c,"dash_end",{reason=early and "near_release:"..timing or ending and "command3_frame23" or "guard_normal",remaining=remaining or -1,home=home,queen_frame=frame,distance=math.sqrt(pos:DistSq(qp))})
  else
   q.stage="dash_pull";D.Pull(q,state,queen,pos)
   return true
  end
 end
 if state.mode=="return" then
  local reach=(c.gear.AttackRange and c.gear:AttackRange() or 2)+(queen.GetPhysicsRadius and queen:GetPhysicsRadius(0) or .5)-.3
  local distance=math.sqrt(pos:DistSq(qp))
  if distance>reach+.2 then
   q.stage="dash_return";Route.Return(q,state,queen,reach,now);return true
  end
  c.bridge.chasing=nil;if c.travel then c.travel.chasing=nil end;q:ReleaseTravel()
  state.mode="solo";state.route=nil
  require("shadowself/control/queendebug").Event(c,"queen_solo",{distance=distance})
 end
 if state.mode=="solo" and awake and near<4.5^2 then
  state.mode="wait";state.route=nil;c.next_move=nil
  if c.bridge.PauseAttack then c.bridge:PauseAttack() end
  if c.actions.Stop then c.actions:Stop() end
  require("shadowself/control/queendebug").Event(c,"dash_wait",{nearest=math.sqrt(near)})
 end
 if state.mode=="wait" then q.stage="dash_wait";Route.Wait(q,state,queen,nearest,now);return true end
 q.stage="strike";return q:Strike(queen,pos,qp,math.sqrt(pos:DistSq(qp)))
end
return D
