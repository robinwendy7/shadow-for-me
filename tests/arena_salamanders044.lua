local names={'actions','navigation','arena_tools','arena_goats','arena_salamanders','encounters','bosses'}
local saved={};for _,n in ipairs(names) do saved[n]=package.loaded['shadowself/control/'..n] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local id=104400
local function ent(name,x,z)
 id=id+1
 local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,name) return name=='slide_loop' and e.prefab=='mutated_penguin' end}
 return e
end
local p=ent('wilson');local staff=ent('staff_tornado');local flute=ent('panflute');local sword=ent('nightsword')
local hand=staff;local bag={staff,flute,sword};local percent=100;local casts={};local guards={};local recovered=0
staff.replica.inventoryitem={classified={percentused={value=function() return percent end}}}
p.replica.inventory={GetEquippedItem=function() return hand end}
p.components.playercontroller={IsBusy=function() return false end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 CastStaff=function(_,item,target,guard)
  assert(item==staff and guard());casts[#casts+1]=target;guards[#guards+1]=guard;return true
 end,
 Self=function() error('this encounter must never use panflute PLAY') end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Risk=function() return 0 end,
 Select=function(_,point) return point end,Clearance=function() return 8 end}
package.loaded['shadowself/control/arena_tools']={Owned=function() end,Usable=function() return true end,Recover=function(_,name)
 assert(name=='staff_tornado','new tactic must not recover a flute');recovered=recovered+1;return true
end}
for _,name in ipairs({'arena_goats','arena_salamanders','encounters','bosses'}) do package.loaded['shadowself/control/'..name]=nil end
local a,b=ent('fruitdragon',10),ent('fruitdragon',12)
local others={ent('mutatedhound',8),ent('mutatedhound',9),ent('mutated_penguin',10),ent('mutated_penguin',11),ent('spider_moon',12)}
local roster={a,b};for _,e in ipairs(others) do roster[#roster+1]=e end
local wave=6;local goal
local c={player=p,plan={arena=true,arena_wave=function() return wave end,arena_center=function() return Vector3(0,0,0) end,
 arena_remaining=function() return roster end,arena_entities=function() return roster end},enemies=roster,gear={forced_weapon=sword},
 observed={},hazards={},snapshot={},h={},actions={SafePoint=function() return true end},
 bridge={PauseAttack=function() end,allowed=function() return true end},travel={BeginDodge=function() end,EndDodge=function() end}}
c.bridge.plan=c.plan
function c:Move(q) goal=q end
c.mechanisms={Equip=function(_,item) hand=item;return true end}
c.encounters=require('shadowself/control/encounters')(c)
local boss=require('shadowself/control/bosses')(c)
assert(boss:AttackBlocked(a),'detection blocks premature melee before the dedicated state has initialized')
assert(boss:Tick(others[3])=='move' and #casts==0,'actual boss scheduler takes priority over sliding-penguin panflute control')
local state=c.arena_salamanders
assert(state and (math.abs(goal.x)==18 or math.abs(goal.z)==18),'initial tactic uses the real arena perimeter')
now=100;boss:Tick(a);assert(#casts==0 and not state.edge_since,'time spent reaching the edge cannot count as patrol time')
p.pos=goal;now=101;c.encounters:Tick(others[3]);assert(state.edge_since==101,'actual encounter entry also bypasses penguin PLAY and starts timer on arrival')
for i,e in ipairs(roster) do e.pos=Vector3(p.pos.x+8+i*.1,0,p.pos.z) end
now=115.99;boss:Tick(a);assert(#casts==0,'no wind during fifteen seconds of edge patrol')
now=116;boss:Tick(a);assert(#casts==1 and casts[1].prefab~='fruitdragon')
now=117;boss:Tick(a);assert(#casts==1 and (state.wind.completed or 0)==0,'accepted cast request is not actual cast confirmation')
state.wind:Performed({invobject=staff,target=casts[1]});state.wind:Performed({invobject=staff,target=casts[1]})
assert(state.wind.completed==1,'duplicate event confirms one wind only')
now=117.1;boss:Tick(a);assert(#casts==2)
percent=95;now=118.1;boss:Tick(a);assert(#casts==3 and state.wind.completed==2,'durability acknowledgement also advances the three-wind burst')
state.wind:Performed({invobject=staff,target=casts[3]});now=119;boss:Tick(a)
assert(#casts==3 and state.first_done and state.budget==1 and not state.wind,'three confirmed winds immediately return to the seven-second patrol')
now=125.99;boss:Tick(a);assert(#casts==3,'second patrol cannot cast early')
now=126;boss:Tick(a);assert(#casts==4,'remaining adds receive one wind after seven seconds')
assert(state.wind.limit==1 and casts[4].prefab~='fruitdragon')
for i=1,3 do others[i].tags.dead=true end
state.wind:Performed({invobject=staff,target=casts[4]});now=126.1;boss:Tick(a)
local last=others[4];last.removed=true;now=127;boss:Tick(a)
assert(state.phase~='melee' and boss:AttackBlocked(a),'missing non-spider without death proof cannot unlock melee')
last.removed=nil;last.tags.dead=true;now=128
local mode,target=boss:Tick(b)
assert(mode=='attack' and target==others[5] and state.phase=='melee' and not state.wind,
 'only spiders and salamanders remain: stop wind and attack spider first')
assert(boss:AttackBlocked(a),'living spider blocks salamander melee')
others[5].removed=true;now=129;mode,target=boss:Tick(a)
assert(mode=='support' and boss:AttackBlocked(a),'missing spider without death confirmation never advances to salamanders')
others[5].removed=nil;others[5].tags.dead=true;now=130;mode,target=boss:Tick(b)
assert(mode=='attack' and target==a,'confirmed spider death advances to nearest salamander')
assert(c.gear.forced_weapon==sword and not c.arena_wind,'melee releases tornado equipment ownership')
assert(not boss:AttackBlocked(a) and boss:AttackBlocked(b),'melee attacks only the selected salamander')
assert(not guards[4](),'delayed wind from the former phase is cancelled after switching to melee')
b.pos=p.pos;mode,target=boss:Tick(b)
assert(target==a,'closer second salamander cannot interrupt the current kill')
a.tags.dead=true;mode,target=boss:Tick(a)
assert(mode=='attack' and target==b,'confirmed target death advances to the next salamander')
b.tags.dead=true;assert(not state:Tick() and state.finished,'last salamander death ends the dedicated tactic')
wave=7;assert(require('shadowself/control/arena_salamanders').Allowed(c,others[1]),'other waves retain their ordinary attack policy')
assert(recovered==0,'owned usable staff never triggers unrelated tool recovery')
-- 关键工具暂缺时继续沿用既有补捡路径，不能回退到排箫或提前近战。
wave=6;a.tags.dead=nil;b.tags.dead=nil
for _,e in ipairs(others) do e.tags.dead=nil end
c.arena_salamanders=nil;c.encounters=require('shadowself/control/encounters')(c)
now=200;boss:Tick(a);p.pos=goal;boss:Tick(a)
local beforeMissing=#casts;bag={flute,sword};now=215
assert(boss:Tick(a)=='support' and recovered==1 and #casts==beforeMissing and boss:AttackBlocked(a),'missing wind staff waits for real pickup without flute or premature melee')
for _,name in ipairs(names) do package.loaded['shadowself/control/'..name]=saved[name] end
GetTime=oldTime
print('PASS: sixth-wave salamander source roster, no penguin flute, actual edge15, three acknowledged winds then one-wind add cleanup, death-proof transition and locked one-by-one melee')
