local M={}
local planar={sword_lunarplant=30,voidcloth_scythe=18,pickaxe_lunarplant=10,shovel_lunarplant=10,shadow_battleaxe=10,spear_wathgrithr_lightning_charged=20}
local bodies={lunarthrall_plant=true,mutatedwarg=true,mutateddeerclops=true,mutatedbearger=true,gestalt_guard_evolved=true,shadowthrall_hands=true,shadowthrall_horns=true,shadowthrall_wings=true,shadowthrall_mouth=true,shadowthrall_centipede=true,wagboss_robot=true,lunar_grazer=true,gelblob=true,ruins_shadeling=true,fused_shadeling=true}

function M.Planar(item)
 local p=item.components and item.components.planardamage
 if p and p.GetDamage then return p:GetDamage() end
 return planar[item.prefab] or 0
end
function M.Electric(player)
 local d=player.components and player.components.debuffable
 if d and d.HasDebuff then return d:HasDebuff("buff_electricattack") end
 return GetTime()<((player._shadowself_combat_buffs or {}).electric_until or 0)
end
function M.Score(player,item,physical,target)
 local special=M.Planar(item)
 if item.prefab=="nightstick" and not M.Electric(player) then
  local wet=target and (target.GetIsWet and target:GetIsWet() or target:HasTag("wet"))
  physical=physical*((TUNING and TUNING.ELECTRIC_DAMAGE_MULT or 1.5)+(wet and (TUNING and TUNING.ELECTRIC_WET_DAMAGE_MULT or 1) or 0))
 end
 local planarbody=target and ((target.components and target.components.planarentity) or bodies[target.prefab])
 if planarbody then physical=(math.sqrt(physical*4+64)-8)*4 end
 local defense=target and target.components and target.components.planardefense
 if defense then special=math.max(0,special-defense:GetDefense()) end
 local score=physical+special
 -- Prefer a planar weapon against planar bodies when one is carried.
 if planarbody and M.Planar(item)>0 then score=score+25 end
 return score
end
return M
