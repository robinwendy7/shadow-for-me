local Inventory=require('shadowself/control/arena_inventory')
local id=159000
local function item(name,x)
 id=id+1
 local e={prefab=name,GUID=id,replica={},components={},pos=Vector3(x or 0,0,0)}
 function e:IsValid() return true end
 function e:HasTag(tag) return tag=='weapon' and (self.prefab=='hambat' or self.prefab=='ruins_bat') end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={classified={percentused={value=function() return 100 end}}}
 return e
end
local p={replica={inventory={GetEquippedItem=function() end}},components={playercontroller={IsBusy=function() return false end}}}
function p:GetPosition() return Vector3(0,0,0) end
function p:HasTag() return false end
local ham,bat=item('hambat'),item('ruins_bat')
assert(Inventory.Obsolete(ham,{ham,bat},p,7) and not Inventory.Obsolete(ham,{ham},p,7),'ruins bat explicitly replaces same-damage ham bat; sole ham retained')
local rain=item('rainhat')
assert(not Inventory.Obsolete(rain,{rain},p,6) and Inventory.Obsolete(rain,{rain},p,7),'keep rain hat through actual HUD wave6 goats, discard afterwards')
local torch=item('torch')
assert(Inventory.Cleanup({torch},p,6,false)==nil and Inventory.Cleanup({torch},p,6,true)==torch and Inventory.Cleanup({torch},p,7,false)==torch,'post6 cleanup clears torch and does not preserve it into wave7')
-- 后续关卡继续清除漏掉的旧物。
assert(Inventory.Cleanup({torch},p,7,true)==torch,'clear torch before ocean transition')
local f1,f2,f3=item('waffles'),item('meatballs'),item('dragonpie')
f1.components.edible={GetHealth=function() return 60 end}
f2.components.edible={GetHealth=function() return 3 end}
f3.components.edible={GetHealth=function() return 40 end}
assert(not Inventory.Want(f3,{f1,f2},p,7),'all food types share two inventory slots')
local discarded=Inventory.Cleanup({f1,f2,f3},p,7,true)
assert(discarded==f2,'extra food slot drops weakest healing food: '..tostring(discarded and discarded.prefab))
local kit,oar=item('boat_item'),item('oar_driftwood')
assert(Inventory.Priority(kit,8)>Inventory.Priority(bat,8) and Inventory.Priority(oar,8)>Inventory.Priority(bat,8),'boat and oar precede ordinary supplies at ocean entry')
local oldA=package.loaded['shadowself/control/actions'];local oldTime=GetTime;local now=0;GetTime=function() return now end
local staff=item('staff_tornado');p.replica.inventory.GetEquippedItem=function() return staff end;local bag={staff};local casts,moves,pauses=0,0,0;local chosen;local busy=false
p.components.playercontroller.IsBusy=function() return busy end
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,CastStaff=function(_,used,target,guard)
 assert(used==staff and (not guard or guard()));casts=casts+1;chosen=target;return true
end}
package.loaded['shadowself/control/arena_goats']=nil
local c={player=p,bridge={PauseAttack=function() pauses=pauses+1 end}}
local owner={c=c,Target=function(_,e) chosen=e end,Release=function() end,
 Move=function() moves=moves+1;return 'move' end,Away=function() moves=moves+1;return 'move' end}
local S=require('shadowself/control/arena_goats');local s=S(owner)
local back,front=item('lightninggoat',12),item('lightninggoat',9)
assert(s:Tick({back,front})=='move' and casts==0,'gather before casting, even if far goat is first in array')
now=3;assert(s:Tick({back,front})=='support' and casts==1 and chosen==front,'cast tornado on nearest leading goat')
now=3.1;s:Tick({back,front});assert(casts==1,'do not spam uncompleted casts')
now=4;busy=true;s:Tick({back,front});assert(casts==1,'do not interrupt casting animation')
busy=false;now=4.2;s:Tick({front});assert(casts==2,'continue tornado for final surviving goat')
front.pos=Vector3(3,0,0);now=5.5
assert(s:Tick({front})=='move' and casts==2,'collision-compressed front line causes retreat, not melee')
assert(not s:Tick({}),'all goats dead releases tactic')
bag={};assert(not s:Tick({back}),'missing or exhausted staff releases normal battle fallback')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/arena_goats']=nil;GetTime=oldTime
print('PASS: arena tornado gather/frontline/repeat/busy/last goat/collision buffer; two food slots; rainhat/ham/torch cleanup; ocean supply priorities')
