-- 第六关蝾螈/蠕虫组合：各自源码配置，复用外圈15秒、三次旋风、清杂后近战。
local Cycle=require("shadowself/control/arena_windcycle")
local S=Class(function(self,owner)
 self.owner=owner;self.c=owner.c;self.others={};self.final_targets={};self.phase="kite";self.budget=Cycle.first_casts
 self.c.arena_salamanders=self
end)
local profiles={fruitdragon={label="蝾螈组合"},worm={label="蠕虫组合"}}
for primary,profile in pairs(profiles) do
 profile.primary=primary;profile.others={};profile.finals={[primary]=true};profile.expected=0;profile.final_count=0;profile.spider_count=0
 for _,choice in ipairs(require("shadowself/data/arena_classic").encounters[6].default) do
  local found=false
  for _,m in ipairs(choice.monsters or {}) do if m.prefab==primary then found=true end end
  if found then
   for _,m in ipairs(choice.monsters) do
    if m.prefab==primary or primary=="fruitdragon" and m.prefab:match("^spider") or primary=="worm" and m.prefab=="slurper" then
     profile.finals[m.prefab]=true;profile.final_count=profile.final_count+m.amount
     if m.prefab~=primary then profile.spider_count=profile.spider_count+m.amount end
    else profile.others[m.prefab]=true;profile.expected=profile.expected+m.amount end
   end
   break
  end
 end
end
local function dead(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()) or false
end
local function live(e)
 return e and e:IsValid() and not e:HasTag("INLIMBO") and not dead(e)
end
local function wave(c)
 return c and c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==6
end
local function profile_for(c)
 local lists={c.plan.arena_entities and c.plan.arena_entities() or {},
  c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies or {}}
 local companion
 for _,list in ipairs(lists) do for _,e in ipairs(list) do if live(e) then
  if profiles[e.prefab] then return profiles[e.prefab] end
  -- 两组的杂怪在第六关配置中互不重叠，可在蠕虫尚未出土时识别组合。
  for _,profile in pairs(profiles) do if profile.others[e.prefab] or profile.finals[e.prefab] then companion=profile end end
 end end end
 return companion
end
function S.Required(c)
 if not wave(c) then return false end
 if c.arena_salamanders and not c.arena_salamanders.finished then return true end
 return profile_for(c)~=nil
end
function S.Allowed(c,e)
 if not S.Required(c) then return true end
 local state=c.arena_salamanders
 return state and state.phase=="melee" and e==state.target and live(e) or false
end
function S:StopWind()
 if self.wind then self.next_cast=self.wind.next_cast;self.wind:Stop();self.wind=nil end
end
function S:Scan()
 local c=self.c
 for _,list in ipairs({c.plan.arena_entities and c.plan.arena_entities() or {},
  c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies or {}}) do
  for _,e in ipairs(list) do
   if self.profile.finals[e.prefab] then self.final_targets[e]=self.final_targets[e] or false
   elseif self.profile.others[e.prefab] then self.others[e]=self.others[e] or false end
  end
 end
 local final_targets,remaining={},{};local killed=0;local final_dead=0;local spider_dead=0
 for e,confirmed in pairs(self.others) do
  if confirmed or dead(e) then self.others[e]=true;killed=killed+1
  elseif live(e) then remaining[#remaining+1]=e end
 end
 for e,confirmed in pairs(self.final_targets) do
  if confirmed or dead(e) then
   self.final_targets[e]=true;final_dead=final_dead+1
   if e.prefab~=self.profile.primary then spider_dead=spider_dead+1 end
  elseif live(e) then final_targets[#final_targets+1]=e end
 end
 local p=c.player:GetPosition()
 local function nearest(a,b) return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition()) end
 table.sort(final_targets,nearest);table.sort(remaining,nearest)
 local cleared=killed>=self.profile.expected and #remaining==0
 if self.profile.primary=="worm" and not cleared and #remaining==0 then
  local objectives=c.plan.arena_objectives and c.plan.arena_objectives()
  -- 每只活蠕虫都是blocking目标；服务端剩余数全部被已看到的活蠕虫占满，才可确认杂怪清完。
  -- 不将失踪、套头或潜地直接算死亡，也不要求已被删除的尸体仍能读到死亡标签。
  if objectives and objectives>0 and objectives==#final_targets then
   self.adds_cleared=true;self.clear_source="server_objectives"
  end
 end
 self.spiders_cleared=spider_dead>=self.profile.spider_count
 if self.profile.primary=="fruitdragon" then
  table.sort(final_targets,function(a,b)
   if (a.prefab=="fruitdragon")~=(b.prefab=="fruitdragon") then return a.prefab~="fruitdragon" end
   return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition())
  end)
 end
 return final_targets,remaining,(cleared or self.adds_cleared) and #remaining==0,final_dead>=self.profile.final_count
end
function S:Kite(target,label)
 Cycle.Hold(self.c)
 self.c.bridge:PauseAttack()
 local seconds=self.budget==Cycle.repeat_casts and Cycle.repeat_seconds or Cycle.first_seconds
 local point,done=require("shadowself/control/arena_perimeter")(self.c,self,seconds)
 if point then return self.owner:Move(point,label,target),target,done end
 -- 未识别到真实场地外圈时不让等待时间冒充已巡游15秒。
 return self.owner:Away(target,5,self.profile.label.." · 寻找场地外圈"),target,false
end
function S:Tick()
 if not wave(self.c) or self.finished then self:StopWind();return end
 self.profile=self.profile or profile_for(self.c)
 if not self.profile then return end
 local final_targets,remaining,cleared,finished=self:Scan()
 local label=self.profile.label
 local target=remaining[1] or final_targets[1]
 if self.wind then self.wind:ConfirmCast() end
 if self.wind and (self.wind.completed or 0)>=self.budget then
  self:StopWind();self.first_done=true;self.budget=Cycle.repeat_casts
  self.phase="kite";self.edge_since=nil;self.edge_index=nil
 end
 if cleared then
  if self.phase~="melee" then print("[ShadowSelf][pack] profile="..self.profile.primary.." phase=melee source="..(self.clear_source or "observed_deaths")) end
  self:StopWind();Cycle.Release(self.c);self.phase="melee"
  if self.profile.primary=="worm" then
   self.target=require("shadowself/control/arena_slurper").Nearest(self.c,self.final_targets,nil,self.target)
   if not self.target then
    local unknown=false;for e,confirmed in pairs(self.final_targets) do if e.prefab=="slurper" and not confirmed and not dead(e) then unknown=true end end
    if not unknown then self.target=final_targets[1] end
   end
  elseif not live(self.target) or self.profile.primary=="fruitdragon" and not self.spiders_cleared
   and self.target.prefab=="fruitdragon" then self.target=final_targets[1] end
  if self.target and self.target.prefab=="fruitdragon" and not self.spiders_cleared then self.target=nil end
  if self.target then
   self.owner:Release();return "attack",self.owner:Target(self.target)
  end
  if finished then self.finished=true;self.owner:Release();return end
  self.c.bridge:PauseAttack();return "support" -- 潜地/暂未同步不等于蠕虫已死，继续等待可攻击目标。
 end
 if not target then self.c.bridge:PauseAttack();return "support" end
 if self.phase=="kite" then
  local seconds=self.budget==Cycle.repeat_casts and Cycle.repeat_seconds or Cycle.first_seconds
  local mode,picked,done=self:Kite(target,label.." · 场地外圈巡游"..seconds.."秒后旋风"..self.budget.."次")
  if not done then return mode,picked end
  self.phase="wind"
 end
 if self.first_done and #remaining==0 then
  -- 一次空扫描或尸体离开视野不算确认清杂；等待真实死亡证据，不能误转近战。
  return self:Kite(target,label.." · 等待杂怪死亡确认后转入逐只近战")
 end
 Cycle.Release(self.c)
 self.wind=self.wind or require("shadowself/control/arena_goats")(self.owner,label)
 self.wind.limit=self.budget;self.wind.gather_time=0
 self.wind.next_cast=math.max(self.wind.next_cast or 0,self.next_cast or 0)
 self.wind.cast_guard=function() return wave(self.c) and self.phase=="wind" and not self.finished end
 -- 首轮三次后每次仅一发，轮间外圈巡游7秒；仍只向其他怪物施法。
 local mode,picked=self.wind:Tick(#remaining>0 and remaining or final_targets)
 if mode then return mode,picked end
 return self:Kite(target,label.." · 补捡可用风向标，继续安全游离")
end
return S
