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




local A=require('shadowself/control/actions');local oldstop=A.Stop
local function scene(bx,bz,px,pz)
 local extras={}
 for _,v in ipairs({{'pillar_atrium',12,-13,2.5},{'pillar_atrium',12,12,2.5},{'pillar_atrium',-12,-13,2.5},
 {'atrium_statue_facing',13,-6,.45},{'atrium_statue_facing',13,6,.45},{'atrium_light',13,0,.45},
 {'atrium_rubble',13,-3,.5},{'atrium_rubble',13,3,.5}})do
  local e=ent(v[1],-570+v[2],-10+v[3]);e.radius=v[4];extras[#extras+1]=e
 end
 local w,c,p,boss,shield,entities=arena(bx,bz,extras);shield(false)
 entities[2].pos=Vector3(-570,0,-10);boss.radius=.75;p.pos=Vector3(px,0,pz)
 w:Scan();w.center=entities[2].pos;w.home=w.center;w.zones={}
 w.fight_corners={Vector3(-556.5,0,-19.95),Vector3(-556.5,0,-1.05)}
 w.phase1={stage='fight',goal=w.fight_corners[2],snares=1,spikes=0,settled=true,followed=true}
 p.hands=ent('king_cane',0,0);p.items={p.hands};c.speed=7.8
 return w,c,p,boss
end
local function replay(rotation,mirror,observe_delay)
local w,c,p,boss=scene(-560.04,-2.57,-557.90,-2.10)
local function transform(v)
 local x,z=(v.x+570)*mirror,v.z+10
 for _=1,rotation do x,z=-z,x end
 return Vector3(x-570,0,z-10)
end
for _,e in ipairs(all)do e.pos=transform(e.pos) end
p.pos=transform(p.pos);w.center=Vector3(-570,0,-10);w.home=w.center
for i,v in ipairs(w.fight_corners)do w.fight_corners[i]=transform(v) end
w.phase1.goal=w.fight_corners[2]
now=65.90;boss.animation='attack';boss.frame=0;c.speed=6
w.state.ready.snare=now
local moving,queued,moveat;local haltcount=0;local moving_halts=0;local commands={};local snapshots={};local owner;local planned=0;local short=0
local emit=Debug.Emit
Debug.Emit=function(_,event,detail)
 if event=='retreat_plan' then planned=planned+1 end
 if event=='corner_side_dodge' then short=short+1 end
end
A.Stop=function()haltcount=haltcount+1;if w.retreat and w.retreat.mode=='prepare' and not w.bait_waited then moving_halts=moving_halts+1 end;moving=nil;queued=nil;moveat=nil end
c.h.StopPredictWalk=function()moving=nil;queued=nil;moveat=nil end
function c:Move(q)
 commands[#commands+1]={at=now,x=q.x,z=q.z}
 if moving then moving=q else queued=q;moveat=moveat or now+.13 end
end
local started=now;local caught=false;local hit=false;local reached=false
for frame=0,100 do
 now=started+frame/30
 if frame>=5 then c.speed=7.8 end
 if frame<=63 then boss.animation='attack';boss.frame=frame
 elseif now<68.23 then
  boss.animation='walk_pre';boss.frame=frame-63
  local bp=boss.pos;local d=math.sqrt(bp:DistSq(p.pos));local n=math.min(d,4.2/30)
  if d>.01 then boss.pos=Vector3(bp.x+(p.pos.x-bp.x)*n/d,0,bp.z+(p.pos.z-bp.z)*n/d) end
 elseif now<68.23+observe_delay then boss.animation='walk_pre';boss.frame=frame-63
 else boss.animation='attack1';boss.frame=math.floor((now-68.23)*30) end
 w:Tick()
 if frame==0 then
  owner=assert(w.retreat,'lure must own a full route before the first movement')
  assert(owner.complete,'the actual corner has a physically valid band and exit; short-dodge fallback is not acceptable')
 end
 if moveat and now>=moveat then moving=queued;queued=nil;moveat=nil end
 if moving then
  local d=math.sqrt(p.pos:DistSq(moving));local n=math.min(d,c:Speed()/30)
  if d>.001 then p.pos=Vector3(p.pos.x+(moving.x-p.pos.x)*n/d,0,p.pos.z+(moving.z-p.pos.z)*n/d) end
 end
 if w.bait_waited then reached=true end
 if frame==32 then hit=p.pos:DistSq(boss.pos)<=4.3^2 end
 if boss.animation=='attack1' and boss.frame>=26 then caught=p.pos:DistSq(boss.pos)<=15^2;break end
 snapshots[#snapshots+1]=string.format('%.2f,%.3f,%.3f,%.3f,%s,%d',now,p.pos.x,p.pos.z,math.sqrt(p.pos:DistSq(boss.pos)),w.mode or '',w.retreat and w.retreat.index or 0)
end
print('RETREAT MODEL',rotation,mirror,observe_delay,'hurt',hit,'caught',caught,'band',reached,'plans',planned,'short',short)
if hit or caught or not reached then print(table.concat(snapshots,'\n')) end
assert(not hit,'same route must clear actual melee hit range')
assert(reached,'reach and wait at the snare band before actual cast')
assert(not caught,'same retreat corridor continues outside real snare range')
assert(short==0,'active lure may never hand direction back to the local short-dodge selector')
assert(planned==1,'without a new physical obstacle one route owns every preparation leg')
assert(moving_halts==0,'moving between route nodes must not send STOP before the waiting band')
Debug.Emit=emit;A.Stop=oldstop
end
for rotation=0,3 do for _,mirror in ipairs({1,-1})do replay(rotation,mirror,0) end end
replay(0,1,.12)
-- A real new obstacle invalidates only this route transaction: replan once, never return to CornerDodge/Reposition.
do
 local w,c,p,boss=scene(-560,-5,-556,-5)
 boss.animation='attack';boss.frame=40;w.state={minions={},phase=1,anim='attack',frame=40,melee_started=now-40/30,ready={snare=now}}
 w.lure_until=now+5;w.lure_attack=w.state.melee_started;w:BeginRetreat()
 local old=assert(w.retreat);local nextpoint=old.points[old.index]
 local block=ent('atrium_statue_facing',(p.pos.x+nextpoint.x)/2,(p.pos.z+nextpoint.z)/2);block.radius=.45
 all[#all+1]=block;w.next_scan=nil
 local shortselector,localreposition=R.CornerDodge,R.Reposition
 R.CornerDodge=function()error('active retreat handed control back to short dodge')end
 R.Reposition=function()error('active retreat handed control back to local reposition')end
 w:Tick()
 R.CornerDodge,R.Reposition=shortselector,localreposition
 assert(w.retreat and w.retreat~=old and not c.owns,'a new physical blocker replans the same owner without resuming attacks')
 assert(c.point and R.Path(w,c.point,nil,true),'replacement route executes a legal checked leg')
end
-- Rooted hand cleanup can move its band only through the same shared route state.
do
 local w,c,p,boss=scene(-560,-5,-556,-5)
 boss.animation='taunt2_loop1';boss.frame=0;w.state={phase=2,anim='taunt2_loop1',frame=0,feasting=true,ready={}}
 w:BeginRetreat();local q=assert(w.retreat)
 local band=q.points[q.band];local exit=q.points[#q.points]
 R.UpdateRetreatBand(w,band,exit)
 assert(w.retreat==q and q.index==q.band and w.bait_point==q.points[q.band] and w.escape_point==q.points[#q.points],'cleanup band and retreat owner cannot retain opposite targets')
end
A.Stop=oldstop
print('PASS: logged65.90 melee -> complete obstacle corridor -> band wait ->68.23 actual snare without owner churn, hurt or cage')
for k,v in pairs(saved)do package.loaded[k]=v end
for k,v in pairs(globals)do _G[k]=v end

