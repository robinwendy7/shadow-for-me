local Reporter = {}
local WorldInfo = require("shadowself/zom/WorldInfo")

local function Round(n) return math.floor((n or 0) + .5) end

local function InventoryLines(player)
    local inv = player.replica.inventory
    if inv == nil then return { "暂时无法查看物品栏。" } end
    local function Describe(items)
        local result, seen = {}, {}
        for _, item in pairs(items) do
            if item ~= nil and item:IsValid() and not seen[item.GUID] then
                seen[item.GUID] = true
                local stack = item.replica ~= nil and item.replica.stackable
                result[#result + 1] = item:GetBasicDisplayName() .. "×"
                    .. (stack ~= nil and stack:StackSize() or 1)
            end
        end
        table.sort(result)
        return #result > 0 and table.concat(result, "、") or "空空的"
    end
    local lines = { "物品栏有：" .. Describe(inv:GetItems()) .. "。" }
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then lines[#lines + 1] = "背包有：" .. Describe(overflow:GetItems()) .. "。" end
    return lines
end

Reporter.InventoryLines = InventoryLines

local function FreshFood(G, player)
    local inv = player.replica.inventory
    if inv == nil then return "暂时无法查看背包" end
    local result, seen = {}, {}
    local function Add(item)
        if item == nil or not item:IsValid() or seen[item.GUID] then return end
        seen[item.GUID] = true
        -- DST 原版 perishable 给新鲜食物同步 fresh；edible_* 是食物类型标签。
        if not item:HasTag("fresh") then return end
        local edible = false
        for _, foodtype in pairs(G.FOODTYPE or {}) do
            if item:HasTag("edible_" .. foodtype) then edible = true; break end
        end
        if not edible then return end
        local stack = item.replica ~= nil and item.replica.stackable
        result[#result + 1] = item:GetBasicDisplayName() .. "×"
            .. (stack ~= nil and stack:StackSize() or 1)
    end
    for _, item in pairs(inv:GetItems()) do Add(item) end
    local overflow = inv:GetOverflowContainer()
    if overflow ~= nil then for _, item in pairs(overflow:GetItems()) do Add(item) end end
    if inv.GetActiveItem ~= nil then Add(inv:GetActiveItem()) end
    table.sort(result)
    return #result > 0 and ("我身上新鲜的食物有：" .. table.concat(result, "、") .. "。")
        or "我身上暂时没有带新鲜度标签的食物。"
end

function Reporter.Get(G, player, topic, task)
    if topic == "stats" then
        local h = player.replica.health
        local u = player.replica.hunger
        local s = player.replica.sanity
        return string.format("当前三维：血量%d，饥饿%d，理智%d。",
            Round(h and h:GetCurrent()), Round(u and u:GetCurrent()), Round(s and s:GetCurrent()))
    elseif topic == "inventory" then
        return InventoryLines(player)
    elseif topic == "fresh_food" then
        return FreshFood(G, player)
    elseif topic == "mods" then
        return "已开启：自动解控、自动修复、自动切骨甲、功能小按钮。"
    elseif topic == "world_name" then
        local name = WorldInfo.GetName(G)
        return name ~= nil and ("我在" .. name .. "。")
            or "我暂时读不到世界编号，等多层世界同步后再问我吧。"
    elseif topic == "equipment" then
        local inv, result = player.replica.inventory, {}
        if inv ~= nil then
            for _, item in pairs(inv:GetEquips()) do
                if item ~= nil then result[#result + 1] = item:GetBasicDisplayName() end
            end
        end
        return "我装备着：" .. (#result > 0 and table.concat(result, "、") or "什么也没有") .. "。"
    elseif topic == "task" then
        return "当前任务是：" .. (task or "跟随与警戒") .. "。"
    elseif topic == "position" then
        local x, _, z = player.Transform:GetWorldPosition()
        return string.format("我在坐标 (%.0f, %.0f)。", x, z)
    elseif topic == "world" then
        local state = G.TheWorld.state
        local day = G.TheWorld.GetDay ~= nil and G.TheWorld:GetDay() or "?"
        return string.format("第%s天，季节%s，月相%s，天气%s。", tostring(day),
            tostring(state.season or "未知"), tostring(state.moonphase or "未知"),
            state.israining and "下雨" or "晴朗")
    elseif topic == "nearby" then
        local x, _, z = player.Transform:GetWorldPosition()
        local list = {}
        for _, ent in ipairs(G.TheSim:FindEntities(x, 0, z, 12, nil, { "INLIMBO" })) do
            if ent ~= player and ent:IsValid() and ent.prefab ~= nil then
                list[#list + 1] = ent:GetBasicDisplayName()
                if #list >= 6 then break end
            end
        end
        return "附近有：" .. (#list > 0 and table.concat(list, "、") or "暂时没发现特别的东西") .. "。"
    end
    return "我状态还不错，可以继续干活！"
end

return Reporter
