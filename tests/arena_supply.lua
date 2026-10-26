local key='shadowself/control/actions';local oldA=package.loaded[key]
local oldS=package.loaded['shadowself/control/arena_supply'];local oldTime=GetTime
local now=0;GetTime=function() return now end
local bag={};local stopped=0;local Inventory=require('shadowself/control/arena_inventory')
package.loaded[key]={Items=function() return bag end,Stop=function() stopped=stopped+1 end}
package.loaded['shadowself/control/arena_supply']=nil
local Supply=require('shadowself/control/arena_supply')
local id=98000
local function item(name,x,z,uses)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),replica={}}
 function e:IsValid() return true end;function e:GetPosition() return self.pos end;function e:HasTag() return false end
 e.replica.inventoryitem={IsHeld=function() return false end,classified={percentused={value=function() return uses or 100 end}}}
 return e
end
local p={pos=Vector3(0,0,0),components={playercontroller={IsBusy=function() return false end}},replica={inventory={}}}
function p:GetPosition() return self.pos end
local enemies={};local picked;local drops={};local rests=0
function p.replica.inventory:DropItemFromInvTile(e) drops[#drops+1]=e end
local a={player=p,running=true,wave=5,items={},ignored={},healing={},bridge={Running=function() return true end}}
function a:NearbyEnemies() return enemies end
function a:StopCombat() end;function a:Say() end
function a:Loot(items) picked=items[1];return Inventory.Want(picked,bag,p,self.wave) end
function a:Rest(_,full) assert(full);rests=rests+1;return true end
local flute=item('panflute',10);a.items={flute};bag={item('panflute')}
assert(Supply.Tick(a,{}) and picked==flute,'wave5 actually retrieves a spare flute even while combat bridge was active')
bag={item('panflute'),item('panflute')};assert(not Supply.Tick(a,{}),'do not collect unlimited duplicate flutes')
local spent=item('panflute',0,0,0)
assert(Inventory.Discard({spent},p,5,flute)==spent,'spent flute yields a full-bag slot for the actual usable drop')
enemies={item('frog',5)}
assert(not Supply.SafePickup(a,flute),'a monster between player and flute blocks the pickup route')
picked=nil;a.pending_item=flute;assert(not Supply.Tick(a,{}) and not picked and stopped==1 and not a.pending_item,'new threat cancels a stale flute approach')
enemies={};a.wave=6;assert(not Supply.SafePickup(a,flute),'delayed pickup cannot cross the wave5 boundary')
a.wave=6;local grass,torch,hat,cut=item('armorgrass'),item('torch'),item('strawhat'),item('cookiecutterhat')
bag={grass,torch,hat,cut};assert(not Supply.Tick(a,{intermission=false}) and #drops==0,'empty scan without authoritative intermission cannot discard gear')
enemies={item('sharkboi')};assert(not Supply.Tick(a,{intermission=true}) and #drops==0,'remaining live enemy prevents post-wave cleanup and recovery')
enemies={};assert(Supply.Tick(a,{intermission=true}) and drops[1]==grass and rests==0)
now=.1;Supply.Tick(a,{intermission=true});assert(#drops==1 and rests==0,'wait for actual removal and throttle before another request')
bag={torch,hat,cut};now=.4;Supply.Tick(a,{intermission=true});assert(drops[2]==torch)
bag={hat,cut};now=.8;Supply.Tick(a,{intermission=true});assert(drops[3]==hat and rests==0)
bag={cut};now=1.2;Supply.Tick(a,{intermission=true});assert(drops[4]==cut,'sixth-wave cleanup includes cookiecutter helmet')
bag={};now=1.6;assert(not Supply.Tick(a,{intermission=true}) and rests==0,'cleanup moves to wave6 without moving the dedicated post7 recovery')
a.wave=7;assert(Supply.Tick(a,{intermission=true}) and rests==1,'post7 full recovery remains immediate')
a.wave=8;assert(not Supply.Tick(a,{intermission=false}) and rests==1,'wave8 supplies cannot take over rowing')
for _,e in ipairs({grass,torch,hat,cut}) do assert(not Inventory.Want(e,{},p,7),'never re-pick deliberately discarded items after wave6') end
local wood1,wood2,marble=item('armorwood'),item('armorwood'),item('armormarble')
a.wave=9;bag={wood1,wood2};local count=#drops;now=5
assert(not Supply.CleanupNine(a,{intermission=false}) and #drops==count,'ninth wave active combat retains wood armour')
enemies={item('minotaur')};assert(not Supply.CleanupNine(a,{intermission=true}),'cleanup requires authoritative rest and no live enemies')
enemies={};assert(Supply.CleanupNine(a,{intermission=true}) and drops[#drops]==wood1)
bag={wood2,marble};now=5.4;assert(Supply.CleanupNine(a,{intermission=true}) and drops[#drops]==wood2,'drop every duplicate wood armour')
bag={marble};now=5.8;assert(Supply.CleanupNine(a,{intermission=true}) and drops[#drops]==marble)
bag={wood1};a.wave=10;now=6.2;assert(Supply.CleanupNine(a,{}) and drops[#drops]==wood1,'stage transition still removes leftover wood armour')
assert(not Inventory.Want(wood1,{},p,10),'discarded wood armour cannot be picked back up next wave')
assert(Inventory.Cleanup({wood1},p,9,true)==wood1,'ordinary rest cleanup includes all wood armour even if worn')
-- After wave6 keep one meal slot, not one unit from a stack; tea keeps its separate SAN role.
p.replica.inventory.GetEquippedItem=function() end
local waffle,dragon,tea=item('waffles'),item('dragonpie'),item('sweettea')
assert(not Inventory.ExcessMeal({waffle,dragon},p,6,false),'active sixth wave still permits two meals')
assert(Inventory.ExcessMeal({waffle,dragon},p,6,true)==dragon,'confirmed sixth clear retains the higher-healing meal')
assert(not Inventory.ExcessMeal({waffle,tea},p,7,false),'SAN tea is separate from the meal slot')
assert(not Inventory.Want(dragon,{waffle},p,7),'seventh and later waves cannot fill a second meal slot')
waffle.replica.stackable={IsFull=function() return false end}
assert(Inventory.Want(waffle,{waffle},p,7),'adding to an existing meal stack does not consume another slot')
a.wave=6;bag={waffle,dragon};now=10;local previous=#drops
assert(not Supply.Tick(a,{intermission=false}) and #drops==previous)
assert(Supply.Tick(a,{intermission=true}) and drops[#drops]==dragon,'actual supply loop drops surplus meals immediately after six')
local Policy=require('shadowself/control/arena_policy');local meatballs=item('meatballs')
for wave=1,15 do assert(not Policy.PickupAllowed(meatballs,wave) and not Inventory.Want(meatballs,{},p,wave),'meatballs never picked in any arena wave') end
package.loaded[key]=oldA;package.loaded['shadowself/control/arena_supply']=oldS;GetTime=oldTime
print('PASS: wave5 flute reserve, authoritative post6 four-item cleanup, retained post7 healing, no re-pick and wave8 rowing priority')
