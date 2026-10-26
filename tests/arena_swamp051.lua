local keys={'actions','navigation','arena_tools','arena_goats','encounters','arena_swamp'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded['shadowself/control/'..k] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),tags={},replica={}}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=ent('wilson');local staff=ent('staff_tornado');local hand=staff;local bag={staff};local casts=0;local goal
p.replica.inventory={GetEquippedItem=function(_,slot) if slot==EQUIPSLOTS.HANDS then return hand end end}
p.components={playercontroller={IsBusy=function() return false end}}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 CastStaff=function(_,item,target,guard) assert(item==staff and hand==staff and guard());assert(target.prefab=="mosquito","swamp wind must prioritize mosquitoes");casts=casts+1;return true end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Risk=function() return 0 end,Select=function(_,q) return q end}
for _,k in ipairs({'arena_tools','arena_goats','encounters','arena_swamp'}) do package.loaded['shadowself/control/'..k]=nil end
local c={player=p,plan={arena=true,arena_wave=function() return 5 end,arena_center=function() return Vector3(0,0,0) end,
 arena_ground=function() return {} end},gear={},snapshot={},travel={BeginDodge=function() end,EndDodge=function() end},
 bridge={PauseAttack=function() end,allowed=function() return true end},Move=function(_,q) goal=q end}
local roster={};for _,name in ipairs({'merm','merm','tentacle','tentacle','mosquito','mosquito','frog','frog'}) do roster[#roster+1]=ent(name,8) end
c.enemies=roster
local Encounters=require('shadowself/control/encounters');local owner=Encounters(c);c.encounters=owner
local firstBoss=setmetatable({c=c},{__index=require('shadowself/control/bosses')})
assert(firstBoss:Tick(roster[3])=='move' and casts==0,'real encounter dispatcher chooses swamp patrol ahead of generic crowd casting')
assert(not owner.swamp_wind.edge_since,'travel from center cannot consume the opening patrol timer')
p.pos=goal;now=2;owner:Tick(roster[1]);assert(owner.swamp_wind.edge_since==2)
now=8.99;owner:Tick(roster[1]);assert(casts==0,'no wind before seven seconds at the actual outer lane')
p.pos=Vector3(0,0,18);for i,e in ipairs(roster) do e.pos=Vector3(8+i*.1,0,18) end
now=9;assert(owner:Tick(roster[1])=='support' and casts==1)
local wind=owner.swamp_wind
now=10;owner:Tick(roster[1]);assert(casts==1,'accepted request alone does not advance the two-wind burst')
wind:Performed({invobject=staff,target=roster[5]});now=10.1;owner:Tick(roster[1]);assert(casts==2)
wind:Performed({invobject=staff,target=roster[5]});now=11.2
assert(owner:Tick(roster[1])=='move' and wind.limit==1 and casts==2,'second confirmed wind returns to the existing seven-second one-wind cleanup')
now=18.19;owner:Tick(roster[1]);assert(casts==2)
now=18.21;owner:Tick(roster[1]);assert(casts==3,'remaining mosquitoes get a subsequent seven-second one-wind round')
local frog=roster[8];for i=1,7 do roster[i].tags.dead=true end;c.enemies={frog}
local Swamp=require('shadowself/control/arena_swamp')
frog.tags.dead=true;assert(not Swamp.Tick(owner) and not owner.swamp_wind and not c.arena_wind,'confirmed deaths release wind ownership')
c.plan.arena_wave=function() return 2 end;frog.tags.dead=nil;assert(not Swamp.Required(c),'second-wave fish/frog whip tactic is untouched')
c.plan.arena_wave=function() return 5 end;c.enemies={ent('prime_mate')};assert(not Swamp.Required(c),'other fifth-wave encounters retain their own tactics')
-- A missing wind staff must not let the normal attack branch bypass this tactic.
c.enemies={frog};bag={};now=50;owner:Tick(frog);p.pos=goal;now=51;owner:Tick(frog)
now=66.1;assert(owner:Tick(frog)=='move','unavailable staff keeps safe movement rather than reverting to melee')
local Policy=require('shadowself/control/arena_policy');local marble=ent('armormarble')
assert(not Policy.AllowArmor(marble,5,{frog}),'last surviving swamp monster still blocks automatic marble equip')
-- 蚊子确认清完即可转近战；鱼人保持距蛙八码，再青蛙，最后触手。
bag={staff};hand=staff;now=80
local fish1,fish2=ent('merm',8),ent('merm',9);local tent1,tent2=ent('tentacle',4),ent('tentacle',5)
local frog1,frog2=ent('frog',30),ent('frog',31);local mos1,mos2=ent('mosquito',12),ent('mosquito',13)
local full={fish1,fish2,tent1,tent2,frog1,frog2,mos1,mos2}
p.pos=Vector3(0,0,0);c.enemies=full;c.plan.arena_entities=function() return full end
owner=Encounters(c);c.encounters=owner;owner:Tick(fish1)
assert(not Swamp.Allowed(c,fish1),'ordinary native attacks remain blocked during patrol')
c.enemies={fish1,fish2,tent1,tent2,frog1,frog2};c.plan.arena_entities=function() return c.enemies end;now=81
assert(owner:Tick(tent1)=='move' and owner.swamp_state.phase=='wind','missing/unloaded adds cannot trigger melee')
for _,e in ipairs({mos1,mos2}) do e.tags.dead=true end
-- Recorded entity references still prove deaths when no longer in the fresh enemy scan.
now=82;local mode,target=owner:Tick(tent1)
assert(mode=='attack' and target==fish1 and not owner.swamp_wind and not c.arena_wind,'two confirmed mosquito deaths release wind and prioritize fish while frogs remain alive')
assert(Swamp.Allowed(c,fish1) and not Swamp.Allowed(c,tent1),'native attack gate enforces the actual chosen fish')
frog1.pos=Vector3(2,0,0)
assert(not Swamp.Allowed(c,fish1) and owner:Tick(fish1)=='move','a frog entering eight units interrupts fish attack and repositions')
local recoveryTicks=0
c.healing={Tick=function() recoveryTicks=recoveryTicks+1;return true end}
assert(owner:Tick(fish1)=='support' and recoveryTicks==1 and not Swamp.Allowed(c,fish1),
 'exclusive frog-separation movement still gives real recovery a turn without permitting an unsafe fish attack')
c.healing=nil
local originalSafe=package.loaded['shadowself/control/navigation'].Safe;local jointChecks=0
package.loaded['shadowself/control/navigation'].Safe=function(_,_,exclude)
 assert(exclude==nil,'separation must include the approaching primary fish in route threat checks');jointChecks=jointChecks+1;return true
end
assert(owner:Tick(fish1)=='move' and jointChecks>0,'frog separation evaluates joint fish and frog threat rather than excluding the fish')
package.loaded['shadowself/control/navigation'].Safe=originalSafe
p.pos=Vector3(0,0,0);frog1.pos=Vector3(12,0,0);fish1.pos=Vector3(10,0,0);owner.swamp_state.target=fish1
assert(not Swamp.Allowed(c,fish1),'even from beyond eight units the fish approach point cannot enter frog clearance')
frog1.pos=Vector3(0,0,8);fish1.pos=Vector3(2,0,0);owner.swamp_state.target=fish1
assert(Swamp.Allowed(c,fish1),'exactly eight units from a frog permits an already-in-range fish attack')
frog1.pos=Vector3(30,0,0);fish1.pos=Vector3(8,0,0);owner:Tick(fish1)
local Boss=require('shadowself/control/bosses');local boss=setmetatable({c=c},{__index=Boss})
assert(boss:AttackBlocked(tent1),'real native boss gate forbids attacking tentacles during fish cleanup')
local late=owner.swamp_state;assert(late.phase=='melee')
fish1.tags.dead=true;c.enemies={fish2,tent1,tent2,frog1,frog2};mode,target=owner:Tick(tent1)
assert(mode=='attack' and target==fish2,'second fish is killed before either tentacle')
fish2.removed=true;c.enemies={tent1,tent2,frog1,frog2};mode=owner:Tick(tent1)
assert(mode=='support' and not Swamp.Allowed(c,tent1),'unloaded fish is not a confirmed death')
fish2.removed=nil;fish2.tags.isdead=true;mode,target=owner:Tick(tent2)
assert(mode=='attack' and target==frog1,'when fish are dead, frogs are killed before nearer tentacles')
frog1.tags.dead=true;c.enemies={tent1,tent2,frog2};mode,target=owner:Tick(tent1)
assert(mode=='attack' and target==frog2,'last frog is still prioritized over tentacles')
frog2.removed=true;c.enemies={tent1,tent2};mode=owner:Tick(tent1)
assert(mode=='support' and not Swamp.Allowed(c,tent1),'missing last frog cannot release tentacle attacks without death confirmation')
frog2.removed=nil;frog2.tags.dead=true;mode,target=owner:Tick(tent2)
assert(mode=='attack' and target==tent1,'confirmed deaths of mosquitoes, fish and frogs release nearest tentacle melee')
assert(Swamp.Allowed(c,tent1) and not Swamp.Allowed(c,tent2),'tentacle melee remains locked one at a time')
-- 蚊子尸体删除但死亡标签漏看时，必须由服务端剩余数补充确认，不能只凭空扫描。
for _,e in ipairs(full) do e.tags={};e.removed=nil end
c.enemies=full;c.plan.arena_entities=function() return c.enemies end
owner=Encounters(c);c.encounters=owner;now=100;owner:Tick(fish1)
mos1.removed=true;mos2.removed=true;c.enemies={fish1,fish2,frog1,frog2,tent1,tent2}
local objectives=7;c.plan.arena_objectives=function() return objectives end
assert(owner:Tick(fish1)=='move' and owner.swamp_state.phase=='wind','one unaccounted server objective prevents premature mosquito completion')
objectives=6;mode,target=owner:Tick(tent1)
assert(mode=='attack' and target==fish1 and owner.swamp_state.completed.mosquito,
 'six server objectives accounted for by two fish, two frogs and two tentacles confirm removed mosquitoes and unlock melee')
for _,k in ipairs(keys) do package.loaded['shadowself/control/'..k]=saved[k] end
GetTime=oldTime
print('PASS: actual fifth-wave swamp encounter dispatch, outer7/two mosquito winds and repeat7/one wind; confirmed mosquito deaths switch to fish with eight-unit frog clearance, then frogs, then tentacles; unloading does not imply death')
