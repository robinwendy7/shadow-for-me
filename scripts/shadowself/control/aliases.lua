-- 原模组已有的装备 prefab 优先保留：暗影香炉在 DST 源码中为 thurible。
local aliases = {
    ["暗影香炉"] = "thurible", ["暗影香炉道具"] = "thurible", ["骨甲"] = "armorskeleton",
    ["骨头"] = "skeletonhat", ["暗影秘典"] = "waxwelljournal", ["暗黑魔典"] = "waxwelljournal",
    ["步行手杖"] = "cane", ["手杖"] = "cane", ["懒人探险杖"] = "orangestaff",
    ["橙色法杖"] = "orangestaff", ["俗气鹅像"] = "goose_idol", ["怪物肉"] = "monstermeat",
    ["种子"] = "seeds", ["金子"] = "goldnugget", ["黄金"] = "goldnugget", ["灰烬"] = "ash",
    ["火把"] = "torch", ["锤子"] = "hammer", ["铲子"] = "shovel", ["排箫"] = "panflute",
    ["传送法杖"] = "telestaff", ["冰箱"] = "icebox", ["盐盒"] = "saltbox",
    ["箱子"] = "treasurechest", ["蜘蛛"] = "spider", ["树"] = "evergreen",
    ["草"] = "grass", ["浆果"] = "berrybush", ["胡萝卜"] = "carrot",
    ["芦苇"] = "reeds", ["矿石"] = "rock1", ["石头"] = "rock1",
    ["木板"] = "boards", ["绳子"] = "rope", ["药膏"] = "healingsalve",
    ["食物"] = "__food__",
    ["香炉"] = "thurible", ["骨头头盔"] = "skeletonhat", ["骨盔"] = "skeletonhat",
    ["暗影盔"] = "skeletonhat", ["暗影甲"] = "armorskeleton", ["魔典"] = "waxwelljournal",
    ["夜燃"] = "nightmarefuel", ["噩梦燃料"] = "nightmarefuel", ["燃料"] = "nightmarefuel",
    ["羊角冻"] = "voltgoatjelly", ["辣伏特羊角冻"] = "voltgoatjelly",
    ["肉丸"] = "meatballs", ["饺子"] = "perogies", ["蜜汁火腿"] = "honeyham",
    ["大肉"] = "meat", ["小肉"] = "smallmeat", ["浆果果酱"] = "jammypreserves",
    ["梦魇燃料"] = "nightmarefuel", ["木头"] = "log", ["树枝"] = "twigs",
    ["草绳"] = "rope", ["石头"] = "rocks", ["燧石"] = "flint",
    ["花瓣"] = "petals", ["蜘蛛丝"] = "silk", ["蜘蛛腺体"] = "spidergland",
    ["治疗药膏"] = "healingsalve", ["蜂蜜药膏"] = "bandage", ["齿轮"] = "gears",
    ["坎普斯背包"] = "krampus_sack", ["小偷包"] = "krampus_sack",
    ["长矛"] = "spear", ["暗影剑"] = "nightsword", ["火腿棒"] = "hambat",
    ["矿工帽"] = "minerhat", ["提灯"] = "lantern", ["火腿棍"] = "hambat",
    ["虫洞"] = "wormhole", ["时空洞"] = "pocketwatch_portal_entrance",
    ["大门"] = "multiplayer_portal", ["复活门"] = "multiplayer_portal",
    ["绚丽之门"] = "multiplayer_portal", ["复活石"] = "resurrectionstone",
    ["试金石"] = "resurrectionstone",
    ["月岩雕像"] = "moonrockidol", ["雕像"] = "moonrockidol",
    ["猪币"] = "pig_coin", ["猪鼻铸币"] = "pig_coin", ["千层铸币"] = "pig_coin",
    ["裂隙表"] = "pocketwatch_portal", ["溯源表"] = "pocketwatch_recall",
    ["不老表"] = "pocketwatch_heal", ["不老怀表"] = "pocketwatch_heal",
    ["暗夜灯"] = "nightlight", ["梦魇灯"] = "nightlight",
    ["恐怖盾牌"] = "shieldofterror", ["战争瓦器人"] = "wagboss_robot",
    ["紫宝石"] = "purplegem", ["天体传送门"] = "multiplayer_portal_moonrock",
    ["摇摇马"] = "yoth_chair_rocking", ["摇摇椅"] = "hermit_chair_rocking",
    ["木椅"] = "wood_chair", ["木凳"] = "wood_stool",
    ["石椅"] = "stone_chair", ["石凳"] = "stone_stool",
    ["熔合暗影"] = "fused_shadeling", ["融合暗影"] = "fused_shadeling",
    ["触手"] = "tentacle", ["天体英雄三阶段"] = "alterguardian_phase3",
    ["天体英雄3阶段"] = "alterguardian_phase3", ["三阶暗影骑士"] = "shadow_knight",
    ["暗影骑士"] = "shadow_knight", ["蜂后"] = "beequeen",
    ["织影者鬼手"] = "shadowchanneler", ["鬼手"] = "shadowchanneler",
}

local function Resolve(name, G)
    if name == nil then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    for _,mark in ipairs({"，",",","：",":","。","！","!"}) do
        while name:sub(1,#mark)==mark do name=name:sub(#mark+1) end
        while name:sub(-#mark)==mark do name=name:sub(1,-#mark-1) end
    end
    local value = aliases[name]
    if value ~= nil then return value end
    -- 支持原版中文显示名，不需要维护完整几千项静态表。
    local names = G.STRINGS ~= nil and G.STRINGS.NAMES or nil
    local partial, ambiguous = nil, false
    if names ~= nil then
        for prefab, display in pairs(names) do
            if type(display) == "string" and display == name then return prefab:lower() end
            if type(display) == "string" and #name >= 6 and display:find(name, 1, true) then
                if partial ~= nil and partial ~= prefab:lower() then ambiguous = true end
                partial = prefab:lower()
            end
        end
    end
    -- 只在匹配唯一时接受短名，避免把“肉”错认成某一道料理。
    if not ambiguous then return partial end
    return nil
end

return { Resolve = Resolve, Map = aliases }
