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

local A=require('shadowself/control/actions');local oldAttack,oldSelf=A.Attack,A.Self
local function replay(ghost)
 local a=ent(ghost and 'shadowchanneler' or 'stalker_minion1',ghost and 8.4 or 2,0)
 local other=not ghost and ent('stalker_minion2',3,0) or nil
 local extras={a};if other then extras[#extras+1]=other end
 local w,c,p,boss,setshield,entities=arena(0,0,extras)
 p.pos=Vector3(ghost and 5.19 or 8.17,0,0);p.sanity=.675
 local cane=ent('king_cane',0,0);local staff=ent('staff_lunarplant',0,0);local amulet=ent('purpleamulet',0,0)
 p.items={cane,staff,amulet};p.hands=cane
 p.replica.sanity.IsInsane=function()return p.body==amulet end
 function c:Speed()return p.hands==cane and 7.8 or 6 end
 local jobs={};local requests=0;local attacks=0;local hits=0;local misses=0;local canceled=0;local submitted
 local function later(dt,fn)jobs[#jobs+1]={at=now+dt,fn=fn}end
 c.travel.BeginDodge=function()
  c.dodging=true
  if p.hands~=cane then later(.12,function()p.hands=cane end)end
 end
 A.Self=function(actor,item,action)
  requests=requests+1
  later(.12,function()
   if action==ACTIONS.UNEQUIP then p.body=nil
   elseif item==amulet then p.body=item else p.hands=item end
   p.sanity=p.body==amulet and 0 or .675
  end)
  return oldSelf(actor,item,action)
 end
 A.Attack=function(actor,target,guard)
  if not oldAttack(actor,target,guard)then return false end
  attacks=attacks+1;submitted=submitted or now
  local weapon=actor.hands
  later(.03,function()if not guard()then canceled=canceled+1 end end) -- real preview guard runs again before send
  later(8/30+math.sqrt(actor.pos:DistSq(target.pos))/15+.12,function()
   if weapon~=staff or ghost and not Flight.GhostReady(w,target) then misses=misses+1
   else hits=hits+1;target.tags.NOCLICK=true end
  end)
  return true
 end
 if ghost then boss.animation='attack';boss.frame=14 else boss.animation='taunt2_loop1';boss.duration=32/30 end
 w:Scan();w.state.ready.snare=now+8
 local started=now
 for i=1,95 do
  now=now+1/30
  if ghost then boss.frame=14+math.floor((now-started)*30);if boss.frame>=63 then boss.animation='walk_pre';boss.frame=0 end
  else
   boss.frame=math.floor((now-started)*30)%32
   -- Different food becomes closest to Boss on the very next scan, as in 122.23~122.93.
   if i==3 then other.pos=Vector3(.8,0,0) end
  end
  for j=#jobs,1,-1 do if now>=jobs[j].at then local job=table.remove(jobs,j);job.fn()end end
  w:Tick()
  if hits>0 then break end
 end
 A.Attack,A.Self=oldAttack,oldSelf
 assert(submitted and hits>0 and misses==0 and canceled==0,ghost and 'post-melee staff+mask sequence must actually land, not restore before ATTACK' or 'changing food rank cannot steal the committed staff shot')
 assert(requests<=(ghost and 3 or 1),'one action cannot oscillate staff/cane/amulet equipment')
 if ghost then assert(attacks==1,'one ghost projectile is submitted and confirmed before a second request')end
 return attacks,hits,requests
end
local a,h,e=replay(true);print('STAFF REPLAY ghost: attacks='..a..' hits='..h..' equips='..e)
a,h,e=replay(false);print('STAFF REPLAY worm: attacks='..a..' hits='..h..' equips='..e)
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end
print('PASS: logged staff/amulet preparation and changing food selection with delayed acknowledgements, deferred guard and actual impact SAN')
