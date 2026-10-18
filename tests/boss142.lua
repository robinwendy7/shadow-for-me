-- 战车只在观察到冲刺结束后开放两刀，首次待机默认禁止。
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local function ent(n,x,z)
 local e={prefab=n,pos=Vector3(x or 0,0,z or 0),anim="idle",frame=0,tags={},replica={}}
 function e:IsValid() return true end;function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end;function e:HasTag(t) return self.tags[t] end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end};e.Transform={GetRotation=function() return 0 end};return e
end
local Native=require("shadowself/native");local saved=Native.context
Native.context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local p=ent("wilson",0,3);local stops=0
local c={player=p,enemies={},hazards={},observed={},snapshot={},h={IsHitingFrame=function() return p.frame>=8 end},
 bridge={PauseAttack=function() end},travel={BeginDodge=function() end,EndDodge=function() end},actions={SafePoint=function() return true end,Stop=function() stops=stops+1 end}}
function c:Move(q) self.moved=q end
local B=require("shadowself/control/bosses");local b=B(c)
for _,name in ipairs({"rook","rook_nightmare"}) do
 local e=ent(name);assert(b:AttackBlocked(e),"unobserved rook cannot be attacked")
 assert(b:Rook(e)=="move" and b:AttackBlocked(e),"idle is not charge completion")
 e.anim="atk_pre";assert(b:AttackBlocked(e));b:Rook(e);assert(b:AttackBlocked(e),"early windup not an initial output window")
 e.anim="atk";b:Rook(e);assert(b:AttackBlocked(e),"charging cannot be attacked")
 e.anim="idle";b:Rook(e);assert(b:AttackBlocked(e),"merely leaving charge without observed recovery does not unlock")
 e.anim="atk_skid";assert(b:Rook(e)=="attack" and not b:AttackBlocked(e),"actual skid unlocks two swings")
 for i=1,2 do
  p.tags.attack=true;p.anim="atk";p.frame=1;b:Rook(e);p.frame=8;b:Rook(e);b:Rook(e)
  assert(b.rooks[e].hits==i,"same impact frame counted only once")
  p.tags.attack=nil;b:Rook(e)
 end
 assert(b:AttackBlocked(e) and not b.rooks[e].ready,"two completed hits close window; skid cannot reopen each tick")
 b:Rook(e);assert(b:AttackBlocked(e))
 e.anim="atk";b:Rook(e);assert(b:AttackBlocked(e));e.anim="atk_collide";b:Rook(e);assert(not b:AttackBlocked(e) and b.rooks[e].hits==0,"next observed finish resets two-hit budget")
end
assert(stops==2)
-- 所有疯猪动画均直通原表，专用路线不再接管。
local routes=b.routes;assert(not routes.Daywalker)
local pig=ent("daywalker");local sentinel={native=true}
for _,name in ipairs({"atk_slam_pre","atk_slam","run_pre","run_loop","atk3"}) do pig.anim=name;assert(routes:Dodge(pig,sentinel)==sentinel) end
Native.context=saved
local info=setmetatable({},{__index=_G});local fn=assert(loadfile("modinfo.lua"));setfenv(fn,info);fn()
local options={};for _,v in ipairs(info.configuration_options) do options[v.name]=v end
assert(options.speech_color.default=="red" and #options.speech_color.options==7 and options.speech_voice.default==true)
print("PASS: 0.12.20 rook default deny/actual skid or collide unlock/two impact budget/next cycle; daywalker native passthrough; seven-color and voice settings defaults")
