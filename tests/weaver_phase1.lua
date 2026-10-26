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
local w,c,p,boss,setshield,entities=arena(6,0,{})
setshield(false);p.pos=Vector3(4.5,0,0);p.sanity=.8
local amulet=ent('purpleamulet',0,0);p.items={amulet};w:Tick()
assert(w.phase1.stage=='fight' and c.owns and not w.sanity_round)
for i=1,8 do
 w.state.anim='attack1';w.state.snare_started=i;Phase1.Observe(w)
 w.state.anim='spike';w.state.spike_count=i;Phase1.Observe(w)
end
assert(w.phase1.stage=='enter' and not w.phase1.goal and not Phase1.KeepMask(w),'no number of observed skills predicts health transition or pre-equips insanity')
w.state.anim='idle';w.state.phase=1;Phase1.Tick(w)
assert(not w.sanity_round and not p.last_equip)
-- 骨刺计数不能再撤销已经确认的圈内输出定位。
w.phase1.stage='fight';w.state.anim='spike';w.state.spike_count=99;Phase1.Observe(w)
assert(w.phase1.stage=='fight' and not w.phase1.goal,'local spike dodge does not trigger an extra return-to-ring movement')
-- 骨牢后回圈只是原一阶段输出定位，不是预拉角。
p.pos=Vector3(10,0,0);boss.pos=Vector3(8,0,0);w.phase1.stage='center';w.phase1.goal=nil
assert(Phase1.Tick(w) and w.phase1.stage=='center' and c.point and c.point:DistSq(Vector3(0,0,0))<8^2)
local hand=ent('shadowchanneler',8.7,0);entities[#entities+1]=hand;setshield(true);boss.animation='taunt3_pre'
step(w,.4)
assert(w.phase1.stage=='done' and w.cycle and not w.phase1.goal and not w.sanity_round,'actual shield/ghost starts field recovery directly, with no pre-transition mask')
if read_source then
 local source=read_source('prefabs/stalker.lua')
 local first=assert(source:find('local function DelaySharedAbilityCooldown(',1,true));local last=assert(source:find('\nend',first,true))
 local fn=assert(loadstring(source:sub(first,last+3)..'\nreturn DelaySharedAbilityCooldown'))
 setfenv(fn,setmetatable({TUNING={STALKER_SNARE_CD=10,STALKER_SPIKES_CD=8,STALKER_MINDCONTROL_CD=15},SHARED_COOLDOWNS={'snare','spikes','mindcontrol'}},{__index=_G}))
 local delay=fn()
 for _,case in ipairs({{.8,.8,7.5},{0,12,5}}) do
  local timers={snare_cd=case[1],mindcontrol_cd=case[2]}
  delay({components={timer={GetTimeLeft=function(_,id)return timers[id]end,StopTimer=function(_,id)timers[id]=nil end,StartTimer=function(_,id,t)timers[id]=t end}}},'spikes')
  assert(math.abs(timers.snare_cd-case[3])<.00001,'source uses a common delay, not a fixed 5-second reset')
 end
 local brain=read_source('brains/stalkerbrain.lua')
 first=assert(brain:find('local function ShouldMindControl(self)',1,true));last=assert(brain:find('\nend',first,true))
 fn=assert(loadstring(brain:sub(first,last+3)..'\nreturn ShouldMindControl'))
 setfenv(fn,setmetatable({IsDefensive=function(self)return self.inst.components.health.currenthealth<10000 end,TUNING={STALKER_ABILITY_RETRY_CD=3}},{__index=_G}))
 local check=fn();local ai={inst={components={health={currenthealth=10001},timer={TimerExists=function()return false end}},HasMindControlTarget=function()return true end}}
 assert(not check(ai),'forced insanity cannot unlock mindcontrol during phase one')
 ai.inst.components.health.currenthealth=9999;assert(check(ai))
 first=assert(brain:find('local function ShouldUseAbility(self)',1,true));last=assert(brain:find('\nend',first,true))
 fn=assert(loadstring(brain:sub(first,last+3)..'\nreturn ShouldUseAbility'))
 local no=function()return false end
 setfenv(fn,setmetatable({ShouldMindControl=no,ShouldSnare=function()return true end,ShouldSummonChannelers=no,ShouldCombatFeast=no,CheckMinions=function()end,ShouldSummonMinions=no,ShouldSpikes=function()return true end},{__index=_G}))
 local choose=fn();ai.inst.components.combat={HasTarget=function()return true end}
 ai.wantstospikes=nil;assert(choose(ai) and ai.abilityname=='fossilsnare')
 ai.wantstospikes=true;assert(choose(ai) and ai.abilityname=='fossilspikes','a pending spike selection changes priority, not random fourth-spike odds')
end
for k,v in pairs(globals)do _G[k]=v end
for _,k in ipairs({'Class','GetTime','Vector3','TheSim','TheWorld','TUNING','EQUIPSLOTS','ACTIONS'})do if globals[k]==nil then _G[k]=nil end end
for _,n in ipairs({'actions','incoming','weaver/observe','weaver/round','weaver/ranged','weaver/route','weaver/debug','weaver/sanity','weaver/cycle','weaver/phase1','weaver/controller'})do local k='shadowself/control/'..n;package.loaded[k]=saved[k] end
print('PASS: no predictive phase transition, ordinary inner-ring output, actual phase2 takeover and original shared cooldown/health-gated abilities')
