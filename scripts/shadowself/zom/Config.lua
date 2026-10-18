-- 工作指令公开；跟随主人只控制长期跟车目标和“解除跟随”权限。
-- FindEntities 只返回当前客户端已加载的实体；大半径不等于全图透视。
local LOADED_SEARCH_RADIUS = 9999
local config = {
    TICK = .25,
    CONTROL_SEARCH_RADIUS = 50,
    CONTROL_LEAD_TIME = .85, -- 预判覆盖施法前摇和网络往返；按实测位移速度计算。
    CONTROL_MISS_LIMIT = 3,
    CONTROL_CONFIRM_DELAY = 1.4,
    AUTO_EQUIP_RETRY = .4,
    AUTO_FUEL_MIN = 10,
    AUTO_SUPPLY_RADIUS = 20,
    OWNER_REPORT_INTERVAL = 180,
    AI_PERSONALITY = "芽衣是高冷的姐姐，内心容易被真诚和关心融化，带一点傲娇。最喜欢的人是蓝原柚子。语气克制、温柔，不辱骂玩家。",
    AUTO_COMBAT_RADIUS = 12, -- 非麦斯威尔、非旺达角色自动寻找附近可攻击怪物。
    AUTO_COMBAT_RETRY = .4, -- 攻击 RPC 最短间隔；原版冷却仍由 combat 校验。
    WANDA_AVOID_RADIUS = 8, -- 旺达只躲怪，不主动攻击；接近此距离先后撤。
    PLACE_SEARCH_RADIUS = 4, -- 普通物品只在脚边找合法位置。
    BOAT_PLACE_SEARCH_RADIUS = 24, -- 船搜索附近海面，优先距离近的合法点。
    PLACE_RETRY = 2,
    ROW_INTERVAL = 1.3,
    MAX_ROW_COUNT = 100,
    ARENA_WORMHOLE_RADIUS = LOADED_SEARCH_RADIUS,
    LEARN_COMBO_GAP = 1, -- 受击间隔不足 1 秒视作同一组连击。
    LEARN_MIN_SAMPLES = 2, -- 至少两组攻击才能推算下一次进攻。
    LEARN_DODGE_INITIAL = 1, -- 初始退避 1 码；受击后逐码增加。
    LEARN_DODGE_MAX = 10,
    LEARN_DODGE_WINDOW = 1.5,
    LEARN_DODGE_COOLDOWN = .7,
    FOLLOW_DISTANCE = 4,
    SPELL_ID = 4,
    PROTECTOR_SPELL_ID = 2, -- 暗黑魔典第二格：暗影保护者（战斗小人）。
    PROTECTOR_COUNT = 5,
    PROTECTOR_RETRY = .8, -- 原地尽快衔接；原版施法忙碌状态仍由游戏校验。
    PROTECTOR_MAX_ATTEMPTS = 8,
    CONTROL_EXCLUDE = { -- 默认不施加暗影禁锢；聊天“别控X”还能临时追加。
        shadow_rook = true, shadow_bishop = true, shadow_knight = true,
        fused_shadeling = true, tentacle = true, tentacle_pillar = true,
        alterguardian_phase3 = true,
        wagboss_robot = true,
    },
    HAND_ATTACK_RADIUS = 12,
    GHOST_HAUNT_RADIUS = LOADED_SEARCH_RADIUS,
    CAST_RANGE = 11.1,
    CAST_EDGE_OFFSET = 3.5,
    CAST_MIN_DISTANCE = 10,
    CAST_MAX_DISTANCE = 10.8,
    BOSS_MIN_DISTANCE = 10,
    BOSS_MAX_DISTANCE = 11.5,
    ENABLED_BY_DEFAULT = true,
    DEVELOPER_USERID = "KU_2DNgIcMt", -- 只按 userid 识别，不信任可改的昵称。
    WORLD_NAMES = {
        ["1"] = "挂机天堂", ["2"] = "萌新天堂", ["3"] = "萌新地洞",
        ["4"] = "长期地面", ["5"] = "长期地洞", ["6"] = "迷你家园",
        ["7"] = "冒险世界", ["8"] = "角斗场",
    },
    WORLD_ALIASES = { -- 玩家常用简称；正式世界名仍由 WORLD_NAMES 识别。
        ["挂机世界"] = "1", ["挂机"] = "1",
        ["萌新世界"] = "2", ["萌新地面"] = "2",
        ["长期世界"] = "4", ["长期服"] = "4",
        ["迷你世界"] = "6", ["迷你家"] = "6",
        ["冒险"] = "7", ["角斗"] = "8",
    },
    WORLD_PORTAL_SEARCH_RADIUS = LOADED_SEARCH_RADIUS,
    WORLD_PORTAL_PREFABS = {
        cave_entrance_open = true, cave_exit = true, migration_portal = true,
        multiplayer_portal = true, multiplayer_portal_moonrock = true,
        multiplayer_portal_moonrock_constr = true,
    },
    WORLD_PORTAL_REACH_DISTANCE = 9.5, -- 小于选择器服务器的 10 码检查。
    ADVENTURE_SECTORS = { -- 冒险地图板块中心；猪币交点按最近中心归属。
        { 488.31, -324.14 }, { 483.30, -52.92 }, { 515.18, 202.72 },
        { 334.49, 368.68 }, { 21.90, 263.32 }, { -130.54, 50.34 },
        { -392.30, 28.19 }, { -170.05, -289.60 }, { 157.91, -461.01 },
        { -504.40, 463.97 },
    },
    PIG_COIN_BASELINES = { 1 }, -- 两次投币之间横移约 1 码。
    PIG_COIN_MIN_CROSS = .001, -- 1 码基线角度很小；拒绝不可靠的近平行交点。
    WORLD_PICKER_TIMEOUT = 12,
    WORLD_TRAVEL_TIMEOUT = 60,
    MAX_SPEECH_LENGTH = 120,
    -- 只填你自己的代理完整地址；DeepSeek 密钥必须留在代理服务端。
    -- 代理建议兼容 POST /v1/responses 的请求和返回格式。
    -- 仅请求本机代理；代理从 DEEPSEEK_API_KEY 环境变量读取密钥。
    AI_PROXY_URL = "http://127.0.0.1:8787/v1/responses",
    AI_MODEL = "deepseek-flash",
    AI_REQUEST_COOLDOWN = 8,
    AI_GLOBAL_COOLDOWN = 2,
    AI_REQUEST_TIMEOUT = 35,
    AI_MAX_INPUT_BYTES = 600,
    AI_MAX_REPLY_BYTES = 240,
    AI_HISTORY_TURNS = 4,
    HELLO_BUTTONS = { -- suqintest/widgets/hello.lua 的现有按钮及其运行状态。
        autoBuyAmulet = { label = "点击复活", flag = "autoBuyAmulet", once = true },
        autoClickPortal = { label = "自动跳洞", flag = "autoClickPortal" },
        autoInspectBoss = { label = "检查Boss", flag = "autoInspectBoss" },
        autoWinonaPuzzle = { label = "女工挂机", flag = "autoWinonaPuzzle" },
        autoRain = { label = "自动下雨", flag = "autoRain" },
        autoWeighCrops = { label = "自动称重", flag = "autoWeighCrops" },
        openMoveStore = { label = "自动存仓", flags = { "autoStoreAll", "autoStoreHeavy" } },
        ancientTrail = { label = "亿点特效", flag = "_ancient_trail_task" },
    },
    ALLOW_ALL_PLAYERS = true,
    OWNER_USERID = "", -- 可选固定管理员 KU_...；可代主人解除跟随。
    WHITELIST = {}, -- 可选管理员 ["KU_..."] = true；不限制日常工作命令。
    TRIGGERS = { "小跟班", "芽衣", "蓝原芽衣", "宝宝", "小助手", "ai" },
    PREFIX_MAX_BYTES = 60,
    PLAYER_COOLDOWN = 1,
    REPLY_COOLDOWN = .5,
    SEARCH_RADIUS = LOADED_SEARCH_RADIUS,
    PICKUP_ALL_RADIUS = 5, -- “捡起脚下所有东西”只扫描发令时脚边 5 码。
    PICKUP_ALL_ITEM_TIMEOUT = 4,
    PORTAL_OWNER_RADIUS = LOADED_SEARCH_RADIUS, -- 选已加载且最靠近跟跳目标的虫洞。
    PORTAL_WAIT_TIMEOUT = 120,
    YIELD_TO_WANDA_PORTAL = true, -- 旺达时空洞出现时暂停本模组控制，交给现有自动跳洞模组。
    DANGER_RADIUS = 9,
    STEP_TIMEOUT = 18,
    MAX_REPEAT = 20, -- 单句最多执行次数，避免刷屏和误操作。
    MOVE_RETRY = .5,
    ARRIVE_DISTANCE = 2.5,
    BASE_POINT = nil, -- 例如 { x = 0, z = 0 }；未知时“回家”明确拒绝。
    LANDMARKS = { -- 只有客户端已加载对应实体，才可寻路前往。
        ["猪王"] = { "pigking" },
        ["月台"] = { "moonbase" },
        ["蜂后"] = { "beequeenhive", "beequeen" },
        ["海边"] = {}, ["洞穴"] = {}, ["远古"] = {},
    },
    TEMPLATES = {
        confirm = { "收到，{player}！小跟班马上出发～", "好嘞，芽衣听到啦！", "命令已接收，正在执行。", "交给我吧，宝宝！", "嗯嗯，AI 明白啦。", "遵命，蓝原芽衣这就去。", "小助手收到，马上处理。", "没问题，看我的！", "这个命令我记下了。", "好哦，我这就动起来。" },
        working = { "正在前往{target}…", "我看看背包里有没有{item}…", "这个有点远，我跑快点！", "正在翻找箱子，稍等一下～", "我在努力了，别催嘛～", "正在装备{item}…", "正在吃{item}…", "正在攻击{target}…", "正在采集，马上就好。", "让我先找找路。" },
        success = { "搞定！{item}已经装备好啦～", "捡到{item}了，接下来要做什么？", "报告：任务完成！", "已经到达{target}。", "吃掉了{item}，感觉好多了。", "东西已经放进容器里了。", "找到你要的{item}啦！", "攻击目标已处理。", "采集完成，收获满满！", "嘿嘿，我是不是很能干？" },
        failure = { "呜…找不到{item}。", "背包满了，先帮我清一下嘛。", "太危险了，我不敢过去…", "路被挡住了，过不去。", "这个东西我拿不起来。", "附近没有水源。", "我饿了，能不能先给我点吃的？", "没有材料，做不了。", "目标不见了。", "失败啦…要不要再试一次？" },
        status = { "当前三维：血量{health}，饥饿{hunger}，理智{sanity}。", "我身上有：{items}。", "我正跟着{player}，距离大概{range}。", "我现在在{location}。", "当前任务是：{task}。", "背包快满了，记得整理哦。", "附近有：{nearby}。", "今天是第{day}天，季节是{season}。", "月相是{moonphase}，天气是{weather}。", "我状态还不错，可以继续干活！" },
        cute = { "嘿嘿，被夸了，尾巴要翘起来了～", "宝宝今天也很努力呢！", "AI 也需要一点夸奖哦～", "小跟班最喜欢{player}啦！", "你叫我芽衣的时候，我心情会变好。", "别看我这样，我可是很聪明的！", "再夸一句，我就跑得更快！", "今天的我也在认真营业～", "你负责命令，我负责可爱。", "我们是最好的搭档，对吧？" },
        greeting = { "你好呀，{player}！今天也一起出发吗？", "我在这儿，叫我就好～",
            "早安！骨甲、魔典和好心情都准备好啦。", "晚上好，路黑的话我会尽量跟紧你。",
            "芽衣收到你的招呼啦！" },
        thanks = { "不客气，{player}，能帮上忙就好！", "嘿嘿，这句谢谢我收下啦。",
            "应该的，我们可是队友嘛。", "再交给我一点事也没关系～", "听到你这么说，我更有干劲了。" },
        joke = { "为什么麦斯威尔不怕黑？因为影子都认识他！", "骨甲说它最近很累——毕竟总在替我扛。",
            "我问虫洞通往哪里，它说：进去就知道啦！", "今天的笑话库存不多，但我会努力补货。",
            "要是禁锢圈会说话，它一定会说：站住，别跑！" },
        comfort = { "别急，{player}，我先陪你把这一段走完。", "失败一次没关系，我们可以再来一次。",
            "你已经做得很好啦，先喘口气。", "我在附近，想说话就叫我。",
            "怪物可以慢慢打，队友的心情要先照顾好。" },
        mood = { "今天状态不错，正在等你的下一条命令。", "我在观察附近，顺便想着怎么少挨一下打。",
            "有点想要燃料，不过还能继续跟车。", "心情很好，因为有人愿意叫我芽衣。",
            "我正在认真工作，偶尔也会偷偷发呆一下。" },
        dev_chat = { "{player}，我在听。想让我做什么可以直接说。",
            "收到，{player}。我能跟随、控怪、查询状态和尝试跳世界。",
            "我听见啦，{player}。具体行动告诉我就好～" },
        owner_chat = { "{player}，我在听，悄悄告诉我想做什么吧。",
            "收到，主人。可以直接私聊下工作命令～" },
        dev_refuse = { "你不是开发者，这个模式不能开放给你哦。",
            "开发者权限只认指定账号，我不能帮你开启。",
            "抱歉，开发者模式需要专属身份验证。",
            "这把钥匙不是你的，普通工作命令仍然可以叫我做。" },
        web_question = { "当前模型不支持搜索网页来回答问题，但游戏里的事我可以试着帮忙。",
            "这个问题需要查资料；我现在没有联网搜索能力，不能乱答。",
            "抱歉，我目前不能搜索网页回答这个问题。" },
        gentle = { "我现在只是一个初级模型，请多多包容，我会继续努力。",
            "听到了，我还在学习，麻烦温柔一点教我呀。",
            "抱歉没做好；我只是初级模型，会一点点改进的。" },
        refuse = { "这个命令太危险了，除非你牵着我的手。", "不行不行，我会被怪物吃掉的！", "先给我吃的，我就去～", "这个我不能做，主人会生气的。", "你确定吗？我觉得会出事…", "不要让我打玩家啦，我会被讨厌的。", "这个物品太珍贵了，我不敢乱用。", "等安全一点再说好不好？", "我现在没空，正在忙呢。", "这个命令超出我的能力范围了。" },
    },
}
-- 配置仅供影子自己的 require 命名空间使用。
return config
