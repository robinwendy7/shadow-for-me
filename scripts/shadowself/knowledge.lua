-- 游戏知识与情境问答：名称 -> 原版配方/说明/当前库存，不把关键词数量当理解能力。
local A=require("shadowself/control/actions")
local K={}
local function has(s,list) for _,v in ipairs(list) do if s:find(v,1,true) then return true end end end
local function carried(r,prefab)
    local n=A.Count(r.owner,prefab)
    local inv=r.owner.replica.inventory
    for _,item in pairs(inv.GetEquips and inv:GetEquips() or {}) do
        if item.prefab==prefab then n=n+(item.replica.stackable and item.replica.stackable:StackSize() or 1) end
    end
    return n
end
local function display(prefab) return STRINGS.NAMES[prefab:upper()] or prefab end
local function names()
    local out={}
    for key,name in pairs(STRINGS.NAMES) do
        if type(name)=="string" and #name>=3 then out[#out+1]={name=name,prefab=key:lower()} end
    end
    table.sort(out,function(a,b) return #a.name>#b.name end)
    return out
end
function K.Match(text,r)
    if not STRINGS or not STRINGS.NAMES or not r.owner then return nil end
    -- 执行指令交给接管请求；此处只回答问题，绝不触发制作动作。
    if text:find("帮我",1,true) or text:find("替我",1,true) or text:find("停止",1,true) or text:find("取消",1,true) then return nil end
    local craft=has(text,{"怎么做","怎么造","如何做","如何制作","怎样做","怎么制作","怎么合成","合成配方","制作配方","需要什么材料","要什么材料","需要哪些材料","要哪些材料","用什么材料","用哪些材料","材料是什么","配方是什么","的配方","怎么搓","如何合成"})
    local missing=has(text,{"缺什么","差什么","缺多少","还差多少","缺哪些材料","还缺哪些"})
    local can=has(text,{"能做吗","能做出来吗","做得出来吗","现在能造","现在能做","会做吗","会制作吗","能不能做","能做","会做","会造","能造"})
    local count=has(text,{"有多少","还有多少","有没有","有几个","有几组","剩多少","还剩几个","带了多少","带没带"})
    local use=has(text,{"有什么用","能干什么","能做什么","用来做什么","干嘛用","做什么用","用处","用途"})
    local about=has(text,{"是什么","是干嘛","介绍一下","介绍下","讲讲","说说"})
    if not (craft or missing or can or count or use or about) then return nil end
    local chosen
    K.index=K.index or names()
    for _,v in ipairs(K.index) do if text:find(v.name,1,true) then chosen=v;break end end
    if not chosen and r.memory.last_item and has(text,{"它","这个","刚才那个","那件","配方","还缺","还有多少"}) then
        chosen={prefab=r.memory.last_item,name=display(r.memory.last_item)}
    end
    if not chosen then return nil end
    local prefab,name=chosen.prefab,chosen.name;r.memory.last_item=prefab
    local recipe=AllRecipes and AllRecipes[prefab]
    if not recipe and GetValidRecipe then recipe=GetValidRecipe(prefab) end
    if count then return name.."，你随身带着"..carried(r,prefab).."个。没有把关着的箱子算进来。","item_stock" end
    if missing and recipe then
        local parts={}
        for _,ing in ipairs(recipe.ingredients or {}) do
            local lack=math.max(0,ing.amount-carried(r,ing.type))
            if lack>0 then parts[#parts+1]=display(ing.type).."×"..lack end
        end
        return #parts>0 and ("按基础配方，还缺："..table.concat(parts,"、").."。") or ("基础材料已经带齐。"..(recipe.placer and "记得给它留个位置。" or "可以再确认一下制作栏。")),"item_missing"
    end
    if can and recipe and not use then
        local b=r.owner.replica.builder
        local learned=b and b:KnowsRecipe(recipe)
        local material=b and b:HasIngredients(recipe)
        if learned and material then return name.."的制作知识和材料都够。要让我做，就说“帮我制作"..name.."”。","item_can_craft" end
        return not material and (name.."的材料还没满足。可以问我“"..name.."还缺什么”。") or (name.."还需要先满足制作知识或科技条件。"),"item_can_craft"
    end
    if craft or missing then
        if recipe then
            local parts={}
            for _,ing in ipairs(recipe.ingredients or {}) do parts[#parts+1]=display(ing.type).."×"..ing.amount end
            return name.."的基础配方："..table.concat(parts,"、").."。","item_recipe"
        end
        local cooking=require("cooking")
        for cooker,recipes in pairs(cooking.recipes) do
            if recipes[prefab] then
                local d=require("shadowself/control/foodplan").Resolve(name)
                local role=d and require("shadowself/control/foodplan").RequiresWarly(d)
                return name.."是烹饪料理。"..(role and "这道需要沃利的便携厨具。" or "要在锅里做。").."说“帮我做"..name.."”，我会按现有食材检查能否配出来，再向你要接管同意。","item_food"
            end
        end
        return name.."没有可查的普通制作配方，别直接把它当制作栏物品。","item_recipe"
    end
    if use then
        local list={}
        for key,rec in pairs(AllRecipes or {}) do
            for _,ing in ipairs(rec.ingredients or {}) do if ing.type==prefab then list[#list+1]=display(rec.product or key);break end end
        end
        table.sort(list)
        if #list>0 then
            local head={};for i=1,math.min(6,#list) do head[#head+1]=list[i] end
            return name.."可作为制作材料，例如："..table.concat(head,"、")..(#list>6 and "等。" or "。"),"item_uses"
        end
    end
    local desc=STRINGS.RECIPE_DESC and STRINGS.RECIPE_DESC[prefab:upper()]
    if type(desc)=="string" and desc~="" then return name.."："..desc,"item_description" end
    return "你说的是"..name.."。它的详细用途我这里没有可靠说明，配方和随身库存倒是能帮你查。","item_description"
end
return K
