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

local A=require('shadowself/control/actions')
local function setup(worm)
 local extras=worm and {ent('stalker_minion1',-2,0)} or {}
 local w,c,p,boss,shield,entities=arena(-8,0,extras)
 p.pos=Vector3(3.9,0,0);p.sanity=.8
 local cane=ent('cane',0,0);local staff=ent('staff_lunarplant',0,0)
 p.items={cane,staff};p.hands=cane;boss.animation='taunt2_loop1';boss.duration=32/30
 shield(true);w:Scan();O.Update(w.state,boss,now);Cycle.Observe(w)
 w.state.ready.snare=now;w.lure_until=now+4;w.feast_lure=true;w.feast_tail=true
 w.bait_point=Vector3(3.9,0,0);w.escape_point=Vector3(8,0,0);w.escape_enough=true
 function c:Speed()return p.hands==cane and 7.8 or 6 end
 c.travel.BeginDodge=function()c.dodging=true;p.hands=cane end
 return w,c,p,boss,cane,staff,extras
end
local w,c,p,boss,cane,staff,extras=setup(true)
assert(R.BaitValid(w,12,15),'fast cane reaches actual cage escape deadline')
p.hands=staff;assert(not R.BaitValid(w,12,15),'fixture reproduces slower staff invalidating same escape');p.hands=cane
local oldSelf=A.Self;local ack;local equipcount=0
A.Self=function(actor,item,action)
 if action==ACTIONS.EQUIP then equipcount=equipcount+1;ack={at=now+.12,item=item} end
 return oldSelf(actor,item,action)
end
local started=now;local attackat
for i=1,25 do
 now=now+1/30;boss.frame=math.floor((now-started)*30)
 if ack and now>=ack.at then p.hands=ack.item;ack=nil end
 w:Tick()
 if p.hand_attacks then attackat=now;break end
end
assert(attackat and p.hand_target==extras[1] and equipcount==1,'speed change cannot steal a committed reachable worm shot before ATTACK')
assert(p.attack_hand==staff,'ordinary ranged shot actually equipped staff')
local until_launch=w.staff_action.launch_until
while now+.04<until_launch do now=now+1/30;boss.frame=math.floor((now-started)*30);w:Tick();assert(p.hands==staff,'movement cannot reclaim cane before launch budget')end
A.Self=oldSelf
w,c,p,boss,cane,staff=setup(false);local before=equips
for i=1,12 do now=now+1/30;boss.frame=i;w:Tick()end
assert(equips==before and p.hands==cane,'no reachable target must produce zero speculative staff equips')
-- Ordinary SAN restore must not stop a retreat that has not reached the band.
p.pos=Vector3(0,0,0)
local amulet=ent('purpleamulet',0,0);local armour=ent('armorwood',0,0)
p.items={cane,staff,amulet,armour};p.body=amulet;p.sanity=0
w.sanity_round={item=amulet,slot=EQUIPSLOTS.BODY,original=armour,restoring=true};w.cycle.spent=true
before=equips;w:Tick()
assert(w.moving and equips==before and p.body==amulet,'mask restore waits for safe band without stopping active retreat')
w.sanity_round=nil;p.body=nil;p.items={cane,staff}
-- SAN food cannot steal the short preparation already reserved for a shot.
w.staff_action={phase="prepare",target=staff};w.lure_until=nil;p.sanity=.1
p.components.playeractionpicker.GetInventoryActions=function()error('food picker must not run during shot preparation')end
assert(not S.Feed(w),'preparing an attack owns the food window')
w.staff_action=nil
-- Same client insanity predicate at every entry; a low display value is not a vulnerability guarantee.
p.sanity=.1;p.replica.sanity.IsInsane=function()return false end
assert(not S.Ready(w) and not S.CanPrepare(w),'low SAN in a non-insane replica cannot enter a fake ghost window')
-- Mid-wave observation must not invent one extra summon loop.
local state=O.New();boss.animation='summon_loop';boss.duration=1;boss.frame=20;O.Update(state,boss,now);w.state=state
assert(math.abs(Flight.BusyLeft(w)-1/3)<.001 and not state.summon_count_known,'unknown first seen loop borrows only visible duration')
boss.animation='summon_pre';boss.frame=0;O.Update(state,boss,now)
boss.animation='summon_loop';O.Update(state,boss,now)
assert(Flight.BusyLeft(w)==2 and state.summon_loops==1,'observed pre guarantees only the real first extra loop')
boss.frame=28;O.Update(state,boss,now);boss.frame=0;O.Update(state,boss,now)
assert(Flight.BusyLeft(w)==1 and state.summon_loops==2,'known second loop cannot invent another continuation')
-- Real preemption destroys stale shot/target ownership, not ghost death evidence.
w.staff_action={target=extras[1]};w.cycle.root_work={target=extras[1]}
w.sanity_round={restoring=false};Cycle.Interrupt(w,'actual_cage_hit')
assert(not w.staff_action and not w.cycle.root_work and w.sanity_round.restoring,'cage takeover cannot resurrect old work after teleport')
-- Already submitted cane hit wins over ordinary food cleanup/diversion.
w,c,p,boss,cane,staff,extras=setup(true);w.lure_until=nil;w.feast_lure=nil
p.items={cane};p.hands=cane;p.sanity=0;boss.animation='attack';boss.frame=40
local hand=ent('shadowchanneler',4,0);w.channelers={hand};w.state.anim='attack';w.state.frame=40;w.state.melee_started=now-40/30
w.cycle.deadline=now+1;w.cycle.hand=hand;w.cycle.sent=now;w.cycle.spent=nil;w.cycle.stage='clear_feed';w.cycle.food=extras[1]
local moves=c.moves or 0;local shots=p.hand_attacks or 0
assert(Cycle.Tick(w) and (c.moves or 0)==moves and (p.hand_attacks or 0)==shots,'pending hand attack cannot be replaced by a worm attack or movement')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
print('PASS: Weaver equipment-speed ownership, no-target stability, summon provenance, exact SAN and real preemption')
