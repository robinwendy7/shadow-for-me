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


-- Idle queen range is explicitly allowed; freezing uses ATTACK and a single staff owner.
c.gear.Swap=function(self)
 local item=self.support_hand and self.support_hand.item or self.forced_weapon
 if item and held.hands~=item then A.Self(p,item,ACTIONS.EQUIP) end
 return not item or held.hands==item
end
c.gear.Mobile=function(self) return self.forced_weapon end
package.loaded["shadowself/control/beequeen"]=nil
local queen=entity("beequeen",0,0);local bee=entity("beeguard",6,0);local ice=entity("icestaff")
c.enemies={queen,bee};c.bridge.wrappers={PreTheLoop={old=function() end}};items={ice};held.hands=ice
p.replica.combat.GetAttackRangeWithWeapon=function() return 8 end
p.pos=Vector3(4,0,2);now=30
local Q=require("shadowself/control/beequeen")(c);c.beequeen=Q
Q:Tick();assert(commands[#commands].target==bee and commands[#commands].action==ACTIONS.ATTACK,"freeze inside idle queen hit radius, not endless retreat")
assert(c.gear.forced_weapon==ice and not c.bridge.chasing and not c.travel.chasing)
-- A queen between player and guard requires a bee-centered lateral shooting angle.
p.pos=Vector3(-4,0,0);bee.pos=Vector3(4,0,0);now=31;c.moved=nil
local before=#commands;Q:Tick()
assert(c.moved and math.abs(c.moved.z)>.1 and #commands==before,"orbit the bee instead of shooting through queen or retreating along the same line")
assert(c.moved:DistSq(bee.pos)<=8.35^2 and c.moved:DistSq(queen.pos)<6.8^2,"idle queen proximity must not veto the orbit")
-- Active pre-impact is still respected, without switching back to cane.
p.pos=Vector3(4,0,2);bee.pos=Vector3(6,0,0);queen.anim="atk";queen.frame=6;now=32;c.moved=nil
before=#commands;Q:Tick();assert(c.moved and c.moved:DistSq(queen.pos)>p.pos:DistSq(queen.pos) and #commands==before)
assert(held.hands==ice and c.gear.forced_weapon==ice,"defensive reposition preserves wand ownership")
queen.anim="idle";bee.anim="frozen_loop_pst";Q:Tick()
assert(c.target==queen and not c.blocked and not c.gear.forced_weapon,"confirmed freeze immediately returns to queen")
-- Short open sidesteps remain short; a U-shaped neck must be exited backwards.
local ant=entity("antlion",-10,0);c.enemies={ant};c.hazards={};c.beequeen=nil;p.pos=Vector3(0,0,0)
local savedWorld=TheWorld
TheWorld={Map={IsPassableAtPoint=function(_,x,y,z) return x<.6 and (x< -2.5 or math.abs(z)<.72) end,IsOceanAtPoint=function() return false end}}
local plan=require("shadowself/control/antnavigation")
local point,goal=plan.Route(c,ant)
assert(point and point.x< -1 and goal.x< -2.5,"connected exit leads back through neck into open ground")
assert(plan.Corridor(c,p.pos,point,ant),"first exit waypoint has a clear corridor")
local route=require("shadowself/control/routes")({c=c})
point=route:AntPoint(ant);assert(point and not route.ant_exit and not route.ant_clearing,"normal local dodge does not launch the removed escape state")
p.pos=Vector3(-2.8,0,0);now=now+1;point=route:AntPoint(ant)
assert(point and plan.Corridor(c,p.pos,point,ant),"committed exit is revalidated from current position")
-- Future room checks start at the candidate, not at the player's old point.
p.pos=Vector3(0,0,0)
assert(not plan.Corridor(c,Vector3(-3,0,0),Vector3(-1,0,2),ant),"a future segment crossing the neck wall is rejected")
TheWorld={state={}};ant.pos=Vector3(0,0,0);p.pos=Vector3(4,0,0)
route=require("shadowself/control/routes")({c=c});point=route:AntPoint(ant)
assert(point and p.pos:DistSq(point)<4^2 and not route.ant_exit,"open arena remains a single short sidestep")
TheWorld=savedWorld
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: antlion connected neck exit/future segment/short sidestep; idle-queen-range freeze, bee-centered orbit, attack-windup defence and immediate frozen handoff")
