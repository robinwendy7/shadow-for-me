local savedA=package.loaded["shadowself/control/actions"]
local savedN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"};ACTIONS={ATTACK={},EQUIP={},PICKUP={},CHOP={},PLAY={}}
TUNING={TOADSTOOL_SPOREBOMB_TIMER=3.5,TOADSTOOL_SPORECLOUD_RADIUS=3.5,TENTACLE_STOPATTACK_DIST=4}
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=0
local function entity(name,x,z)
 guid=guid+1;local e={prefab=name,GUID=guid,pos=Vector3(x or 0,0,z or 0),frame=0,tags={},replica={},components={},entity={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};e.entity.GetParent=function() return e.parent end;return e
end
local p=entity("wilson",2,0);local held={};local items={};local commands={};local entities={}
p.replica.inventory={GetEquippedItem=function(_,slot) return held[slot] end,DropItemFromInvTile=function(_,item) commands[#commands+1]={drop=item} end}
p.replica.combat={};p.components.playercontroller={IsBusy=function() return false end}
ThePlayer=p;TheWorld={state={}};TheSim={FindEntities=function() return entities end}
local A={Items=function() return items end,Self=function(_,item,action) held.hands=item;commands[#commands+1]={item=item,action=action};return true end,
 Attack=function(_,target) commands[#commands+1]={target=target,action=ACTIONS.ATTACK};return true end,
 Scene=function(_,target,action) commands[#commands+1]={target=target,action=action};return true end}
package.loaded["shadowself/control/actions"]=A
require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local pauses=0;local stop=0
local c={player=p,enemies={},observed={},hazards={},snapshot={},gear={},h={IsHitingFrame=function() return p.frame>=8 end},
 bridge={PauseAttack=function() pauses=pauses+1 end,allowed=function() return true end},
 actions={SafePoint=function() return true end,Stop=function() stop=stop+1 end},
 travel={BeginDodge=function() end,EndDodge=function() end},Move=function(self,q,label) self.moved=q;self.status=label end}
c.mechanisms={Equip=function(_,item) held.hands=item;return true end}
package.loaded["shadowself/control/bosses"]=nil
local Boss=require("shadowself/control/bosses");local b=Boss(c);c.bosses=b
-- Completed swings count, not issued attack requests. Exactly two then retreat.
local rook=entity("rook");c.h.ent=rook;c.enemies={rook};rook.anim="atk";b:Tick(rook)
p.pos=Vector3(1,0,3);assert(b:Tick(rook)=="move" and c.moved.x<rook.pos.x and c.bridge.chasing,"clear lane immediately follows the rear using the move owner")
p.pos=Vector3(2,0,0);rook.anim="atk_skid";b:Tick(rook)
for i=1,2 do
 p.tags.attack=true;p.anim="atk";p.frame=1;b:Tick(rook);p.frame=8
 local mode=b:Tick(rook)
 if i<2 then assert(mode=="attack" and stop==0) else assert(mode=="move" and stop==1) end
 p.tags.attack=nil;b:Tick(rook)
end
-- Same-rank insulated headgear keeps current equipment despite inventory order.
package.loaded["shadowself/control/encounters"]=nil
local Enc=require("shadowself/control/encounters");local enc=Enc(c)
local rain,eye=entity("rainhat"),entity("eyebrellahat")
for _,hat in ipairs({rain,eye}) do hat.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HEAD end} end
held.head=rain;items={eye,rain};enc:Insulate({});assert(held.head==rain)
items={rain,eye};enc:Insulate({});assert(held.head==rain)
held.head=eye;items={rain,eye};enc:Insulate({});assert(held.head==eye)
-- Invoke the queen callback with native COLON calling convention (the old radius-zero bug).
local queen=entity("beequeen");queen.anim="atk";c.beequeen={queen=queen};c.enemies={queen};p.pos=Vector3(2,0,0)
local data=require("shadowself/control/queenattack")(c,queen,false)
local q=data:fn(queen.pos,p.pos,0,data.dist)
assert(math.sqrt(q:DistSq(queen.pos))>=6.75 and q.x>0,"queen callback uses actual retreat radius")
-- All source combat families: swipe combo, ice summon, jump dive and torpedo.
local shark=entity("sharkboi");c.enemies={shark};c.beequeen=nil
for _,name in ipairs({"atk1","atk2","atk2_delay","atk3","ice_summon","torpedo_pre","torpedo_jump","torpedo_loop","icedive_standing_jump_pre","icedive_jump_pre","icedive_jump","icedive_dig_pre"}) do
 shark.anim=name;shark.frame=0;assert(b:Dodge(shark,false),name)
end
shark.anim="icedive_dig_loop";assert(not b:Dodge(shark,false),"exposed tail is a three-hit stagger opportunity")
local tower=entity("vault_pillar_guard")
for _,name in ipairs({"atk_1","atk_2","atk_3_pre_a","atk_3_pre_b","atk_3","spin_pre","spin_loop"}) do tower.anim=name;tower.frame=0;assert(b:Dodge(tower,false),name) end
tower.anim="stunned_loop";assert(not b:Dodge(tower,false),"stagger is a punish window")
local mate=entity("prime_mate");mate.anim="atk_weapon";mate.frame=8;assert(b:Dodge(mate,false));mate.frame=9;assert(not b:Dodge(mate,false))
-- Crystal second throw is identified by source animation, not guessed elapsed battle time.
local deer=entity("mutateddeerclops");c.enemies={deer};p.pos=Vector3(8,0,0);deer.anim="idle_loop";assert(b:Tick(deer)=="move" and c.moved.x>=8,"bait lances before attacking the armoured body")
deer.anim="throw";deer.frame=30
b:Tick(deer);assert(math.abs(c.moved.z)>2,"first throw moves laterally after target locks")
deer.anim="throw_2";deer.frame=30;b:Tick(deer);assert(c.moved.x<8,"second lock closes distance while escaping the old impact point")
local fire=entity("firestaff");items={fire};p.pos=c.moved;deer.frame=34;now=1;b:Tick(deer)
assert(commands[#commands].action==ACTIONS.ATTACK and commands[#commands].target==deer)
deer.anim="stagger";assert(b:Tick(deer)=="attack" and not c.gear.forced_weapon)
-- Invulnerable plant body yields to vines; weak body becomes preferred target.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.tags.retaliates=true
local vine=entity("lunarthrall_plant_vine_end",6,0);vine.tags.lunarthrall_plant_end=true;c.enemies={head,vine}
local mode,picked=b:Tick(head);assert(mode=="attack" and picked==vine)
head.tags.retaliates=nil;head.anim="tired_loop_large";mode,picked=b:Tick(vine);assert(picked==head)
-- Bomb starts earlier, with time to clear the cloud; actual cloud remains a path obstacle.
local bomb=entity("sporebomb");bomb.components.timer={GetTimeLeft=function() return 1.6 end}
assert(#b:Zones({bomb})==0);bomb.components.timer.GetTimeLeft=function() return .4 end
assert(#b:Zones({bomb})==1)
local cloud=entity("sporecloud");cloud.tags.sporecloud=true
assert(b:Zones({cloud})[1].radius>=4)
local tent=entity("bigshadowtentacle");tent.anim="breach_loop";b.entities={tent};c.enemies={entity("minotaur",6,0)}
assert(b:Tick(c.enemies[1])=="move","untriggered tentacle is baited first")
tent.anim="atk_pre";assert(#b:Zones({tent})==1 and b.seen[tent],"emerged tentacle becomes an avoid zone")
tent.anim="atk_pst";assert(#b:Zones({tent})==0,"disappearing tentacle no longer blocks approach")
-- Actual missing-controller condition from the Wonkey log.
local Bridge=require("shadowself/control/combat");local bridge=Bridge(p);bridge.native={};assert(bridge:PlayerReady())
p.components.playercontroller=nil;assert(not bridge:PlayerReady() and bridge:ManualAction())
p.components.playercontroller={};ThePlayer=entity("wonkey");assert(not bridge:PlayerReady())
-- Coastal candidate room improves toward land, and boats bypass land margin.
local Nav=require("shadowself/control/navigation")
TheWorld.Map={IsPassableAtPoint=function(_,x) return x>=0 end,IsOceanAtPoint=function(_,x) return x<0 end}
p.pos=Vector3(.2,0,0);assert(Nav.Clearance(c,Vector3(4,0,0))>Nav.Clearance(c,p.pos))
p.GetCurrentPlatform=function() return {} end;assert(Nav.Clearance(c,p.pos)==8)
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: 0.11.3 boss phase scenarios, queen colon callback, stable insulation, early bomb, vines, tentacle bait, Wonkey ownership and coast room; not live gameplay")
