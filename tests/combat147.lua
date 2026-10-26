-- Repeated windups with real native timing, attack-tag cane switch and supervisor handoff.
local function source(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local saved={player=ThePlayer,time=GetTime,world=TheWorld,tuning=TUNING,net=TheNet,sim=TheSim}
local now=10;GetTime=function() return now end;FRAMES=1/30
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),frame=0,anim='idle',tags={},GUID=x or 1,replica={},components={}}
 function e:IsValid() return true end;function e:HasTag(tag) return self.tags[tag] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.prefab=='sharkboi' and 1 or .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return a==e.anim end,GetCurrentAnimationFrame=function() return e.frame end,GetBuild=function() return 'normal' end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=ent('wilson',3,0);local mult=1.25;local item={replica={inventoryitem={GetWalkSpeedMult=function() return mult end}}}
p.replica.inventory={GetEquips=function() return {hands=item} end};p.components.playercontroller={IsBusy=function() return false end}
ThePlayer=p;TheWorld={state={}};TheNet={GetPing=function() return 22 end}
local H={GetTargetCanHitRange=function() return 5 end};local src=source('scripts/shadowself/native/engine/Dodge.lua')
local finish=assert(src:find("\n\taddcreature('dragonfly', 'taunt_pre'",1,true))
local env=setmetatable({HitAndRun=H,GLOBAL={DEGREES=math.pi/180},ThePlayer=p,
 math=setmetatable({clamp=function(x,a,b) return math.max(a,math.min(b,x)) end},{__index=math}),
 FunctionOrValue=function(v,...) return type(v)=='function' and v(...) or v end,
 GAME_util={GetGameDelay=function() return .022/FRAMES end},
 ENT_util={GetAnimation=function(_,e) return e.anim end,FnOrNum=function(_,v,...) return type(v)=='function' and v(...) or v end,CheckDebugString=function() return false end},
 distsq=function(a,b) return a:DistSq(b) end},{__index=_G})
local fn=assert(loadstring(src:sub(1,finish-1)..'\nend'));setfenv(fn,env);fn()
assert(H:GetSpeed()==7.5);mult=1;assert(H:GetSpeed()==6,'weapon acknowledgement cannot reuse cached cane speed')
mult=.8;assert(math.abs(H:GetSpeed()-4.8)<.001,'same-tick slowdowns also affect next dodge timing');mult=1
local fly=ent('dragonfly',0,0);fly.anim='atk'
for cycle=1,2 do
 H.idle_ticks=0
 for frame=0,15 do fly.frame=frame;assert(H:IsAttackPre(fly,1),'close dragon must not wait until frame17 after frame15 impact, cycle '..cycle) end
 fly.anim='idle';assert(not H:IsAttackPre(fly,1));fly.anim='atk'
end
-- Switching to move is intentional attack cancellation on a confirmed threat, no waiting for tag removal.
local swaps={};local Travel=require('shadowself/control/travel')
local travel=Travel(p,{Weapon=function() return item end,Swap=function(_,role) swaps[#swaps+1]=role;return true end})
p.tags.attack=true;travel:BeginDodge();assert(swaps[1]=='move','native dodge must equip cane during a swing')
travel:EndDodge();assert(#swaps==1,'weapon restoration still waits until swing tag is cleared')
p.tags.attack=nil;now=now+.11;travel:UpdateDodge();assert(swaps[2]=='attack')
-- Supervisor-originated pause used to cancel an already-sent mechanism move until the .1s retry.
local oldKill=KillThreadsWithID;KillThreadsWithID=function() end
local Bridge=require('shadowself/control/combat');local thread={id='test',SetList=function() end}
local moved;local bridge=Bridge(p);bridge.tuning={Cheatthread=thread};bridge.thread=thread
bridge.native={POS_util={GoToPoint=function(_,x,z) moved=Vector3(x,0,z) end}}
bridge.coordinator={blocked=true,last_action_kind='move',last_point=Vector3(4,0,2)}
bridge.h={StopHitAndRun=function() moved=nil;bridge.tuning.Cheatthread=nil end}
bridge:PauseAttack();assert(moved and moved.x==4 and moved.z==2,'supervisor must replay ant/queen escape in the same frame after StopWalking')
KillThreadsWithID=oldKill
-- A stale generic special flag cannot keep the just-dodged far enemy as the follow-up.
local far,near=ent('hound',8,0),ent('spider',2,0);p.pos=Vector3(0,0,0)
local c={player=p,h={ent=far,GetAttackTargets=function() end},special_active=true}
c.bridge={player=p,h=c.h,allowed=function() return true end,wrappers={PreTheLoop={old=function() end}}};c.h.selected_ents={[far]=true,[near]=true}
local Secondary=require('shadowself/control/secondary');local s=Secondary(c);s.Scan=function() end;s.Danger=function() return nil end
assert(s:AfterDodge(far)==near and c.h.ent==near,'nearest enemy wins after completed dodge even with stale special flag')
c.special_active=false;c.h.ent=far;s.data={};s.Scan=function() end;s.Danger=function() end
p.tags.attack=true;s:Pulse();assert(c.h.ent==far,'do not change target midway through a swing')
p.tags.attack=nil;s:Pulse();assert(c.h.ent==near,'each new swing refreshes nearest target, not just completed dodges')
-- Real speed movement against actual shark damage geometry; start with cane only, 22ms plus one tick.
local shark=ent('sharkboi',0,0);shark.anim='atk1'
local oldNav=package.loaded['shadowself/control/navigation']
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end}
package.loaded['shadowself/control/sharkroute']=nil;local Shark=require('shadowself/control/sharkroute')
local sc={player=p,hazards={}};p.pos=Vector3(3,0,0)
for frame=0,16 do
 shark.frame=frame;local data=Shark.Dodge(sc,shark,false);assert(data and data.noattack)
 local q=data:fn();local dx,dz=q.x-p.pos.x,q.z-p.pos.z;local distance=math.sqrt(dx*dx+dz*dz)
 if frame>=2 and distance>0 then local step=math.min(distance,7.5/30);p.pos=Vector3(p.pos.x+dx/distance*step,0,p.pos.z+dz/distance*step) end
 if frame==16 then assert(not ((p.pos.x-2)^2+p.pos.z^2<4^2 and p.pos.x>.25),'shark must clear actual offset arc before frame16 impact') end
end
assert(Shark.Dodge(sc,shark,false),'clearing the narrow damage boundary alone cannot stop the requested rear orbit')
for i=1,35 do
 local data=Shark.Dodge(sc,shark,false);if not data then break end
 local q=data:fn();local dx,dz=q.x-p.pos.x,q.z-p.pos.z;local d=math.sqrt(dx*dx+dz*dz)
 if d>0 then local step=math.min(d,7.5/30);p.pos=Vector3(p.pos.x+dx/d*step,0,p.pos.z+dz/d*step) end
end
assert(Shark.Rear(sc,shark) and not Shark.Dodge(sc,shark,false),'reach the actual back before immediately restoring attack')
package.loaded['shadowself/control/navigation']=oldNav;package.loaded['shadowself/control/sharkroute']=nil
ThePlayer,GetTime,TheWorld,TUNING,TheNet,TheSim=saved.player,saved.time,saved.world,saved.tuning,saved.net,saved.sim
print('PASS: repeated close dragon windups; live equipped speed; attack-tag cane; supervisor same-frame escape replay; nearest follow-up; actual 240-degree offset shark arc at7.5/22ms')
