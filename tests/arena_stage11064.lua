local savedActions=ACTIONS;ACTIONS={EAT={},PICKUP={},EQUIP={},RUMMAGE={}}
local lateCache={};for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do lateCache[k]=package.loaded["shadowself/control/"..k];package.loaded["shadowself/control/"..k]=nil end
-- Real food tables, Healing.Tick and Arena:Loot; only server acknowledgements are simulated.
local keys={'actions','navigation','arena_food','arena_inventory','arena_stage11_food','supplies'}
local saved={};for _,name in ipairs(keys) do saved[name]=package.loaded['shadowself/control/'..name] end
local oldCooking=package.loaded.cooking
local oldTime,oldWorld,oldNet,oldSim,oldTuning=GetTime,TheWorld,TheNet,TheSim,TUNING
local now=0;GetTime=function() return now end
local constants={HEALING_TINY=1,HEALING_SMALL=3,HEALING_MEDSMALL=8,HEALING_MED=20,HEALING_MEDLARGE=30,
 HEALING_LARGE=40,HEALING_HUGE=60,HEALING_MOREHUGE=75,HEALING_SUPERHUGE=100,
 CALORIES_TINY=9.375,CALORIES_SMALL=12.5,CALORIES_MEDSMALL=18.75,CALORIES_MED=25,CALORIES_LARGE=37.5,
 CALORIES_HUGE=75,CALORIES_SUPERHUGE=150,SANITY_SMALL=5,SANITY_MED=15,SANITY_LARGE=33,SANITY_HUGE=50,
 BUFF_ELECTRICATTACK_DURATION=300,BUFF_ATTACK_DURATION=240}
setmetatable(constants,{__index=function() return 0 end})
local strings={};setmetatable(strings,{__index=function() return strings end})
local env=setmetatable({TUNING=constants,FOODTYPE={MEAT='MEAT',VEGGIE='VEGGIE',GOODIES='GOODIES'},STRINGS=strings},{__index=_G})
local function recipes(path) local fn=assert(loadstring(read_source(path)));setfenv(fn,env);return fn() end
package.loaded.cooking={recipes={cookpot=recipes('preparedfoods.lua'),portablecookpot=recipes('preparedfoods_warly.lua')}}
-- Food.Health reads these globals for perish/spice adjustments; default0 must not impersonate a spice table.
TUNING={BUFF_ELECTRICATTACK_DURATION=300,BUFF_ATTACK_DURATION=240}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheNet={GetPing=function() return 33 end,Disconnect=function() error('late food failure cannot disconnect the user') end}
TheSim={FindEntities=function() return {} end}
local current;local id=64000
local function ent(name,slot)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(0,0,0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 function e:GetBasicDisplayName() return self.prefab end
 e.AnimState={IsCurrentAnimation=function(_,name) return e.anim==name end,GetCurrentAnimationFrame=function() return 0 end}
 e.Transform={GetRotation=function() return 0 end}
 e.replica.inventoryitem={IsHeld=function() return e.held or false end,
  GetEquipRestrictedTag=function() end,GetWalkSpeedMult=function() return 1 end,
  classified={perish={value=function() return 62 end},percentused={value=function() return 100 end}}}
 if slot then e.replica.equippable={EquipSlot=function() return slot end,IsRestricted=function() return false end} end
 return e
end
local function action(kind,item,guard)
 current.commands[#current.commands+1]={kind=kind,item=item,guard=guard};return true
end
local A={Items=function() return current.bag end,
 Self=function(_,item,kind) return action(kind,item) end,
 Scene=function(_,item,kind,guard) return action(kind,item,guard) end,
 Stop=function() return true end,Move=function() current.moves=current.moves+1;return true end}
package.loaded['shadowself/control/actions']=A
package.loaded['shadowself/control/navigation']={Select=function(_,q) return q end,Safe=function() return current.safe end,
 Clearance=function() return 8 end,Radius=function() return 3 end,Risk=function() return 0 end}
for _,name in ipairs({'arena_food','arena_inventory','arena_stage11_food','supplies'}) do package.loaded['shadowself/control/'..name]=nil end
local Food=require('shadowself/control/arena_food')
local Supplies=require('shadowself/control/supplies')
local Healing=assert(loadfile('scripts/shadowself/control/arena_healing.lua'))()
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage11.lua'))()
local Arena=assert(loadfile('scripts/shadowself/control/arena.lua'))()
local function food(name,count,infinite)
 local e=ent(name);e.count=count or 1;e.infinite=infinite
 e.replica.stackable={StackSize=function() return e.count end,IsFull=function() return false end}
 return e
end
local function remove(list,item)
 for i=#list,1,-1 do if list[i]==item then table.remove(list,i) end end
end
local function add(f,item)
 item.held=true;f.bag[#f.bag+1]=item;if f.arena then remove(f.arena.items,item) end
end
local function start(hp,hunger,buffed)
 now=now+100
 local f={hp=hp,hunger=hunger or 120,sanity=190,bag={},commands={},moves=0,safe=true}
 current=f;local p=ent('wilson');f.player=p
 p.replica.health={GetCurrent=function() return f.hp end,Max=function() return 150 end,MaxWithPenalty=function() return 150 end}
 p.replica.hunger={GetCurrent=function() return f.hunger end,Max=function() return 150 end,GetPercent=function() return f.hunger/150 end}
 p.replica.sanity={GetCurrent=function() return f.sanity end,GetPercent=function() return f.sanity/200 end}
 p.components.playercontroller={IsBusy=function() return false end}
 local hat=ent('wathgrithr_improvedhat',EQUIPSLOTS.HEAD);f.hat=hat;add(f,hat)
 p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HEAD and f.hat end,
  GetItems=function() return f.bag end,GetEquips=function() return {f.hat} end,GetOverflowContainer=function() end,GetNumSlots=function() return 15 end,
  DropItemFromInvTile=function(_,item,whole) assert(whole==false);return action('drop',item) end}
 local arena=setmetatable({player=p,wave=11,route='shadow',running=true,instance='fixture064',generation=1,
  items={},enemies={},ignored={},fire_zones={},bridge={Running=function() return false end}},{__index=Arena});f.arena=arena
 function arena:StopCombat() self.stops=(self.stops or 0)+1 end
 function arena:Say(msg) self.message=msg end
 function arena:NearbyEnemies() return self.enemies end
 arena.encounters={FindCenter=function() return Vector3(0,0,0) end,
  Move=function(_,q,msg) f.moves=f.moves+1;arena.message=msg;return 'hold' end}
 f.healing=Healing(p);f.healing.Safe=function() return f.safe end;f.healing.Path=function() return f.safe end
 arena.healing=f.healing
 f.roster={};for i=1,4 do local e=ent('mermguard_shadow');e.pos=Vector3(i+10,0,0);f.roster[#f.roster+1]=e end
 arena.enemies=f.roster
 local s=Stage(arena);f.stage=s;s.opening_equipped=true;s.prepared=true;s.hat=hat
 if buffed then Supplies.Record(p,'voltgoatjelly_spice_chili','inventory_consumed') end
 return f
end
local function tick(f,delay)
 current=f;now=now+(delay or .2);return f.stage:Tick(f.roster)
end
local function count(f,kind,item)
 local n=0;for _,a in ipairs(f.commands) do if a.kind==kind and (not item or a.item==item) then n=n+1 end end;return n
end
local function wait_eat(f,item)
 for _=1,10 do
  tick(f,.4)
  if f.healing.pending and f.healing.pending.name==item.prefab then return end
 end
 error('expected actual EAT pending for '..item.prefab)
end
local function acknowledge_eat(f,item)
 assert(f.healing.pending and f.healing.pending.name==item.prefab)
 f.player.anim='eat';tick(f,.1);f.player.anim=nil
 f.hp=math.min(150,f.hp+Food.Health(item,f.player));f.hunger=math.min(150,f.hunger+Food.Hunger(item,f.player))
 if not item.infinite then item.count=item.count-1;if item.count<=0 then remove(f.bag,item);item.held=false end end
 tick(f,2)
end
-- These are the actual official client recipes: spicy jelly has3HP, not the old fake20HP fixture.
local f=start(38,100,true);local jelly=food('voltgoatjelly_spice_chili',1,false);add(f,jelly)
assert(Food.Health(jelly,f.player)==3 and Food.Hunger(jelly,f.player)==37.5)
assert(not f.healing:Choose(f.stage.context),'ordinary healing never chooses spicy jelly')
f.sanity=20;assert(not f.healing:SanityFood(f.stage.context),'spicy jelly is excluded from SAN recovery');f.sanity=190
f.stage.context.stage11_food_item=jelly
assert(not f.healing:Choose(f.stage.context),'a leftover food override cannot bypass buff-only recovery exclusion')
f.stage.context.stage11_food_mode='buff'
assert(f.healing:Choose(f.stage.context)==jelly,'explicit buff request remains legal')
f.stage.context.stage11_food_item=nil;f.stage.context.stage11_food_mode=nil
local meal=food('surfnturf',2,false);assert(Food.Health(meal,f.player)==60)
tick(f,1)
assert(count(f,ACTIONS.EAT,jelly)==0 and f.hp==38 and f.stage.recovering,'spicy jelly retains its real3HP nutrition but is never selected for healing')
assert(f.stage.food:Value(jelly,'health')==nil and f.stage.food:Value(jelly,'hunger')==nil and f.stage.food:Value(jelly,'buff')==100,'spicy jelly is buff-only, not ordinary recovery food')
assert(tick(f,1)=='hold' and f.stage.recovering,'no carried meal must keep the recovery lock')
f.arena.items={meal};tick(f,1)
assert(count(f,ACTIONS.PICKUP,meal)==1 and f.arena.pending_item==meal,'empty food reserve uses actual Arena:Loot PICKUP and waits for inventory')
tick(f,.4);assert(count(f,ACTIONS.EAT,meal)==0 and count(f,ACTIONS.PICKUP,meal)==1,'accepted PICKUP alone cannot become usable food or duplicate the request')
add(f,meal);wait_eat(f,meal);acknowledge_eat(f,meal)
assert(f.hp==98 and f.stage.recovering and not f.stage:Allowed(f.roster[1]),'98/150 is still below the actual75 percent recovery target')
wait_eat(f,meal);acknowledge_eat(f,meal)
assert(f.hp==150 and tick(f,1)=='fight' and not f.stage.recovering and f.stage:Allowed(f.roster[1]),'real60HP meals restore the original locked melee only after actual HP crosses75 percent')
-- Replacing an inefficient meal frees only the meal slot; tea remains reserved.
f=start(38,120,true);jelly=food('voltgoatjelly_spice_chili',5,true);meal=food('surfnturf',2,false)
local tea=food('sweettea',3,true);add(f,jelly);add(f,tea);f.arena.items={meal}
local oldMeal=food('fruitmedley',1,false);add(f,oldMeal)
tick(f,1)
assert(count(f,'drop',oldMeal)==1 and count(f,'drop',jelly)==0 and count(f,'drop',tea)==0,'better reserve replaces old meal while retaining chili and the dedicated tea slot')
tick(f,.4)
assert(count(f,'drop',oldMeal)==1 and count(f,ACTIONS.PICKUP,meal)==0,'unacknowledged DROP holds the food transaction instead of sending pickup prematurely')
remove(f.bag,oldMeal);oldMeal.held=false;tick(f,.4)
assert(count(f,ACTIONS.PICKUP,meal)==1 and count(f,'drop',tea)==0,'only actual inventory removal releases replacement PICKUP')
local pickup
for _,a in ipairs(f.commands) do if a.kind==ACTIONS.PICKUP and a.item==meal then pickup=a end end
assert(pickup and type(pickup.guard)=='function','late food pickup carries a delayed safety guard through Arena:Loot')
f.safe=false;assert(not pickup.guard(),'new danger cancels a delayed food pickup before dispatch');f.safe=true
add(f,meal);wait_eat(f,meal)
assert(count(f,'drop',tea)==0 and tea.held,'tea survives replacement and subsequent healing')
-- Full-health infinite food requires actual hunger recovery AND an observed eating animation.
f=start(150,30,true);jelly=food('surfnturf',5,true);add(f,jelly)
wait_eat(f,jelly)
assert(f.stage.hungry and not f.stage:Allowed(f.roster[1]),'low hunger opens a late-only replenishment lock even at full HP')
local originalCount=jelly.count;acknowledge_eat(f,jelly)
assert(f.hp==150 and f.hunger==67.5 and jelly.count==originalCount and not f.healing.pending,'observed eating plus actual hunger restoration acknowledges infinite food at full health')
wait_eat(f,jelly);acknowledge_eat(f,jelly);tick(f,1)
assert(f.hunger==105 and not f.stage.hungry,'hunger replenishment releases only after the65 percent target')
f=start(150,30,true);jelly=food('surfnturf',5,true);add(f,jelly);wait_eat(f,jelly)
f.hunger=70;tick(f,1.5)
assert(f.healing.pending,'unrelated hunger increase without an observed eat cannot acknowledge the requested meal')
-- A plain healing meal cannot impersonate spicy electric buffs to unlock combat.
f=start(38,100,false);meal=food('surfnturf',2,false);add(f,meal)
wait_eat(f,meal);acknowledge_eat(f,meal);wait_eat(f,meal);acknowledge_eat(f,meal)
assert(f.hp==150 and not f.stage.buffs:Ready() and tick(f,1)=='hold' and not f.stage:Allowed(f.roster[1]),'ordinary food recovery never substitutes for confirmed spicy jelly effects')
-- No food must fail explicitly after bounded waiting, not silently loop or disconnect.
f=start(38,120,false)
assert(tick(f,1)=='hold' and f.stage.recovering and not f.stage:Allowed(f.roster[1]))
assert(tick(f,43)=='hold','late food wait must allow its bounded recovery period')
local mode,message=tick(f,3)
assert(mode=='failed' and type(message)=='string' and message:find('人工',1,true),'45 seconds without food progress reports an explicit failure requiring manual handling')
assert(f.arena.instance=='fixture064' and f.arena.running,'failure leaves the character in the current instance without automatic disconnect or fabricated phase changes')
-- 第十一关起：辣冻+最高有效SAN料理双格，保留原茶格；复用实际进食确认。
local Inv=require('shadowself/control/arena_inventory')
local Sanity=assert(loadfile('scripts/shadowself/control/arena_sanity.lua'))()
f=start(150,120,true);current=f;f.arena.stage11=f.stage
jelly=food('voltgoatjelly_spice_chili',5,true);meal=food('surfnturf',2,true);tea=food('sweettea',2,true)
add(f,jelly);add(f,meal);add(f,tea)
assert(Food.Sanity(meal,f.player)==33 and not Inv.ExcessMeal(f.bag,f.player,11,false),
 'official33SAN surfnturf occupies its own slot beside chili and dedicated tea')
local weak=food('fruitmedley',1,false)
assert(not Inv.Want(weak,f.bag,f.player,11),'weaker SAN food cannot add a third meal slot')
assert(Inv.ExcessMeal({jelly,meal,tea,weak},f.player,11,false)==weak,'cleanup preserves chili and highest SAN meal')
assert(Inv.Discard({jelly,meal,tea},f.player,11,ent('lunarplanthat',EQUIPSLOTS.HEAD))==nil,
 'full-bag equipment pickup cannot discard the two protected meal slots')
f.sanity=100
assert(not f.healing:SanityFood(f.stage.context),'exactly100SAN does not trigger the new food rule')
f.sanity=99
assert(f.healing:Choose(f.stage.context)==meal,'below100 selects high SAN meal before the tea policy')
assert(Sanity.Tick(f.arena) and f.healing.pending and f.healing.pending.sanity_food and count(f,ACTIONS.EAT,meal)==1,
 'actual late supply tick starts one normal EAT request at full health')
f.player.anim='eat';now=now+.1;Sanity.Tick(f.arena)
f.player.anim=nil;now=now+1.5;Sanity.Tick(f.arena)
assert(f.healing.pending and count(f,ACTIONS.EAT,meal)==1,'accepted request and animation alone cannot confirm an infinite meal or duplicate EAT')
f.sanity=132;now=now+.1;Sanity.Tick(f.arena)
assert(not f.healing.pending and meal.count==2,'observed eating plus actual SAN restoration confirms infinite food without HP or stack change')
f.sanity=90;f.safe=false;now=now+1
assert(not Sanity.Tick(f.arena) and count(f,ACTIONS.EAT,meal)==1,'unsafe windup does not force EAT or block existing movement')
f.safe=true;f.stage.buffs.pending={}
assert(not Sanity.Tick(f.arena) and count(f,ACTIONS.EAT,meal)==1,'in-flight spicy jelly owns its existing action until acknowledged')
f.stage.buffs.pending=nil
remove(f.bag,meal);f.sanity=190;f.arena.items={meal};now=now+1
assert(Sanity.Tick(f.arena) and count(f,ACTIONS.PICKUP,meal)==1,'safe ground high-SAN meal is reserved even before SAN falls below100')
local icecream=food('icecream',1,false)
assert(Food.Sanity(icecream,f.player)==50 and Inv.Want(icecream,{jelly,meal},f.player,11),
 'official50SAN icecream can upgrade the reserve even when it is not selected as a healing meal')
f.arena.wave=10;f.sanity=50
assert(not f.healing:SanityFood(f.stage.context) and not Sanity.Tick(f.arena),'waves1 through10 retain previous food handling')
print('PASS: late chili plus highest-SAN meal slots; threshold100, real33SAN recipe, no duplicate EAT and infinite-food SAN acknowledgement')
-- Optional SAN reserve acquisition cannot take over the central pig ring.
f=start(150,120,true);f.stage.route='lunar';f.stage.boss=ent('daywalker2')
f.stage.Cleared=function() return true end;f.arena.stage11=f.stage;f.arena.items={food('surfnturf',2,false)}
f.sanity=190;local beforeReserve=count(f,ACTIONS.PICKUP)
assert(not Sanity.Tick(f.arena) and count(f,ACTIONS.PICKUP)==beforeReserve,
 'solo scavenger pig never diverts central orbit to collect a spare ground SAN meal')
-- Latest real-log regression: low health + no food must not trap a solo lunar pig in an outer45s stop.
f=start(38,120,true);f.stage.route='lunar';local solo=ent('daywalker2');f.stage.boss=solo
f.stage.Cleared=function() return true end;f.arena.enemies={solo};f.arena.items={}
local bone=ent('armorskeleton',EQUIPSLOTS.BODY);add(f,bone)
local originalEquipped=f.player.replica.inventory.GetEquippedItem
f.player.replica.inventory.GetEquippedItem=function(inv,slot) if slot==EQUIPSLOTS.BODY then return bone end;return originalEquipped(inv,slot) end
f.stage.recovering=true
assert(not f.stage:Recovery() and not f.stage.recovering and not f.stage.feeding and not f.stage.failed,
 'solo lunar pig without safe healing food returns to bone combat rather than food wait45')
f.stage.route='shadow';assert(f.stage:Recovery(),'other branches retain their existing emergency food protection')
for _,name in ipairs(keys) do package.loaded['shadowself/control/'..name]=saved[name] end
package.loaded.cooking=oldCooking
GetTime,TheWorld,TheNet,TheSim,TUNING=oldTime,oldWorld,oldNet,oldSim,oldTuning
for k,v in pairs(lateCache) do package.loaded["shadowself/control/"..k]=v end
for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do if lateCache[k]==nil then package.loaded["shadowself/control/"..k]=nil end end
ACTIONS=savedActions
print('PASS: official3HP jelly,38HP lock across depletion, safe60HP food replacement with DROP/PICKUP ACK and tea retention, full-health infinite hunger acknowledgement, buff gate and bounded explicit food failure')
