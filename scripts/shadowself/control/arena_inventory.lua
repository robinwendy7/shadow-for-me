-- 战斗中按实际持有取舍；关间休整允许按下一关必出武器提前腾出背包。
local Policy=require("shadowself/control/arena_policy")
local Damage=require("shadowself/control/weapon_damage")
local Food=require("shadowself/control/arena_food")
local P={}
function P.AfterSix(item) return item.prefab=="armorgrass" or item.prefab=="torch" or item.prefab=="strawhat" or item.prefab=="cookiecutterhat" end
local tools={staff_tornado=true,cane=true,nightstick=true,panflute=true,firestaff=true,icestaff=true,icestaff2=true,icestaff3=true,
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
 if item.prefab=="boomerang" or not Policy.known[item.prefab] or tools[item.prefab] or situational[item.prefab] then return false end
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
function P.AfterTen(item)
 local eq=item.replica and item.replica.equippable
 if not eq then return false end
 local slot=eq:EquipSlot()
 return slot==EQUIPSLOTS.HEAD or slot==EQUIPSLOTS.BODY and item.prefab~="armorskeleton"
  and (item:HasTag("armor") or P.Armor(item)~=nil)
end
function P.Special(name,wave)
 if wave>=11 and (name=="alterguardianhat" or name=="lunar_seed" or name=="staff_lunarplant") then return true end
 if wave==11 and name=="wathgrithr_improvedhat" then return true end
 if name=="sweettea" and wave>=9 then return true end
 if name=="nightstick" then return wave<9 end
 if name=="staff_tornado" then return true end
 if name=="rainhat" then return wave<=6 end
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
 if item.prefab=="armorskeleton" then return 1 end
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
-- 无可用身甲的前八关，头部按实际吸收率优先；同减伤才比较位面防御与耐久。
function P.HelmetFallback(player,bag,wave)
 if not wave or wave<1 or wave>8 then return end
 local inv=player.replica.inventory
 if inv:GetEquippedItem(EQUIPSLOTS.BODY) then return end
 for _,item in ipairs(bag) do
  local eq=item.replica and item.replica.equippable
  if eq and eq:EquipSlot()==EQUIPSLOTS.BODY and not item:HasTag("broken") and P.Condition(item)>0 and P.Protection(item)>0 then return end
 end
 local best
 for _,item in ipairs(bag) do
  local eq=item.replica and item.replica.equippable
  if eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and not item:HasTag("broken") and P.Condition(item)>0 and P.Protection(item)>0 then
   if not best or P.Protection(item)>P.Protection(best)
    or P.Protection(item)==P.Protection(best) and (P.PlanarArmor(item)>P.PlanarArmor(best)
     or P.PlanarArmor(item)==P.PlanarArmor(best) and P.Condition(item)>P.Condition(best)+.05) then best=item end
  end
 end
 return best
end
function P.Obsolete(item,bag,player,wave)
 if wave>=9 and (item.prefab=="nightstick" or item.prefab=="armormarble") then return true end
 if P.BelowArmorFloor(item,wave) then return true end
 if item.prefab=="rainhat" and wave>6 or item.prefab=="torch" and wave>=8 then return true end
 if item.prefab=="hambat" then
  for _,other in ipairs(bag) do if other.prefab=="ruins_bat" and P.Condition(other)>0 then return true end end
 end
 -- 回旋镖不参与角斗场拾取或常规武器比较，已有的允许清理。
 if item.prefab=="boomerang" then return true end
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
 if item.prefab=="torch" and wave>=10 then return true end
 return false
end
-- 仅预测确定会刷新的常规近战武器；概率掉落和特殊用途装备不提前淘汰。
local forecast_weapons={spear=true,tentaclespike=true,hambat=true,nightsword=true,ruins_bat=true,
 glasscutter=true,sword_lunarplant=true,voidcloth_scythe=true,shadow_battleaxe=true,
 spear_wathgrithr_lightning=true,spear_wathgrithr_lightning_charged=true}
function P.ForecastDiscard(bag,player,wave,route)
 local nextwave=wave+1
 local supplies=require("shadowself/data/arena_classic").supplies[nextwave]
 if not supplies then return nil end
 local routes={}
 -- 第11关随机分线尚未确定时，对所有可能路线取交集。
 if nextwave<=10 then routes={supplies.default}
 elseif nextwave~=11 and supplies[route or ""] then routes={supplies[route]}
 else for _,sets in pairs(supplies) do routes[#routes+1]=sets end end
 for _,item in ipairs(bag) do
  if not P.Special(item.prefab,wave) and P.Weapon(item,player) then
   local guaranteed=#routes>0
   for _,sets in ipairs(routes) do
    if #sets==0 then guaranteed=false end
    for _,set in ipairs(sets) do
     local better=false
     for _,drop in ipairs(set) do
      if forecast_weapons[drop.prefab] and (drop.probability or 1)>=1 and (drop.amount or 1)>0 then
       local future={prefab=drop.prefab}
       if P.Physical(future)>P.Physical(item) and Damage.Planar(future)>=Damage.Planar(item) then better=true;break end
      end
     end
     if not better then guaranteed=false;break end
    end
    if not guaranteed then break end
   end
   if guaranteed then return item end
  end
 end
end
function P.Want(item,bag,player,wave)
 if not Policy.PickupAllowed(item,wave,player) then return false end
 if wave>=7 and P.AfterSix(item) then return false end
 if wave>=9 and item.prefab=="sweettea" then
  if Food.Health(item,player)<=0 then return false end
  for _,other in ipairs(bag) do if other.prefab=="sweettea" and Food.Health(other,player)>0 then return false end end
  return true
 end
 if wave==5 and item.prefab=="panflute" then
  local tools=require("shadowself/control/arena_tools");if not tools.Usable(item) then return false end
  local usable=0;for _,other in ipairs(bag) do if other.prefab=="panflute" and tools.Usable(other) then usable=usable+1 end end
  return usable<2 -- 本轮补一支备用排箫，避免重复拾取挤满物品栏。
 end
 if item.prefab=="panflute" or item.prefab=="staff_tornado" then
  local tools=require("shadowself/control/arena_tools")
  if not tools.Usable(item) then return false end
  -- 用尽的工具仍在背包中时，也要允许拿取地上的可用替代品。
  local usable=false
  for _,other in ipairs(bag) do if other.prefab==item.prefab and tools.Usable(other) then usable=true;break end end
  if not usable then return true end
 end
 if P.Obsolete(item,bag,player,wave) then return false end
 if wave>=11 and P.IsMeal(item) then
  local candidates={};for _,other in ipairs(bag) do
   if other.prefab==item.prefab then
    local stack=other.replica and other.replica.stackable
    if stack and not stack:IsFull() then return true end
   end
   candidates[#candidates+1]=other
  end
  candidates[#candidates+1]=item
  return P.RetainedMeals(candidates,player)[item] or false
 end
 if P.IsMeal(item) then
  local count=0
  for _,other in ipairs(bag) do if P.IsMeal(other) then
   count=count+1
   local stack=other.replica and other.replica.stackable
   if other.prefab==item.prefab and stack and not stack:IsFull() then return true end
  end end
  if count>=(wave>=7 and 1 or 2) then return false end
 end
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
 if n=="armorskeleton" and wave>=10 then return 9990 end
 if wave==8 and (n=="boat_item" or n=="boat_grass_item") then return 10000 end
 if wave==8 and (n=="oar_driftwood" or item:HasTag("oar")) then return 9900 end
 if Policy.TrapLoot(item,wave) then return -1000 end
 local armor=P.Armor(item)
 if n=="cane" then return wave==3 and 9800 or 3000 end
 if wave==9 and n=="sweettea" then return 8500 end
 if wave>=11 and n=="voltgoatjelly_spice_chili" then return 9950 end
 if wave==11 and n=="wathgrithr_improvedhat" then return 9900 end
 if wave>=11 and n~="sweettea" and Food.Sanity(item)>0 then return 700+Food.Sanity(item) end
 if armor then return 2200+armor end
 if n=="nightstick" then return 4000+P.Physical(item) end
 if not tools[n] and not situational[n] and item.HasTag and item:HasTag("weapon") then return 4000+P.Physical(item) end
 if n=="boat_item" and wave==8 then return 1200 end
 if n=="oar_driftwood" and wave==8 then return 1100 end
 if n=="panflute" then return 900 end
 if n=="icestaff2" or n=="icestaff3" or n=="firestaff" then return 800 end
 if P.Special(n,wave) then return 500 end
 if food[n] or Food.Known(n) then return 100+math.max(0,Food.Health(item)) end
 return 200
end
function P.IsFood(item)
 return food[item.prefab]~=nil or Food.Known(item.prefab) or Food.Recipe(item)~=nil
end
local function foodscore(item,player)
 return math.max(0,Food.Health(item,player))+(item.prefab:find("voltgoatjelly",1,true) and 100 or 0)
end
-- 舒缓茶按原有低SAN饮用规则单独保留；料理限制按物品栏格子而非堆叠数量。
function P.IsMeal(item) return item.prefab~="sweettea" and P.IsFood(item) end
function P.RetainedMeals(bag,player)
 local jelly,reserve,sanity,health
 for _,item in ipairs(bag) do if P.IsMeal(item) and (Food.Health(item,player)>0 or Food.Sanity(item,player)>0) then
  if item.prefab=="voltgoatjelly_spice_chili" then
   if not jelly or Food.Freshness(item)>Food.Freshness(jelly) then jelly=item end
  else
   local san,hp=Food.Sanity(item,player),Food.Health(item,player)
   if not reserve or san>sanity or san==sanity and hp>health then reserve,sanity,health=item,san,hp end
  end
 end end
 local keep={};if jelly then keep[jelly]=true end;if reserve then keep[reserve]=true end;return keep
end
function P.ExcessMeal(bag,player,wave,cleared)
 if wave>=11 then
  local keep=P.RetainedMeals(bag,player)
  for _,item in ipairs(bag) do if P.IsMeal(item) and not keep[item] then return item end end
  return
 end
 local limit=(wave>=7 or wave==6 and cleared) and 1 or 2
 local meals={}
 for _,item in ipairs(bag) do if P.IsMeal(item) then meals[#meals+1]=item end end
 if #meals<=limit then return end
 table.sort(meals,function(a,b)
  local av,bv=foodscore(a,player),foodscore(b,player)
  if av~=bv then return av>bv end
  return (a.GUID or 0)<(b.GUID or 0)
 end)
 return meals[#meals]
end
-- 第六关结束先清理指定四类旧物；其他护甲仍按后段防御门槛处理。
function P.BelowArmorFloor(item,wave)
 if wave==12 and P.PlanarArmor(item)>0 then return false end
 if wave==11 and item.prefab=="wathgrithr_improvedhat" then return false end
 if not P.Armor(item) then return false end
 local floor=wave>=11 and .9 or wave>=8 and .8 or 0
 return P.Protection(item)+.0001<floor
end
function P.Cleanup(bag,player,wave,cleared)
 if wave==10 and cleared then for _,item in ipairs(bag) do if P.AfterTen(item) then return item end end end
 if wave>=10 then for _,item in ipairs(bag) do if item.prefab=="staff_tornado" and P.Condition(item)<.3 then return item end end end
 if wave>=10 or wave==9 and cleared then for _,item in ipairs(bag) do if item.prefab=="armorwood" or item.prefab=="armormarble" then return item end end end
 if wave>=9 then for _,item in ipairs(bag) do if item.prefab=="nightstick" or item.prefab=="armormarble" then return item end end end
 if wave>=7 or wave==6 and cleared then
  for _,item in ipairs(bag) do if P.AfterSix(item) then return item end end
 end
 local excess=P.ExcessMeal(bag,player,wave,cleared)
 if excess then return excess end
 if not (wave>=8 or wave==7 and cleared) then return nil end
 local nextphase=(wave==7 or wave==10) and cleared and wave+1 or wave
 for _,item in ipairs(bag) do
  local eq=item.replica and item.replica.equippable
  local worn=P.Armor(item) and eq and player.replica.inventory:GetEquippedItem(eq:EquipSlot())==item
  if P.BelowArmorFloor(item,nextphase) or not worn and P.Obsolete(item,bag,player,nextphase) then return item end
 end

end
-- 背包满时只用更有价值且已存在于地面的物品置换，不清除未知玩家物品。
function P.Discard(bag,player,wave,wanted)
 if wave>=11 and wanted and P.IsMeal(wanted) then
  local combined={wanted};for _,item in ipairs(bag) do combined[#combined+1]=item end
  local extra=P.ExcessMeal(combined,player,wave,false)
  if extra and extra~=wanted then return extra end
 end
 if wanted and wanted.prefab=="panflute" then
  for _,item in ipairs(bag) do if item.prefab=="panflute" and not require("shadowself/control/arena_tools").Usable(item) then return item end end
 end
 local cleanup=P.Cleanup(bag,player,wave,false);if cleanup then return cleanup end
 for _,item in ipairs(bag) do if not P.Armor(item) and P.Obsolete(item,bag,player,wave) then return item end end
 if wanted and P.Weapon(wanted,player) then
  for _,item in ipairs(bag) do if P.Weapon(item,player) and P.Dominates(wanted,item) then return item end end
 end
 -- 仅在满包要拿装备时清理备用旧甲；已经穿上的替代甲必须真实确认，不能为地上新甲先脱掉旧甲。
 if wanted and P.Priority(wanted,wave)>=2200 then
  local inv=player.replica and player.replica.inventory
  for _,item in ipairs(bag) do
   if not P.Special(item.prefab,wave) and P.Armor(item) then
    local slot=item.replica.equippable:EquipSlot()
    local worn=inv and inv.GetEquippedItem and inv:GetEquippedItem(slot)
    if worn and worn~=item and P.Armor(worn) and P.Obsolete(item,{item,worn},player,wave) then return item end
   end
  end
 end
 if wanted and P.Priority(wanted,wave)>=500 then
  local worst,score,count=nil,nil,0
  local keep=wave>=11 and P.RetainedMeals(bag,player) or {}
  for _,item in ipairs(bag) do local value=not keep[item] and not (wave>=9 and item.prefab=="sweettea") and (food[item.prefab] or Food.Known(item.prefab)) and math.max(0,Food.Health(item,player))
   if value then count=count+1;if not score or value<score then worst,score=item,value end end
  end
  if count>1 then return worst end
 end
end
return P
