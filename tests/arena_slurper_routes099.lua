local oldTime,oldWorld,oldSim=GetTime,TheWorld,TheSim
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
TheSim={FindEntities=function() return {} end}
local id=99000
local function ent(name,x,z)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={},anim='headslurpmiss',frame=0}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=ent('wilson',15);local near,far=ent('slurper',17),ent('slurper',35)
local c={player=p,enemies={far,near},plan={arena=true,arena_wave=function() return 5 end},bridge={allowed=function() return true end},gear={}}
local S=require('shadowself/control/arena_slurper');local W=require('shadowself/control/arena_attackwindows')
for wave=1,15 do c.plan.arena_wave=function() return wave end
 assert(S.Nearest(c,c.enemies)==near and W.Committed(c,near),'every arena wave shares nearest live slurper and its own missed-pounce window')
end
near.tags.INLIMBO=true;assert(S.Nearest(c,c.enemies)==far);near.tags.INLIMBO=nil
near.tags.NOCLICK=true;assert(S.Nearest(c,c.enemies)==far);near.tags.NOCLICK=nil
near.replica.inventoryitem={IsHeld=function() return true end};assert(S.Nearest(c,c.enemies)==far);near.replica.inventoryitem=nil
near.tags.dead=true;assert(S.Nearest(c,c.enemies)==far);near.tags.dead=nil
c.plan.arena=false;assert(not S.Nearest(c,c.enemies) and not W.Committed(c,near),'ordinary-world behavior is preserved');c.plan.arena=true
c.plan.arena_wave=function() return 5 end;c.actions={SafePoint=function() return true end};c.hazards={}
local goal;local boss={c=c,Select=function(_,e) c.bridge.priority_target=e;return e end,Release=function() end,
 Move=function(_,q) goal=q;return 'move' end,Away=function() return 'move' end}
c.bridge.PauseAttack=function() end
local Pack=assert(loadfile('scripts/shadowself/control/arena_snailpack.lua'))();local pack=Pack(boss)
pack.Weapon=function() return true end
local snail=ent('snurtle',-20);local third,fourth=ent('slurper',40),ent('slurper',45)
c.enemies={snail,far,near,third,fourth};c.plan.arena_entities=function() return c.enemies end
pack.target=far;pack.phase='fight'
local mode,target=pack:Tick();assert(mode=='attack' and target==near and pack:CanAttack(near) and not goal,'live far target is replaced by near missed-pounce target through real snail-pack scheduler')
p.pos=Vector3(32,0,0);mode,target=pack:Tick();assert(mode=='attack' and target==far,'movement updates nearest choice without waiting for former target death')
far.anim='atk';assert(not pack:CanAttack(far),'new target actual roll cannot inherit another target punish window')
far.anim='headslurpmiss';assert(pack:Tick()=='attack' and pack:CanAttack(far))
near.pos=Vector3(33,0,0);far.pos=Vector3(40,0,0);far.anim='atk';pack.target=far
local RealBoss=require('shadowself/control/bosses');local realBoss=RealBoss(c)
mode,target=realBoss:Tick(far)
assert(mode=='attack' and target==near and pack.target==near and pack.phase=='fight','real boss windup entry does not redirect a nearby punish window toward a distant rolling slurper')
near.pos=Vector3(17,0,0);far.pos=Vector3(35,0,0);far.anim='headslurpmiss'
-- Execute actual bridge pick closure, including a stale explicit priority target.
local f=assert(io.open('scripts/shadowself/control/combat.lua'));local src=f:read('*a');f:close()
local start=assert(src:find('local pick=function(object,...)',1,true));local stop=assert(src:find('self.wrappers.GetClosestTarget=',start,true))
local make=assert(loadstring('return function(self,plan,allowed,closest) '..src:sub(start,stop-1)..' return pick end'))()
c.bridge.player=p;c.bridge.coordinator=c;c.bridge.priority_target=near
local pick=make(c.bridge,c.plan,c.bridge.allowed,function() return near end)
assert(pick({selected_ents={[far]=true,[near]=true}})==far and c.bridge.priority_target==far,'real bridge priority wrapper does not re-lock the far slurper')
-- Real stage12 geometry: every strict per-monster route is blocked, but total risk can decrease.
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage12.lua'))();p.pos=Vector3(0,0,0);goal=nil
local arena={player=p,bridge={},enemies={},fire_zones={},StopCombat=function() end,Say=function() end,
 encounters={FindCenter=function() return Vector3(0,0,0) end,Move=function(_,q) goal=q end}}
local stage=Stage(arena);local a,b,d=ent('shadowthrall_horns',-2),ent('shadowthrall_hands',2),ent('ruinsnightmare',0,2)
stage.seen={[a]=false,[b]=false,[d]=false};stage.context.enemies={a,b,d}
assert(stage:Move(nil)=='hold' and goal and p.pos:DistSq(goal)>.1,'crowded shadow12 cannot stand waiting for all eight-unit circles to disappear')
local before,after=0,0
for _,e in ipairs({a,b,d}) do before=before+math.max(0,8-math.sqrt(p.pos:DistSq(e.pos)))^2;after=after+math.max(0,8-math.sqrt(goal:DistSq(e.pos)))^2 end
assert(after<before,'fallback genuinely reduces combined eight-unit risk rather than bypassing all safety')
goal=nil;TheWorld.Map.IsPassableAtPoint=function() return false end;stage:Move(nil);assert(not goal,'impassable ground remains blocked during escape fallback')
GetTime,TheWorld,TheSim=oldTime,oldWorld,oldSim
print('PASS: all-wave slurper scope and nearest valid target, actual pack switch/own attack window, actual bridge stale-priority replacement, shadow12 combined-risk escape and impassable ground')
