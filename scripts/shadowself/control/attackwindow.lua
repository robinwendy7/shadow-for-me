-- 蜂后/龙蝇按下一次命中截止时间预留进场、出刀、退场；只约束远程客户端。
local Net=require("shadowself/control/nettiming")
local Nav=require("shadowself/control/navigation")
local M={}
local function profile(e)
 if not e then return end
 if require("shadowself/control/status").Sleeping(e) or require("shadowself/control/status").Frozen(e) then return end
 if e.prefab=="beequeen" then return {hit=14,period=TUNING.BEEQUEEN_ATTACK_PERIOD or 2,radius=(TUNING.BEEQUEEN_HIT_RANGE or 6),bait=TUNING.BEEQUEEN_ATTACK_RANGE or 4} end
 if e.prefab=="warg" or e.prefab=="mutatedwarg" or e.prefab=="claywarg" or e.prefab=="gingerbreadwarg" then
  for _,n in ipairs({"atk_breath_pre","atk_breath_loop","atk_breath_pst"}) do if e.AnimState and e.AnimState:IsCurrentAnimation(n) then return end end
  return {hit=11,period=TUNING.WARG_ATTACKPERIOD or 3,radius=TUNING.WARG_ATTACKRANGE or 4,bait=TUNING.WARG_ATTACKRANGE or 4}
 end
 if e.prefab=="dragonfly" then return {hit=15,period=TUNING.DRAGONFLY_ATTACK_PERIOD or 4,radius=TUNING.DRAGONFLY_HIT_RANGE or 5,bait=TUNING.DRAGONFLY_ATTACK_RANGE or 4} end
end
function M.Observe(c,e)
 if not Net.Remote() then return end
 local cfg=profile(e);if not cfg or not e.AnimState then return end
 c.attack_windows=c.attack_windows or setmetatable({},{__mode="k"})
 local s=c.attack_windows[e] or {};c.attack_windows[e]=s
 local active=e.AnimState:IsCurrentAnimation("atk");local f=e.AnimState:GetCurrentAnimationFrame() or 0
 if active and (not s.active or f<(s.frame or 0)) then
  local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
  s.start=GetTime()-f*(FRAMES or 1/30)-ping/2000;s.bait_retreat=nil
 end
 s.active=active;s.frame=f;return s,cfg
end
function M.Blocked(c,e)
 if not c or not c.player or not Net.Remote() then return false end
 local s,cfg=M.Observe(c,e);if not s then return false end
 if s.active and s.frame<=cfg.hit+2 then return true end
 if not s.start then return e.prefab=="beequeen" end
 local p=c.player:GetPosition();local q=e:GetPosition();local distance=math.sqrt(p:DistSq(q))
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or 2)+e:GetPhysicsRadius(0)
 local safe=cfg.radius+c.player:GetPhysicsRadius(0)+.4
 local speed=Net.Speed(c)
 local cost=math.max(0,distance-reach)/speed+.3+math.max(0,safe-reach)/speed+Net.Delay(c)+2/30
 return s.start+cfg.period+cfg.hit/30-GetTime()<=cost
end
function M.Tick(c,e)
 local s,cfg=M.Observe(c,e);if not s or not M.Blocked(c,e) then return false end
 local p=c.player:GetPosition();local q=e:GetPosition();local d=math.max(.01,math.sqrt(p:DistSq(q)))
 local radius=cfg.radius+c.player:GetPhysicsRadius(0)+.5
 if cfg.bait and (not s.start or not s.active and GetTime()>=s.start+cfg.period) then
  local bait=cfg.bait+c.player:GetPhysicsRadius(0)-.05
  if d<=bait then s.bait_retreat=true;s.retry=GetTime()+.7 end
  if s.bait_retreat and GetTime()>=(s.retry or 0) and d>=radius-.2 then s.bait_retreat=nil end
  if not s.bait_retreat then radius=bait end
 end
 local goal=Vector3(q.x+(p.x-q.x)/d*radius,0,q.z+(p.z-q.z)/d*radius)
 local point=Nav.Select(c,goal,e)
 c.bridge:PauseAttack();c.travel:BeginDodge(c.snapshot);c:Move(point,"联机战斗 · 留出退场时间，先撤再补刀")
 return true
end
return M
