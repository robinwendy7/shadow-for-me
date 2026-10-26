local W=require('shadowself/control/arena_whip')
local function ent(name,x)
 local e={prefab=name,tags={},pos=Vector3(x or 0,0,0),replica={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end
 return e
end
local p=ent('wilson');local m=ent('merm');local f=ent('frog');local dog=ent('icehound',7)
local w=W();w:Update(2,{m},false,{m,dog});assert(not w.active,'only fish cannot identify the combination')
w:Update(2,{m,f},false,{m,f,dog});assert(w.active and w:CanAttack(p),'exactly seven units permits attack before retreat is latched')
dog.pos=Vector3(6.9,0,0);assert(not w:CanAttack(p),'inside seven pauses all attacks')
dog.pos=Vector3(8,0,0);assert(not w:CanAttack(p),'retreat remains latched above seven')
dog.pos=Vector3(9,0,0);assert(not w:CanAttack(p),'old nine-unit boundary no longer clears retreat')
dog.pos=Vector3(11.99,0,0);assert(not w:CanAttack(p),'retreat remains latched until all twelve units are reached')
dog.pos=Vector3(12,0,0);assert(w:CanAttack(p),'twelve units clears retreat')
local oldNav=package.loaded['shadowself/control/navigation'];local planned=false
package.loaded['shadowself/control/navigation']={Safe=function(context)
 assert(context.hazards[#context.hazards].radius==12,'evade route uses the same twelve-unit dog exclusion radius');planned=true;return true end,Risk=function() return 0 end}
dog.pos=Vector3(6,0,0)
local c={player=p,h={ent=m},hazards={},snapshot={},bridge={PauseAttack=function() end},
 travel={BeginDodge=function() end},Move=function(_,_,label) assert(label:find('12码',1,true)) end}
assert(w:Evade(c) and planned,'retreat planning and status both use twelve units')
package.loaded['shadowself/control/navigation']=oldNav
dog.pos=Vector3(12,0,0);assert(w:CanAttack(p))
local fire=ent('firehound',6);w.dogs={dog,fire};assert(not w:CanAttack(p),'check every trap dog, not only the first')
fire.tags.dead=true;assert(w:CanAttack(p),'dead trap no longer blocks')
assert(not w:Clear(Vector3(8,0,0),7),'cannot pick whip next to a trap dog')
w:Update(2,{},false,{});assert(w.active,'empty local scan is not completion')
m.tags.dead=true;w:Update(2,{},false,{});assert(w.active,'one species still alive keeps whip')
f.tags.isdead=true;w:Update(2,{},false,{});assert(w.finished and not w.active,'confirmed deaths of both species release whip')
local other=W();m.tags.dead=nil;f.tags.isdead=nil;other:Update(2,{m,f},false,{})
other:Update(3,{},false,{});assert(other.finished,'next wave cannot inherit the temporary whip policy')
local missing=W();missing:Update(2,{m,f},false,{});m.removed=true;f.removed=true
missing:Update(2,{},false,{});assert(missing.active,'unloaded objects do not masquerade as dead')
missing:Update(2,{},true,{});assert(missing.finished,'server-confirmed cleared intermission ends uncertain tracking')
local cattle1,cattle2,cattle3=ent('beefalo'),ent('beefalo'),ent('beefalo')
local rabbit1,rabbit2=ent('rabbit'),ent('rabbit')
-- 已完成第二关的对象进入第五关时，开启独立的一轮牛兔跟踪。
w:Update(5,{cattle1,cattle2,cattle3,rabbit1,rabbit2},false,{})
assert(not w.active and not w.finished,'living cattle cannot enable rabbit whip, and old wave2 completion must reset')
cattle1.tags.dead=true;cattle2.tags.dead=true
w:Update(5,{cattle3,rabbit1,rabbit2},false,{})
assert(not w.active,'all observed cattle must be confirmed dead')
cattle3.removed=true;w:Update(5,{rabbit1,rabbit2},false,{})
assert(not w.active,'missing/unloaded cattle are not confirmed kills')
cattle3.removed=nil;cattle3.tags.isdead=true
w:Update(5,{rabbit1,rabbit2},false,{})
assert(w.active and w:Want(ent('whip'),{},false),'confirmed cattle deaths enable ground whip for remaining rabbits')
w:Update(5,{},false,{});assert(w.active,'empty scan cannot finish the rabbit wave')
rabbit1.tags.dead=true;rabbit2.tags.dead=true;w:Update(5,{},false,{})
assert(not w.active and not w.finished,'rabbit death stops whip attacks but retains whip until authoritative completion')
w:Update(5,{},true,{});assert(w.finished,'confirmed cleared intermission releases the fifth-wave whip')
local onlyRabbit=W();onlyRabbit:Update(5,{ent('rabbit')},false,{})
assert(not onlyRabbit.active,'other fifth-wave rabbit appearance does not imply the beefalo combination')
assert(w:RetreatRange()==9,'wave2 distance adjustment does not change fifth-wave rabbit policy')
print('PASS: wave2 fish/frog-only whip lifetime, confirmed deaths, no empty-scan completion, all-dog 7/12 hysteresis, matching route radius and pickup exclusion')

-- 芦苇先于鱼人/青蛙加载：立刻拿鞭准备，不能把空扫描当作清场。
local reeds=ent('reeds');local ice=ent('icehound',10);local whipItem=ent('whip',1)
local reedWave=W();reedWave:Update(2,{},false,{reeds,ice})
assert(reedWave.active and reedWave:RetreatRange()==15,'reeds alone activate the second-wave whip tactic')
assert(not reedWave:CanAttack(p),'ten units blocks immediately, without first entering seven')
assert(reedWave:CanPickup(p,whipItem) and reedWave:Want(whipItem,{},false),'safe whip pickup precedes the fifteen-unit retreat')
reedWave:Update(2,{},false,{ice});assert(reedWave.active,'reeds unloading and empty monster scan do not release the tactic')
for _,x in ipairs({7,12,14.99,15}) do ice.pos=Vector3(x,0,0);assert(not reedWave:CanAttack(p),'no attacks at or within fifteen units') end
ice.pos=Vector3(15.01,0,0);assert(not reedWave:CanAttack(p),'retreat clears the15-boundary with a small margin instead of oscillating')
ice.pos=Vector3(15.41,0,0);assert(reedWave:CanAttack(p),'past the margin permits attacks')
ice.pos=Vector3(14,0,0);assert(not reedWave:CanAttack(p),'moving dog re-enters attack exclusion immediately')
whipItem.pos=Vector3(ice.pos.x-6,0,0);assert(not reedWave:CanPickup(p,whipItem),'unsafe pickup destination remains excluded')
whipItem.pos=Vector3(1,0,0);ice.pos=Vector3(6,0,0);assert(not reedWave:CanPickup(p,whipItem),'pickup cannot override the original close trap exclusion')
ice.pos=Vector3(10,0,0)
local savedNav=package.loaded['shadowself/control/navigation'];local Tools=require('shadowself/control/arena_tools')
local recover=Tools.Recover;local permit;local ended=0;local moved=0
local context={player=p,plan={arena_whip_state=reedWave},h={ent=m},snapshot={},hazards={},
 bridge={PauseAttack=function() end},travel={BeginDodge=function() end,EndDodge=function() ended=ended+1 end},
 Move=function(_,_,label) assert(label:find('15码',1,true));moved=moved+1 end}
package.loaded['shadowself/control/navigation']={Safe=function(c,q)
 assert(c.hazards[#c.hazards].radius==15,'route uses fifteen-unit exclusion');return q:DistSq(ice.pos)>15^2 end,Risk=function() return 0 end}
local Encounters=require('shadowself/control/encounters');local encounter=Encounters(context)
encounter.Salamanders=function() end
Tools.Recover=function(_,name,guard) assert(name=='whip' and guard(whipItem));permit=guard;return true end
reedWave.moving=true
assert(encounter:Tick(m)=='support' and ended==1 and moved==0,'real encounter dispatch picks the safe whip before retreat and releases old dodge ownership')
ice.pos=Vector3(6,0,0);assert(not permit(whipItem),'delayed pickup guard rechecks moving trap dogs')
ice.pos=Vector3(10,0,0);Tools.Recover=function() return false end
assert(encounter:Tick(m)=='move' and moved==1,'after pickup or without a safe whip, real dispatch retreats before attacking')
Tools.Recover=recover;package.loaded['shadowself/control/navigation']=savedNav
reedWave:Update(2,{},true,{});assert(reedWave.finished and not permit(whipItem),'server-confirmed rest cancels stale pickup')
local outside=W();outside:Update(1,{},false,{reeds,ice});assert(not outside.active,'reeds in other waves do not activate this tactic')
print('PASS: reed-triggered early whip priority, real support-before-evade dispatch, strict dynamic fifteen-unit attack exclusion and delayed pickup revalidation')
