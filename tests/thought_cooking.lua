-- New local evaluator + general Warly cooking workflow. Containers below only simulate
-- authoritative responses; this is deliberately not presented as live game coverage.
local now=1000;GetTime=function() return now end
TheWorld={state={cycles=3,phase="night",season="winter"}}
local T=require("shadowself/thought")
local r={options={},owner={replica={}},context={hunger=.9,health=.8,sanity=.7,danger=0},memory={last_eat=990}}
local brain=T(r)
local parse=brain:Parse("我饿了哈哈","hunger")
assert(parse.joking and parse.emotion=="hunger" and parse.intent=="emotion")
assert(not brain:Parse("我饿了，不是开玩笑","hunger").joking)
local first=brain:Choose("hunger",{"找点吃的。"},true,parse,"original",{})
assert(first.reply:find("刚吃",1,true) and first.factors.context==1)
r.context.hunger=.1;r.memory.last_eat=0
local second=brain:Choose("hunger",{"找点吃的。"},true,parse,"original",{})
assert(second.reply:find("确实快饿空",1,true) and second.reply~=first.reply)
brain:Observe("death");assert(brain:Snapshot().mood=="sad")
assert(brain:Choose("idle",{"天黑了。"},false,nil,"original",{}).action=="silence")
brain:Observe("victory");assert(brain:Snapshot().mood~="sad")
for i=1,30 do brain:Remember(brain:Parse("我好孤独","lonely"),"先歇会儿。") end
assert(#brain.m.history==12 and brain.m.interactions==30 and brain.m.emotions.lonely)
now=now+100;assert(brain:Choose("lonely",{"一个人也能走。"},true,brain:Parse("我好孤独","lonely"),"original",{}).reply:find("上次",1,true))
local Q=require("shadowself/questions")
for _,text in ipairs({"你是我吗","你知道自己是谁吗","你打得过boss吗","你会做饭吗","别人看得到你吗","你是我的第二人格吗","你好厉害呀","今天星期几","你能做什么菜"}) do
    assert(Q.Match(text,r,brain),text)
end
local weekday=Q.Match("今天星期几",r,brain)
assert(weekday:find("星期",1,true) and not weekday:find("@",1,true))
local fresh={social={history={},emotions={},interactions=90,valence=.5}}
r.memory=fresh;brain:Bind();assert(brain.m==fresh.social and brain.m.interactions==90)
print("PASS: fresh context, recent-meal vs real hunger, negated joke, mood, silence, bounded memory and factual questions")

-- Real rule module with a controlled recipe table, including all four spice kinds
-- and another professional-chef dish (not only voltgoatjelly).
local cooking={ingredients={meat={tags={meat=1}},berries={tags={fruit=1}},ice={tags={}},pepper={tags={veggie=1}}},recipes={cookpot={},portablecookpot={},portablespicer={}}}
local meatballs={priority=1,test=function(_,names,tags) return tags.meat and tags.meat>=1 end}
cooking.recipes.cookpot.meatballs=meatballs;cooking.recipes.portablecookpot.meatballs=meatballs
cooking.recipes.portablecookpot.voltgoatjelly={priority=30,test=function(_,n) return n.berries==4 end}
cooking.recipes.portablecookpot.dragonchilisalad={priority=30,test=function(_,n) return n.ice==4 end}
for _,base in ipairs({"meatballs","voltgoatjelly","dragonchilisalad"}) do
    for _,spice in ipairs({"spice_chili","spice_garlic","spice_salt","spice_sugar"}) do cooking.recipes.portablespicer[base.."_"..spice]={} end
end
cooking.IsCookingIngredient=function(k) return cooking.ingredients[k]~=nil end
package.loaded.cooking=cooking;package.loaded["shadowself/control/foodplan"]=nil
STRINGS={NAMES={MEATBALLS="肉丸",DRAGONCHILISALAD="炽热龙椒沙拉",VOLTGOATJELLY="伏特羊角冻"}}
local powder={}
for _,s in ipairs({"chili","garlic","salt","sugar"}) do powder["spice_"..s]={name="spice_"..s,ingredients={{type=s=="chili" and "pepper" or s,amount=3}}} end
GetValidRecipe=function(k) return powder[k] end
local Food=require("shadowself/control/foodplan")
assert(Food.Parse("帮我做饭")=="ask")
assert(Food.Resolve("肉丸").base=="meatballs")
assert(Food.RequiresWarly(Food.Resolve("炽热龙椒沙拉")))
assert(not Food.RequiresWarly(Food.Resolve("肉丸")))
for _,case in ipairs({{"辣羊角冻","spice_chili"},{"蒜香炽热龙椒沙拉","spice_garlic"},{"咸肉丸","spice_salt"},{"甜肉丸","spice_sugar"},{"肉丸撒辣椒粉","spice_chili"}}) do
    local dish=assert(Food.Resolve(case[1]),case[1]);assert(dish.spice==case[2] and Food.RequiresWarly(dish))
    assert(Food.PowderIngredients(dish.spice))
end
assert(not Food.Resolve("辣不存在的菜") and not Food.Resolve("spice_chili"))
assert(Food.Unique("cookpot",{"meat","ice","ice","ice"},"meatballs"))
cooking.recipes.cookpot.ambiguous={priority=1,test=meatballs.test}
assert(not Food.Unique("cookpot",{"meat","ice","ice","ice"},"meatballs"),"priority ties are rejected")
cooking.recipes.cookpot.ambiguous=nil
local solver=Food.Solver("cookpot","meatballs",{meat=1,ice=2})
local ok,result=coroutine.resume(solver);assert(ok and not result,"cannot invent fourth ingredient")
solver=Food.Solver("cookpot","meatballs",{meat=1,ice=3})
ok,result=coroutine.resume(solver);assert(ok and #result==4)

local pending,actions={},0
local direct_moves,bag_moves,open_calls={},0,{}
local function later(fn) pending[#pending+1]=fn end
local function flush() local list=pending;pending={};for _,fn in ipairs(list) do fn() end end
local function item(k,n) return {prefab=k,replica={stackable={StackSize=function() return n end}}} end
local player={prefab="warly",replica={},components={playercontroller={IsBusy=function() return false end}}}
function player:GetPosition() return {x=0,y=0,z=0} end
function player:GetDistanceSqToInst(e) return e.distance or 1 end
local function container()
    local c={items={},opened=false,widget={}}
    function c:GetItems() return (self.opened or self.inventory) and self.items or {} end
    function c:CanBeOpened() return not self.locked end
    function c:CanTakeItemInSlot() return not self.reject_food end
    function c:IsReadOnlyContainer() return false end
    function c:IsOpenedBy() return self.opened end
    function c:Close() self.opened=false end
    function c:GetOverflowContainer() return nil end
    function c:GetActiveItem() return nil end
    function c:MoveItemFromCountOfSlot(slot,target,count)
        assert(count>=1);actions=actions+1
        assert(self.inventory or self.opened,"source container must actually be open")
        assert(target,"host transfer must explicitly name the player or destination container")
        local it=self.items[slot];assert(it)
        if not self.inventory then
            if target==player then bag_moves=bag_moves+count
            else direct_moves[it.prefab]=(direct_moves[it.prefab] or 0)+count end
        end
        later(function()
            local it=self.items[slot];assert(it,"server processes queued source-slot transfers in order")
            local n=it.replica.stackable:StackSize();local moved=math.min(n,count);self.items[slot]=n>moved and item(it.prefab,n-moved) or nil
            local dest=target==player and player.replica.inventory or target.replica.container
            assert(self.inventory or self.opened,"source remains open until transfer confirmation")
            assert(dest.inventory or dest.opened,"destination must be open for native transfer")
            local i=1;while dest.items[i] do i=i+1 end;dest.items[i]=item(it.prefab,math.min(it.replica.stackable:StackSize(),count))
        end)
    end
    return c
end
player.replica.inventory=container();player.replica.inventory.inventory=true
local function entity(prefab)
    local e={prefab=prefab,tags={},replica={container=container()}}
    function e:IsValid() return true end
    function e:HasTag(t) return self.tags[t] end
    function e:GetPosition() return {x=1,y=0,z=0} end
    return e
end
local pot,fridge,grinder,spicer=entity("portablecookpot"),entity("icebox"),entity("portableblender"),entity("portablespicer")
local empty,scale,chest,custom=entity("icebox"),entity("dragonflychest"),entity("treasurechest"),entity("custom_storage")
empty.distance=.1;fridge.distance=1;scale.distance=2;chest.distance=3;custom.distance=4
empty.replica.container.opened=true -- player's currently open destination, captured before opening cookpot
fridge.replica.container.items={item("meat",2)}
scale.replica.container.items={item("ice",6)}
chest.replica.container.items={item("pepper",1)}
custom.replica.container.items={item("pepper",2)}
local ready=entity("cookpot");ready.distance=4;ready.tags.donecooking=true;ready.replica.container.locked=true;ready.product="meatballs";ready.amount=3
local readyspicer=entity("portablespicer");readyspicer.distance=5;readyspicer.tags.donecooking=true;readyspicer.replica.container.locked=true;readyspicer.product="meatballs_spice_garlic"
local entities={pot,fridge,grinder,spicer,empty,scale,chest,custom,ready,readyspicer}
TheSim.FindEntities=function() return entities end
local function count(p,k)
    local n=0;for _,it in pairs(p.replica.inventory.items) do if it.prefab==k then n=n+it.replica.stackable:StackSize() end end;return n
end
local function insert(k,n)
    local c=player.replica.inventory;local i=1;while c.items[i] do i=i+1 end;c.items[i]=item(k,n)
end
ACTIONS={RUMMAGE={},HARVEST={}}
local callbacks={}
package.loaded["shadowself/control/actions"]={Count=count,Move=function() actions=actions+1 end,Scene=function(p,e,action,valid)
    actions=actions+1;callbacks[#callbacks+1]=valid
    later(function()
        if not valid() then return end
        if action==ACTIONS.RUMMAGE then
            for _,other in ipairs(entities) do
                local function kind(v) return (v.prefab=="cookpot" or v.prefab=="portablecookpot" or v.prefab=="portablespicer") and "cooker" or "chest" end
                if other.prefab==e.prefab or kind(other)==kind(e) then other.replica.container.opened=false end
            end
            e.replica.container.opened=true;open_calls[e]=(open_calls[e] or 0)+1
        else
            assert(e.tags.donecooking);insert(e.product,e.amount or 1);e.tags.donecooking=nil
            -- Readiness may replicate later than inventory changes.
            later(function() e.replica.container.locked=false end)
        end
    end);return true
end}
package.loaded["shadowself/control/actions"].HarvestCooked=function(p,e,guard)
    assert(e:HasTag("donecooking"));return package.loaded["shadowself/control/actions"].Scene(p,e,ACTIONS.HARVEST,guard)
end
package.loaded["shadowself/control/actions"].TransferBatch=function(p,target,steps,guard)
    if not guard() then return false end
    assert(#steps<=4 and target.replica.container.opened)
    for _,step in ipairs(steps) do step.source:MoveItemFromCountOfSlot(step.slot,target,1) end
    return true
end
local starts,grinds=0,0;local overlap=false
for _,e in ipairs({pot,spicer,ready,readyspicer}) do
    e.replica.container.widget.buttoninfo={validfn=function() return true end,fn=function()
        -- Native RPC/button requests execute on the server after preceding queued transfers.
        later(function()
            starts=starts+1;local items=e.replica.container.items
            local seasoning=e.prefab=="portablespicer"
            if not seasoning then for _,other in ipairs({pot,ready}) do
                if other~=e and other.finish and other.finish>now then overlap=true end
            end end
            e.product=seasoning and "meatballs_spice_chili" or "meatballs"
            local n=0;for _ in pairs(items) do n=n+1 end
            assert(seasoning and n==2 or not seasoning and n==4,"cook request follows complete batch in server queue")
            e.replica.container.items={};e.replica.container.opened=false;e.replica.container.locked=true
            e.finish=now+(seasoning and 3 or 35)
        end)
    end}
end
player.replica.builder={KnowsRecipe=function() return true end,HasIngredients=function() return count(player,"pepper")==3 end,MakeRecipeFromMenu=function(_,recipe)
    assert(recipe.name=="spice_chili");grinds=grinds+1
    later(function()
        for slot,it in pairs(player.replica.inventory.items) do if it.prefab=="pepper" then player.replica.inventory.items[slot]=nil end end
        insert("spice_chili",2)
    end)
end}
package.loaded["shadowself/control/cooking"]=nil
local Cooking=require("shadowself/control/cooking")
local cook=Cooking(player,{dish=Food.Resolve("辣肉丸"),target="辣肉丸"},function() end)
local status,why
for i=1,1200 do
    now=now+.2;status,why=cook:Tick()
    assert(status~="failed",why)
    -- Wait one extra tick before every inventory response: no duplicate transfer allowed.
    if #pending>0 then
        local before=actions;local transfer=cook.grab or cook.transfer or cook.deposit
        now=now+.1;cook:Tick()
        if transfer then assert(actions==before,"waits for authoritative item transfer") end
    end
    flush()
    for _,e in ipairs({pot,spicer,ready,readyspicer}) do
        assert(not e.tags.cooking,"native cookpots never replicate a cooking tag")
        if e.finish and now>=e.finish then e.finish=nil;e.tags.donecooking=true end
    end
    if status=="done" then break end
end
assert(status=="done",why or cook.phase)
assert(overlap,"second distinct pot starts before first pot finishes; cooking is concurrent")
local nearest=pot.distance;pot.distance=.5
cook.last_used[pot]=now;cook.last_used[ready]=nil
assert(cook:Find({cookpot=true,portablecookpot=true})==ready,"unused empty pot wins over repeatedly refilling the closest pot")
pot.distance=nearest
assert(cook.completed==2 and count(player,"meatballs_spice_chili")==0 and count(player,"spice_chili")==0 and starts==4 and grinds==1)
local stored=0
for _,e in ipairs({empty,fridge,scale,chest,custom}) do for _,it in pairs(e.replica.container.items) do if it.prefab=="meatballs_spice_chili" then stored=stored+it.replica.stackable:StackSize() end end end
assert(stored==2,"stores both finished meals in initially open container")
local saved={};for _,it in pairs(empty.replica.container.items) do saved[it.prefab]=(saved[it.prefab] or 0)+it.replica.stackable:StackSize() end
assert(cook.collected==2 and saved.meatballs==3 and saved.meatballs_spice_garlic==1,"harvests preexisting ready pots/spicers, identifies actual products and stores all stack units")
assert(count(player,"meat")==0 and count(player,"ice")==0 and count(player,"pepper")==0,"uses fridge, dragonfly chest, regular chest and containers without known prefab names")
assert(why:find("2份",1,true),why)
cook:Cancel();assert(not pot.replica.container.opened and not spicer.replica.container.opened)
-- A different container opened by the player while cooking takes precedence.
chest.replica.container.opened=true;chest.replica.container.reject_food=true
local output=Cooking(player,{dish=Food.Resolve("辣肉丸"),target="辣肉丸"},function() end)
output.output_store={inst=empty,counts={}};output.completed=1
assert(output:OutputDestination().inst==chest,"current open container overrides previous destination")
output.stores={{inst=chest,counts={}}};output.cooker=pot;output:Stage("waiting")
assert(output:Tick()=="running");chest.replica.container.opened=false
assert(output:OutputDestination().inst==chest,"remembers changed destination if walking to harvest closes it")
chest.replica.container.opened=true
insert("meatballs_spice_chili",1);output:Stage("store_output")
assert(output:Tick()=="running");now=now+.6
local ended,message=output:Tick()
assert(ended=="done" and message:find("不接受",1,true) and count(player,"meatballs_spice_chili")==1,"rejected output remains in inventory; no more cooking")
output:Cancel();chest.replica.container.opened=false;chest.replica.container.reject_food=false
-- No empty pot: wait for another already-running cooker, then harvest it.
local all=entities;entities={readyspicer,empty}
readyspicer.tags.donecooking=nil;readyspicer.replica.container.locked=true
local waiting=Cooking(player,{dish=Food.Resolve("肉丸"),target="肉丸"},function() end)
assert(waiting:Tick()=="running" and waiting.phase=="waiting_existing","does not stop just because all cookers are occupied")
now=now+20;assert(waiting:Tick()=="running" and waiting.phase=="waiting_existing")
readyspicer.tags.donecooking=true;assert(waiting:Tick()=="running" and waiting.phase=="harvest")
-- Tag can clear before the inventory update; clearing alone is not success.
waiting.sent=now;readyspicer.tags.donecooking=nil
assert(waiting:Tick()=="running" and waiting.phase=="harvest","waits for food inventory after pot clears")
insert("meatballs_spice_garlic",1)
assert(waiting:Tick()=="running" and waiting.phase=="store_output" and waiting.output_product=="meatballs_spice_garlic")
waiting:Cancel();readyspicer.replica.container.locked=false;entities=all
player.prefab="wilson"
assert(select(1,Cooking(player,{dish=Food.Resolve("炽热龙椒沙拉")},function() end):Tick())=="failed","all specialty dishes require Warly")
player.prefab="warly"
-- Paused combat invalidates pre-action callbacks and resumes the same cooking stage.
local paused=Cooking(player,{dish=Food.Resolve("肉丸"),target="肉丸"},function() end)
local token=paused.token;paused:Pause();assert(paused.token~=token);now=now+100;paused:Resume();assert(paused.token and paused.token~=token and now-paused.since<1)
local revoked=Cooking(player,{dish=Food.Resolve("肉丸")},function() end)
revoked:Open(pot);local cb=callbacks[#callbacks];revoked:Cancel();assert(not cb(),"cancel revokes delayed native action")
print("PASS: concurrent distinct pots before first completion; fair empty-pot rotation; powder reserved per pending base meal; exhaustion waits for all cooked/seasoned output; existing harvest, synchronized storage and cancel")

-- One nearby fridge stays open while two different pots are filled directly.
local saved_entities=entities
local box,pot1,pot2=entity("icebox"),entity("cookpot"),entity("portablecookpot")
entities={box,pot1,pot2}
box.replica.container.items={item("meat",2),item("ice",6)}
local pipeline=Cooking(player,{dish=Food.Resolve("肉丸"),target="肉丸"},function() end)
pipeline.stores={{inst=box,counts={meat=2,ice=6},inspected=true}}
local before_bag=bag_moves;local before_meat=direct_moves.meat or 0;local before_ice=direct_moves.ice or 0
for _,target in ipairs({pot1,pot2}) do
    local filled
    for i=1,120 do
        now=now+.2;local why;filled,why=pipeline:Fill(target,{meat=1,ice=3})
        assert(filled~=nil,why);flush()
        if filled then break end
    end
    assert(filled,"direct fill completes")
    pipeline:PrepareNext()
    assert(box.replica.container.opened,"batch transition preserves nearby storage")
end
assert(open_calls[box]==1,"one source stays open throughout two nearby pots")
assert(bag_moves==before_bag and (direct_moves.meat or 0)-before_meat==2 and (direct_moves.ice or 0)-before_ice==6,"all eight ingredients go storage to pots; none pass through inventory")
pipeline:Cancel();assert(not box.replica.container.opened,"cancel closes storage opened by this session")
-- A distant source falls back to taking a whole ingredient requirement in one visit.
local farbox,far_pot=entity("icebox"),entity("cookpot")
function farbox:GetPosition() return {x=10,y=0,z=0} end
entities={farbox,far_pot};farbox.replica.container.items={item("ice",3)}
local fallback=Cooking(player,{dish=Food.Resolve("肉丸"),target="肉丸"},function() end)
fallback.stores={{inst=farbox,counts={ice=3},inspected=true}}
local bag_before=bag_moves
for i=1,120 do
    now=now+.2;local ok,why=fallback:Fill(far_pot,{ice=3});assert(ok~=nil,why);flush()
    if ok then break end
end
assert(bag_moves-bag_before==3 and open_calls[farbox]==1 and fallback:Snapshot(far_pot.replica.container).ice==3,"far storage takes three units in one withdrawal then fills pot normally")
fallback:Cancel();entities=saved_entities
-- Four confirmed ingredients in <1 second from an already synchronized open box.
local speedbox,speedpot=entity("icebox"),entity("cookpot")
entities={speedbox,speedpot};speedbox.replica.container.opened=true;speedpot.replica.container.opened=true
speedbox.replica.container.items={item("meat",1),item("ice",3)}
local fast=Cooking(player,{dish=Food.Resolve("肉丸"),target="肉丸"},function() end)
local speedstore={inst=speedbox,counts={meat=1,ice=3},inspected=true,read_ready=true}
fast.stores={speedstore};local begin=now;local complete
local first=actions
assert(fast:Fill(speedpot,{meat=1,ice=3})==false)
assert(actions-first==4 and #pending==4,"all four transfers are submitted in the same scheduler call")
assert(not next(speedpot.replica.container.items),"batch does not fake local pot contents")
fast:Fill(speedpot,{meat=1,ice=3});assert(actions-first==4,"no repeated batch before server response")
flush()
for i=1,40 do
    now=now+.05
    local ok,why=fast:Fill(speedpot,{meat=1,ice=3});assert(ok~=nil,why)
    -- One in-flight transfer only, even if the scheduler runs twice before the response.
    local n=actions;fast:Fill(speedpot,{meat=1,ice=3});assert(actions==n,"no duplicate request before server confirmation")
    flush()
    if ok then complete=now;break end
end
assert(complete and complete-begin<=1.01,"four items should fill within one second, got "..tostring(complete and complete-begin))
assert(fast:Snapshot(speedpot.replica.container).ice==3 and fast:Snapshot(speedpot.replica.container).meat==1)
-- Closing/reopening invalidates the ready session; a new sync wait still happens.
speedbox.replica.container.opened=false
assert(not fast:ReadStore(speedstore) and not speedstore.read_ready,"reopening must wait for contents again")
flush();fast:Cancel();entities=saved_entities
print("PASS: four ingredients submitted in the same call; acknowledged at 50ms response; no duplicate in-flight request; reopened storage synchronization preserved")
print("PASS: native chest/cooker coexistence; eight direct ingredients across two pots; one fridge open; far-container batch withdrawal; native open-source/destination checks; cancel cleanup")

local hits={offers=0,lines=0};local ctime=now
local care_runtime={dead=false,dialogue={GetPersonality=function() return {code="INFP"} end},control={}}
function care_runtime.control:Say() hits.lines=hits.lines+1 end
function care_runtime.control:OfferCombat() hits.offers=hits.offers+1;self.pending={plan={defensive=true}};return true end
local care=require("shadowself/concern")(care_runtime)
care:Hit();now=now+.1;care:Hit();assert(#care.hits==1,"dedupe animation plus sampled hit")
now=now+1;care:Hit();now=now+1;care:Hit()
assert(hits.offers==1 and not care_runtime.control.phase,"care asks, never enters possession")
now=now+6;care:Hit();assert(hits.lines==0 and hits.offers==1,"pending combat request has no overlapping concern speech")
print("PASS: repeated hits ask consent; ongoing care without forced possession or duplicate requests")
