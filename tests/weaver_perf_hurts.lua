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




local A=require('shadowself/control/actions');local oldstop=A.Stop
local function scene(bx,bz,px,pz)
 local extras={}
 for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.45},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5}})do
  local e=ent(v[1],-570+v[2],-10+v[3]);e.radius=v[4];extras[#extras+1]=e
 end
 local w,c,p,boss,shield,entities=arena(bx,bz,extras);shield(false)
 entities[2].pos=Vector3(-570,0,-10);boss.radius=.75;p.pos=Vector3(px,0,pz)
 w:Scan();w.center=entities[2].pos;w.home=w.center;w.zones={}
 w.fight_corners={Vector3(-556.5,0,-19.95),Vector3(-556.5,0,-1.05)}
 w.phase1={stage='fight',goal=w.fight_corners[2],snares=1,spikes=0,settled=true,followed=true}
 p.hands=ent('king_cane',0,0);p.items={p.hands};c.speed=7.8
 return w,c,p,boss
end
local function run(name,bx,bz,px,pz,grid,oldwalk)
 local w,c,p,boss=scene(bx,bz,px,pz);now=58.57
 if grid then
  local fence=ent('atrium_fence',-568,-22.57);fence.radius=.1;all[#all+1]=fence;w.next_scan=nil;w:Scan()
 end
 boss.animation='attack';boss.frame=0;c.speed=6;w.state.ready.snare=now+8
 local pf=TheWorld.Pathfinder;local nativecalls=0
 TheWorld.Pathfinder={IsClear=function(_,x,y,z,qx,qy,qz,flags)
  nativecalls=nativecalls+1;return not grid or flags.ignorewalls==true
 end}
 local moving=oldwalk and R.Point(boss.pos,p.pos,1.6) or nil;local queued,at
 A.Stop=function()moving=nil;queued=nil;at=nil end;c.h.StopPredictWalk=function()moving=nil;queued=nil;at=nil end
 function c:Move(q)self.point=q;queued=q;at=at or now+.13 end
 local began=now;local peak,peakms=0,0;local hits=0;local searches=0;local maxnodes=0
 local planner=R.PlanRetreat
 R.PlanRetreat=function(self,preview,short)
  searches=searches+1
  return planner(self,preview,short)
 end
 for frame=0,37 do
  now=began+frame/30;boss.frame=frame
  if frame>=5 then c.speed=7.8 end
  local before=os.clock();w:Tick();peakms=math.max(peakms,(os.clock()-before)*1000)
  peak=math.max(peak,w.route_paths or 0)
  if at and now>=at then moving=queued;queued=nil;at=nil end
  if moving then
   local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,c:Speed()/30)
   if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d) end
  end
  if (frame==32 or grid and frame==22) and math.sqrt(p.pos:DistSq(boss.pos))<=4.3 then hits=hits+1 end
 end
 R.PlanRetreat=planner;TheWorld.Pathfinder=pf
 print('PERF HURT',name,'hit',hits,'peak_paths',peak,'peak_ms',peakms,'native_queries',nativecalls,'searches',searches)
 return hits,peak,searches
end
local recenthits=run('logged83.57',-559.37,-2.48,-557.36,-1.24,false,true)
assert(recenthits==0,'latest exact Boss/player geometry must evade frame32, including inherited approach and delayed cane equip')
local hits,paths,searches=run('logged58.57',-560.08,-17.69,-557.64,-19.26,false,true)
assert(hits==0,'real58.57 geometry must clear the melee radius, not spend the windup on a snare-band detour')
assert(paths<1000,'local dodge must not repeat the4500-query global search')
assert(searches<=2,'one melee with no new obstacle may not continuously rebuild its path')
-- Later hurt lacks an observed Boss position: cover both bearings consistent with player distance2.75 and Boss center radius11.34.
local px,pz=-564.69,-20;local x,z=px+570,pz+10;local pr=math.sqrt(x*x+z*z)
local base=math.atan2(z,x);local da=math.acos((pr*pr+11.34^2-2.75^2)/(2*pr*11.34))
for _,sign in ipairs({-1,1})do
 local bx,bz=-570+math.cos(base+sign*da)*11.34,-10+math.sin(base+sign*da)*11.34
 local hit,checks=run('logged132-bearing'..sign,bx,bz,px,pz,true,false)
 assert(hit==0,'a raster wall must not veto a checked body-sized route on passable arena ground')
 assert(checks<1000,'failed raster paths must not trigger a full graph every frame')
 local nearx,nearz=px+(bx-px)/2.75*1.56,pz+(bz-pz)/2.75*1.56
 local closehit,closechecks=run('logged133-close-bearing'..sign,nearx,nearz,-564.73,-20.03,true,false)
 assert(closehit==0,'the close repeat attack must already be clear at the observed frame22 hurt')
 assert(closechecks<1000,'close repeated attacks keep bounded local work')
end
-- Same complex lure layout that used3920 path checks in0.13.75.
do
 local w,c,p,boss=scene(-560.04,-2.57,-557.90,-2.10)
 boss.animation='attack';boss.frame=0;c.speed=6;w.state.ready.snare=now
 local reads=0
 for _,e in ipairs(all)do local get=e.GetPosition;e.GetPosition=function(self)reads=reads+1;return get(self)end end
 local get=p.GetPosition;p.GetPosition=function(self)reads=reads+1;return get(self)end
 local before=os.clock();w:Tick()
 print('PERF RETREAT','peak_paths',w.route_paths,'cpu_ms',(os.clock()-before)*1000,'position_reads',reads)
 assert(w.retreat and w.retreat.complete,'optimization must retain the full legal escape corridor')
 assert(w.route_paths<1400,'full retreat must not repeat the old3900-check beam and graph search')
 assert(reads<300,'border samples must reuse the current observation snapshot rather than native position reads')
end
-- Precise geometry and holes remain authoritative even when native raster walls are ignored.
do
 local w,c,p,boss=scene(-560,-5,-556,-5);w.zones={};w.state.anim='attack';w.state.frame=0;w.state.melee_started=now
 TheWorld.Pathfinder={IsClear=function(_,x,y,z,qx,qy,qz,flags)return flags.ignorewalls==true end}
 local wall=ent('atrium_statue_facing',-558,-5);wall.radius=.45;w.obstacles={wall};w.bodies={};R.BeginFrame(w)
 assert(not R.Path(w,Vector3(-560,0,-5),nil,true,false,nil,true),'raster fallback never crosses a real entity')
 local oldhole=TheWorld.Map.IsPointNearHole
 TheWorld.Map.IsPointNearHole=function(_,q)return q.z>-3 end
 assert(not R.Path(w,Vector3(-556,0,-1),nil,true,false,nil,true),'hole detection remains active after raster fallback')
 w.center=nil;TheWorld.Map.IsPointNearHole=oldhole
 assert(not R.Path(w,Vector3(-556,0,-8),nil,true,false,nil,true),'outside the atrium the native raster veto remains authoritative')
 TheWorld.Map.IsPointNearHole=oldhole
end
A.Stop=oldstop
print('PASS: local hurt geometry, bounded native/path work, raster fallback with physical walls and holes retained')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
