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
-- Two actual near-endpoint reversals:104.40 and117.43. Keep real source SG impact frame32.
for _,v in ipairs({
 {104.40,18,-556.20,-.72,-557.82,-4.90,-556.07,-.59,-557.93,-2.45},
 {117.43,26,-562.33,.42,-559.84,-3.29,-562.39,.46,-557.63,-2.29}})do
 local w,c,p,boss=scene(v[5],v[6],v[3],v[4]);now=v[1]
 boss.animation='attack';boss.frame=v[2];local cast=now-v[2]/30
 w.state={phase=1,anim='attack',frame=v[2],melee_started=cast,ready={snare=now+8}}
 w.corner_dodge={point=Vector3(v[7],0,v[8]),origin=Vector3(v[9],0,v[10]),cast=cast,safe=4.5,reachable=true,started=true}
 w.point=w.corner_dodge.point;w.moving=true
 local moving=w.point;local before=math.sqrt(p.pos:DistSq(boss.pos));local held=false
 A.Stop=function()moving=nil end;c.h.StopPredictWalk=function()moving=nil end
 function c:Move(q)self.point=q;moving=q end
 for frame=v[2],36 do
  boss.frame=frame;now=cast+frame/30;w:Tick()
  assert(not c.owns,'native approach must not reclaim committed dodge before observed impact ends')
  if moving then
   local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,c:Speed()/30)
   if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d) end
  end
  local current=math.sqrt(p.pos:DistSq(boss.pos))
  assert(current>=before-.04,'logged endpoint cannot reverse into Boss before impact at '..v[1])
  before=current
  if frame==32 then assert(current>4.3,'actual source3.8+player.5 hit radius must stay clear') end
 end
 boss.frame=40;w.state.frame=40;R.BeginFrame(w)
 assert(not w:Threat(),'post-impact recovery returns output ownership without adding a whole attack-cycle delay')
end
--95.40 starts at2.34 with speed6; use physically open side-entry even if current speed cannot promise the deadline.
do
 local w,c,p,boss=scene(-559.85,-17.68,-557.90,-18.97);boss.animation='attack';boss.frame=0;c.speed=6
 w.state={phase=1,anim='attack',frame=0,melee_started=now,ready={snare=now+1}}
 R.BeginFrame(w)
 local first=assert(R.CornerDodge(w,5.35),'logged lower pocket must produce an executable exit')
 local plan=assert(w.corner_dodge)
 local from=p.pos
 for _,point in ipairs(plan.points)do
  assert(R.Path(w,point,nil,true,false,from,true),'every segment keeps real static/body clearance')
  from=point
 end
 local moving=nil;local queued=nil;local start=nil;local cast=now
 A.Stop=function()moving=nil;queued=nil;start=nil end;c.h.StopPredictWalk=function()moving=nil;queued=nil;start=nil end
 function c:Move(q)
  self.point=q
  if moving then moving=q else queued=q;start=start or now+.12 end
 end
 for frame=0,36 do
  now=cast+frame/30;boss.frame=frame;w.state.frame=frame
  if frame==5 then c.speed=7.8 end -- actual cane acknowledgement, never use it early in planning.
  R.BeginFrame(w)
  local goal=w:Threat()
  if goal then w:Move(goal,'logged pocket uninterrupted exit',nil,true) end
  if start and now>=start then moving=queued;queued=nil;start=nil end
  if moving then
   local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,c:Speed()/30)
   if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d) end
  end
  if frame==32 then assert(math.sqrt(p.pos:DistSq(boss.pos))>4.3,'logged side-entry continuation escapes source hit radius after actual speed acknowledgement') end
 end
end
-- A native attack preview before Observe sees the new animation must not mutate a prior cast.
do
 local w,c,p,boss=scene(-560,-3.3,-557.6,-2.3)
 boss.animation='attack';boss.frame=0;w.state={anim='walk_loop',frame=25,phase=1,ready={}}
 local marker={point=Vector3(-562,0,.5),cast=now-3};w.corner_dodge=marker
 assert(not R.CornerDodge(w,5) and w.corner_dodge==marker,'stale observation cannot plan using previous-animation frames')
end
A.Stop=oldstop
print('PASS: three real hurt geometries, endpoint extension/no reversal, impact ownership, open partial two-leg corridor and stale-preview isolation')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
