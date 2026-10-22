-- 本局实际持有物品决定取舍；不把尚未掉落的装备当作已有替代品。
local Policy=require("shadowself/control/arena_policy")
local Damage=require("shadowself/control/weapon_damage")
local Food=require("shadowself/control/arena_food")
local P={}
local tools={cane=true,nightstick=true,panflute=true,firestaff=true,icestaff=true,icestaff2=true,icestaff3=true,
 orangestaff=true,armorsnurtleshell=true,armorskeleton=true,nightmarefuel=true,yellowamulet=true,
 rainhat=true,eyebrellahat=true,lunarplant_kit=true,voidcloth_kit=true}
local situational={batbat=true,torch=true}
local food={waffles=60,dragonpie=40,meatysalad=40,honeyham=30,guacamole=20,fruitmedley=20,
 baconeggs=20,koalefig_trunk=60,meatballs=3,talleggs=60,sweettea=3}
function P.Condition(item)
 local ii=item.replica and item.replica.inventoryitem
 local c=item.components or {};local component=c.armor or c.finiteuses or c.fueled
 if component and component.GetPercent then return component:GetPercent() end
 local net=ii and ii.classified and ii.classified.percentused
 if net then local value=net:value();if value~=255 then return value/100 end end
 return 1
end
function P.Weapon(item,player)
 if not Policy.known[item.prefab] or tools[item.prefab] or situational[item.prefab] then return false end
 require("shadowself/legacy/combat_equipment")
 return require("shadowself/legacy/registry").Equipment.Weapon(player,item)
end
function P.Physical(item)
 require("shadowself/legacy/combat_equipment")
 return require("shadowself/legacy/registry").CombatEquipment.Damage({combat={plan={arena=true}}},item)
end
function P.Dominates(a,b)
 local ap,bp=P.Physical(a),P.Physical(b);local ad,bd=Damage.Planar(a),Damage.Planar(b)
 -- 位面武器不能因物理伤害较低被普通武器淘汰。
 return ap>=bp and ad>=bd and (ap>bp or ad>bd or P.Condition(a)>P.Condition(b)+.05)
end
function P.Special(name,wave)
 if tools[name] then return true end
 if name=="boat_item" or name=="boat_grass_item" or name=="oar_driftwood" then return wave<=8 end
 if name=="torch" then return wave<10 end
 if name=="batbat" then return true end
 if name=="bugnet" or name=="houndstooth_blowpipe" then return wave<=13 end
 return name=="voltgoatjelly_spice_chili" or name=="voltgoatjelly" or name:find("_spice_",1,true)~=nil
end
function P.Armor(item)
 local eq=item.replica and item.replica.equippable
 return eq and eq:EquipSlot()~=EQUIPSLOTS.HANDS and Policy.ArmorScore(item,eq:EquipSlot(),{}) or nil
end
function P.Protection(item)
 local armor=item.components and item.components.armor
 if armor and type(armor.absorb_percent)=="number" then return armor.absorb_percent end
 return ({armorgrass=.6,armorwood=.8,armormarble=.95,armordragonfly=.7,armorruins=.9,armordreadstone=.9,
  armorwagpunk=.8,armor_lunarplant=.8,armor_voidcloth=.8,footballhat=.8,cookiecutterhat=.7,
  slurtlehat=.9,wathgrithr_improvedhat=.8,ruinshat=.9,dreadstonehat=.9,lunarplanthat=.8,voidclothhat=.8})[item.prefab] or 0
end
function P.PlanarArmor(item)
 local c=item.components and item.components.planardefense
 if c and c.GetDefense then return c:GetDefense() end
 return ({armor_lunarplant=10,armor_voidcloth=10,lunarplanthat=10,voidclothhat=10,armorwagpunk=15})[item.prefab] or 0
end
function P.Obsolete(item,bag,player,wave)
 if not Policy.known[item.prefab] or P.Special(item.prefab,wave) then return false end
 if item.prefab=="boat_item" or item.prefab=="boat_grass_item" or item.prefab=="oar_driftwood" then return wave>8 end
 if P.Weapon(item,player) then
  for _,other in ipairs(bag) do if other~=item and P.Weapon(other,player) and P.Dominates(other,item) then return true end end
 end
 local armor=P.Armor(item)
 if armor then
  local slot=item.replica.equippable:EquipSlot()
  for _,other in ipairs(bag) do
   local eq=other.replica and other.replica.equippable;local score=P.Armor(other)
   if other~=item and eq and eq:EquipSlot()==slot and score and P.Protection(other)>=P.Protection(item)
    and P.PlanarArmor(other)>=P.PlanarArmor(item) and
    (score>armor or score==armor and P.Condition(other)>P.Condition(item)+.05) then return true end
  end
 end
 -- 过时的投掷武器/旋风工具不挤占后段装备位。
 if item.prefab=="boomerang" and wave>=3 or item.prefab=="staff_tornado" and wave>=7 or item.prefab=="torch" and wave>=10 then return true end
 return false
end
function P.Want(item,bag,player,wave)
 if P.Obsolete(item,bag,player,wave) then return false end
 local count=0
 for _,other in ipairs(bag) do if other.prefab==item.prefab then
  count=count+1
  local stack=other.replica and other.replica.stackable
  if stack and not stack:IsFull() then return true end
  if P.Condition(item)>P.Condition(other)+.05 and (P.Weapon(item,player) or P.Armor(item)) then return true end
 end end
 return count==0 or (food[item.prefab] or Food.Known(item.prefab)) and count<2
end
function P.Priority(item,wave)
 local n=item.prefab
 if n=="spear" and wave==1 then return 1000 end
 if n=="boat_item" and wave==8 then return 1200 end
 if n=="oar_driftwood" and wave==8 then return 1100 end
 if n=="panflute" or n=="cane" then return 900 end
 if n=="icestaff2" or n=="icestaff3" or n=="firestaff" then return 800 end
 if P.Armor(item) then return 600+P.Armor(item) end
 if P.Special(n,wave) then return 500 end
 if food[n] or Food.Known(n) then return 100+math.max(0,Food.Health(item)) end
 return 200
end
-- 背包满时只用更有价值且已存在于地面的物品置换，不清除未知玩家物品。
function P.Discard(bag,player,wave,wanted)
 for _,item in ipairs(bag) do if P.Obsolete(item,bag,player,wave) then return item end end
 if wanted and P.Weapon(wanted,player) then
  for _,item in ipairs(bag) do if P.Weapon(item,player) and P.Dominates(wanted,item) then return item end end
 end
 if wanted and P.Armor(wanted) then
  for _,item in ipairs(bag) do if not P.Special(item.prefab,wave) and P.Armor(item) and
   item.replica.equippable:EquipSlot()==wanted.replica.equippable:EquipSlot() and P.Armor(wanted)>P.Armor(item)
   and P.Protection(wanted)>=P.Protection(item) and P.PlanarArmor(wanted)>=P.PlanarArmor(item) then return item end end
 end
 if wanted and P.Priority(wanted,wave)>=500 then
  local worst,score,count=nil,nil,0
  for _,item in ipairs(bag) do local value=(food[item.prefab] or Food.Known(item.prefab)) and math.max(0,Food.Health(item,player))
   if value then count=count+1;if not score or value<score then worst,score=item,value end end
  end
  if count>1 then return worst end
 end
end
return P
