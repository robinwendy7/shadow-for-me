-- 延迟50/80/100ms、普通6移速/手杖7.5，不模拟道路或魔光加速。
local saved={time=GetTime,world=TheWorld,net=TheNet,sim=TheSim};local now=0;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local uid=0
local function ent(n,x,z,radius)
 uid=uid+1;local e={prefab=n,GUID=uid,pos=Vector3(x or 0,0,z or 0),anim="idle",frame=0,rotation=0,replica={},components={},radius=radius or .5}
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius end;function e:IsValid() return true end;function e:HasTag() return false end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end,GetCurrentAnimationLength=function() return 4 end}
 e.Transform={GetRotation=function() return e.rotation end};return e
end
local p=ent("wilson",3.5,0);local ping=80;TheWorld={ismastersim=false,state={}};TheNet={GetPing=function() return ping end};TheSim={FindEntities=function() return {} end}
local c={player=p,enemies={},observed={},hazards={},gear={AttackRange=function() return 2 end},snapshot={},h={},bridge={PauseAttack=function() end},travel={BeginDodge=function() end},actions={SafePoint=function() return true end}}
function c:Latency() return ping/1000+.1 end;function c:Speed() return 6 end;function c:Move(q) self.moved=q end
local QueenAttack=require("shadowself/control/queenattack")
for _,ms in ipairs({50,80,100}) do
 ping=ms;local queen=ent("beequeen",0,0,1.5);queen.anim="atk";queen.frame=0
 assert(QueenAttack(c,queen,false).dist>=6.75)
 queen.frame=14;assert(QueenAttack(c,queen,false))
 queen.frame=15;assert(QueenAttack(c,queen,{old=true})==false,"actual hit resolution overrides stale native fallback immediately")
end
assert(not io.open("scripts/shadowself/control/attackwindow.lua","r"),"generic budget is retired, not patched with another delay")
local boss={c=c};local routes=require("shadowself/control/routes")(boss)
local ant=ent("antlion",0,0,4);p.pos=Vector3(4.6,0,0);ant.anim="cast_pre";ant.frame=5;c.attack_windows=nil
local data=routes:Dodge(ant,false);local q=data:fn()
assert(q.z<0 and q:DistSq(p.pos)>=1.7^2 and q:DistSq(p.pos)<=2.25^2,"body-touching ant gets short tangent, not rejected circular chord")
p.pos=q;assert(not routes:Dodge(ant,false));ant.anim="cast_pst";assert(not routes:Dodge(ant,false))
ant.anim="cast_pre";ant.frame=5;data=routes:Dodge(ant,false);assert(data and data:fn():DistSq(p.pos)>1,"every real cast resets even when same frame is first observed")
c.actions.SafePoint=function() return false end;routes.antlion=nil;data=routes:Dodge(ant,false);assert(data and routes:Dodge(ant,false) and not routes.antlion.done,"no route must not mark this and future casts as completed")
c.actions.SafePoint=function() return true end
-- 侧方预备阶段已经抢占，不等冲刺本体碰到近身圆。
local Incoming=require("shadowself/control/incoming");local primary=ent("bishop",5,0);local rook=ent("rook",-7,0);rook.anim="atk_pre";rook.frame=10
c.h.ent=primary;p.pos=Vector3(0,0,0);local point=Incoming.Point(c,{primary,rook});assert(point and math.abs(point.z)>2,"side charge preempts another target's attack/dodge before charge starts")
p.pos=Vector3(0,0,3);local walking_target=ent("hound",0,-4)
assert(Incoming.Risk(Incoming.Lane(c,rook),p.pos)==0 and Incoming.ApproachBlocked(c,{rook},walking_target),"currently outside lane cannot start walking into it to attack A")
-- 熊獾坑：真实源码半径3，单怪走位也绕开；Boss在坑里不攻击，先引出。
local B=require("shadowself/control/bosses");local b=B(c);local hole=ent("bearger_sinkhole");local bear=ent("mutatedbearger");p.pos=Vector3(6,0,0)
local zones=b:Zones({hole});assert(zones[1].bearger_pit and zones[1].radius>=3.8)
c.hazards=zones;assert(b:AttackBlocked(bear));local mode=b:Bearger(bear);assert(mode=="move" and c.moved:DistSq(hole.pos)>10^2)
bear.pos=Vector3(9,0,0);assert(not b:Bearger(bear) and not b:AttackBlocked(bear));c.hazards={}
-- 单怪原生路线也必须使用坑洞禁区，而非仅群怪时才检查。
c.hazards=zones;bear.pos=Vector3(5,0,0);p.pos=Vector3(6,0,0)
c.bridge.allowed=function() return true end;c.bridge.wrappers={IsAttackPre={old=function() return false end},PreTheLoop={old=function() end}}
local sec=require("shadowself/control/secondary")(c)
local native={atkanim="atk",dist=3,fn=function() return Vector3(2,0,0) end}
local wrapped=sec:Wrap(bear,native);assert(wrapped~=native)
local safe=wrapped:fn();assert(safe:DistSq(hole.pos)>=zones[1].radius^2,"solo bear sidestep cannot enter its slow pit")
c.hazards={}
local oldN=require("shadowself/native").context;require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local crystal=ent("mutateddeerclops");crystal.anim="throw";crystal.frame=30;p.pos=Vector3(8,0,0);b:Crystal(crystal)
assert(c.moved.x>=8-.001 and math.abs(c.moved.z)>5,"first ice spike never approaches boss; lateral or away only")
-- 附身炸弹更早动；未临爆的地面蘑菇依旧允许输出。
local bomb=ent("sporebomb");bomb._shadowself_bomb_owner=p;bomb.components.timer={GetTimeLeft=function() return 1.1 end}
assert(#b:Zones({bomb})==1 and b.bomb_imminent==bomb)
bomb.components.timer.GetTimeLeft=function() return 1.8 end;assert(#b:Zones({bomb})==0)
local mushroom=ent("mushroombomb");mushroom.anim="explode_pre";mushroom.frame=0;p.pos=Vector3(0,0,0)
assert(#b:Zones({mushroom})==0);mushroom.frame=30;assert(#b:Zones({mushroom})==1,"leave early enough to exit before earliest random explosion")
require("shadowself/native").context=oldN
GetTime,TheWorld,TheNet,TheSim=saved.time,saved.world,saved.net,saved.sim
print("PASS: 50/80/100ms queen actual-hit release and retired generic budget; true ant cast reset/body-safe tangent/blocked retry; side pre-charge; bear pit lure; first crystal lateral; earlier distinct bomb timing")
