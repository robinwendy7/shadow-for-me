local saved={time=GetTime,world=TheWorld,sim=TheSim}
local nk,rk='shadowself/control/navigation','shadowself/control/guardianroute'
local oldNav,oldRoute=package.loaded[nk],package.loaded[rk]
local selections=0;local blocked=false
package.loaded[nk]={Safe=function() return not blocked end,Select=function(_,q) selections=selections+1;return Vector3(999,0,999) end}
package.loaded[rk]=nil
local R=require('shadowself/control/guardianroute');local G=assert(loadfile('scripts/shadowself/control/guardian.lua'))()
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return not blocked end,IsOceanAtPoint=function() return false end},
 Pathfinder={IsClear=function() return not blocked end}}
local function ent(n,x,z,r)
 local e={prefab=n,pos=Vector3(x,0,z),radius=r or .5,tags={},anim='idle'}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end};e.Transform={GetRotation=function() return 0 end}
 return e
end
-- 日志672.27秒：仍在柱子另一侧，但实际Boss→玩家线已从柱旁穿过。
local king=ent('minotaur',567.72119140625,605.09942626953,1.5)
local pillar=ent('pillar_ruins',576.08,603.93,2);pillar.tags.charge_barrier=true
local logged=Vector3(579.19915771484,0,610.29675292969)
assert((logged.x-pillar.pos.x)*(king.pos.x-pillar.pos.x)+(logged.z-pillar.pos.z)*(king.pos.z-pillar.pos.z)<0)
assert(not R.Aligned(king,pillar,logged),'old opposite-half-plane test incorrectly retained this missed-charge goal')
local p=ent('wilson',2,0);king.pos=Vector3(0,0,0);king.radius=.5;pillar.pos=Vector3(6,0,0);pillar.radius=.5
local nextP=ent('pillar_ruins',0,10);nextP.tags.charge_barrier=true
local roster={pillar,nextP};TheSim={FindEntities=function() return roster end}
local c={player=p,plan={arena=true,arena_wave=function() return 9 end},bridge={chasing=true},travel={chasing=true},actions={Stop=function() end}}
local goal,exact;local boss={c=c,routes={Leap=function(_,e) return e.anim=='jump_atk_pre' end},Release=function() end,
 Move=function(_,q,_,_,verified) goal=q;exact=verified;return 'move' end};c.bosses=boss
king.anim='stun_loop';assert(G.Tick(boss,king)=='attack')
king.anim='idle';now=.1;assert(G.Tick(boss,king)=='move' and exact)
local wait=boss.guardian.wait_goal
for i=1,30 do p.pos=goal;now=now+.05;if G.Tick(boss,king)=='support' then break end end
assert(p.pos:DistSq(wait)<.65^2 and boss.guardian.phase=='lure','verified short legs reach the actual waiting point')
local base={atkanim='paw_loop'};king.anim='paw_loop'
assert(not G.Dodge(c,king,base),'pre-charge cannot steal pillar ownership')
king.anim='bite';assert(G.Dodge(c,king,base)==base,'actual bite retains defensive response')
king.anim='jump_atk_pre';assert(G.Dodge(c,king,base)==base,'leap remains an actual danger')
king.anim='stun_hit'
for i=1,80 do
 local mode=G.Tick(boss,king)
 if mode=='attack' then break end
 assert(mode=='move','blocked turn-back must detour before output');p.pos=goal;now=now+.05
end
assert(G.Tick(boss,king)=='attack','resume output after the turn-back detour reaches attack range')
king.anim='idle';now=now+.1;G.Tick(boss,king)
assert(boss.guardian.pillar==nextP,'one output round selects another pillar')
-- 不可达时不回退到通用Nav.Select的任意空地，也不把原地当成成功移动。
blocked=true;now=now+.1;local before=selections
assert(G.Tick(boss,king)=='support' and not boss.guardian.pillar and selections==before)
blocked=false
-- 真实Boss:Move验证第四参数；指定路线不经过第二次通用选点。
local Boss=assert(loadfile('scripts/shadowself/control/bosses.lua'))()
c.bridge.PauseAttack=function() end;c.travel.BeginDodge=function() end;c.Move=function(_,q) goal=q end
local q=Vector3(3,0,4);Boss.Move({c=c},q,'test',king,true)
assert(goal==q and selections==before)
Boss.Move({c=c},q,'ordinary',king);assert(selections==before+1 and goal.x==999,'ordinary world movement stays unchanged')
package.loaded[nk],package.loaded[rk]=oldNav,oldRoute
GetTime,TheWorld,TheSim=saved.time,saved.world,saved.sim
print('PASS: logged rhino missed-charge geometry, completed output to next-pillar wait, paw-loop ownership, bite/leap exceptions, blocked-route reselect and exact Boss movement integration')
