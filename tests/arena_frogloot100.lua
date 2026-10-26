local oldTime,oldWorld,oldSim=GetTime,TheWorld,TheSim
local key='shadowself/control/actions';local oldA=package.loaded[key]
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local id=100000
local function ent(name)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(0,0,0),tags={},replica={},components={},held=false}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={IsHeld=function() return e.held end}
 return e
end
local p=ent('wilson');p.components.playercontroller={IsBusy=function() return false end}
local whip,wood,meal,split=ent('whip'),ent('armorwood'),ent('dragonpie'),ent('dragonpie')
wood.replica.equippable={EquipSlot=function() return EQUIPSLOTS.BODY end};wood.tags.armor=true
whip.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end};whip.tags.weapon=true
local bag,equips={},{};local scenes,eqs,stops={},{},0
p.replica.inventory={GetEquippedItem=function(_,slot) return equips[slot] end,GetItems=function() return bag end,
 GetNumSlots=function() return 15 end,GetItemInSlot=function(_,i) return bag[i] end}
package.loaded[key]={Items=function() local r={};for _,e in pairs(bag) do r[#r+1]=e end;for _,e in pairs(equips) do r[#r+1]=e end;return r end,
 Scene=function(_,e,action,guard) scenes[#scenes+1]={item=e,guard=guard};return true end,
 Self=function(_,e,action) assert(action==ACTIONS.EQUIP);eqs[#eqs+1]=e;return true end,
 Stop=function() stops=stops+1 end}
local F=assert(loadfile('scripts/shadowself/control/arena_frogloot.lua'))()
local Arena=assert(loadfile('scripts/shadowself/control/arena.lua'))()
local W=require('shadowself/control/arena_whip');local Policy=require('shadowself/control/arena_policy')
local frog,merm=ent('frog'),ent('merm');local foes={frog,merm};local snapshot={instance='frog100',generation=3,wave=2,intermission=false}
local arena={player=p,wave=2,instance='frog100',generation=3,running=true,whip=W(),ignored={},items={meal,wood,whip},enemies=foes,fire_zones={},
 adapter={Snapshot=function() return snapshot end},NearbyEnemies=function() return foes end,StopCombat=function() end,Say=function() end}
arena.Inventory=Arena.Inventory;arena.Want=Arena.Want;arena.TrapReady=Arena.TrapReady;arena.CancelTrapPickup=Arena.CancelTrapPickup;arena.Loot=Arena.Loot
p._shadowself_arena_move_owner=arena;arena.whip:Update(2,foes,false,foes)
F.Update(arena,snapshot);assert(F.Opening(arena) and scenes[1].item==whip and scenes[1].guard(),'actual opening calls real loot for whip before food or armor')
whip.held=true;bag={whip};now=.3;F.Update(arena,snapshot)
assert(F.Opening(arena) and scenes[2].item==wood and scenes[2].guard(),'confirmed whip acquisition prioritizes actual wood armor pickup')
wood.held=true;bag={whip,wood};now=.6;F.Update(arena,snapshot)
assert(F.Opening(arena) and eqs[1]==wood and not arena.frog_loot.ready and not arena.pending_item,'real inventory ACK clears pickup ownership and requests wood equip without assuming success')
equips[EQUIPSLOTS.BODY]=wood;bag={whip};now=1;F.Update(arena,snapshot)
assert(not F.Opening(arena) and arena.frog_loot.ready and Policy.PickupAllowed(wood,2,p),'actual body slot confirms opening and carried armor remains usable')
meal.held=true;bag={whip,meal};F.Update(arena,snapshot)
whip.held=false;wood.held=false;bag={meal};equips={};now=2;F.Update(arena,snapshot)
assert(not Policy.PickupAllowed(whip,2,p) and not Policy.PickupAllowed(wood,2,p),'weapons and armor observed on player cannot be immediately reclaimed after frog loss')
assert(not Policy.PickupAllowed(split,2,p),'stack-split new GUID of carried food also waits until rest')
assert(Policy.PickupAllowed(meal,2,p),'held food is not disabled by a pickup-only restriction')
local count=#scenes;arena.pending_item=wood;arena.pick_deadline=99
assert(not arena:Loot({whip,wood,split}) and #scenes==count and not arena.pending_item and stops>0,'real general loot cancels stale dropped-item pickup and does not steal battle control')
TheSim={FindEntities=function() return {whip,wood} end}
local c={player=p,plan={arena=true,arena_wave=function() return 2 end,arena_ground=function() return {whip,wood} end},
 gear={Owned=function() return false end},actions={SafePoint=function() return true end},enemies={},hazards={},bridge={PauseAttack=function() error('deferred pickup must not pause attacks') end}}
local Tools=assert(loadfile('scripts/shadowself/control/arena_tools.lua'))()
assert(not Tools.Recover(c,'whip') and #scenes==count,'tool recovery uses the same delayed-recovery gate')
local Mechanisms=assert(loadfile('scripts/shadowself/control/mechanisms.lua'))();local mech=Mechanisms(c)
mech.last_weapon=whip;mech.pickup=whip;mech.pickup_until=99
assert(not mech:Pickup() and not mech.pickup and #scenes==count,'weapon/armor recovery also cancels its prior pickup without reissuing it')
foes={};arena.whip:Update(2,{},false,{})
F.Update(arena,snapshot);assert(not Policy.PickupAllowed(wood,2,p),'empty local scan alone never releases frog-drop recovery')
snapshot.intermission=true;now=10;F.Update(arena,snapshot)
assert(Policy.PickupAllowed(wood,2,p) and arena:Loot({wood},true) and scenes[#scenes].item==wood and scenes[#scenes].guard(),'server rest plus no live monsters releases normal retained-item pickup')
local delayed=scenes[#scenes].guard;snapshot.intermission=false;foes={frog};F.Update(arena,snapshot)
assert(not delayed(),'renewed combat cancels an unexecuted recovery request')
arena.wave=3;F.Update(arena,snapshot);assert(not arena.frog_loot and Policy.PickupAllowed(wood,3,p),'other waves are unchanged')
arena.wave=2;arena.whip=W();arena.whip:Update(2,{ent('walrus')},false,{})
F.Update(arena,snapshot);assert(not arena.frog_loot and Policy.PickupAllowed(wood,2,p),'other second-wave encounters are unchanged')
p._shadowself_arena_move_owner=nil;package.loaded[key]=oldA;GetTime,TheWorld,TheSim=oldTime,oldWorld,oldSim
print('PASS: actual whip/wood opening order and equip ACK, dropped and split-stack deferral, real loot/tool/armor recovery cancellation, authoritative rest release, delayed revalidation and encounter scope')
