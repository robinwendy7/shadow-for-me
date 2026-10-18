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



c.Move=function(self,point,label) self.moved=point;self.status=label;self.blocked=true end
c.gear.Swap=function(self)
 local item=self.support_hand and self.support_hand.item or self.forced_weapon
 if item and held.hands~=item then A.Self(p,item,ACTIONS.EQUIP) end
 return not item or held.hands==item
end
c.gear.Mobile=function(self) return self.forced_weapon end
package.loaded["shadowself/control/beequeen"]=nil;package.loaded["shadowself/control/queenflute"]=nil
local Queen=require("shadowself/control/beequeen")
local queen=entity("beequeen");local bee=entity("beeguard",6,0);local ice=entity("icestaff")
items={ice};held.hands=ice;c.enemies={queen,bee};c.bridge.wrappers={PreTheLoop={old=function() end}}
p.replica.combat.GetAttackRangeWithWeapon=function() return 8 end
local busy=false;p.components.playercontroller.IsBusy=function() return busy end
local Q=Queen(c);c.beequeen=Q;p.pos=Vector3(4,0,2);now=1
Q:Tick();local fired=#commands;assert(commands[fired].target==bee)
-- Queen windup interrupts even when busy, attack/equip cooldown and movement throttle would otherwise wait.
queen.anim="atk";queen.frame=1;busy=true;Q.next_support=50;c.next_move=50;now=1.02;c.moved=nil
Q:Tick();assert(c.moved and c.moved:DistSq(queen.pos)>6.75^2 and #commands==fired,"freeze flow immediately leaves queen hit range even while busy/cooling down")
assert(c.next_move==nil and Q.guard_escape,"first urgent movement bypasses old support-move throttle")
-- Last bees may block the outward direction, but cannot turn the escape into a shot-angle compromise.
bee.pos=Vector3(7,0,3.5);queen.frame=7;now=1.22;c.moved=nil;Q:Tick()
assert(c.moved and c.moved:DistSq(queen.pos)>6.75^2 and #commands==fired)
queen.frame=14;now=1.46;c.moved=nil;Q:Tick();assert(c.moved and #commands==fired,"hold escape through impact and replication margin")
queen.anim="idle";busy=false;p.pos=Vector3(8,0,1);bee.pos=Vector3(6,0,1);now=1.7;c.hazards={}
Q:Tick();assert(not Q.guard_escape and #commands==fired+1 and commands[#commands].target==bee,"resume freezing immediately, without stale half-second support cooldown")
-- Stage two restored: full coverage casts immediately; wake starts positioning, not seven-unit waiting.
local flute=entity("panflute");items={flute};queen.anim="idle";queen.replica.health={GetPercent=function() return .65 end}
local bees={};entities={queen};for i=1,10 do bees[i]=entity("beeguard",15,0);entities[#entities+1]=bees[i] end
c.enemies=entities;c.hazards={};p.pos=Vector3(10,0,0);c.gear.AttackRange=function() return 2 end
local plays=0;A.Self=function(_,item,action) if action==ACTIONS.PLAY then plays=plays+1 end;return true end
Q=Queen(c);c.beequeen=Q;now=3;c.moved=nil
Q:Tick();assert(Q.phase==2 and Q.stage=="flute" and c.blocked and plays==1,"safe full coverage casts without waiting for seven-unit guard approach")
queen.anim="sleep_loop";for _,guard in ipairs(bees) do guard.anim="sleep_loop" end
now=4;Q:Tick();assert(Q.stage=="strike" and not c.blocked,"full sleep confirmation still hands back queen solo")
queen.anim="idle";for _,guard in ipairs(bees) do guard.anim="idle" end
bees[10].pos=Vector3(28,0,0);now=4.2;c.moved=nil
Q:Tick();assert(plays==1 and c.blocked and Q.stage=="flute" and c.moved and c.moved.x>p.pos.x,"wake immediately moves toward common coverage instead of waiting for bees to approach")
-- Drive real FocusTarget changes and real command3 release timeline from installed game source.
TUNING.BEEGUARD_SPEED=3;TUNING.BEEGUARD_DASH_SPEED=8
local raw=read_source("prefabs/beeguard.lua");local a=assert(raw:find("local function FocusTarget",1,true));local finish=assert(raw:find("local function BeeSort",a,true))
local env=setmetatable({normalsounds={},poofysounds={},SpawnPrefab=function() return {Transform={SetPosition=function() end}} end},{__index=_G})
local fn=assert(loadstring(raw:sub(a,finish-1).."\nreturn FocusTarget"));setfenv(fn,env);local focus=fn()
for _,guard in ipairs(bees) do
 guard.build="bee_guard_build";guard.AnimState.SetBuild=function(_,build) guard.build=build end;guard.AnimState.GetBuild=function() return guard.build end
 guard.AddTag=function(_,tag) guard.tags[tag]=true end;guard.Transform.GetWorldPosition=function() return guard.pos.x,0,guard.pos.z end
 guard.SoundEmitter={PlayingSound=function() return false end};guard.components.locomotor={walkspeed=3}
 guard.components.combat={SetDefaultDamage=function() end,SetAttackPeriod=function() end,SetTarget=function() end}
 guard.FocusTarget=function(self,target) return focus(self,target) end
 guard:FocusTarget(p);assert(guard.build=="bee_guard_puffy_build" and guard.components.locomotor.walkspeed==8)
end
raw=read_source("stategraphs/SGbeequeen.lua");a=assert(raw:find('name = "focustarget_pst"',1,true));local start=assert(raw:sub(1,a):match(".*()State{"));finish=assert(raw:find("\n    },",a,true))
env=setmetatable({State=function(v) return v end,TimeEvent=function(t,callback) return {time=t,fn=callback} end,EventHandler=function() return {} end,
 CommonHandlers=setmetatable({},{__index=function() return function() return {} end end})},{__index=_G})
fn=assert(loadstring("return "..raw:sub(start,finish+5)));setfenv(fn,env);local state=fn();local release
for _,event in ipairs(state.timeline) do if event.time==23*FRAMES then release=event.fn end end
assert(release,"real game ends dash at frame23; frame19 is only sound")
queen.components.commander={GetAllSoldiers=function() return bees end};queen.components.sanityaura={};queen.sg={statemem={}};queen.SoundEmitter={PlaySound=function() end};queen.BoostCommanderRange=function() end
-- Phase three overrides flute even with flute carried.
queen.replica.health.GetPercent=function() return .45 end;queen.anim="command2";queen.frame=18
for _,guard in ipairs(bees) do guard.pos=Vector3(6,0,0) end
p.pos=Vector3(8,0,0);Q=Queen(c);c.beequeen=Q;c.hazards={};now=5;c.moved=nil
local before=plays;Q:Tick();assert(Q.phase==3 and Q.stage=="dash_pull" and c.blocked and c.moved.x>8 and plays==before,"roar carries boosted guards away, rather than using flute: "..tostring(Q.phase).."/"..tostring(Q.stage).."/"..tostring(c.moved and c.moved.x).."/"..tostring(c.blocked).."/"..tostring(plays).."/"..tostring(before))
-- Beyond old 16.5/18/36-unit cutoffs the direction must remain straight away from queen.
local locked=Q.dash_cycle.dir
for i,x in ipairs({12,20,32,40}) do
 p.pos=Vector3(x,0,0);for _,guard in ipairs(bees) do guard.pos=Vector3(x-2,0,0) end
 now=5+i*.02;c.moved=nil;Q:Tick()
 assert(Q.stage=="dash_pull" and math.abs(c.moved.x-(x+4))<.001 and math.abs(c.moved.z)<.001,"no tangent/orbit at old distance cutoff "..x)
 assert(Q.dash_cycle.dir==locked,"one roar keeps one fixed outward direction")
end
-- Blocking the forward route only allows an outward detour, never a circle around queen.
p.pos=Vector3(20,0,0);for _,guard in ipairs(bees) do guard.pos=Vector3(18,0,0) end
local safe=c.actions.SafePoint;c.actions.SafePoint=function(_,point) return point.x<=20.01 or math.abs(point.z)>.3 end
now=5.2;Q:Tick();assert(c.moved.x>22 and math.abs(c.moved.z)>0,"obstacle detour continues outward")
c.actions.SafePoint=function() return false end;now=5.3;Q.dash_cycle.route=nil;Q:Tick();assert(c.blocked and not Q.dash_cycle.route.point,"no outward route holds without repeatedly sending a zero-distance move")
c.actions.SafePoint=safe
p.pos=Vector3(12,0,0);for _,guard in ipairs(bees) do guard.pos=Vector3(14,0,0) end
queen.anim="command3";queen.frame=0;now=5.5;c.next_move=99;Q:Tick();assert(Q.stage=="dash_return" and c.moved.x<12 and c.next_move==nil,"command3 starts inside the restored one-second return window, before actual boost release")
release(queen);for _,guard in ipairs(bees) do assert(guard.build=="bee_guard_build") end
queen.frame=23;now=5.53;c.moved=nil;Q:Tick()
assert(Q.stage=="dash_return" and c.moved.x<12 and math.abs(c.moved.z)<.001 and c.next_move==nil,"actual dash-end event returns straight to queen in the same tick, ignoring stale move throttle")
-- Return does not wait for an artificial player/queen/guard ordering.
p.pos=Vector3(2,0,0);queen.anim="idle";now=5.8;Q:Tick();assert(Q.stage=="strike" and not c.blocked and c.target==queen,"return reaches melee and immediately resumes solo")
for _,guard in ipairs(bees) do guard.pos=Vector3(5,0,0) end
now=6;Q:Tick();assert(Q.stage=="dash_wait" and c.blocked and c.target==queen,"normal guards catching up enter spacing wait, never restart the old pull or become targets")
-- Build transition alone is enough, no fixed timer or command3 animation is required.
queen.anim="command1";for _,guard in ipairs(bees) do guard:FocusTarget(p);guard.pos=Vector3(14,0,0) end
p.pos=Vector3(12,0,0);now=7;Q:Tick();assert(Q.dash_cycle.seen_dash)
for _,guard in ipairs(bees) do guard:FocusTarget(nil) end
now=7.01;c.moved=nil;Q:Tick();assert(Q.stage=="dash_return" and c.moved.x<12,"observed puffy-to-normal falling edge triggers immediate return without a timeout")
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/beequeen"]=nil;package.loaded["shadowself/control/queenflute"]=nil
print("PASS: freeze threat interrupts busy/cooldown and holds through impact; stage2 restored full-coverage midpoint and immediate wake repositioning; real FocusTarget/build/speed and frame23 release drive fixed straight phase3 pull past old leash, outward-only obstacle detour and immediate return/solo/rejoin cycle")
