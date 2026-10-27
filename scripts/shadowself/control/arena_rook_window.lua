-- 第三关残局准备窗：两秒内允许安全短距离攻击接近，只在实际攻击距离内计挥击。
local M={}
function M.Allow(c,e)
 if not e or not require("shadowself/control/targetpolicy").Rook(e) then return false end
 if not c or not c.bridge or require("shadowself/control/targetpolicy").ClockworkRook(c.bridge)~=e then return false end
 local recovery=c.bosses and c.bosses.rooks and c.bosses.rooks[e]
 if recovery and recovery.wait then return false end
 local a=e.AnimState;local pre=a and a:IsCurrentAnimation("atk_pre");local paw=a and a:IsCurrentAnimation("paw_loop")
 if not pre and not paw then c.rook_window=nil;return false end
 local now=GetTime();local f=a:GetCurrentAnimationFrame() or 0;local s=c.rook_window
 if not s or s.target~=e or pre and (s.anim~="atk_pre" or f<(s.frame or 0)) then
  s={target=e,since=now-(paw and math.max(.5,f/30) or f/30),hits=0};c.rook_window=s
 end
 s.anim=pre and "atk_pre" or "paw_loop";s.frame=f
 local p=c.player;local pa=p.AnimState;local pf=pa and pa:GetCurrentAnimationFrame() or 0
 local combat=p.replica and p.replica.combat
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange()
  or combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)+e:GetPhysicsRadius(0)
 local distance=math.sqrt(p:GetPosition():DistSq(e:GetPosition()))
 local attacking=p:HasTag("attack")
 local raw=require("shadowself/native").Get().ENT_util:GetAnimation(p)
 if attacking then
  if not s.attacking or s.pa~=raw or pf<(s.pf or 0) then s.counted=nil end
  if not s.counted and distance<=reach and c.h.ent==e and c.h.IsHitingFrame and c.h:IsHitingFrame(0,e,true) then s.hits=s.hits+1;s.counted=true end
 else s.counted=nil end
 s.attacking=attacking;s.pa=raw;s.pf=pf
 local remaining=2-(now-s.since)
 if remaining<=0 or s.hits>=2 then return false end
 local gap=math.max(0,distance-reach)
 if gap>0 then
  local speed=math.max(1,math.min(6,c.Speed and c:Speed() or 6))
  local ping=(TheNet and TheNet.GetPing and TheNet:GetPing() or 0)/1000
  -- 只补上一小步，留下至少一刀和网络余量；不会为凑两刀长距离追上冲撞线。
  if gap>1.5 or gap/speed+.55+ping>=remaining then return false end
 end
 local start=p:GetPosition();local center=e:GetPosition()
 local scale=math.max(0,reach-.1)/math.max(.01,distance)
 local goal=gap>0 and Vector3(center.x+(start.x-center.x)*scale,0,center.z+(start.z-center.z)*scale) or start
 local plan=c.plan or c.bridge.plan
 local roster=plan and plan.arena_remaining and plan.arena_remaining() or c.enemies or {}
 for _,other in ipairs(roster) do
  if (other.prefab=="knight" or other.prefab=="knight_nightmare") and other:IsValid() and not other:HasTag("dead") and not other:HasTag("isdead") then
   local attack=other.replica and other.replica.combat
   local radius=(attack and attack.GetAttackRangeWithWeapon and attack:GetAttackRangeWithWeapon() or 2)
    +other:GetPhysicsRadius(0)+p:GetPhysicsRadius(0)+.35
   for i=0,4 do
    local q=Vector3(start.x+(goal.x-start.x)*i/4,0,start.z+(goal.z-start.z)*i/4)
    if q:DistSq(other:GetPosition())<radius^2 then return false end
   end
  end
 end
 return gap==0 or require("shadowself/control/navigation").Safe(c,goal,e)
end
return M
