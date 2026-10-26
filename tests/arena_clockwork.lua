local savedTime=GetTime
local oldNav=package.loaded['shadowself/control/navigation']
local oldRhythm=package.loaded['shadowself/control/arena_clockwork']
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end}
package.loaded['shadowself/control/arena_clockwork']=nil
local now=0;GetTime=function() return now end
local dead=false;local position=Vector3(2,0,0);local targetanim='idle'
local target={prefab='bishop_nightmare',replica={health={IsDead=function() return dead end}},AnimState={
 IsCurrentAnimation=function(_,n) return n==targetanim end,
 GetCurrentAnimationFrame=function() error('state-driven bishop must not read a fixed frame threshold') end}}
function target:IsValid() return true end;function target:HasTag() return false end
function target:GetPosition() return Vector3(0,0,0) end
local c={player={GetPosition=function() return position end},h={ent=target}}
local Rhythm=require('shadowself/control/arena_clockwork');local r=Rhythm(target)
local base={safe=function() return false end,breakdodgefn=function() return true end,
 fn=function() return Vector3(position.x,0,position.z+2) end}
for cycle=1,3 do
 targetanim='idle';assert(not r:Block(c) and not r:Dodge(c,target,base),'between volleys immediately allow continuous attacks')
 if cycle==1 then
 for _,state in ipairs({'atk2_pre','atk2_loop','atk2_pst'}) do
  targetanim=state;now=now+100
  local dodge=r:Dodge(c,target,base)
  assert(r:Block(c) and dodge and dodge.noattack and dodge.update,'every real aiming/charging/emission state blocks every attack')
  assert(dodge.fn==base.fn and not dodge.breakdodgefn(),'real mark-following route is retained while a stale base break cannot release attacks')
  position=dodge:fn();r:AfterDodge(c)
  assert(r:Block(c) and not dodge.breakdodgefn(),'reaching a dodge point cannot resume output during aiming or emission')
  now=now+1000;assert(r:Block(c),'elapsed time never ends an active real state')
 end
 else
  for _,state in ipairs({'atk2_pre','atk2_loop','atk2_pst','atk'}) do
   targetanim=state;assert(not r:Block(c) and not r:Dodge(c,target,base),'after first completed evade all later volleys retain continuous attack')
  end
 end
 targetanim='idle';r:AfterDodge(c)
 assert(not r:Block(c) and not r:Dodge(c,target,base) and r.phase=='attack','actual state exit releases attack without an extra timer')
end
assert(not r:Dodge(c,{},base),'other clockworks do not steal bishop focus')
target.prefab='bishop';targetanim='atk';r=Rhythm(target)
assert(r:Block(c) and r:Dodge(c,target,nil),'ordinary bishop uses actual attack state from its first observation')
targetanim='idle';assert(not r:Block(c))
dead=true;assert(r:Dodge(c,target,base)==base and r.phase=='done','bishop death restores ordinary combat behavior')
GetTime=savedTime
package.loaded['shadowself/control/navigation']=oldNav
package.loaded['shadowself/control/arena_clockwork']=oldRhythm
print('PASS: first bishop aim/charge/emission cycle uses real states, then holds continuous attack through later volleys until death; native hold-ground avoids extra movement')
-- Execute the shipped keyframe method: hold-ground must emit ATTACK without a later WALKTO,
-- including the idle frame immediately after a completed dodge.
local f=assert(io.open('scripts/shadowself/native/engine/HitAndRun.lua'));local src=f:read('*a');f:close()
local a=assert(src:find('\tfunction HitAndRun:OnKeyFrame()',1,true))
local z=assert(src:find('\nend\n--[[HitAndRun.resetguidanims',a,true))
local hits,walks=0,0;local attacking=false
local H={ent={GUID=7},walktime=1,shadowself_hold_ground=function() return true end,
 GetSpeed=function() return 6 end,CloseAndAttack=function() hits=hits+1 end,
 WalkTo=function() walks=walks+1 end,PredictWalkTo=function() walks=walks+1 end}
local env=setmetatable({HitAndRun=H,ThePlayer={HasTag=function(_,tag) return tag=='attack' and attacking end,PushEvent=function() end},
 MOD_util={GetMOption=function(_,_,default) return default end},FRAMES=1/30,GetTime=function() return 1 end},{__index=_G})
local fn=assert(loadstring(src:sub(a,z-1)));setfenv(fn,env);fn()
H:OnKeyFrame();attacking=true;H:OnKeyFrame()
assert(hits==2 and walks==0,'hold-ground attacks resume after dodge with no zero-length walk cancelling the queued attack')
