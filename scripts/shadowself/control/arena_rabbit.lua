-- 仅第五关兔王：多随从时外圈4秒→回身诱出攻击→清两只→留一只专打兔王。
local Cycle=require("shadowself/control/arena_windcycle")
local S=Class(function(self,owner) self.owner=owner;self.c=owner.c;self.phase="opening";self.roster={};self.listeners={} end)
local function dead(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead())
end
local function live(e) return e and e:IsValid() and not dead(e) and not e:HasTag("INLIMBO") end
local function wave(c) return c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==5 end
function S.Required(c)
 if not wave(c) then return false end
 for _,list in ipairs({c.enemies or {},c.plan.arena_remaining and c.plan.arena_remaining() or {}}) do
  for _,e in ipairs(list) do if e.prefab=="rabbitking_aggressive" and live(e) then return true end end
 end
 return false
end
function S.Attackable(e)
 if not live(e) or e:HasTag("notarget") or e:HasTag("NOCLICK") then return false end
 local a=e.AnimState
 return not a or not (a:IsCurrentAnimation("spawn_pre") or a:IsCurrentAnimation("spawn_loop")
  or a:IsCurrentAnimation("despawn") and a:GetCurrentAnimationFrame()>=47)
end
function S.Ignore(c,e)
 c=c and (c.c or c)
 local s=c and c.arena_rabbit
 return s and wave(c) and s.phase=="king" and e and e.prefab=="rabbitkingminion_bunnyman" and S.Attackable(s.king) or false
end
function S.Allowed(c,e)
 local s=c and c.arena_rabbit
 if not s or not wave(c) then return true end
 return s.phase~="kite" and s.phase~="bait" and e==s.target and live(e) and (e~=s.king or S.Attackable(e))
end
function S:Phase(phase)
 if self.phase~=phase then self.phase=phase;print("[ShadowSelf][rabbit] phase="..phase) end
end
function S:Watch(e)
 if self.roster[e]~=nil then return end
 self.roster[e]=dead(e) or false
 if e.ListenForEvent then
  local fn=function() if dead(e) then self.roster[e]=true end end
  self.listeners[e]=fn;e:ListenForEvent("death",fn);e:ListenForEvent("onremove",fn)
 end
end
function S:Stop()
 for e,fn in pairs(self.listeners) do e:RemoveEventCallback("death",fn);e:RemoveEventCallback("onremove",fn) end
 self.listeners={};Cycle.Release(self.c)
 if self.c.arena_rabbit==self then self.c.arena_rabbit=nil end
end
function S:MinionEscape(adds)
 local Nav=require("shadowself/control/navigation")
 local c=self.c;local zones={};local lead=require("shadowself/control/nettiming").Frames(c)+2
 for _,e in ipairs(adds) do
  local a=e.AnimState;local attacking=a and a:IsCurrentAnimation("atk")
  if e==self.bait_target and attacking then self.bait_seen=true end
  -- 第13帧才实际判伤；不能第13帧就回头，也不能只看诱导的那一只。
  if attacking and a:GetCurrentAnimationFrame()<=13+lead then
   zones[#zones+1]={pos=e:GetPosition(),radius=3.5,source=e}
  end
 end
 if #zones==0 then return end
 local q=require("shadowself/control/arena_fire").Escape(c.player,zones)
 if not q then
  local route=setmetatable({enemies={},hazards=zones},{__index=c})
  q=Nav.Escape(route,c.player:GetPosition())
 end
 if q then
  c.bridge:PauseAttack()
  return self.owner:Move(q,"兔王 · 同时避开所有随从实际挥击，再回身攻击",self.king),self.king
 end
end
function S:Tick()
 if not wave(self.c) then self:Stop();return end
 local c=self.c
 for _,list in ipairs({c.plan.arena_entities and c.plan.arena_entities() or {},c.enemies or {}}) do
  for _,e in ipairs(list) do
   if e.prefab=="rabbitking_aggressive" and live(e) then self.king=e end
   if e.prefab=="rabbitkingminion_bunnyman" then self:Watch(e) end
  end
 end
 if not live(self.king) then self:Stop();return end
 c.arena_rabbit=self
 if c.arena_wind then c.arena_wind:Stop() end
 local count,killed=0,0;local adds={}
 for e,confirmed in pairs(self.roster) do
  count=count+1
  if confirmed or dead(e) then self.roster[e]=true;killed=killed+1
  elseif live(e) then adds[#adds+1]=e end
 end
 local p=c.player:GetPosition()
 table.sort(adds,function(a,b) return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition()) end)
 if self.phase~="opening" and killed>=2 then Cycle.Release(c);self:Phase("king") end
 if self.phase=="opening" and count>=3 then self.spare=adds[#adds];self:Phase("kite") end
 -- 新一轮起手才重启四秒诱导；已经躲过的挥击不能在后摇时再重启一次。
 if self.phase=="adds" and self.target then
  local a=self.target.AnimState;local f=a and a:GetCurrentAnimationFrame() or 0
  if not (a and a:IsCurrentAnimation("atk")) or self.recovery_frame and f<self.recovery_frame then self.bait_recovery=nil end
  self.recovery_frame=f
  if a and a:IsCurrentAnimation("atk") and not self.bait_recovery
   and f<=13+require("shadowself/control/nettiming").Frames(c)+2 then
   self.bait_target=self.target;self.target=nil;self.edge_since=nil;self.edge_index=nil;self:Phase("kite")
  end
 end
 -- 多随从阶段兔王的飞踢优先于巡游、诱导与随从输出。
 if #adds>1 and c.bosses and c.bosses.routes then
  local danger=c.bosses.routes:Rabbit(self.king,nil)
  if danger then
   c.bridge:PauseAttack()
   local q=danger.fn and danger.fn()
   if q then return self.owner:Move(q,"兔王 · 优先避开兔王飞踢",self.king),self.king end
   return self.owner:Away(self.king,5,"兔王 · 优先回避兔王"),self.king
  end
 end
 if #adds>1 and (self.phase=="bait" or self.phase=="adds" or self.phase=="kite") then
  local mode,target=self:MinionEscape(adds)
  if mode then return mode,target end
 end
 if self.phase=="kite" then
  self.target=nil;Cycle.Hold(c);c.bridge:PauseAttack()
  local q,done=require("shadowself/control/arena_perimeter")(c,self,4)
  if not done then
   if q then return self.owner:Move(q,"兔王 · 多随从，外圈巡游四秒",self.king),self.king end
   return self.owner:Away(self.king,5,"兔王 · 前往场地外圈"),self.king
  end
  Cycle.Release(c);self:Phase("bait");self.bait_seen=nil
 end
 if self.phase=="bait" then
  if killed>=2 then self:Phase("king")
  else
   local target=self.bait_target
   if not live(target) or target==self.spare then
    target=nil;for _,e in ipairs(adds) do if e~=self.spare then target=e;break end end
    self.bait_target=target;self.bait_seen=nil
   end
   self.target=nil;c.bridge:PauseAttack()
   if not target then return "support",self.king end
   local a=target.AnimState;local attacking=a and a:IsCurrentAnimation("atk")
   if attacking then self.bait_seen=true end
   if self.bait_seen and (not attacking or a:GetCurrentAnimationFrame()>13+require("shadowself/control/nettiming").Frames(c)+2) then
    self.target=target;self.bait_recovery=attacking;self.recovery_frame=attacking and a:GetCurrentAnimationFrame() or nil;self:Phase("adds");self.owner:Release();return "attack",self.owner:Target(target)
   end
   if attacking then return self.owner:Away(target,4,"兔王 · 诱出随从挥击后避开"),target end
   local ep=target:GetPosition();local d=math.sqrt(p:DistSq(ep))
   if d>2 then
    local q=Vector3(ep.x+(p.x-ep.x)/d*1.8,0,ep.z+(p.z-ep.z)/d*1.8)
    return self.owner:Move(require("shadowself/control/navigation").Select(c,q,target),"兔王 · 回身接近，等待随从实际出招",target),target
   end
   return "support",target
  end
 end
 if self.phase=="adds" then
  if killed>=2 then self:Phase("king")
  else
   local a=self.target and self.target.AnimState
   if a and self.recovery_frame and a:GetCurrentAnimationFrame()<self.recovery_frame then self.bait_recovery=nil end
   self.recovery_frame=a and a:GetCurrentAnimationFrame() or nil
   if not (a and a:IsCurrentAnimation("atk")) then self.bait_recovery=nil end
   if self.target and dead(self.target) then
    self.target=nil;self.bait_target=nil;self.edge_since=nil;self.edge_index=nil;self:Phase("kite")
    return self:Tick()
   end
   -- 锁定刚诱出攻击的随从直至死亡，不能因挤动造成距离变化而每帧换人。
   if not live(self.target) or self.target==self.spare then
    self.target=nil
    for _,e in ipairs(adds) do if e~=self.spare then self.target=e;break end end
   end
   if not self.target then c.bridge:PauseAttack();return "support",self.king end
   self.owner:Release();return "attack",self.owner:Target(self.target)
  end
 end
 self.target=self.king;Cycle.Release(c)
 if not S.Attackable(self.king) then
  c.bridge:PauseAttack()
  if adds[1] then return self.owner:Away(adds[1],4,"兔王 · 暂不可攻击，回避随从后继续输出"),self.king end
  return "support",self.king
 end
 self.owner:Release();return "attack",self.owner:Target(self.king)
end
return S
