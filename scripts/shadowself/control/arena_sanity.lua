-- 第十一关起共享既有补给tick与进食确认，不启动独立操作循环。
local A=require("shadowself/control/actions")
local Food=require("shadowself/control/arena_food")
local Inv=require("shadowself/control/arena_inventory")
local M={}
function M.Tick(arena)
 if arena.wave<11 then return false end
 local h=arena.healing
 if not h or not h.SanityFood then return false end
 local stage=arena.stage11
 if stage and stage.buffs and stage.buffs.pending then return false end
 if h.pending and not h.pending.sanity_food then return false end
 if not arena.rest_actions then
  require("shadowself/legacy/action_library")
  arena.rest_actions=require("shadowself/legacy/registry").ActionLibrary(arena.player,{})
 end
 local c={player=arena.player,enemies=arena:NearbyEnemies(60),observed={},hazards=arena.fire_zones or {},actions=arena.rest_actions,
  plan={arena=true,arena_wave=function() return arena.wave end},bridge={PauseAttack=function() arena:StopCombat() end}}
 local hp,max=h:Health()
 -- 濒死回血先处理；辣冻等已发出的进食也由原流程完成，避免重复动作。
 if not h.pending and hp and max and hp/max<=.4 then return false end
 if h.pending or h:SanityFood(c) then
  local active=h:Tick(c)
  if active or h.pending and not h.pending.interrupted then
   arena:Say("第十一关起 · SAN低于100，食用高回理智料理并确认实际恢复")
   return true
  end
  if h.pending then return false end
 end
 if h.pending or arena.player.components.playercontroller:IsBusy() or arena.player:HasTag("attack") then return false end
 local function central_pig()
  local s=arena.stage11
  return arena.wave==11 and s and s.boss and s.boss.prefab=="daywalker2" and s:Cleared()
 end
 -- 拾荒疯猪残局的地面备用料理收集不能抢走中央绕堆控制权；已携带料理仍可正常食用。
 if central_pig() then return false end
 local bag=A.Items(arena.player);local keep=Inv.RetainedMeals(bag,arena.player);local current=0
 for item in pairs(keep) do if item.prefab~="voltgoatjelly_spice_chili" then current=Food.Sanity(item,arena.player) end end
 local best,score
 for _,item in ipairs(arena.items or {}) do
  local value=Food.Sanity(item,arena.player)
  if not (arena.ignored and (arena.ignored[item.GUID] or 0)>GetTime())
   and item.prefab~="sweettea" and item.prefab~="voltgoatjelly_spice_chili" and value>current
   and (not score or value>score) and Inv.Want(item,bag,arena.player,arena.wave)
   and h:Safe(c,item:GetPosition(),Food.Duration(item)+.5) and h:Path(c,item:GetPosition()) then best,score=item,value end
 end
 if not best then return false end
 local wave,id,generation=arena.wave,arena.instance,arena.generation
 local function guard()
  return arena.running and arena.wave==wave and arena.instance==id and arena.generation==generation and best:IsValid()
   and not central_pig()
   and h:Safe(c,best:GetPosition(),Food.Duration(best)+.5) and h:Path(c,best:GetPosition())
 end
 arena:StopCombat()
 if arena:Loot({best},false,guard) then arena:Say("第十一关起 · 额外保留一格高回理智料理");return true end
 return false
end
return M
