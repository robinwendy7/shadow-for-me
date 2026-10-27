-- 采用原版DoRecipeClick/BuilderCanAccessIngredientRecipe的访问条件。
-- KnowsRecipe不包含附近科技站提供的accessible_tech_trees；调味粉nounlock必须检查原型制作。
local A=require("shadowself/control/actions")
local M={}
local function name(prefab) return STRINGS and STRINGS.NAMES and STRINGS.NAMES[prefab:upper()] or prefab end
function M.Check(p,recipe)
    if not recipe then return false,"没有找到这种调味粉的本地制作配方。","recipe" end
    local builder=p.replica and p.replica.builder
    if not builder then return false,"角色的制作状态还没有同步。","sync" end
    if recipe.builder_tag and not p:HasTag(recipe.builder_tag) then
        return false,"当前角色不能研磨"..name(recipe.product or recipe.name).."，需要沃利的厨师能力。","role"
    end
    local access=builder:KnowsRecipe(recipe)
    if not access then
        local learn=builder.CanLearn and builder:CanLearn(recipe.name)
        if not learn then return false,"当前角色不能使用这份研磨配方。","role" end
        local trees=builder.GetTechTrees and builder:GetTechTrees()
        access=trees and CanPrototypeRecipe and CanPrototypeRecipe(recipe.level,trees)
    end
    if not access then return false,"没有收到研磨器的制作科技，请确认靠近的是已部署的便携研磨器。","technology" end
    if not builder:HasIngredients(recipe) then
        local missing={}
        for _,v in ipairs(recipe.ingredients or {}) do
            local have=A.Count(p,v.type)
            if have<v.amount then missing[#missing+1]=name(v.type).."（"..have.."/"..v.amount.."）" end
        end
        return false,#missing>0 and "研磨材料不足："..table.concat(missing,"、") or "研磨材料尚未被制作系统确认。","ingredients"
    end
    return true
end
return M
