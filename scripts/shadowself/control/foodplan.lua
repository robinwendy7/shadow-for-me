-- 直接读取游戏已注册配方，唯一最高优先级才采用，避免碰运气做出别的菜。
local cooking=require("cooking")
local M={}
local aliases={cookedsmallmeat="smallmeat_cooked",cookedmonstermeat="monstermeat_cooked",cookedmeat="meat_cooked"}
function M.RequiresWarly(dish)
    return dish.spice~=nil or not (cooking.recipes.cookpot or {})[dish.base]
end
function M.PowderIngredients(spice)
    local recipe=GetValidRecipe(spice)
    if not recipe then return nil end
    local ingredients={}
    for _,v in ipairs(recipe.ingredients or {}) do ingredients[v.type]=(ingredients[v.type] or 0)+v.amount end
    return next(ingredients) and ingredients or nil
end
function M.Resolve(text)
    local names={["肉丸"]="meatballs",["羊角冻"]="voltgoatjelly",["伏特羊角冻"]="voltgoatjelly",["辣羊角冻"]="voltgoatjelly_spice_chili",["辣椒羊角冻"]="voltgoatjelly_spice_chili"}
    local key=names[text]
    for _,recipes in pairs(cooking.recipes or {}) do for prefab in pairs(recipes) do
        local label=STRINGS and STRINGS.NAMES and STRINGS.NAMES[prefab:upper()]
        if prefab==text or label==text then key=prefab;break end
    end end
    local spiced=cooking.recipes.portablespicer or {}
    if not key then
        for _,v in ipairs({{"辣椒粉","spice_chili"},{"辣","spice_chili"},{"蒜香","spice_garlic"},{"蒜","spice_garlic"},{"咸","spice_salt"},{"盐","spice_salt"},{"甜","spice_sugar"},{"糖","spice_sugar"}}) do
            if text:sub(1,#v[1])==v[1] then
                local base=M.Resolve(text:sub(#v[1]+1))
                local product=base and not base.spice and base.base.."_"..v[2]
                if product and spiced[product] then key=product;break end
            end
        end
        if not key then
            for _,v in ipairs({{"辣椒粉","spice_chili"},{"蒜粉","spice_garlic"},{"盐","spice_salt"},{"糖","spice_sugar"}}) do
                for _,verb in ipairs({"加","撒","加上","撒上"}) do
                    local ending=verb..v[1]
                    if #text>#ending and text:sub(-#ending)==ending then
                        local base=M.Resolve(text:sub(1,#text-#ending))
                        local product=base and not base.spice and base.base.."_"..v[2]
                        if product and spiced[product] then key=product;break end
                    end
                end
            end
        end
    end
    if key then
        local base,spice=key:match("^(.-)_(spice_[%w_]+)$")
        base=base or key
        if not (cooking.recipes.cookpot or {})[base] and not (cooking.recipes.portablecookpot or {})[base] then return nil end
        if spice and not spiced[key] then return nil end
        return {product=key,base=base,spice=spice}
    end
end
function M.Parse(text,awaiting)
    local s=text:gsub("^%s+",""):gsub("%s+$","")
    for _,prefix in ipairs({"帮我做","替我做","给我做","做一道","做一份","做"}) do
        if s:sub(1,#prefix)==prefix then s=s:sub(#prefix+1);break end
    end
    if s=="饭" or s=="做饭" or s=="烹饪" or s=="帮我做饭" then return "ask" end
    local dish=M.Resolve(s)
    if dish then return dish end
    if awaiting then return nil,"这道菜我没在本地配方里找到。换个菜名，例如肉丸。" end
end
function M.Unique(cooker,list,product)
    local names,tags={},{}
    for _,raw in ipairs(list) do
        local name=aliases[raw] or raw;names[name]=(names[name] or 0)+1
        local ingredient=cooking.ingredients[name]
        if ingredient then for tag,n in pairs(ingredient.tags or {}) do tags[tag]=(tags[tag] or 0)+n end end
    end
    local highest=-math.huge;local choices={}
    for key,recipe in pairs(cooking.recipes[cooker] or {}) do
        if recipe.test(cooker,names,tags) then
            local priority=recipe.priority or 0
            if priority>highest then highest=priority;choices={key}
            elseif priority==highest then choices[#choices+1]=key end
        end
    end
    return #choices==1 and choices[1]==product
end
function M.Solver(cooker,product,counts)
    return coroutine.create(function()
        local keys={};for key,n in pairs(counts) do if n>0 and cooking.IsCookingIngredient(key) then keys[#keys+1]=key end end
        table.sort(keys)
        local selected,used={},{};local tries=0
        local function visit(start)
            if #selected==4 then
                tries=tries+1
                if M.Unique(cooker,selected,product) then local result={};for i,v in ipairs(selected) do result[i]=v end;return result end
                if tries%120==0 then coroutine.yield(false) end
                return
            end
            for i=start,#keys do
                local key=keys[i]
                if (used[key] or 0)<counts[key] then
                    used[key]=(used[key] or 0)+1;selected[#selected+1]=key
                    local result=visit(i)
                    selected[#selected]=nil;used[key]=used[key]-1
                    if result then return result end
                end
            end
        end
        return visit(1)
    end)
end
return M
