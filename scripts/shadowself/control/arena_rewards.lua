-- ASTRA真实chest_mimic奖励、启迪之冠5个独立lunarseed格。所有转移等待库存ACK。
local A=require("shadowself/control/actions")
local R=require("shadowself/control/arena_late_runtime")
local Inv=require("shadowself/control/arena_inventory")
local Nav=require("shadowself/control/navigation")
local Route=require("shadowself/control/arena_reward_route")
local needed={alterguardianhat=true,lunar_seed=true,staff_lunarplant=true}
local excluded={ruinshat=true,armorruins=true}
-- 客户端内容同步宽限，不改变服务器拟态箱2.5秒变形计时。
local CONTENT_SETTLE=.8
local TRANSFER_ACK=5
local C=Class(function(self,s,worm) self.s=s;self.player=s.player;self.arena=s.arena;self.worm=worm;self.boxes={};self.visited={};self.inspected={};self.progress=GetTime() end)
function C:Document()
 return self.s.route=="shadow" and require("shadowself/control/arena_doc_inventory").Enabled(self.player)
end
function C:Needed(item)
 if self:Document() then return item.prefab=="staff_lunarplant" or item.prefab=="queen_torch" end
 return needed[item.prefab]
end
function C:BoxesDone()
 local count=0;for _ in pairs(self.visited) do count=count+1 end
 return count>=4
end
function C:Stop()
 if self.opened and self.opened:IsValid() then
  local c=self.opened.replica and self.opened.replica.container;if c then c:Close() end
 end
 self.opened=nil;self.pending=nil;self.confirmed_open=nil;self.empty_since=nil;self.quiet_since=nil
 self.reward_route=nil;self.route_revision=(self.route_revision or 0)+1
 self.retreat=nil
end
function C:Fail(reason)
 self.s.failed="第十一关奖励流程："..reason;return false
end
function C:Evade(entities)
 local zones={};local p=self.player:GetPosition()
 for _,e in ipairs(entities or {}) do if R.Live(e) and e.prefab=="chest_mimic_revealed" then
  zones[#zones+1]={pos=e:GetPosition(),radius=Nav.Radius(e)+1,source=e}
 end end
 local q=require("shadowself/control/arena_fire").Escape(self.player,zones)
 if not q then return false end
 if self.opened then
  local container=self.opened:IsValid() and self.opened.replica and self.opened.replica.container
  if container then container:Close() end
  self.opened=nil;self.confirmed_open=nil
 end
 self.arena.encounters:Move(q,"奖励流程 · 先避开已显形拟态箱，继续核对取物")
 return true
end
function C:Room(item)
 local inv=self.player.replica.inventory
 if inv.GetNumSlots and inv.GetItemInSlot then
  for i=1,inv:GetNumSlots() do if not inv:GetItemInSlot(i) then return true end end
 end
 for _,owned in ipairs(A.Items(self.player)) do
  local st=owned.replica and owned.replica.stackable
  if owned.prefab==item.prefab and st and not st:IsFull() then return true end
 end
 -- 先清理本轮已明确禁止的物品；不丢骨甲、茶、燃料和奖励。
 for _,owned in ipairs(A.Items(self.player)) do
  if excluded[owned.prefab] or Inv.Obsolete(owned,A.Items(self.player),self.player,11) and not needed[owned.prefab] then
   if GetTime()>=(self.next_request or 0) then inv:DropItemFromInvTile(owned,false);self.next_request=GetTime()+.6 end
   return false
  end
 end
 local old=Inv.Discard(A.Items(self.player),self.player,11,item)
 if old and not needed[old.prefab] then
  if GetTime()>=(self.next_request or 0) then inv:DropItemFromInvTile(old,false);self.next_request=GetTime()+.6 end
  return false
 end
 return self:Fail("背包已满且没有可清理物品；请腾出奖励格，未将请求视为取物成功")
end
function C:Tick(entities)
 self.arena:StopCombat();self.s.target=nil;self.arena.bridge.priority_target=nil
 if self.s.failed then return false end
 local now=GetTime();local inv=self.player.replica.inventory
 if not self:BoxesDone() and now-self.progress>45 and not (self.reward_route and self.reward_route.patrol) then
  self.arena:Say("奖励流程 · 取物尚未确认，保持避险；需要人工核对缺失物品")
  if self:Evade(entities) then return false end
 end
 for _,e in ipairs(entities or {}) do if e.prefab=="chest_mimic" then
  local q=e:GetPosition();local key=math.floor(q.x+.5)..":"..math.floor(q.z+.5)
  self.boxes[key]=e -- 拟态变回箱子时GUID改变，同一位置仍只算一个箱子。
 end end
 local waiting=false
 if self.pending then
  local t=self.pending;local c=t.box.replica and t.box.replica.container
  local bag=false;for _,e in ipairs(A.Items(self.player)) do if e==t.item then bag=true end end
  -- 堆叠可能合并，必须同时观察箱格消失及本地同类数量增加。
  local count=0;for _,e in ipairs(A.Items(self.player)) do if e.prefab==t.item.prefab then local st=e.replica and e.replica.stackable;count=count+(st and st:StackSize() or 1) end end
  if bag or c and c:IsOpenedBy(self.player) and c:GetItemInSlot(t.slot)~=t.item and count>t.before then self.pending=nil;self.progress=now;self.quiet_since=nil
  elseif now<t.deadline then waiting=true
  else self.pending=nil;waiting=true;self.arena:Say("奖励流程 · 取物未确认 "..t.item.prefab.."，继续核对而不停止避险") end
 end
 if Route.Tick(self,entities) then return false end
 if waiting then self:Evade(entities);return false end
 local total=0;local box
 local boxkey
 for id,e in pairs(self.boxes) do total=total+1;if not self.visited[id] and e:IsValid() and (not box or self.player:GetPosition():DistSq(e:GetPosition())<self.player:GetPosition():DistSq(box:GetPosition())) then box=e;boxkey=id end end
 local selected=self.reward_route and self.reward_route.target
 for id,e in pairs(self.boxes) do if e==selected and R.Live(e) and not self.visited[id] then box=e;boxkey=id;break end end
 for id,e in pairs(self.boxes) do if e==self.opened and e:IsValid() and not self.visited[id] then box=e;boxkey=id;break end end
 if box then
  local h=self.arena.healing
  local approach=require("shadowself/control/arena_scrappig").Context(self,entities)
  local c=box.replica and box.replica.container
  if not (c and c:IsOpenedBy(self.player)) and Route.Before(self,entities,box) then return false end
  if self:Evade(entities) then return false end
  -- 已打开的拟态箱只有短暂取物窗口，先取物，不能因接近检查反复把箱子关闭。
  if not (c and c:IsOpenedBy(self.player)) and h and (not h:Safe(approach,box:GetPosition(),.6) or not h:Path(approach,box:GetPosition())) then
   if require("shadowself/control/arena_scrappig").Approach(self,entities,box,approach) then return false end
   Route.Begin(self,"奖励流程 · 宝箱接近路径不安全，继续外圈巡游七秒")
   Route.Tick(self,entities);return false
  end
  if not c or not c:IsOpenedBy(self.player) then
   if now>=(self.next_request or 0) and not self.player.components.playercontroller:IsBusy() then
    if self.opened~=box then self:Stop();self.opened=box;self.open_since=now end
    local revision=self.route_revision or 0;local instance,generation=self.arena.instance,self.arena.generation
    A.Scene(self.player,box,ACTIONS.RUMMAGE,function() return self.arena.running and self.arena.wave==11 and self.arena.stage11==self.s
     and self.arena.instance==instance and self.arena.generation==generation and R.Live(box) and Route.Valid(self,box,revision) end)
    self.next_request=now+1
   end
   if self.open_since and now-self.open_since>15 then self.arena:Say("奖励流程 · 宝箱打开未确认，先避险后重试");self.open_since=now end
   return false
  end
  if self.confirmed_open~=box then self.confirmed_open=box;self.next_request=now;self.empty_since=nil;self.quiet_since=nil end
  self.opened=box
  if now<(self.next_request or 0) then return false end
  for slot,item in pairs(c:GetItems() or {}) do
   self.inspected[boxkey]=true
   if self:Needed(item) then
    self.quiet_since=nil
    if not self:Room(item) then return false end
    local before=0;for _,e in ipairs(A.Items(self.player)) do if e.prefab==item.prefab then local st=e.replica and e.replica.stackable;before=before+(st and st:StackSize() or 1) end end
    c:MoveItemFromAllOfSlot(slot,self.player)
    self.pending={box=box,item=item,slot=slot,before=before,deadline=now+TRANSFER_ACK};self.next_request=now+.1;return false
   end
  end
  if not self.inspected[boxkey] then
   -- 空箱也需确认副本容器已打开、实际空状态稳定，不能永远等第一件不存在的物品。
   if c.IsEmpty and c:IsEmpty() then
    self.empty_since=self.empty_since or now
    if now-self.empty_since<CONTENT_SETTLE then return false end
    self.inspected[boxkey]=true
   else
    self.empty_since=nil
    if self.open_since and now-self.open_since>5 then self:Fail("宝箱内容未同步，不能按空箱完成") end
    return false
   end
  end
  -- 即使已经见过其他物品，也给迟到的奖励副本完整的同步窗口。
  -- 有待确认转移时不会进入这里；新奖励出现后重新计时。
  self.quiet_since=self.quiet_since or self.empty_since or now
  if now-self.quiet_since<CONTENT_SETTLE then return false end
  self.visited[boxkey]=true;self.progress=now;self:Stop();self.open_since=nil
  if not self:BoxesDone() then require("shadowself/control/arena_scrappig").AfterBox(self,entities);return false end
  -- 第四箱确认完立即进入换装/装填，不再绕场撤离或等待宝箱怪离场。
 end
 if not self:BoxesDone() and self:Evade(entities) then return false end
 if total<4 then self.arena:Say("奖励流程 · 等待四个真实宝箱同步");return false end
 local visited=0;for _ in pairs(self.visited) do visited=visited+1 end
 if visited<4 then
  self.arena:Say("奖励流程 · 宝箱已变形，等待容器恢复/核对缺失奖励，保持避险")
  self:Evade(entities);return false
 end
 if self:Document() then
  if not R.Item(self.player,"staff_lunarplant") or not R.Item(self.player,"queen_torch") then self.arena:Say("四箱已检查 · 等待亮茄法杖和queen_torch真实入包");return false end
  if not R.Weapon(self.s,"staff_lunarplant") then return false end
  self.complete=true;return true
 end
 if not R.Equip(self.s,"alterguardianhat",EQUIPSLOTS.HEAD) then return false end
 local hat=inv:GetEquippedItem(EQUIPSLOTS.HEAD);local c=hat.replica and hat.replica.container
 if not c or not c:IsOpenedBy(self.player) then self.arena:Say("等待启迪之冠真实容器打开");return false end
 local seeds,free=0,0
 for i=1,c:GetNumSlots() do local e=c:GetItemInSlot(i);if not e then free=free+1 elseif e.prefab=="lunar_seed" then seeds=seeds+1 end end
 if self.seed_pending then
  if seeds>self.seed_pending.before then self.seed_pending=nil;self.progress=now
  elseif now<self.seed_pending.deadline then return false
  else self.seed_pending=nil;return self:Fail("天体珠宝装填没有得到容器确认") end
 end
 local slot,seed
 for i,e in pairs(inv:GetItems() or {}) do if e.prefab=="lunar_seed" then slot,seed=i,e;break end end
 if free>0 and seed then
  if now>=(self.next_request or 0) then
   inv:MoveItemFromCountOfSlot(slot,hat,1)
   self.seed_pending={before=seeds,deadline=now+3};self.next_request=now+.4
  end
  return false
 end
 if seeds==0 then return self:Fail("启迪之冠内没有lunar_seed，不能用相似名称物品代替") end
 if not R.Weapon(self.s,"staff_lunarplant") then return false end
 self.complete=true
 return true
end
function C:Ready(travel)
 if not self.complete then return false end
 if self:Document() then
  local staff=travel and R.Item(self.player,"staff_lunarplant") or self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
  return staff and staff.prefab=="staff_lunarplant" and R.Item(self.player,"queen_torch")~=nil or false
 end
 local inv=self.player.replica.inventory;local hat=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 if not hat or hat.prefab~="alterguardianhat" or not hat:IsValid() then return false end
 local c=hat.replica and hat.replica.container
 if not c or not c:IsOpenedBy(self.player) then return false end
 local seed=false;for _,e in pairs(c:GetItems() or {}) do if e.prefab=="lunar_seed" then seed=true;break end end
 local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)
 if travel then hand=R.Item(self.player,"staff_lunarplant") end
 return seed and hand and hand.prefab=="staff_lunarplant" and not hand:HasTag("broken")
end
return C
