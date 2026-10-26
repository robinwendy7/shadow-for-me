local keys={'shadowself/control/actions','shadowself/control/arena_walrus','shadowself/control/arena_fire'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k] end
local oldTime,oldWorld=GetTime,TheWorld;local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),tags={},replica={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local player=ent('wilson');player.components={playercontroller={IsBusy=function() return false end}}
local flute=ent('panflute');local bag={flute};local plays=0;local goal
package.loaded[keys[1]]={Items=function() return bag end,Stop=function() end,Move=function(_,q) goal=q end,
 Self=function(_,item,action) assert(item==flute and action==ACTIONS.PLAY);plays=plays+1;return true end}
package.loaded[keys[3]]={Safe=function() return true end};package.loaded[keys[2]]=nil
local a={player=player,bridge={},items={},StopCombat=function() end,Say=function() end}
local w=require(keys[2])(a)
local walrus,little,escort,trap=ent('walrus'),ent('little_walrus',2),ent('icehound',2,-2),ent('icehound',12)
trap.tags.sleeping=true
local all={walrus,little,escort,trap}
assert(w:Tick({walrus,little,escort},all) and goal and plays==0,'do not play while a sleeping icehound trap is inside real flute range')
assert(w:Covered(goal) and goal:DistSq(trap.pos)>(TUNING.PANFLUTE_SLEEPRANGE or 15)^2,'selected point controls the walruses while excluding the trap')
player.pos=goal;now=1;local _,hold=w:Tick({walrus,little,escort},all)
assert(hold and plays==1 and not w.control_done,'PLAY dispatch is not sleep confirmation')
walrus.tags.sleeping=true;little.tags.sleeping=true;escort.tags.sleeping=true
now=3;w:Tick({walrus,little},all)
assert(w.control_result=='sleep_confirmed' and w.target==walrus and not w:CanAttack(walrus),'sleep confirmation begins point-blank approach, not an early ranged-reach strike')
assert(w:Escort(escort) and not w:Escort(trap),'flute-controlled escort remains distinct from the original sleeping trap')
player.pos=goal;now=3.2;_,hold=w:Tick({walrus,little},all)
assert(not hold and w:CanAttack(walrus) and not w:CanAttack(little) and not w:CanAttack(escort),'only the closest-position walrus can receive the first attack')
assert(w:Committed(walrus),'point-blank approach commits walrus continuous attacks')
player.pos=Vector3(30,0,0);goal=nil;now=3.3
_,hold=w:Tick({walrus,little,escort},all)
assert(not hold and not goal and w:CanAttack(walrus),'after engagement target movement resumes attack approach without stopping combat or restarting walk-to-touch')
walrus.tags.dead=true;now=3.4;w:Tick({little},all)
assert(w.target==little and not w:CanAttack(little),'walrus death advances to the little walrus, still requiring approach')
player.pos=goal;now=3.6;w:Tick({little},all)
assert(w:CanAttack(little) and not w:CanAttack(escort),'little walrus must be reached before striking; icehound cannot jump the order')
assert(w:Committed(little) and not w:Committed(walrus),'little walrus engagement has its own hold-ground phase')
little.tags.dead=true;now=4;w:Tick({},all)
assert(w.target==escort and w:CanAttack(escort) and not w:CanAttack(trap),'after both walruses die, finish actual escort icehound while leaving trap untouched')
assert(not w:Committed(escort),'icehound combat restores ordinary evasion')
escort.tags.dead=true;w:Tick({},all);assert(not w.target and not w.active and w:CanAttack(ent('frog')),'all escorts dead releases other combined-wave targets without selecting the trap')
-- PLAY accepted but interrupted: old timeout incorrectly marked control_done and walked into the awake group.
local w2=require(keys[2])(a)
walrus.tags={};little.tags={};escort.tags={};player.pos=Vector3(-8,0,0);now=10
_,hold=w2:Tick({walrus,little,escort},all);assert(hold and w2.sent==10)
now=13.6;_,hold=w2:Tick({walrus,little,escort},all)
assert(hold and not w2.control_done and not w2:CanAttack(walrus) and not w2.sent,'unconfirmed sleep timeout never grants attack or point-blank approach')
local previousPlays=plays;now=13.8;w2:Tick({walrus,little,escort},all);assert(plays==previousPlays,'retry cooldown does not spam PLAY')
now=14.2;w2:Tick({walrus,little,escort},all);assert(plays==previousPlays+1 and w2.sent==14.2)
walrus.tags.sleeping=true;little.tags.sleeping=true;now=16.2
_,hold=w2:Tick({walrus,little,escort},all)
assert(hold and not w2.control_done and not w2:CanAttack(walrus),'both walruses asleep is insufficient while an escort hound is still awake')
escort.tags.sleeping=true;now=16.3;w2:Tick({walrus,little,escort},all)
assert(w2.control_done and w2.control_result=='sleep_confirmed','all intended group members must actually be asleep')
escort.tags.sleeping=nil;now=16.4;_,hold=w2:Tick({walrus,little,escort},all)
assert(hold and not w2.control_done and not w2:CanAttack(walrus),'waking before first engagement revokes stale sleep permission')
local far=ent('icehound',-30,0);w2.escorts[far]=true
assert(not w2:Covered(player.pos),'cast point must include escort hounds as well as walruses')
local w3=require(keys[2])(a);bag={};now=20
_,hold=w3:Tick({walrus,little,escort},all)
assert(hold and not w3.control_done and w3.control_result=='missing_flute' and not w3:CanAttack(walrus),'missing flute does not silently bypass required control')
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
GetTime=oldTime;TheWorld=oldWorld
print('PASS: walrus flute excludes trap radius, actual sleep ack, walrus/little/escort order and point-blank attack gating')
