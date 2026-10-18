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
c.Latency=function() return .1 end;c.Speed=function() return 6 end



-- Client freeze animation, not a nonexistent entity tag, ends the control action.
c.gear.Swap=function(self)
 local item=self.support_hand and self.support_hand.item or self.forced_weapon
 if item and held.hands~=item then A.Self(p,item,ACTIONS.EQUIP) end
 return not item or held.hands==item
end
c.gear.Mobile=function(self) return self.forced_weapon end
package.loaded["shadowself/control/beequeen"]=nil
local queen=entity("beequeen")
local guard=entity("beeguard",4,0);local staff=entity("icestaff")
c.enemies={queen,guard};c.bridge.wrappers={PreTheLoop={old=function() end}};c.h.ent=guard
c.gear.AttackRange=function() return 2 end
p.replica.combat.GetAttackRangeWithWeapon=function() return held.hands==staff and 8 or 2 end
p.pos=Vector3(7.6,0,0);items={staff};now=10;c.moved=nil
local Q=require("shadowself/control/beequeen")(c);Q:Tick();assert(not c.moved and held.hands==staff,"safe queen distance + staff range does not force running to 11.5")
now=10.3;Q:Tick();assert(commands[#commands].action==ACTIONS.ATTACK and commands[#commands].target==guard)
guard.anim="frozen";local count=#commands
now=11;Q:Tick();assert(c.h.ent==queen and #commands==count and not c.gear.forced_weapon,"visible frozen animation immediately ends staff fire")
assert(require("shadowself/control/status").Frozen(guard) and not guard:HasTag("frozen"))
guard.anim="frozen_loop_pst";Q:Tick();assert(#commands==count,"still-frozen thaw animation cannot be hit repeatedly either")
assert(require("shadowself/control/navigation").Risk(c,guard.pos,queen)==0,"frozen animation also stops path threat")
-- Closest pair remains locked even when a later row becomes closer.
local guardian=entity("alterguardian_phase2");c.enemies={guardian};c.h.ent=guardian;p.pos=Vector3(8,0,0);c.hazards={}
local a,bg=entity("smallguard_alterguardian_projectile",4,-1.8),entity("smallguard_alterguardian_projectile",4,1.8)
a.anim="attack";bg.anim="attack";a.frame=16;bg.frame=16;a.spawntime=1;bg.spawntime=1
b.ghosts={a,bg};b.moon_hold=true;assert(b:MoonPair(guardian));local locked=b.moon_pair
local a2,b2=entity("smallguard_alterguardian_projectile",7,-1.8),entity("smallguard_alterguardian_projectile",7,1.8)
a2.anim="emerge";b2.anim="emerge";a2.spawntime=2;b2.spawntime=2
b.ghosts={a,bg,a2,b2};b:MoonPair(guardian);assert(b.moon_pair==locked,"later closer pair cannot replace in-flight pair")
a.anim="mutate";b:MoonPair(guardian);assert(b.moon_pair==locked,"one finished member does not release pair")
bg.frame=26;b:MoonPair(guardian);assert(b.moon_pair~=locked and b.moon_pair.a==a2 and b.moon_pair.b==b2)
a2.anim="mutate";b2.anim="mutate";b:MoonPair(guardian);b.moon_hold=nil
-- Bomb remains overhead until the timed release window; then move through landing.
local bomb=entity("sporebomb");bomb.parent=p;bomb._shadowself_born=100
local registry=require("shadowself/bombs");registry.Track(bomb,p)
c.enemies={};c.h.ent=nil;p.pos=Vector3(8,0,0);now=101;assert(#b:Zones({})==0 and not b:BombPoint())
now=102.9;c.hazards=b:Zones({});assert(b.bomb_imminent==bomb and b:BombPoint():DistSq(p.pos)>1)
registry.tracked[bomb]=nil;c.hazards={};b:Zones({});now=103.2;assert(b:BombPoint(),"continue moving after drop, not just before it")
now=104;assert(not b:BombPoint());c.hazards={}
-- Weak body wins over cuttable segments and stale vine follow-up.
local head=entity("lunarthrall_plant");head.tags.lunarthrall_plant=true;head.anim="tired_loop_large"
local middle=entity("lunarthrall_plant_vine",1,0);middle.tags.weakvine=true;middle.tags.lunarthrall_plant_segment=true
c.enemies={middle,head};c.h.ent=middle;p.pos=Vector3(2,0,0)
local mode,picked=b:Tick(middle);assert(mode=="attack" and picked==head and c.brightshade_target==head)
assert(b:AttackBlocked(middle) and not b:AttackBlocked(head),"old segment target cannot receive a follow-up hit")
local Secondary=require("shadowself/control/secondary");local sec=Secondary(c)
assert(not sec:BeforeAttack() and c.h.ent==head,"dodge completion explicitly hands back weak head")
head.tags.retaliates=true;head.anim="idle_large";b:Brightshade(head);assert(not c.brightshade_target)
-- Bare-eye attack follows a close arc and stops once outside the swipe facing.
local deer=entity("mutateddeerclops");c.enemies={deer};c.h.ent=deer;b.crystal={target=deer,eye_bare=true,bare=true}
deer.anim="atk";deer.frame=16;p.pos=Vector3(3,0,0)
local normal={atkanim="atk",atk_start_frame=14,atk_stop_frame=35,point="player",update=false,angle=-80*math.pi/180,dist=6}
require("shadowself/native").context.HitAndRun={targetanimtable={deerclops={normal}}}
assert(b:Dodge(deer,false)==normal)
deer.frame=36;assert(not b:Dodge(deer,false),"same end frame as normal deer")
-- Rabbit king: fixed charge line, tenth-frame launch, stuck punish and burrow wait.
local king=entity("rabbitking_aggressive");c.enemies={king};c.h.ent=king;p.pos=Vector3(5,0,0)
king.anim="dropkick_pre";king.frame=2;local data=b:Dodge(king,false)
local exit=data:fn();assert(data.noattack and math.abs(exit.x-5)<.01 and math.abs(exit.z)>=2.5)
king.anim="dropkick_loop";king.pos=Vector3(3,0,0);assert(b:Dodge(king,false):fn()==exit,"charge sidestep does not drift with the charging boss")
king.anim="stuck_loop";mode,picked=b:Rabbit(king);assert(mode=="attack" and picked==king and not b:AttackBlocked(king))
king.anim="despawn";king.frame=48;assert(b:Rabbit(king)=="support" and b:AttackBlocked(king))
king.anim="thump";assert(not b:Dodge(king,false),"summon animation is an output opportunity, not an invented stomp AoE")
local minion=entity("rabbitkingminion_bunnyman");minion.anim="atk";minion.frame=12;assert(b:Dodge(minion,false))
minion.frame=13;assert(not b:Dodge(minion,false))
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: real freeze animation/safe staff range, serial same-wave ghost pairs, late bomb/landing movement, weak-head follow-up ownership, close crystal flank and source-timed rabbit king charge/stuck/burrow/minions")
