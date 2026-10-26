package.path="./scripts/?.lua;"..package.path
local globals={};for _,k in ipairs({"Class","GetTime","Vector3","TheSim","TheWorld","TUNING","EQUIPSLOTS","ACTIONS"}) do globals[k]=_G[k] end
local saved={};for _,n in ipairs({"actions","incoming","weaver/observe","weaver/route","weaver/debug","weaver/sanity","weaver/cycle","weaver/round","weaver/ranged","weaver/phase1","weaver/controller"}) do
 local k="shadowself/control/"..n;saved[k]=package.loaded[k];package.loaded[k]=nil
end
Class=function(ctor) local c={};c.__index=c;return setmetatable(c,{__call=function(_,...)local o=setmetatable({},c);ctor(o,...);return o end})end
Vector3=function(x,y,z)return {x=x,y=y,z=z,DistSq=function(a,b)return (a.x-b.x)^2+(a.z-b.z)^2 end}end
local now=100;GetTime=function()return now end;EQUIPSLOTS={BODY="body",HANDS="hands",HEAD="head"};ACTIONS={EQUIP={},BLINK={},EAT={},UNEQUIP={}}
TUNING={};local all={};TheSim={FindEntities=function()return all end}
TheWorld={Map={IsPassableAtPoint=function()return true end,IsOceanAtPoint=function()return false end,IsPointNearHole=function()return false end},Pathfinder={IsClear=function()return true end}}
local seq=0
local function ent(name,x,z,a,f)
 seq=seq+1;local e={prefab=name,GUID=seq,pos=Vector3(x,0,z),animation=a or "idle",frame=f or 0,tags={},replica={}}
 function e:IsValid()return not self.removed end;function e:HasTag(t)return self.tags[t] or false end
 function e:GetPosition()return self.pos end;function e:GetPhysicsRadius()return self.radius or .5 end
 e.AnimState={IsCurrentAnimation=function(_,n)return e.animation==n end,GetCurrentAnimationFrame=function()return e.frame end,GetCurrentAnimationLength=function()return e.duration or 4 end}
 e.Transform={GetRotation=function()return 0 end}
 -- 一旦误读Boss服务端信息就立即报错。
 e.components=setmetatable({},{__index=function()error('server component access: '..name)end})
 e.sg=setmetatable({},{__index=function()error('server sg access: '..name)end})
 return e
end
local function prison(boss,marker,x,z)
 local entities={boss,marker}
 for i=0,5 do
  local a=i*math.pi/3;local e=ent('fossilspike',x+math.cos(a),z+math.sin(a),'fossil_pst');e.radius=.2
  entities[#entities+1]=e
 end
 return entities
end
local stops,equips,casts=0,0,0
package.loaded['shadowself/control/actions']={Items=function(p)return p.items end,Stop=function()stops=stops+1 end,
 Attack=function(p,e,guard)if not guard() then return false end;p.hand_attacks=(p.hand_attacks or 0)+1;p.hand_target=e;p.hand_guard=guard;p.attack_hand=p.hands;return true end,
 Self=function(p,i,a)
  if a==ACTIONS.EAT then p.eats=(p.eats or 0)+1;p.last_eat=i
  elseif a==ACTIONS.UNEQUIP then p.unequips=(p.unequips or 0)+1;p.last_unequip=i
  else equips=equips+1;p.last_equip=i end
  return true end,
 Ground=function(p,q,a,guard)assert(guard());casts=casts+1;p.castpoint=q;p.castguard=guard;return not p.reject_cast end}
package.loaded['shadowself/control/incoming']={Lane=function(c,e)return e.lane end,Risk=function(l,p)return p.x>=l.x and p.x<=l.x+6 and math.abs(p.z)<1 and 2 or 0 end}
local O=require('shadowself/control/weaver/observe');local R=require('shadowself/control/weaver/route')
local Debug=require('shadowself/control/weaver/debug');Debug.Configure(false)
local Controller=require('shadowself/control/weaver/controller')
local function fixture(entities,x,z)
 now=now+30;all=entities
 local boss=entities[1];local p=ent('wilson',x or 3,z or 0);p.items={};p.sanity=.1;p.hp=1;p.enabled=true
 p.components={playercontroller={IsBusy=function()return p.busy or false end,IsEnabled=function()return p.enabled end},
  playeractionpicker={GetRightClickActions=function(_,q)if p.no_blink_action then return {} end;return {{action=ACTIONS.BLINK,invobject=p.hands}} end}}
 p.replica.inventory={GetEquippedItem=function(_,slot)return p[slot] end}
 p.replica.sanity={GetPercentNetworked=function()return p.sanity end,IsInsane=function()return p.sanity<=.15 end};p.replica.health={GetPercent=function()return p.hp end}
 local c={player=p,h={ent=boss},snapshot={},observed={},hazards={},target=boss,paused=0,resumed=0,owns=false,enemies={}}
 c.bridge={allowed=function()return true end,PauseAttack=function()c.owns=false;c.paused=c.paused+1 end,
 OwnsThread=function()return c.owns end,ResumeAttack=function()c.owns=true;c.resumed=c.resumed+1 end,
 wrappers={PreTheLoop={old=function()end}}}
 c.gear={AttackRange=function()return 2 end,Weapon=function()return p.weapon end,Swap=function()c.swaps=(c.swaps or 0)+1 end}
 c.travel={BeginDodge=function()c.dodging=true end,EndDodge=function()c.dodging=false end}
 function c:Move(q)self.point=q;self.moves=(self.moves or 0)+1 end;function c:Speed()return self.speed or 7.5 end
 function c:Latency()return .122 end
 local w=Controller(c);c.weaver=w;return w,c,p,boss
end
local function step(w,dt)now=now+(dt or .11);return w:Tick()end
-- 整轮集成使用真实controller/cycle/route/sanity；服务端组件一旦被偷读就报错。
local function arena(bx,bz,extras)
 local boss=ent('stalker_atrium',bx or 8,bz or 8);local gate=ent('atrium_gate',0,0)
 gate.tags.structure=true;gate.radius=2.5
 local entities={boss,gate};for _,e in ipairs(extras or {})do entities[#entities+1]=e end
 local w,c,p=fixture(entities,10.5,10.5)
 local shield=true;boss._hasshield={value=function()return shield end}
 return w,c,p,boss,function(v)shield=v end,entities
end




-- 0.13.70 log 207.43 -> 209.00 -> 209.63: arrived during melee, then Boss walks, not casts.
local w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.86,0)
w:Scan();w.state.ready.snare=now+2.9;w:Tick();assert(w.lure_until)
local first=w.state.melee_started
p.pos=assert(w.bait_point);boss.frame=47;step(w,47/30)
assert(w.bait_waited and w.lure_until and not w.rebait,'actual melee still owns its busy window; do not turn back early')
boss.animation='walk_pre';boss.frame=0;step(w,.63)
assert(w.lure_until and not w.rebait,'near-due cage keeps the exit until actual cast or sustained failure after estimated ready')
boss.animation='walk_loop';boss.frame=0;step(w,.8)
assert(w.lure_until and not w.rebait,'one short walk interval with no displacement is not a failed lure')
for i=1,45 do boss.pos=Vector3(boss.pos.x+.05,0,0);step(w,1/30) end
assert(w.rebait and not w.lure_until and not w.bait_point and not w.escape_point,'walking instead of casting invalidates the old stationary-center plan')
assert(c.point and c.point:DistSq(boss.pos)<p.pos:DistSq(boss.pos),'return toward Boss instead of pushing toward the wall')
assert(not c.owns and not p.hand_attacks and w:AttackBlocked(boss),'return is bait only, never another hit')
-- Post-spawn RootExit cannot reclaim the failed lure while returning for a fresh melee.
local Cycle=require('shadowself/control/weaver/cycle');local root=Cycle.RootExit
Cycle.RootExit=function()return 'spawn'end
boss.animation='walk_loop';boss.frame=0;step(w,.2)
assert(w.rebait and not w.lure_until,'spawn CD estimate must not steal the rebait movement')
Cycle.RootExit=root
p.pos=Vector3(2.35,0,0);step(w,.2)
assert(w.rebait and not w.lure_until and not c.owns and not p.hand_attacks,'at bait distance wait without attacking')
boss.animation='attack';boss.frame=0;step(w,.2)
assert(not w.rebait and w.lure_until and w.state.melee_started~=first,'only a new observed melee start opens the next retreat')
assert(c.point and c.point:DistSq(boss.pos)>p.pos:DistSq(boss.pos),'fresh melee immediately starts the new retreat')
-- Genuine cage during the return still takes priority; no pre-hit blink.
boss.animation='walk_pre';boss.frame=0;p.pos=w.bait_point;w.bait_waited=true;w.state.ready.snare=now+8;step(w,.2)
for i=1,45 do boss.pos=Vector3(boss.pos.x+.05,0,0);step(w,1/30) end
assert(w.rebait)
boss.animation='attack1';boss.frame=0;step(w,.1)
assert(not w.rebait and not w.lure_until and casts==0,'real snare windup preempts return without teleporting before capture')
-- Failed route that never arrived also terminates on walking timeout, rather than extending forever.
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.86,0)
w:Scan();w.state.ready.snare=now;w:Tick();boss.animation='walk_loop';boss.frame=10;step(w,6)
assert(w.lure_until and not w.rebait,'expired route alone does not authorize return')
for i=1,45 do boss.pos=Vector3(boss.pos.x+.05,0,0);step(w,1/30) end
assert(w.rebait and not w.lure_until and not c.owns,'expired route plus sustained pursuit returns without band arrival')
-- A real shared skill owns the decision, not the missed-cast fallback.
for _,anim in ipairs({'attack1','spike','summon_loop','channel_pre'})do
 w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.86,0)
 w:Scan();w.state.ready.snare=now;w:Tick();w.bait_waited=true
 boss.animation=anim;boss.frame=0;step(w,6)
 assert(not w.rebait,'real stationary skill must not turn into a walk-back: '..anim)
end
-- 真实日志的五次短walk -> 骨牢：分别包含0.5秒服务端选择间隔和.12秒客户端观察。
for _,case in ipairs({{90.23,.10},{133.30,.03},{180.17,.20},{190.50,.17},{217.43,.27}})do
 w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.86,0)
 w:Scan();w.state.ready.snare=now;w:Tick();p.pos=w.bait_point;w.bait_waited=true
 now=case[1];w.lure_until=now-.01 -- 已超时也不能绕过保护。
 boss.animation='walk_pre';boss.frame=0;w:Tick()
 local selected=now+case[2]-.12;local servercheck=selected-.5
 for frame=1,math.ceil(case[2]*30)+1 do
  local t=case[1]+frame/30;now=t
  if t>=servercheck+.5+.12 then boss.animation='attack1';boss.frame=math.floor((t-selected)*30)
  else boss.frame=frame;boss.pos=Vector3(math.min(.14*frame,1),0,0) end
  w:Tick()
  assert(not w.rebait,'logged short transition cannot abandon escape: '..case[1])
 end
 assert(w.state.anim=='attack1' and w.snare_run,'delayed real cage owns the escape')
end
-- 饥饿动画和await_snare共存时，每帧只产生一次稳定阶段，不清掉清理事务。
local Cycle=require('shadowself/control/weaver/cycle')
w,c,p,boss=arena(0,0,{ent('stalker_minion1',1,0)})
boss.animation='taunt2_loop1';w:Tick();w.cycle.await_snare=true;w.cycle.spawn_snare=w.state.snare_started;w.cycle.spawn_spike=w.state.spike_count
local emit=Debug.Emit;local stages=0
Debug.Emit=function(_,event)if event=='cycle_stage' then stages=stages+1 end end
for frame=1,60 do step(w,1/30);assert(w.cycle.stage=='clear_feed') end
Debug.Emit=emit
assert(stages==0,'post-spawn wait must not toggle feast stage or reset cleanup each frame')
-- 源码保证的后续段与统一撤离预算：pre有清理窗口，未知额外loop不能借。
local Ranged=require('shadowself/control/weaver/ranged')
w,c,p,boss=arena(0,0,{ent('shadowchanneler',11.8,1)})
p.pos=Vector3(11.8,0,0);boss.animation='taunt3_pre';boss.duration=1;boss.frame=20;w:Scan();O.Update(w.state,boss,now)
assert(Ranged.BusyLeft(w)>=1.49,'taunt pre includes at least the guaranteed loop through original frame35')
assert(not Cycle.RootExit(w),'safe pre work must not be seized by early cage preparation')
boss.animation='taunt3_pst';boss.duration=1;boss.frame=29;O.Update(w.state,boss,now)
w.cycle={stage='spawn',await_snare=true}
assert(Cycle.RootExit(w)=='spawn','last visible busy frames must hand off to escape')
-- 首次人物到柱脚不够：每次决策都等Boss跟入，确认后短躲不强制归点。
local Phase1=require('shadowself/control/weaver/phase1')
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},12,0)
w.boss=boss;w.state.phase=1;w.fight_corners={Vector3(12,0,0),Vector3(12,0,15)}
w.phase1={stage='enter',goal=w.fight_corners[1],snares=1,spikes=0}
assert(Phase1.Tick(w) and w.phase1.stage=='wait' and w.phase1.anchor)
assert(Phase1.Tick(w) and w.phase1.stage=='wait','one historical arrival cannot release the follow-in condition')
boss.pos=Vector3(9,0,0)
assert(not Phase1.Tick(w) and w.phase1.stage=='fight','boss actually entered the pocket combat region')
print('PASS: logged missed-cast rebait, no extra hit, fresh melee retreat, spawn ownership, actual skill priority and no pre-hit blink')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
