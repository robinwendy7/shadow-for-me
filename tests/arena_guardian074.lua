local oldTime,oldSim,oldWorld=GetTime,TheSim,TheWorld
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local navKey='shadowself/control/navigation';local oldNav=package.loaded[navKey]
local routeKey='shadowself/control/guardianroute';local oldRoute=package.loaded[routeKey];package.loaded[routeKey]=nil
package.loaded[navKey]={Safe=function() return true end,Select=function(_,q) return q end}
local G=assert(loadfile('scripts/shadowself/control/guardian.lua'))()
local now=0;GetTime=function() return now end
local function entity(name,x,z)
 local e={prefab=name,pos=Vector3(x,0,z),tags={},anim='idle'}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end}
 e.Transform={GetRotation=function() return 0 end}
 return e
end
local p=entity('wilson',2,0);local king=entity('minotaur',0,0)
local a=entity('pillar_ruins',6,0);local b=entity('pillar_ruins',0,10)
a.tags.charge_barrier=true;b.tags.charge_barrier=true
local roster={a};TheSim={FindEntities=function() return roster end}
local moves,stops=0,0;local goal
local c={player=p,plan={arena=true,arena_wave=function() return 9 end},bridge={chasing=true},travel={chasing=true},
 actions={Stop=function() stops=stops+1 end}}
local boss={c=c,routes={Leap=function() return false end},Release=function() end,
 Move=function(_,q) moves=moves+1;goal=q;return 'move' end}
c.bosses=boss
king.anim='stun_loop';assert(G.Tick(boss,king)=='attack','actual stun keeps its output window')
king.anim='idle';now=1
assert(G.Tick(boss,king)=='move','end of output immediately starts returning behind a real pillar')
local wait=boss.guardian.wait_goal
assert(wait and wait.x>a.pos.x and math.abs(goal.z)>1,'return goes around the pillar rather than walking through its centre')
local mode
for i=1,15 do
 p.pos=goal;now=now+.05;mode=G.Tick(boss,king)
 if mode=='support' then break end
end
assert(mode=='support' and p.pos:DistSq(wait)<.65^2,'return completes at the fixed behind-pillar waiting point')
local before=moves
king.pos=Vector3(.2,0,.15);now=now+.1
assert(G.Tick(boss,king)=='support' and moves==before and boss.guardian.wait_goal==wait,
 'minor boss movement cannot rotate the waiting point or issue wandering moves')
assert(stops==1 and not c.bridge.chasing and not c.travel.chasing,'arrival stops the old approach and releases stale chase ownership')
king.anim='atk';now=now+.1
assert(G.Tick(boss,king)=='support' and not G.Dodge(c,king,{}),'aligned charge retains behind-pillar waiting ownership')
king.anim='stun_hit'
for i=1,80 do
 local result=G.Tick(boss,king)
 if result=='attack' then break end
 assert(result=='move','next collision detours around the obstructing pillar');p.pos=goal;now=now+.05
end
assert(G.Tick(boss,king)=='attack','actual next collision resumes output after the blocked return path clears')
roster={a,b};king.anim='idle';now=now+.1
G.Tick(boss,king)
assert(boss.guardian.pillar==b and boss.guardian.wait_goal~=wait,'next completed output rotates to a different pillar and a new fixed waiting point')
b.tags.NOBLOCK=true;now=now+.1;G.Tick(boss,king)
assert(boss.guardian.pillar~=b,'destroyed or nonblocking pillar still triggers replanning')
-- 错位冲撞已经躲开时，不能每次以当前位置再加四码，越侧移越远。
roster={a};boss.guardian=nil;p.pos=Vector3(2,0,0);king.pos=Vector3(0,0,0)
king.Transform.GetRotation=function() return 90 end;king.anim='atk';now=10
assert(G.Tick(boss,king)=='move' and goal.x>4 and goal.x<5,'misaligned charge first exits only to the safe side of the actual charge line')
p.pos=goal;now=10.1;local beforeExit=moves
assert(G.Tick(boss,king)=='support' and moves==beforeExit,'safe side exit waits without issuing another relative four-unit sidestep')
assert(G.Dodge(c,king,{}):fn():DistSq(p.pos)<.001,'native dodge uses the same bounded exit instead of resuming endless side movement')
king.pos=Vector3(0,0,-2);now=10.2
assert(G.Tick(boss,king)=='support' and moves==beforeExit,'ongoing parallel charge cannot push a safe player farther across the arena')
king.anim='idle';now=10.3
assert(G.Tick(boss,king)=='move','charge end resumes the actual behind-pillar return')
package.loaded[navKey]=oldNav;package.loaded[routeKey]=oldRoute;GetTime,TheSim,TheWorld=oldTime,oldSim,oldWorld
print('PASS: wave9 output-to-pillar arc, fixed waiting goal, no idle wandering, aligned charge ownership, actual stun output and next-pillar rotation')
