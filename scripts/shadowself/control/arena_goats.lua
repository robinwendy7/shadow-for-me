-- 第六关电羊：外圈15秒、六次确认旋风后释放装备控制，转正常近战。
local A=require("shadowself/control/actions")
local Tools=require("shadowself/control/arena_tools")
local Cycle=require("shadowself/control/arena_windcycle")
local S=Class(function(self,encounters,label) self.owner=encounters;self.c=encounters.c;self.label=label or "电羊" end)
function S:Perimeter(goats)
 local c=self.c;local plan=c.plan
 if not plan or not plan.arena or not plan.arena_wave then return end
 local wave=plan.arena_wave()
 if not (wave==6 and self.label=="电羊" or wave==5 and self.label=="沼泽组合") then return end
 if self.melee then return end
 self.limit=self.limit or (wave==6 and self.label=="电羊" and Cycle.goat_first_casts or Cycle.first_casts)
 if self.perimeter_done and (self.completed or 0)>=self.limit then
  if wave==6 and self.label=="电羊" then
   self:Stop();Cycle.Release(c);self.melee=true;c.arena_goat_melee=true;return
  end
  self:Stop();self.completed=0;self.limit=Cycle.repeat_casts
  self.perimeter_done=nil;self.edge_index=nil;self.edge_since=nil
 end
 if self.perimeter_done then Cycle.Release(c);return end
 local seconds=self.limit==Cycle.repeat_casts and Cycle.repeat_seconds or self.first_seconds or Cycle.first_seconds
 local now=GetTime();local pos=c.player:GetPosition();local front,near
 for _,e in ipairs(goats) do local d=pos:DistSq(e:GetPosition())
  if not near or d<near then front,near=e,d end
 end
 c.bridge:PauseAttack();self.owner:Target(front)
 local q,done=require("shadowself/control/arena_perimeter")(c,self,seconds)
 if not q then Cycle.Hold(c);return self.owner:Away(front,5,self.label.." · 寻找场地外沿"),front end
 if done then
  Cycle.Release(c);self.perimeter_done=true;self.since=now-(self.gather_time or 2.4)-.01;return
 end
 Cycle.Hold(c)
 self:Trace("perimeter"..seconds,front)
 return self.owner:Move(q,self.label.." · 场地外沿巡游"..seconds.."秒后旋风"..self.limit.."次",front),front
end
function S:Trace(phase,target,staff)
 local now=GetTime()
 if now<(self.next_log or 0) then return end
 if phase==self.phase and now<(self.log_heartbeat or 0) then return end
 self.phase=phase;self.next_log=now+1;self.log_heartbeat=now+10
 local hand=self.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
 local d=target and math.sqrt(self.c.player:GetPosition():DistSq(target:GetPosition())) or -1
 print(string.format("[ShadowSelf][wind] phase=%s target=%s distance=%.2f owned=%s hand=%s",phase,target and target.prefab or "none",d,tostring(staff~=nil),hand and hand.prefab or "none"))
end
function S:Stop()
 local c=self.c
 if c.arena_wind and c.arena_wind~=self then return end
 c.arena_wind=nil
 if c.gear and c.gear.forced_weapon==c.arena_wind_staff then c.gear.forced_weapon=c.arena_wind_saved end
 c.arena_wind_saved=nil;c.arena_wind_staff=nil;c.arena_wind_locked=nil
 self.cast_until=nil;self.pending_cast=nil;self.standing=nil;self.since=nil;self.owner:Release()
end
function S:Performed(act)
 if act.invobject and act.invobject~=self.staff then return end
 if self.pending_cast and not self.pending_cast.confirmed then
  self.pending_cast.confirmed=true;self.completed=(self.completed or 0)+1
 end
 self:Trace("performaction",act.target,self.staff)
end
function S:ConfirmCast()
 local pending=self.pending_cast
 if not pending then return end
 local value=require("shadowself/control/arena_inventory").Condition(pending.staff)
 if not pending.confirmed and value<pending.condition then self:Performed({invobject=pending.staff,target=pending.target}) end
 if pending.confirmed and GetTime()>=(self.cast_until or 0) or GetTime()-pending.time>2 then self.pending_cast=nil end
end
function S:Tick(goats)
 self:ConfirmCast()
 if #goats==0 then self.c.arena_goat_melee=nil;Cycle.Release(self.c);self:Stop();self.edge_index=nil;self.edge_since=nil;self.perimeter_done=nil;return end
 local perimeter,picked=self:Perimeter(goats)
 if perimeter then return perimeter,picked end
 if self.melee then return end
 local c=self.c;local staff
 for _,item in ipairs(A.Items(c.player)) do
  if item.prefab=="staff_tornado" and Tools.Usable(item) then staff=item;break end
 end
 if not staff then
  self:Trace("missing_staff",goats[1])
  self:Stop();self.staff=nil
  -- 装备随关卡落地时，不能因为已经交战就永远跳过关键风向标。
  if Tools.Recover(c,"staff_tornado") then return "support",goats[1] end
  return
 end
 local now=GetTime();local pos=c.player:GetPosition();local front,distance;local x,z=0,0
 -- 持续施法通常一直返回support；仍须在两次施法之间推进既有回血状态机。
 -- 正在执行的施法先完成，新的敌人威胁由回血自身的安全检查抢占。
 if c.healing and (c.healing.pending or c.healing.seeking or c.healing:Choose(c))
  and not (self.cast_until and now<self.cast_until) and c.healing:Tick(c) then
  -- 只在回血真正接管后让出风向标；未找到安全窗口不能重置聚怪计时。
  -- 新的进食/寻路已下发，不能再EndDodge换武器覆盖它。
  self.owner.moving=nil;self:Stop()
  return "support",goats[1]
 end
 self.staff=staff;c.arena_wind=self
 if c.gear then
  if not c.arena_wind_locked then c.arena_wind_saved=c.gear.forced_weapon;c.arena_wind_locked=true end
  c.arena_wind_staff=staff;c.gear.forced_weapon=staff
 end
 for _,e in ipairs(goats) do
  local q=e:GetPosition();local d=pos:DistSq(q)
  x=x+q.x;z=z+q.z
  if not distance or d<distance then front,distance=e,d end
 end
 self.since=self.since or now
 c.bridge:PauseAttack();self.owner:Target(front)
 -- 拿稳风向标再施法；不再调用会静默拒绝的背包施法入口。
 if c.player.components.playercontroller:IsBusy() then return "support",front end
 local radius=front.GetPhysicsRadius and front:GetPhysicsRadius(0) or .5
 local attack=front.replica and front.replica.combat
 -- mushgnome 的 SetRange(15) 只负责提前触发吐孢子，并非本体近战伤害圈。
 -- 真正的爆炸由 mechanisms 按每颗孢子的动画单独避让。
 local range=front.prefab=="mushgnome" and 0 or (attack and attack.GetAttackRangeWithWeapon and attack:GetAttackRangeWithWeapon() or 3)
 local safe=math.max(self.minimum_distance or 3.8,range+radius+.65) -- 多留出群体碰撞挤推的距离，不贴近攻击前缘。
 if self.cast_until and now<self.cast_until then return "support",front end
 if distance<safe^2 then
  self.standing=nil;self:Trace("retreat",front,staff)
  return self.owner:Away(front,5,self.label.." · 拉开挤推距离再放飓风"),front
 end
 if #goats>1 and now-self.since<(self.gather_time or 2.4) then
  self.standing=nil;self:Trace("gather",front,staff)
  local center=Vector3(x/#goats,0,z/#goats)
  local angle=math.atan2(pos.z-center.z,pos.x-center.x)+.45
  return self.owner:Move(Vector3(center.x+math.cos(angle)*10,0,center.z+math.sin(angle)*10),self.label.." · 聚拢后飓风清场",front),front
 end
 if distance>16^2 then
  self.standing=nil;self:Trace("approach",front,staff)
  local q=front:GetPosition();local d=math.sqrt(distance)
  return self.owner:Move(Vector3(q.x+(pos.x-q.x)/d*12,0,q.z+(pos.z-q.z)/d*12),self.label.." · 靠近飓风施法距离",front),front
 end
 -- EndDodge会触发恢复武器；这里保持施法独占，不能恢复成火腿棒/手杖。
 self.owner.moving=nil
 if c.travel then c.travel.dodging=nil;c.travel.restore_dodge=nil;c.travel.finish_deferred=nil;c.travel.chasing=nil;c.travel.role="attack" end
 if not self.standing then A.Stop(c.player);self.standing=true end
 local hand=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
 if hand~=staff then
  self:Trace("equip_wait",front,staff)
  if c.mechanisms then c.mechanisms:Equip(staff) else A.Self(c.player,staff,ACTIONS.EQUIP) end
  return "support",front
 end
 if c.player.components.playercontroller:IsBusy() then return "support",front end
 if self.limit and ((self.completed or 0)>=self.limit or self.pending_cast) then return "support",front end
 local pending=self.limit and {staff=staff,target=front,time=now,condition=require("shadowself/control/arena_inventory").Condition(staff)} or nil
 if now>=(self.next_cast or 0) then self.pending_cast=pending end
 if now>=(self.next_cast or 0) and A.CastStaff(c.player,staff,front,function() return c.arena_wind==self and (not self.cast_guard or self.cast_guard()) end) then
  self.next_cast=now+.9;self.cast_until=now+.65
  self:Trace("cast_requested",front,staff)
 elseif now>=(self.next_cast or 0) then
  self.pending_cast=nil
  self.next_cast=now+.3;self:Trace("cast_rejected",front,staff)
 end
 return "support",front
end
return S
