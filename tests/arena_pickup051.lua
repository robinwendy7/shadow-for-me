local keys={'actions','navigation','arena_tools','arena_supply','arena','mechanisms'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded['shadowself/control/'..k] end
local oldTime,oldSim=GetTime,TheSim;local now=100;GetTime=function() return now end
local id=991000
local function ent(name,slot,x)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 10,0,0),replica={},tags={}}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetBasicDisplayName() return self.prefab end
 e.replica.inventoryitem={IsHeld=function() return e.held end}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local cane=ent('cane',EQUIPSLOTS.HANDS);local weapon=ent('nightsword',EQUIPSLOTS.HANDS)
local flute=ent('panflute');local staff=ent('staff_tornado');local marble=ent('armormarble',EQUIPSLOTS.BODY)
local bag={cane,weapon};local hand=weapon;local body;local requests,pickups,stops=0,0,0;local last
local p=ent('wilson',nil,0);p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetEquippedItem=function(_,slot) if slot==EQUIPSLOTS.HANDS then return hand elseif slot==EQUIPSLOTS.BODY then return body end end,
 GetItems=function() return bag end,GetNumSlots=function() return 15 end,GetOverflowContainer=function() end}
local A={Items=function() return bag end,Stop=function() stops=stops+1 end,
 Self=function(_,item,act) assert(act==ACTIONS.EQUIP);requests=requests+1;last=item;return true end,
 Scene=function(_,item,_,guard) assert(not guard or guard());pickups=pickups+1;last=item;return true end}
package.loaded['shadowself/control/actions']=A
package.loaded['shadowself/control/navigation']={Safe=function() return true end}
for _,k in ipairs({'arena_tools','arena_supply','arena','mechanisms'}) do package.loaded['shadowself/control/'..k]=nil end
local Arena=require('shadowself/control/arena');local arena=setmetatable({player=p,wave=3,running=true,ignored={},enemies={},fire_zones={},
 bridge={Running=function() return false end}},{__index=Arena})
assert(arena:Loot({flute}) and requests==1 and last==cane and pickups==0,'real ordinary loot first requests cane, no pickup before hand ack')
now=100.1;arena:Loot({flute});assert(requests==1 and pickups==0,'unacknowledged cane does not spam equip or begin walking')
hand=cane;now=100.2;assert(arena:Loot({flute}) and pickups==1 and arena.pending_item==flute,'confirmed cane starts the real pickup action')
hand=weapon;now=100.3;arena:Loot({flute});assert(requests==2 and last==cane,'in-flight loot continues enforcing cane instead of switching to battle weapon')
hand=cane;bag={cane,weapon,flute};flute.held=true;now=101
assert(not arena:Loot({}) and hand==cane,'pickup completion does not unnecessarily restore weapon between items')
-- Third-wave preparation is ahead of the normal opener and cancels an old pickup.
local Supply=require('shadowself/control/arena_supply');local chosen
bag={weapon};local opener={player=p,wave=3,items={staff,cane},pending_item=staff,
 StopCombat=function() end,Say=function() end,Loot=function(_,items) chosen=items[1];return true end}
assert(Supply.CaneOpening(opener) and chosen==cane and not opener.pending_item and stops==1,'third-wave cane pickup preempts another supply pickup')
bag={cane,weapon};assert(not Supply.CaneOpening(opener),'already owning a usable cane does not block the combat opener')
-- Combat-time recovery shares the hand ownership until actual pickup acknowledgement.
local Tools=require('shadowself/control/arena_tools');hand=weapon;now=110
local wave=5;local c={player=p,plan={arena=true,arena_wave=function() return wave end,arena_ground=function() return {staff} end},
 gear={},bridge={PauseAttack=function() end},snapshot={}}
local before=pickups;assert(Tools.Recover(c,'staff_tornado') and pickups==before and last==cane)
hand=cane;now=110.1;assert(Tools.Recover(c,'staff_tornado') and pickups==before+1,'combat recovery walks with confirmed cane')
assert(c.gear.support_hand and c.gear.support_hand.item==cane and c.gear.support_hand.valid(),'pickup owns the hand against native combat swaps')
-- Exercise the real Gear:Swap validator to release cane ownership for the newly acquired staff.
local R=require('shadowself/legacy/registry');local context={player=p,roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end},
 actions={FindAction=function(_,_,_,item) return {item=item} end,Execute=function(_,act) last=act.item;return true end}}
local gear=setmetatable({player=p,combat=context,support_hand=c.gear.support_hand,failed={},next_request=0,
 Weapon=function() return weapon end,Owned=function(_,item) for _,e in ipairs(bag) do if e==item then return true end end;return false end},{__index=R.CombatEquipment})
assert(gear:Swap('attack',{}) and hand==cane,'native attack-role swap honors pickup hand ownership')
bag={cane,weapon,staff};staff.held=true;now=111
assert(not gear:Swap('attack',{}) and not gear.support_hand and last==weapon,'real acquisition invalidates the cane lock and releases combat equipment')
Tools.Recover(c,'staff_tornado');assert(not c.gear.support_hand,'recovery bookkeeping also releases acknowledged ownership')
-- Armour cannot be upgraded to marble during any of the four perimeter tactics.
local Policy=require('shadowself/control/arena_policy')
for _,row in ipairs({{5,'powder_monkey'},{6,'lightninggoat'},{6,'fruitdragon'},{6,'worm'},{6,'monkey'}}) do
 assert(not Policy.AllowArmor(marble,row[1],{ent(row[2])}),'patrol scene forbids automatic marble equip')
end
assert(Policy.AllowArmor(marble,5,{ent('prime_mate')}),'captain-only explicit marble melee remains available')
local monkey=ent('powder_monkey');arena.wave=5;arena.enemies={monkey};bag={cane,weapon,marble};body=nil;arena.next_equip=nil;arena.equip_pending=nil
before=requests;assert(not arena:Equip(arena.enemies) and requests==before,'ordinary arena equip skips marble even if no body armour is worn')
local Mechanisms=require('shadowself/control/mechanisms');c.enemies={monkey};c.gear.Owned=gear.Owned
local mechanisms=Mechanisms(c);mechanisms.picked=marble
TheSim={FindEntities=function() return {marble} end}
assert(not mechanisms:Pickup() and requests==before,'combat-time pickup acknowledgement and upgrade scan both reject patrol marble')
-- 巡游持杖独立于 native 的 move/attack 角色；角色恢复不能切回近战武器。
local Cycle=require('shadowself/control/arena_windcycle');c.gear=gear;c.enemies={monkey};gear.pending=nil;gear.next_request=0
hand=weapon;now=120;Cycle.Hold(c)
assert(c.arena_patrol and gear.patrol_hand==cane and last==cane,'patrol requests the actual owned cane')
hand=cane;assert(gear:Swap('attack',{}) and gear.patrol_hand==cane,'native attack-role restoration still keeps cane during patrol')
Cycle.Release(c);assert(not gear.patrol_hand and not c.arena_patrol)
assert(not gear:Swap('attack',{}) and last==weapon,'phase release allows ordinary melee equipment again')
-- Early waves and missing canes still use the existing pickup path.
local Travel=require('shadowself/control/arena_pickup_travel');hand=weapon;bag={weapon}
assert(Travel.Ready({},p,3,flute) and Travel.Ready({},p,2,flute),'missing cane and waves before three cannot stall pickup')
for _,k in ipairs(keys) do package.loaded['shadowself/control/'..k]=saved[k] end
GetTime=oldTime;TheSim=oldSim
print('PASS: third-wave cane opening; real ordinary/tool pickup waits for equip ack, maintains hand during travel and releases on acquisition; patrol marble blocked in both automatic equip paths, captain melee preserved')
