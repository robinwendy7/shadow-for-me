local oldTime,oldWorld=GetTime,TheWorld;local oldNav=package.loaded['shadowself/control/navigation']
local now=0;GetTime=function() return now end
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),replica={},tags={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end
 return e
end
local p=ent('wilson',-603.17669677734,-162.90557861328)
local dogs={ent('icehound',-590,-170),ent('icehound',-590,-174),ent('icehound',-586,-170),ent('icehound',-586,-174)}
local fish,frog,reeds=ent('merm'),ent('frog'),ent('reeds')
local entities={fish,frog,reeds};for _,e in ipairs(dogs) do entities[#entities+1]=e end
local W=require('shadowself/control/arena_whip');local w=W();w:Update(2,{fish,frog},false,entities)
local blocked=false
TheWorld={Map={IsPassableAtPoint=function(_,x,_,z) return not blocked and math.abs(x+600)<=20 and math.abs(z+160)<=20 end,
 IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return not blocked end}}
-- 重现通用规划无解，但实际存在远离全部睡眠狗的短路。
package.loaded['shadowself/control/navigation']={Safe=function() return false end,Escape=function() end,Risk=function() return 0 end}
local moves=0;local goal;local pauses=0
local c={player=p,plan={arena=true,arena_wave=function() return 2 end,arena_whip_state=w},h={ent=fish},hazards={},snapshot={},enemies={},
 bridge={PauseAttack=function() pauses=pauses+1 end},travel={BeginDodge=function() end,EndDodge=function() end}}
function c:Move(q) moves=moves+1;goal=q end
local Bridge=assert(loadfile('scripts/shadowself/control/combat.lua'))();local b=setmetatable({}, {__index=Bridge})
assert(b:RetreatFromTraps(c) and moves==1 and goal and p.pos:DistSq(goal)>.1,
 'at logged14.965 dog distance supervision dispatches actual retreat even when generic navigation rejects all points')
local start=p.pos
for i=0,30 do
 local q=Vector3(start.x+(goal.x-start.x)*i/30,0,start.z+(goal.z-start.z)*i/30)
 for _,dog in ipairs(dogs) do
  local initial=math.max(0,15-math.sqrt(start:DistSq(dog.pos)))
  assert(math.max(0,15-math.sqrt(q:DistSq(dog.pos)))<=initial+.002,'whole exit route never goes deeper into any trap circle')
 end
end
for _,dog in ipairs(dogs) do assert(goal:DistSq(dog.pos)>15.4^2,'retreat ends outside all trap boundaries with actual clearance') end
p.pos=goal;assert(not b:RetreatFromTraps(c) and w:CanAttack(p),'real exit restores ordinary combat without a15-unit boundary deadlock')
-- 目标暂时丢失时也走同一监督入口，物理无路则报告阻挡而非声称已移动。
p.pos=start;c.h.ent=nil;blocked=true;local before=moves
assert(b:RetreatFromTraps(c) and moves==before and w.evade_status=='blocked','no valid terrain cannot be reported as successful movement')
-- 已在安全拾鞭距离内时，仍交给原有拾取优先流程，不制造进15码又折返的循环。
local toolKey='shadowself/control/arena_tools';local oldTools=package.loaded[toolKey]
package.loaded[toolKey]={Owned=function() end,Usable=function() return true end}
local dropped=ent('whip',p.pos.x,p.pos.z);c.plan.arena_ground=function() return {dropped} end
assert(not b:RetreatFromTraps(c) and moves==before,'missing whip retains safe pickup-before-retreat handoff')
package.loaded[toolKey]=oldTools;c.plan.arena_ground=nil
c.plan.arena_wave=function() return 5 end
assert(not b:RetreatFromTraps(c),'new supervision priority is confined to wave2')
GetTime,TheWorld=oldTime,oldWorld;package.loaded['shadowself/control/navigation']=oldNav
print('PASS: real wave2 logged dog coordinates, supervision retreat priority, fallback with no generic route, whole-path/all-dog clearance, post-exit attack release and honest blocked status')
