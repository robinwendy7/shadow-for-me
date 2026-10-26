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



local Co=require("shadowself/control/coordinator");local savedCo=package.loaded["shadowself/control/coordinator"]
local oldStart,oldSleep,oldKill,oldPaused=StartThread,Sleep,KillThreadsWithID,IsSimPaused
local queen=entity("beequeen");queen.tags.epic=true;queen.tags.hostile=true
queen.replica.health={GetPercent=function() return .45 end};queen.replica.combat={GetTarget=function() return p end}
local guard=entity("beeguard",6,0);guard.tags.hostile=true;guard.build="bee_guard_puffy_build"
guard.AnimState.GetBuild=function() return guard.build end;guard.components.locomotor={walkspeed=8}
guard.replica.combat={GetTarget=function() return p end}
entities={queen,guard}
TheSim.FindEntities=function(_,x,y,z,radius)
 local out={};for _,e in ipairs(entities) do if e.pos:DistSq(Vector3(x,0,z))<=radius^2 then out[#out+1]=e end end;return out
end
local tuning={};local h={};local hits,moves=0,0
local lastCloseForce
h.GetAttackTargets=function(self,range)
 self.selected_ents={};for _,e in ipairs(TheSim:FindEntities(p.pos.x,0,p.pos.z,range)) do
  if not p.replica.combat:IsAlly(e) then self.selected_ents[e]=true end
 end
end
h.GetClosestTarget=function(self) for e in pairs(self.selected_ents) do return e end end
h.PreTheLoop=function() end;h.IsAttackPre=function() return false end;h.DoDodge=function() end
h.CancelDodgingAtk=function() end
for _,name in ipairs({"OnKeyFrame","OnNormalFrame","CloseAndAttack","ShouldAtkWhenDodging"}) do h[name]=function() hits=hits+1;return true end end
h.CloseAndAttack=function(_,target,force) hits=hits+1;lastCloseForce=force;return true end
h.StartHitAndRun=function() tuning.Cheatthread={id=81,SetList=function() end} end
h.StopHitAndRun=function() tuning.Cheatthread=nil end
local n={HitAndRun=h,TUNING=tuning,MOD_util={},ENT_util=require("shadowself/native").context.ENT_util,POS_util={GoToPoint=function(_,x,z) moves=moves+1;c.moved=Vector3(x,0,z) end},KEY_util={MoveKeyDown=function() return false end}}
require("shadowself/native").context=n
p.replica.combat.IsAlly=function() return false end
p.components.playercontroller.DoAction=function() end;p.components.playercontroller.IsHopping=function() return false end
c.owner={perception={}};c.h=h;c.gear={AttackRange=function() return 2 end,Weapon=function() return nil end,Swap=function() return true end}
c.bosses=nil;c.encounters=nil;c.supplies=nil;c.mechanisms={Tick=function() return false end,Dodge=function(_,e,base) return base end}
c.profiles={};c.Profile=Co.Profile;c.Scan=Co.Scan;c.NativePulse=Co.NativePulse;c.HitRecovery=function() end;c.Stop=function() end
c.travel={BeginDodge=function() end,EndDodge=function() end,UpdateDodge=function() end}
c.Move=function(self,point,label) self.blocked=true;self.moved=point;self.status=label;moves=moves+1 end
package.loaded["shadowself/control/coordinator"]=function(bridge) c.bridge=bridge;return c end
local routines={};StartThread=function(fn) local task={id=91,SetList=function() end};routines[task]=coroutine.create(fn);return task end
Sleep=function() coroutine.yield() end;KillThreadsWithID=function() end;IsSimPaused=function() return false end
local Bridge=require("shadowself/control/combat");local bridge=Bridge(p);assert(bridge:Start({kind="fight",coordinated=true,target="beeguard"},function() return true end))
package.loaded["shadowself/control/coordinator"]=savedCo
package.loaded["shadowself/control/beequeen"]=nil
local Q=require("shadowself/control/beequeen")(c);c.beequeen=Q;Q:Anchor(queen)
bridge.priority_target=guard;bridge.resume_target=guard
Q.phase=1;assert(bridge.allowed(guard),"first phase still permits clearing/freezing guards")
-- 明确标记要换掉的一阶段高抗守卫，允许原生补刀；其他冻结守卫仍不打。
Q.recycle_guard=guard;guard.anim="frozen";h.ent=guard
assert(bridge.allowed(guard) and h:ShouldAtkWhenDodging(guard),"phase1 replacement can attack frozen old guard after an in-flight ice projectile")
Q.recycle_guard=nil;assert(not h:ShouldAtkWhenDodging(guard),"ordinary frozen guard remains protected")
guard.anim="idle";hits=0;h.ent=queen
Q.phase=2;assert(bridge.allowed(guard),"policy does not rewrite second phase")
Q.phase=3;Q.late=true;assert(not bridge.allowed(guard),"third-phase guard rejected before explicit command, old priority and resume overrides")
p.pos=Vector3(8,0,0);h:GetAttackTargets(24);assert(not h.selected_ents[guard] and h.selected_ents[queen])
c.blocked=false;c.special_active=false;c.queen_active=true;h.ent=queen;bridge.chasing=nil
assert(not h:CloseAndAttack(guard) and not h:ShouldAtkWhenDodging(guard) and hits==0,"awake/unfrozen captured guard cannot receive follow-up")
h.ent=guard;h:OnKeyFrame();h:OnNormalFrame();assert(hits==0)
h.ent=queen;h:OnKeyFrame();assert(hits==1,"queen output remains allowed")
-- Load the actual shipped DoDodge to verify its captured-guard exit cannot bypass the policy.
local raw=read_3014_dodge();local cut=assert(raw:find("\n\tlocal initidlelist",1,true))
local data={point="target",dist=6,fn=function() return Vector3(12,0,0) end};local originalDodge=h.DoDodge
p.PushEvent=function() end;h.ent=guard;h.pos=guard.pos;h.ppos=p.pos
local env=setmetatable({GLOBAL={DEGREES=math.pi/180},HitAndRun=h,ThePlayer=p,FRAMES=1/30,
 FunctionOrValue=function(v,...) return type(v)=="function" and v(...) or v end,distsq=function(a,b) return a:DistSq(b) end,
 POS_util=n.POS_util,Sleep=function() h.ent=queen end},{__index=_G})
local chunk=assert(loadstring(raw:sub(1,cut-1).."\nend"));setfenv(chunk,env);chunk()
h:DoDodge(data);assert(hits==1,"actual native DoDodge captures guard but cannot attack it after target switches to queen")
h.DoDodge=originalDodge
-- Actual supervisor + actual Scan: queen outside 24 units remains the encounter's target.
bridge.priority_target=queen;bridge.resume_target=nil;p.pos=Vector3(32,0,0);guard.pos=Vector3(30,0,0);now=10;c.next_scan=nil
assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="dash_pull" and c.queen_active and c.h.ent==queen and c.moved.x>32)
local sawqueen=false;local sawguard=false;for _,e in ipairs(c.enemies) do if e==queen then sawqueen=true elseif e==guard then sawguard=true end end
assert(not sawqueen and sawguard,"real scan retains guard as a threat even when it cannot be attacked, queen is outside radius")
-- A temporarily absent scan entry does not discard the already tracked boosted guard.
p.pos=Vector3(48,0,0);guard.pos=Vector3(46,0,0);guard.tags.hostile=nil;guard.replica.combat.GetTarget=function() return nil end
now=10.2;c.next_scan=nil;assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="dash_pull" and c.moved.x>48 and Q.roster[guard],"retain known guards and continue pulling while boost remains; 48 units is not a return trigger")
-- Boost finishes; ignore guard and immediately head toward queen, without clearing it first.
guard.build="bee_guard_build";guard.components.locomotor.walkspeed=3;guard.pos=Vector3(50,0,0)
now=10.4;c.next_scan=nil;assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="dash_return" and c.moved.x<48 and c.h.ent==queen and hits==1)
-- Close normal guards do not restart pull; only a new real boost does.
p.pos=Vector3(2,0,0);guard.pos=Vector3(8,0,0);now=10.6;c.next_scan=nil;assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="strike" and not c.blocked and bridge:OwnsThread())
guard.pos=Vector3(5,0,0);now=10.8;c.next_scan=nil;assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="dash_wait" and c.h.ent==queen and not bridge.allowed(guard))
guard.build="bee_guard_puffy_build";guard.components.locomotor.walkspeed=8;now=11;c.next_scan=nil
assert(coroutine.resume(routines[bridge.supervisor]));assert(Q.stage=="dash_pull" and c.blocked and not bridge:OwnsThread(),"new boost alone starts the next outbound leg")
-- 实际桥接选敌/补刀入口验证：战车排最后，但仍保留 allowed 供躲避扫描。
local rook=entity("rook",3,0);local knight=entity("knight",4,0)
c.beequeen=nil;c.bosses=b;c.special_active=false;c.blocked=false;bridge.chasing=nil;bridge.pause_requested=nil
bridge.priority_target=rook;bridge.resume_target=rook;h.selected_ents={[rook]=true,[knight]=true};h.ent=rook
assert(bridge.allowed(rook) and h:GetClosestTarget()==knight,"actual target picker deprioritizes rook without removing its threat")
local before=hits;h:OnKeyFrame();h:CloseAndAttack(rook);h:ShouldAtkWhenDodging(rook)
assert(hits==before,"actual keyframe/close/captured dodge followup cannot hit rook while another target remains")
h.selected_ents={[rook]=true};assert(h:GetClosestTarget()==rook);h:OnKeyFrame();assert(hits==before,"last rook still waits for observed charge recovery");c.bosses.rooks[rook]={ready=true};h:OnKeyFrame();assert(hits==before+1,"observed charge recovery permits native attacks")
bridge:PauseAttack();c.special_active=false;c.blocked=true;before=hits
h:OnKeyFrame();h:CloseAndAttack(rook);assert(hits==before,"delayed old attack callback cannot steal movement while mechanism owns the paused thread")
c.blocked=false
local spike=entity("sandspike_tall",2,0);bridge.priority_target=spike;assert(not bridge.allowed(spike),"sand spike rejected before priority and explicit command overrides")
-- 帝王蟹过滤也必须先于priority/resume/显式指令，不让原线程误补刀小蟹。
local king=entity("crabking",0,0);local wall=entity("crabking_icewall",2,0);local crabmob=entity("crabking_mob",3,0)
c.crabking=require("shadowself/control/crabking")(c);c.crabking.king=king;c.crabking.stage="break";c.crabking.wall=wall
bridge.priority_target=crabmob;bridge.resume_target=crabmob;h.ent=king
assert(bridge.allowed(king) and bridge.allowed(wall) and not bridge.allowed(crabmob) and not bridge.allowed(rook))
before=hits;h:CloseAndAttack(crabmob);assert(hits==before,"captured crab minion follow-up blocked in actual attack wrapper")
bridge.priority_target=wall;assert(h:GetClosestTarget()==wall,"break ice explicitly picks its allowed wall through actual native picker")
c.crabking=nil
local sleepingEscort=entity('icehound',3,0);sleepingEscort.tags.sleeping=true;sleepingEscort.replica.combat={}
local sleepingTrap=entity('icehound',4,0);sleepingTrap.tags.sleeping=true;sleepingTrap.replica.combat={}
local oldArena,oldContains,oldHunt=bridge.plan.arena,bridge.plan.arena_contains,bridge.plan.arena_walrus
bridge.plan.arena=true;bridge.plan.arena_contains=function() return true end
bridge.plan.arena_walrus={Escort=function(_,e) return e==sleepingEscort end}
assert(bridge.allowed(sleepingEscort) and not bridge.allowed(sleepingTrap),'actual native target filter distinguishes flute-controlled escort from a sleeping trap')
bridge.plan.arena=oldArena;bridge.plan.arena_contains=oldContains;bridge.plan.arena_walrus=oldHunt
-- Actual supervisor: a distant stopped rook resumes normal ATTACK approach,
-- rather than handing the character to the generic GoToPoint chase first.
c.plan=bridge.plan;c.plan.arena=true;c.plan.arena_wave=function() return 3 end
c.plan.arena_remaining=function() return {rook,knight} end
c.plan.arena_contains=function() return true end
entities={rook,knight};rook.pos=Vector3(0,0,0);knight.pos=Vector3(0,0,-15);p.pos=Vector3(12,0,0)
rook.anim='idle';c.bosses=b;b.rooks[rook]={ready=true,hits=0}
bridge.priority_target=rook;bridge.resume_target=nil;bridge.chasing=true;c.travel.chasing=true
c.blocked=false;c.special_active=false;c.queen_active=false;c.next_scan=nil;now=12
local oldMoves=moves
assert(coroutine.resume(routines[bridge.supervisor]))
assert(bridge:OwnsThread() and not bridge.chasing and moves==oldMoves,'stopped rook outside melee reach starts native attack without a walk-to-face phase')
rook.anim='atk_pre';rook.frame=0;c.next_scan=nil;now=12.1
assert(coroutine.resume(routines[bridge.supervisor]))
assert(not bridge:OwnsThread() and moves>oldMoves and math.abs(c.moved.z)>=2.2,'actual supervisor interrupts attack and dispatches lateral movement on the first rook preparation frame')
-- Actual bridge: both walrus targets hold ground and suppress ordinary retreat;
-- the state ends for the escort dog.
local walrus=entity('walrus',0,0)
local hunt=require('shadowself/control/arena_walrus')({player=p})
hunt.active=true;hunt.control_done=true;hunt.target=walrus;hunt.engaged[walrus]=true
c.plan.arena_wave=function() return 2 end;c.plan.arena_walrus=hunt;h.ent=walrus
assert(h.shadowself_hold_ground() and not h:IsAttackPre(walrus,1) and c.secondary:Focus()==walrus,'engaged walrus uses actual hold-ground and attack focus hooks')
walrus.prefab='little_walrus'
assert(h.shadowself_hold_ground() and not h:IsAttackPre(walrus,1),'little walrus also suppresses ordinary attack retreat')
hunt.target=sleepingEscort;h.ent=sleepingEscort
assert(not h.shadowself_hold_ground() and not c.secondary:Focus(),'escort does not inherit walrus hold-ground')
c.plan.arena_walrus=nil
local small=entity('smallbird',12,0);local teen=entity('teenbird',8,0);local adult=entity('tallbird',1,0)
local savedAlly=p.replica.combat.IsAlly
for _,bird in ipairs({small,teen}) do
 bird.tags.companion=true;bird.tags.sleeping=true
 bird.replica.combat={GetTarget=function() end}
end
adult.tags.sleeping=true;adult.replica.combat={GetTarget=function() end}
p.replica.combat.IsAlly=function(_,e)
 return e:HasTag('companion') and (not e.replica.combat or e.replica.combat:GetTarget()~=p)
end
entities={small,teen,adult};c.plan.arena_remaining=function() return entities end
bridge.priority_target=adult;h.selected_ents={[small]=true,[teen]=true,[adult]=true};h.ent=adult
assert(p.replica.combat:IsAlly(small) and p.replica.combat:IsAlly(teen),'actual sleep/companion ally classification is reproduced')
assert(bridge.allowed(small) and bridge.allowed(teen),'sleeping arena birds remain eligible despite companion-based ally classification')
bridge.wrappers.GetAttackTargets.old(h,30)
assert(not h.selected_ents[small] and not h.selected_ents[teen],'original native scan drops both companion birds')
h:GetAttackTargets(30)
assert(h.selected_ents[small] and h.selected_ents[teen],'owned scan restores only current arena roster birds')
assert(h:GetClosestTarget()==small,'real target picker follows smallbird before closer teen/adult birds')
before=hits;h:CloseAndAttack(adult);assert(hits==before,'captured larger-bird followup cannot bypass kill order')
h.ent=small;c.blocked=false;bridge.chasing=nil
before=hits;h:CloseAndAttack(small)
assert(hits==before+1 and lastCloseForce==true,'actual attack bridge requests normal forced attack for the sleeping arena chick in non-prediction mode')
c.plan.arena_bird_committed=function(e)
 return c.plan.arena_wave()==2 and e and ({smallbird=true,teenbird=true,tallbird=true})[e.prefab] or false
end
assert(h.shadowself_hold_ground() and not h:IsAttackPre(small,1) and c.secondary:Focus()==small,'tallbird opening commits the selected smallest bird without attack retreat')
local savedMechanisms,savedHealing,savedSupplies=c.mechanisms,c.healing,c.supplies
c.mechanisms={Tick=function() error('continuous bird attacks cannot hand control to optional support') end,Dodge=function(_,_,data) return data end}
c.healing={Tick=function() error('continuous bird attacks cannot retreat for optional healing') end,BlockAttack=function() return false end}
c.supplies={Tick=function() error('continuous bird attacks cannot retreat for optional buffs') end}
h.shadowself_dodging=nil;c.next_scan=nil;c.blocked=false;c.special_active=false;now=12.5
local birdMoves=moves
assert(coroutine.resume(routines[bridge.supervisor]))
assert(moves==birdMoves and bridge:OwnsThread(),'actual supervisor keeps native attacks and does not issue retreat/chase movement for the committed bird')
c.mechanisms,c.healing,c.supplies=savedMechanisms,savedHealing,savedSupplies
local pet=entity('smallbird',2,0);pet.tags.companion=true;pet.replica.combat={GetTarget=function() end}
pet.replica.follower={GetLeader=function() return p end};entities[#entities+1]=pet
assert(not bridge.allowed(pet),'player-owned bird is not included in the arena ally exception')
local outsider=entity('smallbird',1,0);outsider.tags.companion=true;outsider.replica.combat={GetTarget=function() end}
assert(not bridge.allowed(outsider),'same prefab outside the current arena roster remains excluded')
small.replica.health={IsDead=function() return true end}
assert(h:GetClosestTarget()==teen,'replicated death immediately advances priority even before dead tags arrive')
small.replica.health=nil
small.tags.dead=true;h.ent=h:GetClosestTarget();assert(h.ent==teen and h.shadowself_hold_ground() and not h:IsAttackPre(teen,1),'confirmed smallbird death advances to continuous teenbird attacks')
teen.tags.dead=true;h.ent=h:GetClosestTarget();assert(h.ent==adult and h.shadowself_hold_ground() and not h:IsAttackPre(adult,1),'confirmed teenbird death advances to continuous tallbird attacks')
c.plan.arena_wave=function() return 3 end
small.tags.dead=nil;assert(not bridge.allowed(small),'companion exception ends outside the second wave')
p.replica.combat.IsAlly=savedAlly
-- Actual bridge: every native attack entry is blocked throughout bishop aim/charge/emission.
local bishop=entity('bishop_nightmare',0,0);entities={bishop};c.plan.arena_wave=function() return 3 end
c.plan.arena_remaining=function() return entities end
local rhythm=require('shadowself/control/arena_clockwork')(bishop);c.plan.arena_clockwork=rhythm
bridge.priority_target=bishop;bridge.chasing=nil;h.ent=bishop;c.blocked=false;c.special_active=false
bridge:ResumeAttack();c.bosses=b;b.entities={};c.healing=nil;c.supplies=nil
before=hits
for _,name in ipairs({'atk2_pre','atk2_loop','atk2_pst'}) do
 bishop.anim=name
 for _,f in ipairs({0,999}) do
  bishop.frame=f
  h:OnKeyFrame();h:OnNormalFrame();h:CloseAndAttack(bishop);h:ShouldAtkWhenDodging(bishop)
  local dodge=h:IsAttackPre(bishop,1)
  assert(hits==before and dodge and dodge.noattack,'all four actual native attack entries remain blocked for the entire real bishop state, independent of frame')
 end
end
local scans=0
c.mechanisms={Scan=function() scans=scans+1 end,Tick=function() error('bishop aiming must not hand control to mechanism actions') end,Dodge=function(_,_,data) return data end}
c.healing={Tick=function() error('healing cannot steal bishop aiming movement') end,BlockAttack=function() return false end}
c.supplies={Tick=function() error('supplies cannot steal bishop aiming movement') end}
h.shadowself_dodging=bishop;c.next_scan=nil;now=14
assert(coroutine.resume(routines[bridge.supervisor]));assert(scans==1 and hits==before,'actual supervisor refreshes marks read-only while native dodge owns movement')
h.shadowself_dodging=nil;bishop.anim='idle';c.blocked=false
h:CloseAndAttack(bishop);assert(hits==before+1 and h.shadowself_hold_ground(),'actual state exit immediately releases attacks')
bishop.anim='atk2_pre';bishop.frame=0;h:CloseAndAttack(bishop)
assert(hits==before+2 and not h:IsAttackPre(bishop,1) and h.shadowself_hold_ground(),'after the first dodge later volleys keep continuous output with no extra movement')
-- 巡游攻击锁作用于四个真实原生入口，不能依赖某一Boss实现刚好返回move。
c.arena_patrol=true;c.bosses=nil;c.plan.arena_clockwork=nil;before=hits
h:OnKeyFrame();h:OnNormalFrame();h:CloseAndAttack(bishop);h:ShouldAtkWhenDodging(bishop)
assert(hits==before,'patrol lock blocks every native melee entry even without a Boss gate')
c.arena_patrol=nil;c.plan.arena_wave=function() return 6 end
c.enemies={{prefab='lightninggoat',replica={},IsValid=function() return true end,HasTag=function() return false end}}
h:OnKeyFrame();h:OnNormalFrame();h:CloseAndAttack(bishop);h:ShouldAtkWhenDodging(bishop)
assert(hits==before,'electric-goat scene is melee-locked even before the first patrol state update')
c.enemies={};c.plan.arena_wave=function() return 11 end
local fish=entity('mermguard_shadow',2,0);local pig=entity('daywalker',3,0)
entities={fish,pig};c.plan.arena_remaining=function() return entities end
bridge.priority_target=fish;h.ent=fish;c.blocked=false;bridge.chasing=nil;c.plan.arena_stage11={Allowed=function(_,e) return e==fish end}
before=hits
assert(bridge.allowed(pig),'nonpriority pig remains in threat scanning while its attack entries are vetoed')
h:CloseAndAttack(pig);h:ShouldAtkWhenDodging(pig);h.ent=pig;h:OnKeyFrame();h:OnNormalFrame()
assert(hits==before,'stage11 cannot hit pig through any of the four captured native attack entries')
h.ent=fish;c.secondary.pending=nil;c.secondary.next_scan=nil
h:CloseAndAttack(fish);assert(hits==before+1,'allowed fish still uses the normal native attack entry')
c.plan.arena_stage11={Allowed=function() return false end};before=hits
h:OnKeyFrame();h:OnNormalFrame();h:CloseAndAttack(fish);h:ShouldAtkWhenDodging(fish)
assert(hits==before,'unconfirmed hat/buff or closed worm feeding window blocks every attack entry')
c.plan.arena_stage11=nil
bridge:Stop();StartThread,Sleep,KillThreadsWithID,IsSimPaused=oldStart,oldSleep,oldKill,oldPaused
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/beequeen"]=nil
print("PASS: third-phase guard target veto before all overrides; actual native DoDodge captured-target follow-up blocked; actual supervisor/Scan retain queen beyond24 and known guards; boost-only pull, immediate normal-form return and close normal guards ignored")
