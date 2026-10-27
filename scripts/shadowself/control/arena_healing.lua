-- 只接入角斗场；走位与关键机制先处理，回血不拥有独立战斗线程。
local A=require("shadowself/control/actions")
local Food=require("shadowself/control/arena_food")
local Nav=require("shadowself/control/navigation")
local Incoming=require("shadowself/control/incoming")
local H=Class(function(self,player) self.player=player;self.failed={} end)
function H:Health()
 local h=self.player.replica and self.player.replica.health
 if not h or not h.GetCurrent then return end
 local current=h:GetCurrent()
 local maximum=h.MaxWithPenalty and h:MaxWithPenalty() or h.Max and h:Max()
 if not maximum or maximum<=0 then return end
 return current,maximum,math.max(0,maximum-current)
end
function H:Count(name)
 local n=0
 for _,item in ipairs(A.Items(self.player)) do if item.prefab==name then
  local stack=item.replica and item.replica.stackable;n=n+(stack and stack:StackSize() or 1)
 end end
 return n
end
function H:Tea(c)
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then return end
 if c.plan and c.plan.arena_wave and c.plan.arena_wave()>=9 and GetTime()<(self.player.shadowself_tea_after or 0) then return end
 if not c.plan or not c.plan.arena or not c.plan.arena_wave or c.plan.arena_wave()<9 and not c.waiting_crab then return end
 local sanity=self.player.replica and self.player.replica.sanity
 local current=sanity and sanity.GetCurrent and sanity:GetCurrent()
 if type(current)~="number" or current>=170 then return end
 for _,item in ipairs(A.Items(self.player)) do
  if item.prefab=="sweettea" and item:IsValid() and GetTime()>=(self.failed[item.GUID] or 0) and Food.Health(item,self.player)>0 then return item end
 end
end
function H:SanityFood(c)
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then return end
 if not c.plan or not c.plan.arena or not c.plan.arena_wave or c.plan.arena_wave()<11 then return end
 local sanity=self.player.replica and self.player.replica.sanity
 local current=sanity and sanity.GetCurrent and sanity:GetCurrent()
 if type(current)~="number" or current>=100 then return end
 local best,score
 for _,item in ipairs(A.Items(self.player)) do
  if item:IsValid() and require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) and not Food.BuffOnly(item) and item.prefab~="sweettea"
   and GetTime()>=(self.failed[item.GUID] or 0) then
   local value=Food.Sanity(item,self.player)
   if value>0 and (not score or value>score) then best,score=item,value end
  end
 end
 return best
end
function H:WaitFood(c)
 if not c.waiting_crab then return end
 local hunger=self.player.replica and self.player.replica.hunger
 local current=hunger and hunger.GetCurrent and hunger:GetCurrent()
 local maximum=hunger and hunger.Max and hunger:Max()
 if type(current)~="number" or type(maximum)~="number" or maximum<=0 or current/maximum>=.8 then return end
 local best,score
 for _,item in ipairs(A.Items(self.player)) do
  if item:IsValid() and require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) and not Food.BuffOnly(item) and GetTime()>=(self.failed[item.GUID] or 0) then
   local food=Food.Hunger(item,self.player);local value=math.min(maximum-current,food)-math.max(0,food-(maximum-current))
   if food>0 and (not score or value>score) then best,score=item,value end
  end
 end
 return best,false
end
function H:Choose(c)
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then return end
 local chosen=c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==11 and c.stage11_food_item
 if chosen and chosen:IsValid() and (not Food.BuffOnly(chosen) or c.stage11_food_mode=="buff") then
  for _,item in ipairs(A.Items(self.player)) do if item==chosen and Food.Health(item,self.player)>0 then return item,true,Food.Health(item,self.player) end end
 end
 local hp,max=self:Health()
 local sanity=self:SanityFood(c)
 if sanity and (not hp or not max or hp/max>.4) then return sanity,true,Food.Health(sanity,self.player) end
 local tea=self:Tea(c);if tea then return tea,true,Food.Health(tea,self.player) end
 local hp,max,missing=self:Health();if not hp or hp<=0 then return end
 local critical=hp/max<=.4
 if c.full_recovery and missing<=0 or not c.full_recovery and (missing<8 or hp/max>(c.intermission and .94 or .75)) then return self:WaitFood(c) end
 local best,score,health
 local tea_policy=c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()>=9
 for _,item in ipairs(A.Items(self.player)) do if item:IsValid() and require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) and not Food.BuffOnly(item) and not (tea_policy and item.prefab=="sweettea") and GetTime()>=(self.failed[item.GUID] or 0) then
  local heal=Food.Health(item,self.player)
  if heal>0 and (c.full_recovery or critical or heal<=missing*1.6) then
   local effective=math.min(missing,heal);local waste=math.max(0,heal-missing)
   local value=effective*(critical and 4 or 2)-waste*2-Food.Duration(item)*3+(1-Food.Freshness(item))*2
   if not score or value>score or value==score and item.GUID<best.GUID then best,score,health=item,value,heal end
  end
 end end
 return best,critical,health
end
function H:Safe(c,point,window)
 if c.actions and not c.actions:SafePoint(point) then return false end
 local now=GetTime()
 if now>=(self.next_floor_scan or 0) then
  local p=self.player:GetPosition();self.floor_zones={};self.next_floor_scan=now+.15
  for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,12,nil,{"INLIMBO","DECOR"})) do
   local radius
   if e.prefab=="sporecloud" and e:HasTag("sporecloud") then radius=(TUNING.TOADSTOOL_SPORECLOUD_RADIUS or 3.5)+.8
   elseif e.prefab=="honey_trail" then radius=1.6
   elseif e.prefab=="worm_boss_dirt_ground_fx" then radius=4.5 end
   if not radius then local z=require("shadowself/control/arena_fire").Zone(e,self.player);radius=z and z.radius end
   if radius and e:IsValid() then self.floor_zones[#self.floor_zones+1]={entity=e,pos=e:GetPosition(),radius=radius} end
  end
 end
 for _,zone in ipairs(self.floor_zones or {}) do
  if zone.entity:IsValid() and point:DistSq(zone.pos)<zone.radius^2 then return false end
 end
 for _,zones in ipairs({c.hazards or {},c.mechanisms and c.mechanisms.zones or {}}) do
  for _,zone in ipairs(zones) do if point:DistSq(zone.pos)<((zone.radius or 0)+.5)^2 then return false end end
 end
 for _,e in ipairs(c.enemies or {}) do
  if e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") and not e:HasTag("INLIMBO") then
   local lane=Incoming.Lane(c,e)
   if lane and Incoming.Risk(lane,point)>0 then return false end
   local observed=c.observed and c.observed[e.GUID]
   local dodge=observed and observed.dodge
   if dodge and dodge.safe and not dodge.safe(point) then return false end
   local d=math.sqrt(point:DistSq(e:GetPosition()));local radius=Nav.Radius(e)
   -- 不能把“此刻没前摇”当成接下来一秒安全；计入怪物靠近后起手的余量。
   local approach=(e:HasTag("epic") and 7 or 6)*window
   if d<radius+approach+.6 then return false end
  end
 end
 return true
end
function H:Release(c,eating) self.seeking=nil;require("shadowself/control/arena_pickup_travel").Release(self) end
-- 打断只释放回血自己的操作权；迟到的网络确认仍继续观察，不再站着等。
function H:Interrupt(c)
 self:Release(c);self.draining_until=nil;self.seek_after=GetTime()+.5
 if self.pending then self.pending.interrupted=true end
end
function H:Path(c,point)
 if not Nav.Safe(c,point) then return false end
 local p=self.player:GetPosition();local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(point))/.5))
 for _,e in ipairs(c.enemies or {}) do
  if e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") then
   local ep=e:GetPosition();local radius=Nav.Radius(e)+.6
   local before=math.max(0,radius-math.sqrt(p:DistSq(ep)));local lane=Incoming.Lane(c,e)
   for i=1,steps do
    local q=Vector3(p.x+(point.x-p.x)*i/steps,0,p.z+(point.z-p.z)*i/steps)
    -- 寻找进食位置时，连待机怪也不能穿进其攻击圈；已贴身则只能往外脱离。
    if math.max(0,radius-math.sqrt(q:DistSq(ep)))>before+.02 or lane and Incoming.Risk(lane,q)>0 then return false end
   end
  end
 end
 return true
end
function H:GroundFood(c)
 if c.waiting_crab then return false end -- 船上待战只消耗已携带补给，不追地面食物。
 local hp,max,missing=self:Health()
 if not hp or c.full_recovery and missing<=0 or not c.full_recovery and (hp/max>.65 or missing<8) or not c.plan or not c.plan.arena_ground then return false end
 if self.player.components.playercontroller:IsBusy() or self.player:HasTag("attack")
  or c.h and c.h.shadowself_dodging or c.gear and (c.gear.action_hold or c.gear.pending) then return false end
 local p=self.player:GetPosition();if not self:Safe(c,p,.25) then return false end
 local best,score,duration
 for _,item in ipairs(c.plan.arena_ground()) do
  if item:IsValid() and GetTime()>=(self.failed[item.GUID] or 0) then
   local wave=c.plan.arena_wave and c.plan.arena_wave() or 1
   local allowed=not Food.BuffOnly(item) and require("shadowself/control/arena_policy").PickupAllowed(item,wave,self.player)
    and (wave<7 or require("shadowself/control/arena_inventory").Want(item,A.Items(self.player),self.player,wave))
   local heal=Food.Health(item,self.player);local q=item:GetPosition();local d=math.sqrt(p:DistSq(q))
   local window=d/math.max(3.5,c.Speed and c:Speed() or 6)+Food.Duration(item)+.4
    if allowed and heal>0 and d<=(c.full_recovery and 20 or 3) and self:Safe(c,q,window) and self:Path(c,q) then
    local value=math.min(missing,heal)-d*3
    if not score or value>score then best,score,duration=item,value,window end
   end
  end
 end
 if not best then return false end
 c.bridge:PauseAttack()
 if not require("shadowself/control/arena_pickup_travel").Ready(self,self.player,c.plan.arena_wave and c.plan.arena_wave() or 1,best,c) then return true end
 if A.Scene(self.player,best,ACTIONS.PICKUP) then
  self.pending={kind="pickup",item=best,guid=best.GUID,untiltime=GetTime()+duration,deadline=GetTime()+math.max(3,duration+1)}
  c.status="角斗场 · 安全空档拾取附近回血料理";return true
 end
 self.failed[best.GUID]=GetTime()+3;return false
end
function H:Urgent(c)
 if c.h and c.h.shadowself_dodging then return true end
 local p=self.player:GetPosition()
 for _,e in ipairs(c.enemies or {}) do
  local lane=Incoming.Lane(c,e)
  if lane and Incoming.Risk(lane,p)>0 then return true end
  local o=c.observed and c.observed[e.GUID];local d=o and o.dodge
  if d then
   local name=d.atkanim;if type(name)=="function" then name=name(e) end
   local active=not name or e.AnimState and e.AnimState:IsCurrentAnimation(name)
   if active and (d.safe and not d.safe(p) or p:DistSq(e:GetPosition())<(Nav.Radius(e)+2)^2) then return true end
  end
 end
 return false
end
function H:Seek(c,item,window)
 if c.intermission or not c.Move or not c.travel or GetTime()<(self.seek_after or 0) then return false end
 if c.gear and (c.gear.action_hold or c.gear.pending) then return false end
 if self:Urgent(c) then self:Interrupt(c);return false end
 local now=GetTime();local p=self.player:GetPosition()
 if self.seeking and now-self.seeking.since>3 then
  self:Release(c);self.seek_after=now+1;return false
 end
 local speed=math.max(3.5,c.Speed and c:Speed() or 6)
 local anchor=self.seeking and self.seeking.anchor or p
 local goal=self.seeking and self.seeking.point
 local function reachable(q)
  return q:DistSq(anchor)<=8^2 and self:Safe(c,q,window+math.sqrt(p:DistSq(q))/speed) and self:Path(c,q)
 end
 if not goal or not reachable(goal) then
  if now<(self.next_search or 0) then return false end
  self.next_search=now+.2
  local score;goal=nil
  for _,length in ipairs({3,5,7}) do for i=0,15 do
   local angle=i*math.pi/8;local q=Vector3(p.x+math.cos(angle)*length,0,p.z+math.sin(angle)*length)
   if reachable(q) and Nav.Clearance(c,q)>=5 then
    local s=p:DistSq(q);if not score or s<score then goal,score=q,s end
   end
  end end
 end
 if not goal then self:Release(c);self.seek_after=now+.5;return false end
 self.seeking=self.seeking or {since=now,anchor=Vector3(p.x,0,p.z)};self.seeking.point=goal
 -- 手杖请求归回血当前动作持有，不修改原版travel的dodging/restore_dodge。
 c.bridge:PauseAttack()
 if c.gear and c.gear.Swap then c.gear:Swap("move",c.snapshot) end
 c:Move(goal,"角斗场 · 拉开安全距离后吃回血料理")
 return true
end
function H:Tick(c)
 local now=GetTime();local pc=self.player.components.playercontroller
 if self.player:HasTag("playerghost") or self.player:HasTag("corpse") then self:Release(c);self.pending=nil;return false end
 local hp=self:Health();if not hp or hp<=0 then return false end
 local a=self.player.AnimState
 local hit=a and (a:IsCurrentAnimation("hit") or a:IsCurrentAnimation("hit_spike")
  or a:IsCurrentAnimation("channelcast_hit") or a:IsCurrentAnimation("channelcast_oh_hit"))
 if self.last_health and hp<self.last_health-.1 or hit and not self.hit_active then self:Interrupt(c) end
 self.last_health=hp;self.hit_active=hit or false
 local pending=self.pending
 if pending then
  if pending.kind=="pickup" then
   for _,item in ipairs(A.Items(self.player)) do if item==pending.item then
    require("shadowself/control/arena_pickup_travel").Release(self)
    self.pending=nil;self.next_try=now+.1;return true
   end end
   if not pending.item:IsValid() or now>=pending.deadline then
    self.failed[pending.guid]=now+5;self.pending=nil;return false
   end
   if pending.interrupted then return false end
   if not self:Safe(c,self.player:GetPosition(),math.max(.15,pending.untiltime-now)) then self:Interrupt(c);return false end
   return true
  end
  local a=self.player.AnimState
  if a then
   for _,name in ipairs({"eat_pre","eat","quick_eat_pre","quick_eat","quick_drink_pre","quick_drink","heavy_eat","heavy_quick_eat"}) do
    if a:IsCurrentAnimation(name) then pending.saw_eat=true;break end
   end
  end
  local hunger=self.player.replica and self.player.replica.hunger
  local current_hunger=hunger and hunger.GetCurrent and hunger:GetCurrent()
  local nourished=pending.stage11_food and type(current_hunger)=="number" and type(pending.hunger)=="number" and current_hunger>pending.hunger+.1
  local sr=self.player.replica and self.player.replica.sanity
  local san=sr and sr.GetCurrent and sr:GetCurrent()
  local restored=pending.sanity_food and type(san)=="number" and san>(pending.sanity_before or san)+.1
  local healed=pending.saw_eat and not pending.interrupted and now>=pending.untiltime and (hp>pending.health+.1 or nourished or restored)
  if self:Count(pending.name)<pending.count or healed then
   if pending.name=="sweettea" then self.player.shadowself_tea_after=now+60 end
   require("shadowself/control/supplies").Record(self.player,pending.name,self:Count(pending.name)<pending.count and "inventory_consumed" or "food_recovery_after_eat")
   self.pending=nil;self.next_try=now+.5;self:Release(c)
   return pc:IsBusy()
  elseif now>=pending.deadline then
   self.failed[pending.guid]=now+8;self.pending=nil;self.next_try=now+.5;self:Release(c);return false
  end
  if pending.interrupted then return false end
  if now>=pending.start_deadline and not pending.saw_eat and not pc:IsBusy() then
   self:Interrupt(c);return false
  end
  -- 新的冲撞/技能照常抢占进食，等待晚到的库存确认，不重发同一请求。
  if not self:Safe(c,self.player:GetPosition(),math.max(.15,pending.untiltime-now)) then self:Interrupt(c);return false end
  return true
 end
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then self:Release(c);return false end
 if now<(self.next_try or 0) then return false end
 local item,critical=self:Choose(c)
 if not item then self:Release(c);return self:GroundFood(c) end
 if c.gear and c.gear.action_hold then return false end
 if c.gear and c.gear.pending then
  if self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==c.gear.pending.item then c.gear.pending=nil
  elseif self.seeking and c.gear.pending.role=="move" then
   if self:Urgent(c) or not self:Safe(c,self.player:GetPosition(),.1) or now>=c.gear.pending.untiltime then
    self:Interrupt(c);return false
   end
   -- 等自己的手杖确认，防止普通攻击模块在下一帧反向提交武器换装。
   return true
  else return false end
 end
 if c.h and c.h.shadowself_dodging then return false end
 local delay=c.Latency and c:Latency() or (TheNet and TheNet.GetPing and TheNet:GetPing() or 0)/1000+.1
 local window=Food.Duration(item)+delay*2+.15
 local point=self.player:GetPosition()
 if not self:Safe(c,point,window) then
  if critical and not pc:IsBusy() and not self.player:HasTag("attack") then return self:Seek(c,item,window) end
  return false
 end
 if c.travel and c.travel.dodging and not self.seeking then return false end
 if self.player:HasTag("attack") then
  -- 只禁止下一刀；当前挥刀与命中后的原版退步继续执行。
  self.draining_until=now+.12;return false
 end
 if pc:IsBusy() then return false end
 self:Release(c,true)
 c.bridge:PauseAttack()
 local count=self:Count(item.prefab)
 local sanity_item=item==self:SanityFood(c)
 if c.intermission then A.Stop(self.player) end
 if A.Self(self.player,item,ACTIONS.EAT) then
  self.pending={name=item.prefab,guid=item.GUID,count=count,health=hp,start_deadline=now+math.max(.35,delay*2+.1),untiltime=now+window,deadline=now+math.max(3,window+1.5)}
  if sanity_item then
   local sr=self.player.replica.sanity
   self.pending.sanity_food=true;self.pending.sanity_before=sr:GetCurrent()
  end
  if c.stage11_food_item==item and c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==11 then
   local hunger=self.player.replica and self.player.replica.hunger
   self.pending.stage11_food=true;self.pending.hunger=hunger and hunger.GetCurrent and hunger:GetCurrent()
  end
  self.next_try=now+.3;c.status=item.prefab=="sweettea" and "角斗场 · SAN低于170，饮用舒缓茶" or "角斗场 · 安全空档吃回血料理";return true
 end
 self.failed[item.GUID]=now+3;self.next_try=now+.3;return false
end
function H:BlockAttack(name)
 return GetTime()<(self.draining_until or 0) and (name=="CloseAndAttack" or name=="ShouldAtkWhenDodging" or not self.player:HasTag("attack"))
end
function H:Reset(c) if c then self:Release(c) end;self.pending=nil;self.seeking=nil;self.failed={};self.next_try=nil;self.seek_after=nil;self.next_search=nil;self.draining_until=nil;self.floor_zones=nil;self.next_floor_scan=nil;self.last_health=nil;self.hit_active=nil end
return H
