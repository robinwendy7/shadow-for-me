-- 仅第二关的鸟类持续攻击：按当前真实武器距离逼近，目标移动后重新追击。
local M={}
function M.Active(c,e)
 return c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==2
  and c.plan.arena_bird_committed and c.plan.arena_bird_committed(e) or false
end
function M.Reach(c,e)
 local combat=c.player.replica and c.player.replica.combat
 local range=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or c.gear:AttackRange()
 -- 向内留少量预测误差，不扩大怪物或武器攻击范围。
 return math.max(.5,range+e:GetPhysicsRadius(0)-.2)
end
function M.Chase(c,e)
 return M.Active(c,e) and e:IsValid() and c.player:GetPosition():DistSq(e:GetPosition())>M.Reach(c,e)^2
end
return M
