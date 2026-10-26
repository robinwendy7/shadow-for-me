-- 帝王蟹：只打本体；冰陆阶段先等飞蟹落地/催眠确认，再攻击冰墙。
local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local Nav=require("shadowself/control/navigation")
local K=Class(function(self,c) self.c=c end)
local function live(e)
 if not e or not e:IsValid() or e:HasTag("dead") or e:HasTag("isdead") or e:HasTag("INLIMBO") or e:HasTag("FX") then return false end
 local h=e.replica and e.replica.health
 return not (h and h.IsDead and h:IsDead())
end
local function flying(e)
 return e:HasTag("flying") or e.AnimState and (e.AnimState:IsCurrentAnimation("boat_jump_loop") or e.AnimState:IsCurrentAnimation("boat_jump_pst"))
end
function K:Active()
 return live(self.king) and self.c.player:GetPosition():DistSq(self.king:GetPosition())<=60^2
end
function K:Allowed(e)
 return e==self.king or self.stage=="break" and e==self.wall
end
function K:Unlock()
 local gear=self.c.gear
 if gear.action_hold and gear.action_hold.owner==self then gear.action_hold=nil end
end
function K:Interrupt()
 if not self.pending then return end
 self.pending=nil;self:Unlock();self.next_play=GetTime()+.5
end
function K:Select(e)
 local c=self.c;c.blocked=false;c.target=e;c.h.ent=e;c.bridge.priority_target=e
 c.bridge.wrappers.PreTheLoop.old(c.h)
 return e
end
function K:Move(goal,label,now)
 local c=self.c;local pos=c.player:GetPosition()
 if not self.route or now>=(self.next_route or 0) or pos:DistSq(self.route)<.5^2 then
  self.route=Nav.Select(c,goal,self.king);self.next_route=now+.2
 end
 c.travel:BeginDodge(c.snapshot);c:Move(self.route,label)
 return "support",self.king
end
function K:Tick(target)
 local c=self.c;local p=c.player;local now=GetTime()
 if target.prefab=="crabking" and live(target) then self.king=target end
 if not self:Active() then self:Unlock();self.king=nil;self.stage=nil;return end
 local king=self.king;local kp=king:GetPosition();local pc=p.components.playercontroller
 if not king:HasTag("icewall") then
  self:Unlock();self.ice_since=nil;self.stage="king";self.wall=nil;self.pending=nil;self.roster=nil
  return "attack",self:Select(king)
 end
 if self.stage=="king" and not king:HasTag("notarget") then
  return "attack",self:Select(king) -- 同一破冰输出窗内不因小蟹醒来退回吹箫/拆墙。
 end
 self.ice_since=self.ice_since or now
 local mobs,walls={},{};local airborne=false;local asleep=true
 if now>=(self.next_scan or 0) then self.entities=TheSim:FindEntities(kp.x,0,kp.z,40);self.next_scan=now+.1 end
 for _,e in ipairs(self.entities or {}) do if live(e) then
  if e.prefab=="crabking_mob" or e.prefab=="crabking_mob_knight" then
   mobs[#mobs+1]=e;airborne=flying(e) or airborne;asleep=Status.Sleeping(e) and asleep
  elseif e.prefab=="crabking_icewall" then walls[#walls+1]=e end
 end end
 local roster={};local changed=false
 for _,e in ipairs(mobs) do roster[e]=true;if not self.roster or not self.roster[e] then changed=true end end
 for e in pairs(self.roster or {}) do if not roster[e] then changed=true end end
 self.roster=roster
 if changed then self.stable_at=now+.25;self.route=nil end
 local flute
 local tools=require("shadowself/control/arena_tools")
 for _,item in ipairs(A.Items(p)) do if item.prefab=="panflute" and tools.Usable(item) then flute=item;break end end
 if #mobs>0 and not asleep and not flute and tools.Recover(c,"panflute") then
  self.stage="resupply";return "support",king
 end
 -- MAXRANGE=4，原版0.8秒后发射小蟹，落地前带nosleep，不能提前浪费吹奏。
 if now-self.ice_since<1 or airborne or now<(self.stable_at or 0) then
  self:Unlock();self.stage="landing";self:Select(king);c.status="帝王蟹 · 等飞蟹落地后催眠"
  return "support",king
 end
 if self.pending then
  local hit=p.AnimState and p.AnimState:IsCurrentAnimation("hit")
  if asleep and not pc:IsBusy() then self.pending=nil;self:Unlock()
  elseif hit or now>=self.pending then self.pending=nil;self:Unlock();self.next_play=now+.5
  else self.stage="sleep";c.status="帝王蟹 · 等待小蟹实际入睡";return "support",king end
 end
 if #mobs>0 and not asleep and flute then
  self.stage="sleep";self:Select(king)
  local range=flute.components and flute.components.instrument and flute.components.instrument.range or TUNING.PANFLUTE_SLEEPRANGE or 15
  local covered=true
  for _,e in ipairs(mobs) do if p:GetPosition():DistSq(e:GetPosition())>range^2 then covered=false end end
  if not covered then
   local goal=self.route and now<(self.next_route or 0) and self.route or require("shadowself/control/queenflute").Point(c,king,mobs,range-.6)
   return self:Move(goal,"帝王蟹 · 靠近到排箫覆盖全部小蟹",now)
  end
  local pending=c.gear.pending
  if pending then
   if p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==pending.item then c.gear.pending=nil
   elseif now>=(pending.untiltime or now)+(c.Latency and c:Latency() or .1) then
    c.gear.pending=nil;if c.actions.Stop then c.actions:Stop() end;self.next_play=now+.2
   else c.status="帝王蟹 · 等待已有换装确认再吹箫";return "support",king end
  end
  if not pc:IsBusy() and now>=(self.next_play or 0) then
   c.bridge:PauseAttack();if c.actions.Stop then c.actions:Stop() end
   c.bridge.chasing=nil;c.travel.chasing=nil;c.travel.dodging=nil;c.travel.restore_dodge=nil
   c.gear.action_hold={owner=self,kind="crabking_flute"}
   if A.Self(p,flute,ACTIONS.PLAY) then self.pending=now+3;self.next_play=now+1.5
   else self:Unlock();self.next_play=now+.5 end
  end
  c.status="帝王蟹 · 催眠小蟹后破冰";return "support",king
 end
 self:Unlock()
 -- 原版OnKeyStoneRemoved在首面有效冰墙移除后就清除notarget，icewall标签仍会保留。
 -- 小蟹控制完成后以实际可选中状态切回本体，不必打光剩余冰墙。
 if not king:HasTag("notarget") then
  self.stage="king";self.wall=nil;c.status="帝王蟹 · 本体已可攻击，持续输出"
  return "attack",self:Select(king)
 end
 self.stage="break"
 local wall=self.wall
 if not live(wall) then
  local distance;wall=nil
  for _,e in ipairs(walls) do
   local d=p:GetPosition():DistSq(e:GetPosition())
   if not distance or d<distance then wall,distance=e,d end
  end
 end
 self.wall=wall
 if wall then c.status="帝王蟹 · 小蟹已控制，攻击冰墙破冰";return "attack",self:Select(wall) end
 self:Select(king);c.status="帝王蟹 · 等待冰墙解除后攻击本体";return "support",king
end
return K
