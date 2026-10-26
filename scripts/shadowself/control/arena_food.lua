-- 客户端优先使用原版料理表；食物组件存在时读取实际值。
local M={}
function M.BuffOnly(item) return item and item.prefab=="voltgoatjelly_spice_chili" end
local fallback={waffles=60,dragonpie=40,meatysalad=40,honeyham=30,guacamole=20,fruitmedley=20,
 baconeggs=20,koalefig_trunk=60,meatballs=3,talleggs=60,sweettea=3,frogfishbowl=20}
local harmful={mandrake=true,cookedmandrake=true,mandrakesoup=true,nightmarepie=true}
local cooking
function M.Recipe(item)
 if not cooking then local ok,v=pcall(require,"cooking");cooking=ok and v or {recipes={}} end
 local base=item.prefab:gsub("_spice_.*$","")
 for _,kind in ipairs({"cookpot","portablecookpot","portablespicer"}) do
  local recipes=cooking.recipes and cooking.recipes[kind]
  if recipes and (recipes[item.prefab] or recipes[base]) then return recipes[item.prefab] or recipes[base],base end
 end
 return nil,base
end
function M.Health(item,player)
 local recipe,base=M.Recipe(item)
 if harmful[base] or item:HasTag("spoiledfood") then return 0 end
 local edible=item.components and item.components.edible
 if edible and edible.GetHealth then return edible:GetHealth(player) end
 local value=recipe and recipe.health or fallback[base] or 0
 if type(value)~="number" or value<=0 then return 0 end
 local ii=item.replica and item.replica.inventoryitem
 local perish=ii and ii.classified and ii.classified.perish
 local fresh=perish and perish:value()
 local multiplier=1;local spoiled=false
 if fresh and fresh~=63 then
  if fresh/62<=.2 then multiplier=TUNING.SPOILED_FOOD_HEALTH or 0;spoiled=true
  elseif fresh/62<=.5 then multiplier=TUNING.STALE_FOOD_HEALTH or .333 end
 elseif item:HasTag("stalefood") then multiplier=TUNING.STALE_FOOD_HEALTH or .333 end
 local spice=item.prefab:match("_(spice_.+)$")
 local modifiers=not spoiled and spice and TUNING.SPICE_MULTIPLIERS and TUNING.SPICE_MULTIPLIERS[spice]
 if modifiers then multiplier=multiplier+(modifiers.HEALTH or 0) end
 return value*multiplier
end
function M.Hunger(item,player)
 if harmful[item.prefab] or item:HasTag("spoiledfood") then return 0 end
 local edible=item.components and item.components.edible
 if edible and edible.GetHunger then return edible:GetHunger(player) end
 local recipe=M.Recipe(item);local value=recipe and recipe.hunger or 0
 local fresh=M.Freshness(item)
 if fresh<=.2 then return 0 end
 if fresh<=.5 or item:HasTag("stalefood") then value=value*(TUNING.STALE_FOOD_HUNGER or .667) end
 return value
end
function M.Sanity(item,player)
 local recipe,base=M.Recipe(item)
 if harmful[base] or item:HasTag("spoiledfood") then return 0 end
 local edible=item.components and item.components.edible
 if edible and edible.GetSanity then return math.max(0,edible:GetSanity(player)) end
 local value=recipe and recipe.sanity or 0
 if type(value)~="number" or value<=0 or M.Freshness(item)<=.5 or item:HasTag("stalefood") then return 0 end
 local spice=item.prefab:match("_(spice_.+)$")
 local modifiers=spice and TUNING.SPICE_MULTIPLIERS and TUNING.SPICE_MULTIPLIERS[spice]
 return value*(1+(modifiers and modifiers.SANITY or 0))
end
function M.Duration(item)
 local recipe=M.Recipe(item)
 if item:HasTag("quickeat") or item:HasTag("fooddrink") then return .6 end
 if item:HasTag("sloweat") or item:HasTag("edible_MEAT")
  or recipe and recipe.foodtype==((FOODTYPE and FOODTYPE.MEAT) or "MEAT") then return 1.1 end
 return .6
end
function M.Freshness(item)
 local ii=item.replica and item.replica.inventoryitem
 local perish=ii and ii.classified and ii.classified.perish
 return perish and perish:value()~=63 and perish:value()/62 or 1
end
function M.Known(name) return fallback[name:gsub("_spice_.*$","")]~=nil end
return M
