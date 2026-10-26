local oldTime=GetTime;local now=0;GetTime=function() return now end
local toolsKey='shadowself/control/arena_tools';local oldTools=package.loaded[toolsKey]
package.loaded[toolsKey]={Owned=function() end}
local Rabbit=require('shadowself/control/arena_rabbit')
local id=73000
local function ent(name,x)
 id=id+1
 local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,0),tags={},replica={},anim='idle',listeners={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 function e:ListenForEvent(name,fn) self.listeners[name]=fn end
 function e:RemoveEventCallback(name,fn) if self.listeners[name]==fn then self.listeners[name]=nil end end
 e.AnimState={IsCurrentAnimation=function(_,name) return e.anim==name end,GetCurrentAnimationFrame=function() return 50 end}
 return e
end
local p=ent('wilson');local king=ent('rabbitking_aggressive',8)
local adds={ent('rabbitkingminion_bunnyman',6),ent('rabbitkingminion_bunnyman',7),ent('rabbitkingminion_bunnyman',9)}
local roster={king};local wave=5;local goal;local kingdanger=false
local c={player=p,enemies=roster,gear={},actions={SafePoint=function() return true end},bridge={PauseAttack=function() end},
 plan={arena=true,arena_wave=function() return wave end,arena_entities=function() return roster end,
 arena_remaining=function() return roster end,arena_center=function() return Vector3(0,0,0) end}}
c.bosses={routes={Rabbit=function() return kingdanger and {fn=function() return Vector3(-4,0,0) end} or nil end}}
local owner={c=c,Release=function() end,Target=function(_,e) return e end,
 Move=function(_,q) goal=q;return 'move' end,Away=function() return 'move' end}
local s=Rabbit(owner)
assert(Rabbit.Required(c) and s:Tick()=='attack' and s.target==king,'opening attacks king immediately')
for _,e in ipairs(adds) do roster[#roster+1]=e end
assert(s:Tick()=='move' and s.phase=='kite' and not Rabbit.Allowed(c,king),'three actual summons start movement-only stage')
now=20;assert(s:Tick()=='move' and not s.edge_since,'walking toward the outer ring is not seven seconds of patrol')
p.pos=goal;now=21;s:Tick();assert(s.edge_since==21)
kingdanger=true;assert(s:Tick()=='move' and goal.x==-4 and s.phase=='kite','king attack preempts multi-minion patrol');kingdanger=false
now=24.99;assert(s:Tick()=='move' and s.phase=='kite','no attack before the full four-second outer patrol')
now=25;assert(s:Tick()=='move' and s.phase=='bait','four seconds ends patrol, not permission to attack before bait')
local bait=s.bait_target;assert(bait and not Rabbit.Allowed(c,bait))
bait.anim='atk';local mode,first=s:Tick()
assert(mode=='attack' and first~=king and first~=s.spare and s.phase=='adds','after four seconds and actual minion attack, attack one selected minion, preserving the spare')
first.tags.dead=true;s:Tick();assert(s.phase=='kite','remaining two minions restart four second patrol')
p.pos=goal;now=26;s:Tick();now=30;s:Tick();local nextbait=s.bait_target
nextbait.anim='atk';s:Tick();local second=s.target
assert(second~=first and second~=s.spare and second~=king,'second selected minion remains distinct from the preserved one')
second.tags.dead=true
second.listeners.onremove();second.removed=true
mode=s:Tick()
assert(mode=='attack' and s.phase=='king' and s.target==king and not Rabbit.Allowed(c,s.spare),
 'two confirmed deaths including removal transition to king-only output, never the last minion')
s.spare.anim='atk'
assert(Rabbit.Ignore(c,s.spare) and not Rabbit.Ignore(c,king),'only minion danger is ignored during king output')
local nav=require('shadowself/control/navigation')
assert(nav.Risk(c,s.spare.pos,king)==0,'navigation does not reroute king attacks around the retained minion')
assert(Rabbit.Ignore({c=c},s.spare),'secondary-route context observes the same scoped minion exception')
king.anim='spawn_loop'
assert(not Rabbit.Ignore(c,s.spare) and not Rabbit.Allowed(c,king),'king temporarily untargetable restores minion avoidance')
assert(s:Tick()=='move','unattackable king yields to actual minion avoidance rather than standing in support mode')
king.anim='idle';wave=6
assert(not Rabbit.Ignore(c,s.spare) and Rabbit.Allowed(c,s.spare) and not Rabbit.Required(c),'other waves retain their normal target and threat rules')
s:Stop()
assert(not c.arena_rabbit and not c.arena_patrol and not adds[1].listeners.onremove,'stop releases movement and death callbacks')
package.loaded[toolsKey]=oldTools;GetTime=oldTime
print('PASS: wave5 rabbit king opening, three-summon outer7s, two confirmed minion kills, spare preservation, scoped minion threat suppression and stop cleanup')
