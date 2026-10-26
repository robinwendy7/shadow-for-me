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
local endrook=ent('rook');local endknight=ent('knight',-3,0)
c.bridge.plan={arena=true,arena_wave=function() return 3 end,arena_remaining=function() return {endrook,endknight} end}
c.bridge.allowed=function(e) return not e:HasTag('dead') end
local savedTime=GetTime;GetTime=function() return 0 end
local charge=require('shadowself/control/charge')
for _,name in ipairs({'rook','rook_nightmare'}) do
 endrook.prefab=name
 for _,pre in ipairs({'atk_pre','paw_loop'}) do
  endrook.anim=pre;endrook.frame=0;p.pos=Vector3(8,0,0)
  b.rooks[endrook]={ready=true,hits=1}
  assert(b:AttackBlocked(endrook),'preparation outside the short approach radius closes the previous attack window')
  assert(b:Rook(endrook)=='move' and math.abs(c.moved.x-8)<.01 and math.abs(c.moved.z)>=2.2,'preparation immediately issues a lateral dodge instead of moving backward on the collision line')
  assert(not b.rooks[endrook].ready,'preparation cannot retain the old two-hit window')
  c.charge_windup=nil;c.charge_data=nil;c.charge_target=nil
  assert(charge(c,endrook,false),'third-wave native bridge also bypasses the old preparation delay at frame zero')
 end
end
GetTime=savedTime;endrook.prefab='rook';c.charge_target=nil
endrook.anim='atk';p.pos=Vector3(0,0,3)
assert(b:Rook(endrook)=='move' and c.moved.z>=3.1,'rook endgame first clears the actual attack radius before following beside the charging front')
p.pos=Vector3(3,0,0);b:Rook(endrook)
assert(math.abs(c.moved.x-3)<.01 and c.moved.z>=2.2,'head-on collision lane clears sideways before moving with the charge')
-- 冲撞时保持战车侧旁，停下立即交还攻击，不能产生走到脸上的指令。
local savedNav=package.loaded['shadowself/control/navigation']
package.loaded['shadowself/control/navigation']={Safe=function() return true end}
local advance=assert(loadfile('scripts/shadowself/control/arena_rook.lua'))()
package.loaded['shadowself/control/navigation']=savedNav
local state={};p.pos=Vector3(0,0,4);endrook.pos=Vector3(0,0,0)
local first=advance(c,endrook,state,true)
assert(first.x>endrook.pos.x and first.z>=3.5,'charge advances ahead of the current rook along a safe side lane')
endrook.pos=Vector3(3,0,0)
local following=advance(c,endrook,state,true)
assert(following.x>endrook.pos.x and following.z>=3.5,'follow anticipates the moving rook while remaining outside its charge line')
local rotation=180;endrook.Transform.GetRotation=function() return rotation end
local reversed=advance(c,endrook,state,true)
assert(reversed.x<3,'a reversed charge advances in the new direction instead of preserving an obsolete endpoint')
rotation=0;endrook.pos=Vector3(0,0,0);state={}
for _,name in ipairs({'knight','knight_nightmare'}) do
 endknight.prefab=name;endknight.pos=Vector3(0,0,3);endknight.anim='atk';endknight.frame=10
 local away,label=advance(c,endrook,state,true)
 assert(state.knight==endknight and away.z>4 and label:find('骑士'),'knight range entry preempts forward advance immediately')
 p.pos=away
 assert(advance(c,endrook,state,true).z>=away.z,'early attack windup retains the knight evade')
 endknight.frame=16
 local onward=advance(c,endrook,state,true)
 assert(not state.knight and onward.z>=3.5,'completed knight evade resumes the rook side lane without attacking knight')
 p.pos=Vector3(0,0,4);state={}
end
assert(b:AttackBlocked(endknight),'the temporary knight evade never authorizes hitting knight')
-- 在躲骑士期间看见战车刹停，也必须记住两刀窗口。
endknight.pos=Vector3(0,0,3);endknight.frame=10;endrook.anim='atk';b:Rook(endrook)
endrook.anim='atk_skid';assert(b:Rook(endrook)=='move' and b.rooks[endrook].ready,'rook recovery observed during knight dodge keeps the attack budget')
p.pos=Vector3(0,0,8);endknight.frame=16
assert(b:Rook(endrook)=='attack' and b.rooks[endrook].hits==0,'after knight dodge resume the stopped rook attack window')
endrook.anim='idle'
assert(b:Rook(endrook)=='attack','recovery remains an attack approach after skid changes to idle')
assert(not advance(c,endrook,state,false),'stopped rook generates no walk-to-face route')
-- 只剩骑士：每次攻击前摇都封锁输出，位移和前摇均结束才恢复。
endrook.tags.dead=true
for _,name in ipairs({'knight','knight_nightmare'}) do
 endknight.prefab=name;endknight.pos=Vector3(0,0,0);p.pos=Vector3(0,0,2)
 for cycle=1,2 do
  endknight.anim='atk';endknight.frame=0
  assert(b:AttackBlocked(endknight),'each knight windup blocks strikes immediately')
  assert(b:Knight(endknight)=='move','knight dodge outranks attacking')
  local escape=c.moved;local route=b:Dodge(endknight,{})
  assert(route.noattack and not route.breakdodgefn(),'native dodge cannot insert a mid-evade attack')
  p.pos=escape;endknight.frame=10
  assert(b:AttackBlocked(endknight),'arrival alone does not permit attacking into the swing')
  endknight.frame=16;p.pos=Vector3(0,0,2)
  assert(b:AttackBlocked(endknight),'animation end alone does not claim a completed displacement')
  p.pos=escape
  assert(b:AttackBlocked(endknight) and route.breakdodgefn(),'completed evade requires a fresh point-blank approach before attacking')
  assert(b:Knight(endknight)=='move','after evasion approach closest contact position')
  p.pos=c.moved
  assert(b:Knight(endknight)=='attack' and not b:AttackBlocked(endknight) and b:KnightCommitted(endknight),'at closest contact keep attacking until next windup')
  p.pos=Vector3(0,0,2)
 end
end
c.bridge.plan=nil
-- 所有疯猪动画均直通原表，专用路线不再接管。
local routes=b.routes;assert(not routes.Daywalker)
local pig=ent("daywalker");local sentinel={native=true}
for _,name in ipairs({"atk_slam_pre","atk_slam","run_pre","run_loop","atk3"}) do pig.anim=name;assert(routes:Dodge(pig,sentinel)==sentinel) end
Native.context=saved
local info=setmetatable({},{__index=_G});local fn=assert(loadfile("modinfo.lua"));setfenv(fn,info);fn()
local options={};for _,v in ipairs(info.configuration_options) do options[v.name]=v end
assert(options.speech_color.default=="red" and #options.speech_color.options==7 and options.speech_voice.default==true)
print("PASS: 0.12.20 rook default deny/actual skid or collide unlock/two impact budget/next cycle; daywalker native passthrough; seven-color and voice settings defaults")
