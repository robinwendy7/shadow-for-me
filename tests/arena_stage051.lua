local keys={'actions','navigation','arena_tools','arena_supply','mechanisms','arena'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded['shadowself/control/'..k] end
local oldTime,oldSim,oldWorld=GetTime,TheSim,TheWorld;local now=0;GetTime=function() return now end
local id=994000
local function ent(name,slot,x,z)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e:GetBasicDisplayName() return self.prefab end
 e.replica.inventoryitem={IsHeld=function() return e.held end}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local p=ent('wilson');local star=ent('nightstick',EQUIPSLOTS.HANDS);local marble=ent('armormarble',EQUIPSLOTS.BODY)
local shell=ent('armorsnurtleshell',EQUIPSLOTS.BODY);local ruins=ent('armorruins',EQUIPSLOTS.BODY);local hat=ent('ruinshat',EQUIPSLOTS.HEAD)
local bag={star,marble};local drops={};local picks=0;local stopped=0;local body=marble
p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetItems=function() return bag end,GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HANDS and star or body end,
 GetNumSlots=function() return 15 end,DropItemFromInvTile=function(_,item) drops[#drops+1]=item end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() stopped=stopped+1 end,
 Scene=function() picks=picks+1;return true end,Self=function() return true end}
for _,k in ipairs({'arena_tools','arena_supply','mechanisms','arena'}) do package.loaded['shadowself/control/'..k]=nil end
local Policy=require('shadowself/control/arena_policy');local Inventory=require('shadowself/control/arena_inventory')
for wave=1,15 do assert(not Policy.PickupAllowed(shell,wave) and not Inventory.Want(shell,{},p,wave),'shell armour is never picked in the arena') end
for wave=9,15 do for _,e in ipairs({star,marble}) do assert(not Policy.PickupAllowed(e,wave) and not Inventory.Want(e,{},p,wave)) end end
assert(Policy.PickupAllowed(star,8) and Policy.PickupAllowed(marble,8),'pre9 special equipment remains usable')
for wave=10,15 do assert(not Inventory.Want(ruins,{},p,wave) and not Inventory.Want(hat,{},p,wave),'both ruins armour drops are excluded starting wave10') end
assert(Inventory.Want(ruins,{},p,9) and Inventory.Want(hat,{},p,9),'ninth-wave ruins pickups are retained')
local tea=ent('sweettea');local meals={ent('waffles'),ent('dragonpie')}
assert(Inventory.Want(tea,meals,p,9) and Inventory.Priority(tea,9)>Inventory.Priority(star,9),'ninth-wave tea gets a slot despite normal two-food reserve')
assert(not Inventory.Want(tea,{tea},p,9),'do not fill every slot with duplicate tea stacks')
-- Ninth-wave tea is reserved until consumed, including full-bag equipment replacement in later stages.
for wave=9,15 do
 assert(Inventory.Special('sweettea',wave) and not Inventory.Obsolete(tea,{tea,meals[1]},p,wave))
 assert(not Inventory.Cleanup({tea,meals[1]},p,wave,true),'one meal plus reserved tea survives intermission cleanup')
 assert(not Inventory.Discard({tea,meals[1]},p,wave,ruins),'full-bag armour pickup cannot discard reserved tea as low-healing food')
 assert(not Inventory.Discard({tea},p,wave,ruins),'remaining tea is kept until actual consumption')
 assert(Inventory.ExcessMeal({tea,meals[1],meals[2]},p,wave,true)==meals[2],'surplus meal removal never selects tea')
end
local Supply=require('shadowself/control/arena_supply');local arena={player=p,wave=8,ignored={},StopCombat=function() end,Say=function() end}
assert(not Supply.CleanupNine(arena) and #drops==0)
arena.wave=9;assert(Supply.CleanupNine(arena) and drops[1]==star)
bag={marble};now=.1;assert(Supply.CleanupNine(arena) and #drops==1,'drop throttle waits for the next legal request')
now=.31;assert(Supply.CleanupNine(arena) and drops[2]==marble,'equipped marble is also discarded')
bag={ruins,hat};now=1;assert(not Supply.CleanupNine(arena),'already-owned ruins gear is not explicitly discarded')
-- Wave10 exclusions apply to every pickup route; low-wind cleanup is strict below30 percent.
local football=ent('footballhat',EQUIPSLOTS.HEAD);local shadow=ent('armor_sanity',EQUIPSLOTS.BODY);local light=ent('yellowamulet')
local lowwind=ent('staff_tornado',EQUIPSLOTS.HANDS);local goodwind=ent('staff_tornado',EQUIPSLOTS.HANDS)
lowwind.replica.inventoryitem.classified={percentused={value=function() return 29 end}}
goodwind.replica.inventoryitem.classified={percentused={value=function() return 30 end}}
for wave=10,15 do
 assert(not Policy.PickupAllowed(shadow,wave,p) and not Policy.PickupAllowed(light,wave,p))
 bag={hat};assert(not Policy.PickupAllowed(football,wave,p),'owned usable helmet prevents spare football-hat pickup')
 bag={};assert(Policy.PickupAllowed(football,wave,p),'missing head protection still permits the first football hat')
 assert(not Policy.PickupAllowed(lowwind,wave,p) and Policy.PickupAllowed(goodwind,wave,p))
 assert(Inventory.Cleanup({lowwind,goodwind},p,wave,false)==lowwind)
end
bag={lowwind,goodwind};arena.wave=9;now=2
assert(not Supply.CleanupNine(arena),'before10 the remaining wind uses are retained')
arena.wave=10;assert(Supply.CleanupNine(arena) and drops[#drops]==lowwind,'stage entry clears low wind even before ordinary combat scheduling')
bag={goodwind};now=2.4;assert(not Supply.CleanupNine(arena),'exactly30 percent is retained')
arena.wave=9;bag={ruins,hat}
local Tools=require('shadowself/control/arena_tools');local wave=9
local c={player=p,plan={arena=true,arena_wave=function() return wave end,arena_ground=function() return {shell,star,marble,ruins,hat} end},
 enemies={},gear={},bridge={PauseAttack=function() end},h={},hazards={},observed={}}
for _,name in ipairs({'armorsnurtleshell','nightstick','armormarble'}) do assert(not Tools.Recover(c,name) and picks==0,'tool recovery cannot bypass forbidden pickup policy') end
wave=10;bag={};assert(not Tools.Recover(c,'armorruins') and not Tools.Recover(c,'ruinshat') and picks==0)
TheSim={FindEntities=function() return {shell,star,marble,ruins,hat} end}
local Mechanisms=require('shadowself/control/mechanisms');c.gear.Owned=function() return false end
local mechanism=Mechanisms(c);mechanism.last_weapon=star
assert(not mechanism:Pickup() and picks==0,'native armour-upgrade and last-disarmed-weapon recovery obey bans')
-- Actual geometry guard: return toward the centre, do not chase boss to a lava corner.
local dragon=ent('dragonfly',nil,0,0);c.enemies={dragon};c.plan.arena_center=function() return Vector3(0,0,0) end
c.actions={SafePoint=function() return true end};c.observed[dragon.GUID]={neutral=true}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
package.loaded['shadowself/control/navigation']=nil
local Nav=require('shadowself/control/navigation');local Center=require('shadowself/control/arena_center')
local goal;local owner={c=c,Move=function(_,q) goal=q;return 'move' end,Release=function() end}
p.pos=Vector3(14,0,0)
assert(Center.Tick(owner,dragon)=='move' and goal:DistSq(Vector3(0,0,0))<p.pos:DistSq(Vector3(0,0,0)),'outer position returns inward')
assert(not Center.Point(c,Vector3(15,0,0)) and Center.Point(c,Vector3(12,0,0)),'outside centre, short inward escape is allowed but further outward movement is rejected')
p.pos=Vector3(0,0,0);dragon.pos=Vector3(14,0,14)
assert(Center.Tick(owner,dragon)=='support' and not Center.AttackAllowed(c,dragon),'central player lures outer dragonfly rather than chasing into lava')
assert(Nav.Obstructed(c,Vector3(14,0,14),dragon) and not Nav.Safe(c,Vector3(14,0,14),dragon),'real native route safety rejects corner-directed motion')
local q=Nav.Select(c,Vector3(14,0,14),dragon);assert(q:DistSq(Vector3(0,0,0))<=10^2,'native replacement route stays inside the central battle area')
dragon.pos=Vector3(4,0,0);assert(not Center.Tick(owner,dragon) and Center.AttackAllowed(c,dragon),'central target retains normal attack and dodge handling')
wave=9;assert(Center.Point(c,Vector3(14,0,14)),'central restriction does not change other waves')
local Fire=require('shadowself/control/arena_fire');local lava=ent('lava_pond',nil,14,14);local zones=Fire.LavaZones({lava})
assert(#zones==1 and zones[1].heat and not Fire.Safe(p,Vector3(14,0,14),zones) and Fire.Safe(p,Vector3(0,0,4),zones),'pool heating buffer blocks pickup routes near lava and leaves central movement available')
-- 服务端龙蝇场地：中央CARPET，其余ROAD；点位、整段路径和人物碰撞余量均须守道路。
local oldTiles=WORLD_TILES;WORLD_TILES={ROAD=71,CARPET=72}
TheWorld.Map.GetTileAtPoint=function(_,x,_,z) return math.abs(x)<2 and math.abs(z)<2 and 72 or 71 end
wave=10;p.pos=Vector3(4,0,0);dragon.pos=Vector3(0,0,0)
assert(not Center.Point(c,Vector3(0,0,0)),'central carpet is not a legal waypoint')
assert(not Center.Point(c,Vector3(-4,0,0)),'two road endpoints cannot cross carpet in between')
assert(Center.Point(c,Vector3(4,0,4)),'same-side road corridor remains available')
assert(not Center.RoadAt(c,Vector3(2.1,0,0)) and Center.RoadAt(c,Vector3(2.6,0,0)),'road check includes player collision radius at carpet border')
local approach=Nav.Select(c,dragon.pos,dragon)
assert(Center.RoadAt(c,approach) and Center.RoadPath(c,approach) and approach:DistSq(dragon.pos)<=3.1^2,'actual native navigation approaches carpet-standing dragonfly from adjacent road')
p.pos=Vector3(0,0,0)
assert(Center.Tick(owner,dragon)=='move' and Center.RoadAt(c,goal),'player initially on carpet immediately exits onto a valid road')
WORLD_TILES=oldTiles
for _,k in ipairs(keys) do package.loaded['shadowself/control/'..k]=saved[k] end
GetTime=oldTime;TheSim=oldSim;TheWorld=oldWorld
print('PASS: ninth-wave discard and no re-pick, shell ban across all waves and pickup paths, ruins ban from10 with owned gear preserved, tea slot priority, central dragonfly routing and lava heat buffers')
