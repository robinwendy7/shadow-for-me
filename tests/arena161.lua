local I=require('shadowself/control/arena_inventory')
local function item(name,slot)
 local e={prefab=name,replica={},components={},pos=Vector3(0,0,0)}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local p={replica={inventory={GetEquippedItem=function() end}}};function p:GetPosition() return Vector3(20,0,0) end
local wind=item('staff_tornado')
for wave=1,15 do assert(I.Special('staff_tornado',wave) and not I.Obsolete(wind,{wind},p,wave),'tornado staff retained through all arena stages') end
local grass=item('armorgrass',EQUIPSLOTS.BODY);local cutter=item('cookiecutterhat',EQUIPSLOTS.HEAD)
local wood=item('armorwood',EQUIPSLOTS.BODY);local football=item('footballhat',EQUIPSLOTS.HEAD)
local ruins=item('armorruins',EQUIPSLOTS.BODY);local ruinshat=item('ruinshat',EQUIPSLOTS.HEAD);local bone=item('armorskeleton',EQUIPSLOTS.BODY)
assert(not I.BelowArmorFloor(wood,8) and not I.BelowArmorFloor(football,8),'80 percent armor retained for crab')
assert(I.BelowArmorFloor(grass,8) and I.BelowArmorFloor(cutter,8),'60 percent grass and 70 percent cutter cleared before crab')
assert(I.Cleanup({cutter},p,7,true)==cutter,'wave7 clear drops low armor before ocean begins')
assert(I.BelowArmorFloor(wood,11) and not I.BelowArmorFloor(ruins,11) and not I.BelowArmorFloor(ruinshat,11) and not I.BelowArmorFloor(bone,11),'after dragon retain 90 percent ruins and bone armor; drop wood')
assert(I.Cleanup({football},p,10,true)==football and not I.Cleanup({football},p,10,false),'90 percent threshold starts at dragon completion, not mid-fight')
local oldWorld,oldTime=TheWorld,GetTime;GetTime=function() return 0 end
local map={GetTileCenterPoint=function() return 20,0,0 end,IsOceanAtPoint=function(_,x,_,z) return math.abs(x)<=12 and math.abs(z)<=12 end,IsPassableAtPoint=function() return true end}
TheWorld={Map=map}
local E=require('shadowself/control/arena_encounters');local arena={player=p};local s=E(arena)
local center=s:WaterCenter();assert(center and center.x==0 and center.z==0,'finite water center found before crab entity exists, without brick tile constant')
map.IsOceanAtPoint=function() return true end
assert(not s:WaterCenter(),'unbounded ordinary ocean rejected')
TheWorld=oldWorld;GetTime=oldTime
local saved=package.loaded['shadowself/control/arena_goats'];local targets
package.loaded['shadowself/control/arena_goats']=function(owner,label) assert(label=='群怪');return {Tick=function(_,crowd) targets=crowd;return 'support',crowd[1] end} end
local c={plan={arena=true},player=p,gear={},bridge={allowed=function() return true end},enemies={}}
for i=1,4 do local e=item('hound');e.GUID=i;c.enemies[i]=e end
local Enc=require('shadowself/control/encounters');local enc=Enc(c)
local mode=enc:Tick(c.enemies[1]);assert(mode=='support' and #targets==4,'ordinary arena crowd can invoke tornado tactic outside goat wave')
package.loaded['shadowself/control/arena_goats']=saved
print('PASS: tornado always reserved and usable in ordinary crowds; 80/90 percent armor phase boundaries; finite ocean center before boss spawn, open ocean rejected')
