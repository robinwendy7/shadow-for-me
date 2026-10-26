local Data=require('shadowself/data/arena_classic');local Policy=require('shadowself/control/arena_policy')
local expectedEncounter=assert(loadstring(read_astra_source('astra/modes/arena/encounters.lua')))().WAVES_1_2
local expectedSupply=assert(loadstring(read_astra_source('astra/modes/arena/supplies.lua')))().WAVES_1_2
local function equal(a,b)
 if type(a)~='table' then assert(a==b);return end
 assert(type(b)=='table');for k,v in pairs(a) do equal(v,b[k]) end;for k in pairs(b) do assert(a[k]~=nil) end
end
equal(expectedEncounter,Data.encounters);equal(expectedSupply,Data.supplies)
assert(#Data.encounters==15 and #Policy.waves==15)
assert(Policy.Keep('panflute',15) and Policy.Keep('armorsnurtleshell',15))
assert(not Policy.Upgrade({prefab='cane'},{ruins_bat=true},15))
assert(Policy.Upgrade({prefab='spear'},{ruins_bat=true},7),'only discard known obsolete equipment after a replacement exists')
assert(not Policy.Upgrade({prefab='spear'},{},7))
assert(not Policy.Upgrade({prefab='unknown_mod_relic'},{ruins_bat=true},15),'never discard unknown player equipment')
local charged={prefab='lightninggoat',HasTag=function(_,tag) return tag=='charged' end}
assert(Policy.ArmorScore({prefab='rainhat'},'head',{charged})>Policy.ArmorScore({prefab='eyebrellahat'},'head',{charged}),'stable insulation ranking')
local saved={};for _,key in ipairs({'shadowself/control/actions','shadowself/control/arena_adapter','shadowself/control/combat'}) do saved[key]=package.loaded[key] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local snapshot={state={lobby_state='LOBBY'}};local starts,stops,prepares,cancels=0,0,0,0;local active=false
local adapter={Snapshot=function() return snapshot end,Prepare=function() prepares=prepares+1;return 'running' end,Cancel=function() cancels=cancels+1 end}
package.loaded['shadowself/control/arena_adapter']=function() return adapter end
package.loaded['shadowself/control/combat']=function() return {Running=function() return active end,Start=function() active=true;starts=starts+1;return true end,Stop=function() active=false;stops=stops+1 end} end
package.loaded['shadowself/control/actions']={Items=function() return {} end,Stop=function() end}
package.loaded['shadowself/control/arena']=nil
local p={tags={},replica={inventory={GetItems=function() return {} end}},components={playercontroller={IsBusy=function() return false end}}}
function p:HasTag(t) return self.tags[t] or false end
function p:GetPosition() return Vector3(0,0,0) end
local task=require('shadowself/control/arena')(p,{loop=true})
task.NearbyEnemies=function() return {} end
task.Entities=function() return {{prefab='hound',HasTag=function() return false end,IsValid=function() return true end,GetPosition=function() return Vector3(2,0,0) end}},{} end
task.Loot=function() return false end;task.Equip=function() return false end
assert(task:Tick()=='running' and prepares==1 and starts==0,'no combat before server-confirmed arena instance')
snapshot={state={},instance='one',generation=1,kind='PARTICIPANT',arena=true,wave=1,route='default'}
task:Tick();assert(starts==1 and task:OwnsCombat())
snapshot.wave=2;task:Tick();assert(starts==1,'wave transition reuses combat rather than starting competing threads')
local equips=0
local entities=task.Entities
task.Entities=function() return {},{} end
task.Loot=function() return true end
task.Equip=function() equips=equips+1;return true end
task:Tick();assert(equips==0,'pending pickup cannot be overwritten by equip')
task.Loot=function() return false end
task:Tick();assert(equips==1,'equip allowed when no pending pickup')
active=true;task.healing.pending={name='waffles'}
local stopped=stops;local paused=0;task.bridge.PauseAttack=function() paused=paused+1 end
task:Tick();assert(stops==stopped and paused==1,'last enemy death cannot cancel a pending meal through StopCombat')
task.healing.pending=nil;task:Tick();assert(stops>stopped,'combat can stop after meal confirmation')
task.Entities=entities
snapshot.settlement={mode_id='ARENA',visible=true};task:Tick();assert(not active and prepares==1,'settlement does not immediately requeue')
p.tags.corpse=true;snapshot.settlement=nil;task:Tick();assert(prepares==1,'await server corpse restoration')
p.tags.corpse=nil;snapshot={state={lobby_state='LOBBY'}};task:Tick();assert(prepares==2,'server-confirmed return permits next solo loop')
task:Cancel();assert(cancels==1 and not task.running and not active)
for _,key in ipairs({'shadowself/control/actions','shadowself/control/arena_adapter','shadowself/control/combat'}) do package.loaded[key]=saved[key] end
package.loaded['shadowself/control/arena']=nil;GetTime=oldTime
local parser=require('shadowself/control/request')
assert(parser.Parse('帮我循环角斗场').kind=='arena')
assert(parser.Parse('自动单人角斗场').kind=='arena')
local no=parser.Parse('不要自动角斗场');assert(not no)
assert(not parser.Parse('停止角斗场循环'),'stop must not request another arena run')
print('PASS: all15 waves match actual server data; equipment reserves/obsolete rules; authoritative instance/settlement/restore/requeue/cancel lifecycle; arena commands')
