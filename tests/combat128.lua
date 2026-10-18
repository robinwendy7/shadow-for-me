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
h.GetAttackTargets=function(self,range)
 self.selected_ents={};for _,e in ipairs(TheSim:FindEntities(p.pos.x,0,p.pos.z,range)) do self.selected_ents[e]=true end
end
h.GetClosestTarget=function(self) for e in pairs(self.selected_ents) do return e end end
h.PreTheLoop=function() end;h.IsAttackPre=function() return false end;h.DoDodge=function() end
h.CancelDodgingAtk=function() end
for _,name in ipairs({"OnKeyFrame","OnNormalFrame","CloseAndAttack","ShouldAtkWhenDodging"}) do h[name]=function() hits=hits+1;return true end end
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
bridge:Stop();StartThread,Sleep,KillThreadsWithID,IsSimPaused=oldStart,oldSleep,oldKill,oldPaused
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/beequeen"]=nil
print("PASS: third-phase guard target veto before all overrides; actual native DoDodge captured-target follow-up blocked; actual supervisor/Scan retain queen beyond24 and known guards; boost-only pull, immediate normal-form return and close normal guards ignored")
