-- 第四关麋鹿鹅：争取三次实际挥击；实际攻击剩余时间不足撤离时提前躲避。
local M={}
local function active(c,e)
 local plan=c and c.plan
 local h=e and e.replica and e.replica.health
 return plan and plan.arena and plan.arena_wave and plan.arena_wave()==4
  and e and e.prefab=="moose" and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead")
  and not (h and h.IsDead and h:IsDead())
end
local function radius(c,e)
 local combat=e.replica and e.replica.combat
 return math.max(TUNING.MOOSE_ATTACK_RANGE or 5.5,combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 0)
  +c.player:GetPhysicsRadius(0)+.9
end
local function imminent(c,e)
 local a=e.AnimState
 local hit=a and (a:IsCurrentAnimation("atk") and 20
  or (a:IsCurrentAnimation("hopatk") or a:IsCurrentAnimation("hopatk_loop")) and 42)
 if not hit then return false end
 if (a:GetCurrentAnimationFrame() or 0)>=hit then return false end
 local d=math.sqrt(c.player:GetPosition():DistSq(e:GetPosition()))
 if d>=radius(c,e) then return false end
 local speed=math.max(1,math.min(6,c.Speed and c:Speed() or 6))
 local reserve=(radius(c,e)-d)/speed+require("shadowself/control/nettiming").Delay(c)+.2
 return (hit-(a:GetCurrentAnimationFrame() or 0))/30<=reserve
end
function M.Observe(c,e)
 if not active(c,e) then
  if c and c.arena_moose and not active(c,c.arena_moose.target) then c.arena_moose=nil end
  return
 end
 local s=c.arena_moose
 if not s or s.target~=e then s={target=e,hits=0};c.arena_moose=s end
 local a=e.AnimState;local attack=a and (a:IsCurrentAnimation("atk") and 20
  or (a:IsCurrentAnimation("hopatk") or a:IsCurrentAnimation("hopatk_loop")) and 42)
 if s.started and attack then s.attack_seen=true end
 if s.started and s.attack_seen and (not attack or a:GetCurrentAnimationFrame()>=attack) then
  s.hits=0;s.started=nil;s.data=nil;s.evade=nil;s.attack_seen=nil
 end
 local p=c.player;local pa=p.AnimState
 local f=pa and pa:GetCurrentAnimationFrame() or 0
 local anim=require("shadowself/native").Get().ENT_util:GetAnimation(p)
 local attacking=p:HasTag("attack")
 if attacking then
  if not s.attacking or s.anim~=anim or f<(s.frame or 0) then s.counted=nil end
  if s.hits<3 and not s.counted and c.h and c.h.ent==e and c.h.IsHitingFrame and c.h:IsHitingFrame(0,e,true) then
   s.counted=true
   local combat=p.replica and p.replica.combat
   local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange()
    or combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)+e:GetPhysicsRadius(0)
   if p:GetPosition():DistSq(e:GetPosition())<=reach^2 then s.hits=s.hits+1 end
  end
 else s.counted=nil end
 s.attacking=attacking;s.anim=anim;s.frame=f
 if imminent(c,e) then s.evade=true end
 return s
end
function M.Hold(c,e)
 local s=M.Observe(c,e)
 return s and s.hits<3 and not s.evade or false
end
function M.Block(c,e)
 local s=M.Observe(c,e)
 return s and (s.hits>=3 or s.evade) or false
end
local function done(c,e)
 if not active(c,e) then return true end
 local a=e.AnimState;if not a then return false end
 local f=a:GetCurrentAnimationFrame() or 0
 -- 原生moose普通挥击20帧、跳击42帧；未过命中点时不折返抢攻。
 if a and (a:IsCurrentAnimation("atk") and f<20
  or (a:IsCurrentAnimation("hopatk") or a:IsCurrentAnimation("hopatk_loop")) and f<42) then return false end
 if a and (a:IsCurrentAnimation("atk") or a:IsCurrentAnimation("hopatk") or a:IsCurrentAnimation("hopatk_loop")) then return true end
 local s=c.arena_moose
 return s and s.attack_seen or c.player:GetPosition():DistSq(e:GetPosition())>=(radius(c,e)-.1)^2
end
function M.Dodge(c,e,base)
 local s=M.Observe(c,e)
 if not s then return base end
 if s.hits<3 and not s.evade then return nil end
 if s.started and done(c,e) then return nil end
 s.started=true
 if not s.data then
  s.data={point="target",dist=radius(c,e),update=true,exclusive=true,noattack=true,
   atkanim=function() return require("shadowself/native").Get().ENT_util:GetAnimation(e) end,
   fn=function()
    local p=c.player:GetPosition();local q=e:GetPosition()
    local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
    if d<.01 then dx,dz,d=1,0,1 end
    local r=radius(c,e)
    return require("shadowself/control/navigation").Select(c,Vector3(q.x+dx/d*r,0,q.z+dz/d*r),e)
   end,
   breakdodgefn=function() return done(c,e) end}
 end
 return s.data
end
function M.AfterDodge(c,e)
 local s=c.arena_moose
 if s and s.target==e and s.started and done(c,e) then
  s.hits=0;s.started=nil;s.data=nil;s.evade=nil;s.attack_seen=nil
  -- 保留当前挥击的去重标记，结束走位的同一帧不能再算一刀。
 end
end
-- 缴械回收只借已过命中点的后摇/鸣叫窗口；仍检查其他敌人和整段地形。
function M.PickupSafe(c,item)
 local e
 for _,v in ipairs(c.enemies or {}) do if active(c,v) then e=v;break end end
 if not e then return false end
 local a=e.AnimState;if not a then return false end
 local f=a:GetCurrentAnimationFrame() or 0
 local attack=a and (a:IsCurrentAnimation("atk") and 20
  or (a:IsCurrentAnimation("hopatk") or a:IsCurrentAnimation("hopatk_loop")) and 42)
 local p=c.player:GetPosition();local q=item:GetPosition()
 if p:DistSq(q)>8^2 then return false end
 local window=math.sqrt(p:DistSq(q))/math.max(1,c.Speed and c:Speed() or 6)+.3+require("shadowself/control/nettiming").Delay(c)
 local length=a and a.GetCurrentAnimationLength and a:GetCurrentAnimationLength()
 local remaining=length and math.max(0,length-f/30) or .5
 local spent=attack and f>=attack or a and a:IsCurrentAnimation("honk") and f>=17
 if not spent or remaining<window then return false end
 return require("shadowself/control/navigation").Safe(c,q,e)
end
return M
