-- Load actual installed game recipe definitions into a separate data-only environment.
-- Nutrition/effect constants are dummies; ingredient tags and test functions are native.
local cache={}
local function tree() return setmetatable({},{__index=function(t,k) local v=tree();rawset(t,k,v);return v end}) end
local enum=setmetatable({},{__index=function(_,k) return k end})
local env=setmetatable({TUNING=setmetatable({OCEANFISH_LURE_PREFERENCE=tree()},{__index=function() return 1 end}),FOODTYPE=enum,FOODGROUP=enum,STRINGS=tree()},{__index=_G})
env.SEASONS=enum
env.WORLD_TILES=enum
env.GROUND=enum
env.shallowcopy=function(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
env.deepcopy=function(t) if type(t)~="table" then return t end;local out={};for k,v in pairs(t) do out[k]=env.deepcopy(v) end;return out end
env.ArrayUnion=function(a,b) local c={};for _,v in ipairs(a) do c[#c+1]=v end;for _,v in ipairs(b) do c[#c+1]=v end;return c end
env.require=function(name)
    if name=="tuning" then return env.TUNING end
    if cache[name] then return cache[name] end
    local source=read_source(name..".lua")
    local fn=assert(loadstring(source,"game/"..name));setfenv(fn,env)
    local result=fn();cache[name]=result;return result
end
local cooking=env.require("cooking")
package.loaded.cooking=cooking;package.loaded["shadowself/control/foodplan"]=nil
local Food=require("shadowself/control/foodplan")
local jelly=assert(Food.Resolve("voltgoatjelly"));assert(Food.RequiresWarly(jelly))
local other=assert(Food.Resolve("dragonchilisalad_spice_garlic"));assert(Food.RequiresWarly(other) and other.base=="dragonchilisalad")
local counts={lightninggoathorn=1,honey=2,ice=1,dragonfruit=1,pepper=1,berries=2}
local function solve(product,ingredients)
    local co=Food.Solver("portablecookpot",product,ingredients)
    local ok,result
    repeat ok,result=coroutine.resume(co);assert(ok,result) until coroutine.status(co)=="dead"
    assert(result,product);return result
end
local list=solve("voltgoatjelly",counts);assert(Food.Unique("portablecookpot",list,"voltgoatjelly"))
list=solve("dragonchilisalad",{dragonfruit=1,pepper=1,berries=2})
assert(Food.Unique("portablecookpot",list,"dragonchilisalad"))
assert(not Food.Resolve("nightmarepie_spice_nonexistent"))
local specialties=0;local seasoned=0
for base in pairs(cooking.recipes.portablecookpot) do
    if not cooking.recipes.cookpot[base] then
        specialties=specialties+1;assert(Food.RequiresWarly(assert(Food.Resolve(base))),base)
    end
end
for product in pairs(cooking.recipes.portablespicer) do
    local dish=Food.Resolve(product)
    if dish then assert(dish.spice and Food.RequiresWarly(dish));seasoned=seasoned+1 end
end
assert(specialties>=10 and seasoned>=100)
print("PASS: actual installed game cooking tests, "..specialties.." Warly specialties, "..seasoned.." registered seasoned products; jelly and dragon-chili salad ingredient solutions")
