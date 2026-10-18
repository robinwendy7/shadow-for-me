local Config = require("shadowself/zom/Config")

local function Trim(s)
    s = s or ""
    local marks = { "，", "：", "。", "！" }
    local previous
    repeat
        previous = s
        s = s:gsub("^[%s,:!]+", ""):gsub("[%s,:!]+$", "")
        for _, mark in ipairs(marks) do
            if s:sub(1, #mark) == mark then s = s:sub(#mark + 1) end
            if s:sub(-#mark) == mark then s = s:sub(1, -#mark - 1) end
        end
    until s == previous
    return s
end

local NUMBERS = { ["一"] = 1, ["二"] = 2, ["两"] = 2, ["三"] = 3, ["四"] = 4,
    ["五"] = 5, ["六"] = 6, ["七"] = 7, ["八"] = 8, ["九"] = 9, ["十"] = 10 }
local UNITS = { "个", "件", "把", "份", "只", "次", "块", "组", "颗" }

local function ExtractCount(text)
    text = Trim(text)
    local digits, rest = text:match("^(%d+)%s*(.*)$")
    if digits == nil then
        for word, number in pairs(NUMBERS) do
            if text:sub(1, #word) == word then
                local remainder = text:sub(#word + 1)
                for _, unit in ipairs(UNITS) do
                    if remainder:sub(1, #unit) == unit then
                        digits, rest = number, remainder
                        break
                    end
                end
                if digits ~= nil then break end
            end
        end
    end
    if digits ~= nil then
        rest = Trim(rest)
        for _, unit in ipairs(UNITS) do
            if rest:sub(1, #unit) == unit then rest = Trim(rest:sub(#unit + 1)); break end
        end
        return rest, tonumber(digits)
    end
    local before, trailing, suffix = text:match("^(.-)%s*(%d+)%s*(.-)$")
    if trailing ~= nil and before ~= "" then
        for _, unit in ipairs(UNITS) do
            if suffix == unit then return Trim(before), tonumber(trailing) end
        end
        if suffix == "" then return Trim(before), tonumber(trailing) end
    end
    return text, 1
end

local function Addressed(message)
    if type(message) ~= "string" then return nil end
    local lower = message:lower()
    local best, length
    for _, trigger in ipairs(Config.TRIGGERS) do
        local start = 1
        while true do
            local pos = lower:find(trigger:lower(), start, true)
            if pos == nil or pos > Config.PREFIX_MAX_BYTES then break end
            local prefix = message:sub(1, pos - 1)
            local before = pos > 1 and lower:sub(pos - 1, pos - 1) or ""
            local after = lower:sub(pos + #trigger, pos + #trigger)
            local ascii_boundary = trigger ~= "ai" or
                (not before:match("[%a%d]") and not after:match("[%a%d]"))
            -- 允许 @玩家名、名字加标点、空白；普通句子中途提到的不响应。
            local prefix_ok = prefix == "" or prefix:match("^[%s@＠%p，。！：、]+$")
                or prefix:find("@", 1, true) ~= nil or prefix:find("＠", 1, true) ~= nil
                or (#prefix <= 24 and prefix:match("^%S+%s+$"))
                or prefix:match("^[%s@＠%p，。！：、]*[^，。！：: ]+[，。！：:]%s*$")
            if ascii_boundary and prefix_ok and (best == nil or pos < best
                or (pos == best and #trigger > length)) then
                best, length = pos, #trigger
            end
            start = pos + 1
        end
    end
    if best == nil then return nil end
    return Trim(message:sub(best + length))
end

-- Seek 作为称呼时，绕过本地命令/问答分类。
local function SeekAddressed(message)
    if type(message) ~= "string" then return nil end
    local plain = message:match("^%s*(.-)%s*$") or ""
    if plain:sub(1, 4):lower() ~= "seek" then return nil end
    local after = plain:sub(5, 5)
    if after:match("[%a%d]") then return nil end
    return Trim(plain:sub(5))
end

local function Split(text)
    if text == "再来一次" then return { text } end
    local parts = {}
    local separators = { "然后", "接着", "之后", "同时", "再", "并" }
    while text ~= "" do
        local at, len
        for _, sep in ipairs(separators) do
            local p = text:find(sep, 1, true)
            if p ~= nil and (at == nil or p < at) then at, len = p, #sep end
        end
        if at == nil then parts[#parts + 1] = Trim(text); break end
        parts[#parts + 1] = Trim(text:sub(1, at - 1))
        text = Trim(text:sub(at + len))
    end
    return parts
end

local function ParseStep(raw)
    local s = Trim(raw)
    if s == "" then return nil end
    local lower = s:lower()
    for _, word in ipairs({ "重连", "重新进", "更新模组", "更新模型" }) do
        if s:find(word, 1, true) then return { kind = "reconnect" } end
    end
    for _, verb in ipairs({ "交互", "打开", "关闭" }) do
        local at = s:find(verb, 1, true)
        if at then
            local target = Trim(s:sub(at + #verb)):gsub("^这个", ""):gsub("^那个", "")
            if target ~= "" then return { kind = "interact", text = target, intent = verb } end
        end
    end
    if s == "救命" or s == "救我" or s == "救救我" or s == "复活我"
        or s == "快救我" or s == "帮我复活" or s == "快复活我"
        or s == "救命啊" or s == "把我复活" then
        return { kind = "wanda_revive" }
    end
    local rescue_name = s:match("^救%s*%((.-)%)$") or s:match("^救%s*（(.-)）$")
        or s:match("^救%s*(.+)$") or s:match("^去救%s*(.+)$")
        or s:match("^帮我救%s*(.+)$")
    if rescue_name ~= nil and Trim(rescue_name) ~= "" then
        return { kind = "wanda_revive", text = Trim(rescue_name) }
    end
    -- 按“拾取 + 脚边区域 + 全部”的语义组合识别，不写死某一句话。
    local all_items = s:gsub("物品", "东西"):gsub("物件", "东西"):gsub("物资", "东西")
    if (all_items:find("捡", 1, true) or all_items:find("拾取", 1, true)
        or all_items:find("收集", 1, true))
        and (all_items:find("脚下", 1, true) or all_items:find("脚边", 1, true)
            or all_items:find("附近", 1, true))
        and (all_items:find("所有", 1, true) or all_items:find("全部", 1, true)
            or all_items:find("全捡", 1, true) or all_items:find("捡光", 1, true)
            or all_items:find("都捡", 1, true) or all_items:find("全拾取", 1, true)) then
        return { kind = "pickup_nearby" }
    end
    -- 冒险命令放在通用“去X / 找X / 状态”之前，避免被普通寻路或问答吞掉。
    if lower:find("还有什么boss", 1, true) or lower:find("有什么boss", 1, true)
        or lower:find("剩什么boss", 1, true) or lower:find("查询冒险boss", 1, true)
        or lower:find("冒险boss列表", 1, true) or lower:find("现在哪些boss", 1, true)
        or s:find("还有什么首领", 1, true) then
        return { kind = "adventure_boss_list" }
    end
    local role = s:match("^去换%s*(.-)%s*角色$") or s:match("^换成%s*(.-)%s*角色$")
        or s:match("^换%s*(.-)%s*角色$")
    if role and role ~= "" then return { kind = "switch_character", text = Trim(role) } end
    if s == "旺达模式" or s == "开启旺达模式" then
        return { kind = "wanda_mode", enabled = true }
    end
    if s == "关闭旺达模式" or s == "不要自动开表" then
        return { kind = "wanda_mode", enabled = false }
    end
    local sector_text = s
    for _, prefix in ipairs({ "带我们去", "带大家去", "带我去", "带人去",
        "跳去", "前往", "去", "来", "跳", "到" }) do
        if sector_text:sub(1, #prefix) == prefix then
            sector_text = Trim(sector_text:sub(#prefix + 1))
            break
        end
    end
    local sector = sector_text:match("^(%d+)$")
        or sector_text:match("^(%d+)号$")
        or sector_text:match("^(%d+)板块$")
        or sector_text:match("^(%d+)号板块$")
        or s:match("^开%s*(%d+)号表$")
        or s:match("^打开%s*(%d+)号裂隙表$")
    if sector then return { kind = "sector_watch", sector = tonumber(sector) } end
    for grade, label in ipairs({ "旅者", "专家", "大师", "传奇" }) do
        if s:find(label, 1, true) and (s:find("猪币", 1, true)
            or s:find("铸币", 1, true) or s:find("找", 1, true)
            or s:find("定位", 1, true) or s:find("搜索", 1, true)
            or s:find("投币", 1, true)) then
            return { kind = "pig_coin_search", grade = grade }
        end
    end
    local coin_command = lower:gsub("%s+", "")
    if coin_command == "投币" or coin_command == "投猪币"
        or coin_command == "帮我投币" or coin_command == "用猪币"
        or coin_command == "猪币定位" or coin_command == "用猪币定位"
        or coin_command == "千层铸币" or coin_command == "点千层铸币"
        or coin_command == "找boss" or coin_command == "去找boss"
        or coin_command == "找冒险boss" or coin_command == "找首领"
        or coin_command == "用猪币找boss" or coin_command == "投币找boss" then
        return { kind = "pig_coin_search" } -- 未指定难度时取背包里的第一叠猪币。
    end
    if s == "停止所有行为" or s == "结束所有任务"
        or s == "停止全部行为" or s == "结束全部任务" then
        return { kind = "stop_all" }
    end
    if s == "打角" then return { kind = "arena_jump" } end
    if s == "自动战斗" or s == "战斗学习" or s == "开启自动战斗"
        or s == "开始战斗学习" then return { kind = "combat_learning", enabled = true } end
    if s == "关闭自动战斗" or s == "停止战斗学习" or s == "不要自动战斗" then
        return { kind = "combat_learning", enabled = false,
            stop_combat = s ~= "停止战斗学习" }
    end
    local approach = s:match("^走到%s*(.-)%s*附近$")
        or s:match("^到%s*(.-)%s*附近$")
    if approach ~= nil and Trim(approach) ~= "" then
        return { kind = "approach", text = Trim(approach) }
    end
    local cuddle = s:match("^和%s*(.-)%s*贴贴$")
    if cuddle ~= nil and cuddle ~= "" then
        return { kind = "cuddle", text = Trim(cuddle) }
    end
    if s == "停止划船" or s == "别划了" or s == "不要划船"
        or s == "停桨" or s == "停止划桨" then return { kind = "stop_row" } end
    local row_target, row_count = s:match("^朝%s*(.-)%s*划%s*(%d+)%s*次$")
    if row_target == nil then
        row_target, row_count = s:match("^朝%s*(.-)%s*划%s*([一二三四五六七八九十两]+)%s*次$")
    end
    if row_target ~= nil and row_target ~= "" then
        return { kind = "row", text = Trim(row_target), count = tonumber(row_count) or NUMBERS[row_count] }
    end
    row_target = s:match("^朝%s*(.-)%s*一直划船$")
        or s:match("^朝%s*(.-)%s*持续划船$")
    if row_target ~= nil and row_target ~= "" then
        return { kind = "row", text = Trim(row_target), continuous = true }
    end
    local placing = s:match("^放置%s*(.+)") or s:match("^摆放%s*(.+)")
    if placing ~= nil then
        local item, count = ExtractCount(placing)
        if item ~= "" then return { kind = "place", text = item, count = count } end
    end
    if s:find("你开了什么模组", 1, true) or s:find("开了哪些模组", 1, true)
        or s:find("你有什么功能", 1, true) or s:find("开启了什么功能", 1, true)
        or s:find("你会什么功能", 1, true) then
        return { kind = "status", topic = "mods" }
    end
    if s:find("哪个世界", 1, true) or s:find("什么世界", 1, true)
        or s:find("第几世界", 1, true) or s:find("在哪层", 1, true)
        or s:find("世界位置", 1, true) then
        return { kind = "status", topic = "world_name" }
    end
    local cx, cz = s:match("坐标%s*%(%s*(-?%d+)%s*,%s*(-?%d+)%s*%)")
    if cx == nil then cx, cz = s:match("坐标%s*（%s*(-?%d+)%s*，%s*(-?%d+)%s*）") end
    if cx ~= nil and (s:find("来我身边", 1, true) or s:find("到我身边", 1, true)
        or s:find("来我这", 1, true) or s:find("过来", 1, true)) then
        return { kind = "come_coordinate", x = tonumber(cx), z = tonumber(cz) }
    end
    local speech = s:match("^说%s*(.+)$") or s:match("^学我说%s*(.+)$")
        or s:match("^跟我说%s*(.+)$")
    if speech ~= nil then return { kind = "repeat_speech", text = Trim(speech) } end
    if s:find("你.*傻") or s:find("你.*笨") or s:find("你.*废物")
        or s:find("你.*垃圾") or s:find("你.*白痴")
        or s:find("你.*蠢") or s:find("你.*弱智")
        or s == "傻子" or s == "笨蛋" or s == "垃圾" or s == "废物" then
        return { kind = "insult" }
    end
    if s:find("开发者模式", 1, true) then
        return { kind = "developer_request" }
    end
    if s == "复活" or s:find("点击复活", 1, true)
        or s:find("买护符复活", 1, true) or s:find("帮我复活", 1, true) then
        return { kind = "hello_button", button = "autoBuyAmulet", mode = "once" }
    end
    if s:find("功能小按钮", 1, true) or s:find("小按钮面板", 1, true) then
        return { kind = "hello_button", button = "menu", mode = "open" }
    end
    local buttons = {
        { "自动跳洞", "autoClickPortal" }, { "自动点裂隙", "autoClickPortal" },
        { "检查Boss", "autoInspectBoss" }, { "检查boss", "autoInspectBoss" },
        { "自动检查Boss", "autoInspectBoss" }, { "女工挂机", "autoWinonaPuzzle" },
        { "自动下雨", "autoRain" }, { "自动称重", "autoWeighCrops" },
        { "自动存仓", "openMoveStore" }, { "亿点特效", "ancientTrail" },
    }
    for _, spec in ipairs(buttons) do
        if s:find(spec[1], 1, true) then
            return { kind = "hello_button", button = spec[2],
                mode = (s:find("关闭", 1, true) or s:find("停用", 1, true)
                    or s:find("关掉", 1, true) or s:find("停止", 1, true))
                    and "disable" or "enable" }
        end
    end
    local destination = s:match("^跳%s*去%s*(.+)$")
        or s:match("^跳%s*(.+)$") or s:match("^去%s*(.+)$")
        or s:match("^来%s*(.+)$") or s:match("^到%s*(.+)$")
    if destination ~= nil then
        destination = Trim(destination):gsub("来$", "")
        if destination:sub(1, #"世界") == "世界" then
            destination = Trim(destination:sub(#"世界" + 1))
        end
        -- 数字只表示旺达板块，跳世界只接受中文名称/简称。
        if tonumber(destination) ~= nil or NUMBERS[destination] ~= nil then
            return { kind = "world_name_required" }
        end
        local id
        for number, label in pairs(Config.WORLD_NAMES) do
            if destination == label then id = tonumber(number); break end
        end
        if id == nil then id = tonumber((Config.WORLD_ALIASES or {})[destination]) end
        if id ~= nil or s:find("世界", 1, true) then
            return { kind = "world_travel", world_id = id, text = destination }
        end
    end
    if s:find("恢复默认", 1, true) or s:find("默认模式", 1, true) then
        return { kind = "default_mode" }
    end
    if s:find("只控boss", 1, true) or s:find("只控BOSS", 1, true)
        or s:find("只控制boss", 1, true) or s:find("只控首领", 1, true)
        or s:find("只控老板", 1, true) then return { kind = "boss_only" } end
    if s:find("禁锢", 1, true) or s:find("魔典", 1, true)
        or s:find("暗影秘典", 1, true) or s:find("战斗小人", 1, true)
        or s:find("暗影保护者", 1, true) then
        return { kind = "shadow_skill", text = s }
    end
    if s:find("自动装备", 1, true) or s:find("自动穿戴", 1, true) then
        return { kind = "auto_equip" }
    end
    local seat = s:match("^坐在%s*(.+)") or s:match("^坐到%s*(.+)")
        or s:match("^坐%s*(.+)") or s:match("^骑%s*(摇摇马.*)")
    if seat ~= nil and (seat:find("椅", 1, true) or seat:find("凳", 1, true)
        or seat:find("摇摇马", 1, true)) then
        seat = Trim(seat:gsub("上面?$", ""))
        return { kind = "sit", text = seat }
    end
    if s == "坐下" or s == "坐一会儿" or s == "找个地方坐" then
        return { kind = "sit", text = "椅子" }
    end
    if s:find("智能装备", 1, true) or s:find("智能穿戴", 1, true) then
        return { kind = "smart_equip" }
    end
    if s:find("能复活", 1, true) or s:find("会复活", 1, true)
        or s:find("自己复活", 1, true) then return { kind = "revive_question" } end
    local exclude = s:match("^别控%s*(.+)") or s:match("^不要控%s*(.+)")
        or s:match("^别控制%s*(.+)") or s:match("^不要控制%s*(.+)")
    if exclude ~= nil then return { kind = "exclude_control", text = Trim(exclude) } end
    local force = s:match("^去控%s*(.+)") or s:match("^控住%s*(.+)")
        or s:match("^去控制%s*(.+)") or s:match("^控制%s*(.+)")
    if force ~= nil then return { kind = "force_control", text = Trim(force) } end
    if s:find("飘过来", 1, true) or s:find("飘到我这", 1, true)
        or s:find("灵魂跟我", 1, true) then return { kind = "ghost_follow" } end
    local ghost_x, ghost_z = s:match("^飘到?%s*坐标%s*[%(%（]?%s*(-?%d+)%s*[,，]%s*(-?%d+)")
    if ghost_x ~= nil then return { kind = "goto", x = tonumber(ghost_x), z = tonumber(ghost_z), text = "坐标" } end
    local ghost_place = s:match("^飘去%s*(.+)") or s:match("^飘到%s*(.+)")
    if ghost_place ~= nil then return { kind = "goto", text = Trim(ghost_place) } end
    local haunt = s:match("^作祟%s*(.+)") or s:match("^去作祟%s*(.+)")
        or s:match("^帮我作祟%s*(.+)") or s:match("^对%s*(.+)作祟$")
        or s:match("^闹鬼%s*(.+)") or s:match("^去闹鬼%s*(.+)")
        or s:match("^帮我闹鬼%s*(.+)") or s:match("^对%s*(.+)闹鬼$")
    if haunt ~= nil then
        haunt = Trim(haunt)
        for _, prefix in ipairs({ "附近的", "那边的", "那个", "这个", "一下" }) do
            if haunt:sub(1, #prefix) == prefix then haunt = Trim(haunt:sub(#prefix + 1)) end
        end
        if haunt ~= "" then return { kind = "haunt", text = haunt } end
    end
    if s == "闹鬼" or s == "作祟" then return { kind = "haunt", text = "" } end
    if s:find("查询主人", 1, true) or s:find("谁是主人", 1, true)
        or s:find("当前主人", 1, true) or s:find("跟随谁", 1, true)
        or s:find("权限人", 1, true) or s:find("谁有权限", 1, true) then
        return { kind = "status", topic = "owner" }
    end
    if s:find("解除跟随", 1, true) or s:find("解除主人", 1, true)
        or s:find("不跟我了", 1, true) or s:find("取消跟随", 1, true) then
        return { kind = "release_owner" }
    end
    if s:find("跳虫洞", 1, true) or s:find("钻虫洞", 1, true)
        or s:find("进虫洞", 1, true) then return { kind = "jump_wormhole" } end
    if s:find("换成", 1, true) == 1 then return { kind = "replace", text = Trim(s:sub(#"换成" + 1)) } end
    if s:find("再来一次", 1, true) or s == "重复" then return { kind = "repeat" } end
    if s == "继续" then return { kind = "continue" } end
    if s:find("别打", 1, true) or s:find("停止攻击", 1, true) then return { kind = "stopcombat" } end
    if s:find("停下", 1, true) or s:find("别动", 1, true) or s:find("待命", 1, true)
        or s:find("原地等候", 1, true) or s:find("取消", 1, true) or s:find("别跟", 1, true) then
        return { kind = "stop" }
    end
    if s:find("自由活动", 1, true) then return { kind = "free" } end
    if s:find("跟随", 1, true) or s:find("跟着我", 1, true)
        or s == "跟我" then return { kind = "follow" } end
    if s:find("来我这", 1, true)
        or s:find("来我身边", 1, true) or s:find("过来", 1, true)
        or s:find("到这来", 1, true) or s:find("到这里来", 1, true)
        or s:find("到我这来", 1, true)
        or s:find("保护我", 1, true) then
        return { kind = "approach", text = "我" } -- 走近一次，不开启持续跟随。
    end
    if s:find("报告三维", 1, true) or s:find("三维", 1, true) or s:find("血量", 1, true)
        or s:find("饥饿", 1, true) or s:find("理智", 1, true) or s == "状态" then
        return { kind = "status", topic = "stats" }
    end
    if s:find("有什么吃的", 1, true) or s:find("有啥吃的", 1, true)
        or s:find("有什么食物", 1, true) or s:find("有吃的吗", 1, true)
        or s:find("带了什么吃的", 1, true) then
        return { kind = "status", topic = "fresh_food" }
    end
    if s:find("装备了什么", 1, true) then return { kind = "status", topic = "equipment" } end
    if s:find("整理背包", 1, true) then return { kind = "unsupported", text = s } end
    if (s:find("背包", 1, true) or s:find("身上", 1, true)
        or s:find("物品", 1, true))
        and (s:find("什么", 1, true) or s:find("啥", 1, true)
            or s:find("哪些", 1, true) or s:find("清单", 1, true)
            or s:find("报告", 1, true) or s:find("查看", 1, true)
            or s:find("看看", 1, true))
        or s:find("报告物品", 1, true) then return { kind = "status", topic = "inventory" } end
    if s:find("在干嘛", 1, true) or s:find("当前任务", 1, true) then return { kind = "status", topic = "task" } end
    if s:find("在哪", 1, true) or s:find("位置", 1, true) or s:find("坐标", 1, true) then
        if not s:find("去", 1, true) then return { kind = "status", topic = "position" } end
    end
    if s:find("附近有什么", 1, true) then return { kind = "status", topic = "nearby" } end
    if s:find("世界天数", 1, true) or s:find("季节", 1, true) or s:find("月相", 1, true)
        or s:find("天气", 1, true) or s:find("报时", 1, true) then return { kind = "status", topic = "world" } end
    if s:find("讲笑话", 1, true) or s:find("讲个笑话", 1, true) then
        return { kind = "social", topic = "joke" }
    end
    if s:find("谢谢", 1, true) or s:find("辛苦", 1, true) then
        return { kind = "social", topic = "thanks" }
    end
    if s:find("安慰", 1, true) or s:find("鼓励", 1, true) or s:find("难过", 1, true) then
        return { kind = "social", topic = "comfort" }
    end
    if s:find("你好", 1, true) or s:find("早上好", 1, true) or s:find("晚上好", 1, true) then
        return { kind = "social", topic = "greeting" }
    end
    if s:find("怎么样", 1, true) or s:find("在想什么", 1, true) then
        return { kind = "social", topic = "mood" }
    end
    if s:find("夸", 1, true) or s:find("喜欢", 1, true) or s:find("聪明", 1, true)
        or s:find("卖萌", 1, true) or s:find("表白", 1, true) then
        return { kind = "social", topic = "cute" }
    end
    if s:find("逃跑", 1, true) or s:find("撤退", 1, true) or s:find("躲开", 1, true) then return { kind = "retreat" } end
    if s:find("清怪", 1, true) then return { kind = "attack" } end
    if s:find("回家", 1, true) or s:find("回基地", 1, true) then return { kind = "goto", text = "基地" } end
    for landmark in pairs(Config.LANDMARKS) do
        if s:find("去" .. landmark, 1, true) then return { kind = "goto", text = landmark } end
    end
    local x, z = s:match("去%s*[%(%（]?%s*(-?%d+)%s*[,，]%s*(-?%d+)")
    if x ~= nil then return { kind = "goto", x = tonumber(x), z = tonumber(z), text = "坐标" } end
    if s:find("巡逻", 1, true) then return { kind = "unsupported", text = "巡逻" } end
    if s:find("喂我", 1, true) or s:find("给我食物", 1, true) then
        return { kind = "give", text = "食物" }
    end
    if s:find("治疗我", 1, true) then return { kind = "heal", text = "药膏" } end
    -- 对场景实体使用背包物品：具体动作交给原版动作选择器判断。
    local use_item, use_target = s:match("^用%s*(.-)%s*对%s*(.+)")
    if use_item == nil then use_item, use_target = s:match("^把%s*(.-)%s*用在%s*(.-)上$") end
    if use_item == nil then use_item, use_target = s:match("^把%s*(.-)%s*用在%s*(.+)$") end
    if use_item ~= nil and use_item ~= "" and use_target ~= nil and use_target ~= "" then
        local item, count = ExtractCount(use_item)
        return { kind = "use_on", text = item, target = Trim(use_target), count = count }
    end
    local name, box = s:match("把(.+)放进(.+)")
    if name ~= nil then
        local item, count = ExtractCount(Trim(name:gsub("背包里的", "")))
        return { kind = "store", text = item, box = Trim(box), count = count }
    end
    name = s:match("把(.+)给我") or s:match("把(.+)丢给我")
    if name ~= nil then
        local item, count = ExtractCount(Trim(name))
        return { kind = "give", text = item, count = count }
    end
    if s == "给我" then return { kind = "give" } end
    -- 语音输入常把“捡”识别成“丨”或“棍”；只接受句首，避免误判物品名。
    local short_pickup = s:match("^丨%s*(.+)") or s:match("^棍%s*(.+)")
    if short_pickup ~= nil then
        short_pickup = Trim(short_pickup):gsub("^走", "")
        local item, count = ExtractCount(short_pickup)
        if item ~= "" then return { kind = "pickup", text = item, count = count } end
    end
    local whole_stack = s:find("整组", 1, true) ~= nil or s:find("这一组", 1, true) ~= nil
    local drop_text = whole_stack and Trim((s:gsub("这一组", ""):gsub("整组", ""))) or s
    for _, verb in ipairs({ "丢掉", "丢下", "丢弃", "扔掉", "扔下", "丢", "扔" }) do
        local before = drop_text:match("^把(.+)" .. verb .. "$")
        if before ~= nil then
            local item, count = ExtractCount(before)
            return { kind = "drop", text = item, count = whole_stack and 1 or count,
                whole_stack = whole_stack }
        end
    end
    local patterns = {
        { "帮我捡", "pickup" }, { "捡起来", "pickup" }, { "捡起", "pickup" },
        { "去捡", "pickup" }, { "拾取", "pickup" }, { "收集", "pickup" }, { "捡", "pickup" },
        { "装备", "equip" }, { "穿上", "equip" }, { "戴上", "equip" }, { "拿着", "equip" },
        { "卸下", "unequip" }, { "脱下", "unequip" }, { "摘下", "unequip" },
        { "吃掉", "eat" }, { "食用", "eat" }, { "吃", "eat" }, { "喝", "eat" },
        { "丢给我", "give" }, { "交给我", "give" }, { "递给我", "give" }, { "给我", "give" },
        { "丢掉", "drop" }, { "丢下", "drop" }, { "丢弃", "drop" },
        { "扔掉", "drop" }, { "扔下", "drop" }, { "放下", "drop" }, { "丢", "drop" }, { "扔", "drop" },
        { "使用", "use" }, { "用", "use" }, { "制作", "craft" }, { "合成", "craft" }, { "做", "craft" },
        { "攻击", "attack" }, { "揍", "attack" }, { "干掉", "attack" }, { "打", "attack" },
        { "砍倒", "chop" }, { "砍", "chop" }, { "挖矿", "mine" },
        { "敲碎", "hammer" }, { "敲", "hammer" }, { "锤", "hammer" },
        { "铲掉", "dig" }, { "铲", "dig" }, { "挖", "mine" },
        { "采集", "harvest" }, { "采", "harvest" }, { "摘", "harvest" },
        { "拔", "harvest" }, { "割", "harvest" }, { "收获", "harvest" },
        { "找", "find" }, { "有没有", "find" },
    }
    for _, spec in ipairs(patterns) do
        local source = spec[2] == "drop" and drop_text or s
        local at = source:find(spec[1], 1, true)
        if at ~= nil then
            local target = Trim(source:sub(at + #spec[1]))
            target = target:gsub("^背包里的", ""):gsub("^身上的", "")
            target = target:gsub("^这个", ""):gsub("^那个", "")
            local count
            target, count = ExtractCount(target)
            if target == "它" or target == "这个" or target == "" then target = nil end
            if spec[2] == "mine" and target == nil then target = "矿石" end
            return { kind = spec[2], text = target,
                count = spec[2] == "drop" and whole_stack and 1 or count,
                whole_stack = spec[2] == "drop" and whole_stack or nil, raw = s }
        end
    end
    if s:find("?", 1, true) or s:find("？", 1, true) or s:find("吗", 1, true)
        or s:find("为什么", 1, true) or s:find("怎么", 1, true)
        or s:find("如何", 1, true) or s:find("请问", 1, true)
        or s:find("是多少", 1, true) or s:find("是什么", 1, true)
        or s:find("查一下", 1, true) or s:find("搜索", 1, true) then
        return { kind = "question", text = s }
    end
    return { kind = "unsupported", text = s }
end

local function ParseCommand(command)
    if type(command) ~= "string" or Trim(command) == "" then return nil end
    local result = {}
    for _, part in ipairs(Split(command)) do
        local step = ParseStep(part)
        if step ~= nil and step.kind == "unsupported" then
            -- 去掉口语前置成分后再解析；只在原句无法识别时尝试，不覆盖多步骤和原有语义。
            for offset = 2, #part do
                local byte = part:byte(offset)
                if byte < 128 or byte >= 192 then
                    local candidate = ParseStep(part:sub(offset))
                    if candidate ~= nil and candidate.kind ~= "unsupported"
                        and candidate.kind ~= "question" and candidate.kind ~= "social" then
                        step = candidate; break
                    end
                end
            end
        end
        if step ~= nil then result[#result + 1] = step end
    end
    return result, command
end

local function Parse(message)
    local command = Addressed(message)
    if command == nil then return nil end
    return ParseCommand(command)
end

return { Parse = Parse, ParseCommand = ParseCommand, Addressed = Addressed,
    SeekAddressed = SeekAddressed }
