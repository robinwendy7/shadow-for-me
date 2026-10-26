local keys={'actions','navigation','arena_tools','arena_goats','arena_pirates'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded['shadowself/control/'..k] end
local savedTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={},components={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=ent('wilson');local monkey=ent('powder_monkey',8);local captain=ent('prime_mate',10)
local staff=ent('staff_tornado');local marble=ent('armormarble');local sword=ent('nightsword')
local percent=100;staff.replica.inventoryitem={classified={percentused={value=function() return percent end}}}
local hand=staff;local body;local bag={staff,marble,sword};local requests=0;local equipped=0;local moves=0
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HANDS and hand or body end}
p.components={playercontroller={IsBusy=function() return false end}}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 CastStaff=function(_,item,target,guard) assert(item==staff and target==monkey and guard());requests=requests+1;return true end,
 Attack=function() error('old torch ignition must not run') end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Risk=function() return 0 end}
for _,k in ipairs({'arena_tools','arena_goats','arena_pirates'}) do package.loaded['shadowself/control/'..k]=nil end
local c={player=p,plan={arena=true,arena_wave=function() return 5 end},enemies={captain,monkey},h={},
 gear={},snapshot={},bridge={allowed=function() return true end,PauseAttack=function() end},travel={}}
c.mechanisms={Equip=function(_,item) assert(item==marble);equipped=equipped+1;return false end}
local owner={c=c,Target=function(_,e) return e end,Release=function() end,
 Move=function() moves=moves+1;return 'move' end,Away=function() moves=moves+1;return 'move' end}
local Pirates=require('shadowself/control/arena_pirates');local state=Pirates(owner)
assert(state:Tick(c.enemies)=='move' and requests==0)
now=14.99;state:Tick(c.enemies);assert(requests==0,'no tornado during the first fifteen seconds')
now=15;monkey.pos=Vector3(6.99,0,0);state:Tick(c.enemies);assert(requests==0,'elapsed timer alone cannot bypass seven-unit clearance')
monkey.pos=Vector3(7,0,0);state:Tick(c.enemies);assert(requests==1)
now=16;state:Tick(c.enemies);assert(requests==1 and (state.wind.completed or 0)==0,'accepted RPC is not a confirmed cast')
state.wind:Performed({invobject=staff,target=monkey});state.wind:Performed({invobject=staff,target=monkey})
assert(state.wind.completed==1,'duplicate performaction does not double count')
now=16.1;state:Tick(c.enemies);assert(requests==2)
percent=95;now=17.1;state:Tick(c.enemies);assert(state.wind.completed==2 and requests==3,'replicated durability confirms a cast without performaction')
state.wind:Performed({invobject=staff,target=monkey});now=18;state:Tick(c.enemies)
assert(requests==3 and state.budget==1 and not state.wind,'first burst stops at three confirmed casts')
now=24.99;state:Tick(c.enemies);assert(requests==3)
now=25;state:Tick(c.enemies);assert(requests==4,'next burst follows seven seconds of kiting')
state.wind:Performed({invobject=staff,target=monkey});now=26;state:Tick(c.enemies)
assert(requests==4 and not state.wind,'subsequent bursts stop after one confirmed cast')
monkey.tags.dead=true;assert(state:Tick(c.enemies)=='support' and equipped==1,'captain melee waits for actual marble equip')
body=marble;assert(state:Tick(c.enemies)=='attack' and requests==4,'only captain remains: marble melee replaces wind and torch')
captain.tags.dead=true;assert(not state:Tick(c.enemies),'dead captain ends the encounter')
-- Queen scene preparation must finish before edge kiting; travel to the edge is not timed.
captain.tags.dead=nil;monkey.tags.dead=nil;hand=staff;now=100;p.pos=Vector3(0,0,0)
c.plan.arena_pirate_opening={ready=false};c.plan.arena_center=function() return Vector3(0,0,0) end
local opening=Pirates(owner);local before=requests;local goal
owner.Move=function(_,q) goal=q;return 'move' end
assert(opening:Tick(c.enemies)=='support' and requests==before,'combat cannot bypass unfinished queen-scene pickups')
c.plan.arena_pirate_opening.ready=true
assert(opening:Tick(c.enemies)=='move' and goal and not opening.edge_since,'head to the source-confirmed edge after pickup completion')
assert(math.abs(goal.x)==18 or math.abs(goal.z)==18,'kite route follows the arena perimeter')
now=200;opening:Tick(c.enemies);assert(requests==before,'travel time cannot satisfy fifteen seconds at the edge')
p.pos=goal;now=201;opening:Tick(c.enemies)
assert(opening.edge_since==201,'timer begins on actual perimeter arrival')
monkey.pos=Vector3(p.pos.x+8,0,p.pos.z);captain.pos=Vector3(p.pos.x+10,0,p.pos.z)
now=215.99;opening:Tick(c.enemies);assert(requests==before,'no tornado before all fifteen edge seconds')
now=216;opening:Tick(c.enemies);assert(requests==before+1,'edge timer completion and seven-unit clearance unlock the original three-wind burst')
opening.wind:Performed({invobject=staff,target=monkey});now=217;opening:Tick(c.enemies)
opening.wind:Performed({invobject=staff,target=monkey});now=218;opening:Tick(c.enemies)
opening.wind:Performed({invobject=staff,target=monkey});now=218.1
assert(opening:Tick(c.enemies)=='move' and requests==before+3 and not opening.wind and opening.budget==1,'third actual cast immediately returns to outer patrol before old cast recovery timer expires')
now=225.09;opening:Tick(c.enemies);assert(requests==before+3,'second perimeter patrol cannot cast before seven seconds')
now=225.11;opening:Tick(c.enemies);assert(requests==before+4,'second perimeter patrol casts one wind at seven seconds, not fifteen')
opening.wind:Performed({invobject=staff,target=monkey});now=225.2
assert(opening:Tick(c.enemies)=='move' and not opening.wind,'every later one-wind burst immediately returns to patrol')
now=232.21;opening:Tick(c.enemies);assert(requests==before+5,'third perimeter cycle also uses seven seconds and one wind')
for _,k in ipairs(keys) do package.loaded['shadowself/control/'..k]=saved[k] end
GetTime=savedTime
print('PASS: pirate kite15/clear7, three confirmed winds, subsequent kite7/one wind, duplicate ack and durability ack, real marble equip before captain melee')
