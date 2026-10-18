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



-- Actual installed instrument + HearPanFlute + player frame-30 event drive this offline scenario.
local Status=require("shadowself/control/status")
local queen=entity("beequeen");queen.tags.sleeper=true
local bees={};for i=1,10 do local bee=entity("beeguard",2+math.cos(i)*2,math.sin(i)*2);bee.tags.sleeper=true;bees[i]=bee end
entities={queen};for _,bee in ipairs(bees) do entities[#entities+1]=bee end
TheNet={GetPing=function() return 0 end,GetPVPEnabled=function() return false end}
TheSim.FindEntities=function(_,x,y,z,radius)
 local out={};for _,e in ipairs(entities) do if e:IsValid() and not e:HasTag("dead") and e.pos:DistSq(Vector3(x,0,z))<=radius^2 then out[#out+1]=e end end;return out
end
p.Transform.GetWorldPosition=function() return p.pos.x,0,p.pos.z end
p.HasDebuff=function() return false end;p.SoundEmitter={PlaySound=function() end}
local busy=false;p.components.playercontroller.IsBusy=function() return busy end
p.sg={statemem={},RemoveStateTag=function(_,tag) if tag=="busy" then busy=false end end}
TUNING.PANFLUTE_SLEEPTIME=20;TUNING.PANFLUTE_SLEEPRANGE=15
for _,e in ipairs(entities) do
 function e:HasAnyTag(tags) for _,tag in ipairs(tags) do if self:HasTag(tag) then return true end end;return false end
 e.components.sleeper={IsAsleep=function() return Status.Sleeping(e) end,AddSleepiness=function(_,sleepiness,time) assert(sleepiness==10 and time==20);e.anim="sleep_pre" end}
end
local instrument=assert(loadstring(read_source("components/instrument.lua")))()
local pan=read_source("prefabs/panflute.lua")
local a=assert(pan:find("local function OnPlayed",1,true));local last=assert(pan:find("local function SummonSoul",a,true))
local onplayed,heard=assert(loadstring(pan:sub(a,last-1).."\nreturn OnPlayed,HearPanFlute"))()
local flute=entity("panflute");flute.components.instrument=instrument(flute)
flute.components.instrument:SetRange(15);flute.components.instrument:SetOnPlayedFn(onplayed);flute.components.instrument:SetOnHeardFn(heard)
local oldState,oldEvent,oldTime=State,EventHandler,TimeEvent
State=function(v) return v end;EventHandler=function() return {} end;TimeEvent=function(t,fn) return {time=t,fn=fn} end
local source=read_source("stategraphs/SGwilson.lua");a=assert(source:find('name = "play_flute"',1,true))
local start=assert(source:sub(1,a):match(".*()State{"));last=assert(source:find("\n    State{",a,true))
local state=assert(loadstring("return "..source:sub(start,last-1):gsub(",%s*$","")))()
State,EventHandler,TimeEvent=oldState,oldEvent,oldTime
assert(state.timeline[1].time==1,"installed SG performs PLAY at 30 frames")
p.PerformBufferedAction=function() return flute.components.instrument:Play(p) end
local plays,eats=0,0
A.Self=function(_,item,action)
 if action==ACTIONS.PLAY then plays=plays+1;busy=true;p.anim="flute"
 elseif action==ACTIONS.EAT then eats=eats+1 end
 commands[#commands+1]={item=item,action=action};return true
end
package.loaded["shadowself/control/queenflute"]=nil;package.loaded["shadowself/control/beequeen"]=nil
local Queen=require("shadowself/control/beequeen")
c.enemies=entities;items={flute};c.bridge.wrappers={PreTheLoop={old=function() end}};p.pos=Vector3(10,0,0)
local Q=Queen(c);c.beequeen=Q;now=0
Q:Tick();assert(Q.late and Q.stage=="flute" and c.blocked and plays==1,"ten-guard stage uses full-coverage flute instead of long pull")
now=.5;Q:Tick();assert(c.blocked and plays==1 and not Q.flute_cycle.solo,"PLAY request alone never grants solo")
now=1;state.timeline[1].fn(p);Q:Tick();assert(c.blocked and Q.flute_cycle.confirmed,"actual source hearing puts queen and all guards to sleep; busy still blocks attack")
now=52/30;state.timeline[3].fn(p);Q:Tick()
assert(Q.stage=="strike" and c.target==queen and not c.blocked and Q.flute_cycle.solo,"actual busy release resumes queen solo")
queen.anim="idle";c.travel.dodging=true;c.travel.restore_dodge={};local restoring=c.travel.restore_dodge
now=2;Q:Tick();assert(not c.blocked and plays==1,"waking the queen by attacking must not trigger another flute")
assert(c.travel.dodging and c.travel.restore_dodge==restoring,"continuing solo must preserve native dodge and cane/weapon restoration ownership")
c.travel.dodging=nil;c.travel.restore_dodge=nil
-- Sleep animations, even without an entity sleeping tag, protect guard selection/navigation.
local nav=require("shadowself/control/navigation")
for _,bee in ipairs(bees) do bee.anim="sleep_loop" end
assert(nav.Risk(c,bees[1].pos,queen)==0,"sleeping guards do not create permanent avoidance circles")
bees[1].tags.sleeping=true;bees[1].anim="sleep_pst";now=3;Q:Tick()
assert(c.blocked and plays==2 and not Q.flute_cycle.solo,"one waking guard starts the next sleep cycle, even before stale tag clears")
assert(not Status.Sleeping(bees[1]),"wake animation overrides stale sleeping tag")
-- Failed/delayed hearing is retried after bounded wait, never assumed successful.
busy=false;now=7.2;Q:Tick();assert(c.blocked and plays==2 and not Q.flute_cycle.solo)
now=7.8;Q:Tick();assert(plays==3 and Q.flute_cycle.pending)
-- A guard beyond the ordinary 24-unit combat scan still prevents an incomplete PLAY.
busy=false;Q.flute_cycle=nil;bees[1].tags.sleeping=nil
for _,e in ipairs(entities) do e.anim="idle" end
c.enemies={queen};bees[10].pos=Vector3(26,0,0);p.pos=Vector3(0,0,8);now=9
local before=plays;Q:Tick()
assert(c.blocked and plays==before and c.moved and Q.stage=="flute","out-of-24-range bee prevents incomplete PLAY; move toward full-coverage midpoint")
local F=require("shadowself/control/queenflute")
assert(not F.Covered(p.pos,queen,bees,15))
p.pos=Vector3(13,0,0);bees[1].pos=Vector3(8,0,0);now=9.3;Q:Tick();assert(plays==before+1,"covered queen and full roster permit PLAY immediately")
-- Consuming the last flute keeps the pending acknowledgement and solo; wake reverts to no-flute strategy.
items={};now=10.3;state.timeline[1].fn(p);busy=false;Q:Tick()
assert(Q.flute_cycle and Q.flute_cycle.solo and not c.blocked,"last use disappearance does not discard successful sleep")
bees[1].anim="sleep_pst";now=11;Q:Tick();assert(not Q.flute_cycle and Q.stage=="lure","no flute on wake restores bounded lure")
-- First-phase multi-guard cleanup must also ignore sleeping guards.
local first=Queen(c);c.beequeen=first;items={};c.enemies={queen,bees[1],bees[2]};queen.anim="idle"
bees[1].anim="sleep_loop";bees[2].anim="idle";p.pos=Vector3(8,0,0);now=12
first:Tick();assert(c.target==bees[2],"closest sleeping guard is never selected for first-phase cleanup")
-- Auto-food only suppresses spicy electric jelly during queen combat, preserves other fights and acknowledgement.
package.loaded["shadowself/control/supplies"]=nil
local chili=entity("voltgoatjelly_spice_chili");items={chili};c.enemies={queen};c.observed={};c.travel={};c.bridge.chasing=nil
p._shadowself_combat_buffs=nil;local Supply=require("shadowself/control/supplies");local supply=Supply(c)
now=20;assert(not supply:Tick() and eats==0,"first stage never consumes spicy jelly")
first.phase=2;assert(not supply:Tick() and eats==0,"second stage near sleeping guards suppresses spicy jelly")
c.enemies={entity("deerclops")};assert(supply:Tick() and eats==1 and supply.pending,"other boss combat retains spicy jelly")
items={};c.enemies={queen};now=20.1;supply:Tick();assert(supply.state.electric_until,"already submitted food still uses inventory confirmation")
-- 所有距离用蜂后到守卫计算，不用玩家距离，也不忽略睡眠/冻结守卫。
local savedDebug,savedRoster=first.debug_bees,first.roster
local nearBee=entity("beeguard");nearBee.pos=Vector3(10,0,0);nearBee.anim="sleep_loop"
queen.pos=Vector3(0,0,0);queen.anim="idle";first.phase=2;first.debug_bees={nearBee};first.roster={[nearBee]=true};c.enemies={queen}
assert(supply:QueenBlocksChili(),"exactly10 units still blocks sleeping guards")
nearBee.pos=Vector3(10.01,0,0);assert(not supply:QueenBlocksChili(),"all guards strictly farther than10 restores food")
nearBee.anim="frozen";nearBee.pos=Vector3(9,0,0);assert(supply:QueenBlocksChili(),"frozen guards are still chain-lightning victims")
local otherBee=entity("beeguard");otherBee.pos=Vector3(-9,0,0);nearBee.pos=Vector3(15,0,0)
first.debug_bees={nearBee};first.roster={[nearBee]=true,[otherBee]=true}
assert(supply:QueenBlocksChili(),"known nearby guard outside current scan prevents consumption")
otherBee.tags.isdead=true;assert(not supply:QueenBlocksChili(),"dead guard does not suppress food")
first.spawn_wait={};assert(supply:QueenBlocksChili(),"incomplete spawn roster never enables chili")
first.spawn_wait=nil;queen.anim="spawn";assert(supply:QueenBlocksChili());queen.anim="idle"
for _,phase in ipairs({3,4}) do first.phase=phase;assert(not supply:QueenBlocksChili(),"later phases use the same10-unit safety gate") end
first.phase=1;assert(supply:QueenBlocksChili(),"first phase remains disabled even with enough separation")
first.phase=2;items={chili};p._shadowself_combat_buffs=nil;local farSupply=Supply(c);now=24
assert(farSupply:Tick() and eats==2 and farSupply.pending,"separated queen/guards restores actual original EAT submission")
items={};now=24.1;farSupply:Tick();assert(farSupply.state.electric_until,"restored chili still waits for inventory confirmation")
-- Buff到期之后依旧经过同一距离门槛，不另建补吃线程。
items={chili};now=farSupply.state.electric_until+1;assert(farSupply:Tick() and eats==3,"safe separation also allows normal buff renewal")
first.debug_bees=savedDebug;first.roster=savedRoster;first.phase=2;items={};now=25
-- Real bridge target and captured-victim gates, followed by the actual supervisor loop.
local Co=require("shadowself/control/coordinator");local savedCo=package.loaded["shadowself/control/coordinator"]
local oldStart,oldSleep,oldKill,oldPaused=StartThread,Sleep,KillThreadsWithID,IsSimPaused
local tuning={};local h={};local starts,stops,hits=0,0,0
h.GetAttackTargets=function(self) self.selected_ents={};for _,e in ipairs(entities) do self.selected_ents[e]=true end end
h.GetClosestTarget=function() return queen end;h.PreTheLoop=function() end;h.IsAttackPre=function() return false end
for _,name in ipairs({"OnKeyFrame","OnNormalFrame","CloseAndAttack","ShouldAtkWhenDodging"}) do h[name]=function() hits=hits+1;return true end end
h.StartHitAndRun=function() starts=starts+1;tuning.Cheatthread={id=81,SetList=function() end} end
h.StopHitAndRun=function() stops=stops+1;tuning.Cheatthread=nil end;h.DoDodge=function() end
local n={HitAndRun=h,TUNING=tuning,MOD_util={},ENT_util=require("shadowself/native").context.ENT_util,POS_util={GoToPoint=function() end},KEY_util={MoveKeyDown=function() return false end}}
require("shadowself/native").context=n
local pc=p.components.playercontroller;pc.DoAction=function() end;pc.IsHopping=function() return false end
p.replica.combat.IsAlly=function() return false end
c.h=h;c.gear={AttackRange=function() return 2 end,Weapon=function() return nil end,Swap=function() return true end}
c.Scan=function() end;c.HitRecovery=function() end;c.Stop=function() end;c.mechanisms={Tick=function() return false end}
c.bosses=nil;c.encounters=nil;c.supplies=nil;c.NativePulse=Co.NativePulse;c.travel={BeginDodge=function() end,EndDodge=function() end}
package.loaded["shadowself/control/coordinator"]=function(bridge) c.bridge=bridge;return c end
local routines={};StartThread=function(fn) local task={id=91,SetList=function() end};routines[task]=coroutine.create(fn);return task end
Sleep=function() coroutine.yield() end;KillThreadsWithID=function() end;IsSimPaused=function() return false end
local Bridge=require("shadowself/control/combat");local bridge=Bridge(p);assert(bridge:Start({kind="fight",coordinated=true,target="beeguard"},function() return true end))
package.loaded["shadowself/control/coordinator"]=savedCo
for _,bee in ipairs(bees) do bee.anim="sleep_loop" end
h.ent=queen;queen.anim="idle";c.beequeen=Queen(c);c.beequeen.queen=queen
assert(not bridge.allowed(bees[1]),"explicit target matching cannot bypass sleeping-guard rejection")
h:GetAttackTargets(24);assert(not h.selected_ents[bees[1]],"native selection removes sleeping guards")
assert(not h:CloseAndAttack(bees[1]) and hits==0,"captured dodge victim cannot hit a sleeping guard while current target is queen")
-- At active guards, supervisor physically suspends old 3014 task until sleep acknowledgement.
for _,bee in ipairs(bees) do bee.anim="idle";bee.tags.sleeping=nil;bee.pos=Vector3(3,0,0) end
p.pos=Vector3(10,0,2);c.enemies=entities;items={flute};c.beequeen=Queen(c);busy=false;now=30
assert(coroutine.resume(routines[bridge.supervisor]));assert(not bridge:OwnsThread() and stops==1,"flute request physically pauses native attack task")
now=31;state.timeline[1].fn(p);assert(coroutine.resume(routines[bridge.supervisor]));assert(not bridge:OwnsThread(),"no native restart before busy release")
now=31.8;p.pos=Vector3(3,0,2);state.timeline[3].fn(p);assert(coroutine.resume(routines[bridge.supervisor]));assert(bridge:OwnsThread() and starts==2,"confirmed full sleep resumes native queen solo")
queen.anim="idle";bees[2].anim="sleep_pst";now=32;assert(coroutine.resume(routines[bridge.supervisor]));assert(not bridge:OwnsThread() and stops==2,"awake guard suspends solo for another flute")
bridge:Stop();StartThread, Sleep,KillThreadsWithID,IsSimPaused=oldStart,oldSleep,oldKill,oldPaused
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/queenflute"]=nil;package.loaded["shadowself/control/beequeen"]=nil;package.loaded["shadowself/control/supplies"]=nil
print("PASS: actual game instrument/hearing/frame30 and busy52; full-roster coverage, missing bee, confirmed sleep/solo/wake/retry/last-use; sleeping target and captured victim rejection; spicy-jelly suppression; actual native supervisor pause/resume")
