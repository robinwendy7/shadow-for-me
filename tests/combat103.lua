local oldvec,oldtime,oldent=Vector3,GetTime,ENT_util
local now=10;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local function entity(prefab,x,z,id)
 local e={prefab=prefab,pos=Vector3(x,0,z),GUID=id,tags={}}
 function e:IsValid() return true end;function e:HasTag(tag) return self.tags[tag] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=entity("wilson",1,0,1);p.components={playercontroller={}};local foe=entity("rook",0,0,2);foe.anim="atk"
foe.AnimState={IsCurrentAnimation=function(_,a) return foe.anim==a end};foe.Transform={GetRotation=function() return 0 end}
ENT_util={GetAnimation=function(e) return e.anim end,GetAngle=function() return 0 end}
local c={player=p,enemies={foe},hazards={},observed={},actions={SafePoint=function() return true end}}
local charge=require("shadowself/control/charge");local data=charge(c,foe)
local endpoint=data:fn();p.pos=Vector3(1,0,1)
assert(charge(c,foe)==data and data:fn()==endpoint,"same charge retains exact endpoint and side after player movement")
local Co=require("shadowself/control/coordinator");c.h={ent=foe}
assert(Co.SafeMovePoint(c,endpoint)==endpoint,"generic group direction sampler cannot bend charge sidestep")
-- Execute the actual installed 3014 DoDodge, not a reimplementation.
p.pos=Vector3(1,0,0);local requests={};local frames=0;local closed=0
local h={ent=foe,pos=foe.pos,ppos=p.pos,ShouldAtkWhenDodging=function() return false end,
 CancelDodgingAtk=function() end,CloseAndAttack=function() closed=closed+1 end}
h.IsAttackPre=function() return charge(c,foe) end
function p:PushEvent() end
local env=setmetatable({GLOBAL={DEGREES=math.pi/180},HitAndRun=h,ThePlayer=p,FRAMES=1/30,
 FunctionOrValue=function(v,...) return type(v)=="function" and v(...) or v end,
 distsq=function(a,b) return a:DistSq(b) end,
 POS_util={GoToPoint=function(_,x,z)
   requests[#requests+1]=Vector3(x,0,z)
   local dz=z-p.pos.z;p.pos=Vector3(x,0,p.pos.z+math.min(1,math.max(-1,dz)))
 end},
 Sleep=function() frames=frames+1;if frames==8 then foe.anim="idle" end end},{__index=_G})
local raw=read_3014_dodge();local stop=assert(raw:find("\n\tlocal initidlelist",1,true))
local load=assert(loadstring(raw:sub(1,stop-1).."\nend"));setfenv(load,env);load()
h:DoDodge(data)
assert(#requests==3 and closed==1,"clear charge lane returns immediately to chase instead of waiting full animation")
for _,q in ipairs(requests) do assert(q.x==endpoint.x and q.z==endpoint.z,"native 3014 gets a single straight fixed sidestep, never a moving ring") end
-- Rook grants the early windup to original attacks; dodge only near charge.
p.pos=Vector3(2,0,0);foe.anim="atk_pre"
local oldnet=TheNet;TheNet={GetPing=function() return 0 end}
assert(charge(c,foe,false)==false,"early windup does not suppress native attacks")
now=now+.4;assert(charge(c,foe,false)==false,"normal second swing can begin before sidestep")
now=now+.36;local early=charge(c,foe,false)
assert(early and early:fn().x==2 and math.abs(early:fn().z)==4,"late windup chooses perpendicular endpoint")
p.pos=Vector3(2,0,1);assert(charge(c,foe,false)==early,"late windup retains fixed endpoint")
foe.anim="paw_loop";assert(charge(c,foe,false),"late paw_loop stays in dodge phase")
foe.anim="atk";assert(charge(c,foe,false),"actual ram always dodges immediately")
foe.anim="idle";assert(charge(c,foe,false)==false,"idle resets windup")
foe.anim="atk_pre";assert(charge(c,foe,false)==false,"next charge grants a fresh attack window")
TheNet.GetPing=function() return 250 end;now=now+.51
assert(charge(c,foe,false),"high latency shortens punish window instead of forcing two hits")
foe.anim="idle";charge(c,foe,false);TheNet=oldnet
-- Queen needs radial range, not a sideways/cone dodge; hit occurs at frame 14.
local frame=0;local queen={AnimState={IsCurrentAnimation=function(_,a) return a=="atk" end,GetCurrentAnimationFrame=function() return frame end}}
local qattack=require("shadowself/control/queenattack")
local qdata=qattack(c,queen,false)
assert(qdata.point=="target" and qdata.angle==0 and qdata.dist>=6.75,"queen retreat exits native six-unit targeted hit range")
frame=13;assert(qattack(c,queen,false)==qdata,"one native dodge table until hit frame")
frame=14;assert(qattack(c,queen,false)==false,"queen recovery returns to native attack without waiting for the whole animation")
-- Interrupted equip acknowledgements cannot stall after the native hit state.
local state="hit";p.AnimState={IsCurrentAnimation=function(_,a) return state==a end}
c.gear={pending={untiltime=now+1.2},next_request=100};c.next_move=100;c.last_action_kind="attack";c.attack_until=100
Co.HitRecovery(c);assert(not c.gear.pending and c.gear.next_request==now and c.next_move==nil and c.hit_active)
c.gear.pending={item="new"};Co.HitRecovery(c);assert(c.gear.pending,"same hurt animation does not repeatedly invalidate a new request")
state="idle";Co.HitRecovery(c);assert(not c.hit_active,"native hit recovery resumes immediately with no extra timer")
-- Health drop catches hurt animations missed while the original coroutine yields.
local hp=.9;p.replica={health={GetPercent=function() return hp end}}
Co.HitRecovery(c);c.gear.pending={untiltime=now+1.2};c.gear.failed={weapon=now+3}
hp=.8;now=now+.033;Co.HitRecovery(c)
assert(not c.gear.pending and next(c.gear.failed)==nil,"actual health drop releases stale equip wait even with no hit animation visible")
-- Unsafe attack windows issue an escape instead of silently vetoing all actions.
local secondary=entity("hound",-1,0,3);p.pos=Vector3(0,0,0);foe.pos=Vector3(1,0,0)
c.enemies={foe,secondary};c.observed={[3]={dodge={}}};c.bridge={allowed=function() return true end}
c.tactics={SafeWindow=function() return false end};c.blocked=false
c.gear={AttackRange=function() return 2 end};c.Move=function(_,point) c.moved=point end
setmetatable(c,{__index=Co})
assert(not c:PermitAttack() and c.moved and c.moved:DistSq(p.pos)>0,"unsafe group window must move, never stand idle")
-- Dense overlap with no monotone-safe path: choose a lower-exposure exit.
local N=require("shadowself/control/navigation");c.enemies={};c.observed=nil
for i=0,7 do local a=i*math.pi/4;c.enemies[#c.enemies+1]=entity("hound",math.cos(a),math.sin(a),10+i) end
local escape=N.Escape(c,Vector3(4,0,0))
assert(escape and N.Risk(c,escape)<N.Risk(c,p.pos),"surrounded player can exit overlapping circles instead of freezing")
-- Idle/recovery entities don't become permanent walls; a real windup does.
c.enemies={secondary};secondary.pos=Vector3(2,0,0);c.observed={[3]={neutral=true}}
assert(not N.Obstructed(c,Vector3(4,0,0)),"idle monster does not ban every approach")
c.observed[3]={dodge={}};assert(N.Obstructed(c,Vector3(4,0,0)),"actual secondary windup still blocks attack path")
-- A reachable recovery target must attack before optional circular gathering.
local packs=0;local scans=0;p.pos=Vector3(0,0,0);foe.pos=Vector3(1,0,0)
p.replica={inventory={GetEquippedItem=function() end}};p.AnimState=nil
local ready=setmetatable({player=p,h={ent=foe},enemies={foe,secondary},hazards={},
 observed={[2]={neutral=true},[3]={neutral=true}},owner={},plan={kind="fight"},
 bridge={allowed=function() return true end,wrappers={PreTheLoop={old=function() end}}},
 actions={SafePoint=function() return true end},
 gear={AttackRange=function() return 2 end,Weapon=function() end},
 beequeen={Tick=function() return false end},Scan=function() scans=scans+1 end,
 tactics={Choose=function() return foe end,SafeWindow=function() return true end,Pack=function() packs=packs+1;return true end}}, {__index=Co})
ready:Pulse();assert(packs==0 and not ready.blocked and ready:PermitAttack(),"reachable safe target is handed to native attack immediately, before gathering")
Vector3,GetTime,ENT_util=oldvec,oldtime,oldent
print("PASS: real 3014 fixed straight charge; interrupted equip/hit recovery; unsafe attack moves; surrounded exit; recovery vs active path")
