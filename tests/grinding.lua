-- Use the installed game's real builder replica and prototype predicate, not a
-- KnowsRecipe=true stub: nounlock station recipes deliberately aren't learned.
local time=10000;GetTime=function() return time end
local Tech=assert(loadstring(read_source("techtree.lua")))()
local source=read_source("widgets/widgetutil.lua")
local predicate=assert(source:match("function CanPrototypeRecipe%b()%s*.-\nend"))
assert(loadstring(predicate))()
local env=setmetatable({require=function(name) assert(name=="techtree");return Tech end,
    TheWorld={ismastersim=false},INGREDIENT_MOD_LOOKUP={[0]=1},RoundBiasedUp=math.ceil},{__index=_G})
local loader=assert(loadstring(read_source("components/builder_replica.lua")));setfenv(loader,env)
local Builder=loader()
local function item(k,n) return {prefab=k,replica={stackable={StackSize=function() return n end}}} end
local p={prefab="warly",replica={inventory={items={item("pepper",3)}}},components={}}
function p:HasTag(tag) return tag=="professionalchef" and self.prefab=="warly" end
function p:GetDistanceSqToInst() return 1 end
function p.replica.inventory:GetItems() return self.items end
function p.replica.inventory:GetOverflowContainer() end
function p.replica.inventory:Has(prefab,amount)
    local n=0;for _,v in pairs(self.items) do if v.prefab==prefab then n=n+v.replica.stackable:StackSize() end end
    return n>=amount,n
end
local b=Builder(p);p.replica.builder=b
b.classified={isfreebuildmode={value=function() return false end},recipes={},ingredientmod={value=function() return 0 end},techtrees=Tech.Create({FOODPROCESSING=0})}
local recipe={name="spice_chili",product="spice_chili",builder_tag="professionalchef",nounlock=true,
    level=Tech.Create({FOODPROCESSING=1}),ingredients={{type="pepper",amount=3}},character_ingredients={},tech_ingredients={}}
env.GetValidRecipe=function(k) return k=="spice_chili" and recipe end
GetValidRecipe=env.GetValidRecipe
package.loaded["shadowself/control/grinding"]=nil
local Grind=require("shadowself/control/grinding")
assert(not b:KnowsRecipe(recipe) and b:CanLearn(recipe.name) and b:HasIngredients(recipe))
local ok,message,code=Grind.Check(p,recipe);assert(not ok and code=="technology")
b.classified.techtrees.FOODPROCESSING=1
assert(not b:KnowsRecipe(recipe),"a station's accessible tree does not change learned/bonus recipes")
assert(Grind.Check(p,recipe),"station recipe works even though KnowsRecipe remains false")
p.replica.inventory.items={item("pepper",2)}
ok,message,code=Grind.Check(p,recipe);assert(not ok and code=="ingredients" and message:find("2/3",1,true))
p.prefab="wilson";ok,message,code=Grind.Check(p,recipe);assert(not ok and code=="role")
p.prefab="warly";p.replica.inventory.items={item("pepper",3)}
assert(select(3,Grind.Check(p,nil))=="recipe")
-- Real cooking state machine waits for station replication, submits once, then
-- waits for the crafted item. Standing nearby must not fail on the first tick.
local requests=0
p.components.playercontroller={IsBusy=function() return false end,RemoteMakeRecipeFromMenu=function(_,r)
    assert(r==recipe);requests=requests+1
end}
local grinder={prefab="portableblender",IsValid=function() return true end}
local Cooking=require("shadowself/control/cooking")
local cook=Cooking(p,{dish={base="meatballs",product="meatballs_spice_chili",spice="spice_chili"},target="辣肉丸"},function() end)
cook.grinder=grinder;cook:Stage("grind");b.classified.techtrees.FOODPROCESSING=0
assert(cook:Tick()=="running" and requests==0,"waits for station tech instead of refusing immediately")
time=time+1;b.classified.techtrees.FOODPROCESSING=1
assert(cook:Tick()=="running" and requests==1 and cook.sent)
time=time+1;assert(cook:Tick()=="running" and requests==1,"no repeated crafting while result is pending")
p.replica.inventory.items={item("spice_chili",2)};time=time+.2
assert(cook:Tick()=="running" and cook.phase=="fill","continues only after powder arrives")
local stalled=Cooking(p,cook.plan,function() end);stalled.grinder=grinder;stalled:Stage("grind")
b.classified.techtrees.FOODPROCESSING=0
assert(stalled:Tick()=="running");time=time+5.1
ok,message=stalled:Tick();assert(ok=="failed" and message:find("科技",1,true))
-- Host path uses the same replica methods delegating to the real builder API.
p.replica.inventory.items={item("pepper",3)}
p.components.builder={KnowsRecipe=function() return false end,CanLearn=function() return true end,
    accessible_tech_trees=Tech.Create({FOODPROCESSING=1}),HasIngredients=function() return true end}
assert(Grind.Check(p,recipe),"host delegation supports prototype-only station recipes too")
print("PASS: native builder replica: KnowsRecipe=false + CanLearn + accessible FOODPROCESSING permits powder; role/material/tech errors distinct; delayed tech sync, single crafting request, powder receipt and host path")
