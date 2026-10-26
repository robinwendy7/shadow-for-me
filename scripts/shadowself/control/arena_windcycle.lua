-- 前六关既有外圈巡游战术共用节奏；实际施法次数仍以动作/耐久确认计数。
local M={first_seconds=15,repeat_seconds=7,first_casts=3,goat_first_casts=6,repeat_casts=1}
function M.Hold(c)
 c.arena_patrol=true
 if c.gear then
  c.gear.patrol_hand=require("shadowself/control/arena_tools").Owned(c,"cane")
  if c.gear.Swap then c.gear:Swap("move",c.snapshot) end
 end
end
function M.Release(c) c.arena_patrol=nil;if c.gear then c.gear.patrol_hand=nil end end
function M.Blocked(c)
 if c.arena_patrol then return true end
 local plan=c.plan;local wave=plan and plan.arena and plan.arena_wave and plan.arena_wave()
 if wave~=5 and wave~=6 then return false end
 for _,e in ipairs(c.enemies or {}) do
  local health=e.replica and e.replica.health
  if (wave==5 and e.prefab=="powder_monkey" or wave==6 and not c.arena_goat_melee and e.prefab=="lightninggoat") and e:IsValid()
   and not e:HasTag("dead") and not e:HasTag("isdead") and not (health and health.IsDead and health:IsDead()) then return true end
 end
 return false
end
return M
