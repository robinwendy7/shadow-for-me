-- 文档补给规则由现有Arena tick执行；不另外启动拾取/进食线程。
local A=require("shadowself/control/actions")
local Food=require("shadowself/control/arena_food")
local M={GARLIC="frogfishbowl_spice_garlic"}
function M.Owner(player)
 local arena=player and player._shadowself_arena_move_owner
 return arena and arena.running and arena.doc_enabled and arena or nil
end
function M.Enabled(player) return M.Owner(player)~=nil end
function M.Route(arena) return arena.detected_route or arena.stage11 and arena.stage11.route or arena.route end
function M.NoRecovery(player) local arena=M.Owner(player);return arena and arena.wave==11 and arena.doc_no_recovery11 or false end
function M.CanConsume(player,item)
 local arena=M.Owner(player)
 return not arena or item.prefab~=M.GARLIC or arena.wave==15
end
function M.Observe(arena,snapshot)
 arena.doc_intermission=snapshot.intermission==true
 local key=tostring(arena.instance)..":"..tostring(arena.generation)..":"..tostring(arena.wave)
 if arena.doc_inventory_key~=key then
  arena.doc_inventory_key=key;arena.doc_drop=nil;arena.doc_garlic_pending=nil;arena.doc_no_recovery11=nil
  if arena.wave==15 then arena.doc_garlic_eaten=nil end
 end
 if arena.wave==11 and (snapshot.run_state=="WAVE_ACTIVE" or #(arena.enemies or {})>0) then arena.doc_no_recovery11=true end
end
local function valid(e) return e and e:IsValid() and not e:HasTag("broken") end
local function locked(arena)
 local c=arena.bridge and arena.bridge.coordinator
 local boss=require("shadowself/control/arena_doc_boss")
 return c and boss.Owns(c) and not boss.Preparing(c) or false
end
local function safeidle(arena,duration)
 local c=arena.bridge and arena.bridge.coordinator or require("shadowself/control/arena_prepare").Context(arena)
 return not arena.healing or arena.healing:Safe(c,arena.player:GetPosition(),duration or .4)
end
function M.FoodKeep(bag,player)
 local candidates,keep,tea={},{},nil
 local arena=M.Owner(player)
 for _,item in ipairs(bag) do if valid(item) then
  if item.prefab=="sweettea" then if not tea or Food.Freshness(item)>Food.Freshness(tea) then tea=item end
  elseif Food.Health(item,player)>0 then candidates[#candidates+1]=item end
 end end
 table.sort(candidates,function(a,b)
  local av,bv=Food.Health(a,player),Food.Health(b,player)
  if av~=bv then return av>bv end
  local af,bf=Food.Freshness(a),Food.Freshness(b)
  if af~=bf then return af>bf end
  return (a.GUID or 0)<(b.GUID or 0)
 end)
 if tea then keep[tea]=true end
 for i=1,math.min(2,#candidates) do keep[candidates[i]]=true end
 return keep
end
function M.IsFood(item)
 local recipe=Food.Recipe(item)
 return recipe~=nil or Food.Known(item.prefab) or item:HasTag("edible_MEAT") or item:HasTag("edible_VEGGIE") or item:HasTag("edible_GOODIES")
end
function M.FoodWant(item,bag,player)
 if not M.Enabled(player) or not M.IsFood(item) then return nil end
 if item.prefab=="meatballs" then return false end
 for _,owned in ipairs(bag) do if owned.prefab==item.prefab then
  local stack=owned.replica and owned.replica.stackable
  if stack and not stack:IsFull() and M.FoodKeep(bag,player)[owned] then return true end
 end end
 local combined={item};for _,e in ipairs(bag) do combined[#combined+1]=e end
 return M.FoodKeep(combined,player)[item] or false
end
function M.Required(arena)
 local names={}
 if arena.doc_armor_needed then names[arena.doc_armor_needed]=true end
 if arena.wave==10 then names.armorskeleton=true;names.nightsword=true;names.nightmarefuel=true end
 if arena.wave==11 and M.Route(arena)=="shadow" then names.queen_torch=true;names.staff_lunarplant=arena.stage11 and arena.stage11.finish or nil end
 if arena.wave==15 then names[M.GARLIC]=not arena.doc_garlic_eaten end
 local late=arena.doc_late
 if late and late.Required then
  local candidates=late.RequiredNames and late:RequiredNames() or {}
  for _,n in ipairs(candidates) do names[n]=true end
 end
 local c=arena.bridge and arena.bridge.coordinator
 if c then
  for _,e in ipairs(arena.enemies or {}) do
   local list=require("shadowself/control/arena_doc_boss").Items(c,e)
   for name in pairs(list or {}) do names[name]=true end
  end
 end
 return names
end
function M.PickupProtected(player,item,bag)
 local arena=M.Owner(player);if not arena then return nil end
 if arena.doc_late and arena.doc_late.Want and arena.doc_late:Want(item) then return true end
 for _,owned in ipairs(bag) do if owned.prefab==item.prefab and valid(owned) and require("shadowself/control/arena_inventory").Condition(owned)>0 then
  local stack=owned.replica and owned.replica.stackable
  return stack and not stack:IsFull() or false
 end end
 return valid(item) and require("shadowself/control/arena_inventory").Condition(item)>0
end
function M.TankArmor(arena,item)
 if not arena or not arena.doc_enabled or item.prefab=="armorskeleton" then return false end
 local eq=item.replica and item.replica.equippable
 if not eq or require("shadowself/control/arena_inventory").Protection(item)<.9 then return false end
 local slot=eq:EquipSlot();local route=M.Route(arena)
 if arena.wave==11 and (route=="shadow" or route=="lunar") then
  return slot==EQUIPSLOTS.HEAD or slot==EQUIPSLOTS.BODY and (route=="lunar" or not arena.stage11 or not arena.stage11:Cleared())
 end
 return arena.wave==13 and route=="default" and slot==EQUIPSLOTS.HEAD
end
function M.Protected(player,item)
 local arena=M.Owner(player);if not arena then return false end
 if M.TankArmor(arena,item) then return true end
 if item.prefab==M.GARLIC or Food.BuffOnly(item) or item.prefab=="queen_torch" and M.Route(arena)=="shadow" and arena.wave<15 then return true end
 if M.Required(arena)[item.prefab] then return true end
 local late=arena.doc_late
 if late and late.Want and late:Want(item) then return true end
 if item.prefab=="nightmarefuel" or item.prefab=="cane" then return true end
 return false
end
function M.Drop(arena,item,bag)
 local route=M.Route(arena)
 if arena.wave>=11 and (route=="lunar" or route=="shadow") and (item.prefab=="firestaff" or item.prefab=="icestaff" or item.prefab=="icestaff2" or item.prefab=="icestaff3" or item.prefab=="panflute") then
  -- 后续明确要求排箫的双子场景由DocLate.Required保留。
  if not (arena.doc_late and arena.doc_late.Required and arena.doc_late:Required(item.prefab)) then return true end
 end
 if arena.doc_late and arena.doc_late.Drop and arena.doc_late:Drop(item) then return true end
 if arena.wave==5 and item.prefab=="armormarble" then return true end
 if item.prefab=="torch" and (arena.wave>=6 or arena.wave==5 and arena.doc_intermission and #(arena.enemies or {})==0) then return true end
 if M.IsFood(item) then
  -- 清包判断只查已持有实体；地面候选要加入比较，不能因尚未入包而直接拒绝。
  for _,owned in ipairs(bag) do if owned==item then return not M.FoodKeep(bag,arena.player)[item] end end
  return M.FoodWant(item,bag,arena.player)==false
 end
 return false
end
function M.Cleanup(arena)
 if locked(arena) then return false end
 local p=arena.player;local inv=p.replica.inventory;local bag=A.Items(p)
 local pending=arena.doc_drop
 if pending then
  local owned=false;for _,e in ipairs(bag) do if e==pending.item then owned=true end end
  if not owned then arena.doc_drop=nil
  elseif GetTime()<pending.untiltime then return safeidle(arena) else arena.doc_drop=nil;return false end
 end
 if p.components.playercontroller:IsBusy() or p:HasTag("attack") or not safeidle(arena) then return false end
 for _,item in ipairs(bag) do if M.Drop(arena,item,bag) then
  arena:StopCombat();inv:DropItemFromInvTile(item,false)
  arena.doc_drop={item=item,untiltime=GetTime()+1};arena.ignored[item.GUID]=math.huge
  return true
 end end
 return false
end
function M.Garlic(arena)
 if locked(arena) then return false end
 if arena.wave~=15 or arena.doc_garlic_eaten then return false end
 local p=arena.player;local pending=arena.doc_garlic_pending;local count=0;local selected
 for _,item in ipairs(A.Items(p)) do if item.prefab==M.GARLIC then
  local st=item.replica and item.replica.stackable;count=count+(st and st:StackSize() or 1);selected=item
 end end
 if pending then
  if count<pending.before then arena.doc_garlic_eaten=true;arena.doc_garlic_pending=nil;return false end
  if GetTime()<pending.deadline then return not p:HasTag("attack") and safeidle(arena,.6) end
  arena.doc_garlic_pending=nil;arena.doc_garlic_retry=GetTime()+2;return false
 end
 if not selected or GetTime()<(arena.doc_garlic_retry or 0) or p.components.playercontroller:IsBusy() or p:HasTag("attack") then return false end
 local c=arena.bridge.coordinator or require("shadowself/control/arena_prepare").Context(arena)
 if arena.healing and not arena.healing:Safe(c,p:GetPosition(),Food.Duration(selected)+.4) then return false end
 arena:StopCombat()
 local key=arena.doc_inventory_key
 if A.Self(p,selected,ACTIONS.EAT,function() return M.Owner(p)==arena and arena.wave==15 and arena.doc_inventory_key==key and safeidle(arena,.6) end) then arena.doc_garlic_pending={before=count,deadline=GetTime()+4};return true end
 return false
end
-- 刷怪后仍补捡当前打法确实需要的物品；危险时释放控制，下一安全窗口重试。
function M.Loot(arena)
 if locked(arena) then return false end
 local p=arena.player;local c=arena.bridge.coordinator
 if arena.stage11 and arena.stage11.finish and arena.stage11.reward and not arena.stage11.reward:Ready(true) then return false end
 if p.components.playercontroller:IsBusy() or p:HasTag("attack") or c and c.h and c.h.shadowself_dodging then return false end
 local context=c or require("shadowself/control/arena_prepare").Context(arena)
 local function safe(item)
  local ii=item.replica and item.replica.inventoryitem
  return valid(item) and ii and not ii:IsHeld() and (not arena.healing or arena.healing:Safe(context,item:GetPosition(),.7) and arena.healing:Path(context,item:GetPosition()))
 end
 local pending_owned=false
 for _,item in ipairs(A.Items(p)) do if item==arena.pending_item then pending_owned=true;break end end
 if arena.pending_item and pending_owned then
  arena.pending_item=nil;arena.pick_deadline=nil;require("shadowself/control/arena_pickup_travel").Release(arena)
 elseif arena.pending_item and not safe(arena.pending_item) then
  A.Stop(p);arena.pending_item=nil;arena.pick_deadline=nil;require("shadowself/control/arena_pickup_travel").Release(arena)
  return false
 end
 local bag=A.Items(p);local required=M.Required(arena);local choices={}
 for _,item in ipairs(arena.items or {}) do
  local requested=required[item.prefab] or arena.doc_late and arena.doc_late.Want and arena.doc_late:Want(item)
  local priority=require("shadowself/control/arena_inventory").Priority(item,arena.wave)
  local healing_food=M.IsFood(item) and Food.Health(item,p)>0 and M.CanConsume(p,item) and not Food.BuffOnly(item)
  if (requested or priority>=500 or healing_food) and arena:Want(item,bag) and safe(item) and GetTime()>=(arena.ignored[item.GUID] or 0) then choices[#choices+1]=item end
 end
 if #choices==0 then return false end
 table.sort(choices,function(a,b)
  if (required[a.prefab] and true or false)~=(required[b.prefab] and true or false) then return required[a.prefab] and true or false end
  return p:GetPosition():DistSq(a:GetPosition())<p:GetPosition():DistSq(b:GetPosition())
 end)
 local wave,id,gen=arena.wave,arena.instance,arena.generation
 return arena:Loot(choices,false,function() return arena.running and arena.wave==wave and arena.instance==id and arena.generation==gen and safe(choices[1]) end)
end
return M
