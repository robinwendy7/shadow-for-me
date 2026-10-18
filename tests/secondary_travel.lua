local saved={time=GetTime,vec=Vector3,sim=TheSim}
local now=10;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local function enemy(id,x,data)
 local e={GUID=id,pos=Vector3(x,0,0),data=data,anim=data and "atk" or "idle",prefab="hound",replica={combat={GetAttackRangeWithWeapon=function() return 2 end}}}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end}
 return e
end
local base={atkanim="atk",point="target",dist=6,fn=function() return Vector3(-3,0,0) end}
local primary=enemy(1,3,base);local other=enemy(2,-3,base)
local player={pos=Vector3(0,0,0),busy=false}
function player:GetPosition() return self.pos end;function player:HasTag() return self.busy end
local entities={primary};TheSim={FindEntities=function() return entities end}
local h={ent=primary,idle_ticks=41};local pre=0
local c={h=h,player=player,actions={SafePoint=function() return true end},bridge={allowed=function() return true end,wrappers={
 IsAttackPre={old=function(_,e) h.idle_ticks=0;return e.data end},PreTheLoop={old=function() pre=pre+1 end}}}}
local S=require("shadowself/control/secondary")(c)
assert(S:Wrap(primary,base)==base and h.idle_ticks==41,"single enemy uses exact native table without mutating idle timer")
entities={primary,other};now=now+.06
local group=S:Wrap(primary,base);assert(group~=base)
local q=group:fn()
assert(math.abs(q.z)>1 and math.abs(math.sqrt(q:DistSq(primary.pos))-6)<.001,"left/right windups use third direction and retain native primary distance")
assert(require("shadowself/control/navigation").Safe(S,q),"group alternative path avoids both actual attacks")
assert(S:Wrap(primary,base,group)==group,"same native dodge retains stable wrapper identity across frames")
-- Distant windup whose attack doesn't intersect the native route has no effect.
other.pos=Vector3(15,0,0);now=now+.06
q=group:fn();assert(q.x==-3 and q.z==0,"unrelated distant attack leaves native landing untouched")
-- Actual other attack takes priority over attacking an idle main target.
primary.data=false;primary.anim="idle";other.pos=Vector3(1,0,0);now=now+.06
S:Pulse();assert(h.ent==other and pre==1,"same 3014 thread targets other imminent attack")
h.ent=primary;S.pending=nil
assert(S:Wrap(primary,false,{atkanim="atk"})==false and S.pending==other,"finishing dodge queues a threat rather than nesting another loop")
assert(not S:BeforeAttack() and h.ent==other and not S.pending,"old-target follow-up yields to imminent other attack")
-- A native idle fallback table is not a real swing.
h.ent=primary;other.anim="idle";now=now+.06
S:Pulse();assert(h.ent==primary,"idle fallback does not cause permanent crowd retreat")
-- Dedicated queen tactic must never be retargeted or rerouted by generic groups.
c.beequeen={late=true};c.queen_active=true;h.ent=primary;S.pending=other
S:Pulse();assert(h.ent==primary and not S.pending)
assert(S:Wrap(primary,base)==base,"queen tactics keep their own native/guard dodge tables")
S.pending=other;assert(S:BeforeAttack() and h.ent==primary and not S.pending,"generic pending threat cannot steal queen target")
c.queen_active=false;c.beequeen=nil
-- Cane travel/pursuit has a large enter/exit gap, and never blocks native movement.
local roles={};local hand="weapon";local switches=0
local gear={Weapon=function() return {} end,Swap=function(_,role)
 roles[#roles+1]=role;if role~=hand then hand=role;switches=switches+1 end;return false end,Reset=function() end}
local Travel=require("shadowself/control/travel");local travel=Travel(player,gear)
local function tick(distance,imminent)
 now=now+.21;travel:Tick(Vector3(distance,0,0),2,imminent,{night=false})
end
tick(10);assert(travel.role=="move","long chase borrows cane")
local count=switches
for _,distance in ipairs({6,5,6.8,5.5,4.1}) do tick(distance) end
assert(travel.role=="move" and switches==count,"distance jitter does not bounce cane/weapon")
tick(3.5);assert(travel.role=="attack","weapon restored before melee")
count=switches;for i=1,20 do tick(i%2==0 and 5 or 6) end
assert(switches==count,"no travel re-entry until large distance threshold")
player.busy=true;local requests=#roles;tick(12);assert(#roles==requests,"hurt busy cannot trigger repeated gear swaps")
player.busy=false;tick(12,true);assert(#roles==requests,"imminent attack never borrows a cane")
tick(12);assert(travel.role=="move","chase can resume cane after danger")
local walk=Travel(player,gear);now=now+.21;walk:Tick(Vector3(20,0,0));assert(walk.role=="move","ordinary goto travel also uses cane")
now=now+.21;walk:Tick(Vector3(2,0,0));assert(walk.role=="attack","arrival restores combat hand")
GetTime,Vector3,TheSim=saved.time,saved.vec,saved.sim
print("PASS: native solo untouched; other real windup priority; group third direction/native distance; stable table; idle fallback ignored; cane chase/goto hysteresis, hit and danger suppression")
