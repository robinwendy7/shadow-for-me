-- Real late controllers and real ASTRA HUD normalizer; only transport/game ACKs are simulated.
local keys={'actions','navigation','arena_late_runtime','arena_rewards','arena_stage11_finish','arena_stage12','arena_lunar12',
 'astra/persistence/schema','astra/ui/mode_hud_client','astra/net/mode_hud_state','astra/net/boss_health_state'}
local saved={};local function path(k) return k:find('astra/',1,true)==1 and k or 'shadowself/control/'..k end
for _,k in ipairs(keys) do saved[k]=package.loaded[path(k)];package.loaded[path(k)]=nil end
local oldTime,oldWorld,oldSim,oldTuning,oldActions=GetTime,TheWorld,TheSim,TUNING,ACTIONS
local now=0;GetTime=function() return now end
TUNING={ARMOR_SKELETON_COOLDOWN=5};ACTIONS={EQUIP={},RUMMAGE={},PICKUP={}}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheSim={FindEntities=function() return {} end}
local roster,bag,equips,commands,opened={},{},{},{},{}
local id=65000
local function ent(name,x,z)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={},components={},percent=1}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame or 0 end}
 e.Transform={GetRotation=function() return 0 end}
 e.replica.inventoryitem={classified={percentused={value=function() return e.percent*100 end}}}
 return e
end
local p=ent('wilson');p.components.playercontroller={IsBusy=function() return false end}
p.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
p.replica.inventory={GetEquippedItem=function(_,slot) return equips[slot] end,GetItems=function() return bag end,
 GetNumSlots=function() return 15 end,GetItemInSlot=function(_,slot) return bag[slot] end,
 DropItemFromInvTile=function(_,item) commands[#commands+1]={kind='drop',item=item} end,
 MoveItemFromCountOfSlot=function(_,slot,target,count) commands[#commands+1]={kind='seed',slot=slot,target=target,count=count} end}
local A={Items=function() local all={};for _,e in pairs(bag) do all[#all+1]=e end;for _,e in pairs(equips) do all[#all+1]=e end;return all end,
 Self=function(_,item,act) commands[#commands+1]={kind=act,item=item};return true end,
 Scene=function(_,item,act,guard) assert(not guard or guard());commands[#commands+1]={kind=act,item=item};return true end,
 Stop=function() commands[#commands+1]={kind='stop'} end}
package.loaded[path('actions')]=A
package.loaded[path('navigation')]={Safe=function() return true end,Select=function(_,q) return q end}
for _,k in ipairs({'astra/persistence/schema','astra/net/mode_hud_state','astra/net/boss_health_state','astra/ui/mode_hud_client'}) do
 package.loaded[k]=assert(loadstring(read_astra_source(k..'.lua')))()
end
local R=require(path('arena_late_runtime'));local Finish=require(path('arena_stage11_finish'))
local Chests=require(path('arena_rewards'));local Stage12=require(path('arena_stage12'))
local arena={player=p,wave=11,running=true,instance='late065',generation=4,enemies={},items={},ignored={},bridge={}}
function arena:StopCombat() self.stops=(self.stops or 0)+1 end
function arena:Say(m) self.message=m end
function arena:Loot(items) self.looted=items;return true end
arena.encounters={FindCenter=function() return Vector3(0,0,0) end,Move=function(_,q) arena.goal=q;return 'hold' end}
local function state()
 local s={player=p,arena=arena,context={player=p,enemies={},plan={arena_center=function() return Vector3(0,0,0) end}},phase='boss'}
 function s:Cleared() return true end
 function s:Patrol() arena:StopCombat();self.target=nil;return 'hold' end
 return s
end
local pig=ent('daywalker2');local s=state();s.boss=pig
pig.replica.health={GetCurrent=function() return 100 end}
assert(R.Health(s,pig)==nil,'health_replica dummy100 is never accepted as absolute boss health')
local model={schema_version=1,visible=true,scene_revision=1,bosses={{id=tostring(pig.GUID),prefab=pig.prefab,name='pig',
 current=1000,total=1000,x=0,z=0,attackers=1,damage=0,engaged=true,invincible=false}},focus={},alive={}}
local function net(v) return {value=function() return v end} end
p.astra_player_classified={astra_instance_id=net('late065'),astra_generation=net(4),
 astra_state_payload=net({schema_version=1,states={{schema_version=1,state_id='late065:boss_health',instance_id='late065',generation=4,version=1,value=model}}})}
now=.3;assert(R.Health(s,pig)==1000,'actual ASTRA mode HUD validates exact GUID/prefab health')
arena.generation=5;assert(R.Health(s,pig)==nil,'a previous generation cannot trigger low-health finishing');arena.generation=4
local bone=ent('armorskeleton');equips[EQUIPSLOTS.BODY]=bone;arena.enemies={pig}
assert(Finish.Pig(s,{pig})=='hold','first observed bone waits a full conservative cooldown')
now=5.7;assert(Finish.Pig(s,{pig})=='fight' and s.phase=='pig_four')
arena.bridge.coordinator={h={ent=pig,IsHitingFrame=function() return p.frame==8 end},gear={AttackRange=function() return 2 end}}
p.tags.attack=true;p.pos=Vector3(6,0,0);p.frame=8;assert(R.Hits(s,pig)==0,'air swings cannot count')
p.pos=Vector3(1,0,0);p.tags.attack=nil;R.Hits(s,pig)
for i=1,4 do p.tags.attack=true;p.frame=1;R.Hits(s,pig);p.frame=8;assert(R.Hits(s,pig)==i);R.Hits(s,pig);assert(s.hits==i) end
assert(not Finish.Allowed(s,pig),'four completed impacts close every attack entry immediately')
assert(Finish.Pig(s,{pig})=='hold' and s.phase=='pig_orbit')
local pile=ent('junk_pile_big');pile.GetPhysicsRadius=function() return 3.6 end
Finish.Orbit(s,{pile})
assert(math.abs(math.sqrt(arena.goal:DistSq(pile.pos))-4.4)<.001,'orbit hugs real 3.6-radius junk pile plus player collision instead of nine-unit circle')
now=11.6;assert(Finish.Pig(s,{pig})=='hold','six-second orbit cannot end early')
now=11.8;assert(Finish.Pig(s,{pig})=='fight' and s.hits==0,'six seconds plus ready bone starts next four attacks')
bone.percent=.8;now=12;Finish.BoneReady(s);assert(not Finish.BoneReady(s),'observed real fuel loss restarts cooldown')
-- Preserve real ASTRA decoding while changing its published payload identity.
model.bosses[1].current=201;p.astra_player_classified.astra_state_payload=net({schema_version=1,states={{schema_version=1,state_id='late065:boss_health',instance_id='late065',generation=4,version=2,value=model}}})
now=12.3;Finish.Allowed(s,pig);assert(not s.finish,'201HP does not start the <=200 finish flow')
model.bosses[1].current=200;p.astra_player_classified.astra_state_payload=net({schema_version=1,states={{schema_version=1,state_id='late065:boss_health',instance_id='late065',generation=4,version=3,value=model}}})
now=12.7;assert(not Finish.Allowed(s,pig) and s.finish,'absolute Boss200HP stops normal attacks before reward transaction')
-- Four distinct boxes; wrong items remain inside; requests never imply successful transfers.
commands={};bag={};equips={};p.tags.attack=nil
local crown=ent('alterguardianhat');local seed=ent('lunar_seed');seed.count=5
seed.replica.stackable={StackSize=function() return seed.count end,IsFull=function() return false end}
local staff=ent('staff_lunarplant');local ruinshat=ent('ruinshat');local armorruins=ent('armorruins')
local boxes={};local contents={{crown},{seed},{ruinshat,armorruins},{staff}}
local function container(owner,items,slots)
 local c={items=items,open=false,slots=slots}
 function c:IsOpenedBy() return self.open end
 function c:GetItems() return self.items end
 function c:GetItemInSlot(i) return self.items[i] end
 function c:GetNumSlots() return self.slots end
 function c:Close() self.open=false end
 function c:MoveItemFromAllOfSlot(slot,target) assert(target==p);commands[#commands+1]={kind='take',box=owner,slot=slot,item=self.items[slot]} end
 owner.replica.container=c;return c
end
for i=1,4 do local b=ent('chest_mimic',i*3,0);container(b,contents[i],3);boxes[i]=b end
local hatc=container(crown,{},5)
s=state();arena.stage11=s;arena.enemies={};local rewards=Chests(s,true);s.reward=rewards
local transferred=0;local seenTake={};local openCount={}
for step=1,65 do
 now=now+.6;local ready=rewards:Tick(boxes)
 local a=commands[#commands]
 if a and a.kind==ACTIONS.RUMMAGE then a.item.replica.container.open=true;openCount[a.item]=(openCount[a.item] or 0)+1 end
 if rewards.pending and not seenTake[rewards.pending] then
  local t=rewards.pending;seenTake[t]=true
  local old=#commands;now=now+.1;assert(not rewards:Tick(boxes) and #commands==old,'unconfirmed take neither advances nor sends another action')
  bag[#bag+1]=t.item;t.box.replica.container.items[t.slot]=nil;transferred=transferred+1
 end
 if a and a.kind==ACTIONS.EQUIP then
  equips[a.item==crown and EQUIPSLOTS.HEAD or EQUIPSLOTS.HANDS]=a.item
  if a.item==crown then hatc.open=true end
 end
 if rewards.seed_pending then
  local before=rewards.seed_pending.before;assert(not rewards:Ready())
  now=now+.1;assert(not rewards:Tick(boxes) and rewards.seed_pending,'seed transfer needs actual destination ACK')
  hatc.items[before+1]=ent('lunar_seed');seed.count=seed.count-1
  if seed.count==0 then for i,e in pairs(bag) do if e==seed then bag[i]=nil end end end
 end
 if ready then break end
end
assert(rewards:Ready() and transferred==3 and not s.failed,'four inspected boxes, five individual seeds and actual equipped staff complete normal branch preparation')
assert(boxes[3].replica.container.items[1]==ruinshat and boxes[3].replica.container.items[2]==armorruins,'excluded ruins equipment remains in its box')
local visits=0;for _ in pairs(rewards.visited) do visits=visits+1 end;assert(visits==4)
assert(#hatc.items==5,'five slots accept five separate seeds, never an unbounded stack transfer')
-- Independent worm cycle uses real targetability and completed impacts, not action requests.
s.reward=rewards;s.route='default';s.head=ent('worm_boss_head');s.head.anim='chew_big'
s.boss=ent('worm_boss');model.bosses[1].id=tostring(s.boss.GUID);model.bosses[1].prefab='worm_boss';model.bosses[1].current=1000
local published=3
local function publish()
 published=published+1
 p.astra_player_classified.astra_state_payload=net({schema_version=1,states={{schema_version=1,state_id='late065:boss_health',instance_id='late065',generation=4,version=published,value=model}}})
 now=now+.3
end
publish()
local root=s.boss;s.boss=nil;assert(R.Health(s,nil)==1000,'INLIMBO worm root health comes from the unique real server record, never the dirt dummy health');s.boss=root
local dirt=ent('worm_boss_dirt');s.dirts={dirt};s.context.player=p
p.pos=Vector3(1,0,0);s.phase='boss';s.reward=nil;s.finish=nil;arena.bridge.coordinator.h.ent=dirt
assert(Finish.Worm(s,{})=='fight' and s.phase=='worm_melee' and not s.reward,'normal worm attacks immediately in its real window without patrol or opening rewards')
assert(Finish.Allowed(s,dirt),'worm real window allows ordinary melee before low-health finish')
s.head.anim='head_idle_loop';assert(not Finish.Allowed(s,dirt) and Finish.Worm(s,{})=='hold','worm movement stops attacks without a timed outer patrol')
s.head.anim='chew_big';dirt.tags.notarget=true;assert(not Finish.Allowed(s,dirt),'unattackable worm remains forbidden')
dirt.tags.notarget=nil;model.bosses[1].current=199;publish();assert(not Finish.Allowed(s,dirt) and s.finish,'exact worm199HP locks ordinary damage before reward completion')
s.reward=rewards;local cane=ent('cane');bag[#bag+1]=staff;bag[#bag+1]=cane;equips[EQUIPSLOTS.HANDS]=cane
assert(Finish.Worm(s,{})=='hold','finished four-box rewards still require real staff equip')
equips[EQUIPSLOTS.HANDS]=staff;assert(Finish.Worm(s,{})=='fight' and s.phase=='staff_finish' and Finish.Allowed(s,dirt),'crown/seed/staff confirmed finish targets the actual attackable worm dirt')
hatc.items={};assert(not rewards:Ready() and not Finish.Allowed(s,dirt),'crown depletion closes the final staff gate')
-- Shadow12: exact source roster, sequential confirmed deaths, one bite lure and armor ACK.
arena.wave=12;commands={};bag={};equips={};s=Stage12(arena);arena.stage12=s
local hat=ent('lunarplanthat');local sword=ent('sword_lunarplant');local night=ent('nightsword');local lunararmor=ent('armor_lunarplant')
bag={hat,sword,night,lunararmor,bone};equips[EQUIPSLOTS.HEAD]=hat;equips[EQUIPSLOTS.HANDS]=night
local rabbit=ent('bunnyman',1,0);local spider=ent('spider_dropper',1.5,0)
local wings=ent('shadowthrall_wings',15,0);local hands=ent('shadowthrall_hands',0,15);local horns=ent('shadowthrall_horns',-15,0)
local mouth=ent('shadowthrall_mouth',-15,-15);local nightmare=ent('ruinsnightmare',15,15)
local all={rabbit,spider,wings,hands,horns,mouth,nightmare};arena.enemies=all;p.pos=Vector3(0,0,0)
assert(s:Tick(all)=='fight' and s.target==rabbit and s.phase=='rabbit_spiders')
rabbit.removed=true;assert(s:Tick(all)=='hold' and s.phase=='rabbit_spiders','lost/unloaded rabbit is not dead')
rabbit.removed=nil;rabbit.tags.dead=true;assert(s:Tick(all)=='fight' and s.target==spider)
spider.tags.dead=true;equips[EQUIPSLOTS.HANDS]=sword;p.pos=Vector3(14,0,0)
assert(s:Tick(all)=='fight' and s.target==wings)
wings.tags.dead=true;p.pos=Vector3(0,0,14);assert(s:Tick(all)=='fight' and s.target==hands)
hands.tags.dead=true;p.pos=Vector3(-14,0,0);assert(s:Tick(all)=='fight' and s.target==horns)
horns.tags.dead=true;p.pos=Vector3(14,0,15);assert(s:Tick(all)=='fight' and s.target==nightmare and s.phase=='extra_nightmare')
nightmare.tags.dead=true;mouth.tags.stealth=true;p.pos=Vector3(0,0,0)
assert(s:Tick(all)=='hold' and not s.bait,'lure cannot begin before actual lunar armor equip')
equips[EQUIPSLOTS.BODY]=lunararmor;assert(s:Tick(all)=='hold' and s.bait and not s:Allowed(mouth))
mouth.anim='stalk_bite';s:Tick(all);mouth.anim='stalk_smile_pst';s:Tick(all)
assert(s.bait_used and not s.bait,'one observed bite ends the sole no-dodge lure permission')
mouth.tags.stealth=nil;p.pos=Vector3(-14,0,-15);assert(s:Tick(all)=='fight' and s.target==mouth)
mouth.tags.dead=true;s:Tick(all);assert(s.phase=='drop_lunar_armor')
local keep={};for _,e in ipairs(bag) do if e~=lunararmor then keep[#keep+1]=e end end;bag=keep;equips[EQUIPSLOTS.BODY]=nil
s:Tick(all);assert(not s:Allowed(mouth),'unacknowledged bone equip never starts next target')
equips[EQUIPSLOTS.BODY]=bone;assert(s:Tick(all)=='hold' and s.phase=='confirmed_clear')
s:Stop();assert(not s.bait,'stop immediately releases the one-bite permission')
-- A different random source composition contains rocky instead of a second small target.
s=Stage12(arena);arena.stage12=s;local rocky=ent('rocky',0,0);rabbit.tags.dead=true;mouth.tags.dead=nil;mouth.tags.stealth=true
all={rabbit,rocky,wings,hands,horns,mouth,nightmare};equips[EQUIPSLOTS.BODY]=lunararmor;bag[#bag+1]=lunararmor
p.pos=Vector3(5,0,0);s:Tick(all);assert(not s.bait,'rocky within10 prevents the one-bite setup')
p.pos=Vector3(12,0,0);s:Tick(all);assert(s.bait,'actual rocky separation opens the lure')
mouth.tags.dead=true;s:Tick(all);keep={};for _,e in ipairs(bag) do if e~=lunararmor then keep[#keep+1]=e end end;bag=keep
equips[EQUIPSLOTS.BODY]=nil;s:Tick(all);assert(not s.target,'bone request alone cannot release rocky attacks')
equips[EQUIPSLOTS.BODY]=bone;p.pos=Vector3(1,0,0);assert(s:Tick(all)=='fight' and s.target==rocky and s:Allowed(rocky))
-- Lunar route source supplies and grazer attack are restricted to wave12.
local Lunar=require(path('arena_lunar12'));local Inv=require(path('arena_inventory'))
local vh=ent('voidclothhat');vh.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HEAD end}
local va=ent('armor_voidcloth');va.replica.equippable={EquipSlot=function() return EQUIPSLOTS.BODY end}
assert(not Inv.BelowArmorFloor(vh,12) and not Inv.BelowArmorFloor(va,12) and Inv.BelowArmorFloor(va,11),'only wave12 admits source planar gear below the ordinary physical floor')
arena.wave=12;arena.route='lunar';arena.detected_route=nil;bag={vh,va};equips={};arena.items={}
assert(Lunar.Prepare(arena));equips[EQUIPSLOTS.HEAD]=vh;assert(Lunar.Prepare(arena));equips[EQUIPSLOTS.BODY]=va
assert(not Lunar.Prepare(arena),'actual head and body ACK complete lunar preparation')
local grazer=ent('lunar_grazer');grazer.anim='devour';grazer.frame=25;p.pos=Vector3(1,0,0)
local c={player=p,plan={arena_lunar12=arena.lunar12}}
local dodge=Lunar.Dodge(c,grazer,nil);assert(dodge and dodge.noattack and dodge.fn():DistSq(grazer.pos)>2^2)
grazer.frame=32;assert(not Lunar.Dodge(c,grazer,nil),'finished grazer impact releases output')
c.plan.arena_lunar12=nil;grazer.frame=0;assert(not Lunar.Dodge(c,grazer,nil),'ordinary-world grazer behavior is untouched')
for _,k in ipairs(keys) do package.loaded[path(k)]=saved[k] end
GetTime,TheWorld,TheSim,TUNING,ACTIONS=oldTime,oldWorld,oldSim,oldTuning,oldActions
print('PASS: exact ASTRA health with generation/GUID checks; completed-hit counting, bone cooldown/four-hit/six-second cycle; four chests and five crown slots with transport ACKs; shadow12 exact sequence and one-bite lure')
