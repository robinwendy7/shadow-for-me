-- Source-specific extensions. Ordinary monsters retain the embedded 3014 tables.
local A=require("shadowself/control/actions")
local Plant=require("shadowself/control/plant")
local Nav=require("shadowself/control/navigation")
local Boss=Class(function(self,c) self.c=c;self.seen={};self.bombs={};self.bishopshots=setmetatable({},{__mode="k"});self.rooks={};self.routes=require("shadowself/control/routes")(self) end)
local function anim(e,n) return e and e.AnimState and e.AnimState:IsCurrentAnimation(n) end
local function frame(e) return e.AnimState:GetCurrentAnimationFrame() or 0 end
local function live(e) return e and e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") end
local function dist(a,b) return math.sqrt(a:DistSq(b)) end
local function rawanim(e) return require("shadowself/native").Get().ENT_util:GetAnimation(e) end
function Boss:Item(name)
 self.item_choice=self.item_choice or {}
 local p=self.c.player;local gear=self.c.gear
 return require("shadowself/control/itemchoice").Pick(self.item_choice,name,A.Items(p),p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS),gear and gear.pending)
end
function Boss:Move(q,label,target,verified)
 local c=self.c;c.bridge:PauseAttack();c.travel:BeginDodge(c.snapshot)
 c:Move(verified and q or Nav.Select(c,q,target),label);self.moving=true;return "move",target
end
function Boss:Release()
 if self.moving then self.c.travel:EndDodge(self.c.snapshot);self.moving=nil end
end
function Boss:Away(e,r,label)
 local p=self.c.player:GetPosition();local q=e:GetPosition();local d=math.max(.01,dist(p,q))
 return self:Move(Vector3(q.x+(p.x-q.x)/d*r,0,q.z+(p.z-q.z)/d*r),label,e)
end
function Boss:Select(e)
 self.c.bridge.priority_target=e;self.c.bridge.resume_target=e;return e
end
-- 骑士残局每次挥击均先完整退到攻击圈外，再恢复攻击。
function Boss:KnightState(e)
 if not require("shadowself/control/targetpolicy").KnightOnly(self.c.bridge,e) then return end
 local c=self.c;local p=c.player:GetPosition();local q=e:GetPosition()
 local combat=e.replica and e.replica.combat
 local radius=(combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)
  +e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.5
 self.knights=self.knights or {};local s=self.knights[e]
 local early=anim(e,"atk") and frame(e)<16
 if s and not early and p:DistSq(q)>=(radius+.3)^2 then self.knights[e]=nil;return end
 if not s and early and p:DistSq(q)<=(radius+.5)^2 then s={};self.knights[e]=s end
 if not s then return end
 if self.knight_engaged then self.knight_engaged[e]=nil end
 local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
 if d<.01 then dx,dz,d=0,1,1 end
 s.point=Nav.Select(c,Vector3(q.x+dx/d*(radius+1),0,q.z+dz/d*(radius+1)),e)
 return s
end
function Boss:Knight(e)
 local s=self:KnightState(e)
 self.knight_engaged=self.knight_engaged or {}
 if s then self.knight_engaged[e]=nil;return self:Move(s.point,"骑士 · 完成躲避后再攻击",e) end
 if not require("shadowself/control/targetpolicy").KnightOnly(self.c.bridge,e) then return end
 if anim(e,"atk") and frame(e)<16 then self.c.bridge:PauseAttack();return "support",e end
 if not self.knight_engaged[e] then
  local p=self.c.player:GetPosition();local q=e:GetPosition();local d=dist(p,q)
  local touch=e:GetPhysicsRadius(0)+self.c.player:GetPhysicsRadius(0)+.1
  if d>touch+.15 then
   return self:Move(Vector3(q.x+(p.x-q.x)/d*touch,0,q.z+(p.z-q.z)/d*touch),"骑士 · 贴至最近位置再连续攻击",e)
  end
  self.knight_engaged[e]=true
 end
 self:Release();return "attack",e
end
function Boss:KnightCommitted(e)
 return e and self.knight_engaged and self.knight_engaged[e]
  and require("shadowself/control/targetpolicy").KnightOnly(self.c.bridge,e) and not self:KnightState(e) or false
end
-- 同一出手帧可被索敌、禁攻及监督器多次观察，只计一次；两刀后锁到下一次真实冲撞。
function Boss:RookObserve(target,s)
 local c=self.c;local pa=rawanim(c.player);local f=frame(c.player);local attacking=c.player:HasTag("attack")
 if attacking then
  if not s.wasattack or s.pa~=pa or f<(s.pf or 0) then s.counted=nil end
  local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or 2)+target:GetPhysicsRadius(0)
  local plan=c.plan or c.bridge.plan
  local inrange=not (plan and plan.arena) or c.h.ent==target and c.player:GetPosition():DistSq(target:GetPosition())<=reach^2
  if s.ready and not s.counted and inrange
   and c.h.IsHitingFrame and c.h:IsHitingFrame(0,target,true) then s.hits=s.hits+1;s.counted=true end
 else s.counted=nil end
 s.wasattack=attacking;s.pa=pa;s.pf=f
 if s.ready and s.hits>=2 then s.ready=false;s.wait=true;if c.actions and c.actions.Stop then c.actions:Stop() end end
 return s.wait
end
-- Rook recovery is a two-completed-swing budget, not two RPC requests.
function Boss:Rook(target)
 if target.prefab~="rook" and target.prefab~="rook_nightmare" then return end
 local c=self.c;local s=self.rooks[target] or {hits=0};self.rooks[target]=s
 local charging=anim(target,"atk");local stopped=anim(target,"atk_skid") or anim(target,"atk_collide")
 local endgame=require("shadowself/control/targetpolicy").ClockworkRook(c.bridge)==target
 local preparing=anim(target,"atk_pre") or anim(target,"paw_loop")
 if endgame and preparing then
  if not s.wait and require("shadowself/control/arena_rook_window").Allow(c,target) then
   s.ready=true;s.wait=nil;self:Release();return "attack",target
  end
  if c.rook_window and c.rook_window.target==target and c.rook_window.hits>=2 then s.wait=true end
  s.ready=false
 elseif endgame then c.rook_window=nil end
 if charging then s.charged=true;s.hits=0;s.ready=false;s.wait=nil;s.wait_side=nil;s.wait_standing=nil end
 -- 骑士躲避期间也持续确认战车收尾，不能因此丢失之后两刀的输出窗。
 if stopped and (not s.stopped or s.charged) then
  s.initialized=true;s.charged=nil;s.ready=true;s.hits=0;s.wait=nil
 end
 s.stopped=stopped
 if endgame then
  local goal,label=require("shadowself/control/arena_rook")(c,target,s,charging or preparing and not s.wait)
  if goal then
   if s.wall_wait then
    c.bridge:PauseAttack();c.bridge.chasing=nil;c.travel.chasing=nil
    if not s.wall_standing then c.actions:Stop();s.wall_standing=true end
    c.status=label;return "support",target
   end
   s.wall_standing=nil
   c.bridge.chasing=true;c.travel.chasing=true
   return self:Move(goal,label,target)
  end
 end
 if charging then
  s.charged=true;s.hits=0;s.ready=false
  local p=c.player:GetPosition();local q=target:GetPosition();local r=target.Transform:GetRotation()*math.pi/180
  local dx,dz=p.x-q.x,p.z-q.z
  local along=dx*math.cos(r)-dz*math.sin(r);local side=math.abs(dx*math.sin(r)+dz*math.cos(r))
  if along< -1 or side>target:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+1 then
   s.wait=nil;c.bridge.chasing=true;c.travel.chasing=true
   return self:Move(Vector3(q.x-math.cos(r)*2.2,0,q.z+math.sin(r)*2.2),"战车 · 躲开冲撞线后立即追尾",target)
  end
 end
 -- 只有实际看到冲刺收尾才能开输出窗；首次接管/普通待机不算初始化。
 if self:RookObserve(target,s) then c.bridge:PauseAttack() end
 if s.wait then
  if charging then s.wait=nil
  elseif endgame then
   local q=target:GetPosition();local pos=c.player:GetPosition();local angle=target.Transform:GetRotation()*math.pi/180
   local nx,nz=math.sin(angle),math.cos(angle)
   s.wait_side=s.wait_side or ((pos.x-q.x)*nx+(pos.z-q.z)*nz<0 and -1 or 1)
   local goal=Vector3(q.x+nx*3.5*s.wait_side,0,q.z+nz*3.5*s.wait_side)
   if pos:DistSq(goal)<.4^2 and Nav.Safe(c,goal,target) then
    if not s.wait_standing then c.actions:Stop();s.wait_standing=true end
    self:Release();return "support",target
   end
   s.wait_standing=nil;return self:Move(goal,"战车 · 两刀后侧旁待机，等下一次冲撞",target)
  else return self:Away(target,6,"战车 · 两刀后游离身旁，等下一次冲撞") end
 end
 if not charging and not s.ready then return self:Away(target,endgame and 3.5 or 6,"战车 · 游离身旁，等冲刺结束再输出") end
 -- After the charge line no longer intersects us, native chase resumes immediately.
 if not charging and s.ready then self:Release();return "attack",target end
end
local function waking(e)
 local n=rawanim(e) or ""
 return n:find("tired_wakeup",1,true) or n:find("tired_pst",1,true)
end
function Boss:AttackBlocked(e)
 if not require("shadowself/control/arena_doc_control").Allowed(self.c,e) then return true end
 if require("shadowself/control/arena_doc_control").Continuous(self.c,e) then return false end
 if not require("shadowself/control/arena_rabbit").Allowed(self.c,e) then return true end
 if self.c.plan and self.c.plan.arena_lunar12 and e and e:HasTag("NOCLICK") then return true end
 local stage12=self.c.plan and self.c.plan.arena_stage12
 if not require("shadowself/control/arena_doc_control").Late(self.c) and stage12 and not stage12:Allowed(e) then return true end
 local stage=self.c.plan and self.c.plan.arena_stage11
 if stage and not stage:Allowed(e) then return true end
 if require("shadowself/control/boneguard").Tank(self.c,e) then return false end
 if require("shadowself/control/arena_attackwindows").Block(self.c,e) then return true end
 if require("shadowself/control/arena_windcycle").Blocked(self.c) then return true end
 if not require("shadowself/control/arena_center").AttackAllowed(self.c,e) then return true end
 if not require("shadowself/control/arena_swamp").Allowed(self.c,e) then return true end
 if not require("shadowself/control/arena_salamanders").Allowed(self.c,e) then return true end
 if require("shadowself/control/sharkroute").Block(self.c,e) then return true end
 if require("shadowself/control/arena_moose").Block(self.c,e) then return true end
 if self.moon_hold then return true end
 if self.c.brightshade_target and not Plant.Weak(self.c.brightshade_target) then self.c.brightshade_target=nil end
 if self.c.brightshade_target and e~=self.c.brightshade_target then return true end
 if not e then return false end
 if self:KnightState(e) then return true end
 if require("shadowself/control/targetpolicy").KnightOnly(self.c.bridge,e) and not self:KnightCommitted(e) then return true end
 local rook=require("shadowself/control/targetpolicy").ClockworkRook(self.c.bridge)
 if rook and e~=rook then return true end
 if rook==e and self.rooks[e] and not anim(e,"atk") and self:RookObserve(e,self.rooks[e]) then return true end
 if rook==e and (anim(e,"atk_pre") or anim(e,"paw_loop")) then return not require("shadowself/control/arena_rook_window").Allow(self.c,e) end
 if (e.prefab=="rook" or e.prefab=="rook_nightmare") and (anim(e,"atk") or not (self.rooks[e] and self.rooks[e].ready)) then return true end
 if e.prefab=="mutatedbearger" and not require("shadowself/control/openings").Bear(self.c,e) then
  for _,zone in ipairs(self.c.hazards or {}) do if zone.bearger_pit and e:GetPosition():DistSq(zone.pos)<zone.radius^2 then return true end end
 end
 if e.prefab=="minotaur" and self.guardian and self.guardian.target==e and self.guardian.active and not require("shadowself/control/guardian").Stunned(e) and not self.routes:Leap(e) then return true end
 if e.prefab=="rabbitking_aggressive" and (anim(e,"dropkick_pre") or anim(e,"dropkick_loop") or anim(e,"spawn_pre") or anim(e,"spawn_loop") or anim(e,"despawn") and frame(e)>=47) then return true end
 return e:HasTag("lunarthrall_plant") and waking(e) or (e.prefab=="slurtle" or e.prefab=="snurtle") and (e:HasTag("shell") or anim(e,"hide") or anim(e,"hide_loop") or anim(e,"emerge"))
end
function Boss:WeakHead()
 local p=self.c.player:GetPosition();local best,near
 for _,e in ipairs(self.c.enemies) do
  if Plant.Weak(e) then
   local d=p:DistSq(e:GetPosition());if not near or d<near then best,near=e,d end
  end
 end
 return best
end
function Boss:Brightshade(target)
 if not target:HasTag("lunarthrall_plant") and not target:HasTag("lunarthrall_plant_end") and not Plant.Middle(target) then self.c.brightshade_target=nil;return end
 local c=self.c;local p=c.player:GetPosition();local head,weak,near
 for _,e in ipairs(c.enemies) do if live(e) and e:HasTag("lunarthrall_plant") then
  head=head or e
  if Plant.Weak(e) then local d=p:DistSq(e:GetPosition());if not near or d<near then weak,near=e,d end end
 end end
 if weak then c.brightshade_target=weak;self:Release();return "attack",self:Select(weak) end
 c.brightshade_target=nil
 if target:HasTag("lunarthrall_plant") and waking(target) then return self:Away(target,6,"亮茄 · 即将苏醒，先停止输出撤开") end
 local cut,endpoint,score
 for _,e in ipairs(c.enemies) do
  if live(e) and (Plant.Middle(e) or not e:HasTag("NOCLICK") and e:HasTag("lunarthrall_plant_end")) then
   local d=p:DistSq(e:GetPosition())
   if Plant.Middle(e) then if not score or d<score then cut,score=e,d end
   elseif not endpoint or d<p:DistSq(endpoint:GetPosition()) then endpoint=e end
  end
 end
 if cut then self:Release();return "attack",self:Select(cut) end
 if endpoint and head and endpoint:GetPosition():DistSq(head:GetPosition())>=5^2 then self:Release();return "attack",self:Select(endpoint) end
 if head then return self:Away(head,8,"亮茄 · 先引长藤蔓，随后切断中段") end
 if endpoint then self:Release();return "attack",self:Select(endpoint) end
end
function Boss:Shell(target)
 if self.c.plan and self.c.plan.arena then
  local mode,picked=require("shadowself/control/arena_snails").Tick(self,target)
  if mode then return mode,picked end
 end
 if target.prefab~="slurtle" and target.prefab~="snurtle" then return end
 if self:AttackBlocked(target) then
  self.c.bridge:PauseAttack()
  if self.shell_wait~=target then self.c.actions:Stop();self.shell_wait=target end
  for _,e in ipairs(self.c.enemies) do if e~=target and self.c.bridge.allowed(e) and not self:AttackBlocked(e) then return "attack",self:Select(e) end end
  return "support",target
 end
 self.shell_wait=nil
end
function Boss:MoonHolding()
 local c=self.c;local p=c.player:GetPosition();local now=GetTime();local incoming=false;local casting=false
 for _,e in ipairs(self.ghosts or {}) do
  local q=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
  if p:DistSq(q)<14^2 and ((p.x-q.x)*math.cos(r)-(p.z-q.z)*math.sin(r)>-.5 or p:DistSq(q)<2.5^2) then incoming=true end
 end
 for _,e in ipairs(self.entities or {}) do if e.prefab=="alterguardian_summon_fx" and e:IsValid() and p:DistSq(e:GetPosition())<22^2 then casting=true end end
 if incoming or casting then self.moon_until=now+.3 end
 self.moon_hold=now<(self.moon_until or 0);self.moon_incoming=incoming
 return self.moon_hold
end
function Boss:BombPoint()
 local c=self.c;local p=c.player:GetPosition();local bomb=self.bomb_imminent
 local state=self.bomb_run
 if not bomb and (not state or GetTime()>=(state.untiltime or 0)) then self.bomb_run=nil;return end
 if bomb and (not state or state.bomb~=bomb) then
  local target=c.h and c.h.ent;local q=target and target:GetPosition() or Vector3(p.x-1,0,p.z)
  local d=math.max(.01,dist(p,q));state={bomb=bomb,x=(p.x-q.x)/d,z=(p.z-q.z)/d};self.bomb_run=state
 end
 if bomb then state.untiltime=GetTime()+.8 end
 local goal=Vector3(p.x+state.x*4,0,p.z+state.z*4)
 return Nav.Select(c,goal,c.h and c.h.ent)
end

function Boss:Ignite(target,s)
 local c=self.c;local p=c.player;local now=GetTime()
 local fire=self:Item("firestaff")
 if not fire then
  local pos=p:GetPosition()
  for _,e in ipairs(TheSim:FindEntities(pos.x,0,pos.z,10,{"_inventoryitem"},{"INLIMBO"})) do
   if e.prefab=="firestaff" and e:IsValid() and Nav.Safe(c,e:GetPosition(),target) then
    c.bridge:PauseAttack()
    if not p.components.playercontroller:IsBusy() and now>=(s.nextpickup or 0) then
     local wave=c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave() or 1
     if not require("shadowself/control/arena_pickup_travel").Ready(s,p,wave,e,c) then return "support",target end
     A.Scene(p,e,ACTIONS.PICKUP);s.nextpickup=now+.6
    end
    return "support",target
   end
  end
  fire=self:Item("torch")
 end
 if not fire then return end
 c.bridge:PauseAttack();c.bridge.chasing=nil;c.travel.chasing=nil
 c.gear.forced_weapon=fire;c.travel.dodging=nil;c.travel.restore_dodge=nil;self.moving=nil
 local distance=dist(p:GetPosition(),target:GetPosition())
 local reach=fire.prefab=="firestaff" and 8 or 2+target:GetPhysicsRadius(0)
 if distance>reach then
  local q=target:GetPosition();local pos=p:GetPosition()
  local goal=Vector3(q.x+(pos.x-q.x)/distance*(reach-.1),0,q.z+(pos.z-q.z)/distance*(reach-.1))
  if Nav.Safe(c,goal,target) then return self:Move(goal,fire.prefab=="firestaff" and "晶鹿 · 只到火杖射程，不贴身" or "晶鹿 · 第二发落点已避开，近身火把点燃",target) end
  return "support",target
 end
 if c.mechanisms:Equip(fire) and not p.components.playercontroller:IsBusy() and now>=(s.nextfire or 0) then
  A.Attack(p,target);s.nextfire=now+.5
 end
 return "support",target
end
function Boss:Crystal(target)
 if target.prefab~="mutateddeerclops" then return end
 local c=self.c;local now=GetTime();local s=self.crystal
 if not s or s.target~=target then s={target=target,throws=0};self.crystal=s end
 local f=frame(target);local first=anim(target,"throw");local second=anim(target,"throw_2")
 local weak=anim(target,"stagger_pre") or anim(target,"stagger") or anim(target,"stagger_hit")
 local burning_eye=anim(target,"struggle_pre") or anim(target,"struggle_loop") or anim(target,"struggle_pst")
 if burning_eye then s.bare=true;s.ignited=true;s.nextfire=nil;c.gear.forced_weapon=nil;self:Release();return "attack",target end
 if weak or anim(target,"stagger_pst") then s.eye_bare=true;s.bare=true;s.ignited=true end
 if target:HasTag("fire") then s.bare=true;s.ignited=true end
 if anim(target,"ice_grow_2") and f>=3 then s.eye_bare=nil;s.bare=nil;s.ignited=nil end
 if target.sg and target.sg.mem and target.sg.mem.noeyeice then s.eye_bare=true end
 if not s.eye_bare and anim(target,"ice_grow") and f>=13 then s.bare=nil;s.ignited=nil;s.throws=0 end
 if s.eye_bare and not first and not second then
  c.gear.forced_weapon=nil;self:Release();return "attack",target
 end
 if first and not s.throwing then s.throws=0;s.eye_bare=nil;s.bare=nil;s.ignited=nil end
 if first or second then
  s.throwing=true
  if f>=30 and (s.throwanim~=rawanim(target) or f<(s.lastframe or 0) or not s.locked) then
   local player=c.player:GetPosition();local mark=player;local near
   for _,v in ipairs(self.icemarks or {}) do local d=player:DistSq(v:GetPosition());if not near or d<near then mark=v:GetPosition();near=d end end
   s.locked=Vector3(mark.x,0,mark.z);s.throwanim=rawanim(target);s.escape=nil
  end
  s.lastframe=f
  if second and f>=34 then s.throws=2;s.bare=true end
  if f>=30 then
   if second and s.bare and s.locked and c.player:GetPosition():DistSq(s.locked)>6.0^2 then
    if s.ignited then c.gear.forced_weapon=nil;self:Release();return "attack",target end
    local mode,picked=self:Ignite(target,s);if mode then return mode,picked end
   end
   if not s.escape then
    local q=target:GetPosition();local mark=s.locked;local p=c.player:GetPosition()
    local theta=math.atan2(q.z-mark.z,q.x-mark.x);local best,score
    local body=target:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.2
    for i=0,23 do
     local a=theta+i*math.pi/12;local v=Vector3(mark.x+math.cos(a)*6.8,0,mark.z+math.sin(a)*6.8)
     local dx,dz=v.x-p.x,v.z-p.z;local len=dx*dx+dz*dz
     local t=len>0 and math.max(0,math.min(1,((q.x-p.x)*dx+(q.z-p.z)*dz)/len)) or 0
     local closest=Vector3(p.x+dx*t,0,p.z+dz*t)
     if closest:DistSq(q)>=body*body and Nav.Safe(c,v,target) then
      -- 第一发严格横向，不选择朝Boss走；第二发才选择靠近点燃。
      local toward=(v.x-p.x)*(q.x-p.x)+(v.z-p.z)*(q.z-p.z)
      local value=second and v:DistSq(q) or math.abs(math.cos(a-theta))*30+p:DistSq(v)*.05+(toward>0 and 10000 or 0)
      value=value+Nav.Risk(c,v,target)*100
      if not score or value<score then best,score=v,value end
     end
    end
    s.escape=best or Nav.Select(c,Vector3(mark.x+math.cos(theta+(second and 0 or math.pi/2))*6.8,0,mark.z+math.sin(theta+(second and 0 or math.pi/2))*6.8),target)
   end
   return self:Move(s.escape,second and "晶鹿 · 躲开第二发同时准备点燃" or "晶鹿 · 横移离开冰锥完整范围",target)
  end
  if second then c.bridge:PauseAttack();return "support",target end
  return self:Away(target,9.5,"晶鹿 · 等待冰刺锁点")
 end
 s.throwing=nil;s.locked=nil
 if s.bare then
  if not s.ignited then local mode,picked=self:Ignite(target,s);if mode then return mode,picked end end
  c.gear.forced_weapon=nil;self:Release();return "attack",target
 end
 return self:Away(target,9.5,"晶鹿 · 有冰锥时先骗投掷")
end

function Boss:Toad(target)
 if target.prefab~="toadstool" and target.prefab~="toadstool_dark" then return end
 local c=self.c;local now=GetTime()
 local growing=anim(target,"attack_channeling_pre") or anim(target,"attack_channeling_loop") or anim(target,"hit_channeling")
 if growing then
  self.grew=true;self.treephase=nil
  local robot=self:Item("wagdrone_rolling")
  if robot and not self.dropped and not c.player.components.playercontroller:IsBusy() then
   c.bridge:PauseAttack();c.player.replica.inventory:DropItemFromInvTile(robot);self.dropped=true;return "support",target
  end
  return
 end
 if self.grew then self.grew=nil;self.treephase=true;self.fluted=nil end
 if not self.treephase then return end
 local tree,near;local p=c.player:GetPosition()
 for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,25,{"CHOP_workable"},{"INLIMBO","burnt"})) do
  if e.prefab=="mushroomsprout" or e.prefab=="mushroomsprout_dark" then
   local d=p:DistSq(e:GetPosition());if not near or d<near then tree,near=e,d end
  end
 end
 if not tree then self.treephase=nil;self.dropped=nil;c.gear.forced_weapon=nil;return end
 local flute=self:Item("panflute")
 if flute and not self.fluted then
  c.bridge:PauseAttack()
  if not c.player.components.playercontroller:IsBusy() and A.Self(c.player,flute,ACTIONS.PLAY) then self.fluted=true;self.sleepwait=now+.8 end
  return "support",target
 end
 if now<(self.sleepwait or 0) then return "support",target end
 local axe=self:Item("shadow_battleaxe") or self:Item("multitool_axe_pickaxe") or self:Item("goldenaxe") or self:Item("axe")
 if axe then
  c.bridge:PauseAttack();c.gear.forced_weapon=axe
  if c.mechanisms:Equip(axe) and not c.player.components.playercontroller:IsBusy() and now>=(self.nextchop or 0) then
   A.Scene(c.player,tree,ACTIONS.CHOP);self.nextchop=now+.25
  end
  return "support",target
 end
 self.treephase=nil
end

function Boss:Zones(entities)
 local c=self.c;local p=c.player:GetPosition();local now=GetTime();local zones={};local seen={};self.ghosts={};self.icemarks={};self.bomb_imminent=nil
 local all={};local found={}
 for _,e in ipairs(entities) do all[#all+1]=e;found[e]=true end
 for _,e in ipairs(require("shadowself/bombs").Near(c.player)) do if not found[e] then all[#all+1]=e end end
 entities=all
 local function add(e,r,pos) zones[#zones+1]={pos=pos or e:GetPosition(),radius=r,source=e} end
 for _,e in ipairs(entities) do if live(e) then
  seen[e]=true;local n=e.prefab;local ep=e:GetPosition()
  if n=="bearger_sinkhole" and not anim(e,"disappear") then add(e,(TUNING.MUTATED_BEARGER_SINKHOLERADIUS or 3)+c.player:GetPhysicsRadius(0)+.35);zones[#zones].bearger_pit=true
  elseif n=="sporecloud" and e:HasTag("sporecloud") then add(e,(TUNING.TOADSTOOL_SPORECLOUD_RADIUS or 3.5)+.8)
  elseif n=="mushroombomb" or n=="mushroombomb_dark" then
   local late=false
   if anim(e,"explode_pre") then
    local length=e.AnimState.GetCurrentAnimationLength and e.AnimState:GetCurrentAnimationLength() or 1
    local earliest=length*.5-frame(e)*FRAMES
    local radius=(TUNING.TOADSTOOL_MUSHROOMBOMB_RADIUS or 3.5)+.5
    local exit=math.max(0,radius-math.sqrt(p:DistSq(ep)))/(c.Speed and math.max(1,c:Speed()) or 6)
    late=earliest<=exit+.3+require("shadowself/control/nettiming").Delay(c)
   end
   if late then add(e,(TUNING.TOADSTOOL_MUSHROOMBOMB_RADIUS or 3.5)+.5) end
  elseif n=="sporebomb" then
   self.bombs[e]=self.bombs[e] or e._shadowself_born or now
   local timer=e.components and e.components.timer
   local remaining=timer and timer:GetTimeLeft("explode") or (TUNING.TOADSTOOL_SPOREBOMB_TIMER or 3.5)-(now-self.bombs[e])
   local latency=c.Latency and c:Latency() or .1
   local lead=math.max(24*FRAMES,5/(c.Speed and math.max(1,c:Speed()) or 6)+latency+.15)
   local par=e._shadowself_bomb_owner or e.entity and e.entity:GetParent()
   if remaining<= (par==c.player and math.max(1,5/(c.Speed and math.max(1,c:Speed()) or 6)+latency+.25) or lead+.15) then
    local center=par and par.GetPosition and par:GetPosition() or ep
    if par==c.player or par==c.player.entity then
     center=p;self.bomb_imminent=e
    end
    add(e,5,center)
   end
  elseif n=="bigshadowtentacle" then
   local active=anim(e,"atk_pre") or anim(e,"atk_loop") or anim(e,"atk_idle")
   if active then self.seen[e]=true end
   if self.seen[e] and not anim(e,"atk_pst") and not anim(e,"breach_pst") then add(e,(TUNING.TENTACLE_STOPATTACK_DIST or 4)+1) end
  elseif n=="bishop_charge2_fx" then
   self.bishopshots[e]=self.bishopshots[e] or now
   if now-self.bishopshots[e]<.65 then add(e,2+c.player:GetPhysicsRadius(0)+.3) end
  elseif n=="warg_mutated_ember_fx" then add(e,2)
  elseif n=="deerclops_icelance_ping_fx" then self.icemarks[#self.icemarks+1]=e;add(e,6.1)
  elseif n=="alterguardian_phase2spike" and not anim(e,"spike_pst") then add(e,1.85)
  elseif n=="alterguardian_phase2spiketrail" then
   add(e,1.85)
   local r=e.Transform:GetRotation()*math.pi/180
   for step=2,8,2 do add(e,1.85,Vector3(ep.x+math.cos(r)*step,0,ep.z-math.sin(r)*step)) end
  elseif n=="sharkboi_icespike" then
    local growing=false
    for i=1,4 do if anim(e,"spike"..i.."_pre") and frame(e)<4 then growing=true;break end end
    add(e,growing and 3 or e:GetPhysicsRadius(.8)+self.c.player:GetPhysicsRadius(0)+.2)
   elseif n=="shadowthrall_projectile_fx" and not anim(e,"projectile_impact") then
    self.thrall_projectiles=self.thrall_projectiles or {}
    local old=self.thrall_projectiles[e];local now=GetTime()
    if old and now>old.time and now-old.time<.3 then
     local dt=now-old.time;local vy=(ep.y-old.pos.y)/dt
     if vy<0 then
      local t=(vy+math.sqrt(vy*vy+70*math.max(0,ep.y)))/35
      if t<=.4 then add(e,1+self.c.player:GetPhysicsRadius(0)+.35,Vector3(ep.x+(ep.x-old.pos.x)/dt*t,0,ep.z+(ep.z-old.pos.z)/dt*t)) end
     end
    end
    self.thrall_projectiles[e]={pos=ep,time=now}
  elseif n=="smallguard_alterguardian_projectile" and not anim(e,"mutate") then self.ghosts[#self.ghosts+1]=e;add(e,math.sqrt(TUNING.GESTALT_ATTACK_HIT_RANGE_SQ or 2)+.05)
  end
 end end
 for e in pairs(self.bombs) do if not seen[e] then self.bombs[e]=nil end end
   for e in pairs(self.thrall_projectiles or {}) do if not seen[e] then self.thrall_projectiles[e]=nil end end
 for e in pairs(self.seen) do if not seen[e] then self.seen[e]=nil end end
 for _,zone in ipairs(require("shadowself/control/arena_doc_boss").Zones(c,entities)) do zones[#zones+1]=zone end
 self.zones=zones;return zones
end
-- Finish the selected pair before consulting a later volley.
local function ghost_done(e)
 return not e:IsValid() or anim(e,"mutate") or anim(e,"attack") and frame(e)>25
end
function Boss:MoonPair(target)
 if not target or target.prefab~="alterguardian_phase2" or not self.moon_hold and not self.moon_pair then return end
 local c=self.c;local p=c.player:GetPosition();self.moon_finished=self.moon_finished or setmetatable({},{__mode="k"})
 local pair=self.moon_pair
 if pair and ghost_done(pair.a) and ghost_done(pair.b) then
  self.moon_finished[pair.a]=true;self.moon_finished[pair.b]=true;self.moon_pair=nil;pair=nil
 end
 if not pair then
  local ghosts={}
  for _,e in ipairs(self.ghosts or {}) do if not self.moon_finished[e] and not ghost_done(e) then ghosts[#ghosts+1]=e end end
  local best,score
  for i=1,#ghosts-1 do for j=i+1,#ghosts do
   local ea,eb=ghosts[i],ghosts[j];local a,b=ea:GetPosition(),eb:GetPosition();local width=dist(a,b)
   local ra,rb=ea.Transform:GetRotation(),eb.Transform:GetRotation();local delta=math.abs((ra-rb+180)%360-180)
   if width>=3 and width<=7 and delta<20 and math.abs((ea.spawntime or 0)-(eb.spawntime or 0))<=.25 then
    local value=p:DistSq(a)+p:DistSq(b)
    if not score or value<score then best,score={a=ea,b=eb,apos=a,bpos=b,rotation=ra},value end
   end
  end end
  pair=best;self.moon_pair=pair
 end
 if not pair then return end
 self.moon_hold=true;self.moon_until=GetTime()+.3
 if pair.hold then return p end
 if pair.a:IsValid() then pair.apos=pair.a:GetPosition() end
 if pair.b:IsValid() then pair.bpos=pair.b:GetPosition() end
 local a,b=pair.apos,pair.bpos
 local mid=Vector3((a.x+b.x)/2,0,(a.z+b.z)/2)
 local r=pair.rotation*math.pi/180;local fx,fz=math.cos(r),-math.sin(r)
 if not pair.exit then
  local ep=target:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z;local length=math.max(.01,math.sqrt(dx*dx+dz*dz))
  local sx,sz=-dz/length,dx/length
  local lateral=math.max(-5,math.min(5,(mid.x-p.x)*sx+(mid.z-p.z)*sz))
  pair.entry=Vector3(p.x+sx*lateral,0,p.z+sz*lateral)
  pair.exit=pair.entry
 end
 if p:DistSq(pair.entry)>.4^2 and not pair.cross then
  if Nav.Safe(c,pair.entry,target) then return pair.entry end
  return p
 end
 pair.cross=true
 if p:DistSq(pair.exit)<=.5^2 then pair.hold=true;return p end
 if Nav.Safe(c,pair.exit,target) then return pair.exit end
 return p
end

function Boss:Tentacle(target)
 if target.prefab~="minotaur" or self.routes:Leap(target) then return end
 local c=self.c;local p=c.player:GetPosition();local nearby
 for _,e in ipairs(self.entities or {}) do
  if e.prefab=="bigshadowtentacle" and live(e) and not self.seen[e] and not anim(e,"atk_pst") and not anim(e,"breach_pst") then
   local d=p:DistSq(e:GetPosition())
   if d<9^2 and (not nearby or d<p:DistSq(nearby:GetPosition())) then nearby=e end
  end
 end
 if nearby then
  local q=nearby:GetPosition();local d=math.max(.01,dist(p,q));local edge=(TUNING.TENTACLE_ATTACK_DIST or 4)-.2
  return self:Move(Vector3(q.x+(p.x-q.x)/d*edge,0,q.z+(p.z-q.z)/d*edge),"犀牛 · 引出触手后脱离",target)
 end
end

function Boss:Rabbit(target)
 local king
 for _,e in ipairs(self.c.enemies) do if e.prefab=="rabbitking_aggressive" and live(e) then
  if anim(e,"stuck_loop") or anim(e,"stuck_pst") or anim(e,"dropkick_miss_pst") and frame(e)>=6 then king=e;break end
 end end
 if king then return "attack",self:Select(king) end
 if target.prefab=="rabbitking_aggressive" and (anim(target,"spawn_pre") or anim(target,"spawn_loop") or anim(target,"despawn") and frame(target)>=47) then
  self.c.bridge:PauseAttack();return "support",target
 end
end
function Boss:HoldPosition(target)
 local O=require("shadowself/control/openings")
 return O.DragonDown(target) or O.Bear(self.c,target)
end
function Boss:Bearger(target)
 if target.prefab~="mutatedbearger" then return end
 local open,weapon=require("shadowself/control/openings").Bear(self.c,target)
 if open then
  if weapon then self.c.gear.forced_weapon=weapon;self.bear_weapon=weapon end
  self:Release();return "attack",target
 end
 if self.bear_weapon then
  if self.c.gear.forced_weapon==self.bear_weapon then self.c.gear.forced_weapon=nil end
  self.bear_weapon=nil
 end
 local c=self.c;local p=c.player:GetPosition();local qp=target:GetPosition()
 for _,zone in ipairs(c.hazards or {}) do if zone.bearger_pit and qp:DistSq(zone.pos)<zone.radius^2 then
  local dx,dz=p.x-zone.pos.x,p.z-zone.pos.z;local d=math.sqrt(dx*dx+dz*dz)
  if d<.01 then dx,dz,d=1,0,1 end
  local goal=Vector3(zone.pos.x+dx/d*(zone.radius+7),0,zone.pos.z+dz/d*(zone.radius+7))
  return self:Move(goal,"装甲熊獾 · 避开减速坑，先把Boss引出来",target)
 end end
end
function Boss:Tick(target)
 local c=self.c;local p=c.player:GetPosition()
 if require("shadowself/control/arena_doc_control").Continuous(c,target) then self:Release();return "attack",target end
 if require("shadowself/control/arena_doc_boss").Owns(c) then return "support",target end
 -- 外圈巡游/返回加速地皮不能覆盖已经起手的真实扑击、挥击。
 local windows=require("shadowself/control/arena_attackwindows");local immediate
 for _,e in ipairs(c.enemies or {}) do
  if e:IsValid() and windows.Block(c,e) and p:DistSq(e:GetPosition())<=12^2
   and (not immediate or p:DistSq(e:GetPosition())<p:DistSq(immediate:GetPosition())) then immediate=e end
 end
 if immediate then
  if immediate.prefab=="slurper" then
   -- 远处啜食者起手仍交给侧方威胁扫描，不能因此抢走近处的反击目标。
   immediate=require("shadowself/control/arena_slurper").Nearest(c,c.enemies,nil,target) or immediate
  end
  local pack=c.arena_snailpack
  if pack and pack.active and immediate.prefab=="slurper" and pack.target~=immediate then
   pack.target=immediate;pack.phase=windows.Committed(c,immediate) and "fight" or "bait";pack.bait_seen=nil;pack.standing=nil
  end
  if pack and pack.target==immediate and pack.phase=="bait" then pack.bait_seen=true end
  self:Release();return "attack",self:Select(immediate)
 end
 local center_mode,center_target=require("shadowself/control/arena_center").Tick(self,target)
 if center_mode then return center_mode,center_target end
 if c.plan and c.plan.arena and c.plan.arena_wave and (c.plan.arena_wave()==5 or c.plan.arena_wave()==6) then
  self.snailpack=self.snailpack or require("shadowself/control/arena_snailpack")(self)
  local mode,picked=self.snailpack:Tick()
  if mode then return mode,picked end
 end
 local bat_mode,bat_target=require("shadowself/control/arena_bats").Tick(self,target)
 if bat_mode then return bat_mode,bat_target end
 if c.encounters and c.encounters.Patrol then
  local mode,picked=c.encounters:Patrol(target)
  if mode then return mode,picked end
 elseif c.encounters and c.encounters.Salamanders then
  local mode,picked=c.encounters:Salamanders()
  if mode then return mode,picked end
 end
 local shark_mode,shark_target=require("shadowself/control/sharkroute").Prepare(self,target)
 if shark_mode then return shark_mode,shark_target end
 local ant_mode,ant_target=self.routes:AntRecover(target)
 if ant_mode then return ant_mode,ant_target end
 local knight_mode,knight_target=self:Knight(target)
 if knight_mode then return knight_mode,knight_target end
 if self.bear_weapon and target.prefab~="mutatedbearger" then
  if c.gear.forced_weapon==self.bear_weapon then c.gear.forced_weapon=nil end;self.bear_weapon=nil
 end
 if require("shadowself/control/openings").DragonDown(target) then self:Release();return "attack",target end
 local bear_mode,bear_target=self:Bearger(target);if bear_mode then return bear_mode,bear_target end
 local guardian_mode,guardian_target=require("shadowself/control/guardian").Tick(self,target)
 if guardian_mode then return guardian_mode,guardian_target end
 if self.c.brightshade_target or target:HasTag("lunarthrall_plant") or target:HasTag("lunarthrall_plant_end") or Plant.Middle(target) then
  local mode,picked=self:Brightshade(target);if mode then return mode,picked end
 end
 if self.routes:Leap(target) then self:Release();return "attack",target end
 local clockwork_rook=require("shadowself/control/targetpolicy").ClockworkRook(c.bridge)
 if clockwork_rook then
  local mode,picked=self:Rook(clockwork_rook)
  if mode then return mode,picked end
 end
 if #c.enemies>=2 and Nav.Clearance(c,p)<5 then
  local best,score
  for i=0,15 do
   local a=i*math.pi/8;local q=Vector3(p.x+math.cos(a)*4,0,p.z+math.sin(a)*4)
   if Nav.Safe(c,q) then
    local value=Nav.Clearance(c,q)*20-Nav.Risk(c,q)*30
    if not score or value>score then best,score=q,value end
   end
  end
  if best then return self:Move(best,"群战 · 先脱离岸边和墙角",target) end
 end
 local mode,picked=self:Rabbit(target)
 if not mode then mode,picked=self:Shell(target) end
 if not mode then mode,picked=self:Tentacle(target) end
 if not mode then mode,picked=self:Rook(target) end
 if not mode then mode,picked=self:Brightshade(target) end
 if not mode then mode,picked=self:Crystal(target) end
 if not mode then mode,picked=self:Toad(target) end
 if not mode then self:Release() end
 return mode,picked
end
local profiles={
 vault_pillar_guard={atk_1={29,5.9},atk_2={26,5.9},atk_3_pre_a={1000,6},atk_3_pre_b={1000,6},atk_3={1000,6},spin_pre={1000,6.6},spin_loop={1000,6.6}},
 prime_mate={atk={9,3.5},atk_weapon={9,4}},
 sharkboi={atk1={16,5},atk2={4,5},atk2_delay={1000,5},atk3={12,5},ice_summon={42,6},torpedo_pre={1000,6},torpedo_jump={1000,6},torpedo_loop={1000,6},icedive_standing_jump_pre={1000,5},icedive_jump_pre={1000,5},icedive_jump={1000,5},icedive_dig_pre={1000,5},icedive_dig_pst={4,5}}
}
function Boss:Dodge(target,base)
 if require("shadowself/control/arena_doc_control").Continuous(self.c,target) then return false end
 local owned=require("shadowself/control/arena_doc_boss").Dodge(self.c,target,base)
 if owned~=base then return owned end
 local window=require("shadowself/control/arena_attackwindows").Dodge(self.c,target,base)
 if window~=base then return window end
 local bat=require("shadowself/control/arena_bats").Dodge(self.c,target,base)
 if bat~=base then return bat end
 local snail=require("shadowself/control/arena_snails").Dodge(self.c,target,base)
 if snail~=base then return snail end
 if require("shadowself/control/arena_rabbit").Ignore(self.c,target) then return false end
 local lunar=require("shadowself/control/arena_lunar12").Dodge(self.c,target,base)
 if lunar~=base then return lunar end
 local moose=require("shadowself/control/arena_moose").Dodge(self.c,target,base)
 if moose~=base or target and target.prefab=="moose" and self.c.plan and self.c.plan.arena
  and self.c.plan.arena_wave and self.c.plan.arena_wave()==4 then return moose end
 local knight=self:KnightState(target)
 if knight then
  return {atkanim="atk",point="player",dist=4,update=true,exclusive=true,noattack=true,
   fn=function() local s=self:KnightState(target);return s and s.point or self.c.player:GetPosition() end,
   breakdodgefn=function() return not self:KnightState(target) end}
 end
 if self:HoldPosition(target) then return false end
 if target.prefab=="minotaur" then
  local data=require("shadowself/control/guardian").Dodge(self.c,target,base);if data~=base then return data end
 end
 if target.prefab=="sharkboi" then return require("shadowself/control/sharkroute").Dodge(self.c,target,base) end
 local custom=self.routes:Dodge(target,base)
 if custom~=base or target.prefab=="antlion" or target.prefab=="vault_pillar_guard" and (anim(target,"atk_1") or anim(target,"atk_2")) then return custom end
 local list=profiles[target.prefab];if not list then return base end
 for name,v in pairs(list) do if anim(target,name) and frame(target)<v[1] then
  self.dodges=self.dodges or {};local key=tostring(target.GUID)..name
  if not self.dodges[key] then
   local radius=v[2]+self.c.player:GetPhysicsRadius(0)
   local data={atkanim=name,point="target",dist=radius,update=true,angle=0}
   if target.prefab=="sharkboi" or target.prefab=="vault_pillar_guard" and name:find("atk_3",1,true) then
    data.fn=function()
     local p=self.c.player:GetPosition();local q=target:GetPosition();local r=math.max(radius,dist(p,q))
     local theta=math.atan2(p.z-q.z,p.x-q.x)
     local rot=target.Transform:GetRotation()*math.pi/180
     local back=math.pi-rot;local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
     -- Large enough arc step to start moving now; never chord through the boss.
     theta=theta+math.max(-.8,math.min(.8,delta))
     return Nav.Select(self.c,Vector3(q.x+math.cos(theta)*r,0,q.z+math.sin(theta)*r),target)
    end
   end
   self.dodges[key]=data
  end
  return self.dodges[key]
 end end
 return base
end
return Boss
