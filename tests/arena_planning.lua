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
local spike=item('tentaclespike',EQUIPSLOTS.HANDS);spike.tags.weapon=true
local sword=item('nightsword',EQUIPSLOTS.HANDS);sword.tags.weapon=true
local fresh=item('nightsword',EQUIPSLOTS.HANDS,100);fresh.tags.weapon=true
local old=item('nightsword',EQUIPSLOTS.HANDS,10);old.tags.weapon=true
local star=item('nightstick',EQUIPSLOTS.HANDS);star.tags.weapon=true
local cane=item('cane',EQUIPSLOTS.HANDS);cane.tags.weapon=true
assert(Inventory.Obsolete(spear,{spear,spike},p,3))
assert(Inventory.Obsolete(spike,{spike,sword},p,4))
local hambat=item('hambat',EQUIPSLOTS.HANDS);hambat.tags.weapon=true
hambat.replica.inventoryitem.classified.perish={value=function() return 10 end}
assert(Inventory.Physical(hambat)<51 and Inventory.Obsolete(hambat,{hambat,spike},p,6),'actual client perish values, not full-strength stale ham bat')
assert(not Inventory.Obsolete(star,{star,sword},p,10),'morningstar reserved independent of stronger main weapon')
assert(not Inventory.Obsolete(cane,{cane,sword},p,10),'cane not ranked as disposable weapon')
assert(not Inventory.Want(spear,{sword},p,7),'do not re-pick inferior discarded weapons')
assert(Inventory.Want(fresh,{old},p,10) and Inventory.Obsolete(old,{old,fresh},p,10),'real classified durability drives replacement')
assert(Inventory.Discard({spear},p,3,sword)==spear,'full bag can exchange low damage for an actual ground upgrade')
assert(not Inventory.Discard({sword},p,3,spear),'never discard strong weapon for weaker floor drop')
local armor=item('armorruins',EQUIPSLOTS.BODY);local grass=item('armorgrass',EQUIPSLOTS.BODY)
assert(Inventory.Want(armor,{grass},p,10) and Inventory.Obsolete(grass,{grass,armor},p,10))
local marble=item('armormarble',EQUIPSLOTS.BODY);local wood=item('armorwood',EQUIPSLOTS.BODY)
assert(Inventory.Want(marble,{wood},p,4),'high absorption armor is not discarded merely because mobile armor has higher equip score')
local planar=item('armor_lunarplant',EQUIPSLOTS.BODY)
assert(not Inventory.Obsolete(planar,{planar,armor},p,13),'ordinary armor cannot replace planar defense reserve')
assert(Inventory.Special('icestaff2',12) and Inventory.Special('nightstick',15))
local boatkit=item('boat_item');assert(Inventory.Obsolete(boatkit,{},p,9),'used ocean equipment expires after wave8')
local food=item('meatballs');local flute=item('panflute')
assert(not Inventory.Discard({food},p,5,flute),'keep last known healing/food supply')
local unknown=item('player_keepsake');assert(not Inventory.Obsolete(unknown,{sword},p,15))
local Guard=require('shadowself/control/guardcontrol')
assert(Guard.Ice({plan={arena=true}},item('icestaff2')) and not Guard.Ice({plan={}},item('icestaff2')),'custom ice wand only enabled in arena plan')

local savedA=package.loaded['shadowself/control/actions'];local savedS=package.loaded['shadowself/control/arena_encounters']
local moves,deploys,rows,equips,loots,stops=0,0,0,0,0,0;local lastmove
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Move=function(_,q) moves=moves+1;lastmove=q end,Deploy=function() deploys=deploys+1;return true end,
 Ground=function(_,q,act) rows=rows+1;assert(act==ACTIONS.ROW);return true end,
 Self=function() equips=equips+1;return true end}
package.loaded['shadowself/control/arena_encounters']=nil
local E=require('shadowself/control/arena_encounters')
local arena={player=p,wave=8,items={},bridge={},Inventory=function() return {},bag end,
 StopCombat=function() stops=stops+1 end,Say=function() end,Loot=function() loots=loots+1;return false end}
TheWorld={Map={IsOceanAtPoint=function() return true end,IsPassableAtPoint=function() return true end,GetTileAtPoint=function() return 9 end,GetPlatformAtPoint=function() return nil end}}
local s=E(arena);s.center=Vector3(0,0,0);bag={boatkit};assert(s:Crab({})=='hold' and deploys==1)
now=1;s:Crab({});assert(deploys==1,'do not resend unacknowledged deploy every tick')
now=7;assert(s:Crab({})=='failed','unacknowledged deployment must stop instead of walking into sea')
local boat=item('boat');boat.pos=Vector3(15,0,0)
assert(s:Crab({boat})=='hold' and lastmove==boat.pos and s.deploy==nil,'board only server-replicated boat')
local oar=item('oar_driftwood',EQUIPSLOTS.HANDS);oar.tags.oar=true
bag={oar};p.platform=boat;hand=nil;p.pos=Vector3(11.6,0,0)
s:Crab({boat});assert(equips==1 and rows==0,'wait for authoritative oar hand-slot confirmation')
hand=oar;now=8;s:Crab({boat});assert(rows==1,'confirmed oar submits ROW rather than WALKTO through water')
boat.pos=Vector3(5,0,0);p.pos=Vector3(4,0,0)
assert(s:Crab({boat})=='hold','arrive center and wait for boss rather than attack nonexistent target')
local king=item('crabking');king.pos=Vector3(0,0,0)
assert(s:Crab({boat,king})=='fight')
king.tags.icewall=true
assert(s:Crab({boat,king})=='hold' and lastmove:DistSq(king.pos)>=6^2,'board ice at a clear ring point, not boss feet')
TheWorld.Map.IsOceanAtPoint=function() return false end;TheWorld.Map.GetTileAtPoint=function() return 10 end
p.platform=nil;p.pos=Vector3(0,0,0);king.tags.dead=true
assert(s:Crab({king})=='hold' and lastmove:DistSq(king.pos)>=19^2,'boss death exits collapsing center toward permanent outer shore')
p.pos=lastmove;now=9;assert(s:Crab({king})=='hold','wait at shore for authoritative next wave')
king.tags.dead=nil;king.tags.icewall=true;p.pos=Vector3(0,0,0);s:Reset();s.center=king.pos
local wall=item('crabking_icewall');now=20;s:Crab({king,wall});now=21;s:Crab({king})
now=37;assert(s:Crab({king})=='hold' and s.retreat and lastmove:DistSq(king.pos)>=19^2,'leave before server first-wall-break ice timer expires, allowing travel reserve')
p.pos=lastmove;now=38;assert(s:Crab({king})=='hold' and s.retreat,'never reenter ice while waiting for this melt cycle')

arena.wave=11;s:Reset();p.pos=Vector3(8,0,0);bag={grass}
local head=item('worm_boss_head');head.pos=Vector3(0,0,0)
local anim='chew_big';head.AnimState={IsCurrentAnimation=function(_,name) return name==anim end}
local dirt=item('worm_boss_dirt');dirt.replica.inventoryitem=nil;dirt.replica.combat={};dirt.pos=Vector3(0,0,0)
local watched={};arena.Loot=function(_,items) watched=items;return true end
armor.pos=Vector3(7,0,0)
assert(s:Worm({head,dirt,armor})=='hold' and watched[1]==armor,'rescue superior dropped armor before worm can eat it')
arena.Loot=function() return false end
assert(s:Worm({head,dirt})=='fight' and s.worm_target==dirt and s:Allowed(dirt),'chewing attacks real redirect-damage dirt, not noncombat head')
anim='emerge_eat';p.pos=Vector3(1,0,0);now=10
assert(s:Worm({head,dirt})=='hold' and not s.worm_target and lastmove:DistSq(head.pos)>=4^2,'stop punish and move out before emergence swallow')
anim='head_idle_loop';p.pos=Vector3(8,0,0);food.pos=Vector3(6,0,0);now=11
assert(s:Worm({head,dirt,food})=='hold' and lastmove:DistSq(food.pos)>1.5^2,'ground food remains bait; lure stands outside creature-swallow radius')
local fixed=s.lure.goal;p.pos=Vector3(9,0,0);now=11.5;s:Worm({head,dirt,food});assert(s.lure.goal==fixed,'lure point stays fixed while player moves')
local crack=item('worm_boss_dirt_ground_fx');crack.pos=p.pos;crack.replica.inventoryitem=nil;now=12
assert(s:Tick({crack,armor})=='hold' and lastmove:DistSq(crack.pos)>=4^2,'pre-emergence crack interrupts armor rescue before swallow, not after damage')
local mite=item('cave_vent_mite');mite.replica.inventoryitem=nil;mite.replica.combat={};mite.pos=Vector3(9,0,0)
assert(s:Worm({head,dirt,mite})=='fight' and s.add_target==mite,'nearby stage companions are fought during bait wait')
head.tags.dead=true;dirt.tags.dead=true
assert(not s:Tick({head,dirt,mite}),'dead worm visuals cannot block cleaning remaining stage enemies')
local oldSend,oldRPC=SendRPCToServer,RPC.ControllerActionButtonDeploy
local sent;RPC.ControllerActionButtonDeploy=12345;SendRPCToServer=function(...) sent={...} end
p.components.playercontroller.ismastersim=false
p.components.playercontroller.GetPlatformRelativePosition=function(_,x,z) return 'platform',x-10,z-20 end
local ActualActions=assert(loadfile('scripts/shadowself/control/actions.lua'))()
assert(ActualActions.Deploy(p,boatkit,Vector3(12,0,25)))
assert(sent[1]==12345 and sent[2]==boatkit and sent[3]==2 and sent[4]==5 and sent[6]==true and sent[7]=='platform' and sent[8]==true,'original controller-deploy RPC fields, no false local spawn')
SendRPCToServer=oldSend;RPC.ControllerActionButtonDeploy=oldRPC
package.loaded['shadowself/control/actions']=savedA;package.loaded['shadowself/control/arena_encounters']=savedS
GetTime=oldTime;TheWorld=oldWorld;WORLD_TILES=oldTiles
print('PASS: actual inventory dominance, morningstar/tool reserves, durability replacement, bounded full-bag swaps; acknowledged boat/oar/ROW/ice/shore lifecycle; worm armor rescue, chew-only punish and safe bait lure')
