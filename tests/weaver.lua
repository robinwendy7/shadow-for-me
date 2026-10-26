package.path="./scripts/?.lua;"..package.path
local globals={};for _,k in ipairs({"Class","GetTime","Vector3","TheSim","TheWorld","TUNING","EQUIPSLOTS","ACTIONS"}) do globals[k]=_G[k] end
local saved={};for _,n in ipairs({"actions","incoming","weaver/observe","weaver/round","weaver/ranged","weaver/route","weaver/debug","weaver/sanity","weaver/cycle","weaver/phase1","weaver/controller"}) do
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
package.loaded['shadowself/control/weaver/cycle']={Interrupt=function()end,Observe=function()end,Tick=function()return false end,BlockAttack=function()return false end,LightAllowed=function()return true end,BaitAllowed=function()return true end}
package.loaded['shadowself/control/weaver/phase1']={Observe=function()end,Tick=function()return false end,BlockAttack=function()return false end,KeepMask=function()return false end}
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
-- 无关战斗零干预；实际普通怪保留原走A。
local w,c,p,boss=fixture({ent('deerclops',0,0)});assert(not w:Tick() and c.paused==0)
-- 未知/就绪CD不能自己把输出抢走：先接回原走A，等真实普攻起手才诱牢。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)});assert(w:Tick() and c.owns and not w.lure_until)
local finished=require('shadowself/control/combat').Finished
assert(not finished({coordinator=c,finished=true,clear_since=now-10}),'mechanism hold is not arena combat completion')
p.pos=Vector3(11.3,0,0);step(w);assert(c.owns and not w.lure_until)
boss.animation='attack1';boss.frame=0;step(w);assert(c.point.x>11.3 and not c.owns)
p.pos=Vector3(15.8,0,0);boss.frame=31;step(w,1.12);assert(w.state.snare_result==false)
boss.animation='idle';p.pos=Vector3(2,0,0);step(w);assert(c.owns and w.focus==boss,'snare resolved -> return to output')
-- 同一次普通攻击结算前不回身；第二次攻击重新判断，不沿用第一次安全状态。
boss.animation='attack';boss.frame=20;step(w);assert(not c.owns and c.point.x>p.pos.x)
boss.frame=32;step(w);assert(not c.owns)
boss.frame=38;step(w);p.pos=Vector3(2,0,0);step(w);assert(c.owns)
boss.frame=0;step(w);boss.frame=21;step(w);assert(not c.owns)
-- 清鬼手期间同样躲本体，不会只看当前小目标。
local hand=ent('shadowchanneler',2.5,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),hand},2.5,0)
local shield=true;boss._hasshield={value=function()return shield end};boss.animation='taunt3_loop'
w:Tick();assert(w.focus==hand and p.hand_attacks==1 and not c.owns and w:AttackBlocked(boss))
boss.animation='attack';boss.frame=20;step(w);assert(not c.owns and w:AttackBlocked(hand))
boss.animation='idle';w.state.ready.snare=now+8;step(w);assert(not c.owns and w.focus==hand)
hand.tags.NOCLICK=true;hand.animation='disappear';all={boss,hand};shield=false;p.pos=Vector3(2,0,0);step(w)
assert(c.owns and w.focus==boss and not w:AttackBlocked(boss),'confirmed shield removed -> boss output')
-- 鬼手出现过程不可攻击；不能因当前没有可打鬼手就误打本体。
w,c,p,boss=fixture({ent('stalker_atrium',0,0),ent('shadowchanneler',2.5,0)},2.5,0)
all[2].tags.notarget=true;boss.animation='taunt3_pre';boss._hasshield={value=function()return true end}
w:Tick();assert(not c.owns and w:AttackBlocked(boss))
-- 真正受控时零装备/移动请求；依赖实际解除而不是固定3.5s。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)});p.animation='mindcontrol_loop';p.enabled=false
local e0,m0=equips,c.moves or 0;w:Tick();step(w,5);assert(equips==e0 and (c.moves or 0)==m0 and not c.owns)
p.enabled=true;p.animation='idle';p.pos=Vector3(2,0,0);boss.animation='summon_loop';w.state.ready.snare=now+6;step(w);assert(c.owns)
-- 普通击杀每只刷新冷却；吞食不刷新；原因不明的消失不能伪造20秒CD。
local s=O.New();local m=ent('stalker_minion1',0,0)
O.Minions(s,{m},now);m.animation='eaten';local ev=O.Minions(s,{m},now+.1);assert(ev[1].reason=='consumed' and not s.ready.minions)
s=O.New();m.animation='idle';O.Minions(s,{m},now);m.animation='hit';O.Minions(s,{m},now+1);assert(s.ready.minions==now+21)
local m2=ent('stalker_minion2',0,0);O.Minions(s,{m2},now+2);m2.animation='hit';O.Minions(s,{m2},now+3);assert(s.ready.minions==now+23)
s=O.New();m.animation='idle';O.Minions(s,{m},now);O.Minions(s,{},now+1);assert(s.minions_uncertain and not s.ready.minions)
-- 原地循环帧回零不是新的召唤；控制循环才持续刷新自己的CD估计。
s=O.New();boss.animation='summon_loop';boss.frame=20;O.Update(s,boss,now);boss.frame=0;O.Update(s,boss,now+1);assert(not s.ready.minions)
boss.animation='control_loop';O.Update(s,boss,now+2);O.Update(s,boss,now+3);assert(s.ready.mindcontrol==now+18)
-- 冒险24码版本不能沿用原版15码；真实参数可独立覆盖。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)});boss.tags.adventure=true;w:Tick();local capture,resolve=w:Ranges();assert(capture==24 and resolve==24)
-- 骨刺使用可见实体，不受_combat过滤；不把老骨牢空动画继续封路。
local spike=ent('fossilspike2',3,0,'appear');spike.duration=.5;local cage=ent('fossilspike',4,0,'empty')
w,c,p,boss=fixture({ent('stalker_atrium',0,0),spike,cage});w:Scan();w.zones=R.Zones(w)
assert(#w.zones==1 and R.Risk(w,p.pos)>0)
local q=R.Choose(w,Vector3(5,0,3),nil,true);assert(q and R.Risk(w,q)<R.Risk(w,p.pos))
-- 路线不能穿Boss身体，也不能为了清鬼手踩侧面冲撞通道。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},3,0);w:Scan();w.zones={}
assert(not R.Path(w,Vector3(-3,0,0),nil,true))
local rook=ent('rook',0,0);rook.lane={x=4};all={boss,rook};step(w,.31);w.zones=R.Zones(w)
assert(not R.Path(w,Vector3(7,0,0),nil,false))
-- 已移除主动留虫诱吞食；基础清手/清路不保留回血虫子。
hand=ent('shadowchanneler',10,4);m=ent('stalker_minion1',1,0);m2=ent('stalker_minion2',2,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),hand,m,m2},3,0)
boss._hasshield={value=function()return true end};w.state.ready.snare=now+9;w:Tick()
assert(not w.reserve and not w.mode:find('留虫',1,true),'intentional feeding has been removed')
boss.animation='taunt2_loop1';step(w);assert(w.focus==hand or w.focus==m2)
step(w);assert(w.reserve==nil,'never reserve a worm for healing')
-- 魔杖装备先确认再BLINK，发出后必须等真实位移，避免装备互搏。
local marker=ent('blinkfocus_marker',3,0)
w,c,p,boss=fixture(prison(ent('stalker_atrium',0,0),marker,3,0),3,0)
local staff=ent('orangestaff',0,0);p.items={staff};local n=casts;w:Tick();assert(p.last_equip==staff and casts==n)
p.hands=staff;step(w);assert(casts==n+1 and w.blink_sent)
step(w);assert(casts==n+1 and c.gear.action_hold)
p.pos=p.castpoint;step(w);assert(not w.blink_sent and not c.gear.action_hold)
assert(not p.castguard(),'late prediction callback revoked after actual arrival')
-- 第一次装备未获确认后，下一次等待期限包含退避期，不能在真正重试前反复超时。
w,c,p,boss=fixture(prison(ent('stalker_atrium',0,0),ent('blinkfocus_marker',3,0),3,0),3,0)
staff=ent('orangestaff',0,0);p.items={staff};w:Tick();local requests=equips
step(w,1.6);step(w,.1);step(w,2.1);assert(equips>requests,'equip retry cannot be starved by its own cooldown')
-- 装备护符/恢复护甲时跨帧等确认，不遗留action_hold使后续武器永远无法装备。
w,c,p,boss=fixture({ent('stalker_atrium',0,0),ent('shadowchanneler',3,0)},3,0)
local amulet=ent('purpleamulet',0,0);local armour=ent('armorruins',0,0);p.items={amulet,armour};p.sanity=.8;p.body=armour
boss._hasshield={value=function()return true end};w:Tick();assert(p.last_equip==amulet and c.gear.action_hold)
step(w,.1);assert(c.gear.action_hold and not c.owns)
p.body=amulet;step(w);assert(not c.gear.action_hold and w.focus==all[2])
w.state.ready.snare=now+8;boss._hasshield={value=function()return false end};all={boss};step(w);assert(w.support and w.support.item==armour and c.gear.action_hold)
p.body=armour;p.pos=Vector3(2,0,0);step(w);assert(not c.gear.action_hold and c.owns)
w:Stop();assert(not w:Active() and not c.gear.action_hold)
-- Boss血量使用有效同步的绝对值，不能把改过上限的血量百分比套成原版阶段。
s=O.New();boss.animation='idle';boss.replica.health={Max=function()return 32000 end,GetCurrent=function()return 15000 end,GetPercent=function()return 15000/32000 end}
O.Update(s,boss,now);assert(s.phase==1 and s.health==15000)
boss.replica.health.GetCurrent=function()return 9999 end;O.Update(s,boss,now);assert(s.phase==2)
s=O.New();boss.replica.health={Max=function()return 100 end,GetCurrent=function()return 100 end,GetPercent=function()return 1 end}
O.Update(s,boss,now);assert(not s.health,'remote default replica is not real Boss health')
-- 实测93秒骨刺之后骨牢有至少5秒共享冷却；未知CD不能继续阻止所有输出。
s=O.New();boss.animation='spike';boss.frame=0;O.Update(s,boss,93)
assert(not s.ready.snare,'shared delay happens at SpawnSpikes frame 6, not windup frame 0')
boss.frame=6;O.Update(s,boss,93.2)
assert(s.ready.snare>=98 and s.ready.mindcontrol>=100.5)
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},2,0)
boss.animation='spike';w:Tick();boss.animation='idle';step(w,2.1)
assert(c.owns and w.focus==boss,'spike recovery opens real output instead of endless unknown-CD bait')
-- 真实骨柱动画fossil_pst必须识别；标记仍在但柱子消失时必须立即恢复行动。
marker=ent('blinkfocus_marker',3,0);all=prison(ent('stalker_atrium',0,0),marker,3,0)
w,c,p,boss=fixture(all,3,0);w:Scan();w.state.ready.snare=now+9;w:Tick()
assert(#w.cages==6 and w.holding and not c.owns)
local oldthreat=w.Threat;local watched=0
w.Threat=function(self)watched=watched+1;return oldthreat(self)end
boss.animation='attack';boss.frame=0;step(w);assert(watched>0,'cage fallback still evaluates the actual boss attack')
boss.animation='idle';p.pos=Vector3(2,0,0)
for i=3,#all do all[i].tags.NOCLICK=true end
step(w);assert(c.owns and #w.cages==0,'lingering marker: mode='..tostring(w.mode)..' owns='..tostring(c.owns)..' cages='..#w.cages..' hp='..tostring(w.state.health)..' ready='..tostring(w.state.ready.snare)..' now='..now)
-- 橙宝石国王手杖直接使用在手道具，其他宝石/冷却中的国王手杖不能充当瞬移道具。
marker=ent('blinkfocus_marker',3,0)
w,c,p,boss=fixture(prison(ent('stalker_atrium',0,0),marker,3,0),3,0)
local king=ent('king_cane',0,0);local gem='orangegem';king._gem={value=function()return gem end}
p.items={king};p.hands=king;local before_cast=casts;local before_equip=equips
w:Tick();assert(casts==before_cast+1 and equips==before_equip and w.blinkstaff==king)
gem='bluegem';assert(not p.castguard(),'enchantment changed -> revoke delayed teleport')
w:CancelSupport();w.blink_sent=nil
assert(not w:BlinkItem());gem='orangegem';king.tags.nomagiccast=true;assert(not w:BlinkItem())
king.tags.nomagiccast=nil;assert(w:BlinkItem()==king)
local lazy=ent('orangestaff',0,0);p.items={king,lazy};king.tags.nomagiccast=true;assert(w:BlinkItem()==lazy)
-- 用户要求：骨牢前摇只走路，必须真正出现命中骨柱后才自动瞬移。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},2,0)
king=ent('king_cane',0,0);king._gem={value=function()return 'orangegem' end};p.items={king};p.hands=king
before_cast=casts;w:Tick();assert(casts==before_cast and not w.blink_sent)
boss.frame=24;step(w);assert(casts==before_cast and not w.blink_sent,'no speculative pre-hit teleport')
marker=ent('blinkfocus_marker',2,0);all=prison(boss,marker,2,0);boss.frame=27;step(w,.31)
assert(casts==before_cast+1 and w.blink_sent,'confirmed cage hit requests one teleport')
-- 地图边缘：正常诱招提前向开阔地转向；被困后不能再朝地图外选唯一落点。
local map_saved=TheWorld.Map
TheWorld.Map={IsPassableAtPoint=function(_,x,y,z)return x>-15 and x<15 and z>-12 and z<12 end,
 IsOceanAtPoint=function(_,x,y,z)return x<=-15 or x>=15 or z<=-12 or z>=12 end,
 IsPointNearHole=function()return false end,IsGroundTargetBlocked=function()return false end}
local gate=ent('atrium_gate',0,0);gate.tags.structure=true;gate.radius=2.5
w,c,p,boss=fixture({ent('stalker_atrium',0,0),gate},14.2,0)
w:Tick();assert(c.point and c.point.x<14.2 and R.Clearance(c.point)>R.Clearance(p.pos),'edge recovery chooses open interior before waiting for a snare')
local wanted=Vector3(22,0,0);local route=R.Choose(w,wanted,nil,true)
assert(route and route.x<14.2 and R.Passable(route),'invalid outward goal cannot keep walking into the coast')
marker=ent('blinkfocus_marker',13.5,0)
w,c,p,boss=fixture(prison(ent('stalker_atrium',8.5,0),marker,13.5,0),13.5,0)
king=ent('king_cane',0,0);king._gem={value=function()return 'orangegem' end};p.items={king};p.hands=king
before_cast=casts;w:Tick()
assert(casts==before_cast+1 and p.castpoint and R.Passable(p.castpoint) and p.castpoint.x<13.5,'search other legal directions when straight-away landing is outside the map')
assert(p.castpoint:DistSq(boss.pos)>=4.8^2,'do not teleport back into the boss attack circle')
w,c,p,boss=fixture(prison(ent('stalker_atrium',8.5,0),ent('blinkfocus_marker',13.5,0),13.5,0),13.5,0)
p.items={king};p.hands=king;p.no_blink_action=true;before_cast=casts;w:Tick()
assert(casts==before_cast and not w.blink_sent and not c.gear.action_hold,'native picker refusal is not a submitted or confirmed teleport')
TheWorld.Map=map_saved
-- 真实原生预测RPC + 原版服务器OnRemotePredictWalking：停下后下一次必须重启预测计时。
if read_source then
 w,c,p,boss=fixture({ent('stalker_atrium',0,0)},3,0)
 local pc=p.components.playercontroller
 function pc:CanLocomote()return false end
 function pc:GetPlatformRelativePosition(x,z)return nil,x,z end
 function pc:EncodeControlMods()return 0 end
 local H={};local rpc={PredictWalking=101,StopWalking=102,LeftClick=103};local packets={}
 local server={ismastersim=true,remote_vector={},restarts=0,cancels=0,IsEnabled=function()return true end,GetRemotePredictPosition=function()end}
 server.locomotor={RestartPredictMoveTimer=function()server.restarts=server.restarts+1 end,
  CancelPredictMoveTimer=function()server.cancels=server.cancels+1 end}
 local serverenv=setmetatable({PlayerController={}},{__index=_G})
 local source=read_source('components/playercontroller.lua')
 local a=assert(source:find('function PlayerController:OnRemotePredictWalking(',1,true))
 local z=assert(source:find('\nfunction PlayerController:',a+15,true))
 local fn=assert(loadstring(source:sub(a,z-1)));setfenv(fn,serverenv);fn()
 server.OnRemotePredictWalking=serverenv.PlayerController.OnRemotePredictWalking
 local nativeenv=setmetatable({HitAndRun=H,ThePlayer=p,RPC=rpc,ACTIONS={WALKTO={code=1}},
  SendRPCToServer=function(id,x,z,direct,start,platform,relative,override,stop)
   packets[#packets+1]={id=id,start=start,stop=stop}
   if id==101 then server:OnRemotePredictWalking(x,z,direct,start,platform,override,stop) end
  end},{__index=_G})
 local file=assert(io.open('scripts/shadowself/native/engine/HitAndRun.lua','r'));source=file:read('*a');file:close()
 a=assert(source:find('do --走向和攻击函数',1,true));z=assert(source:find('\ndo --功能性函数',a,true))
 fn=assert(loadstring(source:sub(a,z-1)));setfenv(fn,nativeenv);fn()
 fn=assert(loadfile('scripts/shadowself/native/utils/POS_util.lua'));setfenv(fn,nativeenv);local pos=fn()
 c.h=H;H.ent=boss
 function c:Move(q)self.point=q;pos:GoToPoint(q.x,q.z)end
 w:Move(Vector3(8,0,0),'实测起跑',nil,true)
 assert(server.restarts==1 and H.shadowself_predicting)
 w:Hold('实测等待骨牢',true)
 assert(not H.shadowself_predicting and server.cancels==1)
 now=now+1
 w:Move(Vector3(8,0,0),'实测重新撤离',nil,true)
 assert(server.restarts==2 and H.shadowself_predicting,'restart must carry isstart=true, not reuse an expired session')
end
-- 连续走到识别范围内沿，不把每次重新采样变成脚前碎步。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0)
w:Scan();w.state.ready.snare=now
local before_stops=stops
for i=1,10 do
 boss.frame=math.min(63,(i-1)*3)
 step(w,.1)
 assert(c.point and math.sqrt(c.point:DistSq(p.pos))>1,'retreat has a continuous stride')
 local q=c.point;local d=math.sqrt(q:DistSq(p.pos));local move=math.min(.75,d)
 p.pos=Vector3(p.pos.x+(q.x-p.pos.x)*move/d,0,p.pos.z+(q.z-p.pos.z)*move/d)
 if i>21 then boss.pos=Vector3(boss.pos.x+.3,0,0) end
end
assert(stops==before_stops,'do not stutter on the approach to the bait band')
p.pos=w.bait_point;boss.frame=40;step(w)
assert(w.holding and p.pos:DistSq(boss.pos)<12^2,'wait inside target recognition range')
local band_stops=stops
boss.animation='attack1';boss.frame=0;step(w)
assert(c.point and c.point.x>p.pos.x+1 and stops==band_stops,'actual snare windup immediately leaves the band')
-- 诱牢未触发则回身只骗新普攻，不能无限外推，也不能恢复补刀。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0)
w:Scan();w.state.ready.snare=now
w:Tick();assert(w.lure_until)
boss.animation='idle';step(w,5.2)
assert(w.lure_until and not w.rebait,'idle timeout cannot bypass skill observation')
boss.animation='walk_loop';step(w,.1)
for i=1,45 do boss.pos=Vector3(boss.pos.x-.05,0,0);step(w,1/30) end
-- This boss is walking away: displacement alone must not prove pursuit.
assert(w.lure_until and not w.rebait)
for i=1,100 do boss.pos=Vector3(boss.pos.x+.05,0,0);step(w,1/30) end
assert(w.rebait and not w.lure_until and not c.owns,'sustained real pursuit returns for bait without attacking')
boss.animation='spike';boss.frame=0;step(w)
assert(not w.lure_until,'an actual shared-cooldown skill still takes over the lure')
-- 原走A退至最大攻击距离时继续拥有线程；不能一换武器就被外层追击抢走。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},2.4,0)
w:Scan();w.state.ready.snare=now+10;w:Tick();assert(c.owns)
local before_pauses=c.paused;local before_moves=c.moves or 0
p.pos=Vector3(2.65,0,0);step(w)
assert(c.owns and c.paused==before_pauses and (c.moves or 0)==before_moves,'native max-range retreat must retain attack ownership')
p.pos=Vector3(3.4,0,0);step(w);assert(c.owns,'native owns the final approach instead of external distance stealing it')
-- 复现日志中的2.85码停顿：追近还剩最后一段时先交接原走A，等实际武器确认后继续。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},4.9,0)
w:Scan();w.state.ready.snare=now+8
local sword=ent('sword_lunarplant',0,0);local cane=ent('cane',0,0)
p.weapon=sword;p.hands=cane;p.items={sword,cane}
w:Tick();assert(c.point and not c.owns)
p.pos=Vector3(3.6,0,0);step(w);assert(not c.owns and c.swaps and not w.moving)
p.hands=sword;step(w);assert(c.owns,'weapon acknowledgement resumes native chase before the old 2.85-code dead band')
local resumed=c.resumed;p.pos=Vector3(2.85,0,0);step(w)
assert(c.owns and c.resumed==resumed,'return attack remains owned even if snare CD reaches zero')
w.state.ready.snare=now;step(w);assert(c.owns and not w.lure_until,'ready timer alone must never stop an attack')
boss.animation='attack';boss.frame=0;step(w)
assert(not c.owns and w.lure_until and c.point.x>p.pos.x,'only the actual melee windup begins the long lure')
-- 冷却还很长时照常短撤普攻后回身输出，不为每次普攻都长跑。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0)
w:Scan();w.state.ready.snare=now+8;w:Tick()
assert(not w.lure_until and c.point.x<6)
boss.frame=38;p.pos=Vector3(3.5,0,0);step(w)
assert(c.owns,'ordinary recovery returns directly to native attacks')
-- 未知初始CD不能当作已就绪；更不能把“接管”误当“进入交战”重新数5秒。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0)
w:Tick();assert(not w.lure_until and not w.state.ready.snare)
-- 日志回放：第三次骗招时CD尚未归零，但下一次技能选择前会就绪，必须直接拉远，不能再反打。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0)
w:Scan();w.state.ready.snare=now+8.5
for cycle=1,3 do
 boss.animation='attack';boss.frame=0;w:Tick()
 if cycle<3 then
  assert(not w.lure_until,'early safe melee still allows output')
  boss.frame=38;p.pos=Vector3(3.5,0,0);step(w,1.27);assert(c.owns)
  boss.animation='idle';step(w,1.7)
  boss.animation='attack';boss.frame=0;p.pos=Vector3(2.7,0,0);now=now+.13
 else
  assert(w.lure_until and O.ReadyIn(w.state,'snare',now)>0,'last safe melee arms before zero')
  local resumes=c.resumed
  boss.frame=38;step(w,1.27)
  assert(not c.owns and c.resumed==resumes and w:AttackBlocked(boss),'third recovery must not equip/resume to add another hit')
  p.pos=w.bait_point;boss.frame=55;step(w,.57)
  assert(not c.owns and c.resumed==resumes and w.holding,'wait in the outer band, no return attack')
  boss.animation='attack1';boss.frame=0;step(w,.2)
  assert(c.point and c.point:DistSq(p.pos)>1 and not c.owns,'snare windup immediately extends past resolution radius')
 end
end
-- 中庭栅栏没有wall/structure标签，寻路器返回可走也必须按人物宽度禁入。
local fence=ent('atrium_fence',4.25,0,'idle1_active');fence.radius=.1
w,c,p,boss=fixture({ent('stalker_atrium',0,0),fence},2,0);w:Scan()
assert(#w.fences==1 and not fence:HasTag('wall') and not fence:HasTag('structure'),'explicit prefab scan includes untagged atrium fences')
assert(not R.Path(w,Vector3(6,0,0),nil,true),'an entire clear ray cannot cross a fence despite a permissive pathfinder')
assert(not R.Path(w,Vector3(4.25,0,.8),nil,true),'do not select the fence lip or narrow gap as a destination')
assert(R.Path(w,Vector3(2,0,4),nil,true),'open arena paths remain usable')
local before_clear=R.Clearance(p.pos,w)
w.fences={};assert(before_clear<R.Clearance(p.pos,w),'clearance sees nearby fence congestion rather than reporting open ground')
w.fences={fence};p.pos=Vector3(4.25,0,.7)
assert(R.Path(w,Vector3(4.25,0,3),nil,true),'a player already touching the fence can leave without being trapped by the new exclusion')
assert(not R.FencePath(w,p.pos,Vector3(4.25,0,-3)),'leaving must not cross through the fence first')
-- 窄缝不可钻，真正宽敞的通道仍允许；清掉实体后原路线恢复。
local fence2=ent('atrium_fence',4.25,.8,'idle2_active');fence.pos=Vector3(4.25,0,-.8)
w.fences={fence,fence2};p.pos=Vector3(2,0,0)
assert(not R.Path(w,Vector3(6,0,0),nil,true),'reject a gap too close to both fence bodies')
fence.pos=Vector3(4.25,0,-2.5);fence2.pos=Vector3(4.25,0,2.5)
assert(R.Path(w,Vector3(6,0,0),nil,true),'do not blanket-ban an entire map side when a wide corridor exists')
fence.removed=true;fence2.removed=true;assert(R.FenceClear(w,Vector3(4.25,0,0)))
-- 瞬移可以跨障碍，但落点不能落进栅栏簇；骨牢起手也不能把栅栏后当直线出口。
fence=ent('atrium_fence',6,0,'idle1_active');fence.radius=.1
w,c,p,boss=fixture({ent('stalker_atrium',0,0),fence},0,5);w:Scan()
king=ent('king_cane',0,0);king._gem={value=function()return 'orangegem' end};p.hands=king;p.items={king}
local fence_landing=R.Landing(w,Vector3(6,0,0),king)
assert(fence_landing and R.FenceClear(w,fence_landing) and fence_landing:DistSq(fence.pos)>=1.25^2,'blink landing rejects the barred region')
fence=ent('atrium_fence',13,0,'idle1_active');fence.radius=.1
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0),fence},11.2,0)
w:Tick()
assert(c.point and R.FenceClear(w,c.point) and R.FencePath(w,p.pos,c.point),'snare retreat cannot cross the fence even if every ground point is walkable')
-- 中庭地面边界与合法传送区域：即使场外仍全是陆地，也必须拒绝落点。
gate=ent('atrium_gate',0,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),gate},2.7,0);w:Scan()
assert(R.InArena(w,Vector3(12,0,12)) and not R.InArena(w,Vector3(15,0,0)))
w.avoid_boss=4.5
local geometry=R.BeginRetreat(w);local escape=w.escape_point
assert(w.escape_enough and escape:DistSq(boss.pos)>15^2 and math.abs(escape.z)>1,'choose a deep diagonal instead of the short straight boundary')
assert(R.InArena(w,escape) and R.Path(w,escape,nil,true,false,w.bait_point,true))
local band=w.bait_point
assert(band and math.abs(math.sqrt(band:DistSq(boss.pos))-11.9)<.0001 and R.Path(w,band,nil,true))
assert(math.sqrt(band:DistSq(boss.pos))+.05<12,'arrival tolerance must remain inside snare target search')
p.pos=Vector3(12,0,0);king=ent('king_cane',0,0);king._gem={value=function()return 'orangegem' end};p.hands=king;p.items={king}
local landing=R.Landing(w,Vector3(23,0,0),king)
assert(landing and R.InArena(w,landing),'outward desired teleport must be replaced with an arena-interior landing')
-- 骨刺不再整段撤出大门圈；无落点威胁时继续输出，只短撤第51帧震地。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',0)},2.7,0)
w:Tick();assert(c.owns and not w.moving,'spike windup is output time, not a fixed run outside the gate ring')
boss.frame=20;step(w,2/3);assert(c.owns,'early spike animation remains output when local landing spots are clear')
boss.frame=43;step(w,13/30)
assert(not c.owns and c.point and c.point.x>4 and c.point.x<5 and math.abs(c.point.z)<.001,'late shockwave dodge is a short radial step rather than radius9.3')
p.pos=c.point;boss.frame=47;step(w,4/30)
assert(not c.owns and not w.moving,'stay outside the impending local shockwave rather than immediately walking back in')
boss.frame=58;step(w,11/30)
assert(c.owns or w.mode:find('输出本体'),'resume output immediately after shockwave resolution, without waiting for busy to end')
-- 实际落点只触发附近短移；不受影响的位置仍可攻击，impact残留不长期阻断输出。
local landing=ent('fossilspike2',2.7,0,'appear',20);landing.duration=1
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',20),landing},2.7,0)
w:Tick();assert(not c.owns and c.point and p.pos:DistSq(c.point)<4^2,'a landing underfoot is evaded locally')
landing.animation='impact';landing.frame=1;w:Scan();w.zones=R.Zones(w)
assert(R.Risk(w,p.pos)>0,'new impact retains network grace')
landing.frame=12;step(w,.4)
assert(c.owns and R.Risk(w,p.pos)==0,'spent impact is no longer treated as persistent damage')
-- 高空中的落点尚未接近落地，不能被当作已经生效的墙；临近落地才启用危险圈。
local falling=ent('fossilspike2',4,0,'appear',0);falling.duration=1.5
w,c,p,boss=fixture({ent('stalker_atrium',0,0),falling},3,0);w:Scan()
assert(not O.SpikeDanger(falling,c:Latency()) and R.Risk(w,p.pos)==0)
falling.frame=35;w.zones=R.Zones(w)
assert(O.SpikeDanger(falling,c:Latency()) and R.Risk(w,p.pos)>0)
-- 实测83.53秒：开阔度低也锁定最短短撤，清掉旧攻击/预测后再请求移速。
local lip=ent('atrium_fence',5,2,'idle1_active');lip.radius=.1
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',39),lip},3.45,0)
local shock_stops=0;c.h.StopPredictWalk=function()shock_stops=shock_stops+1 end
w:Tick()
assert(w.shock_run and c.point==w.shock_run.point and math.abs(c.point.z)<.001 and c.point.x>4.4 and c.point.x<5,'local retreat cannot be redirected by generic edge scoring')
assert(shock_stops==1 and c.dodging,'shock departure cancels stale prediction and requests speed equipment')
-- 全段时间推进：保留近身输出，但为尚未结束的攻击和6移速短撤留足时间。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',0)},2.7,0);c.speed=6
for frame=0,51 do
 boss.frame=frame;p.busy=frame>=28 and frame<=35
 w:Tick()
 if w.moving and c.point and not p.busy then
  local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(c:Speed()/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end
 end
 now=now+1/30
end
assert(p.pos.x>=4.3 and p.pos.x<5,'even a delayed short retreat remains inside the gate ring and clears the shockwave')
-- 即使一时所有路径被阻断，也不能因为没有point而漏切移速装备。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',39)},3.45,0);w:Scan()
local blocked_path=R.Path;R.Path=function()return false end
w:Tick();assert(c.dodging and not c.owns,'no-route still requests the cane immediately')
R.Path=blocked_path
-- 实测29.23秒：躲落点也不能在第51帧震地时切回3.42码。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'spike',42)},4.04,0)
w:Tick();assert(w.spike_guard==w.state.spike_count and R.HitFloor(w)>4)
assert(not R.Path(w,Vector3(3.42,0,1),nil,true,true),'even the edge-recovery fallback must not cut inward before the shockwave')
p.pos=Vector3(4.6,0,0);boss.frame=50;step(w,8/30)
assert(not R.Path(w,Vector3(3.42,0,1),nil,true,true),'shockwave floor remains latched after movement changes the calculated lead')
boss.frame=58;step(w,8/30);assert(not R.HitFloor(w),'local shockwave protection releases after resolution')
-- 实测180.07秒：5码外接回巡游时，整条路径仍不能穿过尚未结算的普攻圈。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',25)},5.35,0)
w:Scan();w.state.anim='attack';w.state.frame=25
assert(not R.Path(w,Vector3(4.35,0,0),nil,true,true),'patrol cannot reenter an unresolved melee')
assert(R.Path(w,Vector3(5.35,0,3),nil,true),'outward/tangential movement remains available')
boss.frame=39;assert(R.Path(w,Vector3(4.35,0,0),nil,true),'melee floor releases for return attacks')
-- 场内纵深不足时不主动把自己带到死边，只做正常普攻躲避。
local saved_map=TheWorld.Map
TheWorld.Map={IsPassableAtPoint=function(_,x,y,z)return x>-5 and x<5 and z>-5 and z<5 end}
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.7,0);w:Scan();w.state.ready.snare=now
w:Tick();assert(w.lure_until and not c.owns and not w.escape_enough,'no-lane must not fall through to attack')
local held_resumes=c.resumed;boss.frame=38;step(w,1.27)
assert(not c.owns and c.resumed==held_resumes and w:AttackBlocked(boss),'no-lane recovery still forbids return hits')
TheWorld.Map=saved_map
-- 复现实战：Boss在场地一侧、玩家在Boss外侧时，所有向外直线都短，但侧移再转向有足够纵深。
gate=ent('atrium_gate',-7,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0),gate},2.7,0)
w:Scan();w.state.ready.snare=now+2
w:Tick()
assert(w.lure_until and w.escape_enough and w.bait_point,'find a complete route rather than cancelling the third-melee lure')
local turning=w.escape_turn or w.bait_point;local band_goal=w.bait_point
assert(R.InArena(w,w.escape_point) and R.InArena(w,turning))
local origin=p.pos
for _,point in ipairs(w.retreat.points)do
 assert(R.Path(w,point,nil,true,false,origin,true),'every committed retreat segment is physically legal')
 origin=point
end
local first=turning
assert(c.point and c.point:DistSq(first)<.001,'send the intermediate leg before moving to the outer band')
local resumed_before=c.resumed;boss.frame=38;step(w,1.27)
assert(not c.owns and c.resumed==resumed_before and w:AttackBlocked(boss))
for i=1,w.retreat.band-1 do
 p.pos=w.retreat.points[i];step(w,.1)
 assert(c.point and R.Path(w,c.point,nil,true,false,nil,true),'continue along the same complete route after each turn')
end
p.pos=band_goal;step(w,.1);assert(w.holding and not c.owns)
boss.animation='attack1';boss.frame=0;step(w,.1)
assert(not c.owns and c.point and R.Path(w,c.point,nil,true),'actual snare continues out along the prepared lane')
-- 实战161.80秒：骨牢前最后一次普攻起手就长撤，48帧不能恢复攻击等下一次。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack',0)},2.71,0)
w:Scan();w.state.ready.snare=now+1.64;w:Tick()
assert(w.lure_until and not c.owns and w:AttackBlocked(boss),'last melee frame zero must immediately block attacks')
local resumes=c.resumed
boss.frame=48;step(w,1.6)
assert(not c.owns and c.resumed==resumes,'no return hit at the logged 163.40-second recovery')
p.pos=w.bait_point;boss.frame=55;step(w,.23);assert(w.bait_waited and not c.owns)
local resumes_before=c.resumed;local old_band=p.pos
boss.animation='walk_pre';boss.frame=0;step(w,.1)
step(w,.31)
assert(w.lure_until and not w.rebait and c.resumed==resumes_before,'short walk_pre must retain escape across the behavior-tree selection gap')
boss.frame=8;step(w,.27)
assert(w.lure_until and not w.rebait,'logged .27-second pre-cast interval must not turn back')
boss.animation='walk_loop';boss.frame=0;step(w,.1)
for i=1,45 do boss.pos=Vector3(boss.pos.x+.05,0,0);step(w,1/30) end
assert(w.rebait and not w.lure_until and c.resumed==resumes_before,'sustained measured pursuit allows fresh melee bait')
boss.animation='attack1';boss.frame=0;step(w,.1)
assert(not w.rebait and not c.owns and c.point and p.pos:DistSq(c.point)>1,'actual snare preempts rebait and immediately escapes')
-- 0.13.44两次失败：Boss在约10码处进入walk_loop，不能回到4.17/7.69码骗第二次A。
for _,start in ipairs({9.85,9.95}) do
 w,c,p,boss=fixture({ent('stalker_atrium',0,0,'walk_loop',0)},start,0)
 w:Scan();w.state.ready.snare=now;w.lure_until=now+3;w.escape_enough=true
 w.escape_point=Vector3(18,0,0);w.bait_point=Vector3(11.9,0,0)
 w:Tick()
 assert(not w.rebait and w.lure_until and c.point and c.point.x>start,'logged walk_loop must continue outward rather than trigger rebait_return')
 p.pos=Vector3(11.9,0,0);boss.animation='attack1';boss.frame=0;step(w,.2)
 for frame=1,25 do
  local q=c.point;local d=math.sqrt(p.pos:DistSq(q));local amount=math.min(c:Speed()/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(q.x-p.pos.x)*amount/d,0,p.pos.z+(q.z-p.pos.z)*amount/d) end
  boss.frame=frame;step(w,1/30)
 end
 assert(p.pos.x>15 and not w.rebait and c.resumed==0,'maintained waiting band can cross resolution radius before frame25.5')
end
-- 10.56码不能作为到位停步；继续到至少11码，给起手后留下足够路程。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'idle',0)},10.56,0)
w:Scan();w.escape_point=Vector3(18,0,0);w.escape_enough=true;w.bait_point=Vector3(11.9,0,0)
w.retreat={mode='prepare',complete=true,index=1,band=1,points={w.bait_point,w.escape_point}}
assert(not R.RetreatReady(w))
p.pos=Vector3(11.88,0,0);assert(R.RetreatReady(w))
-- 远角能到不等于结算前能到：从7.69码起手，记录无完整步行解并最大化径向增距。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},7.69,0)
w:Tick();assert(w.snare_run and not w.snare_run.reachable and c.point.x>p.pos.x and math.abs(c.point.z)<.001)
assert(w.snare_run.budget<15.7-7.69,'deadline excludes a far corner that cannot be reached in time')
-- 径向被阻挡且只剩近切线能走时，不再选择一条先横穿Boss再出圈的长路线。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},11.2,0);w:Scan()
local path=R.Path
R.Path=function(owner,q,target,escape,edge,origin)
 local p0=origin or owner.c.player:GetPosition()
 return q.z>3 and q.x>=p0.x and q.x<p0.x+2 and path(owner,q,target,escape,edge,origin)
end
w:Tick();assert(not w.snare_run.reachable and c.point.x>=p.pos.x and c.point:DistSq(boss.pos)>p.pos:DistSq(boss.pos),'fallback increases radius without a backwards arc')
R.Path=path
-- 鬼手使用当前手杖原版攻击，不换主武器，不启动fight线程；本体起手能撤销尚未发出的动作。
hand=ent('shadowchanneler',3,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),hand},3,0)
boss._hasshield={value=function()return true end};boss.animation='taunt3_loop'
local held_cane=ent('king_cane',0,0);p.hands=held_cane;p.weapon=ent('sword_lunarplant',0,0);p.items={held_cane,p.weapon}
w:Tick()
assert(p.hand_attacks==1 and p.hand_target==hand and p.attack_hand==held_cane and not c.swaps and c.resumed==0,'one-health channeler must not request a weapon swap')
assert(p.hand_guard());boss.animation='attack';boss.frame=0
assert(not p.hand_guard(),'boss windup cancels a deferred channeler attack')
step(w);assert(not c.owns and c.point,'boss dodge still interrupts direct ghost-hand cleanup')
-- 骨牢起手期间忽略旧转向点与远角偏好，径向通畅就选最短出圈线，并立即撤掉回身预测。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},11.9,0)
w.escape_turn=Vector3(10,0,5);c.next_move=now+1
local predict_stops=0;c.h.StopPredictWalk=function()predict_stops=predict_stops+1 end
w:Tick();local run=w.snare_run
assert(run and c.point==run.point and math.abs(c.point.z)<.001 and math.abs(c.point.x-15.8)<.001,'direct radius exit is shorter than a diagonal far-corner route')
assert(predict_stops==1 and not c.next_move,'do not spend the first 0.1 seconds continuing toward the boss')
for frame=1,26 do
 local q=c.point;local dx,dz=q.x-p.pos.x,q.z-p.pos.z;local d=math.sqrt(dx*dx+dz*dz)
 if d>.001 then local advance=math.min(7.5/30,d);p.pos=Vector3(p.pos.x+dx*advance/d,0,p.pos.z+dz*advance/d) end
 boss.frame=frame;step(w,1/30)
 assert(w.snare_run==run and math.abs(c.point.z)<.001,'same cast must not replan into oscillating directions')
end
assert(p.pos.x>15,'continuous run crosses the resolution radius before the snare hit')
assert(predict_stops==2,'only reverse once at cast start and stop once after reaching the safe point')
-- 新的真实障碍出现才改变已锁定的撤退线；仍不穿危险区或跳出场内。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},11,0)
w:Scan();w.state.anim='attack1';w.state.snare_started=now
local direct=R.SnareRun(w,0,15);w.zones={{pos=Vector3(13,0,0),radius=.7}}
local around=R.SnareRun(w,1,15)
assert(around~=direct and math.abs(around.z)>.1 and R.Path(w,around,nil,true),'a new blocking hazard must invalidate the old ray')
-- 日志69.63秒起步、69.90秒接骨牢：这0.27秒不能折返，应该继续拉距。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'walk_pre',0)},9.7,0)
w:Scan();w.lure_until=now+3;w.bait_point=Vector3(12.8,0,0);w.escape_point=Vector3(17.1,0,0)
w:Tick();assert(not w.rebait and c.point.x>p.pos.x and not c.owns)
p.pos=Vector3(9.7+7.5*.27,0,0);boss.animation='attack1';boss.frame=0;step(w,.27)
assert(not w.rebait and c.point.x>p.pos.x,'the queued snare must keep the outward direction')
for frame=1,26 do
 local goal=c.point;local d=math.sqrt(p.pos:DistSq(goal));local move=math.min(7.5/30,d)
 if d>.001 then p.pos=Vector3(p.pos.x+(goal.x-p.pos.x)*move/d,0,p.pos.z+(goal.z-p.pos.z)*move/d) end
 boss.frame=frame;step(w,1/30)
end
assert(p.pos.x>15 and c.resumed==0,'removing the false return preserves enough travel to leave snare range')
-- 安全长段未走完不重新转向；真正路径受阻仍必须立刻改路。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},7,0);w:Scan()
w:Move(Vector3(20,0,0),'连续撤离',nil,true);local committed=w.point
now=now+.2;p.pos=Vector3(7.7,0,0)
w:Move(Vector3(20,0,1),'连续撤离',nil,true)
assert(w.point==committed,'small target changes cannot replace a committed safe segment')
-- 二阶段先补自然SAN：请求后等库存消耗，不在网络强制疯狂的0SAN下反复进食。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},9,0)
boss.animation='summon_loop';p.sanity=.2
local food=ent('cookedgreen_cap',0,0);p.items={food}
p.components.playeractionpicker.GetInventoryActions=function(_,i)return i==food and {{action=ACTIONS.EAT}} or {} end
w:Tick();assert(p.eats==1 and w.sanity_food and not c.owns)
step(w);assert(p.eats==1,'waiting for authoritative food consumption')
-- 等进食确认期间，真实攻击必须先于食物等待被处理。
boss.animation='attack';boss.frame=0;p.pos=Vector3(3,0,0);step(w)
assert(c.point and not c.owns and p.eats==1,'pending food never blocks danger movement')
p.items={};p.sanity=.75;boss.animation='summon_loop';step(w)
assert(not w.sanity_food and p.eats==1)
p.items={food};step(w,1);assert(p.eats==1,'enough natural SAN: no extra food')
-- 骨头盔保留身体护甲；同轮固定同一件，清完等待原头盔实际恢复。
hand=ent('shadowchanneler',3,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),hand},3,0)
local hat=ent('skeletonhat',0,0);local hat2=ent('skeletonhat',0,0);local helmet=ent('ruinshat',0,0)
amulet=ent('purpleamulet',0,0);armour=ent('armorruins',0,0)
p.items={hat,hat2,helmet,armour,food};p.head=helmet;p.body=armour;p.sanity=.8
p.components.playeractionpicker.GetInventoryActions=function()return {{action=ACTIONS.EAT}} end
boss._hasshield={value=function()return true end};boss.animation='taunt3_loop'
w:Tick();assert(p.last_equip==hat and w.sanity_round.original==helmet)
p.items={hat2,hat,helmet,armour,food};step(w)
assert(p.last_equip==hat and w.sanity_round.item==hat,'duplicate equipment cannot change the selected item')
p.head=hat;p.sanity=0;step(w)
assert(p.hand_target==hand and not p.eats and p.body==armour,'induced insanity is not natural food deficit')
boss.animation='idle';boss._hasshield={value=function()return false end};all={boss};w.state.ready.snare=now+8
step(w,.5);assert(p.last_equip==helmet and not c.owns and w.sanity_round.restoring)
step(w);assert(not c.owns,'must confirm original gear before returning to normal combat')
p.head=helmet;p.sanity=.8;p.pos=Vector3(2,0,0);step(w)
assert(not w.sanity_round and c.owns)
-- 长前摇继续清手；末段前停止发起新攻击，临界点摘装备，后续控制循环不重新戴。
hand=ent('shadowchanneler',3,0)
w,c,p,boss=fixture({ent('stalker_atrium',0,0),hand},3,0)
p.items={hat,helmet};p.head=helmet;p.sanity=.8
boss._hasshield={value=function()return true end};boss.animation='taunt3_loop'
w:Tick();p.head=hat;p.sanity=0;step(w)
boss.animation='control_pre';boss.duration=4;boss.frame=30
local handcount=p.hand_attacks or 0;step(w,.7)
assert(p.head==hat and not w.sanity_round.restoring and p.hand_attacks>handcount,'do not restore at control windup start')
local delayed_hand=p.hand_guard
boss.frame=90;step(w)
assert(not delayed_hand() and not w.sanity_round.restoring,'stop starting attacks before the equipment deadline')
boss.frame=110;step(w)
assert(w.sanity_round.restoring and p.last_equip==helmet,'restore near the real animation deadline')
p.head=helmet;p.sanity=.8;step(w)
assert(not w.sanity_round and not c.gear.action_hold)
boss.animation='control_loop';step(w);assert(not w.sanity_round and p.head==helmet,'no re-equip during control application')
-- 原槽为空时显式脱下；不能把强制疯狂遗留在身上。
w,c,p,boss=fixture({ent('stalker_atrium',0,0),ent('shadowchanneler',3,0)},3,0)
p.items={amulet};p.sanity=.8;boss.animation='taunt3_loop';boss._hasshield={value=function()return true end}
w:Tick();p.body=amulet;p.sanity=0;step(w)
boss.animation='idle';boss._hasshield={value=function()return false end};all={boss};w.state.ready.snare=now+8
step(w,.5);assert(p.last_unequip==amulet and w.sanity_round and not c.owns)
p.body=nil;p.sanity=.8;p.pos=Vector3(2,0,0);step(w);assert(not w.sanity_round and c.owns)
-- 已有临时装备请求在途，也不能在控制末段继续等待戴上它。
w,c,p,boss=fixture({ent('stalker_atrium',0,0),ent('shadowchanneler',3,0)},3,0)
p.items={hat,helmet};p.head=helmet;p.sanity=.8;boss.animation='taunt3_loop'
boss._hasshield={value=function()return true end};w:Tick();assert(w.support.item==hat)
boss.animation='control_pre';boss.frame=110;step(w)
assert(not w.support and not w.sanity_round and p.head==helmet)
-- 实测194.40~198.53秒：退路只有3~5码，脚边备用点绝不算已到11.2码等待带。
w,c,p,boss=fixture({ent('stalker_atrium',0,0),ent('atrium_gate',0,0)},1.58,0)
w:Scan();w.state.ready.snare=now
-- Stale legacy placeholders cannot become a waiting band; only a newly committed route may own movement.
w.escape_enough=false;w.escape_reach=3.8;w.escape_point=Vector3(3.8,0,0)
boss.animation='attack';boss.frame=0;w:Tick()
assert(w.lure_until and not w.bait_waited and w.moving and c.point.x>4.5,'insufficient depth falls back to real melee dodge, never a false wait')
p.pos=Vector3(3.09,0,0);w.bait_point=p.pos;boss.frame=32;step(w)
assert(not w.bait_waited and w.moving and c.point.x>4.5,'nearby placeholder cannot suppress movement through the hit frame')
w.escape_enough=true;w.escape_point=Vector3(17,0,0)
assert(not R.RetreatReady(w),'a stale enough flag cannot make a close point a valid waiting ring')
w.escape_enough=false;boss.animation='walk_loop';step(w)
assert(not w.rebait and not c.owns,'no full escape: let boss follow toward open ground instead of returning to its face')
-- 源码语义回归：吞食不是纯粹8秒木桩；召唤每个循环有两个吼叫事件。
if read_source then
 local source=read_source('stategraphs/SGstalker.lua')
 local control=assert(source:find('name = "mindcontrol_loop"',1,true))
 assert(source:find('inst:MindControl()',control,true),'control applies on loop entry, not windup start')
 local sanity_source=read_source('components/sanity.lua')
 local first=assert(sanity_source:find('local function _replica_setcurrent(',1,true))
 local last=assert(sanity_source:find('\nend',first,true))
 local setcurrent=assert(loadstring(sanity_source:sub(first,last+3)..'\nreturn _replica_setcurrent'))()
 local networked;local replica={SetCurrent=function(_,n)networked=n end}
 setcurrent({},replica,160,200,0,true,false);assert(networked==0,'temporary gear hides natural SAN on the network')
 setcurrent({},replica,160,200,0,false,false);assert(networked==160,'removing gear restores natural SAN')
 local amulet_source=read_source('prefabs/amulet.lua')
 assert(amulet_source:find('SetInducedInsanity(inst, true)',1,true) and amulet_source:find('SetInducedInsanity(inst, false)',1,true))
 assert(source:find('data.resist <= 0',1,true) and source:find('data.idle > 6',1,true))
 assert(source:find('FrameEvent(25.5',1,true) and source:find('inst:SpawnSnares',1,true))
 source=read_source('prefabs/stalker.lua')
 local a=assert(source:find('local function DelaySharedAbilityCooldown(',1,true))
 local z=assert(source:find('\nend',a,true))
 local fn=assert(loadstring(source:sub(a,z+3)..'\nreturn DelaySharedAbilityCooldown'))
 local tune={STALKER_SNARE_CD=10,STALKER_SPIKES_CD=8,STALKER_MINDCONTROL_CD=15}
 setfenv(fn,setmetatable({TUNING=tune,SHARED_COOLDOWNS={'snare','spikes','mindcontrol'}},{__index=_G}))
 local shared_delay=fn()
 for _,case in ipairs({{2,0},{9,7},{0,15},{12,20}}) do
  local timers={snare_cd=case[1],mindcontrol_cd=case[2]}
  local timer={GetTimeLeft=function(_,id)return timers[id] end,StopTimer=function(_,id)timers[id]=nil end,StartTimer=function(_,id,t)timers[id]=t end}
  shared_delay({components={timer=timer}},'spikes')
  local observed=O.New();observed.ready.snare=100+case[1];observed.ready.mindcontrol=100+case[2]
  boss.animation='spike';boss.frame=6;O.Update(observed,boss,100)
  assert(math.abs(observed.ready.snare-100-timers.snare_cd)<.00001,'snare common shift differs from original source')
  assert(math.abs(observed.ready.mindcontrol-100-timers.mindcontrol_cd)<.00001,'mindcontrol common shift differs from original source')
 end
 local tuning=read_source('tuning.lua')
 assert(tuning:find('STALKER_FIRST_SNARE_CD%s*=%s*5') and tuning:find('STALKER_FIRST_SPIKES_CD%s*=%s*4'))
 -- 复现203.17到249.70秒长间隔的根因：旧12.8码点无法起手，每次失败续3秒重试。
 local search=assert(tonumber(tuning:match('STALKER_SNARE_RANGE%s*=%s*([%d.]+)')))
 local resolve=assert(tonumber(tuning:match('STALKER_SNARE_MAX_RANGE%s*=%s*([%d.]+)')))
 local retry=assert(tonumber(tuning:match('STALKER_ABILITY_RETRY_CD%s*=%s*([%d.]+)')))
 local brain=read_source('brains/stalkerbrain.lua')
 local start=assert(brain:find('local function ShouldSnare(self)',1,true))
 local stop=assert(brain:find('\nend',start,true))
 local fn=assert(loadstring(brain:sub(start,stop+3)..'\nreturn ShouldSnare'))
 setfenv(fn,setmetatable({TUNING={STALKER_ABILITY_RETRY_CD=retry}},{__index=_G}))
 local shouldsnare=fn();local retry_time
 local decision={inst={components={timer={TimerExists=function()return false end,StartTimer=function(_,id,t)assert(id=='snare_cd');retry_time=t end}}}}
 local target_distance=12.8
 decision.inst.FindSnareTargets=function()if target_distance<=search then return {p} end end
 assert(not shouldsnare(decision) and retry_time==3,'old waiting position triggers retry instead of snare')
 w,c,p,boss=fixture({ent('stalker_atrium',0,0)},2.7,0);w:Scan()
 local waiting=assert(R.CapturePoint(w,p.pos,search,resolve))
 for _,error in ipairs({-.09,0,.09}) do
  retry_time=nil;target_distance=math.sqrt(waiting:DistSq(boss.pos))+error
  assert(shouldsnare(decision) and not retry_time,'new waiting point and arrival tolerance remain searchable')
 end
 p.pos=Vector3(12.8,0,0);w.escape_turn=Vector3(14,0,3)
 local corrected=assert(R.CapturePoint(w,p.pos,search,resolve))
 assert(corrected:DistSq(boss.pos)<search^2,'pure band geometry corrects an outside point without executing or clearing another route')
 local adventure=assert(R.CapturePoint(w,p.pos,24,24))
 assert(math.sqrt(adventure:DistSq(boss.pos))+.05<24,'equal adventure search/effect ranges still keep arrival inside search')
 p.pos=waiting;boss.animation='attack1';w:Tick()
 assert(c.point and c.point:DistSq(boss.pos)>resolve^2,'confirmed windup must still run beyond effect range')
 local gate_source=read_source('prefabs/atrium_gate.lua')
 assert(gate_source:find('local ATRIUM_ARENA_SIZE = 14.55',1,true),'arena boundary must match installed game source')
end
if read_source then
 local src=read_source('prefabs/fossil_spike2.lua')
 local impact=src:match('local function OnImpact(.-)local SHADOW_DELTA2')
 assert(impact and impact:find('DoDamage(inst)',1,true) and not impact:find('DoPeriodicTask',1,true),'spike damage is resolved once on impact')
 local sg=read_source('stategraphs/SGstalker.lua')
 local state=sg:match('name = "spikes"(.-)name = "summon_channelers_pre"')
 assert(state and state:find('FrameEvent(51',1,true) and state:find('DoAreaAttack(inst, 3.5',1,true),'short dodge must preserve the real late area hit')
end
if read_source then
 local src=read_source('prefabs/atrium_fence.lua')
 assert(src:find('MakeObstaclePhysics(inst, .1)',1,true) and src:find('COLLISION.CHARACTERS',1,true))
 assert(not src:find('AddTag("wall")',1,true) and not src:find('AddTag("structure")',1,true),'source confirms tag-only obstacle scans miss the fence')
end
for k,v in pairs(globals)do _G[k]=v end
for _,k in ipairs({'Class','GetTime','Vector3','TheSim','TheWorld','TUNING','EQUIPSLOTS','ACTIONS'})do if globals[k]==nil then _G[k]=nil end end
for _,n in ipairs({'actions','incoming','weaver/observe','weaver/round','weaver/ranged','weaver/route','weaver/debug','weaver/sanity','weaver/cycle','weaver/phase1','weaver/controller'})do local k='shadowself/control/'..n;package.loaded[k]=saved[k] end
print('PASS: weaver observation, post-hit-only blink, legal inland landing, coast recovery, real prediction restart, feeding and cooldown/equip acknowledgements')
