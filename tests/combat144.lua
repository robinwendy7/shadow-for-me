-- 只按实际状态决定输出/躲避；不再用通用冷却预算假定Boss随时攻击。
local savedA=package.loaded["shadowself/control/actions"];local Native=require("shadowself/native");local savedN=Native.context
local now=0;GetTime=function() return now end;FRAMES=1/30;EQUIPSLOTS={HANDS="hands",BODY="body",HEAD="head"};ACTIONS={ATTACK={},WALKTO={},EQUIP={}}
TUNING={KLAUS_HIT_RANGE=3,BEEQUEEN_HIT_RANGE=6};TheWorld={ismastersim=false,state={}}
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local uid=0
local function ent(n,x,z)
 uid=uid+1;local e={prefab=n,GUID=uid,pos=Vector3(x or 0,0,z or 0),anim="idle",frame=0,rotation=0,replica={},components={}}
 function e:IsValid() return true end;function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end;function e:HasTag() return false end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return e.rotation end};return e
end
local p=ent("wilson",3,0);local held={};local items={};local entities={}
p.replica.inventory={GetEquippedItem=function(_,slot) return held[slot] end};p.components.playercontroller={IsBusy=function() return false end};p.entity={}
TheSim={FindEntities=function() return entities end}
package.loaded["shadowself/control/actions"]={Items=function() return items end,Self=function(_,item) held.body=item;return true end}
Native.context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local c={player=p,hazards={},enemies={},observed={},gear={},snapshot={},h={},bridge={PauseAttack=function() end},actions={SafePoint=function() return true end},travel={BeginDodge=function() end,EndDodge=function() end}}
function c:Move(q) self.moved=q end
local B=require("shadowself/control/bosses");local b=B(c);c.bosses=b
local dragon=ent("dragonfly");c.h.ent=dragon
for _,name in ipairs({"hit_large","sleep_loop","hit_ground"}) do
 dragon.anim=name
 for i=1,10 do assert(b:Tick(dragon)=="attack" and b:HoldPosition(dragon) and b:Dodge(dragon,{old_idle_fallback=true})==false,"grounded dragon stays a continuous damage window") end
end
dragon.anim="idle";assert(not b:HoldPosition(dragon));local sentinel={native=true};dragon.anim="atk";assert(b:Dodge(dragon,sentinel)==sentinel,"native dynamic dragon calculate owns attack timing, no fixed early radial override")
-- Planar hit window after butt: pit avoidance must yield to the real punish opportunity.
local bear=ent("mutatedbearger");bear.anim="butt_pst";bear.frame=20
local hole=ent("bearger_sinkhole");c.hazards={{pos=hole.pos,radius=3.85,bearger_pit=true}}
assert(b:Bearger(bear)=="move" and b:AttackBlocked(bear),"no planar weapon keeps pit lure")
local sword=ent("sword_lunarplant");items={sword};assert(b:Bearger(bear)=="attack" and c.gear.forced_weapon==sword and not b:AttackBlocked(bear) and b:HoldPosition(bear) and b:Dodge(bear,{old_butt=true})==false,"actual planar inventory permits early approach and hit in pit")
bear.anim="butt_face_hit";bear.frame=10;assert(b:Bearger(bear)=="attack")
bear.anim="stagger_loop";assert(b:Bearger(bear)=="attack")
bear.anim="idle";assert(b:Bearger(bear)=="move" and not c.gear.forced_weapon,"ordinary pit lure resumes after vulnerability")
c.hazards={}
-- Whole chomp owned by one policy: ready bone -> wait for shield/35 -> outward exit -> both claws.
local armor=ent("armorskeleton");armor.replica.equippable={EquipSlot=function() return EQUIPSLOTS.BODY end};armor.components.cooldown={IsCharged=function() return true end}
held.body=armor;items={armor};local savedM=package.loaded["shadowself/control/mechanisms"];package.loaded["shadowself/control/mechanisms"]=nil;local M=require("shadowself/control/mechanisms");local m=M(c);c.mechanisms=m
local klaus=ent("klaus");klaus.anim="attack_chomp";local oldpush={dist=0,point="target",oldpush=true}
for _,f in ipairs({0,10,20,26,34,35}) do klaus.frame=f;now=f/30;assert(m:Dodge(klaus,oldpush)==false and m.tanking_chomp==klaus,"charged armor holds and attacks instead of falling back to push-in") end
m.bone_consumed=now;local data=m:Dodge(klaus,oldpush);assert(data~=oldpush and data.noattack and data.exclusive and not m.tanking_chomp)
p.pos=Vector3(3,0,0);local q=data:fn();assert(q.x>=p.pos.x and q:DistSq(klaus.pos)>=5^2,"shield consumption starts pure outward exit")
klaus.frame=49;assert(m:Dodge(klaus,oldpush).noattack)
klaus.anim="attack_doubleclaw";for _,f in ipairs({15,16,26,27,28}) do klaus.frame=f;assert(m:Dodge(klaus,oldpush).noattack,"hold through both actual claw hits") end
klaus.frame=29;assert(m:Dodge(klaus,oldpush)==false)
held.body=nil;items={};m=M(c);klaus.anim="attack_chomp";klaus.frame=0
assert(m:Dodge(klaus,oldpush).noattack,"without charged armor, outward dodge replaces old push-in for entire chomp")
-- Bishop continuously moves during tracking; simulate speed7.5, never teleport straight to the goal.
local bishop=ent("bishop");local mark=ent("bishop_targeting_fx",3,0);p.pos=Vector3(3,0,0);b.entities={mark};c.hazards={};c.enemies={}
local track=.5;local moved=0
for tick=0,29 do
 bishop.anim=tick<8 and "atk2_pre" or "atk2_loop";bishop.frame=tick<8 and tick or tick-8
 mark.dist={value=function() return math.sqrt(mark.pos:DistSq(bishop.pos)) end};mark.rotation=-math.atan2(mark.pos.z,mark.pos.x)*180/math.pi
 local d=b:Dodge(bishop,false);local aim=d:fn();local distance=math.sqrt(p.pos:DistSq(aim));assert(distance>.1,"do not stop at temporary mark clearance during prep")
 local step=math.min(7.5/30,distance);p.pos=Vector3(p.pos.x+(aim.x-p.pos.x)/distance*step,0,p.pos.z+(aim.z-p.pos.z)/distance*step);moved=moved+step
 local dx,dz=p.pos.x-mark.pos.x,p.pos.z-mark.pos.z;local len=math.sqrt(dx*dx+dz*dz);local t=len>0 and math.min(1,track/len) or 0
 mark.pos=Vector3(mark.pos.x+dx*t,0,mark.pos.z+dz*t);track=math.max(.02,track-.02)
end
assert(moved>7,"tracking must keep movement continuous")
-- 源码在atk2_pst第1帧才创建伤害FX；模拟第0帧的实际移动，不瞬移到安全终点。
bishop.anim="atk2_pst";bishop.frame=0;mark.anim="reticule_pst"
local impact=Vector3(mark.pos.x,0,mark.pos.z);local aim=b:Dodge(bishop,false):fn();local distance=math.sqrt(p.pos:DistSq(aim))
local step=math.min(7.5/30,distance);p.pos=Vector3(p.pos.x+(aim.x-p.pos.x)/distance*step,0,p.pos.z+(aim.z-p.pos.z)/distance*step)
assert(p.pos:DistSq(impact)>2.5^2,"actual firing frame clears radius2 + player body; clearance="..math.sqrt(p.pos:DistSq(impact)))

-- Original hands route table must remain identical through group wrapper.
local hands=ent("shadowthrall_hands");local original={atkanim="run_loop",angle=80*math.pi/180,dist=4,update=false}
local secondary=require("shadowself/control/secondary")(c);assert(secondary:Wrap(hands,original)==original)
-- Real native keyframe/event code: no early recovery cancel while local SG still abouttoattack.
local source=assert(io.open("scripts/shadowself/native/engine/HitAndRun.lua")):read("*a")
local about=true;local callback
local player={sg={HasStateTag=function(_,tag) return about and tag=="abouttoattack" end},HasTag=function() return true end,ListenForEvent=function(_,_,fn) callback=fn end}
local H={DoubleSwitching=function() return false end,HoldingPillow=function() return false end,ent={},guid=0,keyframe=0,PC={CanLocomote=function() return false end},IsHitingFrame=function() return true end}
local env=setmetatable({HitAndRun=H,ThePlayer=player,MOD_util={GetMOption=function(_,_,default) return default end},ACTIONS=ACTIONS},{__index=_G})
local a=assert(source:find("function HitAndRun:IsKeyFrame()",1,true));local z=assert(source:find("\n\t--执行打断攻击",a,true));local f=assert(loadstring(source:sub(a,z-1)));setfenv(f,env);f()
assert(not H:IsKeyFrame(),"early local frame shortcut cannot cancel before hit")
about=false;assert(H:IsKeyFrame(),"confirmed attack phase returns native keyframe behavior")
a=assert(source:find("function HitAndRun:RegisterListener()",1,true));z=assert(source:find("\nend",a,true));f=assert(loadstring(source:sub(a,z-1)));setfenv(f,env);f();H:RegisterListener()
callback(player,{action={action=ACTIONS.WALKTO}});assert(not H.performed_action,"walking isn't an attack acknowledgement")
callback(player,{action={action=ACTIONS.ATTACK}});assert(H.performed_action)
local bearSource=read_source("stategraphs/SGbearger.lua");local klausSource=read_source("stategraphs/SGklaus.lua")
assert(bearSource:find('FrameEvent(20',1,true) and bearSource:find('data.spdamage.planar',1,true) and klausSource:find('TimeEvent(35 * FRAMES',1,true) and klausSource:find('TimeEvent(49 * FRAMES',1,true))
package.loaded["shadowself/control/mechanisms"]=savedM;package.loaded["shadowself/control/actions"]=savedA;Native.context=savedN
print("PASS: actual dragon grounded output; planar bear punish overrides pit lure; whole Klaus shield/bite/two-claw ownership; real-speed tracking bishop escape; original hands identity; real keyframe abouttoattack guard and attack-only confirmation")
