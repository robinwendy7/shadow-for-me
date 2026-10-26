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

-- Logged stall: player relative to gate (13.37,-9.93), pillar (12,-13).
-- Boss bearing was not logged in .67; cover legal approaching bearings, including a blocked radial exit.
local extras={}
for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.5},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5}}) do
 local e=ent(v[1],v[2],v[3]);e.radius=v[4];extras[#extras+1]=e
end
local w,c,p,boss,shield=arena(12.2,-7.6,extras);shield(false);w.boss=boss;w.center=Vector3(0,0,0)
w.obstacles=extras;w.fences={};w.bodies={};w.fight_corners={Vector3(13.5,0,-9.95),Vector3(13.5,0,8.95)}
p.pos=Vector3(13.37,0,-9.93);c.speed=7.8;boss.radius=.75;boss.animation='attack';boss.frame=0
w.state={anim='attack',frame=0,melee_started=now,phase=1,ready={}};w.phase1={stage='fight',goal=w.fight_corners[1],settled=true,at_corner=true}
R.BeginFrame(w)
local radial=R.Point(boss.pos,p.pos,5.3)
assert(not R.Path(w,radial,nil,true),'radial retreat is blocked by the pillar/boundary in this corner')
local q=assert(R.CornerDodge(w,5.35),'open inward/lower corridor must be considered outside the old +/-45 degree search')
assert(R.Path(w,q,nil,true,false,nil,w.corner_dodge.reachable) and p.pos:DistSq(q)>1,'the selected route must execute meaningful legal movement')
assert(q.x<p.pos.x-1,'take the open inward/lower corridor rather than stand against the outer pillar')
local threat=w:Threat()
if not threat then
 assert(w.corner_dodge.reachable and R.MeleeOutputWindow(w,q),'only a verified extra-hit window may defer movement')
 w.state.frame=12;boss.frame=12;R.BeginFrame(w);threat=w:Threat()
end
assert(threat,'controller must take a legal exit before the hit; no radial fallback standstill')
w:Move(threat,'logged corner exit',nil,true);assert(c.point and p.pos:DistSq(c.point)>1,'movement actually receives a nonzero destination')
-- Even when late enough that complete escape cannot be proved, use the available corridor; do not claim safety.
w.corner_dodge=nil;w.state.frame=27;boss.frame=27;w.state.melee_started=now+2;R.BeginFrame(w)
local late=assert(R.CornerDodge(w,5.35),'a partial legal exit beats remaining at the blocked radial point')
assert(not w.corner_dodge.reachable and not R.MeleeOutputWindow(w,late),'partial exit cannot authorize another swing')
print('PASS: logged corner geometry, blocked radial exit, full-circle lower corridor, controller movement and partial-exit attack lock')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end



