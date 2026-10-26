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





local function landmarks()
 local extras={}
 for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.5},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5}})do
  local e=ent(v[1],-570+v[2],-10+v[3]);e.radius=v[4];extras[#extras+1]=e
 end
 return extras
end
local w,c,p,boss=arena(-558.98,-16.67,landmarks());all[2].pos=Vector3(-570,0,-10);w.center=all[2].pos
p.pos=Vector3(-556.47,0,-20.17);p.hands=ent('king_cane',0,0);p.items={p.hands}
w:Scan();w.state={minions={},phase=1,anim='attack',frame=13,melee_started=now-13/30,ready={snare=now+5}}
boss._hasshield={value=function()return false end};boss.animation='attack';boss.frame=13;boss.radius=.75;w.fight_corners={Vector3(-556.5,0,-19.95),Vector3(-556.5,0,-1.05)}
w.phase1={stage='fight'};w.focus=boss;w.holding=false
w.corner_dodge={point=Vector3(-556.45,0,-20.18),origin=Vector3(-557.51,0,-19.12),started=true,cast=w.state.melee_started}
local plan=w.corner_dodge;local pos=plan.point;local moves=c.moves or 0
for i=1,20 do w:AttackBlocked(boss)end
assert(w.corner_dodge==plan and plan.point==pos and (c.moves or 0)==moves,'native attack validation must never create/replace/advance movement plans')

-- 131.27真实位置：已接近伤害圈外沿，不能为绕到别的终点再走回3码处。
local start=now;local minimum=math.sqrt(p.pos:DistSq(boss.pos));c.speed=7.8
for frame=13,37 do
 now=start+(frame-13)/30;boss.frame=frame
 for i=1,8 do w:AttackBlocked(boss)end
 w:Tick()
 if w.moving and c.point then
  local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(d,5.1/30)
  if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d)end
 end
 local current=math.sqrt(p.pos:DistSq(boss.pos));minimum=math.min(minimum,current)
 if frame==32 then assert(current>4.3,'latest frame32 must remain outside source hit radius')end
end
assert(minimum>=4.28,'near-safe position cannot be changed into the logged3.03-yard inward walk')
-- 143.60真实最后一次普攻：3.17秒CD必须被同一次撤离接住，不继续穿到墙角等被困。
local extras={}
for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.5},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5}})do
 local e=ent(v[1],-570+v[2],-10+v[3]);e.radius=v[4];extras[#extras+1]=e
end
w,c,p,boss=arena(-568.07,-17.98,extras);all[2].pos=Vector3(-570,0,-10)
boss._hasshield={value=function()return false end};boss.radius=.75
p.pos=Vector3(-568.22,0,-16.68);p.hands=ent('king_cane',0,0);p.items={p.hands};c.speed=7.8
w:Scan();w.state.ready.snare=now+3.17;w.phase1={stage='return',snares=2,anchor=Vector3(-556.5,0,-19.95)}
boss.animation='attack';boss.frame=0;w:Tick()
assert(w.retreat and w.lure_until and not c.owns,'actual last melee must reserve the exit before the next ability-selection interval')
local began=now;local moving,queued,at;local caught=false
local A=require('shadowself/control/actions');local oldStop=A.Stop
A.Stop=function()moving=nil;queued=nil;at=nil end;c.h.StopPredictWalk=A.Stop
function c:Move(q)self.point=q;if moving then moving=q else queued=q;at=at or now+.12 end end
-- The first command was already emitted above; emulate its normal acknowledgement.
queued=c.point;at=now+.12
for frame=1,150 do
 now=began+frame/30
 if frame<=63 then boss.animation='attack';boss.frame=frame
 elseif now-began<3.67 then
  boss.animation='walk_loop';boss.frame=(frame-63)%30
  local d=math.sqrt(boss.pos:DistSq(p.pos));local n=math.min(d,4.2/30)
  if d>.001 then boss.pos=Vector3(boss.pos.x+(p.pos.x-boss.pos.x)*n/d,0,boss.pos.z+(p.pos.z-boss.pos.z)*n/d)end
 else boss.animation='attack1';boss.frame=math.floor((now-began-3.67)*30)end
 for j=1,4 do w:AttackBlocked(boss)end
 w:Tick()
 if at and now>=at then moving=queued;at=nil;queued=nil end
 if moving then
  local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,5.1/30)
  if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d)end
 end
 if boss.animation=='attack1' and boss.frame>=26 and boss.frame<=27 then
  caught=math.sqrt(p.pos:DistSq(boss.pos))<=15
 end
end
A.Stop=oldStop
assert(not caught,'late-melee -> boss pursuit -> real snare must not reproduce the wall-side capture')
print('PASS: native attack validation has no route-planning side effects')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
