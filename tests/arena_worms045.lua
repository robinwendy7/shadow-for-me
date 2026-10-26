local names={'actions','navigation','arena_tools','arena_goats','arena_salamanders','encounters','bosses'}
local saved={};for _,n in ipairs(names) do saved[n]=package.loaded['shadowself/control/'..n] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function() return false end}
 return e
end
local p=ent('wilson');local staff=ent('staff_tornado');local sword=ent('nightsword')
local hand=staff;local casts={};local guards={}
staff.replica.inventoryitem={classified={percentused={value=function() return 100 end}}}
p.replica.inventory={GetEquippedItem=function() return hand end}
p.components.playercontroller={IsBusy=function() return false end}
package.loaded['shadowself/control/actions']={Items=function() return {staff,sword} end,Stop=function() end,
 CastStaff=function(_,item,target,guard) assert(item==staff and guard());casts[#casts+1]=target;guards[#guards+1]=guard;return true end,
 Self=function() error('worm pack must not use flute') end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Risk=function() return 0 end,Select=function(_,q) return q end,Clearance=function() return 8 end}
package.loaded['shadowself/control/arena_tools']={Owned=function() end,Usable=function() return true end,Recover=function() return false end}
for _,n in ipairs({'arena_goats','arena_salamanders','encounters','bosses'}) do package.loaded['shadowself/control/'..n]=nil end
local worms={ent('worm',10),ent('worm',11),ent('worm',12)}
local adds={ent('slurper',8),ent('slurper',9),ent('monkey',10),ent('monkey',11)}
local roster={};for _,e in ipairs(adds) do roster[#roster+1]=e end
local goal;local wave=6
local c={player=p,plan={arena=true,arena_wave=function() return wave end,arena_center=function() return Vector3(0,0,0) end,
 arena_entities=function() return roster end,arena_remaining=function() return roster end},enemies=roster,gear={forced_weapon=sword},
 observed={},hazards={},snapshot={},h={},actions={SafePoint=function() return true end},bridge={allowed=function() return true end,PauseAttack=function() end},
 travel={BeginDodge=function() end,EndDodge=function() end}}
c.bridge.plan=c.plan
function c:Move(q) goal=q end
c.mechanisms={Equip=function(_,item) hand=item;return true end}
c.encounters=require('shadowself/control/encounters')(c)
local boss=require('shadowself/control/bosses')(c)
assert(boss:AttackBlocked(adds[1]) and boss:Tick(adds[1])=='move','source-unique companions identify worm pack before underground worms appear')
local state=c.arena_salamanders
assert(state.profile.primary=='worm' and state.profile.expected==2 and state.profile.final_count==5,'two monkeys are wind adds; three worms and two slurpers enter melee after their confirmed deaths')
now=100;boss:Tick(adds[1]);assert(#casts==0 and not state.edge_since,'approaching perimeter cannot count as patrol time')
p.pos=goal;now=101;boss:Tick(adds[1]);assert(state.edge_since==101)
for i,e in ipairs(adds) do e.pos=Vector3(p.pos.x+8+i*.1,0,p.pos.z) end
now=115.99;boss:Tick(adds[1]);assert(#casts==0)
now=116;boss:Tick(adds[1]);assert(#casts==1)
-- 真正看到出土实体后纳入收尾目标，不能在三次旋风前转入近战。
for i,e in ipairs(worms) do e.pos=Vector3(p.pos.x+10+i,0,p.pos.z);roster[#roster+1]=e end
for n=1,3 do
 assert(#casts==n and casts[n].prefab~='worm' and boss:AttackBlocked(worms[1]),'first burst targets adds and blocks premature worm attacks')
 local t=116+n
 now=t-.1;boss:Tick(worms[1]);assert(#casts==n,'unconfirmed request cannot satisfy burst quota')
 state.wind:Performed({invobject=staff,target=casts[n]});now=t;boss:Tick(worms[1])
end
assert(#casts==3 and state.first_done and state.budget==1 and not state.wind,'after three confirmed winds return to seven-second patrol')
now=125.99;boss:Tick(worms[1]);assert(#casts==3)
now=126;boss:Tick(worms[1]);assert(#casts==4,'only seven seconds are needed for the next one-wind burst')
for i=1,3 do adds[i].tags.dead=true end
state.wind:Performed({invobject=staff,target=casts[4]});now=126.1;boss:Tick(worms[1]);assert(#casts==4 and not state.wind)
now=133.2;boss:Tick(worms[1])
assert(#casts==5 and casts[5]==adds[4] and state.wind.limit==1,'single-wind cleanup selects the last monkey instead of the worms')
adds[4].removed=true;now=134;boss:Tick(worms[1])
assert(state.phase=='wind' and boss:AttackBlocked(worms[1]),'unconfirmed disappearance of the fourth add cannot unlock melee')
local objectives=4
c.plan.arena_objectives=function() return objectives end
now=134.1;boss:Tick(worms[1])
assert(state.phase~='melee','one additional server objective means a missing add is still unresolved')
objectives=3;state.first_done=nil;now=134.2
local clearedMode,clearedTarget=boss:Tick(worms[1])
assert(clearedMode=='attack' and clearedTarget==worms[1] and state.phase=='melee'
 and state.clear_source=='server_objectives' and not adds[4].tags.dead,
 'three remaining server objectives accounted for by three live worms unlock melee despite removed add corpse and incomplete wind quota')
adds[4].removed=nil;adds[4].tags.dead=true;now=135
local mode,target=boss:Tick(adds[4])
assert(mode=='attack' and target==worms[1] and state.phase=='melee','four confirmed add deaths immediately release normal worm combat')
assert(not state.wind and c.gear.forced_weapon==sword and not guards[5](),'melee restores normal weapon and invalidates queued wind')
local native={native=true};assert(boss:Dodge(worms[1],native)==native,'worm melee keeps the existing native dodge behavior')
for i=1,2 do worms[i].tags.dead=true;boss:Tick(worms[i]) end
assert(state.target==worms[3],'after confirmed kills continue to the remaining worm')
worms[3].tags.INLIMBO=true;now=136
assert(state:Tick()=='support' and not state.finished,'temporary underground invisibility cannot count as the third worm death')
worms[3].tags.INLIMBO=nil;assert(state:Tick()=='attack','visible surviving worm resumes output without another patrol or wind burst')
worms[3].tags.dead=true;assert(not state:Tick() and state.finished,'all three actual worm deaths finish the tactic')
-- New request: confirmed monkey clearance releases nearest-slurper melee, then worms.
for _,e in ipairs(worms) do e.tags={};e.removed=nil end
for _,e in ipairs(adds) do e.tags={};e.removed=nil end
adds[3].tags.dead=true;adds[4].tags.dead=true
local S=require('shadowself/control/arena_salamanders');local nextState=S(c.encounters);nextState.first_done=true
local m,t=nextState:Tick()
assert(m=='attack' and t==adds[1] and nextState.phase=='melee' and not nextState.wind,'after monkey deaths, surviving slurpers enter nearest-target melee without another wind loop')
adds[1].pos=Vector3(p.pos.x+30,0,p.pos.z);m,t=nextState:Tick()
assert(m=='attack' and t==adds[2],'worm-pack slurper melee switches to the actually nearer survivor')
adds[1].tags.dead=true;adds[2].tags.dead=true;m,t=nextState:Tick()
assert(m=='attack' and t.prefab=='worm','worms are attacked only after both slurpers are confirmed dead')
wave=5;assert(not require('shadowself/control/arena_salamanders').Required(c),'fifth-wave slurpers do not activate sixth-wave wind tactic')
for _,n in ipairs(names) do package.loaded['shadowself/control/'..n]=saved[n] end
GetTime=oldTime
print('PASS: worm-pack detection before emergence, source-specific 3+4 roster, edge15/three acknowledged winds/one-wind cleanup, confirmed add clearance, native worm dodge and no false underground death')
