-- 执行真实Arena循环，模拟两次查询之间刷怪，以及跨帧/跨波缓存变化。
local keys={'shadowself/control/actions','shadowself/control/combat','shadowself/control/arena_adapter','shadowself/control/arena_healing','shadowself/control/arena'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k] end
local oldTime,oldSim,oldWorld=GetTime,TheSim,TheWorld
local now=0;GetTime=function() return now end
local starts,stops,loot,heals,farCalls=0,0,0,0,0;local active=false
local snapshot={state={},instance='run',generation=1,kind='PARTICIPANT',arena=true,wave=1,route='default'}
local player={replica={inventory={GetItems=function() return {} end,GetEquips=function() return {} end,GetOverflowContainer=function() end,GetEquippedItem=function() end}},components={playercontroller={IsBusy=function() return false end}}}
function player:GetPosition() return Vector3(0,0,0) end
function player:HasTag() return false end
package.loaded['shadowself/control/actions']={Items=function() return {} end,Scene=function() loot=loot+1;return false end,Stop=function() end}
package.loaded['shadowself/control/combat']=function() return {Running=function() return active end,Start=function() starts=starts+1;active=true;return true end,Stop=function() stops=stops+1;active=false end} end
package.loaded['shadowself/control/arena_adapter']=function() return {Snapshot=function() return snapshot end,Cancel=function() end} end
package.loaded['shadowself/control/arena_healing']=function() return {Health=function() return false end,Reset=function() end,Tick=function() heals=heals+1;return true end} end
package.loaded['shadowself/control/arena']=nil
local Arena=require('shadowself/control/arena');local task=Arena(player,{})
task.instance='run';task.generation=1;task.route='default'
local items={};local spawned
for i=1,10 do
 local e={prefab=i%2==0 and 'waffles' or 'meatballs',GUID=99000+i,replica={inventoryitem={IsHeld=function() return false end}}}
 function e:IsValid() return not self.removed end
 function e:GetPosition() return Vector3(i,0,1) end
 function e:HasTag() return false end
 function e:GetBasicDisplayName() return self.prefab end
 items[#items+1]=e
end
TheSim={FindEntities=function(_,x,y,z,r)
 if r==60 then farCalls=farCalls+1;local result={};for _,e in ipairs(items) do result[#result+1]=e end;return result end
 if r==24 and spawned then return {spawned} end
 return {}
end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local Inventory=require('shadowself/control/arena_inventory');local priority=Inventory.Priority;local evaluations=0
Inventory.Priority=function(...) evaluations=evaluations+1;return priority(...) end
local enemies,drops=task:Entities();assert(#enemies==0 and #drops==10 and farCalls==1 and evaluations==10,'priority calculated once per item, not sort comparator')
items[1].removed=true;now=.05;enemies,drops=task:Entities();assert(#drops==9 and farCalls==1,'raw list cache filters invalid entities each frame')
now=.21;task:Entities();assert(farCalls==2,'far supply scan has bounded cadence')
snapshot.wave=2;now=.22;task:Tick();assert(farCalls==3,'authoritative wave change immediately invalidates far cache')
spawned={prefab='hound',GUID=99999,replica={combat={}}}
function spawned:IsValid() return true end
function spawned:HasTag(name) return name=='dead' and self.dead or false end
function spawned:GetPosition() return Vector3(2,0,0) end
local attempts=loot;now=.23;task:Tick()
assert(starts==1 and active and heals==0 and loot==attempts,'fresh close scan interrupts intermission before new spawn can be mistaken for safe loot/eat time')
now=.24;task:Tick();assert(starts==1 and stops==0,'fresh near spawn merged into cache avoids stop/start oscillation')
spawned.dead=true;now=.25;task:Tick();assert(not active and stops==1,'dead body with delayed replica health cannot retain combat forever')
Inventory.Priority=priority
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
GetTime=oldTime;TheSim=oldSim;TheWorld=oldWorld
print('PASS: real arena cross-frame loop; bounded raw scan and one priority evaluation/item; invalid/dead filtering; immediate wave cache reset; fresh near spawn blocks rest and preserves existing combat owner')
