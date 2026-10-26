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
local hand=ent('shadowchanneler',8,8)
local bug=ent('stalker_minion1',1,1)
local w,c,p,boss,setshield,entities=arena(0,0,{hand,bug})
p.pos=Vector3(6,0,1);p.sanity=.8
local staff=ent('staff_lunarplant',0,0);local cane=ent('cane',0,0)
p.items={staff,cane};p.hands=cane
boss.animation='taunt2_loop1';w:Tick()
assert(w.cycle.stage=='clear_feed' and w.cycle.food==bug and p.last_equip==staff,'actual feeding worms trigger ranged cleanup immediately')
p.hands=staff;step(w,.5)
assert(p.hand_target==bug and p.attack_hand==staff and casts==0,'brightshade uses ordinary attack, not spellcasting')
local guard=p.hand_guard
boss.animation='attack1';boss.frame=0;step(w)
assert(not guard() and c.point and c.point:DistSq(boss.pos)>p.pos:DistSq(boss.pos) and not w.snare_run.reachable,'real cage preempts worm attack; a too-close cast cannot be labelled a timely full escape')
-- 清空脚下即可拉走，不必等场上全部虫子自爆，也不虚构一次击杀。
bug.tags.NOCLICK=true;boss.animation='idle';step(w,2);step(w,.4)
assert(w.cycle.stage=='patrol' and not w.sanity_round and not c.owns)
local far=ent('stalker_minion2',-10,-10);entities[#entities+1]=far;step(w)
assert(w.cycle.stage=='patrol' and w.cycle.bugs==1 and w.cycle.feeding==0)
-- 吞食复发立即进入补救；旧版遗留疯狂装备也必须脱下。
local close=ent('stalker_minion1',.7,0);entities[#entities+1]=close;boss.animation='taunt2_loop1';step(w)
assert(w.cycle.stage=='clear_feed' and w.cycle.food==close)
-- 实测吞食idle等待FindMinions(5)：4.5码外圈的虫子也必须先清，不能去拉蹲着的Boss。
local outerfood=ent('stalker_minion1',4.5,0)
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8.7,0),outerfood})
p.pos=Vector3(7,0,0);p.sanity=.8;p.items={staff};p.hands=staff;boss.animation='taunt2_loop1'
w:Tick()
assert(w.cycle.stage=='clear_feed' and w.cycle.food==outerfood and p.hand_target==outerfood,'waiting-circle food is handled before any patrol')
-- 暂时没有可打虫子且仍吞食时留在清理流程，不调用巡游去等一个不会跟随的Boss。
outerfood.pos=Vector3(9,0,0);w.state.ready.snare=now+8;step(w,.4)
assert(w.cycle.stage=='clear_feed' and not w.moving and (w.staff_action or w.mode:find('不巡游')),'feasting retains the submitted projectile or holds cleanup; never patrols a rooted boss')
-- 清掉最后的食物、骨牢已就绪时，利用吞食已定住Boss的窗口立刻撤，不等新的平A。
w.state.ready.snare=now;step(w)
assert(w.lure_until and w.feast_lure and not w.rebait and not p.hand_guard(),'actual feast cleanup arms cage preparation and invalidates stale worm attacks')
assert(w.cycle.stage=='clear_feed' and not w.sanity_round)
boss.animation='attack1';boss.frame=0;step(w)
assert(w.snare_run and not w.feast_lure,'real cage preempts feast preparation')
-- 实测103.90骗A撤退 -> 106.10改为吞食：必须释放旧诱牢并重新接近清虫。
local stalledfood=ent('stalker_minion1',1,0)
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8.7,0),stalledfood})
p.pos=Vector3(2.7,0,0);p.sanity=.8;p.items={cane};p.hands=cane
w:Tick();w.state.ready.snare=now+2;boss.animation='attack';boss.frame=0;step(w)
assert(w.lure_until and not w.feast_lure)
p.pos=Vector3(11.04,0,0);w.state.ready.snare=now+8;boss.animation='taunt2_pre';boss.frame=0;step(w,2.2)
assert(not w.lure_until and not w.rebait and w.cycle.food==stalledfood and w.mode:find('清除'),'new feast cancels the old cage wait even while estimated snare cooldown is ready')
assert(w.moving and c.point.x<p.pos.x,'return to actual food rather than holding at 11 yards')
p.pos=Vector3(2.5,0,0);w.state.ready.snare=now+6;boss.animation='taunt2_loop1';step(w,.4)
assert(p.hand_target==stalledfood,'worm attacks resume after the stale wait is released')
-- 已确认清空后准备诱牢期间又来虫子，也必须立即释放等待状态。
stalledfood.tags.NOCLICK=true;w.state.ready.snare=now;step(w,.4)
assert(w.feast_lure and w.lure_until)
local newfood=ent('stalker_minion2',.8,0);entities[#entities+1]=newfood;p.pos=Vector3(11.04,0,0);w.state.ready.snare=now+6;step(w,.2)
assert(not w.feast_lure and not w.lure_until and w.cycle.food==newfood and w.moving)
-- 实测96.23：召鬼手结束即放骨牢。召唤已定住Boss，不能贴身发呆等待虫子。
w,c,p,boss,setshield,entities=arena(0,0,{})
p.pos=Vector3(2.68,0,0);p.sanity=.8;p.items={cane};p.hands=cane
w:Scan();w.state.ready.snare=now+2;boss.duration=65/30;boss.animation='taunt3_pre';boss.frame=0;w:Tick()
assert(not w.spawn_lure and w.cycle.stage=='spawn','guaranteed follow-up loop keeps the pre stage available for cleanup')
for frame=1,65 do
 local point=c.point
 if point then
  local d=math.sqrt(p.pos:DistSq(point));local n=math.min(c:Speed()/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(point.x-p.pos.x)*n/d,0,p.pos.z+(point.z-p.pos.z)*n/d) end
 end
 boss.frame=frame;step(w,1/30)
end
boss.animation='taunt3_loop';boss.duration=40/30
for frame=0,40 do
 boss.frame=frame;step(w,1/30)
 if c.point then local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(c:Speed()/30,d)
 if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end end
end
assert(math.sqrt(p.pos:DistSq(boss.pos))>=11,'summon preparation reaches the cage waiting band before guaranteed loop release')
boss.animation='attack1';boss.frame=0;step(w,.1)
assert(not w.spawn_lure and w.snare_run and w.snare_run.reachable,'actual snare takes over from a reachable starting distance')
-- 召手前摇即规划外围；长召虫尚在busy时保留清路窗口，不能归入站桩吞食。
w,c,p,boss,setshield=arena(4,8,{ent('shadowchanneler',8.7,0)})
p.sanity=.8;boss.animation='taunt3_pre';w:Tick();step(w,.5)
assert(w.cycle.stage=='spawn' and w.cycle.route_goal and w.cycle.perimeter,'channeler windup plans outer route immediately')
boss.animation='summon_loop';step(w,.5);assert(w.cycle.stage=='spawn' and w.cycle.await_snare,'summon busy keeps the route plan and post-spawn cage barrier')
-- 重复同种法杖保持选定实体；装备确认前不会发攻击。
w,c,p,boss,setshield,entities=arena(0,0,{ent('stalker_minion1',1,0)})
p.pos=Vector3(6,0,0);p.sanity=.8
local staff2=ent('staff_lunarplant',0,0);p.items={staff,staff2,cane};p.hands=cane
boss.animation='taunt2_loop1' -- 重复装备测试使用真实定身窗口，不要求未知CD下贴近换装。
w:Tick();assert(p.last_equip==staff and not p.hand_attacks)
p.items={staff2,staff,cane};p.hands=staff;step(w,.5)
assert(p.hand_target==entities[3] and w.cycle.staff==staff and p.attack_hand==staff)
-- 真正骗A后先固定武器，再临时戴护符，只打一只最近鬼手，恢复身体护甲。
local near=ent('shadowchanneler',10,8);local other=ent('shadowchanneler',11,8)
w,c,p,boss,setshield,entities=arena(4,8,{near,other,ent('stalker_minion1',-10,-10)})
p.pos=Vector3(10,0,8);p.sanity=.8
local amulet=ent('purpleamulet',0,0);local armour=ent('armorruins',0,0)
p.items={amulet,armour,staff,cane};p.body=armour;p.hands=staff
w:Tick();step(w,.4)
assert(w.cycle.stage=='patrol' and not w.sanity_round and not p.last_equip,'no automatic insanity before actual normal attack')
w.state.ready.snare=now+8 -- 本例只验证法杖弹跳；骨牢冷却必须明确足够，不能假定未知CD安全。
boss.animation='attack';boss.frame=0;step(w)
assert(p.last_equip==amulet and w.sanity_round.original==armour and not p.hand_attacks)
p.body=amulet;p.sanity=0;boss.frame=6;step(w,.2)
assert(p.hand_target==near and p.attack_hand==staff and p.hand_attacks==1,'nearest ghost attacked inside actual busy window')
local ghostguard=p.hand_guard
near.tags.NOCLICK=true;boss.frame=12;step(w,.2)
assert(w.staff_action and not w.sanity_round.restoring,'first kill does not restore SAN while another bounce target lives')
other.tags.NOCLICK=true;boss.frame=30;step(w,.6)
assert(w.sanity_round.restoring and p.last_equip==armour,'all confirmed bounce targets killed allows equipment restoration')
p.body=armour;p.sanity=.8;boss.frame=38;step(w,8/30)
assert(not w.sanity_round and p.hand_attacks==1,'one real melee grants only one ghost attack')
boss.frame=44;step(w,.2);assert(p.hand_attacks==1)
-- 模拟躲开普攻后才收到护符装备确认；不能再用“尚需换装”的旧预算饿死清手。
w,c,p,boss,setshield,entities=arena(4,8,{ent('shadowchanneler',9.5,8),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(9.5,0,8);p.sanity=.8;p.items={amulet,armour,cane};p.body=armour;p.hands=cane
w:Tick();step(w,.4);boss.animation='attack';boss.frame=18;step(w,.6)
assert(p.last_equip==amulet)
p.body=amulet;p.sanity=0;boss.frame=22;step(w,4/30)
assert(p.hand_attacks==1 and p.attack_hand==cane,'confirmed mask leaves enough time for a 1hp hand attack and prompt restore')
-- 不等精神控制前摇临界点；普攻busy结束前就要取消未完成的换装。
w,c,p,boss,setshield=arena(4,8,{ent('shadowchanneler',10,8),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(10,0,8);p.sanity=.8;p.items={amulet,armour,staff};p.body=armour;p.hands=staff
w:Tick();step(w,.4);w.state.ready.snare=now+8;boss.animation='attack';boss.frame=0;step(w)
assert(p.last_equip==amulet)
p.body=amulet;p.sanity=0;boss.frame=45;step(w,1.5)
assert(p.last_equip==armour and w.sanity_round.restoring and not p.hand_attacks,'late equip acknowledgement cannot start a late attack')
p.body=armour;p.sanity=.8;boss.animation='control_pre';boss.frame=0;step(w,.5)
assert(not w.sanity_round,'unexpected control restores immediately, not near its application')
-- 不具备疯狂装备时不能假装鬼手已可攻击，更不能诱控制等待。
w,c,p,boss,setshield=arena(4,8,{ent('shadowchanneler',10,8),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(10,0,8);p.sanity=.8;p.items={staff};p.hands=staff
w:Tick();step(w,.4);boss.animation='attack';boss.frame=0;step(w)
assert(not p.hand_attacks and not w.sanity_round and w.cycle.stage=='patrol')
-- 没有法杖仍能用手杖清1血虫子；破盾且虫子清空接回本体原走A。
local road=ent('stalker_minion1',10,10)
w,c,p,boss,setshield,entities=arena(9,9,{road})
p.pos=Vector3(11,0,10);p.hands=cane;p.items={cane};p.sanity=.8;boss.animation='taunt2_loop1'
w:Tick();assert(p.hand_target==road and p.attack_hand==cane)
road.tags.NOCLICK=true;setshield(false);boss.animation='idle';step(w,.5);step(w,.4)
assert(w.cycle.stage=='fight' and c.owns and not w.sanity_round,'empty real field resumes ordinary output without waiting for control')
-- 即使有盾，真实普攻后的骨牢准备也必须优先于巡游/清理。
w,c,p,boss,setshield=arena(6,0,{ent('shadowchanneler',8,0),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(10,0,0);p.sanity=.8;w:Tick();w.state.ready.snare=now+1
boss.animation='attack';boss.frame=0;step(w)
assert(w.lure_until and w.mode:find('骨牢') and not p.hand_attacks,'shield must not disable bone-cage bait or overwrite its retreat')
-- 一阶段无实体/技能证据时不因真实血量低或默认血量值运行预转场。
-- 清手破盾后场上无虫立即回原输出；下一轮虫子触发清理，不能继续贪本体。
w,c,p,boss,setshield,entities=arena(0,0,{ent('stalker_minion1',9,9)})
p.pos=Vector3(10,0,9);p.sanity=.8;w:Tick();w.cycle.seen_summon=true
entities[3].tags.NOCLICK=true;setshield(false);boss.animation='idle';step(w,.5);step(w,.4)
assert(w.cycle.stage=='fight' and w.moving and c.point:DistSq(boss.pos)<p.pos:DistSq(boss.pos),'empty field approaches boss immediately, without a mandatory corner trip')
p.pos=Vector3(2.5,0,0);step(w,.2);assert(c.owns,'in-range empty field resumes output')
local nextbug=ent('stalker_minion1',boss.pos.x+.5,boss.pos.z);entities[#entities+1]=nextbug;boss.animation='taunt2_pre';step(w,.2)
assert(w.cycle.stage=='clear_feed' and not c.owns,'next real feast restarts cleanup before the perimeter cycle')
-- 人物脚前无虫，但Boss追击直线将穿过虫子：先到虫子->Boss的反侧，不能继续等它跟上。
local crossing=ent('stalker_minion1',0,8)
w,c,p,boss,setshield,entities=arena(-5,8,{ent('shadowchanneler',-9,-8),crossing})
p.pos=Vector3(4,0,8);p.sanity=.8;p.items={cane};p.hands=cane
w:Tick();step(w,.4)
assert(w.cycle.stage=='patrol' and w.cycle.feeding==0 and w.cycle.pull and w.moving,'predict boss collision before food enters its actual feeding circle')
local away=w.cycle.pull_point
assert(away.x<boss.pos.x and R.InArena(w,away) and R.Path(w,away,nil,true),'opposite-side waypoint stays inside arena and uses a legal flank instead of crossing the boss')
assert(c.point==away,'validated diversion bypasses generic edge scoring and tiny intermediate footsteps')
step(w,.11);assert(w.cycle.pull_point==away and c.point==away,'unchanged worm geometry preserves one continuous route')
-- 以人物7.5、Boss1.5移速推进追击：实际拉开后才回外围，不以人物先到点当Boss已脱离。
for i=1,60 do
 local point=c.point
 if w.moving and point then
  local d=math.sqrt(p.pos:DistSq(point));local n=math.min(.1*c:Speed(),d)
  if d>.001 then p.pos=Vector3(p.pos.x+(point.x-p.pos.x)*n/d,0,p.pos.z+(point.z-p.pos.z)*n/d) end
 end
 local d=math.sqrt(boss.pos:DistSq(p.pos));local n=math.min(.15,math.max(0,d-2))
 if d>.001 then boss.pos=Vector3(boss.pos.x+(p.pos.x-boss.pos.x)*n/d,0,boss.pos.z+(p.pos.z-boss.pos.z)*n/d) end
 boss.animation='walk_loop';step(w,.1)
 assert(w.cycle.feeding==0,'diversion must not lead the following boss into the worm feeding circle')
end
assert(boss.pos:DistSq(crossing.pos)>5^2,'boss is actually led away from the threatened worm')
-- 实际吞食优先清食物；不能保留上一段拉扯坐等Boss跟随。
boss.animation='taunt2_loop1';crossing.pos=Vector3(boss.pos.x+.5,0,boss.pos.z);step(w,.2)
assert(w.cycle.stage=='clear_feed' and not w.cycle.pull and not w.cycle.pull_point and w.cycle.food==crossing)
-- 被栏杆封死的反侧目标不能被当成规划成功，移动落点也不能钻进栅栏。
crossing=ent('stalker_minion1',0,8)
local fences={ent('shadowchanneler',-9,-8),crossing}
for _,z in ipairs({4,6,8,10,12}) do fences[#fences+1]=ent('atrium_fence',-8,z) end
w,c,p,boss,setshield,entities=arena(-5,8,fences);p.pos=Vector3(4,0,8);p.items={cane};p.hands=cane;p.sanity=.8
w:Tick();step(w,.4)
if w.cycle.pull_point then assert(R.FenceClear(w,w.cycle.pull_point) and R.FencePath(w,p.pos,w.cycle.pull_point)) end
-- 引离过程中骗到普攻，顺路清手仍可执行；真实骨牢抢占这两种动作。
local passinghand=ent('shadowchanneler',4,8)
w,c,p,boss,setshield,entities=arena(-5,8,{passinghand,ent('stalker_minion1',0,8)})
p.pos=Vector3(4,0,8);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Tick();step(w,.4);assert(w.cycle.pull)
w.state.ready.snare=now+20;boss.animation='attack';boss.frame=0;step(w)
assert(p.last_equip==amulet,'diversion yields actual melee window to a nearby hand')
p.body=amulet;p.sanity=0;boss.frame=6;step(w,.2)
assert(p.hand_target==passinghand and p.attack_hand==cane,'hand on the current route is cleared without a weapon swap')
local passingguard=p.hand_guard
boss.animation='attack1';boss.frame=0;step(w)
assert(w.snare_run and not passingguard() and w.mode:find('骨牢'),'real snare preempts both diversion and opportunistic hand attack')
-- 实测179.70：5.30码发换装，确认时回弹到5.23码；安全距离内不能被再一次“躲普攻”饿死。
local reboundhand=ent('shadowchanneler',5.23,0)
w,c,p,boss,setshield,entities=arena(0,0,{reboundhand,ent('stalker_minion1',-10,-10)})
p.pos=Vector3(5.3,0,0);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Tick();step(w,.4);w.state.ready.snare=now+20
boss.animation='attack';boss.frame=17;step(w)
assert(p.last_equip==amulet)
p.pos=Vector3(5.23,0,0);p.body=amulet;p.sanity=0;boss.frame=23;step(w,.2)
assert(p.hand_target==reboundhand and p.hand_attacks==1,'safe server position correction must not cancel ghost attack after mask acknowledgement')
-- 场上已无虫、鬼手仍有6只：外圈不能无休止绕，只拿当前武器走到最近鬼手的可攻击位置。
local firstghost=ent('shadowchanneler',7,8)
w,c,p,boss,setshield,entities=arena(0,0,{firstghost,ent('shadowchanneler',-7,-8)})
p.pos=Vector3(11,0,11);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Scan()
w.cycle={stage='patrol',center=Vector3(0,0,0),corners=Cycle.SidePoints(w,Vector3(0,0,0)),index=1,seen_summon=true}
w:Tick()
assert(w.cycle.approach==firstghost and w.cycle.hand_point and c.point==w.cycle.hand_point,'visit a real ghost instead of waiting at a distant corner')
local handpoint=w.cycle.hand_point;p.pos=handpoint;step(w,.2)
assert(not w.moving and w.mode:find('鬼手已在攻击距离'),'hold near the hand to let boss supply a melee window')
-- 边缘通用回中央不能覆盖已骗A后的撤退，即使开阔度不足。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8,8)})
p.pos=Vector3(10,0,0);p.sanity=.8;p.items={cane};p.hands=cane;w:Tick()
w.lure_until=now+3;w.bait_point=Vector3(11.2,0,0);w.escape_point=Vector3(16,0,0);w.escape_enough=true
w.edge_return=true
local oldclear=R.Clearance;R.Clearance=function()return 5 end
boss.animation='idle';step(w)
assert(not w.mode:find('先离开场地边缘'),'generic edge return never overrides an active cage retreat')
R.Clearance=oldclear
-- 实测172.93：骨牢后离Boss15.57码、离鬼手0.92码，不能继续等Boss追近后才考虑清手。
local fixedhand=ent('shadowchanneler',13,0)
w,c,p,boss,setshield,entities=arena(-2,0,{fixedhand})
p.pos=Vector3(13,0,0);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
fixedhand.tags.notarget=true -- 位置信息可读，交互暂不可用。
w:Scan();w.cycle={stage='patrol',center=Vector3(0,0,0),corners=Cycle.SidePoints(w,Vector3(0,0,0)),index=1,seen_summon=true}
w.state.ready.snare=now+8;w:Tick()
assert(w.cycle.hand_positions[fixedhand] and p.last_equip==amulet and not p.hand_attacks,'locate an unselectable ghost and prepare gear inside the far post-snare window')
p.body=amulet;step(w,.2)
assert(w.cycle.hand==fixedhand and not p.hand_attacks and w.mode:find('等待疯狂'),'equipment acknowledgement alone is not actual insane/targetable confirmation')
p.sanity=0;fixedhand.tags.notarget=nil;step(w,.2)
assert(p.hand_target==fixedhand and p.attack_hand==cane and p.hand_attacks==1,'clear a fixed-position ghost with cane while boss is still far away')
fixedhand.tags.NOCLICK=true;step(w,.2);step(w,.3)
assert(p.last_equip==armour,'confirmed ghost death restores actual original body equipment')
p.body=armour;p.sanity=.8;step(w,.3);assert(not w.sanity_round)
-- 有虫时不使用远距离疯狂窗口；仍用真实普攻，避免停Boss让虫子追上。
w,c,p,boss,setshield,entities=arena(-2,0,{ent('shadowchanneler',13,0),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(13,0,0);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Tick();step(w,.4);w.state.ready.snare=now+8;step(w)
assert(not p.last_equip and not p.hand_attacks,'living worms forbid the distant insanity window')
-- 新策略：实际还在吞食且有食物就继续清；估算CD归零不再让清虫停止。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8,8),ent('stalker_minion1',1,0),ent('stalker_minion2',1,1)})
p.pos=Vector3(2,0,0);p.sanity=.8;p.items={cane};p.hands=cane;boss.animation='taunt2_loop1'
w:Tick();w.state.ready.snare=now;step(w,.8)
assert(w.feast_tail and w.lure_until,'near-ready cage reserves walking distance before unknown full-health feast release')
local oldguard=p.hand_guard;boss.animation='attack1';boss.frame=0;step(w)
assert(not oldguard() and w.snare_run,'actual cage interrupts a queued worm attack even after feeding')
-- 实测164.40：已经站在鬼手旁，Boss追到2.65码普攻；不能先撤3码把手留在身后。
local closehand=ent('shadowchanneler',3.8,0)
w,c,p,boss,setshield,entities=arena(0,0,{closehand,ent('stalker_minion1',-10,-10)})
p.pos=Vector3(2.65,0,0);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Tick();step(w,.4);w.state.ready.snare=now+20
boss.animation='attack';boss.frame=0;step(w)
assert(w.cycle.opening_deadline and p.last_equip==amulet and not w.moving,'real melee start reserves a bounded early ghost strike before outward dodge')
p.body=amulet;p.sanity=0;boss.frame=5;step(w,5/30)
assert(p.hand_target==closehand and p.hand_attacks==1,'confirmed insanity issues ordinary cane attack before boss hit frame')
local sent=p.hand_attacks
boss.frame=13;closehand.tags.NOCLICK=true;step(w,8/30)
assert(w.moving and c.point and c.point:DistSq(boss.pos)>p.pos:DistSq(boss.pos),'confirmed ghost hit immediately hands control back to melee dodge')
for frame=14,32 do
 if w.moving and c.point then
  local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(c:Speed()/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end
 end
 boss.frame=frame;step(w,1/30)
end
assert(math.sqrt(p.pos:DistSq(boss.pos))>=5.15 and p.hand_attacks==sent,'one early strike still exits the protected melee radius before frame32')
-- 装备回执过晚，不能为了清手超过保留的逃跑时间。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',3.8,0),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(2.65,0,0);p.sanity=.8;p.items={cane,amulet,armour};p.hands=cane;p.body=armour
w:Tick();step(w,.4);w.state.ready.snare=now+20;boss.animation='attack';boss.frame=0;step(w)
assert(w.cycle.opening_deadline)
p.body=amulet;p.sanity=0;boss.frame=18;step(w,.6)
assert(not p.hand_attacks and w.moving and not Cycle.OpeningAllowed(w),'late equip acknowledgement forfeits the strike instead of delaying dodge')
-- 圈外的虫子不改变当前吞食目标，圈内仍活着就继续处理。
w,c,p,boss,setshield,entities=arena(0,0,{ent('stalker_minion1',1,0),ent('stalker_minion2',1,1),ent('stalker_minion1',-10,-10),ent('stalker_minion2',10,-10)})
p.pos=Vector3(2,0,0);p.items={cane};p.hands=cane;boss.animation='taunt2_loop1'
w:Tick();w.state.ready.snare=now;step(w,.8)
assert(w.cycle.bugs==4 and w.cycle.feeding==2 and w.lure_until,'safe recovery does not rely on a final-one-worm threshold')
-- 实测272.77：eat_pst第6帧突然看到圈内虫子，不能把收尾撤退取消并往回走。
w,c,p,boss,setshield,entities=arena(0,0,{ent('stalker_minion1',1,0)})
p.pos=Vector3(9.2,0,0);p.sanity=.8;p.items={cane};p.hands=cane;boss.animation='taunt2_loop1'
w:Tick();w.feast_lure=true;w.lure_until=now+3;boss.animation='taunt2_pst';boss.frame=6;step(w)
assert(w.feast_lure and w.lure_until,'food in eat_pst cannot undo the escape before frame8 busy release')
-- 实测114.73：召唤中远处已有4只虫子，但脚下为空时仍要利用召唤定身预留骨牢距离。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8,8),ent('stalker_minion1',-10,-10),ent('stalker_minion2',-10,10)})
p.pos=Vector3(3.48,0,0);p.items={cane};p.hands=cane;p.sanity=.8;boss.animation='summon_loop';boss.frame=60
w:Scan();w.state.ready.snare=now+.63;w:Tick()
assert(w.spawn_lure and w.lure_until and w.moving,'outside summoned worms do not force standing next to boss with snare ready')
entities[#entities+1]=ent('stalker_minion1',1,0);step(w,.2)
assert(w.spawn_lure and w.lure_until,'first approaching worm does not reverse a summon escape')
w.state.ready.snare=now+6;boss.animation='taunt2_pre';step(w,.2)
assert(not w.spawn_lure and not w.lure_until,'actual feast still gives control back to cleanup instead of waiting forever')
-- 实测342.73：远处等鬼手时，骨牢先于Boss下一次贴身普攻就绪。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',10.21,0),ent('stalker_minion1',-10,-10)})
p.pos=Vector3(10.21,0,0);p.sanity=.8;p.items={cane,amulet};p.hands=cane
w:Tick();step(w,.4);w.state.ready.snare=now+.73;boss.animation='walk_loop';step(w)
assert(w.moving and R.Path(w,c.point,nil,true) and w.retreat and w.lure_until,'prepare a legal escape rather than stop for a hand while boss closes to 3.92 yards')
assert(not w.cycle.cage_point or R.SnareExit(w,w.cycle.cage_point,0,15),'a casting band needs an executable exit')
-- 实测205.33：震地距离已安全，但脚下有将落地的骨刺，不能用短撤到位Hold压住局部闪避。
local landing=ent('fossilspike2',5.49,0,'appear',25);landing.duration=1
w,c,p,boss,setshield,entities=arena(0,0,{landing})
p.pos=Vector3(5.49,0,0);p.items={cane};p.hands=cane;boss.animation='spike';boss.frame=42
w:Tick()
assert(w.moving and c.point and p.pos:DistSq(c.point)>.2^2 and w.mode:find('残留骨刺'),'local landing evasion preempts a safe shockwave hold before frame58')
assert(R.Risk(w,c.point)<R.Risk(w,p.pos),'landing escape actually reduces local spike risk')
-- 首轮补救持续清虫；实际清空再准备，而非让估计CD永久阻断清虫。
local many={ent('shadowchanneler',-8,-8)}
for n=1,7 do many[#many+1]=ent('stalker_minion1',1,n*.15) end
w,c,p,boss,setshield,entities=arena(0,0,many)
p.pos=Vector3(2.34,0,0);p.hands=cane;p.items={cane};boss.animation='taunt2_loop1'
w:Scan();w.state.ready.snare=now+6;w:Tick()
assert(p.hand_attacks==1,'known cooldown still permits close cleanup')
local attacks=p.hand_attacks;w.state.ready.snare=now;step(w,.1)
assert(w.feast_tail and w.cycle.feeding==7,'seven-worm feast reserves escape instead of gambling on its remaining health')
step(w,.8)
for i=4,#entities do entities[i].tags.NOCLICK=true end
step(w,.2);assert(w.feast_lure,'confirmed empty feeding circle keeps the recovery retreat active')
attacks=p.hand_attacks
for frame=1,60 do
 if w.moving and c.point then
  local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(c:Speed()/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end
 end
 boss.frame=frame%30;step(w,1/30)
end
assert(math.sqrt(p.pos:DistSq(boss.pos))>=11.55 and p.hand_attacks==attacks,'confirmed cleared feeding circle keeps the safety retreat continuous')
boss.animation='attack1';boss.frame=0;step(w)
assert(w.snare_run.reachable,'prepared waiting band has a conservatively budgeted exit')
-- 加入6帧起步损耗与15%位移折损，仍在25.5帧结算前走出生效圈。
for frame=1,25 do
 if frame>6 and w.moving and c.point then
  local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(c:Speed()*.85/30,d)
  if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end
 end
 boss.frame=frame;step(w,1/30)
end
assert(math.sqrt(p.pos:DistSq(boss.pos))>15,'continuous conservative-budget run crosses the effect radius before resolution')
-- 109.80秒旧预算把10.27码起手到15.7码标作可达；新预算不再报可达。
w,c,p,boss=fixture({ent('stalker_atrium',0,0,'attack1',0)},10.27,0)
w:Tick();assert(not w.snare_run.reachable and w.snare_run.budget<5.43,'reject the observed optimistic deadline')
-- 退路不足的备用线本身和真正执行的整段都不能往Boss/中心折回。
w,c,p,boss=fixture({ent('stalker_atrium',0,0)},8.9,0);w:Scan()
local committed=R.BeginRetreat(w);local outward=committed.points[1];assert(outward:DistSq(boss.pos)>p.pos:DistSq(boss.pos))
w:Move(outward,'test',nil,true)
assert(c.point==outward and R.Path(w,c.point,nil,true),'validated increasing-distance segment bypasses local centre/edge rescoring')
-- 首轮手清空后：先等一次实际共享技能，结束后才去外侧落脚点。
local Round=require('shadowself/control/weaver/round')
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',8,0)})
p.pos=Vector3(9,0,0);p.items={cane,amulet,armour};p.hands=cane;p.body=armour;p.sanity=.8
w:Tick();entities[3].tags.NOCLICK=true;setshield(false);boss.animation='idle';step(w,.4)
assert(w.cycle.round=='wait_skill','actual first shield removal waits for a subsequent skill before corner placement')
boss.animation='spike';boss.frame=0;step(w);boss.frame=62;step(w,62/30)
boss.animation='idle';step(w)
assert(w.cycle.round=='corner' and w.cycle.corner,'observed skill completion starts a legal outer corner approach')
p.pos=w.cycle.corner;boss.pos=Vector3(p.pos.x-2.5,0,p.pos.z);w.state.ready.snare=now+20
boss.animation='idle';step(w)
assert(not p.last_equip and w.mode:find('普攻'),'wait at the outer point without wearing insanity before the real attack')
boss.animation='attack';boss.frame=0;step(w)
assert(not p.last_equip and w.moving and w.cycle.round_dodge==c.point,'actual melee uses a legal adjoining-edge red-circle dodge before control bait')
p.pos=c.point;boss.frame=38;step(w,38/30)
assert(w.cycle.round=='control' and p.last_equip==amulet,'after evasion start the bounded control-bait equipment transaction')
p.body=amulet;p.sanity=0;boss.frame=40;step(w,.1)
assert(w.sanity_round and not w.sanity_round.restoring and w.moving,'acknowledged insanity immediately approaches boss instead of restoring')
p.pos=Vector3(boss.pos.x,0,boss.pos.z+2.6);boss.frame=45;step(w,5/30);assert(c.owns,'in-range control bait resumes native output')
boss.animation='control_pre';boss.duration=2;boss.frame=0;step(w)
assert(c.owns and not w.sanity_round.restoring,'actual control windup is output time')
boss.frame=49;step(w,49/30)
assert(w.sanity_round.restoring and p.last_equip==armour,'restore at the actual windup safety deadline, not on entry')
p.body=armour;p.sanity=.8;boss.animation='control_pst';boss.frame=0;step(w,.2)
boss.animation='idle';step(w,.2)
assert(w.cycle.round=='await_wave' and not w.sanity_round,'completed control does not re-equip insanity')
boss.animation='summon_pre';boss.frame=0;boss.duration=1;step(w)
assert(w.cycle.round=='lap' and w.cycle.stage=='spawn' and w.cycle.route_goal,'new summon plans the route; a short pre cannot borrow unknown future loop lengths')
-- 最后鬼手的实际死亡确认保留护符；仍有其他手则必须恢复原装备。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',3.8,0)})
p.pos=Vector3(2.6,0,0);p.items={cane,amulet,armour};p.hands=cane;p.body=armour;p.sanity=.8
w:Tick();step(w,.4);w.cycle.round='lap';w.cycle.round_since=now;w.state.ready.snare=now+20;boss.animation='attack';boss.frame=0;step(w)
p.body=amulet;p.sanity=0;boss.frame=5;step(w,5/30)
assert(p.hand_attacks==1 and w.cycle.sent,'last ghost strike uses the established real-melee window')
entities[3].tags.NOCLICK=true;setshield(false);boss.frame=13;step(w,8/30)
assert(w.cycle.round=='control' and w.sanity_round and not w.sanity_round.restoring,'confirmed final ghost kill retains this exact amulet into control output')
p.pos=c.point;boss.frame=40;step(w,.9)
assert(w.moving and not w.sanity_round.restoring,'final ghost approaches boss without unequipping the retained amulet')
p.pos=Vector3(2.6,0,0);boss.frame=45;step(w,5/30);assert(c.owns,'final-ghost control output resumes in range')
-- 无血条时控制可能尚未解锁，观察不到起手必须退出诱导，而非永远戴着等。
boss.animation='idle';step(w,3.2)
assert(w.cycle.round=='await_wave' and w.sanity_round.restoring,'unobserved control is bounded and restores original armour')
-- 召唤第一轮的保证后续loop可借用，但不能无限假定还有6轮。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',9,0),ent('stalker_minion1',9,1)})
p.pos=Vector3(9,0,0);p.items={cane,amulet,armour};p.hands=cane;p.body=armour;p.sanity=.8
w:Tick();w.cycle.round='lap';w.cycle.round_since=now;w.state.ready.snare=now+1
boss.animation='summon_pre';boss.duration=1;boss.frame=0;step(w)
boss.animation='summon_loop';boss.duration=2;boss.frame=0;step(w)
assert(w.state.summon_loops==1 and Round.SpawnLeft(w)==4 and not w.lure_until,'only source-guaranteed first extra loop opens a bounded clearing window')
assert(p.hand_target and p.hand_target.prefab=='stalker_minion1','summon window clears the route worm before drifting to a distant centre target')
boss.frame=59;step(w,59/30);boss.frame=0;step(w,.1)
assert(w.state.summon_loops==2 and Round.SpawnLeft(w)==2,'second loop has no fabricated future duration')
-- 首轮实际最后一手死亡也必须等技能->去角落，不能误用后续圈的留护符捷径。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',3.8,0)})
p.pos=Vector3(2.6,0,0);p.items={cane,amulet,armour};p.hands=cane;p.body=armour;p.sanity=.8
w:Tick();step(w,.4);w.state.ready.snare=now+20;boss.animation='attack';boss.frame=0;step(w)
p.body=amulet;p.sanity=0;boss.frame=5;step(w,5/30)
assert(w.cycle.sent,'first final hand has a submitted real strike')
entities[3].tags.NOCLICK=true;setshield(false);boss.frame=13;step(w,8/30)
assert(w.cycle.round=='wait_skill','first final hand must not bypass actual skill and corner preparation')
-- 挥刀已提交但还没命中时，等待不能给自己发STOP。
w,c,p,boss,setshield,entities=arena(0,0,{ent('shadowchanneler',3.8,0),ent('shadowchanneler',-9,0)})
p.pos=Vector3(2.6,0,0);p.items={cane,amulet,armour};p.hands=cane;p.body=armour;p.sanity=.8
w:Tick();step(w,.4);w.state.ready.snare=now+20;boss.animation='attack';boss.frame=0;step(w)
p.body=amulet;p.sanity=0;boss.frame=5;step(w,5/30)
local stops=p.stops or 0;p.busy=true;boss.frame=6;step(w,1/30)
assert((p.stops or 0)==stops,'pending ghost hit must not be cancelled by the wait branch')
-- 大门阻断所有直达角点时，仍能沿分段路径完成转场，不跳回lap等技能。
w,c,p,boss,setshield,entities=arena(-8,-8,{})
p.pos=Vector3(0,0,-5);p.items={cane,amulet};p.hands=cane;w:Scan()
local target=Vector3(0,0,10)
assert(not R.Path(w,target,nil,true),'gate must actually obstruct the direct regression route')
local waypoint,total=R.Waypoint(w,target)
assert(waypoint and R.Path(w,waypoint,nil,true) and waypoint:DistSq(target)>.1 and total>15,'segmented route must go around the gate')
local Round=require('shadowself/control/weaver/round')
w.cycle={round='corner',round_since=now,index=1,corners={target,target,target,target}}
assert(Round.Tick(w) and w.cycle.round=='corner' and w.cycle.corner_waypoint,'blocked chord retains corner preparation and submits a real waypoint')
for _=1,240 do
    if c.point and w.moving then
        assert(R.Path(w,c.point,nil,true),'every submitted corner segment must remain legal')
        local d=math.sqrt(p.pos:DistSq(c.point));local n=math.min(d,5.1/30)
        if d>.001 then p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*n/d,0,p.pos.z+(c.point.z-p.pos.z)*n/d) end
    end
    now=now+1/30;Round.Tick(w)
    if p.pos:DistSq(target)<=1.2^2 then break end
end
assert(p.pos:DistSq(target)<=1.2^2 and w.cycle.round=='corner','walk the complete obstructed transition instead of merely selecting a waypoint')
-- 当前一侧边界不足：即使地图别处存在远点，也不能把这个识别带标为可逃。
boss.pos=Vector3(0,0,0);p.pos=Vector3(11.9,0,0);w.bodies={};w.avoid_boss=nil
w.escape_point=Vector3(13,0,13);w.escape_enough=true;w.bait_point=Vector3(11.9,0,0)
assert(not R.SnareExit(w,w.bait_point,0,15) and not R.BaitValid(w,12,15),'far endpoint cannot stand in for an executable exit from the band')
local route=R.BeginRetreat(w);local recovery=route.points[1]
assert(recovery and p.pos:DistSq(recovery)>.3^2 and R.Path(w,recovery,nil,true),'wall-side failure commits a legal staging route')
local start=p.pos;local length=math.sqrt(start:DistSq(recovery))
p.pos=Vector3(start.x+(recovery.x-start.x)*.6/length,0,start.z+(recovery.z-start.z)*.6/length);now=now+.2
assert(R.RetreatGoal(w)==recovery,'same committed retreat keeps its effective segment')
-- 转场普攻尚在伤害范围内时，过了动画帧也不能戴疯狂装备开始输出。
w.cycle={round='corner',round_since=now,index=1,corners={target,target,target,target},corner=target}
boss.animation='attack';boss.frame=38;w.state.anim='attack';w.state.frame=38;w.state.melee_started=now-38/30
p.pos=Vector3(3.5,0,0)
Round.Tick(w);assert(w.cycle.round=='corner','late frame alone is not evidence that the melee was successfully evaded')
if read_source then
 local src=read_source('prefabs/staff_lunarplant.lua')
 assert(src:find('SetRange(8, 10)',1,true) and src:find('SetProjectile("brilliance_projectile_fx")',1,true))
 local sg=read_source('stategraphs/SGstalker.lua'):gsub('\r','')
 assert(sg:find('FindMinions(5)',1,true) and sg:find('FrameEvent(8, function(inst) inst.sg:RemoveStateTag("busy") end)',1,true),'feast waits for a wider food circle and releases busy early in its post animation')
 assert(sg:find('FrameEvent(63, function(inst)\n                inst.sg:RemoveStateTag("busy")',1,true),'ghost transaction budget must track the actual melee busy release')
end
for k,v in pairs(globals)do _G[k]=v end
for _,k in ipairs({'Class','GetTime','Vector3','TheSim','TheWorld','TUNING','EQUIPSLOTS','ACTIONS'})do if globals[k]==nil then _G[k]=nil end end
for _,n in ipairs({'actions','incoming','weaver/observe','weaver/route','weaver/debug','weaver/sanity','weaver/cycle','weaver/round','weaver/ranged','weaver/phase1','weaver/controller'})do local k='shadowself/control/'..n;package.loaded[k]=saved[k] end
print('PASS: phase2 actual spawn, feeding recovery, staff attacks, stable duplicates, one-ghost busy window, prompt restore, cage priority and native output')

