-- 原版minotaur只会撞带charge_barrier的柱子晕眩；落石未落地不作为掩体。
local Nav=require("shadowself/control/navigation")
local G={}
local function anim(e,n) return e.AnimState and e.AnimState:IsCurrentAnimation(n) end
function G.Stunned(e)
 return anim(e,"stun_pre") or anim(e,"stun_loop") or anim(e,"stun_hit") or anim(e,"stun_jump_pre")
end
local function valid(e)
 return e and e:IsValid() and e:HasTag("charge_barrier") and not e:HasTag("NOBLOCK") and not e:HasTag("INLIMBO") and not e:HasTag("FX") and (e:GetPosition().y or 0)<.5
end
local function key(point) return math.floor(point.x/2+.5)..":"..math.floor(point.z/2+.5) end
local function chargeclear(c,e,q)
 local ep=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local x,z=q.x-ep.x,q.z-ep.z
 local width=math.max(4,e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.6)
 return x*math.cos(r)-z*math.sin(r)<=-width or math.abs(x*math.sin(r)+z*math.cos(r))>=width
end
local function chargeexit(c,e)
 local p=c.player:GetPosition();if chargeclear(c,e,p) then return p end
 local ep=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local signed=(p.x-ep.x)*math.sin(r)+(p.z-ep.z)*math.cos(r)
 local width=math.max(4,e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.6)
 local step=(width-math.abs(signed)+.25)*(signed<0 and -1 or 1)
 return Vector3(p.x+math.sin(r)*step,0,p.z+math.cos(r)*step)
end
local function crosspillar(a,b,pillar,player)
 local q=pillar:GetPosition();local x,z=b.x-a.x,b.z-a.z;local length=x*x+z*z
 local t=length>0 and math.max(0,math.min(1,((q.x-a.x)*x+(q.z-a.z)*z)/length)) or 0
 local radius=pillar:GetPhysicsRadius(0)+player:GetPhysicsRadius(0)+.2
 return (q.x-a.x-x*t)^2+(q.z-a.z-z*t)^2<radius^2
end
local function nextpillar(state,now)
 state.phase="select";state.owns_until=nil
 if state.pillar then
  local p=state.pillar:IsValid() and state.pillar:GetPosition() or state.pillar_point
  if p then
   state.last_point=Vector3(p.x,0,p.z)
   state.used=state.used or {};local k=key(p);state.used[k]=(state.used[k] or 0)+1
  end
 end
 state.pillar=nil;state.direction=nil;state.wait_goal=nil;state.waiting=nil;state.wait_since=nil;state.active=nil
 state.charging=nil;state.danger_waiting=nil;state.danger_reported=nil;state.next_scan=nil;state.since=now;state.progress=nil;state.progress_time=now
end
local function trace(c,state,phase,goal)
 if not (c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==9) or state.trace_phase==phase then return end
 state.trace_phase=phase
 local p=c.player:GetPosition();local b=state.pillar and state.pillar:GetPosition() or state.pillar_point or p;local q=goal or state.wait_goal or p
 print(string.format("[ShadowSelf][guardian] phase=%s pillar=%.2f,%.2f player=%.2f,%.2f goal=%.2f,%.2f",phase,b.x,b.z,p.x,p.z,q.x,q.z))
end
function G.Tick(boss,e)
 if e.prefab~="minotaur" then return end
 local c=boss.c;local now=GetTime();local ep=e:GetPosition();local p=c.player:GetPosition()
 local arena9=c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==9
 local state=boss.guardian
 if not state or state.target~=e then state={target=e,used={}};boss.guardian=state end
 if G.Stunned(e) then
  trace(c,state,"stunned")
  state.phase="stunned";state.owns_until=nil
  state.stunned=true;state.active=nil
  if arena9 then
   local q,arrived=require("shadowself/control/guardianattack").Point(c,e,state)
   if not arrived then
    if q then return boss:Move(q,"远古守护者 · 绕过阻挡物，进入攻击距离",e,true) end
    c.bridge:PauseAttack();c.status="远古守护者 · 回身路线受阻，重新寻找绕行路径";return "support",e
   end
  end
  boss:Release();c.bridge.chasing=nil;c.travel.chasing=nil;c.status="远古守护者 · 撞柱晕眩，抓紧输出"
  return "attack",e
 end
 if state.stunned then state.stunned=nil;state.attack_path=nil;state.attack_retry=nil;nextpillar(state,now) end
 if boss.routes:Leap(e) then state.phase="danger";state.owns_until=nil;return end
 local charging=anim(e,"atk")
 -- 未撞晕的一轮冲锋结束、隔柱久等或绕行无进展，均改用另一处柱子。
 if state.pillar and (state.charging and not charging
  or not charging and state.wait_since and now-state.wait_since>=6
  or not charging and state.progress_time and now-state.progress_time>=8
  or not charging and state.since and now-state.since>=16) then nextpillar(state,now) end
 state.charging=charging or nil
 if not valid(state.pillar) or state.pillar:GetPosition():DistSq(ep)>28^2 then
  if state.pillar then nextpillar(state,now) end
  state.pillar=nil;state.waiting=nil;state.active=nil
  if now<(state.next_scan or 0) then return end
  state.next_scan=now+.25
  local score;local candidates={};local alternatives=false
  for _,pillar in ipairs(TheSim:FindEntities(ep.x,0,ep.z,28,{"charge_barrier"})) do if valid(pillar) then
   candidates[#candidates+1]=pillar
   if state.last_point and pillar:GetPosition():DistSq(state.last_point)>=6^2 then alternatives=true end
  end end
  for _,pillar in ipairs(candidates) do
   local bp=pillar:GetPosition();local d=ep:DistSq(bp)
   if d>.5^2 and (not alternatives or bp:DistSq(state.last_point)>=6^2) then
    local value=p:DistSq(bp)+d*.4+(d<=4^2 and 50 or 0)+((state.used or {})[key(bp)] or 0)*1000
    if not score or value<score then state.pillar,score=pillar,value;state.reset=d<=4^2 end
   end
  end
  if state.pillar then
   state.since=now;state.progress_time=now;state.progress=nil;state.direction=nil
   local point=state.pillar:GetPosition();state.pillar_point=Vector3(point.x,0,point.z)
  end
 end
 if not state.pillar then return end
 state.active=true
 local bp=state.pillar:GetPosition();local dx,dz=bp.x-ep.x,bp.z-ep.z;local len=math.sqrt(dx*dx+dz*dz)
 if len<.01 then return end
 -- 原版Brain在柱子4码内不主动起冲锋，先把它带离柱脚再回到柱后。
 if state.reset and len<6.5 then
  state.phase="transfer";state.owns_until=now+.35
  return boss:Move(Vector3(bp.x-dx/len*10,0,bp.z-dz/len*10),"远古守护者 · 先拉离柱脚，留出冲锋距离",e)
 end
 state.reset=nil
 if not state.direction or not arena9 and not charging then state.direction={x=dx/len,z=dz/len} end
 -- 第九关一轮输出后选定柱后落点；Boss小幅移动不让落点每帧绕柱旋转。
 -- 冲撞线偏离柱体时重建方向；只在柱子另一侧仍可能从柱旁穿过。
 if arena9 and not charging and state.wait_goal
  and not require("shadowself/control/guardianroute").Aligned(e,state.pillar,state.wait_goal) then
  state.direction={x=dx/len,z=dz/len};state.wait_goal=nil;state.waiting=nil
 end
 local dir=state.direction;local radius=state.pillar:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+1
 if arena9 then radius=radius*2 end
 local goal=Vector3(bp.x+dir.x*radius,0,bp.z+dir.z*radius)
 if arena9 then state.wait_goal=state.wait_goal or goal;goal=state.wait_goal end
 local distance=p:DistSq(goal)
 if not state.progress or distance<state.progress-.5^2 then state.progress=distance;state.progress_time=now end
 if charging then
  local rot=e.Transform:GetRotation()*math.pi/180;local side=math.abs(math.sin(rot)*dx+math.cos(rot)*dz)
  local forward=math.cos(rot)*dx-math.sin(rot)*dz
  if forward<0 or side>state.pillar:GetPhysicsRadius(0)+e:GetPhysicsRadius(0)-.15 then
   if arena9 then
    state.phase="danger";state.owns_until=now+.35
    if not state.danger_reported then
     state.danger_reported=true
     print(string.format("[ShadowSelf][guardian] misaligned pillar=%.2f,%.2f player=%.2f,%.2f heading=%.1f",bp.x,bp.z,p.x,p.z,e.Transform:GetRotation()))
    end
    local exit=chargeexit(c,e)
    if p:DistSq(exit)>.25^2 then
     state.danger_waiting=nil;state.waiting=nil
     return boss:Move(exit,"远古守护者 · 退出错位冲撞带，不连续外移",e)
    end
    -- 已脱离本次冲撞，只在整段返柱路线也避开冲撞线时恢复移动。
    local pass=Nav.Safe(c,goal,e) and not crosspillar(p,goal,state.pillar,c.player);local n=math.max(1,math.ceil(math.sqrt(p:DistSq(goal))/.5))
    for i=1,n do
     if not chargeclear(c,e,Vector3(p.x+(goal.x-p.x)*i/n,0,p.z+(goal.z-p.z)*i/n)) then pass=false;break end
    end
    if pass then
     state.danger_waiting=nil
     if p:DistSq(goal)<.65^2 then
      if not state.waiting and c.actions.Stop then c.actions:Stop() end
      state.waiting=true;state.phase="lure";boss:Release();c.bridge.chasing=nil;c.travel.chasing=nil
      c.status="远古守护者 · 已回柱后，等待下一次有效撞柱";return "support",e
     end
     state.waiting=nil;state.phase="transfer";return boss:Move(goal,"远古守护者 · 已避开错位冲撞，继续返回柱后",e,true)
    end
    state.waiting=nil
    if not state.danger_waiting and c.actions.Stop then c.actions:Stop() end
    state.danger_waiting=true;c.status="远古守护者 · 已在冲撞带外，等待冲锋结束后回柱"
    return "support",e
   end
   state.phase="danger";state.owns_until=nil
   local sign=(math.sin(rot)*(p.x-ep.x)+math.cos(rot)*(p.z-ep.z))<0 and -1 or 1
   state.waiting=nil
   return boss:Move(Vector3(p.x+math.sin(rot)*4*sign,0,p.z+math.cos(rot)*4*sign),"远古守护者 · 先侧躲错位冲撞，下轮重新引柱",e)
  end
 end
 if p:DistSq(goal)<.65^2 then
  state.phase="lure";state.owns_until=now+.35
  if not state.waiting and c.actions.Stop then c.actions:Stop() end
  if arena9 then boss:Release();c.bridge.chasing=nil;c.travel.chasing=nil end
  state.wait_since=state.wait_since or now
  trace(c,state,"lure",goal)
  state.waiting=true;c.status="远古守护者 · 隔柱诱导冲撞，等实际晕眩"
  return "support",e
 end
 state.waiting=nil;state.wait_since=nil
 if arena9 then
  local route=require("shadowself/control/guardianroute")
  local point=route.Point(c,goal,state.pillar,e)
  if not point then
   if not state.route_blocked then print("[ShadowSelf][guardian] transfer_blocked reselect_pillar");state.route_blocked=true end
   nextpillar(state,now);return "support",e
  end
  state.route_blocked=nil;state.phase="transfer";state.owns_until=now+.35
  trace(c,state,"transfer",goal)
  return boss:Move(point,"远古守护者 · 移到石柱背面，引导撞柱",e,true)
 end
 if not Nav.Safe(c,goal,e) or arena9 and crosspillar(p,goal,state.pillar,c.player) then
  -- 先绕柱体外沿，不直线穿过柱子走向背后。
  local theta=math.atan2(p.z-bp.z,p.x-bp.x);local wanted=math.atan2(dir.z,dir.x)
  local delta=(wanted-theta+math.pi)%(2*math.pi)-math.pi;local best,score
  for _,side in ipairs({delta<0 and -1 or 1,delta<0 and 1 or -1}) do
   local a=theta+side*.55;local point=Vector3(bp.x+math.cos(a)*radius,0,bp.z+math.sin(a)*radius)
   if Nav.Safe(c,point,e) and (not arena9 or not crosspillar(p,point,state.pillar,c.player)) then
    local value=point:DistSq(goal)+p:DistSq(point)*.2
    if not score or value<score then best,score=point,value end
   end
  end
  goal=best or Nav.Select(c,goal,e)
 end
 state.phase="transfer";state.owns_until=now+.35
 return boss:Move(goal,"远古守护者 · 移到石柱背面，引导撞柱",e)
end
function G.Dodge(c,e,base)
 if e.prefab~="minotaur" then return base end
 local s=c.bosses and c.bosses.guardian
 -- run_start的atk_pre/paw_loop也会触发普通回避；不能到atk才保护返柱移动。
 if c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==9 and s and s.target==e
  and (s.phase=="transfer" or s.phase=="lure") and valid(s.pillar) and GetTime()<(s.owns_until or 0)
  and not G.Stunned(e) and not anim(e,"bite") and not anim(e,"gore")
  and not (c.bosses.routes and c.bosses.routes:Leap(e)) then return false end
 if not anim(e,"atk") then return base end
 if c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==9 and s and s.target==e
  and s.phase=="danger" and GetTime()<(s.owns_until or 0) then
  return {atkanim="atk",point="player",dist=4,update=true,noattack=true,exclusive=true,
   fn=function() return chargeexit(c,e) end}
 end
 if c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==9 and s and s.target==e
  and (s.phase=="transfer" or s.phase=="lure") and valid(s.pillar) and GetTime()<(s.owns_until or 0) then
  -- 当前策略每次tick核对冲撞线、柱子和移动进展；普通侧闪不得覆盖这段移动。
  return false
 end
 return {atkanim="atk",point="player",dist=4,update=true,noattack=true,exclusive=true,fn=function()
  local p=c.player:GetPosition();local ep=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
  local sign=math.sin(r)*(p.x-ep.x)+math.cos(r)*(p.z-ep.z)<0 and -1 or 1
  return Nav.Select(c,Vector3(p.x+math.sin(r)*4*sign,0,p.z+math.cos(r)*4*sign),e)
 end}
end
return G
