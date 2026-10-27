local A=require("shadowself/control/actions")
local R=require("shadowself/control/arena_late_runtime")
local Nav=require("shadowself/control/navigation")
local fixed={shadowthrall_wings=true,shadowthrall_hands=true,shadowthrall_horns=true,shadowthrall_mouth=true,ruinsnightmare=true}
local options={bunnyman=true,rocky=true,spider=true,spider_warrior=true,spider_dropper=true}
local danger={shadowthrall_wings=true,shadowthrall_hands=true,shadowthrall_horns=true,shadowthrall_mouth=true,rocky=true,ruinsnightmare=true}
local S=Class(function(self,arena)
 self.arena=arena;self.player=arena.player;self.seen={};self.phase="hat"
 self.context={player=self.player,enemies={},observed={},hazards={},plan={arena=true,arena_wave=function() return 12 end,arena_center=function() return arena.encounters:FindCenter() end}}
 self.context.actions={SafePoint=function(_,q)
  if not TheWorld.Map:IsPassableAtPoint(q.x,0,q.z) or TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) then return false end
  for _,zone in ipairs(self.context.hazards) do if q:DistSq(zone.pos)<zone.radius^2 then return false end end
  return true
 end}
end)
function S:Observe(entities)
 for _,e in ipairs(entities) do if fixed[e.prefab] or options[e.prefab] then
  self.seen[e]=self.seen[e] or R.Dead(e)
 end end
 for e,dead in pairs(self.seen) do if not dead and R.Dead(e) then self.seen[e]=true end end
end
function S:Manifest()
 local found={};local count=0
 for e in pairs(self.seen) do found[e.prefab]=true;if options[e.prefab] then count=count+1 end end
 for name in pairs(fixed) do if not found[name] then return false end end
 return count>=2
end
function S:Group(names)
 local target
 for e,dead in pairs(self.seen) do if names[e.prefab] and not dead then
  -- 离开扫描或暂时不可点击仍占用当前阶段，绝不按死亡推进。
  if not R.Live(e) then return nil,false end
  if not target or self.player:GetPosition():DistSq(e:GetPosition())<self.player:GetPosition():DistSq(target:GetPosition()) then target=e end
 end end
 return target,target==nil
end
function S:Safe(q,target,rockonly)
 if not TheWorld.Map:IsPassableAtPoint(q.x,0,q.z) or TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) then return false end
 for e,dead in pairs(self.seen) do if not dead and R.Live(e) and e~=target and danger[e.prefab] then
  local radius=e.prefab=="rocky" and rockonly and 10 or 8
  if q:DistSq(e:GetPosition())<radius^2 then return false end
 end end
 return Nav.Safe(self.context,q,target)
end
function S:Path(q,target,rockonly)
 local p=self.player:GetPosition();local n=math.max(1,math.ceil(math.sqrt(p:DistSq(q))/.5))
 for i=1,n do
  local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
  if not TheWorld.Map:IsPassableAtPoint(v.x,0,v.z) or TheWorld.Map:IsOceanAtPoint(v.x,0,v.z) then return false end
  for e,dead in pairs(self.seen) do if not dead and R.Live(e) and e~=target and danger[e.prefab] then
   local radius=e.prefab=="rocky" and rockonly and 10 or 8
   local before=math.max(0,radius-math.sqrt(p:DistSq(e:GetPosition())))
   if math.max(0,radius-math.sqrt(v:DistSq(e:GetPosition())))>before+.01 then return false end
  end end
 end
 return true
end
function S:Move(target,rockonly)
 self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil
 local p=self.player:GetPosition();local best,score;local c=self.context
 for _,distance in ipairs({2,4,6,10}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*distance,0,p.z+math.sin(a)*distance)
  if self:Safe(q,target,rockonly) and self:Path(q,target,rockonly) then
   local value=target and q:DistSq(target:GetPosition()) or p:DistSq(q)*-.1
   if not score or value<score then best,score=q,value end
  end
 end end
 if best then self.arena.encounters:Move(best,"暗影裂隙 · 避开其余目标，接近当前目标")
 else
  -- 同时夹在多个8码圈内时，逐个不加深会互相矛盾；使用已有联合风险出口。
  local hazards={};for _,zone in ipairs(c.hazards or {}) do hazards[#hazards+1]=zone end
  for e,dead in pairs(self.seen) do if not dead and R.Live(e) and e~=target and danger[e.prefab] then
   hazards[#hazards+1]={pos=e:GetPosition(),radius=e.prefab=="rocky" and rockonly and 10 or 8,source=e}
  end end
  local route=setmetatable({hazards=hazards},{__index=c})
  local goal=target and target:GetPosition() or p
  local exit=Nav.Escape(route,goal,target)
  if exit then self.arena.encounters:Move(exit,"暗影裂隙 · 间距受夹击，先降低联合危险再恢复攻击")
  else self.arena:Say("暗影裂隙 · 联合出口被地形阻挡，重查脱困路线") end
 end
 return "hold"
end
function S:Allowed(e)
 if self.failed or self.bait or not self.target or e~=self.target or not R.Live(e) or e:HasTag("notarget") then return false end
 if e.prefab=="shadowthrall_mouth" and e:HasTag("stealth") then return false end
 local inv=self.player.replica.inventory;local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)
 local hat=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 if not hand or hand.prefab~=self.weapon_name or not hat or hat.prefab~="lunarplanthat" then return false end
 if self.phase=="rocky" then local body=inv:GetEquippedItem(EQUIPSLOTS.BODY);if not body or body.prefab~="armorskeleton" then return false end end
 return self:Safe(self.player:GetPosition(),e,self.phase=="mouth")
end
function S:Attack(target,weapon,phase)
 R.Phase(self,phase);self.weapon_name=weapon
 if not R.Live(target) or target:HasTag("notarget") or target.prefab=="shadowthrall_mouth" and target:HasTag("stealth") then return self:Move(nil,phase=="mouth") end
 local combat=self.player.replica.combat
 local item=R.Item(self.player,weapon)
 if not item then if not R.Weapon(self,weapon) then return "hold" end end
 local range=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2
 local ii=item and item.replica and item.replica.inventoryitem
 if combat and combat.GetWeaponAttackRange and ii and ii.AttackRange then
  range=range-combat:GetWeaponAttackRange()+ii:AttackRange()
 end
 range=range+target:GetPhysicsRadius(0)-.15
 if not self:Safe(self.player:GetPosition(),target,phase=="mouth") or self.player:GetPosition():DistSq(target:GetPosition())>range^2 then return self:Move(target,phase=="mouth") end
 if not R.Weapon(self,weapon) then return "hold" end
 self.target=target;self.arena.bridge.priority_target=target;return "fight"
end
function S:Tick(entities)
 if self.failed then return "failed",self.failed end
 self.context.enemies=self.arena.enemies or {};self.context.hazards=self.arena.fire_zones or {};self:Observe(entities)
 if not R.Equip(self,"lunarplanthat",EQUIPSLOTS.HEAD) then return "hold" end
 if not self:Manifest() then return self:Move(nil) end
 local target,done=self:Group({bunnyman=true,spider=true,spider_warrior=true,spider_dropper=true})
 if not done then return target and self:Attack(target,"nightsword","rabbit_spiders") or self:Move(nil) end
 for _,name in ipairs({"shadowthrall_wings","shadowthrall_hands","shadowthrall_horns"}) do
  target,done=self:Group({[name]=true})
  if not done then return target and self:Attack(target,"sword_lunarplant",name) or self:Move(nil) end
 end
 target,done=self:Group({ruinsnightmare=true})
 if not done then return target and self:Attack(target,"sword_lunarplant","extra_nightmare") or self:Move(nil) end
 local mouth,cleared=self:Group({shadowthrall_mouth=true})
 if not cleared then
  if not mouth then return self:Move(nil,true) end
  if mouth:HasTag("stealth") then
   self.target=nil;self.arena:StopCombat()
   if self.bait_used then self.bait=nil;return self:Move(nil,true) end
   if not self:Safe(self.player:GetPosition(),mouth,true) then self.bait=nil;return self:Move(nil,true) end
   if not R.Equip(self,"armor_lunarplant",EQUIPSLOTS.BODY) then return "hold" end
   R.Phase(self,"mouth_bait");self.bait=true
   if not self.bait_stopped then A.Stop(self.player);self.bait_stopped=true end
   local a=mouth.AnimState
   if a and a:IsCurrentAnimation("stalk_bite") then self.bait_attack=true end
   if self.bait_attack and a and not a:IsCurrentAnimation("stalk_bite") then self.bait_used=true;self.bait=nil end
   self.arena:Say("狞笑 · 仅本次诱导原地等待，亮茄甲反伤后确认stealth解除")
   return "hold"
  end
  self.bait=nil;self.bait_used=true
  return self:Attack(mouth,"sword_lunarplant","mouth")
 end
 self.bait=nil
 local body=R.Item(self.player,"armor_lunarplant")
 if body then
  self.arena:StopCombat();R.Phase(self,"drop_lunar_armor")
  if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_drop or 0) then self.player.replica.inventory:DropItemFromInvTile(body,false);self.arena.ignored[body.GUID]=math.huge;self.next_drop=GetTime()+.6 end
  return "hold"
 end
 if not R.Equip(self,"armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
 target,done=self:Group({rocky=true})
 if not done then return target and self:Attack(target,"sword_lunarplant","rocky") or self:Move(nil) end
 self.arena:StopCombat();self.target=nil;R.Phase(self,"confirmed_clear");return "hold"
end
function S:Stop() self.bait=nil;R.Stop(self) end
return S
