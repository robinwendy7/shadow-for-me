-- 第三关残局：先处理骑士，再沿冲撞线外侧提前前移，冲撞结束交还攻击动作接近。
local Nav=require("shadowself/control/navigation")
local function knight(e)
 return e and (e.prefab=="knight" or e.prefab=="knight_nightmare")
  and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead")
end
local function radius(c,e)
 local combat=e.replica and e.replica.combat
 return (combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)
  +e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.35
end
return function(c,rook,state,charging)
 state.wall_wait=nil
 local p=c.player:GetPosition();local plan=c.bridge.plan or c.plan
 local roster=plan.arena_remaining and plan.arena_remaining() or c.enemies
 local q=rook:GetPosition();local rotation=rook.Transform:GetRotation()*math.pi/180
 local fx,fz=math.cos(rotation),-math.sin(rotation);local nx,nz=-fz,fx
 local combat=rook.replica and rook.replica.combat
 -- SGrook.DoRamAOE以攻击命中距离+玩家碰撞半径检测前方75度；不能只按战车碰撞体估算。
 local hitrange=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2
 local clearance=math.max(hitrange,rook:GetPhysicsRadius(0))+c.player:GetPhysicsRadius(0)+.6
 local function penetration(point)
  if not charging then return 0 end
  local dx,dz=point.x-q.x,point.z-q.z
  local along=dx*fx+dz*fz;local side=dx*nx+dz*nz
  -- 前方整条冲撞通道含终点；后方保留圆形余量，避免紧贴战车脚下。
  return math.max(0,clearance-math.sqrt(side*side+math.min(0,along)^2))
 end
 local initial=penetration(p)
 local function safe(point,exclude)
  if penetration(point)>0 or not Nav.Safe(c,point,exclude or rook) then return false end
  local n=math.max(2,math.ceil(math.sqrt(p:DistSq(point))/.4))
  for i=1,n do
   local v=Vector3(p.x+(point.x-p.x)*i/n,0,p.z+(point.z-p.z)*i/n)
   if penetration(v)>initial+.01 then return false end
  end
  return true
 end
 local function select(wanted,exclude)
  if safe(wanted,exclude) then return wanted end
  local best,score
  for _,length in ipairs({2,3.5,5}) do for i=0,23 do
   local a=i*math.pi/12;local v=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
   if safe(v,exclude) then
    local value=v:DistSq(wanted)+p:DistSq(v)*.1
    if not score or value<score then best,score=v,value end
   end
  end end
  return best or p
 end
 local threat=state.knight
 if threat then
  local a=threat.AnimState
  local attacking=a and a:IsCurrentAnimation("atk") and a:GetCurrentAnimationFrame()<16
  if not knight(threat) or not attacking and p:DistSq(threat:GetPosition())>=(radius(c,threat)+.5)^2 then
   state.knight=nil;threat=nil
  end
 end
 for _,e in ipairs(roster or {}) do
  if knight(e) and c.bridge.allowed(e) and p:DistSq(e:GetPosition())<=radius(c,e)^2 then
   if not threat or p:DistSq(e:GetPosition())<p:DistSq(threat:GetPosition()) then threat=e end
  end
 end
 if threat then
  state.knight=threat;state.advance=nil
  local q=threat:GetPosition();local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
  if d<.01 then dx,dz,d=0,1,1 end
  local wanted=Vector3(q.x+dx/d*(radius(c,threat)+1),0,q.z+dz/d*(radius(c,threat)+1))
  return select(wanted,rook),"战车 · 优先躲开骑士，再按冲撞方向前移"
 end
 if not charging then state.advance=nil;state.follow_side=nil;state.motion=nil;state.wall_wait=nil;return end
 local now=GetTime();local motion=state.motion
 if not motion or motion.pos:DistSq(q)>.12^2 then state.motion={pos=q,since=now};state.wall_wait=nil
 elseif now-motion.since>=.35 and initial==0 and safe(p) then
  state.wall_wait=true
  return p,"战车 · 贴墙冲撞未结束，保持侧面安全位置"
 end
 local signed=(p.x-q.x)*nx+(p.z-q.z)*nz
 if initial>0 then
  state.advance=nil
  local side=signed<0 and -1 or 1
  for _,sign in ipairs({side,-side}) do
   local point=Vector3(p.x+nx*(clearance+.3-signed*sign)*sign,0,p.z+nz*(clearance+.3-signed*sign)*sign)
   if safe(point) then return point,"战车 · 侧移避开冲撞通道及终点" end
  end
  local wanted=Vector3(p.x+nx*(clearance+.3)*side,0,p.z+nz*(clearance+.3)*side)
  return select(wanted),"战车 · 绕开阻挡寻找侧面安全位置"
 end
 -- 蓄力/冲撞期间提前往冲撞方向移动，但落点始终在冲撞线外侧。
 -- 以当前朝向持续更新侧前方位置，不把未知的停止点当成安全等待点。
 state.follow_side=state.follow_side or (signed<0 and -1 or 1)
 local side=state.follow_side
 local offset=math.max(3.5,clearance+.25)
 state.advance=Vector3(q.x+nx*offset*side+fx*2,0,q.z+nz*offset*side+fz*2)
 return select(state.advance),"战车 · 沿安全侧线提前前移，冲撞结束立即攻击接近"
end
