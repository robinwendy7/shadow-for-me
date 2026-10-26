-- Four observed failures: preparation starvation, unsafe pirate collection,
-- missing bone armour and exclusive swamp movement suppressing recovery.
local names={'actions','arena_prepare','arena_supply','arena_late_runtime','arena_scrappig','boneguard','navigation'}
local saved={};for _,n in ipairs(names) do saved[n]=package.loaded['shadowself/control/'..n] end
local oldTime=GetTime;local now=100;GetTime=function() return now end
local bag,slots,requests={},{},{}
local function ent(name,x,slot,condition)
 local e={prefab=name,pos=Vector3(x or 0,0,0),replica={},tags={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={IsHeld=function() return e.held end,classified={percentused={value=function() return condition or 100 end}}}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local p=ent('wes');p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetEquippedItem=function(_,slot) return slots[slot] end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 Self=function(_,e,action) assert(action==ACTIONS.EQUIP);requests[#requests+1]=e;return true end}
package.loaded['shadowself/control/arena_prepare']=nil
local Prepare=require('shadowself/control/arena_prepare')
local hat=ent('footballhat',0,EQUIPSLOTS.HEAD);local wood=ent('armorwood',0,EQUIPSLOTS.BODY)
local marble=ent('armormarble',0,EQUIPSLOTS.BODY);local cane=ent('cane');local staff=ent('staff_tornado')
local stops=0
local arena={wave=11,player=p,bridge={},healing={},StopCombat=function() stops=stops+1 end}
local state={arena=arena,player=p,buffs={}}
bag={hat,wood,marble}
assert(Prepare.Head(state) and requests[1]==hat,'empty head equips a real backup before preparation/recovery can starve it')
assert(Prepare.Head(state) and #requests==1,'an equipment request is not an equipment acknowledgement; retries throttled')
slots[EQUIPSLOTS.HEAD]=hat;assert(not Prepare.Head(state),'actual worn acknowledgement releases head recovery')
slots[EQUIPSLOTS.HEAD]=nil;state.buffs.pending={};now=101
assert(not Prepare.Head(state) and #requests==1,'pending confirmed-food transaction is not interrupted by emergency equipment')
state.buffs.pending=nil;arena.healing.pending={};assert(not Prepare.Head(state),'normal healing transaction also retains ownership')
arena.healing.pending=nil;slots[EQUIPSLOTS.HEAD]=hat
local fish=ent('merm',3)
local c={player=p,enemies={fish},plan={arena=true,arena_wave=function() return 5 end},bridge={PauseAttack=function() end}}
c.healing={pending={}};assert(not Prepare.Armor(c),'pending recovery is not interrupted by body equipment requests');c.healing=nil
assert(Prepare.Armor(c) and requests[#requests]==wood,'empty body restores useful carried protection; swamp policy still excludes marble')
slots[EQUIPSLOTS.BODY]=wood;assert(not Prepare.Armor(c),'actual body acknowledgement ends recovery')
local foodGoal;local checks=0;local beforeFoodRequests=#requests
package.loaded['shadowself/control/navigation']={Select=function(_,q) return q end}
state.context=c;state.food_window=1.3
arena.encounters={Move=function(_,q) foodGoal=q end}
arena.healing.Safe=function(_,_,q,window) checks=checks+1;assert(window==1.3);return q.x>=5.9 end
assert(Prepare.FoodMove(state,'food escape')=='hold' and foodGoal.x>=5.9 and checks>24 and #requests==beforeFoodRequests,
 'food preparation actively chooses a verified safe endpoint instead of waiting or issuing an unsafe eat')
package.loaded['shadowself/control/navigation']=saved.navigation

-- An unsafe remaining helmet must not freeze the original pirate controller.
local Supply=assert(loadfile('scripts/shadowself/control/arena_supply.lua'))()
local queen=ent('monkeyqueen',20);local spare=ent('footballhat',2,EQUIPSLOTS.HEAD)
local monkey=ent('powder_monkey',3);local floor={spare};local safe=true;local loots=0;local pickupGuard
arena={wave=5,instance='pirates',generation=1,running=true,player=p,bridge={},enemies={monkey},
 entities={queen,spare},items=floor,fire_zones={},encounters={FindCenter=function() return Vector3(0,0,0) end},
 StopCombat=function() end,Say=function() end,TrapReady=function() return false end,
 NearbyEnemies=function(self) return self.enemies end,
 Loot=function(_,items,_,guard) loots=loots+1;pickupGuard=guard;return true end}
bag={hat,wood,staff};slots[EQUIPSLOTS.HEAD]=hat;slots[EQUIPSLOTS.BODY]=wood
assert(not Supply.PirateOpening(arena) and arena.pirate_opening.ready and loots==0,
 'owned tornado and worn helmet release dangerous all-helmet collection into unchanged patrol/wind tactic')
assert(arena.pirate_opening.deferred[1]==spare and not Supply.PirateOpening(arena) and loots==0,
 'deferred extras are not retried while the fight continues')
arena.TrapReady=function() return true end;arena.enemies={}
assert(Supply.PirateOpening(arena) and loots==1 and arena.pirate_opening.collecting,'real rest reopens deferred collection')
spare.held=true;assert(not Supply.PirateOpening(arena) and not arena.pirate_opening.deferred,'actual inventory ownership completes deferred collection')

-- Bone armour outranks ordinary supplies; request still respects path and phase.
local bone=ent('armorskeleton',2,EQUIPSLOTS.BODY);local sword=ent('nightsword',1);sword.tags.weapon=true
local Inv=require('shadowself/control/arena_inventory')
assert(Inv.Priority(bone,10)>Inv.Priority(sword,10) and Inv.Priority(bone,11)>Inv.Priority(ent('nightmarefuel'),11))
bag={cane};slots={};arena.wave=10;arena.items={bone};arena.enemies={};arena.pirate_opening=nil
arena.healing={Safe=function() return safe end,Path=function() return safe end}
assert(Supply.BonePickup(arena) and pickupGuard(),'safe bone pickup is dispatched before weapon/fuel supply')
safe=false;assert(not pickupGuard() and not Supply.BonePickup(arena),'new danger invalidates delayed bone pickup')
safe=true;arena.generation=2;assert(not pickupGuard(),'generation transition invalidates delayed bone pickup')
bag={bone};assert(not Supply.BonePickup(arena),'actually owned bone armour suppresses duplicate pickup')
bag={};arena.wave=9;assert(not Supply.BonePickup(arena),'special bone pickup does not change earlier waves')

-- Shadow and scrap pigs retain distinct animation mechanisms.
local Runtime=assert(loadfile('scripts/shadowself/control/arena_late_runtime.lua'))()
local originalHealth=Runtime.Health;Runtime.Health=function() return 5000 end
package.loaded['shadowself/control/arena_late_runtime']=Runtime
local Pig=assert(loadfile('scripts/shadowself/control/arena_scrappig.lua'))()
package.loaded['shadowself/control/arena_scrappig']=Pig
local shadow=ent('daywalker',5);local animation='run_pre'
shadow.AnimState={IsCurrentAnimation=function(_,a) return a==animation end,GetCurrentAnimationFrame=function() return 0 end}
assert(Pig.Kind(shadow)=='pounce');animation='atk_slam_pre';assert(Pig.Kind(shadow)=='slam')
animation='laser_pre';assert(not Pig.Kind(shadow),'shadow pig never uses scrap pig laser state')
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
local patrolled=false
arena={wave=11,player=p,enemies={shadow},items={},bridge={},StopCombat=function() end,Say=function() end}
state={arena=arena,player=p,boss=shadow,route='shadow',context={},Cleared=function() return true end,
 Patrol=function() patrolled=true;return 'hold' end}
bag={};slots={}
assert(Finish.Pig(state,{shadow})=='hold' and patrolled and not Finish.Allowed(state,shadow),
 'missing bone armour cannot fall through to bare-body shadow boss output')
bag={bone};now=102
assert(Finish.Pig(state,{shadow})=='hold' and requests[#requests]==bone and not Finish.Allowed(state,shadow),
 'bone equip request alone does not authorize output')
slots[EQUIPSLOTS.BODY]=bone
assert(Finish.Pig(state,{shadow})==nil and Finish.Allowed(state,shadow),'actual bone equip acknowledgement releases normal shadow combat')
local evades=0;local shield=false
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end}
package.loaded['shadowself/control/boneguard']={Ready=function() return shield end}
state.context={player=p,enemies={shadow},hazards={}}
arena.encounters={Move=function() evades=evades+1 end};animation='atk_slam_pre'
assert(Pig.Dodge(state,{shadow}) and evades==1,'shadow slam preempts preparation while bone is cooling')
shield=true;assert(not Pig.Dodge(state,{shadow}) and evades==1,'ready bone retains the existing direct attack exception')
state.finish=true;state.reward={visited={},s=state};arena.healing=nil
assert(not Pig.Dodge(state,{shadow}),'ready bone permits existing shield-protected box opening')
state.reward.complete=true
assert(Pig.Dodge(state,{shadow}) and evades==2,'after box protection ends the staff finish again dodges shadow slam')
Runtime.Health=originalHealth
for _,n in ipairs(names) do package.loaded['shadowself/control/'..n]=saved[n] end
GetTime=oldTime
print('PASS: preparation recovery ownership, pirate unsafe/deferred loot, bone priority/path/phase guards, shadow equipment acknowledgement and distinct boss states')
