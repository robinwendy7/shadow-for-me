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




local Flight=require('shadowself/control/weaver/ranged')
local Cycle=require('shadowself/control/weaver/cycle')
local nearplayer=ent('stalker_minion1',5.5,0);local nearboss=ent('stalker_minion2',1,0)
local w,c,p,boss=arena(0,0,{nearplayer,nearboss})
p.pos=Vector3(6,0,0);local staff=ent('staff_lunarplant',0,0);p.items={staff};p.hands=staff;p.sanity=.8
boss.animation='taunt2_loop1';boss.duration=4;w:Scan();O.Update(w.state,boss,now)
w.cycle={stage='clear_feed',perimeter=true}
assert(Flight.FoodTarget(w)==nearboss,'Boss distance must outrank player distance and scan order')
assert(Flight.Work(w,nearplayer) and p.hand_target==nearboss,'a near-player worm request attacks the nearest Boss food instead')
local job=w.staff_action;assert(job and job.phase=='flight')
nearplayer.pos=Vector3(.2,0,0)
Flight.Work(w,nearplayer)
assert(w.staff_action==job and job.target==nearboss,'new food rank cannot cancel a committed shot')
-- Boss-nearest food out of range: approach a legal firing position instead of silently picking the near-player worm.
now=now+.7;w.staff_action=nil;w.light_sent=nil;nearplayer.pos=Vector3(-10,0,10);p.pos=Vector3(10.2,0,0);p.hand_target=nil
assert(Flight.Work(w,nearplayer) and w.staff_action.target==nearboss and w.staff_action.phase=='approach')
assert(c.point and c.point.x<p.pos.x and not p.hand_target,'move into range before sending the Boss-food shot')
p.pos=c.point;Flight.Work(w,nearplayer)
assert(p.hand_target==nearboss and w.staff_action.phase=='flight')
nearboss.tags.NOCLICK=true;assert(Flight.FoodTarget(w)==nearplayer,'confirmed dead food leaves priority list')
now=now+.7;nearboss.tags.NOCLICK=nil;w.staff_action=nil;w.light_sent=nil;p.pos=Vector3(11.9,0,0)
w.lure_until=now+4;w.feast_lure=true;w.feast_tail=true;boss.duration=4
assert(Flight.Work(w,nearplayer) and w.staff_action.target==nearboss and w.staff_action.phase=='approach','long observed feast may approach Boss food only with a complete return budget')
w.staff_action=nil;boss.duration=.6
assert(not Flight.Work(w,nearplayer) and not w.staff_action,'short feast cannot spend the escape budget to approach food')

-- 实测11.67米外、32帧吞食循环：最近虫超射程，仍应从连通虫群首发，不能旁观。
now=now+1;w.staff_action=nil;w.light_sent=nil;w.lure_until=nil;w.feast_tail=nil
p.pos=Vector3(11.67,0,0);p.hand_target=nil;nearplayer.pos=Vector3(5,0,0)
boss.duration=32/30;boss.frame=12;O.Update(w.state,boss,now)
local cane=ent('king_cane',0,0);p.items={cane,staff};p.hands=cane;w.next_equip=now+.1
assert(Flight.FoodTarget(w)==nearboss and Flight.FoodShot(w,nearboss)==nearplayer,'reachable relay must still connect to the Boss-nearest food')
assert(Flight.Work(w,nearboss) and w.staff_action.phase=='prepare','partial busy window begins weapon preparation')
now=now+.11;boss.frame=15;O.Update(w.state,boss,now);Flight.Work(w)
assert(p.last_equip==staff,'after the equip limiter clears the short loop equips instead of waiting for an impossible full setup budget')
p.hands=staff;boss.frame=28;O.Update(w.state,boss,now);Flight.Work(w)
assert(not p.hand_target,'too-late frames preserve the prepared weapon without cancelling/launching')
now=now+.15;boss.frame=0;O.Update(w.state,boss,now);Flight.Work(w)
assert(p.hand_target==nearplayer and w.staff_action.phase=='flight','next real 32-frame loop launches into the feeding cluster')
local committed=w.staff_action
nearboss.pos=Vector3(2,0,0);Flight.Work(w,nearboss)
assert(w.staff_action==committed,'relay rank changes cannot cancel a committed ordinary attack')
nearplayer.pos=Vector3(5,0,14)
assert(Flight.FoodShot(w,nearboss)==nearboss,'an unrelated player-near worm outside bounce connectivity cannot replace food')

-- 完整监督器：真实短循环、估计骨牢已就绪、鬼手共存，清虫仍必须持续发射。
local hungry=ent('stalker_minion1',-7,0);local relay=ent('stalker_minion2',-3,0)
local ghost=ent('shadowchanneler',3,3)
w,c,p,boss=arena(-8,0,{hungry,relay,ghost})
p.pos=Vector3(3.67,0,0);p.sanity=.8;p.hands=cane;p.items={cane,staff};boss.duration=32/30;boss.animation='taunt2_loop1'
w:Scan();O.Update(w.state,boss,now);Cycle.Observe(w);w.state.ready.snare=now
local start=now;local ack;local requested;local shots=0;local previous=0
for frame=1,96 do
 now=start+frame/30;boss.frame=frame%32
 if ack and now>=ack then p.hands=requested;ack=nil end
 w:Tick()
 if p.last_equip and p.last_equip~=p.hands and not ack then requested=p.last_equip;ack=now+.12 end
 if (p.hand_attacks or 0)>previous then
  assert(p.hand_target==relay,'whole controller must use the feeding cluster before the visible ghost')
  shots=shots+1;previous=p.hand_attacks
 end
 assert(not w.lure_until,'a ready estimate cannot send a staffed player away while the Boss is visibly eating')
end
assert(shots>=2,'three real short feast loops must produce repeated worm shots instead of permanent window waiting')
local prepared=p.hand_guard;boss.animation='attack1';boss.frame=0;step(w)
assert(not prepared() and w.snare_run,'actual cage must still revoke cleanup and take movement ownership')

-- Statue .45 + player .5 fits the 1.10-wide physical gap to arena edge14.55.
local statue=ent('atrium_statue_facing',13,0);statue.radius=.45
w,c,p,boss=arena(8,0,{statue});w.boss=boss;w.center=Vector3(0,0,0);w.obstacles={statue};w.fences={};w.bodies={};w.zones={}
p.pos=Vector3(14.0,0,-3)
for _,cached in ipairs({false,true})do
 w.route_frame=nil;if cached then R.BeginFrame(w)end
 assert(R.Path(w,Vector3(14,0,3),nil,true),'full player sweep fits statue-to-boundary gap, cached='..tostring(cached))
 assert(not R.Path(w,Vector3(14.1,0,3),nil,true),'player radius cannot cross real arena boundary')
 p.pos=Vector3(13.4,0,-3)
 assert(not R.Path(w,Vector3(13.4,0,3),nil,true),'inner line still collides with statue')
 local via,total=R.Waypoint(w,Vector3(13.4,0,3),true)
 assert(via and total>6 and R.Path(w,via,nil,true),'segmented outer route must find the narrow passage')
 p.pos=Vector3(14,0,-3)
end
-- Close the physical gap: neither buffering adjustment nor cached path may tunnel through it.
statue.pos=Vector3(13.2,0,0);R.BeginFrame(w)
assert(not R.Path(w,Vector3(14,0,3),nil,true),'less than a player width remains blocked')
statue.pos=Vector3(13,0,0);w.route_frame=nil
-- Screenshot-like pocket: direct upward crossing hits the statue, inward/downward exits are unavailable.
p.pos=Vector3(13.4,0,-2.5);boss.pos=Vector3(12,0,-1.6);boss.radius=.75;boss.animation='attack';boss.frame=0;c.speed=7.8
w.fight_corners={Vector3(13.4,0,-2.5),Vector3(13.4,0,5)};w.state={anim='attack',phase=1,frame=0,melee_started=now,ready={}}
TheWorld.Map.IsPassableAtPoint=function(_,x,y,z)return x>=13.3 and z>=-2.6 and z<=6 end
R.BeginFrame(w)
local first=assert(R.CornerDodge(w,5),'corner must use a side-entry path instead of rejecting the statue side entirely')
local plan=assert(w.corner_dodge)
assert(plan.reachable and plan.exit,'no straight ray fits this pocket: use two full checked segments')
assert(R.Path(w,first,nil,true,false,nil,true))
local endpoint=plan.exit
p.pos=first;R.BeginFrame(w)
assert(R.CornerDodge(w,5)==endpoint,'finish the side entry then continue along the same edge route')
assert(R.Path(w,endpoint,nil,true,false,nil,true) and math.sqrt(endpoint:DistSq(boss.pos))>=plan.safe)
print('PASS: Boss-nearest staff food, committed shot ownership, safe approach, narrow statue edge passage, closed gap rejection and two-leg corner dodge')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end


