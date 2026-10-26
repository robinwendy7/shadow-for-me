local Inventory=require('shadowself/control/arena_inventory')
local Policy=require('shadowself/control/arena_policy')
local id=95000
local function item(name,slot,percent)
 id=id+1
 local e={prefab=name,GUID=id,replica={},components={},pos=Vector3(0,0,0),tags={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return 4 end
 function e:GetBasicDisplayName() return self.prefab end
 e.replica.inventoryitem={IsHeld=function() return false end,GetEquipRestrictedTag=function() end,GetWalkSpeedMult=function() return 1 end,
  classified={percentused={value=function() return percent or 100 end}},CanDeploy=function() return true end}
 if slot then e.replica.equippable={EquipSlot=function() return slot end,IsRestricted=function() return false end} end
 return e
end
local oldTime,oldWorld,oldTiles=GetTime,TheWorld,WORLD_TILES
local now=0;GetTime=function() return now end;WORLD_TILES={OCEAN_ICE=9,COTL_BRICK=10}
local hand;local bag={};local p={replica={},components={},pos=Vector3(15,0,0),platform=nil}
function p:HasTag() return false end
function p:GetPosition() return self.pos end
function p:GetCurrentPlatform() return self.platform end
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HANDS and hand end,GetItems=function() return bag end,GetEquips=function() return hand and {hand} or {} end,GetOverflowContainer=function() end}
p.components.playercontroller={IsBusy=function() return false end}
local spear=item('spear',EQUIPSLOTS.HANDS);spear.tags.weapon=true
local boomerang=item('boomerang',EQUIPSLOTS.HANDS);boomerang.tags.weapon=true
for wave=1,15 do
 assert(not Inventory.Want(boomerang,{},p,wave) and not Inventory.Want(boomerang,{spear},p,wave),'never pick boomerang, even with empty inventory')
 assert(not Inventory.Weapon(boomerang,p) and Inventory.Obsolete(boomerang,{boomerang},p,wave),'boomerang does not replace melee weapons and can be discarded')
end
local spike=item('tentaclespike',EQUIPSLOTS.HANDS);spike.tags.weapon=true
local sword=item('nightsword',EQUIPSLOTS.HANDS);sword.tags.weapon=true
local fresh=item('nightsword',EQUIPSLOTS.HANDS,100);fresh.tags.weapon=true
local old=item('nightsword',EQUIPSLOTS.HANDS,10);old.tags.weapon=true
local star=item('nightstick',EQUIPSLOTS.HANDS);star.tags.weapon=true
local cane=item('cane',EQUIPSLOTS.HANDS);cane.tags.weapon=true
assert(Inventory.ForecastDiscard({spear},p,2,'default')==spear,'wave2 intermission discards spear for guaranteed wave3 tentacle spike')
assert(not Inventory.ForecastDiscard({spike},p,3,'default'),'10 percent night sword cannot justify dropping current spike')
assert(Inventory.ForecastDiscard({spike},p,4,'default')==spike,'guaranteed fresh ham bat replaces spike before wave5')
assert(not Inventory.ForecastDiscard({star,cane},p,6,'default'),'morningstar and cane preserved despite guaranteed ruins bat')
assert(not Inventory.ForecastDiscard({sword},p,6,'default'),'lower damage next weapon cannot displace current sword')
assert(not Inventory.ForecastDiscard({sword},p,15,'default'),'last wave has no forecast equipment')
local planar=item('sword_lunarplant',EQUIPSLOTS.HANDS);planar.tags.weapon=true
assert(not Inventory.ForecastDiscard({planar},p,6,'default'),'higher physical damage does not discard planar weapon')
local wood=item('armorwood',EQUIPSLOTS.BODY)
for _,gear in ipairs({wood,spear,star,spike}) do
 for _,supply in ipairs({item('panflute'),item('waffles'),item('icestaff3')}) do
  assert(Inventory.Priority(gear,3)>Inventory.Priority(supply,3),'armor and melee weapons precede tools and food')
 end
end
assert(Inventory.Priority(item('firestaff'),2)<Inventory.Priority(item('waffles'),2),'trap staff remains last')
assert(Inventory.Obsolete(spear,{spear,spike},p,3))
assert(Inventory.Obsolete(spike,{spike,sword},p,4))
local hambat=item('hambat',EQUIPSLOTS.HANDS);hambat.tags.weapon=true
hambat.replica.inventoryitem.classified.perish={value=function() return 10 end}
assert(Inventory.Physical(hambat)<51 and Inventory.Obsolete(hambat,{hambat,spike},p,6),'actual client perish values, not full-strength stale ham bat')
assert(not Inventory.Obsolete(star,{star,sword},p,8),'morningstar reserved before ninth wave independent of stronger main weapon')
assert(not Inventory.Obsolete(cane,{cane,sword},p,10),'cane not ranked as disposable weapon')
assert(not Inventory.Want(spear,{sword},p,7),'do not re-pick inferior discarded weapons')
assert(Inventory.Want(fresh,{old},p,10) and Inventory.Obsolete(old,{old,fresh},p,10),'real classified durability drives replacement')
assert(Inventory.Discard({spear},p,3,sword)==spear,'full bag can exchange low damage for an actual ground upgrade')
assert(not Inventory.Discard({sword},p,3,spear),'never discard strong weapon for weaker floor drop')
local armor=item('armorruins',EQUIPSLOTS.BODY);local grass=item('armorgrass',EQUIPSLOTS.BODY)
assert(Inventory.Want(armor,{grass},p,9) and Inventory.Obsolete(grass,{grass,armor},p,9))
assert(not Inventory.Discard({grass,armor},p,6),'before ocean preparation spare armor is retained with free bag space')
assert(Inventory.Discard({grass,armor},p,10)==grass,'ocean preparation clears obsolete spare grass armor when stronger armor is owned')
assert(not Inventory.Discard({grass},p,6,armor),'never discard worn/only armor before floor upgrade is acquired')
assert(Inventory.Priority(cane,3)>Inventory.Priority(spike,3) and Inventory.Priority(spike,3)>Inventory.Priority(armor,3),'third-wave cane precedes weapons and armor')
assert(Inventory.Priority(armor,3)>Inventory.Priority(item('rainhat',EQUIPSLOTS.HEAD),3),'rainhat is utility, not protective helmet')
assert(not Inventory.Armor(item('rainhat',EQUIPSLOTS.HEAD)))
local marble=item('armormarble',EQUIPSLOTS.BODY);local wood=item('armorwood',EQUIPSLOTS.BODY)
assert(Inventory.Want(marble,{wood},p,4),'high absorption armor is not discarded merely because mobile armor has higher equip score')
local planar=item('armor_lunarplant',EQUIPSLOTS.BODY)
assert(not Inventory.Obsolete(planar,{planar,armor},p,10),'ordinary armor cannot replace planar defense reserve')
assert(Inventory.Special('icestaff2',12) and not Inventory.Special('nightstick',15))
local boatkit=item('boat_item');assert(Inventory.Obsolete(boatkit,{},p,9),'used ocean equipment expires after wave8')
local food=item('meatballs');local flute=item('panflute')
assert(not Inventory.Discard({food},p,5,flute),'keep last known healing/food supply')
local unknown=item('player_keepsake');assert(not Inventory.Obsolete(unknown,{sword},p,15))
local Guard=require('shadowself/control/guardcontrol')
assert(Guard.Ice({plan={arena=true}},item('icestaff2')) and not Guard.Ice({plan={}},item('icestaff2')),'custom ice wand only enabled in arena plan')
local torch=item('torch',EQUIPSLOTS.HANDS);torch.tags.weapon=true
local priorHand=hand;hand=torch
local gearContext={player=p,plan={arena=true},enemies={},owner={perception={Inventory=function() return {torch} end}}}
local gear=require('shadowself/legacy/registry').CombatEquipment(gearContext)
assert(not gear:Weapon(),'sole torch is not an ordinary arena combat weapon after disarm')
gearContext.plan.arena=false;assert(gear:Weapon()==torch,'ordinary non-arena torch behavior remains available')
hand=priorHand

local savedA=package.loaded['shadowself/control/actions'];local savedS=package.loaded['shadowself/control/arena_encounters']
local moves,deploys,rows,equips,loots,stops=0,0,0,0,0,0;local lastmove
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Stop=function() stops=stops+1 end,
 Move=function(_,q) moves=moves+1;lastmove=q end,Deploy=function() deploys=deploys+1;return true end,
 Ground=function(_,q,act) rows=rows+1;assert(act==ACTIONS.ROW);return true end,
 Self=function() equips=equips+1;return true end}
package.loaded['shadowself/control/arena_encounters']=nil
local E=require('shadowself/control/arena_encounters')
local arena={player=p,wave=8,items={},bridge={},Inventory=function() return {},bag end,
 Prune=function() return false end,StopCombat=function() stops=stops+1 end,Say=function() end,Loot=function() loots=loots+1;return false end}
TheWorld={Map={IsOceanAtPoint=function() return true end,IsPassableAtPoint=function() return true end,GetTileAtPoint=function() return 9 end,GetPlatformAtPoint=function() return nil end}}
local s=E(arena);s.center=Vector3(0,0,0);p.pos=Vector3(28,0,0)
arena.items={food,boatkit,oar};bag={};local cleaned=false
arena.Prune=function() cleaned=true;return true end
local beforeLoot=loots
assert(s:Crab({})=='hold' and not cleaned and loots==beforeLoot+1,'boat pickup is attempted before unrelated cleanup; pickup itself handles a full bag')
arena.Prune=function() return false end
arena.Loot=function(_,items) assert(#items==1 and items[1]==boatkit,'missing boat bypasses all ordinary supplies');return true end
assert(s:Crab({})=='hold' and deploys==0,'ground boat pickup precedes deploying and boarding')
arena.Loot=function() loots=loots+1;return false end
bag={boatkit};assert(s:Crab({})=='hold' and deploys==1)
now=.2;s:Crab({});assert(deploys==1,'do not resend unacknowledged deploy every tick')
now=7;assert(s:Crab({})=='hold' and not s.deploy,'delayed boat ack retries without walking into sea or ending arena loop')
local boat=item('boat');boat.pos=Vector3(15,0,0)
assert(s:Crab({boat})=='hold' and lastmove==boat.pos and s.deploy==nil,'board only server-replicated boat')
local oar=item('oar_driftwood',EQUIPSLOTS.HANDS);oar.tags.oar=true
bag={oar};p.platform=boat;hand=nil;p.pos=Vector3(11.6,0,0)
s:Crab({boat});assert(equips==1 and rows==0,'wait for authoritative oar hand-slot confirmation')
hand=oar;now=8;s:Crab({boat});assert(rows==1,'confirmed oar submits ROW rather than WALKTO through water')
s.row_count=6;s.row_pending=nil;boat.pos=Vector3(5,0,0);p.pos=Vector3(4,0,0)
assert(s:Crab({boat})=='hold','arrive center and wait for boss rather than attack nonexistent target')
local king=item('crabking');king.pos=Vector3(0,0,0)
local bat=item('ruins_bat',EQUIPSLOTS.HANDS);bag={oar,bat}
local beforeBat=equips
assert(s:Crab({boat,king})=='hold' and equips==beforeBat+1,'at center request actual ruins-bat equip before starting combat')
hand=bat
assert(s:Crab({boat,king})=='fight')
king.tags.icewall=true
assert(s:Crab({boat,king})=='hold' and lastmove:DistSq(king.pos)>=6^2,'board ice at a clear ring point, not boss feet')
TheWorld.Map.IsOceanAtPoint=function() return false end;TheWorld.Map.GetTileAtPoint=function() return 0 end
p.platform=nil;p.pos=Vector3(0,0,0);king.tags.dead=true
assert(s:Crab({king})=='hold' and lastmove:DistSq(s.start_point)<.001,'boss death returns to the recorded eighth-wave starting position')
p.pos=lastmove;now=9;assert(s:Crab({king})=='hold','wait at shore for authoritative next wave')
king.tags.dead=nil;king.tags.icewall=true;p.pos=Vector3(0,0,0);s:Reset();s.center=king.pos
local wall=item('crabking_icewall');now=20;s:Crab({king,wall});now=21;s:Crab({king})
local beforeContinue=moves;local beforeRows=rows
now=37;assert(s:Crab({king})=='fight' and not s.retreat and moves==beforeContinue,'ice deadline never interrupts attacking living king')
king.tags.icewall=nil;s.retreat=true
now=60;assert(s:Crab({king})=='fight' and not s.retreat and rows==beforeRows,'phase two ending clears stale retreat, never boards or rows')
local cracked=item('boat_ice_crabking');cracked.AnimState={IsCurrentAnimation=function(_,name) return name=='cracked2' end}
assert(s:Crab({king,cracked,boat})=='fight' and moves==beforeContinue,'cracked ice and nearby boat do not stop post-phase-two output')
assert(s:Crab({})=='fight','one missed scan retains known living boss and post-phase-two combat')
-- 返程忽略小蟹攻击，持续撤到陆地，不借船跨越水面。
TheWorld.Map.GetTileAtPoint=function() return 0 end
s.start_point=Vector3(20,0,0);king.tags.dead=true;p.pos=Vector3(0,0,0);now=61
local mob=item('crabking_mob');mob.pos=Vector3(1,0,0)
local mobanim='atk1';mob.AnimState={IsCurrentAnimation=function(_,name) return name==mobanim end}
local route=require('shadowself/control/arena_return')
assert(s:Crab({king,mob,boat})=='hold' and lastmove:DistSq(s.start_point)<.001,'return ignores actual crab swing rather than stopping or dodging')
mobanim='idle';now=62
assert(s:Crab({king,mob,boat})=='hold' and lastmove:DistSq(s.start_point)<.001,'idle crab does not block resuming home route')
-- 旋转冲撞在身前形成扫掠通道，不能只躲当前小蟹中心。
mobanim='atk_loop';mob.pos=Vector3(-4,0,0);mob.Transform={GetRotation=function() return 0 end}
local escape,danger=route.Dodge(p,{mob},s.start_point)
assert(danger and escape and math.abs(escape.z)>2,'return avoids forward spin lane before the crab reaches player')
mob.tags.sleeping=true;assert(not select(2,route.Dodge(p,{mob},s.start_point)),'sleeping crab is not an active return threat');mob.tags.sleeping=nil
-- Boss死亡后即使小蟹正在攻击，也先确认上岸，再去较远的入场点。
TheWorld.Map.IsOceanAtPoint=function(_,x) return x<18 end
TheWorld.Map.GetTileAtPoint=function(_,x) return x<18 and WORLD_TILES.OCEAN_ICE or 0 end
s.start_point=Vector3(24,0,0);s.return_point=nil;s.next_return=nil;now=62.2
assert(s:Crab({king,mob,boat})=='hold' and s.return_stage=='home' and lastmove:DistSq(s.start_point)<.001,
 'confirmed death immediately walks across ice to the entry point, ignoring attacking crabs')
p.pos=lastmove;now=62.5
assert(s:Crab({king,mob,boat})=='hold' and s.return_stage=='home' and lastmove:DistSq(s.start_point)<.001,
 'arrival at the entry point holds until server advances')
p.pos=Vector3(0,0,0)
TheWorld.Map.IsOceanAtPoint=function() return true end;TheWorld.Map.GetTileAtPoint=function() return 0 end
local beforeWait=moves;now=63
assert(s:Crab({king,boat})=='hold' and rows==beforeRows and moves==beforeWait,'no walking route means wait, never board or row toward return point')
TheWorld.Map.IsOceanAtPoint=function() return false end;TheWorld.Map.GetTileAtPoint=function() return 10 end
TheWorld.Map.GetPlatformAtPoint=function(_,x,z) if x>9 and x<11 then return boat end end
assert(not route.Clear(Vector3(8,0,0),Vector3(12,0,0)),'return rejects a boat even if map reports passable ground underneath')
TheWorld.Map.GetPlatformAtPoint=function() end
s:Reset();assert(not s.second_phase and not s.retreat,'new encounter resets post-phase-two commitment')

-- 通用蠕虫处理器独立回归；第十一关真实组合由arena_stage11062覆盖。
arena.wave=12;s:Reset();p.pos=Vector3(8,0,0);bag={grass}
local head=item('worm_boss_head');head.pos=Vector3(0,0,0)
local anim='chew_big';head.AnimState={IsCurrentAnimation=function(_,name) return name==anim end}
local dirt=item('worm_boss_dirt');dirt.replica.inventoryitem=nil;dirt.replica.combat={};dirt.pos=Vector3(0,0,0)
local watched={};arena.Loot=function(_,items) watched=items;return true end
local rescue=item('armordreadstone',EQUIPSLOTS.BODY);rescue.pos=Vector3(7,0,0)
assert(s:Worm({head,dirt,rescue})=='hold' and watched[1]==rescue,'rescue superior dropped armor before worm can eat it')
arena.Loot=function() return false end
assert(s:Worm({head,dirt})=='fight' and s.worm_target==dirt and s:Allowed(dirt),'chewing attacks real redirect-damage dirt, not noncombat head')
anim='emerge_eat';p.pos=Vector3(1,0,0);now=10
assert(s:Worm({head,dirt})=='hold' and not s.worm_target and lastmove:DistSq(head.pos)>=4^2,'stop punish and move out before emergence swallow')
anim='head_idle_loop';p.pos=Vector3(8,0,0);food.pos=Vector3(6,0,0);now=11
assert(s:Worm({head,dirt,food})=='hold' and lastmove:DistSq(food.pos)>1.5^2,'ground food remains bait; lure stands outside creature-swallow radius')
local fixed=s.lure.goal;p.pos=Vector3(9,0,0);now=11.5;s:Worm({head,dirt,food});assert(s.lure.goal==fixed,'lure point stays fixed while player moves')
local crack=item('worm_boss_dirt_ground_fx');crack.pos=p.pos;crack.replica.inventoryitem=nil;now=12
assert(s:Tick({crack,armor})=='hold' and lastmove:DistSq(crack.pos)>=4^2,'generic worm handler interrupts armor rescue at pre-emergence crack')
local mite=item('cave_vent_mite');mite.replica.inventoryitem=nil;mite.replica.combat={};mite.pos=Vector3(9,0,0)
assert(s:Worm({head,dirt,mite})=='fight' and s.add_target==mite,'nearby stage companions are fought during bait wait')
head.tags.dead=true;dirt.tags.dead=true
assert(not s:Tick({head,dirt,mite}),'generic worm handler releases dead worm visuals; wave11 route is tested separately')
local oldSend,oldRPC=SendRPCToServer,RPC.ControllerActionButtonDeploy
local sent;RPC.ControllerActionButtonDeploy=12345;SendRPCToServer=function(...) sent={...} end
p.components.playercontroller.ismastersim=false
p.components.playercontroller.GetPlatformRelativePosition=function(_,x,z) return 'platform',x-10,z-20 end
local ActualActions=assert(loadfile('scripts/shadowself/control/actions.lua'))()
assert(ActualActions.Deploy(p,boatkit,Vector3(12,0,25)))
assert(sent[1]==12345 and sent[2]==boatkit and sent[3]==2 and sent[4]==5 and sent[6]==true and sent[7]=='platform' and sent[8]==true,'original controller-deploy RPC fields, no false local spawn')
SendRPCToServer=oldSend;RPC.ControllerActionButtonDeploy=oldRPC
-- 岸边4码不能容纳整只船时，仍能配对较深且原版许可的水面点。
p.pos=Vector3(-20,0,-20)
TheWorld.Map.IsOceanAtPoint=function(_,x,y,z) return math.abs(x)<18 and math.abs(z)<18 end
TheWorld.Map.IsPassableAtPoint=function(_,x,y,z) return math.abs(x)>=18 or math.abs(z)>=18 end
boatkit.replica.inventoryitem.CanDeploy=function(_,q) return math.abs(q.x)<12.8 and math.abs(q.z)<12.8 end
local shore,water=require('shadowself/control/arena_boat')(p,boatkit,Vector3(0,0,0))
assert(shore and water and not TheWorld.Map:IsOceanAtPoint(shore.x,0,shore.z) and boatkit.replica.inventoryitem:CanDeploy(water),'land/water pair honors full boat clearance, unlike the four-unit probe')
arena.wave=8;bag={boatkit};s:Reset();s.center=Vector3(0,0,0);lastmove=nil;now=50
assert(s:Crab({})=='hold' and lastmove,'wave8 immediately advances to a valid shore instead of waiting eight seconds for an absent boss')
boatkit.replica.inventoryitem.CanDeploy=function() return false end
assert(not require('shadowself/control/arena_boat')(p,boatkit,Vector3(0,0,0)),'never bypass rejected deployment or fabricate a boat')
-- 中心坐标未同步不妨碍合法放船；确认的船实体也应立即上船。
local savedCenter=s.FindCenter;s:Reset();s.FindCenter=function() return nil end
bag={boatkit};p.platform=nil;now=60
TheWorld.Map.IsOceanAtPoint=function() return true end
boatkit.replica.inventoryitem.CanDeploy=function() return true end
local beforeDeploy=deploys
assert(s:Crab({})=='hold' and deploys==beforeDeploy+1 and s.deploy,'first tick deploys at a valid local water point without waiting for center or boss')
lastmove=nil;assert(s:Crab({boat})=='hold' and lastmove==boat.pos and not s.deploy,'replicated boat boards even while rowing center is still unresolved')
s.FindCenter=savedCenter
-- Real corner opening: move one tile along an edge before any deployment request.
s:Reset();s.FindCenter=function() return Vector3(0,0,0) end
p.pos=Vector3(-18,0,-18);p.platform=nil;bag={boatkit};now=80
TheWorld.Map.GetTileCenterPoint=function(_,x,_,z) return math.floor(x/4)*4+2,0,math.floor(z/4)*4+2 end
TheWorld.Map.IsOceanAtPoint=function(_,x,_,z) return math.abs(x)<18 and math.abs(z)<18 end
TheWorld.Map.IsPassableAtPoint=function(_,x,_,z) return math.abs(x)>=18 or math.abs(z)>=18 end
boatkit.replica.inventoryitem.CanDeploy=function(_,q) return math.abs(q.x)<14 and math.abs(q.z)<14 end
beforeDeploy=deploys;lastmove=nil
assert(s:Crab({})=='hold' and deploys==beforeDeploy and lastmove and lastmove:DistSq(Vector3(-14,0,-18))<.001,'corner cannot deploy first or walk diagonally into water')
p.pos=lastmove;now=80.3;s:Crab({})
assert(s.corner_done and deploys==beforeDeploy+1,'reaching the adjacent tile center releases actual deployment')
local localWater=s.deploy.point
assert(p.pos:DistSq(localWater)<=require('shadowself/control/arena_boat').Range(boatkit)^2,'deployment point lies within actual controller approach range')
s:Reset();p.pos=Vector3(-18,0,-18);lastmove=nil;now=81
local land=TheWorld.Map.IsPassableAtPoint
TheWorld.Map.IsPassableAtPoint=function(map,x,y,z) return not (x>-18 and z<=-18) and land(map,x,y,z) end
s:Crab({});assert(lastmove and lastmove:DistSq(Vector3(-18,0,-14))<.001,'blocked first edge selects the other adjacent tile instead')
-- A geometrically legal point at eight or nine units must not become an immediate deploy request.
s:Reset();p.pos=Vector3(0,0,0)
TheWorld.Map.IsOceanAtPoint=function() return true end
boatkit.replica.inventoryitem.CanDeploy=function(_,q) return q:DistSq(p.pos)>=8^2 end
assert(not s:BoatPoint(boatkit,Vector3(10,0,0)),'CanDeploy alone cannot authorize far deployment from current shore')
s.FindCenter=savedCenter
package.loaded['shadowself/control/actions']=savedA;package.loaded['shadowself/control/arena_encounters']=savedS
GetTime=oldTime;TheWorld=oldWorld;WORLD_TILES=oldTiles
print('PASS: actual inventory dominance, morningstar/tool reserves, durability replacement, bounded full-bag swaps; acknowledged boat/oar/ROW/ice/shore lifecycle; worm armor rescue, chew-only punish and safe bait lure')
