local oldA=package.loaded["shadowself/control/actions"];local oldK=package.loaded["shadowself/knowledge"]
local oldNames,oldDesc=STRINGS.NAMES,STRINGS.RECIPE_DESC;local oldRecipes,oldValid=AllRecipes,GetValidRecipe
STRINGS.NAMES={TORCH="火把",LOG="木头",BOARDS="木板",CUTGRASS="草",TWIGS="树枝"};STRINGS.RECIPE_DESC={TORCH="便携照明。"}
AllRecipes={torch={name="torch",ingredients={{type="cutgrass",amount=2},{type="twigs",amount=2}}},boards={name="boards",ingredients={{type="log",amount=4}}}}
GetValidRecipe=function(name) return AllRecipes[name] end
package.loaded["shadowself/control/actions"]={Count=function(_,key) return ({log=2,torch=1,cutgrass=1,twigs=2})[key] or 0 end}
package.loaded["shadowself/knowledge"]=nil
local K=require("shadowself/knowledge")
local r={memory={},owner={replica={inventory={GetEquips=function() return {hands={prefab="torch",replica={}}} end},builder={KnowsRecipe=function() return true end,HasIngredients=function() return false end}}}}
local reply,id=K.Match("火把怎么做",r);assert(id=="item_recipe" and reply:find("草×2",1,true) and reply:find("树枝×2",1,true))
reply,id=K.Match("火把还缺什么",r);assert(id=="item_missing" and reply:find("草×1",1,true))
reply,id=K.Match("我有多少火把",r);assert(id=="item_stock" and reply:find("2个",1,true),"carried count includes equipped item")
reply,id=K.Match("木头能做什么",r);assert(id=="item_uses" and reply:find("木板",1,true),"reverse recipe use is based on real ingredients")
reply,id=K.Match("火把现在能做吗",r);assert(id=="item_can_craft" and reply:find("材料",1,true))
reply,id=K.Match("刚才那个的配方是什么",r);assert(id=="item_recipe" and reply:find("火把",1,true),"short item followup remembers previous subject")
assert(K.Match("帮我制作火把",r)==nil,"knowledge never steals an execution command")
package.loaded["shadowself/control/actions"]=oldA;package.loaded["shadowself/knowledge"]=oldK
STRINGS.NAMES=oldNames;STRINGS.RECIPE_DESC=oldDesc;AllRecipes=oldRecipes;GetValidRecipe=oldValid
print("PASS: grounded recipe, material deficit, carried+equipped count, recipe uses, builder conditions, item followup and execution-command isolation")
