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
function G.Tick(boss,e)
 if e.prefab~="minotaur" then return end
 local c=boss.c;local now=GetTime();local ep=e:GetPosition();local p=c.player:GetPosition()
 if G.Stunned(e) then
  if boss.guardian then boss.guardian.active=nil end
  boss:Release();c.bridge.chasing=nil;c.travel.chasing=nil;c.status="远古守护者 · 撞柱晕眩，抓紧输出"
  return "attack",e
 end
 if boss.routes:Leap(e) then return end
 local state=boss.guardian
 if not state or state.target~=e then state={target=e};boss.guardian=state end
 if not valid(state.pillar) or state.pillar:GetPosition():DistSq(ep)>28^2 then
  state.pillar=nil;state.waiting=nil;state.active=nil
  if now<(state.next_scan or 0) then return end
  state.next_scan=now+.25
  local score
  for _,pillar in ipairs(TheSim:FindEntities(ep.x,0,ep.z,28,{"charge_barrier"})) do if valid(pillar) then
   local bp=pillar:GetPosition();local d=ep:DistSq(bp)
   if d>.5^2 then
    local value=p:DistSq(bp)+d*.4+(d<=4^2 and 50 or 0)
    if not score or value<score then state.pillar,score=pillar,value;state.reset=d<=4^2 end
   end
  end end
 end
 if not state.pillar then return end
 state.active=true
 local bp=state.pillar:GetPosition();local dx,dz=bp.x-ep.x,bp.z-ep.z;local len=math.sqrt(dx*dx+dz*dz)
 if len<.01 then return end
 -- 原版Brain在柱子4码内不主动起冲锋，先把它带离柱脚再回到柱后。
 if state.reset and len<6.5 then
  return boss:Move(Vector3(bp.x-dx/len*10,0,bp.z-dz/len*10),"远古守护者 · 先拉离柱脚，留出冲锋距离",e)
 end
 state.reset=nil
 local charging=anim(e,"atk")
 if not charging or not state.direction then state.direction={x=dx/len,z=dz/len} end
 local dir=state.direction;local radius=state.pillar:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+1
 local goal=Vector3(bp.x+dir.x*radius,0,bp.z+dir.z*radius)
 if charging then
  local rot=e.Transform:GetRotation()*math.pi/180;local side=math.abs(math.sin(rot)*dx+math.cos(rot)*dz)
  local forward=math.cos(rot)*dx-math.sin(rot)*dz
  if forward<0 or side>state.pillar:GetPhysicsRadius(0)+e:GetPhysicsRadius(0)-.15 then
   local sign=(math.sin(rot)*(p.x-ep.x)+math.cos(rot)*(p.z-ep.z))<0 and -1 or 1
   state.waiting=nil
   return boss:Move(Vector3(p.x+math.sin(rot)*4*sign,0,p.z+math.cos(rot)*4*sign),"远古守护者 · 先侧躲错位冲撞，下轮重新引柱",e)
  end
 end
 if p:DistSq(goal)<.65^2 then
  if not state.waiting and c.actions.Stop then c.actions:Stop() end
  state.waiting=true;c.status="远古守护者 · 隔柱诱导冲撞，等实际晕眩"
  return "support",e
 end
 state.waiting=nil
 if not Nav.Safe(c,goal,e) then
  -- 先绕柱体外沿，不直线穿过柱子走向背后。
  local theta=math.atan2(p.z-bp.z,p.x-bp.x);local wanted=math.atan2(dir.z,dir.x)
  local delta=(wanted-theta+math.pi)%(2*math.pi)-math.pi;local best,score
  for _,side in ipairs({delta<0 and -1 or 1,delta<0 and 1 or -1}) do
   local a=theta+side*.55;local point=Vector3(bp.x+math.cos(a)*radius,0,bp.z+math.sin(a)*radius)
   if Nav.Safe(c,point,e) then
    local value=point:DistSq(goal)+p:DistSq(point)*.2
    if not score or value<score then best,score=point,value end
   end
  end
  goal=best or Nav.Select(c,goal,e)
 end
 return boss:Move(goal,"远古守护者 · 移到石柱背面，引导撞柱",e)
end
function G.Dodge(c,e,base)
 if e.prefab~="minotaur" or not anim(e,"atk") then return base end
 return {atkanim="atk",point="player",dist=4,update=true,noattack=true,exclusive=true,fn=function()
  local p=c.player:GetPosition();local ep=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
  local sign=math.sin(r)*(p.x-ep.x)+math.cos(r)*(p.z-ep.z)<0 and -1 or 1
  return Nav.Select(c,Vector3(p.x+math.sin(r)*4*sign,0,p.z+math.cos(r)*4*sign),e)
 end}
end
return G
