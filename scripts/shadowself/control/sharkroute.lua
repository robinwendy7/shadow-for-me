-- SGsharkboi: 240度扇形扫击绕近背面；钻出/跳跃/鱼雷保持各自AOE间距。
local Nav=require("shadowself/control/navigation")
local R={}
local function anim(e,n) return e.AnimState and e.AnimState:IsCurrentAnimation(n) end
local function torpedo(e) return anim(e,"torpedo_pre") or anim(e,"torpedo_jump") or anim(e,"torpedo_loop") end
local function arena7(c) return c and c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==7 end
-- 第七关把原22/10/18帧窗口加倍，并跨后摇保持剩余时间。
function R.SwipeHold(c,e)
 if not arena7(c) then return false end
 local f=e.AnimState:GetCurrentAnimationFrame() or 0
 local now=GetTime();local state=c.shark_swipe_hold
 for _,v in ipairs({{"atk1",44},{"atk2",20},{"atk3",36}}) do if anim(e,v[1]) then
  if not state or state.target~=e or state.name~=v[1] or f<(state.frame or 0) then
   state={target=e,name=v[1],untiltime=now+(v[2]-f)/30};c.shark_swipe_hold=state
  end
  state.frame=f
  return f<=v[2]
 end end
 if anim(e,"atk2_delay") then return true end
 if state and state.target==e and (anim(e,state.name.."_pst") or anim(e,"idle") or anim(e,"idle_loop") or anim(e,"walk_loop") or anim(e,"taunt")) then
  return now<=state.untiltime
 end
 c.shark_swipe_hold=nil;return false
end
local function releasefollow(c)
 if c.shark_follow_hand then
  if c.gear and c.gear.patrol_hand==c.shark_follow_hand then c.gear.patrol_hand=c.shark_follow_saved end
  if c.gear and c.gear.pending and c.gear.pending.item==c.shark_follow_hand then
   c.gear.pending=nil;c.gear.next_request=0 -- 滑行已结束，不再等过期的手杖装备请求。
  end
  c.shark_follow_hand=nil;c.shark_follow_saved=nil
 end
 if c.shark_follow_owner then
  c.shark_follow_owner:Release();c.shark_follow_owner=nil
  if c.travel then c.travel.chasing=nil end
  if c.bridge then c.bridge.chasing=nil end
  if c.gear and c.gear.Swap then c.gear:Swap("attack",c.snapshot) end
 end
end
function R.Rear(c,e)
 local p=c.player:GetPosition();local q=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local d=math.sqrt(p:DistSq(q));if d<.01 then return false end
 return ((p.x-q.x)*math.cos(r)-(p.z-q.z)*math.sin(r))/d<=-math.cos(15*math.pi/180)
end
-- 准备阶段可抢两刀；按实际动画剩余时长保留离开跳跃/滑行判定的时间。
function R.PreAttack(c,e)
 if not e or e.prefab~="sharkboi" or not c.plan or not c.plan.arena or not c.plan.arena_wave or c.plan.arena_wave()~=7 then return false end
 if not anim(e,"torpedo_pre") then c.shark_pre=nil;return false end
 local f=e.AnimState:GetCurrentAnimationFrame() or 0;local state=c.shark_pre
 if not state or state.target~=e or f<(state.frame or 0) then state={target=e,hits=0};c.shark_pre=state end
 state.frame=f
 local p=c.player;local d=math.sqrt(p:GetPosition():DistSq(e:GetPosition()))
 local combat=p.replica and p.replica.combat
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)+e:GetPhysicsRadius(0)
 local pf=p.AnimState and p.AnimState:GetCurrentAnimationFrame() or 0
 local raw=p.AnimState and require("shadowself/native").Get().ENT_util:GetAnimation(p)
 if p:HasTag("attack") then
  if not state.attacking or raw~=state.animation or pf<(state.player_frame or 0) then state.counted=nil end
  if not state.counted and d<=reach and c.h and c.h.ent==e and c.h.IsHitingFrame and c.h:IsHitingFrame(0,e,true) then state.hits=state.hits+1;state.counted=true end
 else state.counted=nil end
 state.attacking=p:HasTag("attack");state.player_frame=pf;state.animation=raw
 local length=e.AnimState.GetCurrentAnimationLength and e.AnimState:GetCurrentAnimationLength() or 1.2
 local speed=math.max(1,math.min(6,c.Speed and c:Speed() or 6))
 local exit=math.max(0,3+p:GetPhysicsRadius(0)+.8-d)/speed
 local reserve=exit+require("shadowself/control/nettiming").Delay(c)+.15
 return state.hits<2 and d<=reach and length-f/30>reserve
end
function R.Committed(c,e)
 if not c or not e or e.prefab~="sharkboi" then return false end
 if not anim(e,"torpedo_loop") then releasefollow(c) end
 if R.PreAttack(c,e) then c.shark_charge_seen=e;c.shark_recovery=nil;return true end
 local active=torpedo(e)
 if active then c.shark_charge_seen=e;c.shark_recovery=nil
 elseif c.shark_charge_seen==e then c.shark_charge_seen=nil;c.shark_recovery=e end
 for _,name in ipairs({"atk1","atk2","atk2_delay","atk3","ice_summon","icedive_standing_jump_pre","icedive_jump_pre","icedive_jump","icedive_dig_pre","icedive_dig_pst","spawn"}) do
  if anim(e,name) then
   c.shark_recovery=nil
   if not R.Rear(c,e) or name~="atk1" and name~="atk2" and name~="atk2_delay" and name~="atk3" then c.shark_attack_window=nil end
  end
 end
 if active then c.shark_attack_window=nil end
 if R.SwipeHold(c,e) then c.shark_attack_window=nil;return false end
 return not active and (c.shark_recovery==e or c.shark_attack_window==e and R.Rear(c,e))
end
-- 滑行时沿安全侧后方跟随实时位置；不能将“已躲出冲撞线”变成原地等待。
function R.SlidePoint(c,e,safe)
 local p=c.player:GetPosition();local q=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local radius=3+c.player:GetPhysicsRadius(0)+1.4
 local back=math.pi-r;local theta=math.atan2(p.z-q.z,p.x-q.x)
 local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
 local function clear(point)
  if not Nav.Safe(c,point,e) then return false end
  local n=math.max(2,math.ceil(math.sqrt(p:DistSq(point))/.4))
  for i=0,n do
   if not safe(Vector3(p.x+(point.x-p.x)*i/n,0,p.z+(point.z-p.z)*i/n)) then return false end
  end
  return true
 end
 local tail=Vector3(q.x+math.cos(back)*radius,0,q.z+math.sin(back)*radius)
 if clear(tail) then return tail end
 local sign=delta<0 and -1 or 1
 for _,side in ipairs({sign,-sign}) do
  local a=theta+side*math.min(.45,math.abs(delta))
  local v=Vector3(q.x+math.cos(a)*radius,0,q.z+math.sin(a)*radius)
  if clear(v) then return v end
 end
 return p
end
function R.Block(c,e)
 if not e or e.prefab~="sharkboi" then return false end
 if R.PreAttack(c,e) then return false end
 if R.SwipeHold(c,e) then return true end
 R.Committed(c,e)
 if torpedo(e) then return true end
 if c.shark_recovery==e or R.Rear(c,e) then return false end
 return c.shark_swipe==e
  or anim(e,"atk1") or anim(e,"atk1_pst") or anim(e,"atk2") or anim(e,"atk2_pst") or anim(e,"atk2_delay") or anim(e,"atk3") or anim(e,"atk3_pst")
end
-- 实际扫击以身前2码为圆心、半径3.5、240度截面判定；供绕背检查与取证使用。
function R.SwipeDanger(c,e,q)
 local p=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local dx,dz=q.x-p.x-2*math.cos(r),q.z-p.z+2*math.sin(r)
 local radius=3.5+c.player:GetPhysicsRadius(0)
 return dx*dx+dz*dz<radius^2 and dx*math.cos(r)-dz*math.sin(r)>-1.75
end
function R.SwipePoint(c,e)
 local p=c.player:GetPosition();local ep=e:GetPosition()
 if R.Rear(c,e) then return p end
 local body=e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)
 -- 已在较远正面时，赶不到背面就先退出真实偏心圆，不把“4~5码”误当安全。
 if math.sqrt(p:DistSq(ep))>body+1.5 and R.SwipeDanger(c,e,p) then
  local r=e.Transform:GetRotation()*math.pi/180
  local center=Vector3(ep.x+2*math.cos(r),0,ep.z-2*math.sin(r))
  local dx,dz=p.x-center.x,p.z-center.z;local length=math.sqrt(dx*dx+dz*dz)
  if length>.01 then
   local radius=3.5+c.player:GetPhysicsRadius(0)+.45
   local q=Vector3(center.x+dx/length*radius,0,center.z+dz/length*radius)
   if not R.SwipeDanger(c,e,q) and Nav.Safe(c,q,e) then return q end
  end
 end
 -- 远处开始躲避时保留当前半径；禁止在挥击中从4~5码径直切到1.8码。
 local radius=math.max(body+.3,math.sqrt(p:DistSq(ep)))
 local theta=math.atan2(p.z-ep.z,p.x-ep.x)
 local back=math.pi-e.Transform:GetRotation()*math.pi/180
 local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
 local preferred=delta<0 and -1 or 1
 for _,side in ipairs({preferred,-preferred}) do for _,step in ipairs({.7,.45,.25}) do
  local a=theta+side*math.min(step,math.abs(delta));local q=Vector3(ep.x+math.cos(a)*radius,0,ep.z+math.sin(a)*radius)
  local clear=Nav.Safe(c,q,e)
  local n=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.2))
  for i=0,n do
   local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
   if v:DistSq(ep)<(body+.04)^2 then clear=false;break end
  end
  if clear then return q end
 end end
 return p
end
function R.Prepare(boss,e)
 if e.prefab~="sharkboi" then return end
 local c=boss.c
 if R.PreAttack(c,e) then boss:Release();return "attack",e end
 if anim(e,"torpedo_loop") then
  if arena7(c) then
   c.shark_follow_owner=boss
   local cane=require("shadowself/control/arena_tools").Owned(c,"cane")
   if cane and c.gear then
    if not c.shark_follow_hand then c.shark_follow_saved=c.gear.patrol_hand end
    c.shark_follow_hand=cane;c.gear.patrol_hand=cane
    if c.gear.Swap then c.gear:Swap("move",c.snapshot) end
   end
  end
  local data=R.Dodge(c,e,false)
  if data then return boss:Move(data:fn(),"鲨鱼 · 手杖跟随滑行，停下立即恢复武器攻击",e) end
 end
 if R.SwipeHold(c,e) then
  local data=R.Dodge(c,e,false)
  if data and data.fn then return boss:Move(data:fn(),"鲨鱼 · 延长挥击回避，后摇结束前保持安全位置",e) end
 end
 if arena7(c) and (anim(e,"atk1") or anim(e,"atk1_pst") or anim(e,"atk2") or anim(e,"atk2_pst")
  or anim(e,"atk2_delay") or anim(e,"atk3") or anim(e,"atk3_pst")) then
  local data=R.Dodge(c,e,false)
  if data and data.fn then return boss:Move(data:fn(),"鲨鱼 · 挥击立即绕背，连击结束前禁止向内切近",e) end
 end
 if R.Committed(c,e) then return end
 if not (anim(e,"idle") or anim(e,"idle_loop") or anim(e,"walk_loop") or anim(e,"taunt")) then return end
 local p=c.player:GetPosition();local q=e:GetPosition();local d=math.sqrt(p:DistSq(q))
 local touch=e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.1
 if d>touch+.15 then
  return boss:Move(Vector3(q.x+(p.x-q.x)/d*touch,0,q.z+(p.z-q.z)/d*touch),"鲨鱼 · 先贴近缩短下次绕背路径",e)
 end
end
function R.IceState(c,e)
 c.shark_ice=c.shark_ice or {};local state=c.shark_ice[e]
 local f=e.AnimState:GetCurrentAnimationFrame() or 0
 if anim(e,"ice_summon") then
  if not state or not state.summoning or f<(state.frame or 0) then state={summoning=true};c.shark_ice[e]=state end
  state.frame=f
  if not state.locked then
   state.rotation=e.Transform:GetRotation();state.pos=e:GetPosition()
   if f>=35 then state.locked=true;state.untiltime=GetTime()+math.max(0,(58-f)/30)+.3 end
  end
 elseif state then state.summoning=nil end
 return state
end
function R.IceZones(c,e)
 local state=R.IceState(c,e);local zones={}
 if not state or not state.locked or GetTime()>=(state.untiltime or 0) then return zones end
 local theta=state.rotation*math.pi/180;local pos=state.pos
 -- 原版每侧20根，间隔1.65码，漂移可达±1.5；前方整条生长区都避开。
 for distance=4,34,5 do
  zones[#zones+1]={pos=Vector3(pos.x+math.cos(theta)*distance,0,pos.z-math.sin(theta)*distance),radius=6.1,source=e,ice_rail=true}
 end
 return zones
end
function R.Dodge(c,e,base)
 local a=e.AnimState;local f=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
 local swipe=R.SwipeHold(c,e) or anim(e,"atk1") and f<=16 or anim(e,"atk2") and f<=4 or anim(e,"atk2_delay") or anim(e,"atk3") and f<=12
 local ice=anim(e,"ice_summon") and f<58
 local ice_state=R.IceState(c,e)
 local emerging=anim(e,"icedive_standing_jump_pre") or anim(e,"icedive_dig_pst") and f<4 or anim(e,"icedive_jump_pre") or anim(e,"icedive_jump") or anim(e,"icedive_dig_pre") or anim(e,"spawn") and f<20
 local torpedo=torpedo(e)
 local committed=R.Committed(c,e)
 if swipe then c.shark_swipe=e end
 local lingering=c.shark_swipe==e and (anim(e,"atk1") or anim(e,"atk1_pst") or anim(e,"atk2") or anim(e,"atk2_pst") or anim(e,"atk3") or anim(e,"atk3_pst"))
 if lingering and not R.Rear(c,e) then swipe=true end
 if not lingering and not swipe then c.shark_swipe=nil end
 if not torpedo then c.shark_torpedo=nil end
 if committed then return false end
 if swipe and R.Rear(c,e) and not R.SwipeHold(c,e) then c.shark_attack_window=e;return false end
 if not swipe and not emerging and not torpedo and not ice then return base end
 local name
 for _,n in ipairs({"atk1","atk1_pst","atk2","atk2_pst","atk2_delay","atk3","atk3_pst","ice_summon","torpedo_pre","torpedo_jump","torpedo_loop","torpedo_climb","torpedo_pst","idle","idle_loop","walk_loop","taunt","icedive_standing_jump_pre","icedive_jump_pre","icedive_jump","icedive_dig_pre","icedive_dig_pst","spawn"}) do if anim(e,n) then name=n;break end end
 local data={atkanim=name,point="target",dist=swipe and 3 or ice and 6 or torpedo and 4 or 3.1,update=true,exclusive=true,noattack=true}
 if ice then
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition();local rot=(ice_state and ice_state.rotation or e.Transform:GetRotation())*math.pi/180
   local back=math.pi-rot;local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
   local side=delta<0 and -1 or 1;local radius=math.max(3.4,math.min(4.2,math.sqrt(p:DistSq(ep))))
   local hazards={};for _,h in ipairs(c.hazards or {}) do hazards[#hazards+1]=h end
   for _,h in ipairs(R.IceZones(c,e)) do hazards[#hazards+1]=h end
   local view=setmetatable({hazards=hazards},{__index=c})
   for _,sign in ipairs({side,-side}) do
    local a=theta+sign*math.min(.65,math.abs(delta));local point=Vector3(ep.x+math.cos(a)*radius,0,ep.z+math.sin(a)*radius)
    if Nav.Safe(view,point,e) then return point end
   end
   return Nav.Select(view,Vector3(ep.x+math.cos(back)*radius,0,ep.z+math.sin(back)*radius),e)
  end
 elseif swipe then
  data.fn=function()
   if arena7(c) then return R.SwipePoint(c,e) end
   local p=c.player:GetPosition();local ep=e:GetPosition();local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local back=math.pi-e.Transform:GetRotation()*math.pi/180;local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
   if R.Rear(c,e) then return p end
   local body=(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or 1)+(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)
   local radius=math.max(body+.15,math.min(body+.3,math.sqrt(p:DistSq(ep))))
   local preferred=delta<0 and -1 or 1
   for _,side in ipairs({preferred,-preferred}) do
    local step=math.min(.55,math.abs(delta));local v=Vector3(ep.x+math.cos(theta+side*step)*radius,0,ep.z+math.sin(theta+side*step)*radius)
    if Nav.Safe(c,v,e) then return v end
   end
   return Nav.Select(c,Vector3(ep.x+math.cos(back)*radius,0,ep.z+math.sin(back)*radius),e)
  end
 else
  -- 地下跃出是全圆近身伤害，不能把它当作扫击贴身绕背。
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition();local radius=data.dist+c.player:GetPhysicsRadius(0)+.3
   local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local rot=e.Transform:GetRotation()*math.pi/180
   if torpedo then
    local state=c.shark_torpedo
    local clear=3+c.player:GetPhysicsRadius(0)+.8
    local function safe(q)
     local dx,dz=q.x-ep.x,q.z-ep.z
     local along=dx*math.cos(rot)-dz*math.sin(rot)
     local lateral=math.abs(dx*math.sin(rot)+dz*math.cos(rot))
     return dx*dx+dz*dz>=(2.5+c.player:GetPhysicsRadius(0)+.5)^2
      and (lateral>=clear or along<=-clear)
    end
    if safe(p) then
     if anim(e,"torpedo_loop") then return R.SlidePoint(c,e,safe) end
     return p
    end
    if not state or state.target~=e or not safe(state.point) then
     local nx,nz=math.sin(rot),math.cos(rot);local signed=nx*(p.x-ep.x)+nz*(p.z-ep.z)
     local sign=state and state.side or (signed<0 and -1 or 1)
     local goal,score
     for _,side in ipairs({sign,-sign}) do
      for _,turn in ipairs({math.pi/2,math.pi}) do
       local angle=-rot+side*turn;local r=clear+.5
       local q=Vector3(ep.x+math.cos(angle)*r,0,ep.z+math.sin(angle)*r)
       if safe(q) and Nav.Safe(c,q,e) then
        local value=p:DistSq(q)+(side~=sign and 10 or 0)
        if not score or value<score then goal,score=q,value end
       end
      end
     end
     local fallback=Vector3(p.x+nx*(clear-math.abs(signed)+.5)*sign,0,p.z+nz*(clear-math.abs(signed)+.5)*sign)
     state={target=e,side=sign,point=goal or Nav.Select(c,fallback,e)};c.shark_torpedo=state
    end
    return state.point
   end
   return Nav.Select(c,Vector3(ep.x+math.cos(theta)*radius,0,ep.z+math.sin(theta)*radius),e)
  end
 end
 return data
end
return R
