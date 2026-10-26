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
local Phase1=require('shadowself/control/weaver/phase1')
-- 最新日志真实召虫：有6秒以上CD，却在第一次短loop就永久交出清虫权。
local food=ent('stalker_minion1',-6,0)
local w,c,p,boss,shield=arena(-8,0,{food})
p.pos=Vector3(3.9,0,0);p.hands=ent('king_cane',0,0);p.items={p.hands,ent('staff_lunarplant',0,0)}
boss.animation='summon_loop';boss.duration=22/30;boss.frame=8
w:Scan();O.Update(w.state,boss,now);Cycle.Observe(w);w.state.ready.snare=now+6.6
print('AUDIT premature spawn owner',Cycle.RootExit(w))
assert(not Cycle.RootExit(w),'6.6-second snare cooldown cannot lock a still-summoning Boss into cage preparation')
-- 最新日志真实吞食：15.7米外无首发入口，接近不应要求移动加换装加抛弹都在一圈内完成。
boss.animation='taunt2_loop1';boss.duration=32/30;boss.frame=0;p.pos=Vector3(7.7,0,0)
w.staff_action=nil;O.Update(w.state,boss,now);Cycle.Observe(w);w.state.ready.snare=now+6
assert(Flight.Work(w,food) and w.staff_action and w.staff_action.phase=='approach' and c.point,'food beyond range must make safe walking progress, not stand through every loop')
-- 一阶段已经引入过Boss，骨牢后回程遇上Boss时应恢复战斗，而非强制穿到精确柱脚。
w,c,p,boss,shield=arena(6,4);shield(false);p.pos=Vector3(8,0,4)
w:Scan();w.fight_corners={Vector3(13.5,0,-9.95),Vector3(13.5,0,8.95)}
w.phase1={stage='return',snares=2,anchor=w.fight_corners[2],goal=w.fight_corners[2]}
w.state={phase=1,anim='walk_loop',ready={snare=now+8}}
assert(not Phase1.Tick(w) and w.phase1.stage=='fight','Boss already followed into the fight corridor: resume output instead of exact-corner commute')

-- 进入射程后CD临近必须撤离，但该撤离不能又被“有法杖+有食物”每帧取消重建。
do
 local worm=ent('stalker_minion1',-7,-8)
 local w,c,p,boss=arena(-8,-8,{worm});p.pos=Vector3(-8,0,1.2)
 local cane=ent('king_cane',0,0);local staff=ent('staff_lunarplant',0,0);p.hands=staff;p.items={cane,staff}
 boss.animation='taunt2_loop1';boss.duration=32/30;w:Scan();w.state.ready.snare=now
 local begin=w.BeginRetreat;local plans=0
 function w:BeginRetreat()plans=plans+1;return begin(self)end
 for i=1,6 do boss.frame=i;step(w,1/30)end
 assert(w.feast_tail and w.lure_until and plans==1,'a necessary food-range retreat must have one persistent owner, not repeated cancel/replan')
end

-- 连续监督器：15.7米外起步，短召虫循环，异步移动/换装、延迟guard、真实抛出和命中分别结算。
local A=require('shadowself/control/actions');local oldAttack,oldSelf,oldStop=A.Attack,A.Self,A.Stop
local function continuous(feast)
 local worm=ent('stalker_minion1',-6,0);local hand=ent('shadowchanneler',8,5)
 local w,c,p,boss,shield=arena(-8,0,{worm,hand})
 p.pos=Vector3(7.7,0,0);p.sanity=.8
 local cane=ent('king_cane',0,0);local staff=ent('staff_lunarplant',0,0)
 p.items={cane,staff};p.hands=cane
 local jobs={};local moving,queued,moveat;local busy=0;local serial=0;local sent,hit;local revoked=0;local shots=0
 local function later(dt,fn)jobs[#jobs+1]={at=now+dt,fn=fn}end
 A.Stop=function()moving=nil;queued=nil;moveat=nil;if now<busy then serial=serial+1;busy=now end end
 c.h.StopPredictWalk=A.Stop
 function c:Speed()return p.hands==cane and 7.8 or 6 end
 function c:Move(q)self.point=q;queued=q;moveat=moveat or now+.12 end
 c.travel.BeginDodge=function()
  c.dodging=true
  if p.hands~=cane and not c.cane_pending then c.cane_pending=true;later(.12,function()p.hands=cane;c.cane_pending=nil end)end
 end
 A.Self=function(actor,item,action)
  oldSelf(actor,item,action)
  if action==ACTIONS.EQUIP then later(.12,function()p.hands=item end)end
  return true
 end
 A.Attack=function(actor,target,guard)
  assert(target==worm,'food cannot lose the whole summon/feast window to the visible ghost')
  if not guard() then return false end
  shots=shots+1;local this=serial+1;serial=this;busy=now+8/30+.12
  later(.03,function()if not guard() then revoked=revoked+1;serial=serial+1 else sent=sent or now end end)
  local flight=math.sqrt(p.pos:DistSq(target.pos))/15
  later(8/30+.12,function()
   if serial~=this then return end
   later(flight,function()target.tags.NOCLICK=true;target.animation='hit';hit=now end)
  end)
  return true
 end
 w:Scan();w.state.ready.snare=now+8
 local began=now;local nearest=15.7
 for frame=1,180 do
  now=began+frame/30
  for j=#jobs,1,-1 do if now>=jobs[j].at then local job=table.remove(jobs,j);job.fn()end end
  p.busy=now<busy
  if moveat and now>=moveat then moving=queued;queued=nil;moveat=nil end
  if moving and not p.busy then
   local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,c:Speed()/30)
   if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d)end
  end
  if feast then boss.animation='taunt2_loop1';boss.duration=32/30;boss.frame=frame%32
  elseif frame<10 then boss.animation='summon_pre';boss.duration=10/30;boss.frame=frame
  else boss.animation='summon_loop';boss.duration=22/30;boss.frame=(frame-10)%22 end
  w:Tick();nearest=math.min(nearest,math.sqrt(p.pos:DistSq(boss.pos)))
  if hit then break end
 end
 print('AUDIT CONTINUOUS',feast and 'feast' or 'summon','shot',shots,'send',sent and sent-began,'hit',hit and hit-began,'distance',nearest,'revoked',revoked)
 assert(sent and hit and hit-began<4.3 and revoked==0,'multi-loop approach must actually reach range, launch and kill before4.3s without cancelling its own attack')
 assert(nearest<12,'15.7m food cleanup must physically enter range instead of testing stationary commands')
end
continuous(false);continuous(true)
A.Attack,A.Self,A.Stop=oldAttack,oldSelf,oldStop
print('PASS: full decision audit: summon cooldown ownership, multi-loop food approach and phase1 recovery handoff')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
