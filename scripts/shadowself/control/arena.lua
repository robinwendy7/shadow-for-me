local A=require("shadowself/control/actions")
local Policy=require("shadowself/control/arena_policy")
local Inventory=require("shadowself/control/arena_inventory")
local Arena=Class(function(self,player,plan,report)
 self.player=player;self.plan=plan;self.report=report or function() end
 self.adapter=require("shadowself/control/arena_adapter")(player)
 self.bridge=require("shadowself/control/combat")(player)
 self.since=GetTime();self.running=true;self.runs=0;self.wave=1;self.ignored={}
 player._shadowself_arena_move_owner=self
 self.encounters=require("shadowself/control/arena_encounters")(self)
 self.healing=require("shadowself/control/arena_healing")(player)
 self.opening=require("shadowself/control/arena_opening")(self)
 self.whip=require("shadowself/control/arena_whip")()
end)
function Arena:Say(message)
 if self.message~=message then
  self.message=message
  if self.wave==8 then print("[ShadowSelf][boat] "..message) end
  self.report(message)
 end
end
function Arena:BatAttached()
 if self.wave~=6 and self.wave~=7 then return false end
 local inv=self.player.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 return head and head.prefab=="bat_boss" or self.bridge.coordinator and self.bridge.coordinator.bat_detach~=nil or false
end
function Arena:OwnsCombat() return self.bridge:Running() end
function Arena:Dormant(e)
 local hunt=self.opening and self.opening.hunt
 return Policy.DormantTrapGuard(e,self.wave) and not (hunt and hunt:Escort(e))
end
function Arena:StopCombat() if self.bridge:Running() then self.bridge:Stop() end end
function Arena:Entities()
 local p=self.player:GetPosition();local enemies,items={},{}
 if not self.raw_entities or GetTime()>=(self.next_entities or 0) then
  self.raw_entities=TheSim:FindEntities(p.x,0,p.z,60,nil,{"INLIMBO","FX","DECOR","playerghost"})
  self.next_entities=GetTime()+.2
 end
 self.entities={}
 for _,e in ipairs(self.raw_entities) do if e:IsValid() then self.entities[#self.entities+1]=e end end
 if self.wave==11 then
  for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,12,{"FX"},{"INLIMBO"})) do
   if e.prefab=="worm_boss_dirt_ground_fx" then self.entities[#self.entities+1]=e end
  end
 end
 for _,e in ipairs(self.entities) do
  if e~=self.player and e:IsValid() and not e:HasTag("player") then
   local health=e.replica and e.replica.health
   if Policy.Monster(e.prefab,self.wave) and e.replica and e.replica.combat and not e:HasTag("isdead") and not e:HasTag("dead") and not (health and health:IsDead()) and not self:Dormant(e) then enemies[#enemies+1]=e
   elseif Policy.known[e.prefab] and e.replica and e.replica.inventoryitem and not e.replica.inventoryitem:IsHeld() then items[#items+1]=e end
  end
 end
 local priorities,distances={},{}
 for _,item in ipairs(items) do priorities[item]=Inventory.Priority(item,self.wave);distances[item]=p:DistSq(item:GetPosition()) end
 table.sort(items,function(a,b)
  local reserveA=priorities[a];local reserveB=priorities[b]
  if reserveA~=reserveB then return reserveA>reserveB end
  return distances[a]<distances[b]
 end)
 return enemies,items
end
function Arena:Inventory()
 local owned,items={},A.Items(self.player)
 for _,item in ipairs(items) do owned[item.prefab]=true end
 return owned,items
end
function Arena:Want(item,bag)
 if not Policy.PickupAllowed(item,self.wave,self.player) then return false end
 if self.wave==11 and self.collect_stage11_hats and self.collect_stage11_hats==self.stage11
  and item.prefab=="wathgrithr_improvedhat" then
  return item:IsValid() and not item:HasTag("broken") and Inventory.Condition(item)>0
 end
 if self.wave==5 and self.pirate_opening and (not self.pirate_opening.ready or self.pirate_opening.collecting)
  and require("shadowself/control/arena_supply").PirateItem(item) then return true end
 if item.prefab=="whip" then return self.whip:Want(item,bag,not self.whip:CanPickup(self.player,item)) end
 return Inventory.Want(item,bag,self.player,self.wave)
end
-- 陷阱拾取以服务器关间状态为准，本地空扫描不能代表目标已全部击杀。
function Arena:TrapReady()
 local s=self.adapter:Snapshot()
 return self.running and s and s.intermission and not s.settlement
  and s.instance==self.instance and s.generation==self.generation and s.wave==self.wave
  and #self:NearbyEnemies(60)==0
end
function Arena:CancelTrapPickup()
 local item=self.pending_item
 if not item or not Policy.TrapLoot(item,self.wave) then return end
 for _,owned in ipairs(A.Items(self.player)) do if owned==item then return end end
 if not self:TrapReady() then
  A.Stop(self.player);self.pending_item=nil;self.pick_deadline=nil;self.next_item=nil
 end
end
function Arena:Loot(items,cleared,extra_guard)
 self:CancelTrapPickup()
 if self.pending_item and not Policy.PickupAllowed(self.pending_item,self.wave,self.player) then
  A.Stop(self.player);self.pending_item=nil;self.pick_deadline=nil;require("shadowself/control/arena_pickup_travel").Release(self)
 end
 local owned,bag=self:Inventory();local inv=self.player.replica.inventory
 if self.pending_item then
  local held=false;for _,i in ipairs(bag) do if i==self.pending_item then held=true;break end end
  if held or not self.pending_item:IsValid() then
   if held and Inventory.Armor(self.pending_item) then self.equip_due=true end
   require("shadowself/control/arena_pickup_travel").Release(self)
   self.pending_item=nil;self.pick_deadline=nil
  elseif GetTime()<(self.pick_deadline or 0) then
   require("shadowself/control/arena_pickup_travel").Ready(self,self.player,self.wave,self.pending_item)
   return true
  else self.ignored[self.pending_item.GUID]=GetTime()+5;self.pending_item=nil end
 end
 if self.player.components.playercontroller:IsBusy() then return true end
 if self.equip_due then
  if GetTime()<(self.next_equip or 0) or self:Equip(self.enemies or {}) then return true end
  self.equip_due=nil
 end
 if GetTime()<(self.next_item or 0) then return true end
 local wanted
 for _,item in ipairs(items) do
  if GetTime()>=(self.ignored[item.GUID] or 0) and self:Want(item,bag) and require("shadowself/control/arena_fire").Safe(self.player,item:GetPosition(),self.fire_zones) then wanted=item;break end
 end
 -- 普通补给先拿；法杖不能在开战前或清怪缓存过期时触发陷阱。
 if wanted and Policy.TrapLoot(wanted,self.wave) then wanted=nil end
 if not wanted then
  for _,item in ipairs(items) do
   if not Policy.TrapLoot(item,self.wave) and GetTime()>=(self.ignored[item.GUID] or 0)
    and self:Want(item,bag) and require("shadowself/control/arena_fire").Safe(self.player,item:GetPosition(),self.fire_zones) then wanted=item;break end
  end
 end
 if not wanted and cleared and self:TrapReady() then
  for _,item in ipairs(items) do
   if Policy.TrapLoot(item,self.wave) and GetTime()>=(self.ignored[item.GUID] or 0)
    and self:Want(item,bag) and require("shadowself/control/arena_fire").Safe(self.player,item:GetPosition(),self.fire_zones) then
    -- 拿陷阱前覆盖整个补给扫描范围，不能只凭近处24码或旧缓存判清场。
    if #self:NearbyEnemies(60)>0 then return false end
    wanted=item;break
   end
  end
 end
 if not wanted then require("shadowself/control/arena_pickup_travel").Release(self);return false end
 self:StopCombat()
 local capacity=inv.GetNumSlots and inv:GetNumSlots() or 15;local used=0
 for _ in pairs(inv:GetItems() or {}) do used=used+1 end
 local overflow=inv.GetOverflowContainer and inv:GetOverflowContainer()
 local spare=overflow and overflow.GetNumSlots and overflow:GetNumSlots() or 0
 if overflow then for _ in pairs(overflow:GetItems() or {}) do spare=spare-1 end end
 if used>=capacity and spare<=0 then
  local discard_bag=bag
  if self.wave==5 and self.pirate_opening and not self.pirate_opening.ready then
   discard_bag={}
   for _,item in ipairs(bag) do if not require("shadowself/control/arena_supply").PirateItem(item) then discard_bag[#discard_bag+1]=item end end
  end
  local old=Inventory.Discard(discard_bag,self.player,self.wave,wanted)
  if old then
   inv:DropItemFromInvTile(old,false);self.ignored[old.GUID]=math.huge;self.next_item=GetTime()+.5;return true
  end
  self:Say("背包已满，保留后段关键装备；暂缓拾取"..(wanted:GetBasicDisplayName() or wanted.prefab))
  self.ignored[wanted.GUID]=GetTime()+5;return false
 end
 local guard
 if self.wave==5 and self.pirate_opening and (not self.pirate_opening.ready or self.pirate_opening.collecting)
  and require("shadowself/control/arena_supply").PirateItem(wanted) then
  local opening=self.pirate_opening;local instance,generation=self.instance,self.generation
  guard=function() return self.running and self.wave==5 and self.instance==instance and self.generation==generation
   and self.pirate_opening==opening and (not opening.ready or opening.collecting) and require("shadowself/control/arena_supply").PirateItem(wanted)
   and (#(self.enemies or {})==0 or require("shadowself/control/arena_supply").SafePickup(self,wanted)) end
 elseif Policy.TrapLoot(wanted,self.wave) then
  local wave,instance,generation=self.wave,self.instance,self.generation
  guard=function()
   return self.wave==wave and self.instance==instance and self.generation==generation and self:TrapReady()
  end
 elseif wanted.prefab=="panflute" and self.wave==5 then
  local instance=self.instance
  guard=function() return self.instance==instance and require("shadowself/control/arena_supply").SafePickup(self,wanted) end
 elseif wanted.prefab=="whip" then
  local instance=self.instance
  local wave=self.wave
  guard=function() return self.running and self.instance==instance and self.wave==wave and (wave==2 or wave==5) and self.whip.active and self.whip:CanPickup(self.player,wanted) end
 end
 local previous_guard=guard
 guard=function() return Policy.PickupAllowed(wanted,self.wave,self.player) and (not previous_guard or previous_guard()) and (not extra_guard or extra_guard()) end
 if not require("shadowself/control/arena_pickup_travel").Ready(self,self.player,self.wave,wanted) then return true end
 if A.Scene(self.player,wanted,ACTIONS.PICKUP,guard) then
  self.pending_item=wanted;self.pick_deadline=GetTime()+math.max(3,math.sqrt(self.player:GetPosition():DistSq(wanted:GetPosition()))/4+2)
  self.next_item=GetTime()+.2;return true
 end
 self.ignored[wanted.GUID]=GetTime()+3;return false
end
function Arena:Prune(upcoming)
 if self.player.components.playercontroller:IsBusy() or GetTime()<(self.next_item or 0) then return false end
 local _,bag=self:Inventory();local item=Inventory.Cleanup(bag,self.player,self.wave,upcoming)
 item=item or (upcoming and Inventory.ForecastDiscard(bag,self.player,self.wave,self.route) or Inventory.Discard(bag,self.player,self.wave))
 if item then
  self:StopCombat();self.player.replica.inventory:DropItemFromInvTile(item,false)
  self.ignored[item.GUID]=math.huge;self.next_item=GetTime()+.5;return true
 end
 return false
end
function Arena:Equip(enemies)
 if self.player.components.playercontroller:IsBusy() or self.player:HasTag("attack") or GetTime()<(self.next_equip or 0) then return false end
 local inv=self.player.replica.inventory;local _,items=self:Inventory()
 if self.equip_pending then
  local pending=self.equip_pending
  if inv:GetEquippedItem(pending.slot)==pending.item or not pending.item:IsValid() then self.equip_pending=nil
  elseif GetTime()<pending.deadline then return true
  else self.equip_pending=nil end
 end
 for _,slot in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
  local hand=inv:GetEquippedItem(slot);local best=hand;local score=hand and Policy.ArmorScore(hand,slot,enemies) or -1
  score=score or -1
  for _,item in ipairs(items) do local eq=item.replica and item.replica.equippable
   if eq and eq:EquipSlot()==slot and Policy.AllowArmor(item,self.wave,enemies) then local value=Policy.ArmorScore(item,slot,enemies)
    if value and value>score then best,score=item,value end
   end
  end
  if slot==EQUIPSLOTS.HEAD then best=require("shadowself/control/arena_inventory").HelmetFallback(self.player,items,self.wave) or best end
  if best and best~=hand then
   self:StopCombat();self.next_equip=GetTime()+.5
   if A.Self(self.player,best,ACTIONS.EQUIP) then self.equip_pending={item=best,slot=slot,deadline=GetTime()+2};return true end
  end
 end
 return false
end
function Arena:HelmetFallback()
 local inv=self.player.replica.inventory
 if self.equip_pending and (inv:GetEquippedItem(self.equip_pending.slot)==self.equip_pending.item
  or not self.equip_pending.item:IsValid() or GetTime()>=self.equip_pending.deadline) then self.equip_pending=nil end
 local c=self.bridge.coordinator
 if self.healing and self.healing.pending or c and (c.dodging or c.travel and c.travel.dodging) then return false end
 local best=require("shadowself/control/arena_inventory").HelmetFallback(self.player,A.Items(self.player),self.wave)
 if not best or inv:GetEquippedItem(EQUIPSLOTS.HEAD)==best or self.equip_pending or self.pending_item
  or self.player.components.playercontroller:IsBusy() or self.player:HasTag("attack") or GetTime()<(self.next_equip or 0) then return false end
 self:StopCombat();self.next_equip=GetTime()+.5
 if A.Self(self.player,best,ACTIONS.EQUIP) then self.equip_pending={item=best,slot=EQUIPSLOTS.HEAD,deadline=GetTime()+2};return true end
 return false
end
function Arena:Combat()
 if self.bridge:Running() then return true end
 local plan={kind="fight",target="",coordinated=true,arena=true,arena_remaining=function() return self.enemies or {} end,arena_wave=function() return self.wave end,arena_priority=function() return self.stage12 and self.stage12.target or self.stage11 and self.stage11.target or self.opening.target end,arena_healing=self.healing,arena_no_whip=function() return self.trap_dogs end,arena_ground=function() return self.items or {} end,arena_contains=function(e)
  return Policy.Monster(e.prefab,self.wave) and self.encounters:Allowed(e) and self.player:GetPosition():DistSq(e:GetPosition())<60^2
 end}
 plan.arena_spider_control=function(e) return self.opening:SpiderScene():Allowed(e) end
 plan.arena_spider_scene=function() return self.opening:SpiderScene():Active() end
 plan.arena_bone_busy=function() return require("shadowself/control/arena_bone_maintenance").Busy(self.player) end
 plan.arena_stage11=self.stage11
 plan.arena_stage12=self.stage12
 plan.arena_strategy=self.stage12 or self.stage11
 plan.arena_lunar12=self.lunar12
 plan.arena_route=self.detected_route or self.route
 plan.arena_bird_committed=function(e) return self.wave==2 and e and ({smallbird=true,teenbird=true,tallbird=true})[e.prefab] or false end
 plan.arena_clockwork=self.opening.rhythm
 plan.arena_walrus=self.opening.hunt
 plan.arena_pirate_opening=self.pirate_opening
 plan.arena_entities=function() return self.entities or {} end
 plan.arena_objectives=function() return self.remaining_objectives end
 if self.wave==5 then
  for _,e in ipairs(self.entities or {}) do if e.prefab=="slurtle" or e.prefab=="snurtle" then plan.arena_snail_scene=true;break end end
 end
 plan.arena_center=function() return self.encounters:FindCenter() end
 plan.arena_whip=function() return self.whip.active end
 plan.arena_whip_state=self.whip
 plan.arena_no_whip=function() return self.trap_dogs and not (self.whip.active and self.whip:CanAttack(self.player)) end
 local ok,why=self.bridge:Start(plan,function() return true end)
 if not ok then return false,why end
 if self.encounters.worm_target or self.encounters.add_target then self.bridge.priority_target=self.encounters.worm_target or self.encounters.add_target end
 return true
end
function Arena:NearbyEnemies(range)
 -- 大范围补给列表允许缓存，但进食前必须重新检查近处新生成的怪。
 local near={};local p=self.player:GetPosition()
 for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,range or 24,nil,{"INLIMBO","FX","DECOR","isdead","playerghost"})) do
  local h=e.replica and e.replica.health
  if e~=self.player and e:IsValid() and Policy.Monster(e.prefab,self.wave) and e.replica and e.replica.combat
   and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h:IsDead()) and not self:Dormant(e) then near[#near+1]=e end
 end
 if self.raw_entities and #near>0 then
  local found={};for _,e in ipairs(self.raw_entities) do found[e]=true end
  for _,e in ipairs(near) do if not found[e] then self.raw_entities[#self.raw_entities+1]=e end end
 end
 return near
end
function Arena:Rest(near,full,waiting_crab)
 near=near or self:NearbyEnemies()
 if #near>0 then return false,near end
 if not self.healing:Health() then return false end
 if not self.rest_actions then
  require("shadowself/legacy/action_library")
  self.rest_actions=require("shadowself/legacy/registry").ActionLibrary(self.player,{})
 end
 local c={player=self.player,intermission=true,full_recovery=full,waiting_crab=waiting_crab,enemies={},observed={},hazards={},actions=self.rest_actions,
  plan={arena=true,arena_wave=function() return self.wave end,arena_ground=function() return self.items or {} end},
  bridge={PauseAttack=function() end}}
 if self.healing:Tick(c) then self.pending_item=nil;return true end
 return false
end
function Arena:Encounter()
 local mode,message=self.encounters:Tick(self.entities or {})
 if mode=="failed" then self:StopCombat();return "failed",message end
 if mode=="hold" then return "running" end
 if mode=="fight" then
  local ok,why=self:Combat();if not ok then return "failed",why end
  if self.encounters.worm_target or self.encounters.add_target then self.bridge.priority_target=self.encounters.worm_target or self.encounters.add_target end
  self.encounters:MaintainCombat()
  return "running"
 end
end
function Arena:Tick()
 if not self.running then return "done" end
 local snapshot,why=self.adapter:Snapshot()
 if not snapshot then
  self:StopCombat()
  if self.adapter.error or GetTime()-self.since>60 then return "failed",why end
  self:Say(why);return "running"
 end
 if self.player:HasTag("playerghost") or self.player:HasTag("corpse") then self:StopCombat();self:Say("等待角斗场结算和服务器复原角色。");return "running" end
 if snapshot.settlement then
  self:StopCombat();self.settling=true;self.pending_item=nil
  self.enemies=self:NearbyEnemies(60)
  if require("shadowself/control/arena_residual").Tick(self) then return "running" end
  self:Say("本局结算中，等服务器归还大厅后开始下一局。");return "running"
 end
 if snapshot.instance and snapshot.kind=="PARTICIPANT" then
  if not snapshot.arena or not snapshot.wave then self:StopCombat();return "running" end
  if self.instance~=snapshot.instance or self.generation~=snapshot.generation then
   if self.stage12 then self.stage12:Stop() end
   if self.stage11 then require("shadowself/control/arena_late_runtime").Stop(self.stage11) end
   self.stage12=nil
   self.lunar12=nil
   self.pirate_opening=nil;self.stage11=nil;self.detected_route=nil;self.ten_cleanup_due=nil;self.ten_cleanup_done=nil
   self.whip=self.instance==snapshot.instance and self.whip or require("shadowself/control/arena_whip")();self:StopCombat();self.instance=snapshot.instance;self.generation=snapshot.generation;self.runs=self.runs+1;self.ignored={};self.pending_item=nil;self.encounters:Reset();self.opening:Reset();self.healing:Reset();self.raw_entities=nil
  end
  self.settling=nil;self.since=GetTime()
  if self.wave~=snapshot.wave or self.route~=snapshot.route then
   self.pirate_opening=nil
   if self.wave~=snapshot.wave then
    self.lunar12=nil
    if self.stage12 then self.stage12:Stop();self:StopCombat();self.stage12=nil end
    if self.stage11 then require("shadowself/control/arena_late_runtime").Stop(self.stage11) end
    if self.stage11 then self:StopCombat() end -- 清除原生桥捕获的第十一关攻击门槛。
    self.stage11=nil
   end
   if snapshot.wave==10 and self.wave~=10 then self.ten_cleanup_due=true;self.ten_cleanup_done=nil end
   self.wave=snapshot.wave;self.route=snapshot.route;self.pending_item=nil;self.ignored={};self.encounters:Reset();self.opening:Reset();self.raw_entities=nil
   if self.wave==8 then self.next_item=nil;self.pick_deadline=nil;self.equip_due=nil;self.equip_pending=nil;self.next_equip=nil end
   local policy=Policy.waves[self.wave];self:Say("角斗场第"..self.wave.."关："..(policy and policy.note or "按当前敌人处理。"))
  end
  self:CancelTrapPickup()
  self.remaining_objectives=snapshot.remaining_objectives
  local enemies,items=self:Entities()
  self.items=items;self.enemies=enemies
  if require("shadowself/control/arena_residual").Tick(self) then return "running" end
  if self:BatAttached() then
   -- 最后一只套头时不在地面扫描中；仍须运行原监督循环完成卸下/落地确认。
   local ok,reason=self:Combat();if not ok then return "failed",reason end
   return "running"
  end
  require("shadowself/control/arena_bone_maintenance").Sync(self)
  if self:HelmetFallback() then return "running" end
  -- 第八关在同一次关卡确认中推进船流程，旧猫鞭、普通清包/补给和开局动作均不插队。
  if self.wave==8 then self.fire_zones={};return self:Encounter() end
  if require("shadowself/control/arena_supply").CleanupNine(self,snapshot) then return "running" end
  if require("shadowself/control/arena_supply").AfterTen(self,snapshot) then return "running" end
  if require("shadowself/control/arena_supply").CaneOpening(self) then return "running" end
  self.whip:Update(self.wave,enemies,snapshot.intermission and #self:NearbyEnemies(60)==0,self.entities)
  require("shadowself/control/arena_frogloot").Update(self,snapshot)
  if self.whip.finished and not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.whip.next_drop or 0) then
   for _,item in ipairs(A.Items(self.player)) do if item.prefab=="whip" then
    self:StopCombat();self.player.replica.inventory:DropItemFromInvTile(item,false)
    self.ignored[item.GUID]=math.huge;self.whip.next_drop=GetTime()+.5;return "running"
   end end
  end
  self.trap_dogs=false
  if self.wave==2 or self.wave==3 then
   for _,e in ipairs(self.entities or {}) do if (e.prefab=="icehound" or e.prefab=="firehound") and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") then self.trap_dogs=true;break end end
  end
  local fire=require("shadowself/control/arena_fire");local p=self.player:GetPosition()
  self.fire_zones=fire.Zones(self.player,TheSim:FindEntities(p.x,0,p.z,16,nil,{"INLIMBO"}))
  if self.wave==10 then
   for _,zone in ipairs(fire.LavaZones(self.entities or {})) do self.fire_zones[#self.fire_zones+1]=zone end
  end
  if self.wave==2 then
   for _,zone in ipairs(fire.WebZones(self.player,self.entities or {})) do self.fire_zones[#self.fire_zones+1]=zone end
  end
  if require("shadowself/control/arena_frogloot").Opening(self) then return "running" end
  if self.whip.active and self.whip:CanPickup(self.player) and not self.bridge:Running() then
   local owned=false
   for _,item in ipairs(A.Items(self.player)) do if item.prefab=="whip" and require("shadowself/control/arena_tools").Usable(item) then owned=true;break end end
   if not owned then
    for _,item in ipairs(items) do if item.prefab=="whip" and self:Loot({item}) then return "running" end end
   end
  end
  if not self.bridge:Running() then
   local escape=fire.Escape(self.player,self.fire_zones)
   if escape then
    self.pending_item=nil
    if GetTime()>=(self.next_fire_move or 0) then A.Move(self.player,escape);self.next_fire_move=GetTime()+.15 end
    return "running"
   end
  end
  if require("shadowself/control/arena_bone_maintenance").Busy(self.player) then return "running" end
  if require("shadowself/control/arena_supply").Tick(self,snapshot) then return "running" end
  if require("shadowself/control/arena_lunar12").Prepare(self) then return "running" end
  if fire.Safe(self.player,self.player:GetPosition(),self.fire_zones) and self.opening:Tick(enemies) then return "running" end
  local encounter,message=self:Encounter()
  if encounter then return encounter,message end
  if #enemies==0 then
   local near=self:NearbyEnemies()
   if #near>0 then
    local ok,why=self:Combat();if not ok then return "failed",why end
    return "running"
   end
   -- 最后一只怪死亡时，让已开始的进食先收到确认，不能StopCombat把料理动作取消。
   if self.bridge:Running() and self.healing.pending and not self.healing.pending.interrupted then self.bridge:PauseAttack();return "running" end
   self:StopCombat()
   -- 只有服务器确认关间休整且全场无活怪，才按下一关必出武器提前丢弃。
   if snapshot.intermission and not self.pending_item and not self.healing.pending
    and #self:NearbyEnemies(60)==0 and self:Prune(true) then return "running" end
   local resting=self:Rest(near)
   if resting then return "running" end
   -- 拾取在服务器确认前仍占用本次操作，避免换装覆盖走向物品的动作。
   if not self:Loot(items,true) and not self:Equip(enemies) then self:Prune() end
   return "running"
  end
  -- 前置补给优先；已经交战后拾取不抢走走位进程。
  if not self.bridge:Running() then
   local urgent=false;local hasweapon=false
   for _,item in ipairs(A.Items(self.player)) do
    if item:HasTag("weapon") and item.prefab~="cane" and item.prefab~="icestaff" and item.prefab~="firestaff" then hasweapon=true;break end
   end
   for _,e in ipairs(enemies) do if self.player:GetPosition():DistSq(e:GetPosition())<6^2 then urgent=true;break end end
   if not urgent or not hasweapon then
    if self:Loot(items) or self:Equip(enemies) then return "running" end
   else self.pending_item=nil end
  end
  if not self.bridge:Running() and not self.pending_item and self:Equip(enemies) then return "running" end
  local ok,message=self:Combat();if not ok then return "failed",message end
  return "running"
 end
 require("shadowself/control/arena_bone_maintenance").Stop(self)
 self:StopCombat();self.instance=nil;self.generation=nil;self.pending_item=nil
 if self.settling then self.settling=nil;self.adapter.rejections=0;self.since=GetTime() end
 if GetTime()-self.since>180 then return "failed","角斗场开局长时间没有得到服务器入场确认，已停止。" end
 self:Say("单人角斗场循环：正在选择经典单人、准备和开局。")
 return self.adapter:Prepare(snapshot)
end
function Arena:Cancel()
 require("shadowself/control/arena_bone_maintenance").Stop(self)
 if self.player._shadowself_arena_move_owner==self then self.player._shadowself_arena_move_owner=nil end
 if self.stage12 then self.stage12:Stop() end
 if self.stage11 then require("shadowself/control/arena_late_runtime").Stop(self.stage11) end
 self.running=false;self:StopCombat();self.adapter:Cancel();self.pending_item=nil;self.healing:Reset()
 A.Stop(self.player)
end
return Arena
