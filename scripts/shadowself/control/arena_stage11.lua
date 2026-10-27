-- 第十一关：补给/食用确认与路线战术，复用Arena调度及原生战斗，不另起循环。
local A=require("shadowself/control/actions")
local Inv=require("shadowself/control/arena_inventory")
local Nav=require("shadowself/control/navigation")
local Food=require("shadowself/control/arena_food")
local routes={shadow={marker="mermguard_shadow",boss="daywalker",count=4,label="暗影线"},
 lunar={marker="mermguard_lunar",boss="daywalker2",count=4,label="月亮线"},
 default={marker="cave_vent_mite",boss="worm_boss",count=4,label="普通线"}}
local function dead(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()) or false
end
local function live(e) return e and e:IsValid() and not dead(e) and not e:HasTag("INLIMBO") end
local function headarmor(item)
 local eq=item and item.replica and item.replica.equippable
 return item and item:IsValid() and not item:HasTag("broken") and Inv.Condition(item)>0
  and eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and Inv.Protection(item)>0
end
local function chew(e)
 if not live(e) or not e.AnimState then return false end
 for _,name in ipairs({"chew_small","chew_big","chew_shock_loop","chew_shock_pst"}) do
  if e.AnimState:IsCurrentAnimation(name) then return true end
 end
 return false
end
local S=Class(function(self,arena)
 self.arena=arena;self.player=arena.player;self.seen={};self.phase="prepare"
 self.context={player=self.player,enemies={},observed={},hazards={},snapshot={},h={},gear={},
  plan={arena=true,arena_wave=function() return arena.wave end,arena_ground=function() return arena.items or {} end,arena_center=function() return arena.encounters:FindCenter() end},
  actions={SafePoint=function(_,q) return TheWorld.Map:IsPassableAtPoint(q.x,0,q.z) and not TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) end},
  bridge={PauseAttack=function() arena:StopCombat() end}}
 self.buffs=require("shadowself/control/supplies")(self.context)
 self.food=require("shadowself/control/arena_stage11_food")(self)
end)
-- 残血恢复由同一个Arena tick执行，不让侧方冲撞线程反复抢走治疗窗口。
function S:Recovery()
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then self.recovering=nil;self.feeding=nil;self.food_window=nil;return false end
 local h=self.arena.healing
 if not h or not h.Health or not h.Tick then return false end
 local hp,max=h:Health();if not hp or not max or max<=0 or hp<=0 then return false end
 -- 月亮线仅剩拾荒疯猪：无有效回血料理时回到骨甲四击/贴堆循环，
 -- 不让75%回血目标将残局困在外圈45秒并自动停止。已有进食请求仍先确认。
 local body=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
 local solo=self.route=="lunar" and self:Cleared() and self.boss and self.boss.prefab=="daywalker2"
 for _,e in ipairs(self.arena.enemies or {}) do if e~=self.boss and live(e) then solo=false end end
 local shield=solo and require("shadowself/control/boneguard").Ready(self.context)
 local unsafe=shield and not h:Safe(self.context,self.player:GetPosition(),.9)
 if solo and body and body.prefab=="armorskeleton" and Inv.Condition(body)>0 and not h.pending
  and (self.recovering or hp/max<=.4) and (not self.food:Available("health") or unsafe) then
  if not self.recovery_nofood then print("[ShadowSelf][stage11] recovery=deferred reason="..(unsafe and "food_window_unsafe_shield_ready" or "no_safe_food").." fallback=bone_cycle hp="..hp) end
  self.recovery_nofood=true;self.recovering=nil;self.feeding=nil;self.food.since=nil;self.food:CancelPickup()
  return false
 end
 self.recovery_nofood=nil
 if not self.recovering and hp/max<=.4 then
  self.recovering=true
  if h.pending then h:Interrupt(self.context) end
  print("[ShadowSelf][stage11] recovery=begin hp="..hp)
 end
 if not self.recovering then return false end
 if hp/max>=.75 and not h.pending then
  self.recovering=nil;print("[ShadowSelf][stage11] recovery=end hp="..hp);return false
 end
 self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil;self.arena.encounters.worm_target=nil
 self.food:Tick("health");return true
end
function S:HungerRatio()
 local r=self.player.replica and self.player.replica.hunger
 if not r then return end
 if r.GetCurrent and r.Max then local max=r:Max();if max and max>0 then return r:GetCurrent()/max end end
 if r.GetPercent then return r:GetPercent() end
end
function S:Hunger()
 if require("shadowself/control/arena_doc_inventory").NoRecovery(self.player) then self.hungry=nil;return false end
 local ratio=self:HungerRatio();if not ratio then return false end
 if ratio<=.25 then self.hungry=true end
 if not self.hungry then return false end
 if ratio>=.65 and not self.arena.healing.pending then self.hungry=nil;return false end
 self.food:Tick("hunger");return true
end
function S:Observe(entities)
 if not self.route then
  for _,key in ipairs({"shadow","lunar","default"}) do
   for _,e in ipairs(entities or {}) do if e:IsValid() and e.prefab==routes[key].marker then
    self.route=key;self.arena.detected_route=key
    print("[ShadowSelf][stage11] route="..key.." source="..e.prefab);break
   end end
   if self.route then break end
  end
 end
 if not self.route then
  for _,e in ipairs(entities or {}) do
   local route=({daywalker="shadow",daywalker2="lunar",worm_boss="default",worm_boss_head="default",worm_boss_dirt="default"})[e.prefab]
   if route then self.route=route;self.arena.detected_route=route;break end
  end
 end
 if not self.route then return end
 self.head=nil;self.dirts={};self.boss=nil
 for _,e in ipairs(entities or {}) do
  if e.prefab==routes[self.route].marker then self.seen[e]=self.seen[e] or dead(e) end
  if e.prefab==routes[self.route].boss and live(e) then self.boss=e end
  if e.prefab=="worm_boss_head" and live(e) then self.head=e end
  if e.prefab=="worm_boss_dirt" and live(e) then self.dirts[#self.dirts+1]=e end
 end
 for e,confirmed in pairs(self.seen) do if not confirmed and dead(e) then self.seen[e]=true end end
end
function S:Cleared()
 if not self.route then return false end
 local count=0
 for _,confirmed in pairs(self.seen) do count=count+1;if not confirmed then return false end end
 return count>=routes[self.route].count
end
function S:Patrol(label)
 if self.food_window then return require("shadowself/control/arena_prepare").FoodMove(self,label) end
 if self.boss and self.boss.prefab=="daywalker2" and self:Cleared() then
  return require("shadowself/control/arena_stage11_finish").Orbit(self,self.arena.entities or {})
 end
 self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil
 self.context.enemies=self.arena.enemies or {};self.context.hazards=self.arena.fire_zones or {}
 local q=require("shadowself/control/arena_perimeter")(self.context,self,math.huge)
 if q then self.arena.encounters:Move(Nav.Select(self.context,q),label) else self.arena:Say(label.." · 等待场地中心") end
 return "hold"
end
function S:Prepare()
 local arena=self.arena;local p=self.player;local pc=p.components.playercontroller
 self.context.enemies=arena.enemies or {};self.context.hazards=arena.fire_zones or {}
 local hat,jelly
 for _,item in ipairs(A.Items(p)) do if item:IsValid() and not item:HasTag("broken") then
  if item.prefab=="wathgrithr_improvedhat" and Inv.Condition(item)>0 and (not hat or Inv.Condition(item)>Inv.Condition(hat)) then hat=item end
  if item.prefab=="voltgoatjelly_spice_chili" and Food.Health(item,p)>0 then jelly=item end
 end end
 if self.opening_equipped then
  local current=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
  if headarmor(current) then hat=current
  elseif not hat then
   for _,item in ipairs(A.Items(p)) do if headarmor(item) and (not hat or Inv.Protection(item)>Inv.Protection(hat)) then hat=item end end
  end
 end
 if self.buffs.pending then
  local safe=not arena.healing or arena.healing:Safe(self.context,p:GetPosition(),.3)
  if not safe then self.buffs.pending.interrupted=true end
  self.buffs:Tick()
  if not safe then self:Patrol("第十一关 · 进食窗口受威胁，先避让并继续核对食用结果") end
  return true
 end
 local want=not jelly and not self.buffs:Ready() and "voltgoatjelly_spice_chili" or not hat and "wathgrithr_improvedhat"
 if want then
  arena:StopCombat();local choices={}
  local bag=A.Items(p)
  for _,item in ipairs(arena.items or {}) do
   if item.prefab==want and item:IsValid() and (want~="wathgrithr_improvedhat" or headarmor(item))
    or want=="wathgrithr_improvedhat" and self.opening_equipped and headarmor(item) and Inv.Want(item,bag,p,11) then
    choices[#choices+1]=item
   end
  end
  table.sort(choices,function(a,b) return Inv.Condition(a)>Inv.Condition(b) end)
  if #choices>0 then
   if want=="voltgoatjelly_spice_chili" then
    local combined={};for _,item in ipairs(A.Items(p)) do combined[#combined+1]=item end;combined[#combined+1]=choices[1]
    local extra=Inv.ExcessMeal(combined,p,11,false)
    for _,item in ipairs(A.Items(p)) do if item==extra and item.prefab~=want then
     if not pc:IsBusy() and GetTime()>=(self.next_drop or 0) then
      p.replica.inventory:DropItemFromInvTile(item,false);arena.ignored[item.GUID]=math.huge;self.next_drop=GetTime()+.3
     end
     arena:Say("第十一关 · 腾出料理格，优先辣伏特羊角冻");return true
    end end
   end
   arena:Say("第十一关 · 优先拾取"..want);arena:Loot(choices);return true
  end
  if want=="voltgoatjelly_spice_chili" then
   if require("shadowself/control/arena_doc_inventory").NoRecovery(p) then
    self:Patrol("第十一关 · 缺少辣冻增益，继续避让并等待补捡，不转入回血料理流程")
   else self.food:Tick("reserve") end
   return true
  end
  self:Patrol("第十一关 · 等待"..want.."同步，保持安全巡游");return true
 end
 if p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)~=hat then
  arena:StopCombat();arena:Say(self.opening_equipped and "第十一关 · 恢复有效头部护甲" or "第十一关 · 装备女武神头盔")
  if not pc:IsBusy() and GetTime()>=(self.next_equip or 0) then A.Self(p,hat,ACTIONS.EQUIP);self.next_equip=GetTime()+.4 end
  return true
 end
 self.opening_equipped=true
 self.buffs:Check()
 if not self.buffs:Ready() then
  arena:StopCombat()
  if arena.healing and arena.healing.Safe and not arena.healing:Safe(self.context,p:GetPosition(),Food.Duration(jelly)+.3) then
   self.food_window=Food.Duration(jelly)+.3
   self:Patrol("第十一关 · 先拉开安全窗口再食用辣冻");return true
  end
  arena:Say("第十一关 · 确认食用辣伏特羊角冻后开启近战")
  self.buffs:Tick();return true
 end
 self.food_window=nil;self.hat=hat;self.prepared=true;return false
end
function S:Allowed(e)
 local allowed=require("shadowself/control/arena_doc_early").Stage11Allowed(self,e)
 if allowed~=nil then return allowed end
 if self.failed or self.recovering or self.hungry or self.feeding then return false end
 local late=require("shadowself/control/arena_stage11_finish").Allowed(self,e)
 if late~=nil then
  if self.finish or self.route=="default" then return late end
  local body=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
  return late and self.prepared and self.buffs:Ready() and headarmor(self.hat)
   and self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)==self.hat
   and body and body.prefab=="armorskeleton"
 end
 if self.failed or self.recovering or self.hungry or self.feeding or not self.prepared or not self.buffs:Ready() or not e or not headarmor(self.hat) or self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)~=self.hat then return false end
 if self.route=="default" then
  return self:Cleared() and chew(self.head) and live(e) and not e:HasTag("notarget") and e==self.target and e.prefab=="worm_boss_dirt"
   and e:GetPosition():DistSq(self.head:GetPosition())<4^2
 end
 if not self.route then return false end
 if not self:Cleared() then return e.prefab==routes[self.route].marker and live(e)
  and require("shadowself/control/arena_stage11_finish").FishSafe(self,self.player:GetPosition()) end
 return e.prefab==routes[self.route].boss and live(e)
end
function S:Tick(entities)
 if self.failed then return "failed",self.failed end
 self.feeding=nil
 self.context.enemies=self.arena.enemies or {};self.context.hazards=self.arena.fire_zones or {}
 self.buffs:Check()
 self:Observe(entities)
 if self.route~="lunar" and self.route~="shadow" and require("shadowself/control/arena_scrappig").Dodge(self,entities) then return "hold" end
 if require("shadowself/control/arena_stage11_finish").WormDanger(self,entities) then return "hold" end
 -- 地裂是钻出吞食的实际预警；保留原蠕虫流程中高于补给/攻击的撤离动作。
 for _,e in ipairs(entities or {}) do if live(e) and e.prefab=="worm_boss_dirt_ground_fx" then
  local p=self.player:GetPosition();local q=e:GetPosition();local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
  if d<4 then
   if self.buffs.pending then self.buffs.pending.interrupted=true;self.buffs:Tick() end
   if self.arena.healing and self.arena.healing.pending then self.arena.healing:Interrupt(self.context) end
   self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil;self.arena.encounters.worm_target=nil
   if d<.01 then dx,dz,d=1,0,1 end
   self.arena.encounters:Move(Nav.Select(self.context,Vector3(q.x+dx/d*4.5,0,q.z+dz/d*4.5)),"普通线 · 提前离开地裂吞食范围")
   return "hold"
  end
 end end
 local requested=require("shadowself/control/arena_doc_early").Stage11(self,entities)
 if requested then return requested end
 if require("shadowself/control/arena_prepare").Head(self) then return "hold" end
 -- 先完成已经发出的进食确认，补给替换和增益刷新均不能抢占。
 if self.buffs.pending then
  local h=self.arena.healing
  local safe=not h or h:Safe(self.context,self.player:GetPosition(),.3)
  if not safe then self.buffs.pending.interrupted=true end
  self.buffs:Tick()
  if not safe then self:Patrol("第十一关 · 进食受威胁，先回避并核对迟到确认") end
  return "hold"
 end
 if self.route=="default" then
  if require("shadowself/control/arena_stage11_hats").Tick(self) then return "hold" end
  if self:Recovery() or self:Hunger() then return self.failed and "failed" or "hold",self.failed end
  self.food.since=nil
  return require("shadowself/control/arena_stage11_finish").Worm(self,entities)
 end
 if self.finish then return require("shadowself/control/arena_stage11_finish").Pig(self,entities) end
 if self:Recovery() or self:Hunger() or self:Prepare() then
  if self.failed then return "failed",self.failed end
  return "hold"
 end
 if require("shadowself/control/arena_stage11_hats").Tick(self) then return "hold" end
 if not self.route then return self:Patrol("第十一关 · 等待实际鱼人/地热螨确认路线") end
 local late=require("shadowself/control/arena_stage11_finish").Pig(self,entities)
 if late then self.food.since=nil;return late end
 local target,near;local p=self.player:GetPosition()
 if self.route=="default" then
  if self:Cleared() and chew(self.head) then
   for _,e in ipairs(self.dirts) do if not e:HasTag("notarget") and e:GetPosition():DistSq(self.head:GetPosition())<4^2 then
    local d=p:DistSq(e:GetPosition());if not near or d<near then target,near=e,d end
   end end
  end
  if not target then self.arena.encounters.worm_target=nil;return self:Patrol(self:Cleared() and "普通线 · 蠕虫移动/非进食，继续巡游" or "普通线 · 外圈巡游，等待四只地热螨全部死亡") end
  self.arena.encounters.worm_target=target;self.phase="worm_eat"
 else
  if self:Cleared() then target=self.boss;self.phase="boss"
  else
   self.phase="fish"
   local finish=require("shadowself/control/arena_stage11_finish")
   if not finish.FishSafe(self,p) then
    self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil
    local b=self.boss:GetPosition();local dx,dz=p.x-b.x,p.z-b.z;local d=math.sqrt(dx*dx+dz*dz)
    if d<.01 then dx,dz,d=1,0,1 end
    local q=Nav.Select(self.context,Vector3(b.x+dx/d*7.5,0,b.z+dz/d*7.5))
    self.arena.encounters:Move(q,"鱼人存活 · 先与拾荒疯猪拉开七码");return "hold"
   end
   for e,confirmed in pairs(self.seen) do if not confirmed and live(e) then
    if finish.FishSafe(self,e:GetPosition()) then
     local d=p:DistSq(e:GetPosition());if not near or d<near then target,near=e,d end
    end
   end end
  end
  if not target then return self:Patrol(routes[self.route].label.." · 等待目标/死亡确认") end
 end
 self.food.since=nil
 self.target=target;self.arena.bridge.priority_target=target
 self.arena:Say(routes[self.route].label..(self.phase=="fish" and " · 优先鱼人，疯猪仅躲避" or self.phase=="boss" and " · 鱼人清完，击杀疯猪" or " · 进食窗口输出，移动立即停手"))
 return "fight"
end
return S
