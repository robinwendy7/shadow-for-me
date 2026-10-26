local lateCache={};for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do lateCache[k]=package.loaded["shadowself/control/"..k];package.loaded["shadowself/control/"..k]=nil end
-- Real stage scheduler and supply tracker; only game actions/terrain are simulated.
local savedA=package.loaded['shadowself/control/actions']
local savedNav=package.loaded['shadowself/control/navigation']
local savedSupplies=package.loaded['shadowself/control/supplies']
local savedStageFood=package.loaded['shadowself/control/arena_stage11_food'];package.loaded['shadowself/control/arena_stage11_food']=nil
local savedTime,savedWorld,savedNet,savedTuning,savedSim=GetTime,TheWorld,TheNet,TUNING,TheSim
local now=0;GetTime=function() return now end
TUNING={BUFF_ELECTRICATTACK_DURATION=300,BUFF_ATTACK_DURATION=240}
TheNet={GetPing=function() return 30 end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local id=62000
local function entity(name,slot,x)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame or 0 end}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local bag,head,commands={},nil,{}
local p=entity('wilson');p.components.playercontroller={IsBusy=function() return false end}
local hp,hunger,sanity=200,100,180
p.replica.health={GetCurrent=function() return hp end}
p.replica.hunger={GetCurrent=function() return hunger end}
p.replica.sanity={GetCurrent=function() return sanity end}
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HEAD and head end,
 DropItemFromInvTile=function(_,item) commands[#commands+1]={drop=item} end}
local A={Items=function() return bag end,
 Self=function(_,item,action) commands[#commands+1]={item=item,action=action};return true end}
package.loaded['shadowself/control/actions']=A
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end,Radius=function() return 3 end}
local Supplies=assert(loadfile('scripts/shadowself/control/supplies.lua'))()
package.loaded['shadowself/control/supplies']=Supplies
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage11.lua'))()
local Inv=require('shadowself/control/arena_inventory')
local policy=require('shadowself/control/arena_policy')
local chili=entity('voltgoatjelly_spice_chili');local stack=5
chili.replica.stackable={StackSize=function() return stack end,IsFull=function() return false end}
chili.components.edible={GetHealth=function() return 20 end}
local hat=entity('wathgrithr_improvedhat',EQUIPSLOTS.HEAD)
local tea=entity('sweettea');local waffle=entity('waffles')
local pauses,moved,looted=0,nil,nil
local arena={player=p,wave=11,enemies={},items={},ignored={},bridge={}}
function arena:StopCombat() pauses=pauses+1 end
function arena:Say(msg) self.message=msg end
function arena:Loot(items) looted=items;return true end
arena.encounters={FindCenter=function() return Vector3(0,0,0) end,
 Move=function(_,q,msg) moved=q;arena.message=msg;return 'hold' end}
local safe=true;arena.healing={Safe=function() return safe end}
local function fresh()
 p._shadowself_combat_buffs={};p.anim=nil;head=nil;bag={};commands={};looted=nil;moved=nil;stack=5;safe=true
 arena.bridge.priority_target=nil;arena.encounters.worm_target=nil
 return Stage(arena)
end
local function merms(name,bossname)
 local out={entity(bossname,nil,1)}
 for i=1,4 do out[#out+1]=entity(name,nil,i+2) end
 return out
end
local s=fresh();local lunar=merms('mermguard_lunar','daywalker2');arena.items={chili,hat};bag={waffle,tea}
assert(s:Tick(lunar)=='hold' and looted[1]==chili and #commands==0 and not s.prepared,'extra meal slot allows mandatory chili pickup while retaining existing reserve and tea')
bag={tea};now=.4;commands={};s:Tick(lunar)
assert(looted[1]==chili and #commands==0,'mandatory chili is picked before other food or melee')
bag={tea,chili};looted=nil;s:Tick(lunar)
assert(looted[1]==hat and not s:Allowed(lunar[2]),'mandatory hat pickup precedes melee')
assert(Inv.Want(hat,{chili},p,11) and not Inv.BelowArmorFloor(hat,11),'the 90 percent generic armor floor cannot reject required Valkyrie hat')
bag={tea,chili,hat};commands={};now=.8;s:Tick(lunar)
assert(commands[1].item==hat and commands[1].action==ACTIONS.EQUIP and not s.prepared,'EQUIP request alone is not equipped-head acknowledgement')
now=.9;s:Tick(lunar);assert(#commands==1,'unacknowledged hat requests are throttled')
head=hat;now=1.3;s:Tick(lunar)
assert(s.buffs.pending and commands[#commands].action==ACTIONS.EAT and not s:Allowed(lunar[2]),'actual equipped hat permits EAT but accepted EAT request does not permit melee')
now=1.4;s:Tick(lunar);assert(not s.buffs:Ready(),'no automatic phantom buff after an accepted request')
p.anim='eat';now=1.6;s:Tick(lunar);p.anim=nil;hunger=130;now=2.6;s:Tick(lunar)
assert(not s.buffs.pending and s.buffs:Ready() and s.buffs.state.confirmed_source=='food_recovery_after_eat','infinite stack stays at five: observed eating plus actual restored hunger confirms the buff at full health')
now=2.65;assert(s:Tick(lunar)=='hold' and moved and not s:Allowed(lunar[2]),'living merms require withdrawing seven units from scavenger pig before attacking')
lunar[1].pos=Vector3(20,0,0)
now=2.7;assert(s:Tick(lunar)=='fight' and s.target==lunar[2] and s.route=='lunar')
assert(s:Allowed(lunar[2]) and not s:Allowed(lunar[1]),'lunar merm is attacked, scavenger pig is dodge-only')
assert(arena.enemies~=nil,'route policy never removes pig threats from the shared enemy roster')
assert(s:Tick({lunar[1]})=='fight' and not s:Allowed(lunar[1]),'an empty merm scan is not merm completion')
for i=2,4 do lunar[i].tags.dead=true end
lunar[5].removed=true;s:Tick({lunar[1]})
assert(not s:Cleared() and not s:Allowed(lunar[1]),'entity removal/unload cannot substitute for the fourth confirmed death')
lunar[5].removed=nil;lunar[5].replica.health={IsDead=function() return true end}
assert(s:Tick(lunar)=='hold' and s:Cleared() and not s:Allowed(lunar[1]),'four genuine merm deaths now enter the verified health/bone preparation phase')
local previous=now;now=245
assert(not s:Allowed(lunar[1]),'expired chili immediately closes melee before the next arena tick')
now=previous
head=nil;assert(not s:Allowed(lunar[1]),'removed hat immediately closes melee')
-- Interrupted infinite-food animation cannot infer a successful buff from unrelated recovery.
s=fresh();bag={chili,hat};head=hat;arena.items={};now=10;s:Tick(lunar);p.anim='eat';now=10.1;s:Tick(lunar)
safe=false;hunger=140;now=10.2;s:Tick(lunar)
p.anim=nil;safe=true;now=11.5;s:Tick(lunar)
assert(not s.buffs:Ready() and s.buffs.pending.interrupted and moved,'unsafe eating yields to patrol, and unrelated recovery cannot fabricate buff confirmation')
stack=4;now=11.6;s:Tick(lunar)
assert(s.buffs:Ready() and s.buffs.state.confirmed_source=='inventory_consumed','late actual consumption still confirms after interruption')
-- A completed ordinary consumption also resolves if the final jelly item vanishes.
s=fresh();head=hat;bag={chili,hat};now=20;s:Tick(lunar);bag={hat};now=20.2;s:Tick(lunar)
assert(s.buffs:Ready() and not s.buffs.pending,'last consumed jelly is confirmed before checking for replacement ground food')
assert(s:Tick(lunar)=='hold' and not s.buffs.pending,'last jelly resolves before the new pig preparation phase')
-- Shadow route is based on actual marker, independent of stale server route labels.
s=fresh();bag={chili,hat};head=hat;now=30;Supplies.Record(p,chili.prefab,'inventory_consumed')
local shadow=merms('mermguard_shadow','daywalker')
assert(s:Tick(shadow)=='fight' and s.route=='shadow' and arena.detected_route=='shadow' and not s:Allowed(shadow[1]))
for i=2,5 do shadow[i].tags.dead=true end
assert(s:Tick(shadow)=='hold' and not s:Allowed(shadow[1]),'missing exact health never falls back to dummy100HP')
-- The requested normal-route reward flow supersedes the former mite-clear melee opening.
s=fresh();bag={chili,hat};head=hat;now=40
local worm={entity('worm_boss'),entity('worm_boss_head'),entity('worm_boss_dirt')}
for i=1,4 do worm[#worm+1]=entity('cave_vent_mite',nil,i+3) end
worm[2].anim='chew_big'
assert(s:Tick(worm)=='fight' and s.route=='default' and not s.reward and s.target.prefab=='cave_vent_mite' and not s:Allowed(worm[3]),'normal route starts ordinary mite melee, saves rewards for low worm HP and forbids attacking worm before confirmed mite deaths')
-- Electric-only is insufficient: spice must also be refreshed, every later wave is checked.
local context={player=p,plan={arena=true,arena_wave=function() return 12 end},enemies={},observed={},bridge={PauseAttack=function() end}}
p._shadowself_combat_buffs={electric_until=now+300};local buffs=Supplies(context);bag={chili}
assert(not buffs:Ready() and buffs:Tick() and buffs.pending,'missing chili has to be consumed even when plain electric buff remains active')
assert(buffs.checked:find('12:',1,true)==1,'later wave buff diagnostic records current wave')
context.plan.arena_wave=function() return 13 end;buffs:Check();assert(buffs.checked:find('13:',1,true)==1,'the next wave rechecks instead of assuming wave11 consumption lasts forever')
p.components.debuffable={HasDebuff=function(_,name) return name=='buff_electricattack' or name=='buff_attack' end}
assert(buffs:Ready(),'actual available server debuffs take precedence over client timers');p.components.debuffable=nil
-- Stage10 settlement drops equipped/all head gear and only non-bone body armor.
local Supply=assert(loadfile('scripts/shadowself/control/arena_supply.lua'))()
local bone=entity('armorskeleton',EQUIPSLOTS.BODY);bone.tags.armor=true
local body=entity('armordragonfly',EQUIPSLOTS.BODY);body.tags.armor=true
local rainhat=entity('rainhat',EQUIPSLOTS.HEAD);local amulet=entity('purpleamulet',EQUIPSLOTS.BODY)
assert(Inv.AfterTen(hat) and Inv.AfterTen(rainhat) and Inv.AfterTen(body) and not Inv.AfterTen(bone) and not Inv.AfterTen(amulet))
arena.wave=10;arena.NearbyEnemies=function() return {} end;bag={hat,rainhat,body,bone,amulet,tea};commands={};now=500
assert(not Supply.AfterTen(arena,{intermission=false}) and #commands==0,'no premature cleanup during active wave10')
assert(Supply.AfterTen(arena,{intermission=true}) and commands[#commands].drop==hat)
bag={rainhat,body,bone,amulet,tea};now=500.1
assert(Supply.AfterTen(arena,{intermission=true}) and #commands==1,'one acknowledged cleanup step at a time')
now=500.4;Supply.AfterTen(arena,{intermission=true});assert(commands[#commands].drop==rainhat)
bag={body,bone,amulet,tea};arena.wave=11;arena.ten_cleanup_due=true;now=500.8
assert(Supply.AfterTen(arena,{intermission=false}) and commands[#commands].drop==body,'unfinished cleanup resumes across the server wave transition')
bag={bone,amulet,tea};now=501.2
assert(not Supply.AfterTen(arena,{}) and arena.ten_cleanup_done and not arena.ten_cleanup_due)
bag={hat,bone};assert(not Supply.AfterTen(arena,{}) and #commands==3,'completed cleanup cannot discard the new stage11 hat')
-- The ordinary crowd fallback must not replace the wave11 fish-first melee plan.
local cc={player=p,plan={arena=true,arena_stage11=s,arena_wave=function() return 11 end,
 arena_priority=function() return shadow[1] end},enemies=shadow,gear={},bridge={allowed=function() return true end}}
local encounters=assert(loadfile('scripts/shadowself/control/encounters.lua'))()(cc)
local mode=encounters:Tick(shadow[1])
assert(not mode and not encounters.arena_crowd,'four source merms never trigger generic gather/flute/tornado crowd behavior')
-- An automatic armor upgrade cannot take off the mandatory stage11 headgear.
head=hat;hat.tags.armor=true
local better=entity('slurtlehat',EQUIPSLOTS.HEAD);better.tags.armor=true
better.replica.inventoryitem={GetPercentUsed=function() return 1 end}
TheSim={FindEntities=function() return {better} end}
local pickup=assert(loadfile('scripts/shadowself/control/mechanisms.lua'))()(cc)
assert(not pickup:Pickup() and not pickup.pickup,'automatic pickup preserves actual mandatory hat instead of causing an equip/unequip loop')
-- A wave transition must release the captured stage11 attack gate before wave12 starts.
local savedCombat,savedAdapter=package.loaded['shadowself/control/combat'],package.loaded['shadowself/control/arena_adapter']
local active,starts,stops,captured=true,0,0,nil
package.loaded['shadowself/control/combat']=function() return {
 Running=function() return active end,Stop=function() stops=stops+1;active=false end,
 Start=function(_,plan) starts=starts+1;active=true;captured=plan;return true end} end
package.loaded['shadowself/control/arena_adapter']=function() return {Snapshot=function()
 return {instance='stage11-run',generation=1,kind='PARTICIPANT',arena=true,wave=12,route='default'}
end} end
TheSim.FindEntities=function() return {} end;bag={};now=600
local task=assert(loadfile('scripts/shadowself/control/arena.lua'))()(p,{})
task.wave=11;task.route='default';task.instance='stage11-run';task.generation=1;task.stage11=s
task.Entities=function(self) self.entities={};return {},{} end
task.opening.Tick=function() return false end
task.encounters.Tick=function() return 'fight' end;task.encounters.MaintainCombat=function() end
assert(task:Tick()=='running' and stops==1 and starts==1 and not task.stage11 and not captured.arena_stage11,'authoritative next wave restarts the existing bridge without the stale stage11 gate')
assert(not captured.arena_bird_committed(hat),'wave12 does not inherit the tallbird no-retreat override')
task.wave=2
assert(captured.arena_bird_committed(entity('smallbird')),'tallbird commitment also holds when flute is missing; opening scheduling owns any actual control attempt')
package.loaded['shadowself/control/combat'],package.loaded['shadowself/control/arena_adapter']=savedCombat,savedAdapter
package.loaded['shadowself/control/actions']=savedA
package.loaded['shadowself/control/navigation']=savedNav
package.loaded['shadowself/control/supplies']=savedSupplies
package.loaded['shadowself/control/arena_stage11_food']=savedStageFood
GetTime,TheWorld,TheNet,TUNING,TheSim=savedTime,savedWorld,savedNet,savedTuning,savedSim
for k,v in pairs(lateCache) do package.loaded["shadowself/control/"..k]=v end
for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do if lateCache[k]==nil then package.loaded["shadowself/control/"..k]=nil end end
print('PASS: stage11 mandatory pickup/equip/actual infinite-food consumption, three source routes, confirmed add deaths, pig veto, feeding-only worm with immediate crack escape, later-wave buff checks and stage10 cleanup acknowledgement')
