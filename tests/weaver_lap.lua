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



local Phase1=require('shadowself/control/weaver/phase1')

local Cycle=require('shadowself/control/weaver/cycle')
local function layout()
 local out={}
 for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.5},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5},{'atrium_fence',0,-14,.1}})do
  local e=ent(v[1],v[2],v[3]);e.radius=v[4];out[#out+1]=e
 end
 return out
end
local extras=layout();local bug=ent('stalker_minion1',12.5,-9.9);local middle=ent('stalker_minion2',0,0)
extras[#extras+1]=bug;extras[#extras+1]=middle
local w,c,p,boss,shield,entities=arena(11,-8,extras);p.pos=Vector3(13.5,0,-9.95);boss.radius=.75
local cane=ent('king_cane',0,0);local staff=ent('staff_lunarplant',0,0)
p.items={cane,staff};p.hands=cane;p.sanity=.8;c.speed=7.8
boss.animation='taunt3_pre';boss.duration=4;boss.frame=0;w:Tick()
assert(w.cycle.stage=='spawn' and w.cycle.route_goal and w.cycle.perimeter,'actual channeler pre plans the perimeter without health or server SG')
assert(p.last_equip==staff and not p.hand_target,'edge worm starts one acknowledged staff preparation')
p.hands=staff;boss.frame=12;step(w,.4)
assert(p.hand_target==bug and p.attack_hand==staff,'staff selects edge-corridor worm, not centre worm')
assert(p.hand_target~=middle,'middle pile is not an attack destination')
bug.tags.NOCLICK=true;boss.animation='summon_pre';boss.frame=0;boss.duration=1;step(w,.8)
assert(w.cycle.await_snare,'a newly observed worm wave reserves the next actual shared skill')
boss.animation='summon_loop';boss.duration=2;boss.frame=0;step(w,.1)
assert(w.state.summon_loops==1 and not w.spawn_lure,'known first loop reopens clearing after the short pre')
boss.frame=59;step(w,59/30)
assert(w.spawn_lure and w.lure_until,'summon tail gives up clearing before the post-spawn cage')
local pending=p.hand_guard
if w.bait_point and w.escape_enough then p.pos=w.bait_point end
boss.animation='summon_pst';boss.frame=7;boss.duration=.5;step(w,.2)
assert(w.cycle.await_snare and w.lure_until,'busy release is not permission to chase a hand or worm')
boss.animation='attack1';boss.frame=0;step(w,.1)
assert(w.snare_run and w.cycle.shared_seen,'the actual cage owns motion after summon release')
assert(not pending or not pending(),'real cage invalidates an old attack guard')
boss.frame=31;step(w,31/30)
assert(not w.cycle.await_snare and not w.spawn_lure,'after actual cage resolution the perimeter resumes, not another synthetic cage wait')
-- Outer path constraints apply to every graph edge, not just the final destination.
w.lure_until=nil;w.avoid_boss=nil;boss.animation='idle';w.state.anim='idle';boss.pos=Vector3(0,0,0)
p.pos=Vector3(10.5,0,-10.5);R.BeginFrame(w)
local destination=Vector3(-10.5,0,10.5);local arrived=false
for i=1,14 do
 if p.pos:DistSq(destination)<.01 then arrived=true;break end
 local waypoint=assert(R.Waypoint(w,destination,true),'a segmented outer route exists around centre and native blockers')
 assert(R.OuterPath(w,waypoint) and R.Path(w,waypoint,nil,true),'every executed leg remains outside centre')
 p.pos=waypoint;R.BeginFrame(w)
end
assert(arrived,'segmented outer graph makes forward progress around obstacles')
-- Cage direction preference cannot override actual collision or the release deadline.
w.cycle=nil;p.pos=Vector3(10,0,3.9);boss.pos=Vector3(10,0,-8);w.obstacles={};w.fences={};w.bodies={}
w.fight_corners={Vector3(13.5,0,-9.95),Vector3(13.5,0,8.95)};w.state={anim='idle',frame=0,phase=1,ready={}};R.BeginFrame(w)
local exit,travel,budget=R.SnareExit(w,p.pos,0,15)
assert(exit and travel<=budget and R.Path(w,exit,nil,true),'preferred-side cage exit still meets physical and timing constraints')
assert(exit.x>p.pos.x+.2,'when feasible, cage exit bends toward the two pillar pockets rather than the arena centre')
print('PASS: native-layout spawn planning, edge staff selection, known-loop reopening, post-spawn cage barrier, full outer path and cage side preference')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end



