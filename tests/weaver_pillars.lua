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
-- Installed atrium_end layout, converted from Tiled coordinates /16, relative to gate (288,288).
-- Preserve all three pillars and blocking landmarks; rotate/reflect/translate to test entity anchoring.
for rotation=0,3 do for _,mirror in ipairs({1,-1}) do
 local function pos(x,z)
  x=x*mirror
  for i=1,rotation do x,z=-z,x end
  return Vector3(x+100,0,z-200)
 end
 local extras={}
 local function add(n,x,z,r)
  local v=pos(x,z);local e=ent(n,v.x,v.z);e.radius=r or .5;extras[#extras+1]=e;return e
 end
 add('pillar_atrium',12,-13,2.5);add('pillar_atrium',-12,-13,2.5);add('pillar_atrium',-12,12,2.5)
 for _,v in ipairs({{-1,-15},{1,-14},{0,-13},{-1,-12}})do add('atrium_fence',v[1],v[2],.1)end
 add('atrium_light',-13,0);add('atrium_statue_facing',-13,-6,.45);add('atrium_statue_facing',-13,6,.45)
 add('atrium_rubble',-13,-3);add('atrium_rubble',-13,3)
 local w,c,p,boss,shield=arena(0,0,extras);shield(false);w.boss=boss
 local center=pos(0,0);w.center=center;w.home=center;boss.pos=pos(-7,0);p.pos=pos(-6,0)
 w.obstacles={};w.fences={};w.bodies={}
 for _,e in ipairs(extras)do if e.prefab=='atrium_fence' then w.fences[#w.fences+1]=e else w.obstacles[#w.obstacles+1]=e end end
 local corners=assert(R.FightCorners(w),'landmark endpoints exist in the installed three-pillar geometry')
 for _,q in ipairs(corners)do
  assert(q:DistSq(pos(-13.5,-9.95))<.01 or q:DistSq(pos(-13.5,8.95))<.01,'choose two-statue side, never fence side or missing fourth corner')
  assert(R.InArena(w,q) and R.Passable(q) and R.FenceClear(w,q))
 end
 w.phase1={stage='enter',snares=1,spikes=0};w.state={phase=1,anim='idle',ready={}}
 assert(Phase1.Tick(w) and w.phase1.stage=='enter' and w.phase1.goal,'first actual cage releases early pull to a real pillar')
 local target=w.phase1.goal
 local reached=false
 for j=1,12 do
  if p.pos:DistSq(target)<.01 then reached=true;break end
  local waypoint=assert(R.Waypoint(w,target),'deep pocket requires a legal full segmented route, not just a free endpoint')
  assert(R.Path(w,waypoint,nil,true));p.pos=waypoint
 end
 assert(reached,'pillar entry nodes reach the deep pocket in a finite number of segments')
 p.pos=Vector3(target.x,0,target.z);boss.pos=pos(-10.9,target:DistSq(pos(-13.5,-9.95))<.01 and -9.95 or 8.95)
 Phase1.Tick(w);assert(w.phase1.stage=='fight' and w.phase1.anchor==target);w.state={anim='attack',frame=0,melee_started=now,phase=1}
 boss.animation='attack';boss.frame=0;R.BeginFrame(w)
 local dodge=R.CornerDodge(w,5.25);assert(dodge,'long windup allows along-edge dodge')
 local edge=pos(-12,0);local direction=pos(-12,1)
 local normalx,normalz=direction.z-edge.z,-(direction.x-edge.x)
 local motionx,motionz=dodge.x-p.pos.x,dodge.z-p.pos.z
 local along=math.abs(motionx*(direction.x-edge.x)+motionz*(direction.z-edge.z))
 local cross=math.abs(motionx*normalx+motionz*normalz)
 assert(w.corner_dodge.reachable and along+cross>0,'full-circle exit is physically legal and clears the actual hit radius before impact')
 assert(R.Path(w,dodge,nil,true,false,nil,w.corner_dodge.reachable) and R.InArena(w,dodge),'whole lateral segment is legal')
 assert(w.phase1.anchor==target,'ordinary melee uses a short sideways dodge without throwing away damage to cross the whole arena')
 assert(R.CornerDodge(w,5.25)==dodge,'same cast keeps one direction without oscillation')
 local threat=w:Threat();assert(threat==dodge,'controller chooses lateral route rather than radial retreat')
 w:Move(threat,'test lateral full segment',nil,true)
 assert(c.point==dodge,'Move executes entire validated lateral segment without local edge scoring changing direction')
 w.phase1.stage='fight';p.pos=dodge;boss.animation='idle';w.state.anim='idle';R.BeginFrame(w)
 assert(not Phase1.Tick(w) and w.phase1.stage=='fight','after short sideways dodge output resumes without walking back to exact corner')
 w.state.anim='attack1';w.state.snare_started=now+1;Phase1.Observe(w)
 assert(w.phase1.stage=='return' and w.phase1.anchor==target and not w.phase1.goal,'next cage requests a nearest-end return without discarding established output ownership')
 p.pos=target;boss.animation='attack';w.state.anim='attack';R.BeginFrame(w)
 -- A real pillar on the lateral segment must reject it, even if both endpoints are passable land.
 local block=ent('pillar_atrium',(p.pos.x+dodge.x)/2,(p.pos.z+dodge.z)/2);block.radius=2.5
 w.obstacles[#w.obstacles+1]=block;R.BeginFrame(w)
 assert(not R.Path(w,dodge,nil,true),'continuous lateral route checks pillar collision')
end end
-- A route crossing the large attack/model circle is legal if it clears the small physical body before impact.
do
 local w,c,p,boss,shield=arena(0,0,{});shield(false);w.boss=boss;w.center=Vector3(0,0,0)
 w.obstacles={};w.fences={};w.bodies={};boss.radius=.75;boss.animation='attack';boss.frame=0
 p.pos=Vector3(-2,0,1.5);w.state={anim='attack',frame=0,melee_started=now};w.avoid_boss=5.2
 w.fight_corners={Vector3(-8,0,1.5),Vector3(8,0,1.5)};c.speed=10
 R.BeginFrame(w)
 local q=assert(R.CornerDodge(w,5.35),'fast enough early windup may cross the attack circle to the opposite side')
 assert(R.Path(w,q,nil,true),'selected physical exit remains valid')
 local crossing=Vector3(5.5,0,1.5)
 w.corner_dodge={point=crossing,cast=now,reachable=true}
 assert(R.Path(w,crossing,nil,true,false,nil,true),'a timely cross-model segment clears the 0.75 body instead of inheriting the generic never-approach restriction')
 assert(math.sqrt(q:DistSq(boss.pos))>=4.5,'impact endpoint uses source hit range plus player radius')
 boss.frame=29;w.state.frame=29;w.corner_dodge=nil;R.BeginFrame(w)
 local late=R.CornerDodge(w,5.35)
 assert(not late or not w.corner_dodge.reachable and not R.MeleeOutputWindow(w,late),'late exit cannot pretend safe passage or authorize another swing')
end
-- Delaying ordinary melee is bounded by actual travel and current normal attack commitment.
do
 local w,c,p,boss,shield=arena(0,0,{});shield(false);w.boss=boss;w.center=Vector3(0,0,0)
 p.pos=Vector3(2.6,0,0);w.obstacles={};w.fences={};w.bodies={};w.state={anim='attack',frame=0,melee_started=now}
 boss.animation='attack';boss.frame=0;p.animation='idle';c.speed=7.8
 local exit=Vector3(5.3,0,0)
 assert(R.MeleeOutputWindow(w,exit),'early ordinary windup still fits one normal swing plus escape')
 w.fight_corners={Vector3(-13.5,0,-9.95),Vector3(-13.5,0,8.95)}
 assert(not w:Threat(),'controller leaves the early output window to the original attack thread')
 w.lure_until=now+3
 assert(w:Threat(),'cage-reserved melee still leaves immediately instead of taking extra swings')
 w.lure_until=nil
 w.state.frame=20;boss.frame=20
 assert(not R.MeleeOutputWindow(w,exit),'late windup cannot fit another normal swing')
 assert(w:Threat(),'controller takes movement ownership before actual melee impact')
 -- Real cage-preparation branch remains above all delayed-melee decisions in controller.
end
-- Missing landmarks keep old scheduling available; they cannot create an infinite corner Hold.
local w,c,p,boss,shield=arena(0,0,{});shield(false);w.boss=boss;w.center=Vector3(0,0,0)
w.state={phase=1,anim='idle',ready={}};w.phase1={stage='center',snares=1};p.pos=Vector3(4,0,0)
assert(not R.FightCorners(w));Phase1.Tick(w);assert(w.phase1.stage=='fight')
print('PASS: native-layout pillar pair under eight transforms, first-cage transfer, locked lateral melee dodge, collision and missing-landmark fallback')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end



