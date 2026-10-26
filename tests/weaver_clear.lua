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


local Clear=require('shadowself/control/weaver/ranged');local S=require('shadowself/control/weaver/sanity')
local A=require('shadowself/control/actions');local oldAttack,oldSelf=A.Attack,A.Self
local hands={ent('shadowchanneler',5,1),ent('shadowchanneler',5,-1),ent('shadowchanneler',6,0)}
local bugs={ent('stalker_minion1',4,2),ent('stalker_minion2',5,2)}
local w,c,p,boss,shield,entities=arena(0,0,{hands[1],hands[2],hands[3],bugs[1],bugs[2]})
p.pos=Vector3(6,0,0);p.sanity=.8
local staff=ent('staff_lunarplant',0,0);local cane=ent('king_cane',0,0);local mask=ent('purpleamulet',0,0)
p.items={staff,cane,mask};p.hands=cane;p.replica.sanity.IsInsane=function()return p.body==mask end
boss.animation='idle' -- no busy animation or estimated cooldown permission is required for staff clearing
local jobs={};local shots=0;local hits=0;local misses=0;local unequips=0
local function later(dt,fn)jobs[#jobs+1]={at=now+dt,fn=fn}end
A.Self=function(actor,item,action)
 if action==ACTIONS.UNEQUIP then unequips=unequips+1 end
 later(.12,function()if action==ACTIONS.UNEQUIP then actor.body=nil elseif item==mask then actor.body=mask else actor.hands=item end end)
 return oldSelf(actor,item,action)
end
A.Attack=function(actor,target,guard)
 local result=oldAttack(actor,target,guard);if not result then return false end
 shots=shots+1
 later(.8,function()
  if not O.Live(target) then return end -- 连续射击的后发弹抵达已死亡目标不算SAN导致的未命中。
  if target.prefab=='shadowchanneler' and not Clear.GhostReady(w,target)then misses=misses+1
  else target.tags.NOCLICK=true;hits=hits+1 end
 end)
 return true
end
local started=now
for i=1,210 do
 now=now+1/30
 if i>=30 and i<62 then boss.animation='attack';boss.frame=i-30 else boss.animation='idle';boss.frame=0 end
 for j=#jobs,1,-1 do if now>=jobs[j].at then local job=table.remove(jobs,j);job.fn()end end
 local dead=true;for _,h in ipairs(hands)do if O.Live(h)then dead=false end end;shield(not dead)
 w:Tick()
 if now-started<2.5 then assert(unequips==0,'staff mode keeps nightmare amulet across consecutive shots and target changes')end
 if i==75 then assert(shots>=2 and not w.lure_until and not w.rebait,'idle phase2 with staff attacks continuously without bait or cage-CD gating')end
 if not w.clear_mode and not w.sanity_round then break end
end
assert(hits>=5 and misses==0 and not w.clear_mode and p.body~=mask,'staff clears ghosts and worms, then restores SAN and returns to boss style')
assert(not w.cycle,'old perimeter/round state machines are not dispatched')
A.Attack,A.Self=oldAttack,oldSelf
-- Control damage deadline is the exception to holding the mask throughout a clear.
local controlhand=ent('shadowchanneler',5,0)
w,c,p,boss,shield,entities=arena(0,0,{controlhand});p.pos=Vector3(6,0,0)
p.items={staff,cane,mask};p.hands=staff;p.body=mask;p.sanity=0
boss.animation='control_pre';boss.duration=4;boss.frame=110;w:Tick()
assert(p.last_unequip==mask and w.clear_control_pause,'actual control deadline restores the mask before damage')
p.body=nil;p.sanity=.8;step(w,.2)
assert(p.last_equip~=mask,'no immediate re-equip during the same control animation')
-- No staff: worms are the only attack focus even when the cage is already ready.
local bug=ent('stalker_minion1',4,1);local hand=ent('shadowchanneler',4,0)
w,c,p,boss,shield,entities=arena(0,0,{bug,hand});p.pos=Vector3(4,0,1);p.items={cane,mask};p.hands=cane;p.sanity=.8
w:Tick();w.state.ready.snare=now;w:Tick()
assert(w.clear_mode=='worms' and w.focus==bug and c.owns and not w.lure_until,'no staff goes directly through native attack to worms, ignoring cage preparation')
boss.animation='attack1';boss.frame=0;step(w)
assert(w.focus==bug and c.owns,'user-approved worm cleanup continues through cage windup')
-- A confirmed prison still uses the actual native blink action and an arena-legal destination.
p.pos=Vector3(8,0,0);local marker=ent('blinkfocus_marker',8,0);all=prison(boss,marker,8,0)
cane._gem={value=function()return 'orangegem' end};boss.frame=27;step(w,.4)
assert(casts>0 and p.castpoint and R.InArena(w,p.castpoint),'actual cage hit still blinks out while clearing worms')
-- After worm death, all hands use the shared cage cooldown, not one hand per boss melee.
bug.tags.NOCLICK=true;all=entities;boss.animation='idle';boss.frame=0;p.pos=Vector3(4,0,0);w.blink_sent=nil
w:Tick();w.state.ready.snare=now+8;step(w)
assert(w.clear_mode=='hands' and p.last_equip==mask,'after worms, a safe cage cooldown immediately starts ghost cleanup')
p.body=mask;p.sanity=0;step(w,.5)
assert(p.hand_target==hand,'no-staff ghost attack does not wait for another boss melee')
local second=ent('shadowchanneler',4,1);entities[#entities+1]=second;hand.tags.NOCLICK=true;step(w,.7)
assert(p.hand_target==second and boss.animation=='idle','same cage cooldown clears another hand without baiting a melee')
second.tags.NOCLICK=true;shield(false);step(w,.7)
assert(not w.clear_mode,'confirmed full clear returns to the original boss plan')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
print('PASS: persistent-amuletted staff clearing from idle; no-staff worms first, hit-only blink, all hands in cage cooldown, then boss style')
