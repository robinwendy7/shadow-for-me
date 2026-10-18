-- 0.12.19：攻击形状、固定落点及每次攻击的侧方检查；物理与网络为模拟。
local now=0;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local uid=0
local function ent(n,x,z)
 uid=uid+1;local e={prefab=n,GUID=uid,pos=Vector3(x or 0,0,z or 0),anim="idle",frame=0,rotation=0,replica={},components={}}
 function e:IsValid() return true end;function e:HasTag() return false end;function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.Transform={GetRotation=function() return e.rotation end};e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end};return e
end
local p=ent("wilson",3,0);local entities={};TheSim={FindEntities=function() return entities end};TheWorld={state={}}
local c={player=p,enemies={},observed={},hazards={},actions={SafePoint=function() return true end},Latency=function() return .15 end}
local boss={c=c,entities={}};local routes=require("shadowself/control/routes")(boss)
-- 主教从预备首帧响应；绑定本只主教的标记，标记继续追踪时再移动，出范围后停住。
local bishop=ent("bishop");bishop.anim="atk2_pre"
local mark=ent("bishop_targeting_fx",3,0);mark.dist={value=function() return 3 end}
local foreign=ent("bishop_targeting_fx",2.8,0);foreign.rotation=90;foreign.dist={value=function() return 6 end}
boss.entities={foreign,mark};local data=routes:Dodge(bishop,false);assert(data and data.noattack)
local q=data:fn();assert(q:DistSq(p.pos)>1 and math.abs(q:DistSq(bishop.pos)-9)<.001)
assert(routes.bishops[bishop].mark.x==3,"do not borrow other bishop's mark")
p.pos=q;assert(data:fn():DistSq(q)>1,"tracking phase must keep moving, never stop at a temporary safe point")
mark.pos=p.pos;mark.rotation=-math.atan2(mark.pos.z,mark.pos.x)*180/math.pi;data=routes:Dodge(bishop,false);q=data:fn();assert(q:DistSq(p.pos)>1)
bishop.anim="atk2_pst";bishop.frame=1;mark.anim="reticule_pst"
local impact=ent("bishop_charge2_fx",mark.pos.x,mark.pos.z);boss.entities={mark,impact};data=routes:Dodge(bishop,false);assert(data and not data.safe(p.pos))
bishop.frame=21;assert(not routes:Dodge(bishop,false),"impact recovery releases dodge")
-- 蚁狮每轮只短移一次，同一时针；离Boss远也不能放大成大圆。
local ant=ent("antlion");ant.anim="attack_pre";p.pos=Vector3(12,0,0)
data=routes:Dodge(ant,false);q=data:fn();assert(q.z<0 and p.pos:DistSq(q)<=2^2,"fixed clockwise short world step")
p.pos=q;assert(not routes:Dodge(ant,false));ant.anim="attack";ant.frame=0;assert(not routes:Dodge(ant,false),"same cast does not request another sidestep")
ant.anim="attack_pre";ant.frame=0;data=routes:Dodge(ant,false);local q2=data:fn();assert(q2.z<q.z and p.pos:DistSq(q2)<=4)
-- 鱼雷位移只能算一次；到点后不能又平移一段。
local shark=ent("sharkboi");shark.anim="torpedo_pre";p.pos=Vector3(3,0,0)
local Shark=require("shadowself/control/sharkroute");data=Shark.Dodge(c,shark,false);q=data:fn();p.pos=q
shark.anim="torpedo_loop";shark.pos=Vector3(2,0,0);assert(Shark.Dodge(c,shark,false):fn():DistSq(q)==0)
shark.anim="idle";assert(not Shark.Dodge(c,shark,false) and not c.shark_torpedo)
-- 攻击前无pending也必须读取侧方墨荒；躲避中不偷换捕获的主目标。
local primary=ent("shadowthrall_wings",5,0);local hand=ent("shadowthrall_hands",-3,0);hand.anim="run_loop";p.pos=Vector3(0,0,0)
entities={primary,hand};local h={ent=primary};c.h=h;c.bridge={allowed=function() return true end,wrappers={IsAttackPre={old=function(_,e) return e==hand and {atkanim="run_loop"} or false end},PreTheLoop={old=function() end}}}
local sec=require("shadowself/control/secondary")(c);assert(not sec.pending)
assert(not sec:BeforeAttack(true) and h.ent==primary and sec.pending==hand,"attack-during-dodge yields without mutating captured target")
sec.pending=nil;assert(not sec:BeforeAttack() and h.ent==hand,"fresh side rush preempts current-target attack even without pending")
hand.anim="idle";now=1;h.ent=primary;assert(sec:BeforeAttack(),"finished attack immediately restores output, no idle crowd fleeing")
local horns=ent("shadowthrall_horns");horns.anim="jump";horns.frame=29;assert(routes:Dodge(horns,false).dist>=3.8)
-- 冰刺长成后不再被当3码持续爆炸，三墨荒弹丸按重力预测降落，落地后解除。
EQUIPSLOTS=EQUIPSLOTS or {HANDS="hands",BODY="body",HEAD="head"}
local Boss=require("shadowself/control/bosses");local B=Boss(c);local spike=ent("sharkboi_icespike",8,0);spike.anim="spike1_pre";spike.frame=0
assert(B:Zones({spike})[1].radius==3);spike.anim="spike1";local z=B:Zones({spike});assert(z[1].radius<1.5,"grown ice is collision only")
local shot=ent("shadowthrall_projectile_fx",0,0);shot.anim="projectile_loop";shot.pos.y=2;now=2;B:Zones({shot})
now=2.1;shot.pos=Vector3(1,1,0);z=B:Zones({shot});assert(#z==1 and z[1].pos.x>1 and z[1].radius>=1.8)
shot.anim="projectile_impact";assert(#B:Zones({shot})==0,"already landed projectile isn't recurring hazard")
assert(not next(B:Zones({})));assert(not next(B.thrall_projectiles),"projectile observations clean up")
print("PASS: 0.12.19 moving bishop marker/source/impact; short fixed-direction ant casts; fixed shark lane; fresh off-target rush interruption; horns landing; grown ice collision; thrall projectile landing and cleanup")
