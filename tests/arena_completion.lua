-- 服务器真实prefab及耗尽工具必须进入执行路径，不能只测试近似名称。
local Data=require('shadowself/data/arena_classic')
local pirates=Data.encounters[5].default[2].monsters
assert(pirates[1].prefab=='prime_mate' and pirates[2].prefab=='powder_monkey')
assert(read_source('prefabs/primemate.lua'):find('Prefab("prime_mate"',1,true)
 and read_source('stategraphs/SGprimemate.lua'):find('TimeEvent(9 * FRAMES',1,true),
 'actual game prefab and frame9 attack match the corrected captain dodge profile')
local source=read_astra_source('astra/modes/arena/encounter_adapters.lua')
assert(source:find('WAITING_FOR_LUNAR_REVENANT_DEATH',1,true)
 and source:find('_astra_arena_lunar_revenant_defeated=true',1,true),
 'current captured objective actually waits for the adapter death sequence')
local keys={'shadowself/control/actions','shadowself/control/arena_tools','shadowself/control/arena_goats','shadowself/control/navigation','shadowself/control/encounters'}
local saved={};for _,key in ipairs(keys) do saved[key]=package.loaded[key] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function entity(name,uses,x)
 local e={prefab=name,GUID=name..tostring(uses),uses=uses,pos=Vector3(x or 0,0,0),replica={}}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={IsHeld=function() return e.held end,classified={percentused={value=function() return e.uses end}}}
 return e
end
local staff=entity('staff_tornado',100);local spent=entity('staff_tornado',0)
local replacement=entity('staff_tornado',70,4);local sword=entity('nightsword',100)
local bag={spent,staff};local ground={};local hand=staff;local casts,picks,drops=0,0,0;local allowPickup=true
local p=entity('wilson',100);p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetEquippedItem=function() return hand end,GetItems=function() return bag end,GetNumSlots=function() return 15 end,
 DropItemFromInvTile=function() drops=drops+1 end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 CastStaff=function(_,item) assert(item.uses>0);casts=casts+1;return true end,
 Scene=function(_,item,action,guard) assert(item==replacement and guard());picks=picks+1;return allowPickup end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end}
package.loaded['shadowself/control/arena_tools']=nil;package.loaded['shadowself/control/arena_goats']=nil
local c={player=p,plan={arena=true,arena_ground=function() return ground end},gear={forced_weapon=sword},travel={},
 bridge={PauseAttack=function() end},mechanisms={Equip=function() end}}
local owner={c=c,Target=function() end,Release=function() end,Move=function() return 'move' end,Away=function() return 'move' end}
local Wind=require('shadowself/control/arena_goats');local wind=Wind(owner);local goat=entity('lightninggoat',100,10)
assert(wind:Tick({goat})=='support' and casts==1 and c.gear.forced_weapon==staff,'skip spent staff before a usable staff')
staff.uses=0;now=1
assert(not wind:Tick({goat}) and casts==1 and not c.arena_wind and c.gear.forced_weapon==sword,
 'actual zero durability releases gear ownership and normal combat instead of infinite failed casts')
ground={replacement};assert(wind:Tick({goat})=='support' and drops==1 and picks==0,'drop spent tool before replacement')
bag={};now=2;assert(wind:Tick({goat})=='support' and picks==1,'recover usable staff from ground through existing pickup path')
now=3;allowPickup=false
assert(not wind:Tick({goat}),'unavailable pickup action cannot monopolize support and stop combat')
allowPickup=true
bag={staff};staff.uses=100;ground={};now=3;hand=staff
assert(wind:Tick({goat})=='support' and casts==2)
local heals=0
c.healing={pending={},Tick=function() heals=heals+1;return true end}
now=3.2;wind:Tick({goat});assert(heals==0,'do not cancel an in-flight cast to start eating')
now=4;assert(wind:Tick({goat})=='support' and heals==1 and casts==2 and not c.arena_wind and c.gear.forced_weapon==sword,
 'continuous wind support yields to existing healing state between casts')
c.healing=nil
local stillGathering=Wind(owner);local back=entity('lightninggoat',100,12)
now=10;stillGathering:Tick({goat,back});local started=stillGathering.since
c.healing={Choose=function() return true end,Tick=function() return false end}
now=11;stillGathering:Tick({goat,back})
assert(stillGathering.since==started,'unsafe healing attempt cannot reset gather timer or starve casts')
local before=casts;now=13;stillGathering:Tick({goat,back})
assert(casts==before+1,'failed healing window still progresses to continuous casting')
c.healing=nil;stillGathering:Stop()
local sliding=entity('penguin',100,10);sliding.AnimState={IsCurrentAnimation=function(_,name) return name=='slide_loop' end}
c.enemies={sliding};c.bridge.allowed=function() return true end;bag={entity('panflute',0)}
package.loaded['shadowself/control/encounters']=nil
assert(not require('shadowself/control/encounters')(c):Penguins(sliding),
 'exhausted flute cannot restart endless penguin PLAY/wait cycles')
for _,key in ipairs(keys) do package.loaded[key]=saved[key] end
GetTime=oldTime
local Inventory=require('shadowself/control/arena_inventory')
local emptyFlute=entity('panflute',0);local flute=entity('panflute',60)
assert(not Inventory.Want(emptyFlute,{},p,3),'do not collect exhausted flute')
assert(Inventory.Want(flute,{emptyFlute},p,3),'exhausted held flute cannot veto usable replacement')
assert(not Inventory.Want(spent,{},p,6),'do not collect exhausted weather staff')
assert(Inventory.Want(replacement,{spent},p,6),'allow weather staff replacement with spent copy still held')
-- 原静态路线仍然畅通，但同步移动的第三只怪会在到达前切入；不能保持旧方向。
local oldWorld=TheWorld;TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local route=require('shadowself/control/crowdroute')
local left=entity('knight',100,-2);local right=entity('knight_nightmare',100,2)
local s={player=p,c={player=p,Speed=function() return 6 end,Latency=function() return .03 end},
 actions={SafePoint=function() return true end},enemies={left,right},data={[left]={atkanim='atk'},[right]={atkanim='atk'}},hazards={}}
local first=assert(route.Choose(s,Vector3(1,0,0),left))
local sign=first.z>0 and 1 or -1
local crossing=entity('knight',100,first.x);crossing.pos=Vector3(first.x,0,sign*8)
s.enemies={left,right,crossing};s.data[crossing]={atkanim='atk'}
assert(route.Choose(s,first,left)==first,'static distant body leaves the existing route valid')
s.motion={[crossing]={vx=0,vz=-sign*16}}
local redirected=route.Choose(s,first,left)
assert(redirected and redirected~=first and redirected.z*sign<0,'moving body invalidates commitment before occupying the route')
TheWorld=oldWorld
local oldSim,oldClock=TheSim,GetTime;local clock=0;GetTime=function() return clock end
local walker=entity('powder_monkey',100,5)
TheSim={FindEntities=function() return {walker} end}
local context={player=p,plan={arena=true},h={},actions={},bridge={allowed=function() return true end,
 wrappers={IsAttackPre={old=function() return nil end}}}}
local observer=require('shadowself/control/secondary')(context)
observer:Scan();assert(#observer.enemies==1 and observer.observed[walker.GUID].neutral,
 'idle arena monster is a body obstacle, not a reported attack')
clock=.1;walker.pos=Vector3(4.4,0,0);observer:Scan()
assert(math.abs(observer.motion[walker].vx+6)<.001,'use actual synchronized displacement')
clock=.2;walker.pos=Vector3(40,0,0);observer:Scan()
assert(observer.motion[walker].vx==0,'teleport is not extrapolated as crowd movement')
clock=1;walker.pos=Vector3(41,0,0);observer:Scan()
assert(observer.motion[walker].vx==0,'stale observation cannot supply velocity')
context.plan.arena=false;clock=2;observer:Scan()
assert(#observer.enemies==0,'ordinary non-arena idle monster scan retains previous behavior')
TheSim=oldSim;GetTime=oldClock
print('PASS: server pirate names; current revenant death contract; exhausted wind fallback/recovery/gear release; healing between casts; usable tool loot')
