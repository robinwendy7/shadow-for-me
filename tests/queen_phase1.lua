-- 一阶段日志回归：零距离蜜块路线、闪避被蜜块覆盖、冻抗轮换。
local savedA=package.loaded["shadowself/control/actions"];local savedN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"};ACTIONS={ATTACK={},PLAY={},EQUIP={}}
TUNING={BEEQUEEN_HIT_RANGE=6}
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=0
local function entity(name,x,z)
 guid=guid+1;local e={prefab=name,GUID=guid,pos=Vector3(x or 0,0,z or 0),tags={},components={},replica={},anim="idle",frame=0}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=entity("wilson",3.5,0);local queen=entity("beequeen");local bee=entity("beeguard",10,0)
local cane=entity("cane");local ice=entity("icestaff");local held=cane
p.replica.inventory={GetEquippedItem=function() return held end};p.components.playercontroller={IsBusy=function() return false end}
p.replica.combat={GetAttackRangeWithWeapon=function() return held==ice and 8 or 2 end}
queen.replica.health={GetPercent=function() return 1 end}
local items={ice,cane};local shots=0;local moves=0
package.loaded["shadowself/control/actions"]={Items=function() return items end,Attack=function() shots=shots+1;return true end}
require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
TheWorld={state={}};TheSim={FindEntities=function() return {queen,bee} end}
local c={player=p,h={ent=queen},enemies={queen,bee},hazards={},observed={},snapshot={},gear={},travel={},owner={}}
c.bridge={allowed=function() return true end,wrappers={PreTheLoop={old=function() end}},PauseAttack=function() end}
c.actions={SafePoint=function() return true end,Stop=function() end}
c.Latency=function() return .1 end;c.gear.Mobile=function() return cane end;c.gear.AttackRange=function() return 2 end
c.gear.Swap=function(self) held=self.support_hand and self.support_hand.item or self.forced_weapon or cane;return true end
c.travel.BeginDodge=function() end;c.travel.EndDodge=function() end
c.Move=function(self,point,label) moves=moves+1;self.moved=point;self.status=label;self.blocked=true end
package.loaded["shadowself/control/beequeen"]=nil
local Queen=require("shadowself/control/beequeen");local q=Queen(c);c.beequeen=q;q:Anchor(queen)
bee.anim="frozen"
q:Move(Vector3(p.pos.x+.01,0,p.pos.z),"蜂蜜阻路",queen)
assert(c.moved and p.pos:DistSq(c.moved)>=.75^2,"blocked tiny approach chooses a useful detour rather than the player's feet")
now=.1;c.blocked=false;q:Strike(queen,p.pos,queen.pos,3.5)
assert(not c.blocked and not q.first_route,"clear direct attack path immediately releases old detour rather than running it to completion")
-- 已处在真实武器射程内时，旧绕行目标和蜂后脚下的蜜块不得强制继续跑。
local previousRadius=queen.GetPhysicsRadius;queen.GetPhysicsRadius=function() return 1.5 end
c.hazards={{pos=queen.pos,radius=1,honey=true}};q.first_route={point=Vector3(7,0,0),expires=now+1}
c.blocked=false;q:Strike(queen,p.pos,queen.pos,3.5)
assert(not c.blocked and not q.first_route,"within true weapon plus queen radius must restore attacks immediately")
queen.GetPhysicsRadius=previousRadius
-- 固定受阻场景60次更新，完整路径检查限频，不再每帧枚举72点。
local nav=require("shadowself/control/navigation");local savedSafe=nav.Safe;local checks=0
nav.Safe=function(...) checks=checks+1;return savedSafe(...) end
c.hazards={{pos=Vector3(2,0,0),radius=1,honey=true}};q.first_route=nil
for i=1,60 do now=1+i/60;q:Move(Vector3(1.8,0,0),"绕蜜性能回归",queen) end
nav.Safe=savedSafe
assert(checks<=160,"60 updates must reuse route plans, checks="..checks)
print("PASS: phase1 60-tick blocked-route full path checks="..checks.." (at most 25 per plan, cached for .2 seconds)")
-- 使用真实Mechanisms.Tick排序：蜜块移动不得覆盖蜂后前摇逃脱。
local M=require("shadowself/control/mechanisms");local m=M(c);local honey_calls=0
m.Scan=function(self) self.zones={} end;m.Incoming=function() return false end
m.Honey=function() honey_calls=honey_calls+1;c:Move(queen.pos,"wrong honey direction");return true end
c.hazards={{pos=p.pos,radius=1,honey=true}};queen.anim="atk";queen.frame=1;now=.2
assert(m:Tick() and honey_calls==0 and q.guard_escape and not q.first_route)
assert(c.moved:DistSq(queen.pos)>6.75^2,"attack escape points out of queen hit radius even while standing in honey")
local escape=q.guard_escape.point
queen.frame=7;now=.4;m:Tick();assert(honey_calls==0 and q.guard_escape.point==escape,"windup retains dodge direction without replanning every frame")
queen.frame=14;now=.65;m:Tick();assert(honey_calls==0,"hold direction through impact and replication margin")
queen.anim="idle";now=3;m:Tick();assert(honey_calls==1,"honey escape resumes after hit window, not during it")
local oldOwn=c.bridge.OwnsThread;c.bridge.OwnsThread=function() return true end
queen.anim="atk";queen.frame=1;local countHoney=honey_calls
assert(m:Tick()==false and honey_calls==countHoney and not q.guard_escape,"running original dodge retains exclusive movement instead of being replaced by another defence loop")
c.bridge.OwnsThread=oldOwn;queen.anim="idle"
-- 三次冻结分别计数，同一冻结期间重复采样不增加；解冻后换掉旧个体。
local G=require("shadowself/control/guardcontrol")
q.guard_stats={};q.recycle_guard=nil;bee.anim="idle";c.hazards={};q.first_route=nil
for i=1,3 do
 bee.anim="frozen";now=now+2;G.Observe(q,{bee},now);G.Observe(q,{bee},now+.1)
 assert(q.guard_stats[bee].freezes==i)
 assert(not G.Recycle(q,bee,now),"don't break an active freeze just to refresh")
 bee.anim="idle";now=now+2;G.Observe(q,{bee},now)
 if i<3 then assert(not G.Recycle(q,bee,now)) end
end
assert(G.Recycle(q,bee,now)==bee,"after three freeze cycles, do not start an increasingly expensive fourth")
c.gear.forced_weapon=ice;q:Tick();assert(c.target==bee and not c.blocked and not c.gear.forced_weapon and not c.gear.support_hand,"recycled guard goes to normal native combat, without forced ice")
-- 击杀后新一批出现，正常清到一只，再对新个体使用冰杖。
bee.tags.isdead=true;G.Observe(q,{},now+.1);assert(not q.recycle_guard)
local fresh={};for i=1,4 do fresh[i]=entity("beeguard",7+i,0) end
c.enemies={queen,unpack(fresh)};TheSim.FindEntities=function() return c.enemies end
queen.anim="spawn";now=now+1;q:Tick()
assert(q.spawn_wait and q.stage=="spawn_wait" and c.target==queen and c.blocked and q.phase==1,"replacement spawn must finish before clearing the new batch")
queen.anim="idle";fresh[1].anim="spawn_in";now=now+.5;q:Tick();assert(q.spawn_wait and c.blocked,"new guard spawn animation also delays cleanup")
fresh[1].anim="idle";now=now+.1;q:Tick();assert(q.spawn_wait,"settle interval protects chained spawns")
now=now+.5;q:Tick();assert(not q.spawn_wait and c.target~=queen and q.phase==1 and not q.recycle_guard,"finished replacement batch resumes cleanup down to one")
c.enemies={queen,fresh[1]};p.pos=Vector3(8,0,1);now=now+1;q:Tick()
assert(q.guard_stats[fresh[1]].freezes==0 and not q.recycle_guard and c.gear.forced_weapon==ice,"fresh last guard starts with its own control history")
-- 无冻结反馈时按实际执行的冰杖攻击计数，等待弹道后结束无效补冰。
q.guard_stats={};q.recycle_guard=nil;local target=fresh[1]
for i=1,4 do now=now+.6;G.OnAction(c,{action=ACTIONS.ATTACK,target=target,invobject=ice}) end
assert(not G.Recycle(q,target,now+.5),"wait for last projectile/replication before judging failed control")
local beforeShots=shots;q:Tick();assert(shots==beforeShots and c.blocked,"four actual shots stop further submissions while waiting for projectile feedback")
assert(G.Recycle(q,target,now+1.1)==target)
local count=q.guard_stats[target].shots
G.OnAction(c,{action=ACTIONS.ATTACK,target=target,invobject=cane});assert(q.guard_stats[target].shots==count,"melee does not count as freezing")
package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
package.loaded["shadowself/control/beequeen"]=nil
print("PASS: phase1 useful honey detour/immediate native handoff; actual mechanism priority holds queen dodge through impact; distinct freeze cycles and actual ice shots; recycle, kill/respawn/clear and fresh last guard control")
