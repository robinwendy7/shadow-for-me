-- 文档指定的后期关卡顺序；仅由现有Arena tick调用，不创建控制线程。
local A=require("shadowself/control/actions")
local R=require("shadowself/control/arena_late_runtime")
local I=require("shadowself/control/arena_inventory")
local Food=require("shadowself/control/arena_food")
local Status=require("shadowself/control/status")
local Tools=require("shadowself/control/arena_tools")
local Nav=require("shadowself/control/navigation")
local Plant=require("shadowself/control/plant")
local S=Class(function(self,arena)
 self.arena=arena;self.player=arena.player;self.seen={};self.phase="prepare";self.revision=0
 self.context={player=self.player,enemies={},hazards={},observed={},plan={arena=true,arena_wave=function() return arena.wave end},
  actions={SafePoint=function(_,q) return TheWorld.Map:IsPassableAtPoint(q.x,0,q.z) and not TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) end}}
end)
local families={default13={nightmarebeak=true,crawlingnightmare=true,shadow_bishop=true,shadow_knight=true,shadow_rook=true},lunar12={mutatedbearger=true,mutatedwarg=true,mutateddeerclops=true},
 lunar13={alterguardian_phase1_lunarrift=true,alterguardian_phase2_lunarrift=true,alterguardian_phase3_lunarrift=true},
 lunar14={alterguardian_phase1=true,alterguardian_phase2=true,alterguardian_phase3=true},
 shadow13={bat_boss_shadow=true,rocky_boss_shadow=true,worm_boss_shadow=true,worm_boss_shadow_dirt=true,worm_boss_shadow_head=true},
 shadow14={stalker_atrium=true},shadow15={charlie_boss=true,shrouden=true},
 queen={beequeen=true},twins={twinofterror1=true,twinofterror2=true}}
local adds={lunar12={gestalt_guard_evolved=true,mutatedbuzzard_gestalt=true},lunar13={lunarthrall_plant=true},lunar14={lunarfrog=true}}
local expected={lunar12=2,lunar13=3,lunar14=10}
local function isplant(e)
 return e and (e.prefab=="lunarthrall_plant" or e.prefab=="lunarthrall_plant_vine" or e.prefab=="lunarthrall_plant_vine_end"
  or e:HasTag("lunarthrall_plant") or e:HasTag("lunarthrall_plant_end") or Plant.Middle(e)) or false
end
local requirements={queen={armordragonfly=true,ruinshat=true},twins={panflute=true},
 lunar12={voidclothhat=true,armorskeleton=true,voidcloth_boomerang=true,voidcloth_scythe=true},
 lunar13={voidclothhat=true,armorskeleton=true,voidcloth_boomerang=true,voidcloth_scythe=true},
 lunar14={voidclothhat=true,armorskeleton=true,voidcloth_boomerang=true,glasscutter=true,icestaff=true},
 shadow13={lunarplanthat=true,armorskeleton=true,sword_lunarplant=true},
 shadow14={orangestaff=true,purpleamulet=true},shadow15={lunarplanthat=true,armorskeleton=true,sword_lunarplant=true}}
local function kind(arena)
 local route=arena.detected_route or arena.route
 if arena.wave==13 and route=="default" then return "default13" end
 if arena.wave==12 and route=="default" then return "queen" end
 if arena.wave==14 and route=="default" then return "twins" end
 if route=="lunar" and (arena.wave==12 or arena.wave==13 or arena.wave==14) then return "lunar"..arena.wave end
 if route=="shadow" and (arena.wave==13 or arena.wave==14 or arena.wave==15) then return "shadow"..arena.wave end
end
function S:Active() return self.arena.doc_enabled~=false and self.arena.running and kind(self.arena)~=nil or false end
function S:Key() return kind(self.arena) end
function S:Phase(name)
 if self.phase~=name then
  self.revision=self.revision+1;self.phase=name
  print("[ShadowSelf][doc_late] wave="..tostring(self.arena.wave).." phase="..name)
 end
end
function S:GenericOnly(name)
 self.generic_warned=self.generic_warned or {}
 if not self.generic_warned[name] then
  self.generic_warned[name]=true
  print("[ShadowSelf][doc_late] prefab="..name.." support=generic_only reason=no_existing_boss_profile")
 end
end
function S:Item(name)
 local inv=self.player.replica.inventory
 for _,slot in ipairs({EQUIPSLOTS.HANDS,EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
  local e=inv:GetEquippedItem(slot);if e and e.prefab==name and Tools.Usable(e) and I.Condition(e)>0 then return e end
 end
 for _,e in ipairs(A.Items(self.player)) do if e.prefab==name and Tools.Usable(e) and I.Condition(e)>0 then return e end end
end
function S:Required(name)
 local key=self:Key();local req=requirements[key]
 if name==self.needed_armor or self.freeze_needed and name=="icestaff" then return true end
 return req and not (name=="shroomcake" and self.cake_done) and (req[name] or key=="lunar12" and name=="firestaff" and self.deerclops) or false
end
function S:RequiredNames()
 local out={}
 if self.needed_armor then out[#out+1]=self.needed_armor end
 if self.freeze_needed then out[#out+1]="icestaff" end
 for name in pairs(requirements[self:Key()] or {}) do
  if name~="shroomcake" or not self.cake_done then out[#out+1]=name end
 end
 if self:Key()=="lunar12" and self.deerclops then out[#out+1]="firestaff" end
 table.sort(out);return out
end
function S:Want(item)
 if not self:Required(item.prefab) or not Tools.Usable(item) then return false end
 if self:Key()=="queen" and item.prefab=="ruinshat" then return true end -- 本关拾起所有可用铥头
 if item.prefab=="shroomcake" and self.cake_done then return false end
 return not self:Item(item.prefab)
end
function S:Prefabs()
 local key=self:Key();local names={}
 for name in pairs(families[key] or {}) do names[name]=true end
 for name in pairs(adds[key] or {}) do names[name]=true end
 if key=="shadow13" then
  names.worm_boss_shadow_segment=true;names.worm_boss_shadow_tail=true;names.worm_boss_dirt_ground_fx=true
 elseif key=="twins" then names.eyeofterror_mini=true;names.eyeofterror_mini_grounded=true
 elseif key=="lunar13" then names.lunarthrall_plant_vine=true;names.lunarthrall_plant_vine_end=true end
 return names
end
function S:Drop(item)
 return self:Key()=="shadow15" and item.prefab=="queen_torch"
  or self:Key()=="lunar12" and self.cake_done and item.prefab=="shroomcake"
  or (self.twins_drop_pending or self.twins_finished) and self.instance==self.arena.instance and self.generation==self.arena.generation and item.prefab=="panflute" or false
end
function S:Owner()
 return self.enabled and self.arena.doc_enabled~=false and self.arena.running and (not self.arena.doc_late or self.arena.doc_late==self)
  and self.wave==self.arena.wave and self.instance==self.arena.instance and self.generation==self.arena.generation
end
-- Capture the request's phase as well as the arena identity. A later phase or
-- Stop/restart in the same arena must never resurrect a queued preview callback.
function S:Guard(check)
 local revision,wave,instance,generation,key=self.revision,self.wave,self.instance,self.generation,self:Key()
 return function()
  return self:Owner() and revision==self.revision and wave==self.wave and instance==self.instance
   and generation==self.generation and key==self:Key() and (not check or check()) or false
 end
end
function S:Ground(name)
 for _,item in ipairs(self.arena.items or {}) do
  local ii=item.replica and item.replica.inventoryitem
  if item.prefab==name and Tools.Usable(item) and not item:HasTag("INLIMBO") and ii and not ii:IsHeld() then return item end
 end
end
function S:SafePickup(item)
 if not self:Owner() or not item or not Tools.Usable(item) or item:HasTag("INLIMBO") then return false end
 local ii=item.replica and item.replica.inventoryitem
 if not ii or ii:IsHeld() then return false end
 local listed=false;for _,e in ipairs(self.arena.items or {}) do if e==item then listed=true;break end end
 if not listed then return false end
 local c=self.context;local coordinator=self.arena.bridge.coordinator
 c.enemies={};c.hazards={};c.observed=coordinator and coordinator.observed or {}
 for _,e in ipairs(self.arena.enemies or {}) do
  if R.Live(e) and not Status.Sleeping(e) and not (Status.Frozen and Status.Frozen(e)) then c.enemies[#c.enemies+1]=e end
 end
 for _,zone in ipairs(self.arena.fire_zones or {}) do c.hazards[#c.hazards+1]=zone end
 for _,zone in ipairs(coordinator and coordinator.mechanisms and coordinator.mechanisms.zones or {}) do c.hazards[#c.hazards+1]=zone end
 local point=item:GetPosition();local p=self.player:GetPosition();local pathfinder=TheWorld and TheWorld.Pathfinder
 if pathfinder and not pathfinder:IsClear(p.x,0,p.z,point.x,0,point.z,{ignorecreep=true,ignorewalls=false}) then return false end
 if not Nav.Safe(c,point) then return false end
 return not self.arena.healing or self.arena.healing:Path(c,point)
end
function S:Pickup(name,all)
 for _,item in ipairs(self.arena.items or {}) do if item.prefab==name and Tools.Usable(item) then
  if (all or not self:Item(name)) and self:SafePickup(item) then
   self.arena:StopCombat()
   return self.arena:Loot({item},false,self:Guard(function() return (all or not self:Item(name)) and self:SafePickup(item) end))
  end
 end end
 return false
end
function S:Equip(name,slot)
 local item=self:Item(name)
 if not item then
  if self:Pickup(name) then self.arena:Say("后期流程 · 等待 "..name)
  else self:Wait("后期流程 · 先避开威胁，再安全补捡 "..name) end
  return false
 end
 if self.player.replica.inventory:GetEquippedItem(slot)==item then
  self.equipped=self.equipped or {};self.equipped[slot]=item;return true,item
 end
 self.arena:StopCombat()
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_equip or 0) then
  if A.Self(self.player,item,ACTIONS.EQUIP,self:Guard(function() return self:Item(name)==item end)) then self.next_equip=GetTime()+.4 end
 end
 return false,item
end
function S:Protect(c)
 if not self:Active() or not self:Owner() or not c or not c.gear then return end
 c.gear.protected_slots=c.gear.protected_slots or {};c.gear._doclate_owner=self
 local inv=self.player.replica.inventory
 for slot,item in pairs(self.equipped or {}) do
  if inv:GetEquippedItem(slot)==item and Tools.Usable(item) then c.gear.protected_slots[slot]=true end
 end
 if self.weapon_name then
  local item=self:Item(self.weapon_name)
  if item and inv:GetEquippedItem(EQUIPSLOTS.HANDS)==item then c.gear.forced_weapon=item;self.weapon=item end
 end
end
function S:DropItem(name)
 for _,e in ipairs(A.Items(self.player)) do if e.prefab==name then
  self.arena:StopCombat()
  if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_drop or 0) then
   self.player.replica.inventory:DropItemFromInvTile(e,false);self.next_drop=GetTime()+.4
   self.arena.ignored=self.arena.ignored or {};if e.GUID then self.arena.ignored[e.GUID]=math.huge end
  end
  return true
 end end
 return false
end
function S:Observe(entities)
 for _,e in ipairs(entities or {}) do
  local key=self:Key()
  if families[key] and families[key][e.prefab] or adds[key] and adds[key][e.prefab] then self.seen[e]=self.seen[e] or R.Dead(e) end
  if e.prefab=="mutateddeerclops" and R.Live(e) then self.deerclops=true end
 end
 for e,dead in pairs(self.seen) do if not dead and R.Dead(e) then self.seen[e]=true end end
end
function S:Nearest(names)
 local target,near
 for e,dead in pairs(self.seen) do if not dead and names[e.prefab] and R.Live(e) and not e:HasTag("NOCLICK") and not e:HasTag("notarget") then
  local d=self.player:GetPosition():DistSq(e:GetPosition());if not near or d<near then target,near=e,d end
 end end
 return target
end
function S:GroupDone(names,count)
 local dead,live=0,0
 for e,confirmed in pairs(self.seen) do if names[e.prefab] then if confirmed then dead=dead+1 elseif R.Live(e) then live=live+1 end end end
 if live>0 then return false end
 if dead>=count then return true end
 -- Only the authoritative server count may confirm removed corpses; an empty scan cannot.
 local known=0;local key=self:Key();local roots={}
 for e,confirmed in pairs(self.seen) do
  if not confirmed and R.Live(e) and families[key] and families[key][e.prefab] and not names[e.prefab] then
   local root=e.prefab:find("worm_boss_shadow",1,true)==1 and "worm_boss_shadow" or e.prefab
   if not roots[root] then roots[root]=true;known=known+1 end
  end
 end
 return known>0 and self.arena.remaining_objectives==known
end
function S:Wait(label,target)
 self.target=nil;self.arena:StopCombat();self.arena.bridge.priority_target=nil
 local p=self.player:GetPosition();local nearest,dist
 for _,e in ipairs(self.context.enemies or {}) do if R.Live(e) then
  local d=p:DistSq(e:GetPosition());if not dist or d<dist then nearest,dist=e,d end
 end end
 local q
 if nearest and dist<8^2 then
  local ep=nearest:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
  if d<.01 then dx,dz,d=1,0,1 end
  q=Nav.Select(self.context,Vector3(ep.x+dx/d*8,0,ep.z+dz/d*8),nearest)
 elseif target then q=Nav.Select(self.context,target:GetPosition(),target) end
 if q and p:DistSq(q)>.2^2 then self.arena.encounters:Move(q,label) else self.arena:Say(label) end
 return "hold"
end
function S:Select(target,weapon)
 self.weapon_name=weapon
 if not target then return self:Wait("后期流程 · 等待当前目标真实死亡确认") end
 if weapon and not self:Equip(weapon,EQUIPSLOTS.HANDS) then return "hold" end
 self.target=target;self.arena.bridge.priority_target=target
 self:Protect(self.arena.bridge.coordinator)
 return "fight",target
end
function S:Defensive(e)
 local key=self:Key();return e and (families[key] and families[key][e.prefab] or adds[key] and adds[key][e.prefab] or key=="lunar13" and isplant(e)) or false
end
function S:Allowed(e)
 if not self:Active() then return true end
 if not self:Owner() then return false end
 if not e or self.target~=e or not R.Live(e) or e:HasTag("notarget") or e:HasTag("NOCLICK") or self.queen_recovery or self.flute_pending then return false end
 if self:Key()=="lunar13" and self.phase=="lunar_adds" and e.prefab~="lunarthrall_plant" then return false end
 if self:Key()=="lunar12" then
  for _,boss in ipairs(self.arena.enemies or {}) do if families.lunar12[boss.prefab] and R.Live(boss) and self.player:GetPosition():DistSq(boss:GetPosition())<10^2 then return false end end
 end
 if self:Key()=="twins" and not self.flute_fallback and not self.controlled then return false end
 if self:Key()=="shadow13" and e.prefab=="worm_boss_shadow_dirt" then
  local chew,head=self:WormChewing();if not chew or e:GetPosition():DistSq(head:GetPosition())>=4^2 then return false end
 end
 if self.weapon_name then local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS);if not hand or hand.prefab~=self.weapon_name then return false end end
 return true
end
S.AttackAllowed=S.Allowed
function S:Hold(e)
 if not self:Active() then return false end
 return self.target and self:Allowed(self.target) and (self:Key()=="queen" or self:Key()=="twins" and not self.flute_fallback or self:Key()=="default13" and self.phase~="default_rook" or self:Key()=="lunar13" and self.phase=="lunar_adds" or self:Key()=="lunar14" and self.phase=="lunar_frog_shot") or false
end
function S:Count(name)
 local count=0
 for _,e in ipairs(A.Items(self.player)) do if e.prefab==name then local st=e.replica and e.replica.stackable;count=count+(st and st:StackSize() or 1) end end
 return count
end
function S:EatOne(name)
 local item=self:Item(name);local pending=self.eating
 if pending then
  if not pending.guard() then self.eating=nil;return false end
  local count=self:Count(pending.name)
  if count<pending.count or not pending.item:IsValid() then self.eating=nil;self.next_eat=GetTime()+.35;return true end
  if GetTime()>pending.deadline then self.eating=nil;self.next_eat=GetTime()+.5 end
  return false
 end
 if not item then
  if not self:Pickup(name) then self:Wait("后期流程 · 先避开威胁，再安全补捡 "..name) end
  return false
 end
 self.arena:StopCombat()
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_eat or 0) then
  local count=self:Count(name)
  local guard=self:Guard()
  local send_guard=function() return guard() and item:IsValid() and self:Count(name)>=count end
  if A.Self(self.player,item,ACTIONS.EAT,send_guard) then self.eating={item=item,name=name,count=count,deadline=GetTime()+3.5,guard=guard} end
 end
 return false
end
function S:Queen()
 local helmet=self:Ground("ruinshat")
 if helmet and self:SafePickup(helmet) then self:Phase("queen_gear");if self:Pickup("ruinshat",true) then return "hold" end end
 local inv=self.player.replica.inventory
 if not inv:GetEquippedItem(EQUIPSLOTS.BODY) or inv:GetEquippedItem(EQUIPSLOTS.BODY).prefab~="armordragonfly"
  or not inv:GetEquippedItem(EQUIPSLOTS.HEAD) or inv:GetEquippedItem(EQUIPSLOTS.HEAD).prefab~="ruinshat" then self:Phase("queen_gear") end
 if not self:Equip("armordragonfly",EQUIPSLOTS.BODY) or not self:Equip("ruinshat",EQUIPSLOTS.HEAD) then return "hold" end
 if self.eating then self:EatOne(self.eating.name) end
 local h=self.player.replica.health;local hp=h and h.GetCurrent and h:GetCurrent()
 if hp and hp<40 then self.queen_recovery=true end
 if self.queen_recovery then
  self:Phase("queen_recover")
  if hp and hp>100 and not self.eating then self.queen_recovery=nil else
   self.arena:StopCombat();self.target=nil
   local best,score
   for _,item in ipairs(A.Items(self.player)) do local value=Food.Health(item,self.player)
    if value>0 and not Food.BuffOnly(item) and require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) and (not score or value>score) then best,score=item,value end
   end
   if best then self:EatOne(best.prefab)
   else
    for _,item in ipairs(self.arena.items or {}) do if Food.Health(item,self.player)>0 and not Food.BuffOnly(item) and require("shadowself/control/arena_doc_inventory").CanConsume(self.player,item) then self:Pickup(item.prefab);break end end
   end
   return "hold"
  end
 end
 self:Phase("queen_tank");return self:Select(self:Nearest(families.queen))
end
function S:Twins(entities)
 local any,live={},false
 for e,dead in pairs(self.seen) do if families.twins[e.prefab] then any[e.prefab]=true;if not dead and R.Live(e) then live=true end end end
 if self:GroupDone(families.twins,2) or any.twinofterror1 and any.twinofterror2 and not live and self.arena.remaining_objectives==0 then
  self.twins_finished=true;self.twins_drop_pending=true;self:Phase("twins_complete");self.target=nil;self.arena:StopCombat()
  if not self:DropItem("panflute") then self.twins_drop_pending=nil end
  return "hold"
 end
 self:Phase("twins_control")
 local targets={twinofterror1=true};local laser=self:Nearest(targets)
 local laser_done=self:GroupDone(targets,1)
 local target=laser_done and self:Nearest({twinofterror2=true}) or laser
 if not target then return self:Wait("双子 · 等待激光眼真实死亡确认") end
 local flute=self:Item("panflute")
 if flute then self.flute_seen=true end
 if not flute then
  if self:Pickup("panflute") then return "hold" end
  if self:Ground("panflute") then return self:Wait("双子 · 排箫尚可补捡，等待安全拾取窗口") end
  local spent=false;for _,e in ipairs(A.Items(self.player)) do if e.prefab=="panflute" and not Tools.Usable(e) then spent=true end end
  if self.flute_seen or spent then self.flute_fallback=true;self.controlled=nil;return self:Select(target) end
  return self:Wait("双子 · 开局等待地上排箫，尚未开始无控制近战")
 end
 self.flute_fallback=nil
 local roster={};local seen={}
 for _,list in ipairs({entities or {},self.arena.enemies or {}}) do for _,e in ipairs(list) do
  local combat=e.replica and e.replica.combat
  if R.Live(e) and not e:HasTag("player") and (families.twins[e.prefab] or combat and not e:HasTag("structure") and not e:HasTag("wall") and not e:HasTag("FX")) and not seen[e] then seen[e]=true;roster[#roster+1]=e end
 end end
 local controlled=#roster>=1
 for _,e in ipairs(roster) do if not Status.Sleeping(e) then controlled=false end end
 if self.flute_pending then
  if not self.flute_pending.guard() then self.flute_pending=nil
  elseif controlled then self.flute_pending=nil;self.controlled=true;self.had_sleep=true;self.woke_at=nil
  elseif GetTime()>=self.flute_pending.deadline then self.flute_pending=nil;self.next_flute=GetTime()+.4
  else self.arena:StopCombat();self.target=nil;return "hold" end
 end
 if controlled then self.controlled=true;self.had_sleep=true;self.woke_at=nil;return self:Select(target) end
 self.controlled=nil;self.target=nil;self.arena:StopCombat()
 if self.had_sleep then
  self.woke_at=self.woke_at or GetTime()
  if GetTime()-self.woke_at<2 then return self:Wait("双子 · 生物苏醒满2秒后再次催眠",target) end
 end
 local range=(TUNING.PANFLUTE_SLEEPRANGE or 15)-1;local covered=true
 for _,e in ipairs(roster) do if self.player:GetPosition():DistSq(e:GetPosition())>range^2 then covered=false;break end end
 if not covered then
  local point=self.arena.opening and self.arena.opening.Coverage and self.arena.opening:Coverage(roster,range)
  if point then self.arena.encounters:Move(point,"双子 · 排箫覆盖所有生物后再吹奏");return "hold" end
  return self:Wait("双子 · 寻找全体排箫覆盖点",target)
 end
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_flute or 0) then
  local guard=self:Guard(function() return self:Item("panflute")==flute end)
  if A.Self(self.player,flute,ACTIONS.PLAY,guard) then self.flute_pending={deadline=GetTime()+3.5,guard=guard};self.next_flute=GetTime()+.5 end
 end
 return "hold"
end
function S:WormChewing()
 for head,dead in pairs(self.seen) do if not dead and head.prefab=="worm_boss_shadow_head" and R.Live(head) then
  for _,name in ipairs({"chew_small","chew_big","chew_shock_loop","chew_shock_pst"}) do
   if head.AnimState and head.AnimState:IsCurrentAnimation(name) then return true,head end
  end
 end end
 return false
end
function S:ShadowDanger(entities)
 local zones={}
 for _,e in ipairs(entities or {}) do if R.Live(e) then
  local name=e.prefab;local a=e.AnimState
  if name=="worm_boss_shadow_segment" or name=="worm_boss_shadow_tail" then
   zones[#zones+1]={pos=e:GetPosition(),radius=math.max(2,e:GetPhysicsRadius(0))+self.player:GetPhysicsRadius(0)+.5,source=e}
  elseif name=="worm_boss_dirt_ground_fx" or name=="worm_boss_shadow_head" and a
   and (a:IsCurrentAnimation("emerge_eat") or a:IsCurrentAnimation("emerge_full") or a:IsCurrentAnimation("emerge_taunt")) then
   zones[#zones+1]={pos=e:GetPosition(),radius=4.5,source=e}
  end
 end end
 local q=require("shadowself/control/arena_fire").Escape(self.player,zones)
 if not q then return false end
 self.target=nil;self.arena:StopCombat();self.arena.bridge.priority_target=nil
 self.arena.encounters:Move(q,"暗影蠕虫 · 提前躲开钻出和体节，再继续当前目标")
 return true
end
function S:Dodge(c,e,base)
 if self:Hold(e) then return false end
 return base
end
function S:Shadow13()
 local inv=self.player.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 if head and head.prefab=="bat_boss_shadow" then
  self.arena:StopCombat();self.target=nil
  if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_drop or 0) then inv:DropItemFromInvTile(head,false);self.next_drop=GetTime()+.35 end
  return "hold"
 end
 if not self:Equip("lunarplanthat",EQUIPSLOTS.HEAD) or not self:Equip("armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
 local bat=self:Nearest({bat_boss_shadow=true})
 if not self:GroupDone({bat_boss_shadow=true},1) then
  self:Phase("shadow_bat");return self:Select(bat,"sword_lunarplant")
 end
 local rocky=self:Nearest({rocky_boss_shadow=true})
 if rocky then self:GenericOnly(rocky.prefab);self:Phase("shadow_rocky");return self:Select(rocky,"sword_lunarplant") end
 local chewing,head=self:WormChewing()
 if not chewing then self:Phase("shadow_worm_wait");return self:Wait("暗影蠕虫 · 回避钻出和体节，等待真实咀嚼窗口") end
 local dirt,near
 for e,dead in pairs(self.seen) do if not dead and e.prefab=="worm_boss_shadow_dirt" and R.Live(e) and not e:HasTag("notarget") and not e:HasTag("NOCLICK") and e:GetPosition():DistSq(head:GetPosition())<4^2 then
  local d=self.player:GetPosition():DistSq(e:GetPosition());if not near or d<near then dirt,near=e,d end
 end end
 self:Phase("shadow_worm_chew");return self:Select(dirt,"sword_lunarplant")
end
-- Preserve the existing Brightshade handler's real weak-head/vine target.
-- If only an invulnerable root is visible, it is a strategy anchor for that
-- handler to lure vines; Allowed still forbids striking that root.
function S:PlantTarget()
 return self:Nearest({lunarthrall_plant=true})
end
function S:Head90()
 local ok,item=require("shadowself/control/arena_doc_early").Armor90(self.arena,EQUIPSLOTS.HEAD)
 self.needed_armor=self.arena.doc_armor_needed
 if ok then self.equipped=self.equipped or {};self.equipped[EQUIPSLOTS.HEAD]=item end
 return ok
end
function S:Default13()
 if not self:Head90() then self:Phase("default_gear");return "hold" end
 local ghosts={nightmarebeak=true,crawlingnightmare=true}
 if not self:GroupDone(ghosts,2) then self:Phase("default_ghosts");return self:Select(self:Nearest(ghosts)) end
 if not self:GroupDone({shadow_bishop=true},1) then self:Phase("default_bishop");return self:Select(self:Nearest({shadow_bishop=true})) end
 if not self:GroupDone({shadow_knight=true},1) then self:Phase("default_knight");return self:Select(self:Nearest({shadow_knight=true})) end
 self:Phase("default_rook");return self:Select(self:Nearest({shadow_rook=true}))
end
function S:Distance10()
 local nearest,dist
 for _,e in ipairs(self.arena.enemies or {}) do if families.lunar12[e.prefab] and R.Live(e) then
  local d=self.player:GetPosition():DistSq(e:GetPosition());if not dist or d<dist then nearest,dist=e,d end
 end end
 if nearest and dist<10^2 then
  self.arena:StopCombat();self.target=nil
  local p=self.player:GetPosition();local q=nearest:GetPosition();local d=math.sqrt(dist);local x,z=p.x-q.x,p.z-q.z
  if d<.01 then d,x,z=1,1,0 end
  self.arena.encounters:Move(Nav.Select(self.context,Vector3(q.x+x/d*10.5,0,q.z+z/d*10.5)),"天体12 · 保持距Boss十码")
  return true
 end
 return false
end
function S:FarAdd()
 local target,near;local p=self.player:GetPosition()
 local combat=self.player.replica.combat;local range=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2
 for e,dead in pairs(self.seen) do if not dead and adds.lunar12[e.prefab] and R.Live(e) then
  local q=e:GetPosition();local d=math.sqrt(p:DistSq(q));local length=math.max(0,d-range-.2)
  local point=d>.01 and Vector3(p.x+(q.x-p.x)*length/d,0,p.z+(q.z-p.z)*length/d) or p
  local safe=true
  for _,boss in ipairs(self.arena.enemies or {}) do if families.lunar12[boss.prefab] and R.Live(boss) and point:DistSq(boss:GetPosition())<10^2 then safe=false;break end end
  if safe and (not near or d<near) then target,near=e,d end
 end end
 return target
end
function S:Freeze(target)
 if not target or Status.Frozen(target) then self.freeze_needed=nil;return true end
 self.freeze_needed=true;self:Phase("lunar_freeze")
 if not self:Equip("icestaff",EQUIPSLOTS.HANDS) then return false end
 self.arena:StopCombat();self.target=nil
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_freeze or 0) then
  if A.Attack(self.player,target,self:Guard(function() return R.Live(target) and not Status.Frozen(target) and self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==self:Item("icestaff") end)) then self.next_freeze=GetTime()+.5 end
 end
 return false
end
function S:FrogPatrol(boss)
 self.arena:StopCombat();self.target=nil;self.arena.bridge.priority_target=nil
 local p=self.player:GetPosition();local now=GetTime()
 if self.frog_last and now-self.frog_time<=.5 and p:DistSq(self.frog_last)>.05^2 then self.frog_elapsed=(self.frog_elapsed or 0)+now-self.frog_time end
 self.frog_last=p;self.frog_time=now
 if now<(self.next_frog_move or 0) then return "hold" end
 self.next_frog_move=now+.25
 local center=boss and boss:GetPosition() or self.arena.encounters:FindCenter()
 if not center then return "hold" end
 local x,z=p.x-center.x,p.z-center.z;local d=math.sqrt(x*x+z*z);if d<.01 then x,z,d=1,0,1 end
 self.frog_dir=self.frog_dir or 1
 for i=1,2 do
  local direction=i==1 and self.frog_dir or -self.frog_dir
  local q=Vector3(p.x-z/d*3*direction+x/d*.5,0,p.z+x/d*3*direction+z/d*.5)
  local map=TheWorld.Map;local pf=TheWorld.Pathfinder
  if map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and (not pf or pf:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false})) and require("shadowself/control/arena_center").Point(self.context,q) then
   self.frog_dir=direction;self.arena.encounters:Move(q,"天体14 · 简单巡游两秒，再原生投掷一次");break
  end
 end
 return "hold"
end
function S:Lunar()
 local key=self:Key()
 if not self:Equip("voidclothhat",EQUIPSLOTS.HEAD) or not self:Equip("armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
 if key=="lunar12" then
  if not self:GroupDone(adds[key],expected[key]) then
   local warg=self:Nearest({mutatedwarg=true})
   if warg and not self:Freeze(warg) then return "hold" end
  end
  if self:Distance10() then return "hold" end
 end
 if key=="lunar14" and not self:GroupDone(adds[key],expected[key]) then
  local boss=self:Nearest({alterguardian_phase1=true})
  if boss and not self:Freeze(boss) then self.frog_shot=nil;return "hold" end
  if self.frog_shot then
   if not R.Live(self.frog_shot) or R.Hits(self,self.frog_shot)>=1 then
    self.frog_shot=nil;self.frog_elapsed=0;self.frog_last=nil;self:Phase("lunar_frog_patrol")
    return self:FrogPatrol(boss)
   end
   return self:Select(self.frog_shot,"voidcloth_boomerang")
  end
  if (self.frog_elapsed or 0)<2 then self:Phase("lunar_frog_patrol");return self:FrogPatrol(boss) end
  self.frog_shot=self:Nearest({lunarfrog=true});R.ResetHits(self)
  if not self.frog_shot then return self:FrogPatrol(boss) end
  self:Phase("lunar_frog_shot");return self:Select(self.frog_shot,"voidcloth_boomerang")
 end
 if not self:GroupDone(adds[key],expected[key]) then
  self:Phase("lunar_adds")
  local target
  if key=="lunar13" then target=self:PlantTarget() elseif key=="lunar12" then target=self:FarAdd() else target=self:Nearest(adds[key]) end
  return self:Select(target,"voidcloth_boomerang")
 end
 self:Phase("lunar_boss");return self:Select(self:Nearest(families[key]),key=="lunar14" and "glasscutter" or "voidcloth_scythe")
end
function S:Tick(entities)
 if not self.arena.running or self.arena.doc_enabled==false then self:Stop();return end
 local key=self:Key()
 if self.instance~=self.arena.instance or self.generation~=self.arena.generation then self.twins_finished=nil;self.twins_drop_pending=nil;self.last_key=nil end
 if self.last_key=="twins" and key~="twins" then self.twins_finished=true;self.twins_drop_pending=true;self.last_key=nil end
 if not key then
  self:Stop()
  if self.twins_drop_pending then if self:DropItem("panflute") then return "hold" end;self.twins_drop_pending=nil end
  return
 end
 if self.twins_drop_pending and key~="twins" then
  if self:DropItem("panflute") then return "hold" end;self.twins_drop_pending=nil
 end
 if self.wave~=self.arena.wave or self.instance~=self.arena.instance or self.generation~=self.arena.generation then
  self:Stop();self.seen={};self.phase="prepare";self.equipped={};self.weapon_name=nil;self.target=nil
  self.wave,self.instance,self.generation=self.arena.wave,self.arena.instance,self.arena.generation
  self.cake_done=nil;self.eating=nil;self.queen_recovery=nil;self.flute_pending=nil;self.flute_seen=nil;self.flute_fallback=nil;self.controlled=nil;self.had_sleep=nil;self.woke_at=nil;self.deerclops=nil;self.frog_shot=nil;self.frog_elapsed=nil;self.frog_last=nil;self.next_frog_move=nil;self.next_freeze=nil;self.freeze_needed=nil
 end
 self.enabled=true
 self.last_key=key;self.context.enemies=self.arena.enemies or {};self.context.hazards=self.arena.fire_zones or {};self:Observe(entities)
 if key=="default13" then return self:Default13() end
 if key=="queen" then return self:Queen() end
 if key=="twins" then return self:Twins(entities) end
 if key=="shadow13" then
  local attached=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
  if attached and attached.prefab=="bat_boss_shadow" then return self:Shadow13() end
  if self:ShadowDanger(entities) then return "hold" end;return self:Shadow13()
 end
 if key=="shadow14" then
  for _,name in ipairs({"orangestaff","purpleamulet"}) do if not self:Item(name) then
   if self:Pickup(name) then return "hold" end
   return self:Wait("远古织影者 · 等待必需工具 "..name)
  end end
  return self:Select(self:Nearest(families[key]))
 end
 if key=="shadow15" then
  if self:DropItem("queen_torch") then return "hold" end
  if not self:Equip("lunarplanthat",EQUIPSLOTS.HEAD) or not self:Equip("armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
  local target=self:Nearest(families[key]);if target then self:GenericOnly(target.prefab) end
  return self:Select(target,"sword_lunarplant")
 end
 return self:Lunar()
end
function S:Stop()
 self.enabled=false;self.revision=self.revision+1
 local c=self.arena.bridge.coordinator
 if c and c.gear and c.gear._doclate_owner==self then
  if c.gear.forced_weapon==self.weapon then c.gear.forced_weapon=nil end
  c.gear.protected_slots=nil;c.gear._doclate_owner=nil
 end
 self.target=nil;self.flute_pending=nil;self.eating=nil
end
return S
