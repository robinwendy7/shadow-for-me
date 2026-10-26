local saved={world=TheWorld,sim=TheSim,time=GetTime}
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local id=104300
local function entity(name,x,z)
 id=id+1
 local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),radius=1,anim='idle',frame=0,rotation=0,tags={},replica={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return self.radius end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return e.rotation end}
 return e
end
local p=entity('wilson',0,5);p.radius=.5
local shark=entity('sharkboi')
local c={player=p,enemies={shark},hazards={},observed={},snapshot={},plan={arena=true,arena_wave=function() return 7 end},
 actions={SafePoint=function() return true end,Stop=function() end},
 bridge={PauseAttack=function() end,allowed=function() return true end},travel={BeginDodge=function() end,EndDodge=function() end}}
c.bridge.plan=c.plan
function c:Move(point) self.moved=point end
local boss=require('shadowself/control/bosses')(c)
local R=require('shadowself/control/sharkroute')
local toolsKey='shadowself/control/arena_tools';local oldTools=package.loaded[toolsKey]
local cane=entity('cane');local savedPatrol={};local roles={}
package.loaded[toolsKey]={Owned=function(_,name) return name=='cane' and cane or nil end}
c.gear={patrol_hand=savedPatrol,Swap=function(_,role) roles[#roles+1]=role;return false end}
-- 经过真实Boss调度入口，已安全的玩家也必须在滑行开始后跟随。
shark.anim='torpedo_loop'
assert(boss:Tick(shark)=='move' and c.moved:DistSq(p.pos)>.1,'slide starts dynamic following through actual boss scheduler instead of holding safe point')
assert(c.gear.patrol_hand==cane and roles[#roles]=='move','slide immediately requests cane ownership without stopping movement to wait for equip ACK')
local first=c.moved
shark.pos=Vector3(5,0,0)
assert(boss:Tick(shark)=='move' and c.moved:DistSq(first)>.1,'moving shark updates follow destination during the same slide')
assert(boss:AttackBlocked(shark),'follow never attacks during active damaging slide')
-- 到跟随点的每段路径均不切入滑行伤害带。
local function safe(q)
 local dx,dz=q.x-shark.pos.x,q.z-shark.pos.z
 return dx*dx+dz*dz>=3.5^2 and (math.abs(dz)>=4.3 or dx<=-4.3)
end
for i=0,20 do
 local v=Vector3(p.pos.x+(c.moved.x-p.pos.x)*i/20,0,p.pos.z+(c.moved.z-p.pos.z)*i/20)
 assert(safe(v),'dynamic following route stays outside jump and slide damage geometry')
end
-- 滑行结束后即使仍在侧面也直接输出；不要求额外绕背。
shark.anim='torpedo_climb'
c.gear.pending={item=cane};c.gear.next_request=100
assert(R.Committed(c,shark) and not boss:AttackBlocked(shark) and not boss:Dodge(shark,{}),'slide recovery directly attacks from current side without extra orbit')
assert(not R.Prepare(boss,shark),'recovery does not schedule another move before output')
assert(c.gear.patrol_hand==savedPatrol and roles[#roles]=='attack' and not boss.moving,
 'actual slide end releases cane/movement ownership and requests normal weapon immediately without a rear condition')
assert(not c.gear.pending and c.gear.next_request==0,'obsolete cane equip wait cannot delay the first post-slide weapon request')
package.loaded[toolsKey]=oldTools;c.gear=nil
-- 正常挥击则不同：侧面禁攻，继续绕行到正后方。
for _,name in ipairs({'atk1','atk2','atk3'}) do
 shark.pos=Vector3(0,0,0);shark.anim=name;shark.frame=0
 p.pos=Vector3(0,0,1.65)
 assert(boss:AttackBlocked(shark) and not R.Committed(c,shark),'normal swipe cannot reuse slide recovery or side position for attack')
 local data=boss:Dodge(shark,false)
 assert(data and data.noattack and data:fn():DistSq(p.pos)>.01,'normal swipe continues orbit past the side')
 local theta=160*math.pi/180;p.pos=Vector3(math.cos(theta)*1.65,0,math.sin(theta)*1.65)
 assert(not R.Rear(c,shark) and boss:Dodge(shark,false),'back-side at 160 degrees still must finish moving to the rear')
 p.pos=Vector3(-1.65,0,0)
 assert(boss:Dodge(shark,false) and boss:AttackBlocked(shark),'rear arrival cannot cut short the extended seventh-wave swipe window')
 shark.frame=name=='atk1' and 45 or name=='atk2' and 21 or 37
 assert(R.Rear(c,shark) and not boss:Dodge(shark,false) and not boss:AttackBlocked(shark),'actual rear releases attack without extra wandering')
end
-- The doubled window is exclusive to seventh-wave arena combat.
c.plan.arena_wave=function() return 6 end;shark.anim='atk1';shark.frame=17
assert(not R.SwipeHold(c,shark),'other encounters do not inherit the extended swipe timing')
c.plan.arena_wave=function() return 7 end
-- 第七关滑行准备窗：最多两刀真实距离内的挥击，留足跳跃前撤离时间。
local native=require('shadowself/native');local savedNative=native.context
native.context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
c.gear={AttackRange=function() return 2 end};c.h={ent=shark,IsHitingFrame=function() return p.frame>=8 end}
shark.AnimState.GetCurrentAnimationLength=function() return 1.6 end
p.pos=Vector3(1.65,0,0);p.anim='atk';p.frame=0;p.tags.attack=nil;shark.anim='torpedo_pre';shark.frame=0
assert(boss:Tick(shark)=='attack' and R.Committed(c,shark) and not boss:AttackBlocked(shark),'actual boss entry opens attacks before sliding rather than immediately dodging')
p.tags.attack=true;p.frame=1;shark.frame=3;R.PreAttack(c,shark)
p.frame=8;shark.frame=8;assert(R.PreAttack(c,shark) and c.shark_pre.hits==1)
R.Committed(c,shark);assert(c.shark_pre.hits==1,'duplicate frame scans cannot count a second swing')
p.frame=1;shark.frame=10;R.PreAttack(c,shark)
p.frame=8;shark.frame=18;assert(not R.PreAttack(c,shark) and c.shark_pre.hits==2)
assert(boss:AttackBlocked(shark) and boss:Dodge(shark,false),'two completed swings immediately hand control back to pre-slide escape')
p.tags.attack=nil;shark.anim='torpedo_jump';shark.frame=0
assert(not R.Committed(c,shark) and boss:AttackBlocked(shark) and boss:Dodge(shark,false),'actual jumping always cancels the attack window')
shark.anim='torpedo_pre';shark.frame=40
assert(not R.PreAttack(c,shark),'late or shortened preparation leaves time to exit rather than greed two attacks')
shark.frame=0;p.pos=Vector3(8,0,0)
assert(not R.PreAttack(c,shark),'preparation window does not chase a distant shark')
p.pos=Vector3(1.65,0,0);shark.anim='idle';R.Committed(c,shark)
native.context=savedNative
-- 原版可撞晕屏障，按不同空间位置轮换，不把同地点的实体更换算成转移。
local Guardian=require('shadowself/control/guardian')
local king=entity('minotaur');local a=entity('pillar_ruins',6,0);local b=entity('pillar_ruins',0,10);local d=entity('pillar_ruins',-10,0)
for _,e in ipairs({a,b,d}) do e.tags.charge_barrier=true end
local roster={a,b,d};TheSim={FindEntities=function() return roster end}
c.enemies={king};c.plan.arena_wave=function() return 9 end
boss.guardian=nil;p.pos=Vector3(11,0,0)
assert(Guardian.Tick(boss,king)=='support' and boss.guardian.pillar==a,'initial bait uses actual barrier with player behind it')
king.anim='atk';Guardian.Tick(boss,king)
king.anim='stun_pre';assert(Guardian.Tick(boss,king)=='move','actual collision stun detours around the intervening pillar before output')
king.anim='stun_hit';Guardian.Tick(boss,king)
assert(boss.guardian.pillar==a,'repeated stunned frames retain output rather than switching mid-stun')
king.anim='idle';now=1;Guardian.Tick(boss,king)
local second=boss.guardian.pillar
assert(second and second~=a and second.pos:DistSq(a.pos)>=36,'after stun recovery transfers to a different pillar position')
assert(boss.guardian.used['3:0']==1,'one stun sequence retires the old position exactly once')
king.anim='stun_loop';Guardian.Tick(boss,king);king.anim='idle';now=2;Guardian.Tick(boss,king)
local third=boss.guardian.pillar
assert(third and third~=a and third~=second,'third attempt prefers another unused position instead of alternating near one pillar')
-- 一轮实际冲锋未眩晕，结束后重新选位。
king.anim='atk';Guardian.Tick(boss,king);king.anim='idle';now=3;Guardian.Tick(boss,king)
assert(boss.guardian.pillar~=third,'missed charge switches position on actual charge end')
-- 在同一柱后久等、卡路原地绕圈均能退出当前尝试。
boss.guardian=nil;king.pos=Vector3(0,0,0);p.pos=Vector3(11,0,0);now=10
Guardian.Tick(boss,king);assert(boss.guardian.pillar==a)
now=17;Guardian.Tick(boss,king)
assert(boss.guardian.pillar~=a,'waiting without a charge does not camp one pillar forever')
boss.guardian=nil;p.pos=Vector3(3,0,0);now=20;Guardian.Tick(boss,king)
local stalled=boss.guardian.pillar
now=29;Guardian.Tick(boss,king)
assert(boss.guardian.pillar~=stalled,'no movement progress abandons a failed circular approach')
-- 当前冲锋中不换诱导柱；跳跃仍交给已有躲避。
local locked=boss.guardian.pillar;king.anim='atk';now=30;Guardian.Tick(boss,king);now=60;Guardian.Tick(boss,king)
assert(boss.guardian.pillar==locked,'ongoing charge never switches its barrier on a timer')
king.anim='jump_atk_pre';assert(not Guardian.Tick(boss,king),'leap dodge keeps precedence over pillar transfer')
local falling=entity('ruins_cavein_obstacle',0,15);falling.tags.charge_barrier=true;falling.pos.y=4
local decoration=entity('pillar_ruins',12,12)
roster={falling,decoration};boss.guardian=nil;king.anim='idle';now=70
assert(not Guardian.Tick(boss,king),'airborne rock and untagged decoration cannot serve as replacement pillars')
falling.pos.y=0;now=71;Guardian.Tick(boss,king)
assert(boss.guardian.pillar==falling,'newly landed server barrier is eligible for the next lure')
-- Ninth-wave lure retreat doubles the full old pillar-relative distance.
c.plan.arena_wave=function() return 9 end;king.anim='idle';king.pos=Vector3(-12,0,0);now=80;boss.guardian=nil
local nav=require('shadowself/control/navigation');local safeBefore=nav.Safe
nav.Safe=function() return true end
Guardian.Tick(boss,king)
local selected=boss.guardian.pillar
local expected=(selected:GetPhysicsRadius(0)+p:GetPhysicsRadius(0)+1)*2
assert(math.abs(math.sqrt(boss.guardian.wait_goal:DistSq(selected.pos))-expected)<.001,'wave9 stands twice as far behind the pillar')
nav.Safe=safeBefore
c.bosses=boss;king.anim='atk';boss.guardian.phase='transfer';boss.guardian.owns_until=now+.35
assert(not Guardian.Dodge(c,king,{}),'wave9 transfer owns movement while the actual pillar remains valid')
boss.guardian.phase='danger';assert(Guardian.Dodge(c,king,{}),'misaligned actual charge restores emergency sidestep')
boss.guardian.phase='transfer';selected.tags.NOBLOCK=true
assert(Guardian.Dodge(c,king,{}),'invalidated pillar cannot suppress dodge');selected.tags.NOBLOCK=nil
c.plan.arena_wave=function() return 10 end
assert(Guardian.Dodge(c,king,{}),'pillar ownership override never affects other waves')
TheWorld,TheSim,GetTime=saved.world,saved.sim,saved.time
print('PASS: shark live slide following with safe paths, direct recovery attack, full rear orbit for normal swipes; guardian spatial pillar rotation after stun/miss/wait/stall, charge lock and real barrier checks')
