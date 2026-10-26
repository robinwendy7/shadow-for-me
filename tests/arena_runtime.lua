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
-- 场景冰火杖必须在清怪后且所有普通补给之后拾取。
local Policy=require('shadowself/control/arena_policy')
local actions=package.loaded['shadowself/control/actions'];local picked,guard;local cancelled=0
actions.Stop=function() cancelled=cancelled+1 end
local function drop(name,guid)
 local e={prefab=name,GUID=guid,replica={inventoryitem={IsHeld=function() return false end}}}
 function e:IsValid() return true end
 function e:HasTag() return false end
 function e:GetPosition() return Vector3(10,0,0) end
 return e
end
local fire,ice,food=drop('firestaff',100001),drop('icestaff',100002),drop('waffles',100003)
local sleeping={prefab='icehound',GUID=100004,replica={combat={}},asleep=true}
function sleeping:IsValid() return true end
function sleeping:HasTag(tag) return tag=='sleeping' and self.asleep or false end
function sleeping:GetPosition() return Vector3(12,0,0) end
local alive={prefab='rook',GUID=100005,replica={combat={}}}
function alive:IsValid() return true end
function alive:HasTag() return false end
function alive:GetPosition() return Vector3(40,0,0) end
local scene={fire,ice,sleeping};local owned={}
actions.Items=function() return owned end
actions.Scene=function(_,item,_,check) if check and not check() then return false end;picked=item;guard=check;return true end
TheSim.FindEntities=function() return scene end
for _,wave in ipairs({2,3}) do
 snapshot.wave=wave;snapshot.intermission=false
 task.wave=wave;task.pending_item=nil;task.ignored={};task.next_item=nil;task.raw_entities=nil;now=now+1;picked=nil
 assert(Inventory.Priority(fire,wave)<Inventory.Priority(food,wave))
 local hostiles=task:Entities();assert(#hostiles==0,'dormant scene guards do not prevent post-clear pickup')
 assert(not task:Loot({fire,ice},false) and not picked,'precombat cannot pick either trap staff')
 assert(task:Loot({fire,food,ice},true) and picked==food,'ordinary supplies beat both trap staffs even with unsorted input')
 task.pending_item=nil;task.next_item=nil;picked=nil
 assert(not task:Loot({fire,ice},true) and not picked,'empty local scan during active/preparing wave must not release trap staff')
 snapshot.intermission=true
 scene={fire,ice,sleeping,alive}
 assert(not task:Loot({fire,ice},true) and not picked,'fresh 60-range scan blocks stale clear flag for distant live enemy')
 scene={fire,ice,sleeping};task.next_item=nil
 assert(task:Loot({fire,ice},true) and picked==fire,'clear wave permits first trap pickup')
 assert(guard and guard(),'trap action has final send-time validation')
 local delayed=guard;snapshot.intermission=false;picked=nil
 assert(not delayed(),'server returns to combat before action RPC: reject delayed pickup')
 local before=cancelled
 assert(not task:Loot({fire,ice},true) and not picked and not task.pending_item and cancelled==before+1,'cancel walking to trap when server clearance is lost')
 snapshot.intermission=true;task.next_item=nil
 assert(task:Loot({fire,ice},true) and picked==fire)
 local previous=guard;snapshot.wave=wave+1
 assert(not previous(),'stale previous-wave trap request cannot send')
 snapshot.wave=wave
 owned={fire};task.next_item=nil;picked=nil
 assert(task:Loot({ice},true) and picked==ice,'confirmed first pickup permits second staff')
 owned={};task.pending_item=nil;task.next_item=nil;sleeping.asleep=false;picked=nil
 assert(not task:Loot({fire,ice},true) and not picked,'awake guards are live danger again')
 sleeping.asleep=true;scene={fire,ice,sleeping}
end
task.wave=9;task.pending_item=nil;task.next_item=nil;picked=nil
assert(task:Loot({fire},false) and picked==fire,'later-wave normal staff supplies remain available before combat')
assert(not Policy.DormantTrapGuard(sleeping,9),'trap clear exception is scoped to waves two and three')
print('PASS: wave2/3 trap staffs deferred until clear, last among ordinary loot, fresh distant enemy gate, sleeping/waking guards and later-wave isolation')
-- 预丢武器只能在权威休整期，不以空缓存/开局准备冒充清关。
task.pending_item=nil;task.next_item=nil;task.raw_entities=nil;task.healing.pending=nil
snapshot.wave=2;task.wave=2;snapshot.intermission=false;scene={}
local prune=task.Prune;local forecasts=0
task.Prune=function(_,upcoming) if upcoming then forecasts=forecasts+1;return true end;return false end
task:Tick();assert(forecasts==0,'empty active wave must not forecast-discard')
snapshot.intermission=true;task.raw_entities=nil;now=now+1
task:Tick();assert(forecasts==1,'authoritative cleared intermission can forecast-discard')
scene={alive};task.raw_entities={};task.next_entities=now+1
now=now+.01;task:Tick();assert(forecasts==1,'distant fresh live enemy blocks forecast-discard despite cached clear')
task.Prune=prune
local armor=drop('armorwood',100006)
armor.replica.equippable={EquipSlot=function() return EQUIPSLOTS.BODY end}
local worn;local equipCalls=0
player.replica.inventory.GetEquippedItem=function(_,slot) if slot==EQUIPSLOTS.BODY then return worn end end
actions.Self=function(_,item,action) assert(item==armor and action==ACTIONS.EQUIP);equipCalls=equipCalls+1;return true end
owned={armor};task.pending_item=armor;task.equip_pending=nil;task.equip_due=nil;task.next_equip=nil;task.next_item=nil;picked=nil;now=now+3
assert(task:Loot({food},true) and equipCalls==1 and not picked,'acknowledged armor pickup equips before next supply')
now=now+.6
assert(task:Loot({food},true) and equipCalls==1 and not picked,'wait for actual armor slot ack without duplicate equip or loot interruption')
worn=armor;now=now+.1
assert(task:Loot({food},true) and picked==food,'confirmed armor equip releases next supply pickup')
assert(not Inventory.Discard({armor},player,3),'currently worn armor remains protected')
print('PASS: armor pickup equips before more loot, delayed equip confirmation blocks competing actions, worn armor retained')
-- 第八关必须从同一个首次确认tick进入船流程，不让旧猫鞭/普通补给/开局绕行先执行。
local launched=0
task.encounters.Tick=function() launched=launched+1;return 'hold' end
task.opening.Tick=function() error('wave8 cannot wait behind a regular opener') end
task.Loot=function() error('wave8 cannot wait behind ordinary loot') end
task.Prune=function() error('wave8 cannot wait behind ordinary pruning') end
task.Entities=function() return {},{} end
task.whip.finished=true;owned={drop('whip',100008)}
snapshot.wave=8;now=now+1
assert(task:Tick()=='running' and launched==1 and not task.next_item and #task.fire_zones==0,'first authoritative wave8 update immediately dispatches boat encounter without prior-wave loot delay or stale floor hazards')
Inventory.Priority=priority
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
GetTime=oldTime;TheSim=oldSim;TheWorld=oldWorld
print('PASS: real arena cross-frame loop; bounded raw scan and one priority evaluation/item; invalid/dead filtering; immediate wave cache reset; fresh near spawn blocks rest and preserves existing combat owner')
