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


local P=require('shadowself/control/weaver/phase1');local Round=require('shadowself/control/weaver/round')
local w,c,p,boss,setshield,entities=arena(-2,0,{})
setshield(false);p.pos=Vector3(9.9,0,0)
boss.animation='attack1';boss.frame=0;w:Tick()
assert(w.phase1.snares==1 and w.phase1.stage=='corner_exit','first actual snare arms transfer, never estimated HP or attack count')
p.pos=Vector3(13.3,0,0);boss.frame=31;step(w,31/30)
local q=w.phase1;local corner=q.corner
assert(corner and q.stage=='corner_travel' and R.InArena(w,corner) and math.abs(corner.x)>=11.9 and math.abs(corner.z)>=11.9,'after first snare select a reachable deep corner')
-- The old failure: an attack starts while player is still 4.5 units before the corner.
p.pos=Vector3(corner.x,0,corner.z-4.5);boss.pos=Vector3(corner.x-6,0,corner.z-5)
boss.animation='attack';boss.frame=0;step(w)
assert(q.stage=='corner_travel' and w.moving and not c.owns and not w.lure_until,'mid-route melee cannot turn into output or a second bait route')
assert(c.point:DistSq(corner)<.01,'continue to the actual corner, not a point 4-5 units short')
boss.frame=40;step(w,40/30)
assert(q.stage=='corner_travel' and w.moving and not c.owns,'after dodging a melee resume the same unfinished transfer')
-- Merely reaching the character endpoint is insufficient while Boss remains outside.
p.pos=corner;boss.animation='idle';boss.pos=Vector3(corner.x-4,0,corner.z-4);step(w)
assert(q.stage=='corner_wait' and not c.owns and not w.moving,'wait at real corner until boss follows all the way inside')
boss.pos=Vector3(corner.x-1.8,0,corner.z-1.8);step(w)
assert(q.stage=='corner_fight' and c.owns and not P.BlockAttack(w,boss),'only both arrivals release ordinary output')
-- Phase2 spawning mid-transfer must not silently reset corner task into centre feeding/chasing.
w,c,p,boss,setshield,entities=arena(-2,0,{})
setshield(false);p.pos=Vector3(9.9,0,0);boss.animation='attack1';w:Tick()
p.pos=Vector3(13.3,0,0);boss.frame=31;step(w,31/30)
q=w.phase1;corner=q.corner;p.pos=Vector3(corner.x,0,corner.z-4.5)
local hand=ent('shadowchanneler',2,0);entities[#entities+1]=hand;setshield(true)
boss.animation='taunt3_pre';step(w,.4)
assert(w.state.phase==2 and P.Transferring(w) and w.moving and not p.hand_attacks,'actual phase2 does not abandon the corner transfer while 4.5 units short')
-- Obstacles at a deep ideal coordinate must force another valid corner/depth, never an unsafe fallback.
local statue=ent('atrium_statue_facing',12.9,12.9);statue.radius=.45
w,c,p,boss,setshield,entities=arena(-2,0,{statue})
setshield(false);p.pos=Vector3(9.9,0,0);boss.animation='attack1';w:Tick()
p.pos=Vector3(13.3,0,0);boss.frame=31;step(w,31/30)
q=w.phase1;assert(q.corner and R.FenceClear(w,q.corner) and R.InArena(w,q.corner),'deep goal rejects occupied statue volume')
-- The later perimeter round has the same strict arrival gate.
w,c,p,boss,setshield,entities=arena(8,8,{})
w:Scan();O.Update(w.state,boss,now);w.state.phase=2
w.cycle={round='corner',round_since=now,center=Vector3(0,0,0),corners={Vector3(12.4,0,12.4)},index=1,corner=Vector3(12.4,0,12.4)}
p.pos=Vector3(12.4,0,7.9);boss.animation='attack';boss.frame=40
w.state.anim='attack';w.state.frame=40;w.state.melee_started=now-40/30
assert(Round.Tick(w) and w.cycle.round=='corner' and w.moving and not c.owns,'later corner cycle cannot enter control/output after a mid-route attack')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
print('PASS: first-snare deep corner, 4.5-unit-short melee continuation, boss arrival, phase2 takeover, statue collision and later-round arrival gate')
