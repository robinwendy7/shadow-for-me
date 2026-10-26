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

-- 原版SG时间轴驱动，客户端与服务端实例分开；移动/装备/攻击有延迟，不在下发时假装完成。
-- 动画时长/路径物理为模型参数，并非启动了真实游戏。
assert(read_source,'requires installed DST source')
local env=setmetatable({FRAMES=1/30,require=function()end,
 State=function(v)return v end,FrameEvent=function(f,fn)return {time=f/30,fn=fn}end,
 TimeEvent=function(t,fn)return {time=t,fn=fn}end,EventHandler=function(n,fn)return {name=n,fn=fn}end,
 CommonStates=setmetatable({},{__index=function()return function()end end}),
 CommonHandlers=setmetatable({},{__index=function()return function()return {} end end}),
 CAMERASHAKE={},ShakeAllCameras=function()end,
 StateGraph=function(_,states)local out={};for _,s in ipairs(states)do out[s.name]=s end;return out end},{__index=_G})
local source=assert(loadstring(read_source('stategraphs/SGstalker.lua')));setfenv(source,env)
local graph=source();assert(graph.snare and graph.eat_idle and graph.eat_pst)
local A=require('shadowself/control/actions');local oldAttack,oldSelf,oldStop=A.Attack,A.Self,A.Stop
local oldGround=A.Ground;local records={}
for _,release in ipairs({2.5,5,9}) do
 local ghost=ent('shadowchanneler',11.9,0)
 local worms={};for n=1,14 do worms[#worms+1]=ent(n%2==0 and 'stalker_minion1' or 'stalker_minion2',1,(n%3)*.15) end
 local entities={ent('stalker_atrium',0,0),ghost};for _,e in ipairs(worms)do entities[#entities+1]=e end
 local w,c,p,boss=fixture(entities,2.5,0);c.speed=7.8;p.sanity=.8
 local cane,amulet,armour=ent('king_cane',0,0),ent('purpleamulet',0,0),ent('armor_sanity',0,0)
 p.items={cane,amulet,armour};p.hands=cane;p.body=armour
 local shield=true;boss._hasshield={value=function()return shield end}
 local begin=now;local jobs={};local moving,queued,moveat;local busy=0;local caught,cleared=0,0
 local points={};local server={};local current,entered,done;local snare_at;local attackserial=0
 local lengths={taunt2_loop1=1.067,taunt2_loop2=.9,taunt2_loop3=.9,taunt2_pst=.5,attack1=1.4}
 local function noop()end
 local function pending(dt,fn)jobs[#jobs+1]={at=now+dt,fn=fn}end
 local function moveframe(goal,amount)
  local d=math.sqrt(p.pos:DistSq(goal));if d>.001 then local n=math.min(amount,d);p.pos=Vector3(p.pos.x+(goal.x-p.pos.x)*n/d,0,p.pos.z+(goal.z-p.pos.z)*n/d)end
 end
 function c:Move(q) queued=q;moveat=moveat or now+.2 end
 c.h.StopPredictWalk=function()moving=nil;queued=nil;moveat=nil end
 A.Stop=function()moving=nil;queued=nil;moveat=nil;attackserial=attackserial+1 end
 A.Self=function(_,item,action)
  busy=math.max(busy,now+.12)
  pending(.12,function()
   if action==ACTIONS.UNEQUIP then p.body=nil;p.sanity=.8
   elseif item==amulet then p.body=amulet;p.sanity=0
   elseif item==armour then p.body=armour;p.sanity=.8
   else p.hands=item end
  end);return true
 end
 A.Attack=function(_,target,guard)
  if guard and not guard() then return false end
  attackserial=attackserial+1;local token=attackserial
  busy=now+.12+8/30;moving=nil;queued=nil;moveat=nil
  pending(.12+8/30,function()
   -- guard是发包前条件，不是服务器每帧重新判断的命中条件；已提交动作只会被真实停止/移动打断。
   if token==attackserial and target:IsValid() and not target:HasTag('NOCLICK')
    and p.pos:DistSq(target.pos)<=2.5^2 then
    target.tags.NOCLICK=true;target.animation='hit';if target==ghost then shield=false;cleared=cleared+1 end
   end
  end);return true
 end
 A.Ground=function()return false end
 server.components={locomotor={StopMoving=noop},epicscare={Scare=noop},
  health={IsHurt=function()return now-begin<release end},combat={DoAreaAttack=noop}}
 server.SoundEmitter={PlaySound=noop};server.BattleChatter=noop
 server.AnimState={PlayAnimation=function(_,name)boss.animation=name;boss.frame=0;boss.duration=lengths[name] or 1 end,Show=noop,Hide=noop,AnimDone=function()return true end}
 server.sg={mem={},statemem={}}
 function server.sg:HasStateTag(tag)return false end
 function server.sg:RemoveStateTag()end
 function server.sg:GoToState(name,data)
  if name=='idle' then current=nil;boss.animation='idle';entered=now;return end
  current=assert(graph[name],name);entered=now;done={};self.statemem={}
  current.onenter(server,data)
 end
 function server:FindMinions(proximity)
  local out={};for _,e in ipairs(worms)do if not e.tags.NOCLICK and e.pos:DistSq(boss.pos)<(1.8+(proximity or .5))^2 then out[#out+1]=e end end;return out
 end
 function server:EatMinions()
  local n=0;for _,e in ipairs(self:FindMinions())do if n<3 then e.tags.NOCLICK=true;e.animation='eaten';n=n+1 end end;return n
 end
 function server:StartAbility()end
 function server:SpawnSnares()
  if p.pos:DistSq(boss.pos)<=15^2 then
   caught=caught+1
   records[#records+1]=string.format('CAGE,%.2f,%.3f,%s',now-begin,math.sqrt(p.pos:DistSq(boss.pos)),w.mode or '')
  end
  snare_at=now
 end
 -- 首次未知血量的吞食，中途回满时间有三个不同取值。
 server.sg:GoToState('eat_idle',{idle=0,resist=3})
 w:Scan();w.state.ready.snare=now+.8
 for frame=1,600 do
  now=now+1/30
  for i=#jobs,1,-1 do if now>=jobs[i].at then local job=table.remove(jobs,i);job.fn()end end
  p.busy=now<busy
  if moveat and now>=moveat then moving=queued;queued=nil;moveat=nil;if now<busy then attackserial=attackserial+1;busy=now end end
  if moving and not p.busy then moveframe(moving,5.1/30) end
  if current then
   local state=current;local elapsed=now-entered;boss.frame=math.floor(elapsed*30+.001)
   for i,event in ipairs(state.timeline or {})do
    if not done[i] and elapsed>=event.time then done[i]=true;event.fn(server)end
   end
   if current==state and elapsed>=boss.duration then
    for _,event in ipairs(state.events or {})do if event.name=='animover' then event.fn(server)end end
   end
  elseif not snare_at then server.sg:GoToState('snare',{p}) end
  w:Tick();points[#points+1]=string.format('%.2f,%.3f,%.3f,%s,%s',now-begin,p.pos.x,p.pos.z,boss.animation,w.mode or '')
  if snare_at and now>snare_at+.3 then break end
 end
 assert(snare_at,'source feast must really release into snare')
 if caught>0 then for i=math.max(1,#points-32),#points do print(points[i])end end
 assert(caught==0,'delayed source-timeline recovery trapped player at release '..release)
 if release>=5 then assert(cleared>=1,'long source feast must permit acknowledged ghost cleanup, not stand through the whole feast') end
 records[#records+1]=string.format('release=%.1f caught=%d ghosts_killed=%d final_radius=%.3f',release,caught,cleared,math.sqrt(p.pos:DistSq(boss.pos)))
 records[#records+1]=table.concat(points,'\n')
 if release==9 then
  -- 接续外围带虫：Boss实际追击，虫子按两种walk起停节奏移动，攻击仍走原SG第32帧。
  w:Stop();current=nil;moving=nil;queued=nil;moveat=nil;jobs={};busy=0
  boss.pos=Vector3(-8,0,-8);p.pos=Vector3(-10.5,0,-10.5);p.body=armour;p.sanity=.8
  for _,e in ipairs(worms)do e.tags.NOCLICK=true end
  local gate=ent('atrium_gate',0,0);gate.radius=2.5;gate.tags.structure=true;entities[#entities+1]=gate
  local hands={};for _,v in ipairs({{-10,-6},{-10,6},{0,10},{10,6},{10,-6},{0,-10}})do
   local e=ent('shadowchanneler',v[1],v[2]);entities[#entities+1]=e;hands[#hands+1]=e
  end
  for i=1,8 do local e=ent(i%2==0 and 'stalker_minion1' or 'stalker_minion2',(i%3)-1,math.floor(i/3)-1);worms[#worms+1]=e;entities[#entities+1]=e end
  shield=true;w:Scan();w.state.phase=2
  w.cycle={stage='patrol',round='lap',round_since=now,center=Vector3(0,0,0),seen_summon=true,had_hands=true,
   corners=Cycle.SidePoints(w,Vector3(0,0,0)),index=3}
  local nextsnare,nextmelee=now+5,now;w.state.ready.snare=nextsnare
  local meleehits,feeds=0,0;local walkstart=now;local tagsbusy=false
  server.components.combat.target=p
  server.components.combat.StartAttack=function()nextmelee=now+3 end
  server.components.combat.DoAttack=function()if p.pos:DistSq(boss.pos)<4.3^2 then meleehits=meleehits+1 end end
  local enterstate=server.sg.GoToState
  function server.sg:GoToState(name,data)tagsbusy=name~='idle';return enterstate(self,name,data)end
  server.sg.RemoveStateTag=function(_,tag)if tag=='busy' then tagsbusy=false end end
    server.StartAbility=function(_,name)if name=='snare' then nextsnare=now+10 end end
  -- 原版walk_loop动画长度未知；攻击/骨牢时间轴使用真实SG，走路作为持续追击处理。
  lengths.attack=2.3
  for frame=1,2700 do
   now=now+1/30
   for i=#jobs,1,-1 do if now>=jobs[i].at then local job=table.remove(jobs,i);job.fn()end end
   p.busy=now<busy
   if moveat and now>=moveat then moving=queued;queued=nil;moveat=nil;if now<busy then attackserial=attackserial+1;busy=now end end
   if moving and not p.busy then
    local before=p.pos;moveframe(moving,5.1/30)
    for _,body in ipairs({boss,gate})do local r=(body==boss and 1.6 or 3)
     if p.pos:DistSq(body.pos)<math.min(r*r,before:DistSq(body.pos)-.001) then p.pos=before end
    end
   end
   for _,bug in ipairs(worms)do if not bug.tags.NOCLICK then
    -- 原版45±5秒寿命；此段没有feasting，不能把虫子当成永不自爆的追击单位。
    if now-walkstart>=50 then bug.tags.NOCLICK=true;bug.animation='hit' end
    local f=frame%30;local speed=bug.prefab=='stalker_minion1' and (f<6 and 3 or 0) or (f>=16 and 1.5 or 0)
    local d=math.sqrt(bug.pos:DistSq(boss.pos));local n=math.min(speed/30,d)
    if d>.001 then bug.pos=Vector3(bug.pos.x+(boss.pos.x-bug.pos.x)*n/d,0,bug.pos.z+(boss.pos.z-bug.pos.z)*n/d)end
    if not bug.tags.NOCLICK and bug.pos:DistSq(boss.pos)<1.8^2 then bug.tags.NOCLICK=true;feeds=feeds+1 end
   end end
   if current then
    local state=current;local elapsed=now-entered;boss.frame=math.floor(elapsed*30+.001)
    for i,event in ipairs(state.timeline or {})do if not done[i] and elapsed>=event.time then done[i]=true;event.fn(server)end end
    if current==state and elapsed>=boss.duration then for _,event in ipairs(state.events or {})do if event.name=='animover'then event.fn(server)end end end
   end
   if not current or not tagsbusy then
    local d=math.sqrt(p.pos:DistSq(boss.pos))
    if now>=nextsnare and d<=12 then server.sg:GoToState('snare',{p})
    elseif now>=nextmelee and d<=2.7 then server.sg:GoToState('attack')
    else
     current=nil;boss.animation='walk_loop';boss.frame=frame%30
     if d>2.5 then local n=math.min(4.2/30,d-2.5);boss.pos=Vector3(boss.pos.x+(p.pos.x-boss.pos.x)*n/d,0,boss.pos.z+(p.pos.z-boss.pos.z)*n/d)end
    end
   end
   shield=false;for _,e in ipairs(hands)do if not e.tags.NOCLICK then shield=true;break end end
   local killed=0;for _,e in ipairs(hands)do if e.tags.NOCLICK then killed=killed+1 end end
   w:Tick()
   records[#records+1]=string.format('lap,%.2f,%.3f,%.3f,%.3f,%.3f,%d,%d,%s',now-walkstart,p.pos.x,p.pos.z,boss.pos.x,boss.pos.z,killed,feeds,w.mode or '')
   if killed==6 then break end
  end
  local killed=0;for _,e in ipairs(hands)do if e.tags.NOCLICK then killed=killed+1 end end
  print('LAP MODEL:',killed,'ghosts killed;',feeds,'worms reached boss;',meleehits,'melee hits;',caught,'cages')
  if write_weaver_sim then write_weaver_sim(table.concat(records,'\n')) end
  assert(killed==6,'continuous perimeter chase must finish all six ghosts')
  assert(feeds==0 and meleehits==0 and caught==0,'continuous simplified model must preserve separation and escape actual source hit frames')
 end
end
A.Attack,A.Self,A.Stop,A.Ground=oldAttack,oldSelf,oldStop,oldGround
if write_weaver_sim then write_weaver_sim(table.concat(records,'\n')) end
print('PASS: original SG feast/snare timelines with delayed movement/equipment/hit acknowledgements and active cleanup at the safe band; simplified physical model only')
for k,v in pairs(globals)do _G[k]=v end
for _,k in ipairs({'Class','GetTime','Vector3','TheSim','TheWorld','TUNING','EQUIPSLOTS','ACTIONS'})do if globals[k]==nil then _G[k]=nil end end
for _,n in ipairs({'actions','incoming','weaver/observe','weaver/route','weaver/debug','weaver/sanity','weaver/cycle','weaver/round','weaver/ranged','weaver/phase1','weaver/controller'})do local k='shadowself/control/'..n;package.loaded[k]=saved[k] end


