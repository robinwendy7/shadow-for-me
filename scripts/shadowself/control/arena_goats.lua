-- 角斗场电羊：短时聚拢，持续对最前排施放原版飓风；不进入近战换血。
local A=require("shadowself/control/actions")
local S=Class(function(self,encounters,label) self.owner=encounters;self.c=encounters.c;self.label=label or "电羊" end)
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
 self.cast_until=nil;self.standing=nil;self.since=nil;self.owner:Release()
end
function S:Performed(act)
 if act.invobject and act.invobject~=self.staff then return end
 self:Trace("performaction",act.target,self.staff)
end
function S:Tick(goats)
 if #goats==0 then self:Stop();return end
 local c=self.c;local staff
 for _,item in ipairs(A.Items(c.player)) do
  if item.prefab=="staff_tornado" and item:IsValid() and not item:HasTag("broken") then staff=item;break end
 end
 if not staff then
  self:Trace("missing_staff",goats[1])
  self.since=nil
  -- 装备随关卡落地时，不能因为已经交战就永远跳过关键风向标。
  for _,drop in ipairs(c.plan and c.plan.arena_ground and c.plan.arena_ground() or {}) do
   local ii=drop.replica and drop.replica.inventoryitem
   if drop.prefab=="staff_tornado" and drop:IsValid() and ii and not ii:IsHeld() then
    c.bridge:PauseAttack()
    if c.player.components.playercontroller:IsBusy() then return "support",goats[1] end
    if require("shadowself/control/navigation").Safe(c,drop:GetPosition()) then
     if GetTime()>=(self.next_pickup or 0) then
      A.Scene(c.player,drop,ACTIONS.PICKUP);self.next_pickup=GetTime()+1
     end
     return "support",goats[1]
    end
    return self.owner:Away(goats[1],4,self.label.." · 拉开后取天气风向标"),goats[1]
   end
  end
  return
 end
 local now=GetTime();local pos=c.player:GetPosition();local front,distance;local x,z=0,0
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
 local safe=math.max(3.8,(attack and attack.GetAttackRangeWithWeapon and attack:GetAttackRangeWithWeapon() or 3)+radius+.65) -- 多留出群体碰撞挤推的距离，不贴近攻击前缘。
 if self.cast_until and now<self.cast_until then return "support",front end
 if distance<safe^2 then
  self.standing=nil;self:Trace("retreat",front,staff)
  return self.owner:Away(front,5,self.label.." · 拉开挤推距离再放飓风"),front
 end
 if #goats>1 and now-self.since<2.4 then
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
 if now>=(self.next_cast or 0) and A.CastStaff(c.player,staff,front,function() return c.arena_wind==self end) then
  self.next_cast=now+.9;self.cast_until=now+.65
  self:Trace("cast_requested",front,staff)
 elseif now>=(self.next_cast or 0) then
  self.next_cast=now+.3;self:Trace("cast_rejected",front,staff)
 end
 return "support",front
end
return S
