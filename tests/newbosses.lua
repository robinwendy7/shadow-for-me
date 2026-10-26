package.path="./scripts/?.lua;"..package.path
local saved,globals={},{}
for _,key in ipairs({"Class","GetTime","Vector3","TheWorld","TheSim","TheNet","TUNING","FRAMES","EQUIPSLOTS","ACTIONS"}) do globals[key]=_G[key] end
for _,key in ipairs({"geometry","rocky","bat","charlie","shrouden","escape","beam","debug","controller"}) do
    local name="shadowself/control/newbosses/"..key;saved[name]=package.loaded[name];package.loaded[name]=nil
end
local actionkey="shadowself/control/actions";saved[actionkey]=package.loaded[actionkey]
local navkey="shadowself/control/navigation";saved[navkey]=package.loaded[navkey]
Class=function(ctor) local c={};c.__index=c;return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end}) end
local now=100;GetTime=function() return now end;FRAMES=1/30;TUNING={ROCKY_BOSS_SCALE=1.4}
Vector3=function(x,y,z) return {x=x,y=y,z=z,DistSq=function(a,b) return (a.x-b.x)^2+(a.z-b.z)^2 end} end
EQUIPSLOTS={HEAD="head",HANDS="hands"};ACTIONS={UNEQUIP={},EQUIP={},BLINK={}}
local sequence=0
local function entity(n,x,z,a,f,r)
    sequence=sequence+1
    local e={prefab=n,pos=Vector3(x,0,z),animation=a or "idle",frame=f or 0,rotation=0,GUID=sequence,replica={}}
    function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags and self.tags[t] or false end
    function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return r or .9 end
    e.Transform={GetRotation=function() return e.rotation end}
    e.AnimState={IsCurrentAnimation=function(_,name) return name==e.animation end,GetCurrentAnimationFrame=function() return e.frame end}
    return e
end
local all={};TheSim={FindEntities=function() return all end};TheWorld={};TheNet={GetPing=function() return 22 end}
package.loaded[navkey]={Clearance=function() return 8 end,Radius=function() return 3 end}
local unhat,stopped=0,0
package.loaded[actionkey]={Stop=function() stopped=stopped+1 end,
    Items=function(p) return p.items or {} end,
    Ground=function(p,point,act,guard)
        assert(act==ACTIONS.BLINK and guard());p.castpoint=point;p.casts=(p.casts or 0)+1
        return not p.reject_blink
    end,
    Self=function(p,item,act)
        if act==ACTIONS.UNEQUIP then unhat=unhat+1
        else assert(act==ACTIONS.EQUIP);p.equips=(p.equips or 0)+1;p.equipitem=item end
        return true
    end}
local G=require("shadowself/control/newbosses/geometry")
require("shadowself/control/newbosses/debug").Configure(false)
local New=require("shadowself/control/newbosses/controller")
local function fixture(target,entities)
    now=now+1;all=entities or {target}
    local p=entity("wilson",3.5,0,"idle",0,.5);local head,hand
    p.replica.inventory={GetEquippedItem=function(_,slot) if slot=="head" then return head else return hand end end}
    p.components={playercontroller={IsBusy=function() return p.busy or false end}}
    local c={player=p,h={ent=target},enemies=entities or {target},observed={},hazards={},snapshot={},moves=0,begins=0,ends=0,pauses=0}
    c.actions={SafePoint=function(_,v) return not c.coast or v.z<c.coast end}
    c.gear={AttackRange=function() return 2 end}
    c.bridge={PauseAttack=function() c.pauses=c.pauses+1 end}
    c.travel={BeginDodge=function() c.begins=c.begins+1 end,EndDodge=function() c.ends=c.ends+1 end}
    function c:Speed() return 7.5 end;function c:Latency() return .122 end
    function c:Move(q) self.point=q;self.moves=self.moves+1 end
    local n=New(c);c.newbosses=n
    return n,c,p,function(value) head=value end,function(value) hand=value end
end
-- 几何不是统一圆形：长条前后轴危险，侧方近处安全；矩形/三角均有体积填充。
local e=entity("rocky_boss_shadow",0,0,"atk_snip");local shapes={}
require("shadowself/control/newbosses/rocky").Build({},e,shapes,{},.75)
assert(G.Risk(shapes,Vector3(10,0,0))>0 and G.Risk(shapes,Vector3(-4,0,0))>0)
assert(G.Risk(shapes,Vector3(3.5,0,3))==0)
local n,c,p=fixture(e);assert(n:Tick() and c.point and n:Blocked(e))
assert(G.Risk(n.shapes,c.point)<G.Risk(n.shapes,p.pos),"dodge reduces actual hitbox risk")
p.pos=c.point;now=now+.1;n:Tick();local exits=c.ends
e.frame=20;now=now+.1;assert(not n:Tick() and not n:Blocked(e) and c.ends==exits+1,"snip ends -> original attack restored once")
e.animation="atk_dash";e.frame=1;p.pos=Vector3(5,0,0);now=now+.1
assert(n:Tick() and c.point);p.pos=c.point
e.frame=22;now=now+.1;local before=c.ends
assert(n:Tick() and c.ends==before,"inter-dash pause cannot restore weapon/attack")
e.rotation=90;e.frame=0;now=now+.1;n:Tick()
local st=n.states[e];assert(st.chain==2 and st.direction[2]<-.99,"new dash same animation reset updates direction")
e.animation="idle";now=now+.1;n:Tick();assert(not n:Holding())
-- 蝙蝠扑咬与扑空前5帧仍危险；同时检查另一只，而非只看当前输出目标。
local bat=entity("bat_boss_shadow",0,0,"hair_attack_fail",4)
n,c,p=fixture(bat);p.pos=Vector3(1.5,0,0);assert(n:Tick() and n:Blocked(bat))
bat.frame=11;now=now+.1;assert(not n:Tick() and not n:Blocked(bat))
local clone=entity("bat_boss_shadow",0,0,"hair_attack",0);bat.pos=Vector3(10,0,10);bat.animation="idle"
n,c,p=fixture(bat,{bat,clone});p.pos=Vector3(3,0,0);assert(n:Tick() and n:Blocked(bat),"off-target clone preempts attacks")
local sethead;n,c,p,sethead=fixture(bat);sethead(clone)
local count=unhat;assert(n:Tick() and unhat==count+1);n:Tick();assert(unhat==count+1,"unequip requests throttled until acknowledgement")
sethead(nil);now=now+.6;n:Tick();assert(not n:Holding())
assert(c.bridge.priority_target==bat,"focus one real bat while still evading both")
n:Stop();assert(not c.bridge.priority_target,"stop releases only its own focus")
-- 女王藤蔓范围跨整个19..39帧；反弹只能从客户端动画推断，不读取canreflect字段。
local queen=entity("charlie_boss",0,0,"aoe",38)
n,c,p=fixture(queen);p.pos=Vector3(5,0,0);assert(n:Tick() and n:Blocked(queen))
queen.frame=40;now=now+.1;assert(not n:Tick() and not n:Blocked(queen))
local ranged=entity("slingshot",0,0);ranged.tags={slingshot=true};local melee=entity("sword_lunarplant",0,0);melee.tags={weapon=true}
queen.animation="air_cast";queen.frame=23;now=now+.1;n:Scan()
assert(not n:WeaponAllowed(ranged) and n:WeaponAllowed(melee))
queen.animation="vine_cast";now=now+.1;n:Scan();assert(n:WeaponAllowed(ranged))
-- FX/CLASSIFIED实体没有_combat，照样识别；危险消失后不继续封路。
local missile=entity("charlie_boss_projectile",3,0);missile.tags={CLASSIFIED=true};missile.pos.y=1
queen.pos=Vector3(20,0,20);queen.animation="idle";n,c,p=fixture(queen,{queen,missile});p.pos=Vector3(3,0,0)
assert(n:Tick() and #n.shapes>0)
missile.pos.y=5;now=now+.1;n:Tick();assert(#n.shapes==0)
local minion=entity("charlie_boss_minion2",3,0,"charlie_atk",15);all={queen,minion};now=now+.1;n:Scan();assert(#n.shapes>0)
minion.frame=16;now=now+.1;n:Scan();assert(#n.shapes==0,"impact+3 ends real minion hit checks")
local vines=entity("charlie_boss_vines",3,0);all={vines};now=now+.1;n:Scan();assert(#n.shapes>0)
vines._emerged={value=function() return true end};now=now+.1;n:Scan();assert(#n.shapes==0)
-- 憎恶光束中心是独立特效，不是Boss脚下；扩宽预动画就预留5码。
local shroud=entity("shrouden",0,0,"idle")
local beam=entity("shrouden_optic_blast_fx",10,0,"beam_wide_pre")
n,c,p=fixture(shroud,{shroud,beam});p.pos=Vector3(10,0,0)
assert(n:Tick() and c.point and G.Risk(n.shapes,c.point)<G.Risk(n.shapes,p.pos))
assert(math.abs(n.shapes[1].radius-6.1)<.001 and n.shapes[1].pos.x==10)
beam.animation="beam_wide_pst";now=now+.1;n:Scan();assert(#n.shapes==0)
shroud.animation="teleport_pst";shroud.frame=27;p.pos=Vector3(3.7,0,0);all={shroud};now=now+.1
assert(n:Tick() and n:Blocked(shroud));shroud.frame=29;now=now+.1;assert(not n:Tick())
shroud.animation="optic_blast_pst";shroud.frame=12;now=now+.1;assert(n:Blocked(shroud),"noattack tag removal does not mean landing shock ended")
shroud.frame=19;now=now+.1;assert(not n:Tick() and not n:Blocked(shroud))
shroud.animation="punch_loop";now=now+.1;n:Scan()
assert(G.Risk(n.shapes,Vector3(6,0,0))>0 and G.Risk(n.shapes,Vector3(-2,0,0))==0)
-- 憎恶召唤的墨荒是无敌技能实体，单独避让，不能纳入补刀目标。
local summon=entity("shadowthrall_horns",0,0,"shrouden_jump",0)
summon.tags={NOCLICK=true,notarget=true};shroud.animation="idle"
n,c,p=fixture(shroud,{shroud,summon});assert(New.Unattackable(summon) and n:Tick())
summon.animation="shrouden_jump_pst";now=now+.1;n:Scan();assert(#n.shapes==0)
local spike=entity("charliearena_spike",3.5,0,"spike1_loop")
spike.AnimState.GetMultColour=function() return 1,.5,.5,1 end
all={shroud,spike};now=now+.1;n:Scan();assert(n.shapes[1].radius==3.75)
spike.animation="spike_pst";now=now+.1;n:Scan();assert(#n.shapes==0)
-- 岸线及碰撞体积：不能挑一个终点安全、途中撞过Boss身体的路线。
n,c,p=fixture(e);e.animation="atk_snip";e.rotation=0;p.pos=Vector3(3.5,0,0);c.coast=.2
n:Tick();assert(c.point and c.point.z<.2)
local q=Vector3(-3.5,0,0);assert(n:Path(q)==nil,"cannot pass through physical boss body")
local restores=c.ends;n:Stop();assert(not n:Holding() and c.ends==restores,"stop never queues another equip")
-- 普通战斗严格隔离：即使旧怪正在攻击，新模块也不接管、不发移动。
local deer=entity("deerclops",0,0,"atk",1);n,c,p=fixture(deer);c.observed[deer.GUID]={dodge={}}
assert(not n:Tick() and c.moves==0 and c.pauses==0 and not n:Blocked(deer))
-- 查理必须走出完整判定，不能因短路线稍微降低风险就停在三路攻击中间。
queen.pos=Vector3(0,0,0);queen.animation="castlift";queen.frame=25
n,c,p=fixture(queen);p.pos=Vector3(7,0,0)
assert(n:Tick() and c.point and n:Risk(c.point,.6)==0,"prefer complete escape over a shorter still-hit endpoint")
-- 发射方向在身体停止转向后仍跟踪14帧，每帧最多2度，而非瞬间转向玩家。
queen.frame=8;n,c,p=fixture(queen);p.pos=Vector3(4,0,0);n:Scan()
queen.frame=22;p.pos=Vector3(0,0,-4);now=now+14/30;n:Scan()
assert(math.abs(n.states[queen].cast_rot-28)<.01 and n.shapes[1].finish.z<n.shapes[1].pos.z and queen.rotation==0)
queen.animation="aoe";queen.frame=0;n,c,p=fixture(queen);p.pos=Vector3(5.5,0,0)
assert(n:Tick() and n:Risk(c.point,.6)==0,"counterattack retreats beyond all 6 units plus clearance")
-- 侧路攻击出生圆会伸到身后，不能当成从前方1码开始的矩形。
queen.animation="castlift";queen.frame=22;n,c,p=fixture(queen);n:Scan()
queen.frame=41;p.pos=Vector3(-3,0,0);now=now+19/30;n:Scan()
assert(G.Risk(n.shapes,Vector3(-1,0,3.8))>0 and G.Risk(n.shapes,Vector3(-2.5,0,4))==0)
local predictive=true;local halts=0;c.h.StopPredictWalk=function() predictive=false;halts=halts+1 end
assert(n:Tick() and n:Blocked(queen) and not predictive and halts==1,"frame40 is emission, not end; hold and clear prediction correctly")
queen.frame=57;now=now+16/30;assert(n:Tick() and n:Blocked(queen) and c.ends==0)
queen.frame=60;now=now+3/30;assert(n:Tick() and n:Blocked(queen))
queen.animation="idle";now=now+.05;assert(n:Tick() and n:Blocked(queen),"shot persists after animation changes")
now=now+.2;assert(not n:Tick() and not n:Blocked(queen),"release after final shot and network reserve")
-- 环绕方向保持一致，但不能把选路限制成只朝一侧撞墙。
queen.animation="castlift";queen.frame=0;n,c,p=fixture(queen);p.pos=Vector3(3.5,0,0);n:Scan()
local profile=require("shadowself/control/newbosses/charlie")
profile.Commit(n,Vector3(2,0,4))
assert(n.states[queen].dodge_side==1 and profile.MoveBias(n,Vector3(2,0,-4))>profile.MoveBias(n,Vector3(2,0,4)))
-- 反击在hit第8帧转aoe；利用前置8帧撤离，不等范围攻击动画才离开近身位。
queen.animation="hit";queen.frame=0;queen.replica.health={GetPercent=function() return .9 end,IsDead=function() return false end}
n,c,p=fixture(queen);p.pos=Vector3(2.4,0,0)
assert(n:Tick() and c.point and n:Risk(c.point,.6)==0 and n:Blocked(queen))
queen.replica.health.GetPercent=function() return 1 end
n,c,p=fixture(queen);p.pos=Vector3(2.4,0,0)
assert(not n:Tick(),"above counter unlock health do not retreat on ordinary hit")
queen.replica.health=nil
-- 只看未来终点会漏掉中间扫过的光束；窗口判定覆盖当前到预测时刻整条轨迹。
shapes={};G.Circle(shapes,beam,1,Vector3(0,0,0),30,0)
assert(G.Risk(shapes,Vector3(3,0,0),.2)==0 and G.Window(shapes,Vector3(3,0,0),0,.2)>0)
-- 特效空间查询缺席时使用同步跟随符号，且飞行Boss不是地面实心路障。
shroud.pos=Vector3(0,0,0);shroud.animation="optic_blast_pre2";shroud.frame=0
shroud.AnimState.GetSymbolPosition=function(_,name) assert(name=="optic_blast_fx_follow");return 10,0,0,true end
n,c,p=fixture(shroud);p.pos=Vector3(10,0,0)
assert(n:Tick() and c.point and #n.bodies==0 and n.shapes[1].pos.x==10)
assert(n:Risk(c.point,.6)==0,"beam fallback picks a fully safe landing")
shroud.animation="optic_blast_loop";now=now+.1;p.pos=Vector3(14,0,0);c.point=nil
assert(n:Tick() and c.point and c.point:DistSq(Vector3(10,0,0))>16,"keep moving outside beam edge instead of stop and wait to be caught")
shroud.animation="optic_blast_pre3";now=now+.1;n:Scan();assert(n.shapes[1].radius>6)
shroud.animation="optic_blast_loop";now=now+.1;n:Scan();assert(n.shapes[1].radius>6,"wide radius retained after transition animation")
shroud.AnimState.GetSymbolPosition=nil
-- 连续光束流程：起手就跑，即使已经远离窄光束也不停；接近终点前续路。
shroud.animation="optic_blast_pre1";shroud.frame=0;shroud.pos=Vector3(0,0,0)
n,c,p=fixture(shroud);p.pos=Vector3(20,0,0)
local stops_before=stopped;local renewed=false;local previous_point
for _,phase in ipairs({{"optic_blast_pre1",8},{"optic_blast_pre2",12},{"optic_blast_loop",30},
    {"optic_blast_pre3",10},{"optic_blast_loop",30},{"optic_blast_pst",19}}) do
    shroud.animation=phase[1]
    if phase[1]=="optic_blast_pre2" then shroud.pos=Vector3(p.pos.x,0,p.pos.z) end
    for frame=0,phase[2]-1 do
        shroud.frame=frame;now=now+.1
        local moves,ends=c.moves,c.ends
        assert(n:Tick() and c.moves==moves+1 and c.ends==ends and n:Holding(),"every beam pulse moves, without restoring attack gear")
        assert(stopped==stops_before and c.point and p.pos:DistSq(c.point)>2^2,"never stop or wait at a short waypoint")
        if previous_point and previous_point:DistSq(c.point)>.01 then renewed=true end
        previous_point=c.point
        local d=math.sqrt(p.pos:DistSq(c.point));p.pos=Vector3(p.pos.x+(c.point.x-p.pos.x)*.75/d,0,p.pos.z+(c.point.z-p.pos.z)*.75/d)
    end
end
assert(renewed and c.begins>80,"long running waypoints renewed before arriving")
shroud.frame=19;now=now+.1;local ends=c.ends
assert(not n:Tick() and c.ends==ends+1 and not n.beam_run,"release movement once only after landing attack ends")
-- 特效单独存在也持续跑动；窄光束尚未变宽就已预留5码真实半径。
shroud.animation="idle";beam.animation="beam_basic_loop";beam.pos=Vector3(0,0,0)
n,c,p=fixture(shroud,{beam});p.pos=Vector3(18,0,0)
assert(n:Tick() and c.moves==1 and n.shapes[1].radius>6,"far from narrow beam still keeps running with wide clearance")
-- 前方被岸线封住时选择侧方通路，不冲过地形边界，也不切回等待。
shroud.animation="optic_blast_loop";shroud.pos=Vector3(0,0,0);n,c,p=fixture(shroud);p.pos=Vector3(20,0,0)
c.actions.SafePoint=function(_,q) return q.x<23 end
assert(n:Tick() and c.point and c.point.x<23)
local d=math.sqrt(p.pos:DistSq(c.point));assert(d>=6,"use a continuous side route when forward path reaches edge")
local moves=c.moves;n:Stop();assert(not n.beam_run and not n:Holding() and c.moves==moves,"stop clears beam run without another move")
-- 黑液瞬移只用正常动作；装备确认前不施法，也不并发切手杖或发移动。
local staff1=entity("orangestaff",0,0);local staff2=entity("orangestaff",0,0)
shroud.animation="teleport_loop";local sethand
n,c,p,_,sethand=fixture(shroud);p.pos=Vector3(2,0,0);p.tags={gelblobbed=true};p.items={staff1,staff2}
assert(n:Tick() and p.equipitem==staff1 and c.gear.action_hold and not p.casts and c.moves==0 and c.begins==0)
now=now+.1;p.items={staff2,staff1};assert(n:Tick() and p.equips==1 and not p.casts,"hold the exact chosen staff through delayed ack")
sethand(staff1);now=now+.3;assert(n:Tick() and p.casts==1 and c.gear.action_hold and c.moves==0)
now=now+.2;assert(n:Tick() and p.casts==1 and c.gear.action_hold,"request is not teleport completion")
p.pos=p.castpoint;now=now+.1;assert(n:Tick() and not c.gear.action_hold and not n.gel_escape,"observed displacement releases hand lock")
now=now+.1;n:Tick();assert(p.casts==1,"stale gel tag cannot immediately cast a second time")
-- 取消、装备超时、服务器拒绝施法都释放所有权并回到步行避让。
n,c,p,_,sethand=fixture(shroud);p.pos=Vector3(2,0,0);p.tags={gelblobbed=true};p.items={staff1}
n:Tick();n:Stop();assert(not c.gear.action_hold and not p.casts)
n,c,p=fixture(shroud);p.pos=Vector3(2,0,0);p.tags={gelblobbed=true};p.items={staff1}
n:Tick();now=now+2.1;n:Tick();assert(not c.gear.action_hold and c.moves>0 and not p.casts)
n,c,p,_,sethand=fixture(shroud);p.pos=Vector3(2,0,0);p.tags={gelblobbed=true};sethand(staff1);p.reject_blink=true
n:Tick();assert(p.casts==1 and not c.gear.action_hold and c.moves>0)
-- 遗留黑液地块也能识别，消退地块不再封路；没有瞬移道具时仍持续走位。
local trail=entity("honey_trail_shrouden_fx",2,0,"trail1");trail.Transform.GetScale=function() return 1.25 end
shroud.animation="idle";n,c,p=fixture(shroud,{shroud,trail});p.pos=Vector3(2,0,0)
assert(n:Tick() and c.moves>0 and not c.gear.action_hold)
trail._isfading={value=function() return true end};now=now+.1;n:Scan();assert(#n.shapes==0)
-- 与当前游戏源码对照的关键值，避免把旧Boss的外观当新Boss机制。
for file,terms in pairs({
    ["stategraphs/SGrocky.lua"]={'FrameEvent(12','FrameEvent(17','inst.enraged and 5','hitbox:AddTriangle'},
    ["stategraphs/SGbat.lua"]={'"hair_attack_fail"','FrameEvent(5','TryHat(inst, target)'},
    ["stategraphs/SGcharlie_boss.lua"]={'FrameEvent(19','FrameEvent(39','GetAOEParams(0, 6','FrameEvent(8','FrameEvent(22','canturn and 5 or 2','SpawnMinion(inst, 2, -inst.sg.statemem.sideoffs, 20)'},
    ["stategraphs/SGshrouden.lua"]={'aoeparams.radius = 3.9','FrameEvent(28','local PORTAL_RADIUS = 3.5','PlayAnimation("optic_blast_pre1")'},
    ["prefabs/shrouden_optic_blast.lua"]={'local BEAM_RADIUS_WIDE = 5','optic_blast_fx_follow'},
    ["prefabs/shrouden.lua"]={'local CONTACT_RADIUS = 3.2','local UNCONCATCT_RADIUS = 3.35','"honey_trail_shrouden_fx"'},
    ["prefabs/gelblob_attach_fx.lua"]={'target:AddTag("gelblobbed")','inst.mainblob:set(mainblob)'},
}) do local src=read_source(file);for _,term in ipairs(terms) do assert(src:find(term,1,true),file..":"..term) end end
for key in pairs(package.loaded) do if key:find("shadowself/control/newbosses/",1,true)==1 then package.loaded[key]=nil end end
for key,value in pairs(saved) do package.loaded[key]=value end
for key,value in pairs(globals) do _G[key]=value end
print("PASS: four new bosses; continuous beam run from pre1 through wide/landing, early waypoint renewal and coast reroute; gel blink acknowledgement/fallback; ordinary combat isolation")
