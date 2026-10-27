-- 仅第十一关：一格料理内交换补给，使用原有DROP/PICKUP/EAT和回血确认。
local A=require("shadowself/control/actions")
local Food=require("shadowself/control/arena_food")
local Inv=require("shadowself/control/arena_inventory")
local Policy=require("shadowself/control/arena_policy")
local M=Class(function(self,owner) self.owner=owner;self.arena=owner.arena;self.player=owner.player;self.dropped={} end)
function M:Owned(item)
 for _,e in ipairs(A.Items(self.player)) do if e==item then return true end end
 return false
end
function M:Value(item,mode)
 if mode~="buff" and require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then return end
 if item and not require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) then return end
 if not item or not item:IsValid() or item:HasTag("spoiledfood") or not Policy.PickupAllowed(item,11,self.player) then return end
 if mode=="buff" and item.prefab~="voltgoatjelly_spice_chili" then return end
 if mode~="buff" and Food.BuffOnly(item) then return end
 -- 茶独占原有格子，紧急料理选择不让低SAN喝茶覆盖回血/饥饿处理。
 if item.prefab=="sweettea" then return end
 local health=Food.Health(item,self.player);if health<=0 then return end
 if mode=="health" then return health end
 if mode=="buff" then return 100 end
 local hunger=Food.Hunger(item,self.player);if hunger>0 then return hunger end
end
function M:Safe(item)
 local h=self.arena.healing;local c=self.owner.context;local q=item:GetPosition()
 return h:Safe(c,q,Food.Duration(item)+.3) and h:Path(c,q)
end
function M:Available(mode)
 local now=GetTime();local h=self.arena.healing
 for _,item in ipairs(A.Items(self.player)) do
  if self:Value(item,mode) and not (h.failed and now<(h.failed[item.GUID] or 0)) then return true end
 end
 for _,item in ipairs(self.arena.items or {}) do
  local ignored=self.arena.ignored[item.GUID]
  if self:Value(item,mode) and (self.dropped[item.GUID] or not ignored or ignored<=now)
   and not (h.failed and now<(h.failed[item.GUID] or 0)) and self:Safe(item) then return true end
 end
 return false
end
function M:Progress()
 self.since=GetTime();self.warned=nil
end
function M:Wait(reason)
 local now=GetTime();self.since=self.since or now
 self.owner.food_status=reason
 if now-self.since>=45 then
  self.owner.failed="第十一关补给45秒无进展："..reason.."。已停止接管，人物仍在副本，请人工补给或退出。"
  return true
 end
 if self.reason~=reason or now>=(self.next_log or 0) then
  self.reason=reason;self.next_log=now+15
  print("[ShadowSelf][stage11_food] wait="..reason.." seconds="..math.floor(now-self.since))
 end
 self.owner:Patrol("第十一关 · "..reason.."；保持回避，45秒无进展将停止并提示人工处理")
 return true
end
function M:CancelPickup()
 if self.arena.pending_item and self.arena.pending_item==self.target then
  A.Stop(self.player);self.arena.pending_item=nil;self.arena.pick_deadline=nil
  require("shadowself/control/arena_pickup_travel").Release(self.arena)
 end
 self.target=nil
end
function M:Tick(mode)
 if mode~="buff" and require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then self:CancelPickup();self.owner.feeding=nil;return false end
 local s=self.owner;local arena=self.arena;local h=arena.healing;local c=s.context;local now=GetTime()
 s.feeding=true;arena:StopCombat();s.target=nil;arena.bridge.priority_target=nil;arena.encounters.worm_target=nil
 self.since=self.since or now
 if now-self.since>=45 and not h.pending then return self:Wait("没有可安全取得的有效补给") end
 if h.pending then
  local old=h.pending;local active=h:Tick(c)
  if h.pending~=old and not (h.failed and now<(h.failed[old.guid] or 0)) then self:Progress() end
  if h.pending or active then
   if old.interrupted then return self:Wait("进食/拾取受威胁，继续核对迟到确认") end
   arena:Say("第十一关 · 等待真实料理消耗或状态恢复确认");return true
  end
 end
 if mode=="buff" and s.buffs:Ready() then return false end
 if mode=="health" then local hp,max=h:Health();if hp and max and hp/max>=.75 then return true end end
 if mode=="hunger" and (s:HungerRatio() or 0)>=.65 then return true end
 if self.mode~=mode then self:CancelPickup();self.mode=mode end
 if self.target and self:Owned(self.target) then
  if arena.pending_item==self.target then
   arena.pending_item=nil;arena.pick_deadline=nil;require("shadowself/control/arena_pickup_travel").Release(arena)
  end
  self:Progress();self.target=nil
 end
 local carried,best;local ground,score
 local function candidates(kind)
  carried,best,ground,score=nil,nil,nil,nil
  for _,item in ipairs(A.Items(self.player)) do
   local value=self:Value(item,kind)
   if value and (not best or value>best) then carried,best=item,value end
  end
  for _,item in ipairs(arena.items or {}) do if not self:Owned(item) then
   local value=self:Value(item,kind)
   local ignored=arena.ignored[item.GUID]
   if self.dropped[item.GUID] then ignored=nil end
   if value and (not ignored or ignored<=now) and not (h.failed and now<(h.failed[item.GUID] or 0)) and self:Safe(item) then
    local distance=math.sqrt(self.player:GetPosition():DistSq(item:GetPosition()))
    value=value-distance*.15
    if not score or value>score then ground,score=item,value end
   end
  end end
 end
 local selected_mode=mode;candidates(mode)
 if mode=="buff" and not carried and not ground then selected_mode="reserve";candidates(selected_mode) end
 if self.target and (not self.target:IsValid() or not self:Safe(self.target)) then self:CancelPickup() end
 if self.target then ground=self.target;score=math.huge;selected_mode=self.target_mode end
 -- 明显更有效的地面料理优先，不能用3HP辣冻模拟20/60HP主治疗。
 if ground and (not carried or score>best+1) then
  self.target=ground;self.target_mode=selected_mode
  local pc=self.player.components.playercontroller
  local combined={};for _,item in ipairs(A.Items(self.player)) do combined[#combined+1]=item end;combined[#combined+1]=ground
  local extra=Inv.ExcessMeal(combined,self.player,11,false)
  for _,item in ipairs(A.Items(self.player)) do if item==extra and item.prefab~=ground.prefab then
   if not h:Safe(c,self.player:GetPosition(),.3) then return self:Wait("腾料理格前先拉开安全距离") end
   if not pc:IsBusy() and now>=(self.next_drop or 0) then
    self.player.replica.inventory:DropItemFromInvTile(item,false)
    self.dropped[item.GUID]=item;arena.ignored[item.GUID]=nil;self.next_drop=now+.5
   end
   arena:Say("第十一关 · 料理格替换，等待旧料理真实移出；保留舒缓茶");return true
  end end
  if self.dropped[ground.GUID] then arena.ignored[ground.GUID]=nil end
  local instance,generation=arena.instance,arena.generation
  local guard=function()
   return arena.running and arena.wave==11 and arena.stage11==s and arena.instance==instance and arena.generation==generation
    and self:Value(ground,selected_mode)~=nil and self:Safe(ground)
  end
  if arena:Loot({ground},false,guard) then arena:Say("第十一关 · 安全拾取"..ground.prefab.."，等待库存确认");return true end
  return self:Wait("目标料理暂不可拾取，寻找可用替代")
 end
 if not carried then return self:Wait(mode=="buff" and "缺少有效辣冻" or "没有可安全取得的有效料理") end
 if selected_mode=="reserve" then arena:Say("第十一关 · 已保留备用料理，等待有效辣冻");return self:Wait("缺少有效辣冻，备用料理已保留") end
 if not h:Safe(c,self.player:GetPosition(),Food.Duration(carried)+.3) then
  s.food_window=Food.Duration(carried)+.3;return self:Wait("料理已备好，先拉开安全进食窗口")
 end
 s.food_window=nil
 -- 这个选择只随第十一关上下文传入，不改变其他关的回血/喝茶顺序。
 c.stage11_food_item=carried
 c.stage11_food_mode=selected_mode
 local active=h:Tick(c)
 c.stage11_food_item=nil;c.stage11_food_mode=nil
 if active or h.pending then arena:Say("第十一关 · 安全食用"..carried.prefab.."，核对实际恢复");return true end
 return self:Wait("料理操作未确认，继续安全处理")
end
return M
