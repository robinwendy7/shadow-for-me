local A=require("shadowself/control/actions")
local Inventory=require("shadowself/control/arena_inventory")
local Tools=require("shadowself/control/arena_tools")
local M={}
function M.CleanupNine(arena,snapshot)
 if arena.wave<9 then return false end
 local after_nine=arena.wave>=10 or snapshot and snapshot.intermission and #arena:NearbyEnemies(60)==0
 for _,item in ipairs(A.Items(arena.player)) do
  if item.prefab=="nightstick" or item.prefab=="armormarble" or after_nine and item.prefab=="armorwood"
   or arena.wave>=10 and item.prefab=="staff_tornado" and Inventory.Condition(item)<.3 then
   arena:StopCombat()
   if arena.player.components.playercontroller:IsBusy() or GetTime()<(arena.next_stage_drop or 0) then return true end
   arena.player.replica.inventory:DropItemFromInvTile(item,false)
   arena.ignored[item.GUID]=math.huge;arena.next_stage_drop=GetTime()+.3
   arena:Say(item.prefab=="staff_tornado" and "第十关起 · 丢弃低于30%耐久的天气风向标" or after_nine and "第九关结束 · 清理木甲、大理石甲和晨星" or "第九关起 · 丢弃晨星和大理石甲")
   return true
  end
 end
 return false
end
function M.AfterTen(arena,snapshot)
 if arena.ten_cleanup_done then return false end
 local cleared=arena.wave==10 and snapshot and snapshot.intermission and #arena:NearbyEnemies(60)==0
 if not cleared and not (arena.wave>=11 and arena.ten_cleanup_due) then return false end
 arena:StopCombat()
 for _,item in ipairs(A.Items(arena.player)) do if Inventory.AfterTen(item) then
  if arena.player.components.playercontroller:IsBusy() or GetTime()<(arena.next_stage_drop or 0) then return true end
  arena.player.replica.inventory:DropItemFromInvTile(item,false)
  arena.ignored[item.GUID]=math.huge;arena.next_stage_drop=GetTime()+.3
  arena:Say("第十关结束 · 丢弃全部头部装备和骨甲以外的盔甲");return true
 end end
 arena.ten_cleanup_done=true;arena.ten_cleanup_due=nil;return false
end
function M.CaneOpening(arena)
 if arena.wave~=3 then return false end
 for _,item in ipairs(A.Items(arena.player)) do if item.prefab=="cane" and Tools.Usable(item) then return false end end
 for _,item in ipairs(arena.items or {}) do
  if item.prefab=="cane" and Tools.Usable(item) then
   arena:StopCombat()
   if arena.pending_item and arena.pending_item~=item then A.Stop(arena.player);arena.pending_item=nil;arena.pick_deadline=nil end
   arena:Say("第三关开局 · 优先拾取手杖")
   return arena:Loot({item})
  end
 end
 return false
end
function M.PirateItem(item)
 if not Tools.Usable(item) then return false end
 if item.prefab=="staff_tornado" then return true end
 local eq=item.replica and item.replica.equippable
 return eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and (item:HasTag("armor") or Inventory.Protection(item)>0) or false
end
function M.PirateOpening(arena)
 if arena.wave~=5 then return false end
 if not arena.pirate_opening then
  for _,e in ipairs(arena.entities or {}) do
   if e.prefab=="monkeyqueen" and e:IsValid() then
    arena.pirate_opening={instance=arena.instance,generation=arena.generation};break
   end
  end
 end
 local opening=arena.pirate_opening
 if not opening then return false end
 if opening.ready then
  if not opening.deferred or not arena:TrapReady() then return false end
  local remaining={};for _,item in ipairs(opening.deferred) do
   local ii=item:IsValid() and item.replica and item.replica.inventoryitem
   if ii and not ii:IsHeld() then remaining[#remaining+1]=item end
  end
  if #remaining==0 then opening.deferred=nil;opening.collecting=nil;return false end
  opening.collecting=true
  if arena:Loot(remaining) then return true end
  opening.collecting=nil;return false -- 容量不足/物品不可取不能再次卡住整关。
 end
 if #(arena.enemies or {})>0 and require("shadowself/control/arena_prepare").Armor(require("shadowself/control/arena_prepare").Context(arena)) then return true end
 arena:StopCombat()
 if arena.pending_item and not M.PirateItem(arena.pending_item) then
  A.Stop(arena.player);arena.pending_item=nil;arena.pick_deadline=nil
 end
 local items={};local source=arena.entities or arena.items or {}
 for _,item in ipairs(source) do
  local ii=item.replica and item.replica.inventoryitem
  if item:IsValid() and ii and not ii:IsHeld() and M.PirateItem(item) then items[#items+1]=item end
 end
 local p=arena.player:GetPosition()
 table.sort(items,function(a,b)
  if (a.prefab=="staff_tornado")~=(b.prefab=="staff_tornado") then return a.prefab=="staff_tornado" end
  return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition())
 end)
 local unsafe=false
 if #(arena.enemies or {})>0 then
  for _,item in ipairs(items) do if not M.SafePickup(arena,item) then unsafe=true;break end end
 end
 if unsafe then
  if arena.pending_item then A.Stop(arena.player);arena.pending_item=nil;arena.pick_deadline=nil end
  local staff=false;for _,item in ipairs(A.Items(arena.player)) do if item.prefab=="staff_tornado" and Tools.Usable(item) then staff=true end end
  local inv=arena.player.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
  if staff and head and Inventory.Protection(head)>0 and Inventory.Condition(head)>0 then
   opening.deferred=items;opening.ready=true
   arena:Say("海盗开局 · 已有旋风与头甲，危险补捡留到休整，进入原有巡游")
   return false
  end
  require("shadowself/control/arena_prepare").Escape(arena,require("shadowself/control/arena_prepare").Context(arena),"海盗开局 · 先离开包围，再安全取得旋风与头甲")
  return true
 end
 arena:Say("海盗场景 · 先拾取旋风和全部头部护甲")
 if arena:Loot(items) then return true end
 if #items>0 or arena.pending_item then
  local staff=false;for _,item in ipairs(A.Items(arena.player)) do if item.prefab=="staff_tornado" and Tools.Usable(item) then staff=true end end
  local inv=arena.player.replica.inventory;local head=inv.GetEquippedItem and inv:GetEquippedItem(EQUIPSLOTS.HEAD)
  if not arena.pending_item and staff and head and Inventory.Protection(head)>0 then opening.deferred=items;opening.ready=true;return false end
  if #(arena.enemies or {})>0 then require("shadowself/control/arena_prepare").Escape(arena,require("shadowself/control/arena_prepare").Context(arena),"海盗开局 · 补捡暂不可执行，先安全移动") end
  return true
 end
 if arena:Equip(arena.enemies or {}) then return true end
 opening.ready=true
 arena:Say("海盗场景 · 补给确认，开始场边游离15秒")
 return false
end
function M.BonePickup(arena)
 if arena.wave~=10 and arena.wave~=11 then return false end
 local stage=arena.stage11;local h=arena.healing
 if not h or h.pending or stage and (stage.finish or stage.buffs and stage.buffs.pending) then return false end
 for _,item in ipairs(A.Items(arena.player)) do if item.prefab=="armorskeleton" and Tools.Usable(item) then return false end end
 local candidates={}
 for _,item in ipairs(arena.items or {}) do if item.prefab=="armorskeleton" and Tools.Usable(item) then candidates[#candidates+1]=item end end
 if #candidates==0 then return false end
 table.sort(candidates,function(a,b) return Inventory.Condition(a)>Inventory.Condition(b) end)
 local c=require("shadowself/control/arena_prepare").Context(arena)
 local wave,instance,generation=arena.wave,arena.instance,arena.generation
 local function safe(item)
  c.enemies=arena:NearbyEnemies(60)
  local ii=item.replica and item.replica.inventoryitem
  return arena.running and arena.wave==wave and arena.instance==instance and arena.generation==generation
   and item:IsValid() and ii and not ii:IsHeld() and h:Safe(c,item:GetPosition(),.6) and h:Path(c,item:GetPosition())
 end
 for _,item in ipairs(candidates) do if safe(item) then
  arena:Say("第十/十一关 · 优先安全取得骨甲，保留后续疯猪防护")
  return arena:Loot({item},false,function() return safe(item) end)
 end end
 return false
end
function M.SafePickup(arena,item)
 if not arena.running or arena.wave~=5 or not item:IsValid() or not Tools.Usable(item) then return false end
 local ii=item.replica and item.replica.inventoryitem
 if not ii or ii:IsHeld() then return false end
 local c=arena.bridge.coordinator
 if c and c.h and c.h.shadowself_dodging then return false end
 local p=arena.player:GetPosition();local q=item:GetPosition()
 local dx,dz=q.x-p.x,q.z-p.z;local length=dx*dx+dz*dz
 -- 不为排箫穿过活怪；沿整段拾取路线保留进攻前摇余量。
 for _,e in ipairs(arena:NearbyEnemies(60)) do
  local v=e:GetPosition();local t=length>0 and math.max(0,math.min(1,((v.x-p.x)*dx+(v.z-p.z)*dz)/length)) or 0
  if (v.x-p.x-dx*t)^2+(v.z-p.z-dz*t)^2<8^2 then return false end
 end
 return true
end
function M.WeaponUpgrade(arena)
 if arena.wave~=10 and arena.wave~=11 then return false end
 local p=arena.player;local h=arena.healing;local stage=arena.stage11
 if not h or h.pending or stage and (stage.finish or stage.buffs and stage.buffs.pending) then return false end
 local bag=A.Items(p)
 if arena.pending_item and arena.pending_item.prefab=="nightsword" then
  for _,item in ipairs(bag) do if item==arena.pending_item then
   arena:Loot({arena.pending_item});return false -- 只在库存确认后释放拾取请求。
  end end
 elseif arena.pending_item then return false end
 for _,item in ipairs(bag) do if item.prefab=="nightsword" and Tools.Usable(item) then return false end end
 local candidates={}
 for _,item in ipairs(arena.items or {}) do if item.prefab=="nightsword" and Tools.Usable(item) then candidates[#candidates+1]=item end end
 if #candidates==0 then
  if arena.pending_item and arena.pending_item.prefab=="nightsword" then
   A.Stop(p);arena.pending_item=nil;arena.pick_deadline=nil
   require("shadowself/control/arena_pickup_travel").Release(arena)
  end
  return false
 end
 local c=arena.bridge.coordinator
 if not arena.pending_item and (p.components.playercontroller:IsBusy() or p:HasTag("attack") or c and c.h and c.h.shadowself_dodging) then return false end
 if not arena.rest_actions then
  require("shadowself/legacy/action_library")
  arena.rest_actions=require("shadowself/legacy/registry").ActionLibrary(p,{})
 end
 local wave,id,generation=arena.wave,arena.instance,arena.generation
 local context={player=p,actions=arena.rest_actions,enemies=arena:NearbyEnemies(60),observed=c and c.observed or {},
  hazards=arena.fire_zones or {},mechanisms=c and c.mechanisms,plan={arena=true,arena_wave=function() return wave end}}
 local function safe(item)
  local ii=item.replica and item.replica.inventoryitem
  context.enemies=arena:NearbyEnemies(60)
  return arena.running and arena.wave==wave and arena.instance==id and arena.generation==generation
   and Tools.Usable(item) and ii and not ii:IsHeld()
   and h:Safe(context,item:GetPosition(),.6) and h:Path(context,item:GetPosition())
 end
 for _,item in ipairs(candidates) do
  if item.prefab=="nightsword" and Inventory.Want(item,bag,p,wave) and safe(item) then
   arena:StopCombat();arena:Say("第十/十一关 · 安全补捡影刀，确认入包后由现有换装选择武器")
   return arena:Loot({item},false,function() return safe(item) end)
  end
 end
 if arena.pending_item and arena.pending_item.prefab=="nightsword" then
  A.Stop(p);arena.pending_item=nil;arena.pick_deadline=nil
  require("shadowself/control/arena_pickup_travel").Release(arena)
 end
 return false
end
function M.Tick(arena,snapshot)
 local reward=arena.stage11 and arena.stage11.reward
 if arena.stage11 and arena.stage11.finish and reward and not reward:Ready(true) then return false end
 if M.BonePickup(arena) then return true end
 if M.WeaponUpgrade(arena) then return true end
 if arena.wave>=11 and require("shadowself/control/arena_sanity").Tick(arena) then return true end
 if arena.wave>=10 then
  local h=arena.healing
  -- 补给在战斗协调器启动前也会执行，复用休整动作库，提供真实地形/路径校验。
  if not arena.rest_actions then
   require("shadowself/legacy/action_library")
   arena.rest_actions=require("shadowself/legacy/registry").ActionLibrary(arena.player,{})
  end
  local wave,id,generation=arena.wave,arena.instance,arena.generation
  local context={player=arena.player,actions=arena.rest_actions,enemies=arena:NearbyEnemies(60),observed={},hazards=arena.fire_zones or {},plan={arena=true,arena_wave=function() return wave end}}
  local function safe(item)
   local reward=arena.stage11 and arena.stage11.reward
   context.enemies=arena:NearbyEnemies(60)
   return arena.running and arena.wave==wave and arena.instance==id and arena.generation==generation
    and not (reward and (reward.opened or reward.pending)) and item:IsValid() and h:Safe(context,item:GetPosition(),.6) and h:Path(context,item:GetPosition())
  end
  if not h.pending then for _,item in ipairs(arena.items or {}) do
   if item.prefab=="nightmarefuel" and Inventory.Want(item,A.Items(arena.player),arena.player,wave) and safe(item) then
    arena:StopCombat();arena:Say("第十关起 · 安全拾取噩梦燃料，保留骨甲补给")
    return arena:Loot({item},false,function() return safe(item) end)
   end
  end end
 end
 if arena.wave==5 then
  if M.PirateOpening(arena) then return true end
  local flutes={}
  for _,item in ipairs(arena.items or {}) do
   if item.prefab=="panflute" and M.SafePickup(arena,item) then flutes[#flutes+1]=item end
  end
  if arena.pending_item and arena.pending_item.prefab=="panflute" and not M.SafePickup(arena,arena.pending_item) then
   A.Stop(arena.player);arena.pending_item=nil;arena.pick_deadline=nil
  end
  if #flutes>0 then
   if not arena.bridge:Running() then
    local _,bag=arena:Inventory()
    for _,item in ipairs(arena.items or {}) do
     if Inventory.Priority(item,5)>Inventory.Priority(flutes[1],5) and arena:Want(item,bag) then return false end
    end
   end
   return arena:Loot(flutes)
  end
 elseif (arena.wave==6 or arena.wave==7) and snapshot.intermission and #arena:NearbyEnemies(60)==0 then
  arena:StopCombat()
  if arena.wave==6 and not arena.healing.pending then
   for _,item in ipairs(A.Items(arena.player)) do if Inventory.AfterSix(item) then
    if arena.player.components.playercontroller:IsBusy() or GetTime()<(arena.next_item or 0) then return true end
    arena.player.replica.inventory:DropItemFromInvTile(item,false)
    arena.ignored[item.GUID]=math.huge;arena.next_item=GetTime()+.3
    arena:Say("第六关结束 · 丢弃草甲、火把、草帽和饼干切割机帽")
    return true
   end end
  end
  if not arena.healing.pending then
   local excess=Inventory.ExcessMeal(A.Items(arena.player),arena.player,arena.wave,true)
   if excess then
    if arena.player.components.playercontroller:IsBusy() or GetTime()<(arena.next_item or 0) then return true end
    arena.player.replica.inventory:DropItemFromInvTile(excess,false)
    arena.ignored[excess.GUID]=math.huge;arena.next_item=GetTime()+.3
    arena:Say("第六关结束起 · 只保留一格料理，丢弃多余料理")
    return true
   end
  end
  if arena.wave==7 then return arena:Rest({},true) end
 end
 return false
end
return M
