-- 第二关鱼人/青蛙：先拿鞭与穿木甲，战中失落物只在真实休整后补捡。
local A=require("shadowself/control/actions")
local M={}
function M.Update(arena,snapshot)
 local whip=arena.whip
 if arena.wave~=2 or not whip or not whip.started then arena.frog_loot=nil;return end
 local s=arena.frog_loot
 if not s or s.instance~=arena.instance then
  s={instance=arena.instance,owned={},obtained={},prefabs={},initial_ground={}};arena.frog_loot=s
  for _,item in ipairs(arena.items or {}) do s.initial_ground[item]=true end
 end
 for _,item in ipairs(A.Items(arena.player)) do
  s.owned[item]=true
  s.prefabs[item.prefab]=true
  if item:IsValid() and not item:HasTag("broken") and require("shadowself/control/arena_inventory").Condition(item)>0 then s.obtained[item.prefab]=true end
 end
 -- 本地空扫描或仅仅看见尸体不能解除延后补捡。
 s.released=snapshot.intermission and arena:TrapReady() or false
end
function M.Opening(arena)
 local s=arena.frog_loot
 if not s or s.ready or s.released or not arena.whip.active then return false end
 local p=arena.player;local inv=p.replica.inventory;local held={}
 for _,item in ipairs(A.Items(p)) do
  if item:IsValid() and not item:HasTag("broken") and require("shadowself/control/arena_inventory").Condition(item)>0 then held[item.prefab]=item end
  if arena.pending_item==item then
   arena.pending_item=nil;arena.pick_deadline=nil;require("shadowself/control/arena_pickup_travel").Release(arena)
  end
 end
 if not arena.whip:CanPickup(p) then return false end
 for _,name in ipairs({"whip","armorwood"}) do
  if not held[name] and not s.obtained[name] then
   for _,item in ipairs(arena.items or {}) do
    if item.prefab==name and not s.owned[item] and item:IsValid() and not item:HasTag("broken")
     and require("shadowself/control/arena_inventory").Condition(item)>0 then
     arena:Say(name=="whip" and "鱼人青蛙开局 · 优先拾取三尾猫鞭" or "鱼人青蛙开局 · 优先拾取木甲并确认穿戴")
     return arena:Loot({item},false,function() return arena.wave==2 and arena.frog_loot==s and not s.released and not s.owned[item] end)
    end
   end
  end
 end
 local armor=held.armorwood
 if armor and inv:GetEquippedItem(EQUIPSLOTS.BODY)~=armor then
  arena:StopCombat()
  if not p.components.playercontroller:IsBusy() and not p:HasTag("attack") and GetTime()>=(s.next_equip or 0) then
   A.Self(p,armor,ACTIONS.EQUIP);s.next_equip=GetTime()+.5
  end
  return true -- 发出穿戴请求不等于实际已经穿上。
 end
 if held.whip and armor and inv:GetEquippedItem(EQUIPSLOTS.BODY)==armor then s.ready=true end
 return false
end
return M
