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

local Cycle=require('shadowself/control/weaver/cycle')
local Flight=require('shadowself/control/weaver/ranged')
local S=require('shadowself/control/weaver/sanity')
-- 真实无标签壁画/雕像；宽度按原版碰撞体，而非图片视觉尺寸猜测。
local mural=ent('atrium_rubble',4,0);mural.radius=.5
local statue=ent('atrium_statue_facing',4,2);statue.radius=.45
local w,c,p,boss,setshield,entities=arena(-6,0,{mural,statue})
p.pos=Vector3(2,0,0);w:Scan()
assert(#w.obstacles>=2 and not mural:HasTag('structure') and not statue:HasTag('wall'),'untagged native obstacles must be scanned explicitly')
assert(not R.Path(w,Vector3(6,0,0),nil,true),'swept player body cannot cross a mural even if native pathfinder says clear')
assert(not R.Path(w,Vector3(6,0,2),nil,true),'a diagonal cannot cross the adjacent statue')
assert(R.Blocker(w,p.pos,Vector3(6,0,0))==mural,'diagnostic identifies the actual blocking prefab/GUID')
p.pos=Vector3(2,0,1);assert(not R.Path(w,Vector3(6,0,1),nil,true),'two native obstacles leave less than player clearance: reject the gap')
statue.pos=Vector3(4,0,4);assert(R.Path(w,Vector3(6,0,1.8),nil,true),'a genuinely wide opening stays usable')
local gatecenter=w.center;p.pos=Vector3(12,0,0);boss.pos=Vector3(0,0,0);w.bodies={};w.obstacles={mural,statue}
local exit=Vector3(13,0,10);w.escape_enough=true;w.escape_point=exit;w.bait_point=Vector3(11.9,0,0)
assert(not R.BaitValid(w,12,15),'a distant legal endpoint is not an exit from a wall-side band')
-- A projectile launched at high SAN, or followed by an early unequip, does no ghost damage.
local g1=ent('shadowchanneler',3,0);local g2=ent('shadowchanneler',-3,0);local g3=ent('shadowchanneler',0,3)
w,c,p,boss,setshield,entities=arena(0,0,{g1,g2,g3});p.pos=Vector3(10,0,0)
local staff=ent('staff_lunarplant',0,0);local amulet=ent('purpleamulet',0,0);local armour=ent('armorwood',0,0)
p.hands=staff;p.body=armour;p.sanity=.8;p.items={staff,amulet,armour}
p.replica.sanity.IsInsane=function()return p.body==amulet and p.sanity==0 end
assert(not Flight.GhostReady(w,g1),'high SAN must reject a ghost projectile target')
p.body=amulet;p.sanity=0;assert(Flight.GhostReady(w,g1),'acknowledged forced insanity permits a hit')
local function damage(e)if Flight.GhostReady(w,e)then e.tags.NOCLICK=true;return true end;return false end
p.body=armour;p.sanity=.8;assert(not damage(g1) and not g1.tags.NOCLICK,'old early restore makes a delayed projectile miss, not a successful submitted ATTACK')
-- Run the real supervisor with delayed equipment ack, windup, first flight and two bounce flights.
local A=require('shadowself/control/actions');local oldAttack,oldSelf=A.Attack,A.Self
local jobs={};local hits={};local restored_at;local submitted;local missed=0;local normal_attacks=0
local function later(delay,fn)jobs[#jobs+1]={at=now+delay,fn=fn}end
A.Self=function(actor,item,action)
 local result=oldSelf(actor,item,action)
 if action==ACTIONS.EQUIP or action==ACTIONS.UNEQUIP then
  later(.12,function()
   if action==ACTIONS.UNEQUIP then actor.body=nil
   elseif item==staff then actor.hands=item else actor.body=item end
   actor.sanity=actor.body==amulet and 0 or .8
   if submitted and actor.body~=amulet then restored_at=now end
  end)
 end
 return result
end
A.Attack=function(actor,target,guard)
 local ok=oldAttack(actor,target,guard);if not ok then return false end
 normal_attacks=normal_attacks+1
 if submitted then return true end
 submitted=now
 local function impact(e,nexttarget)
  if damage(e)then hits[#hits+1]=now else missed=missed+1 end
  if nexttarget then later(.1+math.sqrt(e.pos:DistSq(nexttarget.pos))/10,function()impact(nexttarget,nexttarget==g2 and g3 or nil)end)end
 end
 later(8/30+7/15+.12,function()impact(g1,g2)end)
 return true
end
boss.animation='taunt3_loop';boss.duration=8;boss.frame=0
w:Scan();w.state.ready.snare=now -- estimated ready must not block the actual busy window
local began=now
for i=1,180 do
 now=now+1/30;boss.frame=math.floor((now-began)*30)
 for j=#jobs,1,-1 do if now>=jobs[j].at then local job=table.remove(jobs,j);job.fn()end end
 if #hits==3 then setshield(false)end
 w:Tick()
 if submitted and now<submitted+.7 then assert(p.body==amulet,'amulet cannot be removed during the initial projectile flight')end
 if #hits==3 and restored_at then break end
end
assert(submitted and normal_attacks==1 and #hits==3 and missed==0,'one ordinary staff attack must land and bounce into three ghosts during summon')
assert(restored_at and restored_at>=hits[3],'SAN is restored only after the final confirmed bounce kill')
assert(casts==0,'staff attacks never use spellcasting')
-- Visibility/notarget changes are not death; leave a final living ghost pending.
g1.tags.NOCLICK=nil;g1.tags.notarget=true;all={boss,g1};w.channelers={g1};p.body=amulet;p.sanity=0
boss.animation='taunt3_loop';boss.frame=0;boss.duration=10;w.state.anim='taunt3_loop';w.state.frame=0;w.state.channeling=true;w.state.summoning=false
Flight.Sent(w,g1,staff);local flight=w.staff_action;now=flight.first_until+.1
assert(Flight.Pending(w),'notarget cannot be interpreted as a confirmed kill')
-- Safety preempts a still-pending chain before summon_pst frame7 and before control damage.
w.state.anim='summon_pst';w.state.channeling=false;w.state.summoning=true;w.state.frame=7
assert(not Flight.Pending(w) and not w.staff_action,'release pending flight at actual summon busy end rather than holding into cage')
w.state.anim='control_pre';w.state.summoning=false;w.state.controlling=true;w.state.frame=0;boss.duration=4
Flight.Sent(w,g1,staff);w.state.frame=110
assert(S.ControlDue(w) and not Flight.Pending(w),'control hit deadline overrides remaining bounce lifetime')
-- All-snapshot kills, including the final hand, may complete; high SAN alone may not.
w.state.controlling=false;w.state.anim='taunt3_loop';w.state.frame=0;w.state.channeling=true;boss.duration=10
g1.tags.notarget=nil;Flight.Sent(w,g1,staff);now=w.staff_action.first_until+.1;g1.tags.NOCLICK=true
assert(not Flight.Pending(w),'confirmed final ghost death completes the pending shot')
p.items={amulet,armour};p.hands=nil;assert(not Flight.Window(w),'no staff must use the existing melee/perimeter strategy')
A.Attack,A.Self=oldAttack,oldSelf
if read_source then
 local rubble=read_source('prefabs/atrium_rubble.lua');local statue=read_source('prefabs/atrium_statue.lua')
 assert(rubble:find('MakeObstaclePhysics(inst, .5)',1,true) and statue:find('MakeObstaclePhysics(inst, .45)',1,true))
 local fx=read_source('prefabs/brilliance_projectile_fx.lua')
 assert(fx:find('local SPEED = 15',1,true) and fx:find('local BOUNCE_SPEED = 10',1,true) and fx:find('local BOUNCE_RANGE = 12',1,true))
 assert(fx:find('DoTaskInTime(.1, TryBounce',1,true) and fx:find('SetRange(25)',1,true))
 local combat=read_source('components/combat_replica.lua')
 assert(combat:find('sanity:IsCrazy()',1,true),'ghost damage depends on insanity at damage resolution')
 local sg=read_source('stategraphs/SGstalker.lua')
 assert(sg:find('FrameEvent(7, function(inst) inst.sg:RemoveStateTag("busy") end)',1,true),'summon_pst releases busy at frame7')
end
print('PASS: untagged mural/statue collision, narrow gaps, in-flight SAN ownership, delayed staff damage and bounce chain, summon/control safety preemption, native no-staff fallback')
for k,v in pairs(globals)do _G[k]=v end
for _,k in ipairs({'Class','GetTime','Vector3','TheSim','TheWorld','TUNING','EQUIPSLOTS','ACTIONS'})do if globals[k]==nil then _G[k]=nil end end
for _,n in ipairs({'actions','incoming','weaver/observe','weaver/route','weaver/debug','weaver/sanity','weaver/cycle','weaver/round','weaver/ranged','weaver/phase1','weaver/controller'})do local k='shadowself/control/'..n;package.loaded[k]=saved[k] end
