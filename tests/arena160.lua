local oldA=package.loaded['shadowself/control/actions'];local oldO=package.loaded['shadowself/control/arena_opening'];local oldE=package.loaded['shadowself/control/encounters'];local oldG=package.loaded['shadowself/control/arena_goats']
local oldTime,oldWorld=GetTime,TheWorld;local now=0;GetTime=function() return now end
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={combat={GetAttackRangeWithWeapon=function() return 3 end}}}
 function e:IsValid() return true end;function e:HasTag(k) return self.tags[k] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=ent('wilson');local busy=false;p.components={playercontroller={IsBusy=function() return busy end}}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local flute,staff=ent('panflute'),ent('staff_tornado');p.replica.inventory={GetEquippedItem=function() return staff end};local bag={flute};local plays,moves,casts=0,0,0
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 Move=function() moves=moves+1 end,Self=function() plays=plays+1;return true end,
 CastStaff=function(_,used,target,guard) assert(used==staff and (not guard or guard()));casts=casts+1;return true end}
package.loaded['shadowself/control/arena_opening']=nil
local arena={player=p,wave=3,bridge={},StopCombat=function() end}
local opening=require('shadowself/control/arena_opening')(arena);opening:Reset()
local bishop,knight,rook=ent('bishop',2),ent('knight',4),ent('rook',22)
assert(opening:Tick({bishop,knight}) and plays==0,'incomplete clockwork roster cannot trigger flute')
assert(opening:Tick({bishop,knight,rook}) and plays==0 and moves==1,'bishop in range alone is insufficient: move to all-three coverage')
p.pos=Vector3(11,0,0);now=.3
assert(opening:Tick({bishop,knight,rook}) and plays==1,'flute only when all three fit radius')
bishop.tags.sleeping=true;now=2.3
assert(opening:Tick({bishop,knight,rook}) and not opening.done,'bishop-only sleeping ack does not release opener')
knight.tags.sleeping=true;rook.tags.sleeping=true
assert(not opening:Tick({bishop,knight,rook}) and opening.done and opening.target==bishop)
package.loaded['shadowself/control/encounters']=nil
local c={player=p,plan={arena=true,arena_priority=function() return bishop end},enemies={},gear={},bridge={allowed=function(e) return not e.tags.sleeping end}}
local E=require('shadowself/control/encounters');local encounters=E(c)
encounters:Tick(knight);assert(c.bridge.priority_target==bishop,'ordinary encounter pulse preserves arena bishop focus')
local walrus=ent('walrus',10);c.enemies={walrus};local mode,target=encounters:Walrus(walrus)
assert(mode=='attack' and target==walrus,'arena forced-aggro walrus never tries to lose aggro')
local dog=ent('icehound',4);c.enemies={walrus,dog}
mode,target=encounters:Walrus(walrus);assert(mode=='attack' and target==dog,'awake dogs still precede arena walrus')
dog.tags.sleeping=true;mode,target=encounters:Walrus(walrus);assert(target==walrus,'sleeping trap dogs remain excluded')
local Fire=require('shadowself/control/arena_fire');local hole=ent('spiderhole',0);local zones=Fire.WebZones(p,{hole})
p.pos=Vector3(-8,0,0)
assert(#zones==1 and not Fire.Safe(p,Vector3(8,0,0),zones),'avoid crossing actual cave nest creep radius')
assert(Fire.Safe(p,Vector3(-8,0,7),zones),'safe route alongside web remains usable')
package.loaded['shadowself/control/arena_goats']=nil;bag={staff};p.pos=Vector3(0,0,0)
local owner={c={player=p,bridge={PauseAttack=function() end}},Target=function() end,Release=function() end,Move=function() return 'move' end,Away=function() return 'move' end}
local g=require('shadowself/control/arena_goats')(owner);local goat=ent('lightninggoat',5)
assert(g:Tick({goat})=='support' and casts==1,'cast at five yards instead of endlessly demanding seven yards')
goat.pos=Vector3(3.5,0,0);now=2.4
assert(g:Tick({goat})=='support' and casts==1,'brief cast commitment does not become retreat mid-action')
now=3.2;assert(g:Tick({goat})=='move','after cast, close crowded goat resumes escape')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/arena_opening']=oldO;package.loaded['shadowself/control/encounters']=oldE;package.loaded['shadowself/control/arena_goats']=oldG
GetTime=oldTime;TheWorld=oldWorld
print('PASS: all-three flute range/ack, persistent bishop focus, arena-only forced-aggro walrus, cave web route exclusion, practical tornado cast distance and commitment')
