local oldA=package.loaded['shadowself/control/actions'];local oldSupply=package.loaded['shadowself/control/arena_supply']
local oldArena=package.loaded['shadowself/control/arena'];local oldTime=GetTime
local now=0;GetTime=function() return now end
local bag={};local owned={};local requests={};local headAck=true;local id=99000
local function item(name,slot)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(1,0,0),replica={}}
 function e:IsValid() return true end;function e:HasTag() return false end;function e:GetPosition() return self.pos end
 e.replica.inventoryitem={IsHeld=function() return owned[e] end,classified={percentused={value=function() return 100 end}}}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 Scene=function(_,target,action,guard) assert(action==ACTIONS.PICKUP and guard and guard());requests[#requests+1]={item=target,guard=guard};return true end}
package.loaded['shadowself/control/arena_supply']=nil;package.loaded['shadowself/control/arena']=nil
local Supply=require('shadowself/control/arena_supply');local Arena=require('shadowself/control/arena')
local p={components={playercontroller={IsBusy=function() return false end}},replica={inventory={}}}
function p:GetPosition() return Vector3(0,0,0) end
p.replica.inventory.GetItems=function() return bag end;p.replica.inventory.GetNumSlots=function() return 15 end
local queen=item('monkeyqueen');local staff=item('staff_tornado');local helmet1=item('footballhat',EQUIPSLOTS.HEAD)
local helmet2=item('footballhat',EQUIPSLOTS.HEAD);local rain=item('rainhat',EQUIPSLOTS.HEAD);local marble=item('armormarble',EQUIPSLOTS.BODY)
local initial=item('footballhat',EQUIPSLOTS.HEAD);bag={initial};owned[initial]=true
local a=setmetatable({player=p,running=true,wave=5,instance='island',generation=1,ignored={},enemies={},
 entities={queen,helmet1,rain,marble,helmet2,staff},bridge={Running=function() return false end},
 StopCombat=function() end,Say=function() end,Equip=function() return not headAck end},{__index=Arena})
assert(Supply.PirateOpening(a) and requests[1].item==staff,'queen scene immediately prioritizes tornado ahead of nearby helmets and ordinary supplies')
assert(a:Want(helmet1,bag),'opening permits duplicate head armour despite an owned helmet of the same prefab')
owned[staff]=true;bag[#bag+1]=staff;now=1
assert(Supply.PirateOpening(a) and requests[2].item==helmet1,'real staff inventory confirmation permits the first duplicate helmet')
now=1.5;assert(Supply.PirateOpening(a) and #requests==2 and not a.pirate_opening.ready,'pending pickup request is not pickup completion')
owned[helmet1]=true;bag[#bag+1]=helmet1;headAck=false;now=2
assert(Supply.PirateOpening(a) and #requests==2 and not a.pirate_opening.ready,'helmet equip acknowledgement completes before advancing')
headAck=true;now=3
assert(Supply.PirateOpening(a) and requests[3].item==helmet2,'collect all armour instances, not only the best or one per prefab')
owned[helmet2]=true;bag[#bag+1]=helmet2;headAck=false;now=4
assert(Supply.PirateOpening(a) and not a.pirate_opening.ready,'last pickup still waits for actual equipment state')
headAck=true;now=5
assert(not Supply.PirateOpening(a) and a.pirate_opening.ready and #requests==3,'only after actual pickup and equip does the edge-kite stage unlock')
assert(not Supply.PirateItem(rain) and not Supply.PirateItem(marble),'weather hats and body armour cannot masquerade as head armour')
assert(not requests[3].guard(),'old pickup callback cannot run after opening completion')
a.pirate_opening.ready=false;a.generation=2;assert(not requests[3].guard(),'old pickup callback cannot cross generation changes')
a.pirate_opening=nil;a.entities={staff,helmet1};assert(not Supply.PirateOpening(a) and not a.pirate_opening,'another fifth-wave scene cannot trigger the monkey queen opening')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/arena_supply']=oldSupply
package.loaded['shadowself/control/arena']=oldArena;GetTime=oldTime
print('PASS: monkey queen scene prep, actual tornado pickup first, all duplicate head armour, inventory/equip confirmation, non-armour exclusions and stale callback guards')
