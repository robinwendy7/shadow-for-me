local Native=require('shadowself/native');local savedNative=Native.context
local savedWorld=TheWorld
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local function entity(name)
 local e={prefab=name,pos=Vector3(0,0,0),anim='idle',frame=0,tags={},replica={}}
 function e:IsValid() return true end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
Native.context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local M=require('shadowself/control/arena_moose')
local p=entity('wilson');local goose=entity('moose');local other=entity('knight')
goose.replica.combat={GetAttackRangeWithWeapon=function() return 3 end}
p.pos=Vector3(2,0,0)
local wave=4
local c={player=p,plan={arena=true,arena_wave=function() return wave end},enemies={goose},observed={},hazards={},
 h={ent=goose,IsHitingFrame=function() return p.frame>=8 end},gear={AttackRange=function() return 2 end},
 actions={SafePoint=function() return true end}}
c.bridge={plan=c.plan,allowed=function() return true end}
local boss=require('shadowself/control/bosses')(c)
local base={atkanim='atk',dist=4}
local function swing()
 p.tags.attack=true;p.anim='atk';p.frame=1
 M.Observe(c,goose);p.frame=8;M.Observe(c,goose)
end
goose.anim='idle';goose.frame=0
assert(M.Hold(c,goose) and not boss:Dodge(goose,base),'safe recovery still allows the three-swing quota')
for cycle=1,3 do
 for i=1,3 do
  swing()
  for repeatFrame=1,4 do M.Observe(c,goose) end
  assert(c.arena_moose.hits==i,'one impact frame observed many times is still one swing')
  if i<3 then
   assert(M.Hold(c,goose) and not boss:AttackBlocked(goose) and not boss:Dodge(goose,base),'first two swings retain stationary attack despite goose windup')
  end
 end
 goose.anim='atk';goose.frame=0
 assert(not M.Hold(c,goose) and boss:AttackBlocked(goose),'third real swing blocks further output and releases movement')
 local data=boss:Dodge(goose,base)
 assert(data and data.noattack and data.exclusive,'three swings use existing exclusive native dodge with no premature follow-up')
 assert(data.fn():DistSq(goose.pos)>p.pos:DistSq(goose.pos),'dodge moves outside goose melee range')
 M.AfterDodge(c,goose);assert(c.arena_moose.hits==3,'starting a dodge does not reset the three-hit count')
 p.pos=data.fn();assert(not data.breakdodgefn(),'safe position alone cannot resume output before the actual incoming hit frame')
 goose.frame=20
 assert(data.breakdodgefn() and not boss:Dodge(goose,base),'past hit frame and safe distance finish the same native dodge')
 assert(c.arena_moose.hits==0,'observing a completed incoming attack releases stale retreat even if the old dodge callback was interrupted')
 M.AfterDodge(c,other);assert(c.arena_moose.hits==0,'an unrelated dodge does not alter the released counter')
 M.AfterDodge(c,goose);assert(c.arena_moose.hits==0 and M.Hold(c,goose),'completed dodge starts the next three-swing cycle')
 -- 即使玩家仍停在第三刀命中帧，也不能算作下一循环第一刀。
 assert(c.arena_moose.hits==0,'same animation impact cannot leak into the next cycle')
 p.pos=Vector3(2,0,0);goose.anim='idle';goose.frame=0
end
p.tags.attack=nil;M.Observe(c,goose)
p.tags.attack=true;p.frame=1;M.Observe(c,goose);p.frame=7;M.Observe(c,goose)
assert(c.arena_moose.hits==0,'cancelled swing before its hit frame and repeated requests do not count')
p.pos=Vector3(12,0,0);p.frame=8;M.Observe(c,goose)
assert(c.arena_moose.hits==0,'out-of-range swing does not satisfy the quota')
p.pos=Vector3(2,0,0);M.Observe(c,goose)
assert(c.arena_moose.hits==0,'walking into range after a missed impact does not turn it into a hit')
c.h.ent=other;p.frame=1;M.Observe(c,goose);p.frame=8;M.Observe(c,goose)
assert(c.arena_moose.hits==0,'swing directed at another creature is not a goose hit')
c.h.ent=goose
for i=1,3 do swing() end
goose.anim='hopatk';goose.frame=41
local hop=boss:Dodge(goose,base);p.pos=hop.fn()
assert(not hop.breakdodgefn(),'jump attack stays in dodge until its own actual 42-frame hit window')
goose.frame=42;assert(hop.breakdodgefn());M.AfterDodge(c,goose)
-- Actual SCD death-1: distance1.5, atk14 while still attacking; incoming hit20 must override an incomplete quota.
p.pos=Vector3(1.5,0,0);p.tags.attack=nil;goose.anim='idle';M.Observe(c,goose)
goose.anim='atk';goose.frame=14
assert(not M.Hold(c,goose) and boss:AttackBlocked(goose),'incoming deadline cancels stationary output even with fewer than three hits')
local emergency=boss:Dodge(goose,base)
assert(emergency and emergency.noattack and emergency.exclusive and c.arena_moose.hits<3,'incomplete quota cannot suppress actual goose windup')
p.pos=emergency.fn();assert(not emergency.breakdodgefn(),'must stay clear until the actual hit frame')
goose.frame=21;assert(emergency.breakdodgefn());M.AfterDodge(c,goose)
goose.anim='idle';assert(M.Hold(c,goose) and not c.arena_moose.evade,'completed emergency dodge releases attack control for a fresh cycle')
-- 最新日志atk20仍在5码处跑：命中点过后不能因负剩余时间再次触发撤离。
p.pos=Vector3(1.5,0,0);p.tags.attack=nil;goose.anim='atk';goose.frame=25
assert(M.Hold(c,goose) and not boss:AttackBlocked(goose) and not boss:Dodge(goose,base),'spent attack recovery immediately permits reengagement instead of relatching evade at close range')

wave=5;assert(boss:Dodge(goose,base)==base and not c.arena_moose,'other waves retain ordinary goose behavior and clear old counters')
wave=4;goose.tags.dead=true
assert(boss:Dodge(goose,base)==base and not M.Hold(c,goose),'dead goose cannot retain a quota or force another dodge')
Native.context=savedNative;TheWorld=savedWorld
print('PASS: wave4 goose three impact-frame swings before exclusive dodge; repeated cycles, duplicate/cancelled/out-of-range/other-target exclusion, normal/jump hit clearance and stage/death reset')
