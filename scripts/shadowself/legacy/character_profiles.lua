local AIPLAYER=require("shadowself/legacy/registry")
-- 角色差异以本机 prefab 与公开客户端标签为准；战斗中有限书籍/战歌由 combat_roles 单独调度；不自动使用变身道具。
local PROFILES = {
    wilson={label="威尔逊",tempo=1,burst=4},
    willow={label="薇洛",tempo=.95,burst=4},
    wolfgang={label="沃尔夫冈",tempo=.9,burst=5,hunger=.55,defend=true},
    wendy={label="温蒂",tempo=1.12,burst=3},
    wx78={label="WX-78",tempo=.82,burst=5,raincare=true},
    wickerbottom={label="薇克巴顿",tempo=.92,burst=5},
    woodie={label="伍迪",tempo=.9,burst=5,lumber=true},
    waxwell={label="麦斯威尔",tempo=1.08,burst=3,health=.55},
    wathgrithr={label="薇格弗德",tempo=.86,burst=5,defend=true,meat=true},
    webber={label="韦伯",tempo=1.05,burst=3,spiderfriend=true},
    winona={label="薇诺娜",tempo=.85,burst=5},
    warly={label="沃利",tempo=1.08,burst=3,prepared=true,hunger=.5},
    wortox={label="沃拓克斯",tempo=1.03,burst=3,souls=true},
    wormwood={label="沃姆伍德",tempo=1.1,burst=3,plant=true},
    wurt={label="沃特",tempo=1,burst=4,vegetarian=true},
    walter={label="沃尔特",tempo=1.05,burst=3,health=.6},
    wanda={label="旺达",tempo=1.15,burst=3,age=true,health=.65},
    wes={label="韦斯",tempo=1.2,burst=3,health=.55},
    wonkey={label="芜猴",tempo=.95,burst=4},
}
-- 原版 prefab 中的 foodaffinity 喜好；饱腹估值计入额外约15点收益。
local FAVOURITES={wilson="baconeggs",willow="hotchili",wolfgang="potato_cooked",wendy="bananapop",wx78="butterflymuffin",wickerbottom="surfnturf",woodie="honeynuggets",waxwell="lobsterdinner",wathgrithr="turkeydinner",webber="icecream",winona="vegstinger",wortox="pomegranate_cooked",wormwood="cave_banana_cooked",wurt="durian_cooked",walter="trailmix",wanda="taffy",wes="freshfruitcrepes"}
local Profiles = Class(function(self, player, config, model)
    self.player, self.config, self.model = player, config, model
    self.data = PROFILES[player.prefab] or {label=player.prefab or "未知角色",tempo=1,burst=4}
    self.favourite=FAVOURITES[player.prefab]
    self.food_history = model.food_history or {}
    model.food_history = self.food_history
end)

-- 变身状态持续阻止普通人形逻辑，恢复人形后重新评估装备和库存。
function Profiles:IsTransformed()
    return self.player:HasTag("wereplayer") or self.player:HasTag("werebeaver") or self.player:HasTag("beaver") or self.player:HasTag("weremoose") or self.player:HasTag("weregoose")
end

-- 当前世界时刻以游戏天数表达，使食物习惯可跨重新连接保存。
function Profiles:WorldDay()
    local state=TheWorld and TheWorld.state or {}
    return (state.cycles or 0)+(state.time or 0)
end

-- 食物估值不替代游戏的食性检查；沃利为近期重复食物降权，饥荒时仍允许吃。
function Profiles:FoodScore(item, food, stat, snapshot)
    if not food or (food[stat] or 0)<=0 then return nil end
    if self.data.prepared and not item:HasTag("preparedfood") and not item:HasTag("pre-preparedfood") then return nil end
    if self.data.meat and food.type ~= "meat" and food.type ~= "goodies" then return nil end
    if self.data.vegetarian and food.type == "meat" then return nil end
    if stat == "heal" and (self.data.plant or self.data.age) then return nil end
    if (food.heal or 0)<0 and (snapshot.health or 0)<.5 then return nil end
    if (snapshot.hunger or 1)>.15 and snapshot.temperature then
        if snapshot.temperature>60 and (food.temperature or 0)>0 then return nil end
        if snapshot.temperature<5 and (food.temperature or 0)<0 then return nil end
    end
    local score=food[stat]
    if stat=="h" then
        if item.prefab==self.favourite then score=score+15 end
        if self.data.vegetarian and food.type=="veggie" then score=score*1.33 end
        local missing=(snapshot.hunger_max or 150)*(1-(snapshot.hunger or 0))
        score=math.min(score,missing)-math.max(0,score-missing)*.2
        if (food.s or 0)<0 and (snapshot.sanity or 0)<.4 then score=score-50 end
    end
    if self.data.prepared then
        local history=self.model.food_history or {}
        local last=history[item.prefab]
        if type(last)=="number" and self:WorldDay()-last<2 then score=score*.25 end
    elseif self.data.souls and item.prefab~="wortox_soul" then score=score*.5 end
    return score
end

-- 只有确认消耗之后记录食物，避免发出的请求污染饮食记忆。
function Profiles:OnCompleted(plan)
    if plan.name=="EAT" and plan.item then
        self.model.food_history=self.model.food_history or {}
        self.model.food_history[plan.item.prefab]=self:WorldDay()
    end
end

-- 专属治疗动作优先级高于普通药膏和食物；不误用其他类型的怀表。
function Profiles:HealPlan(snapshot, actions)
    if self.data.age or self.player:HasTag("health_as_oldage") then
        for _, item in ipairs(snapshot.items) do
            if item.prefab=="pocketwatch_heal" and item:HasTag("pocketwatch_inactive") then
                local act=actions:FindAction("CAST_POCKETWATCH",nil,item)
                if act then return {kind="action",action=act,name="CAST_POCKETWATCH",item=item} end
            end
        end
        return nil,true
    elseif self.data.plant or self.player:HasTag("self_fertilizable") then
        for _, prefab in ipairs({"compostwrap","compost","manure","guano"}) do
            for _, item in ipairs(snapshot.items) do
                if item.prefab==prefab then
                    local name=prefab=="compostwrap" and "HEAL" or "FERTILIZE"
                    local act=actions:FindAction(name,nil,item)
                    if act then return {kind="action",action=act,name=name,item=item} end
                end
            end
        end
    elseif self.data.souls and (snapshot.counts.wortox_soul or 0)>2 then
        for _, item in ipairs(snapshot.items) do
            if item.prefab=="wortox_soul" then return {kind="drop",item=item,name="释放一个灵魂治疗"} end
        end
    end
end

-- 角色需求阈值；旺达年龄采用同步的剩余生命比例，而非把年龄当作普通食物治疗。
function Profiles:Threshold(which)
    if which=="health" then return self.data.health or .4 end
    if which=="hunger" then return self.data.hunger or .4 end
    return .3
end

-- 己方蜘蛛不作为自动防御目标；其他角色不会因装备齐全就自动挑战 Boss。
function Profiles:CanDefend(snapshot)
    if self.config.combat_mode=="flee" then return false end
    if self.config.combat_mode~="defend" and not self.data.defend then return false end
    if #snapshot.threats~=1 or (snapshot.health or 0)<.75 then return false end
    local enemy=snapshot.threats[1]
    if self.data.spiderfriend and enemy:HasTag("spider") then return false end
    local allowed={spider=true,hound=true,icehound=true,firehound=true}
    if not allowed[enemy.prefab] or enemy:HasTag("epic") then return false end
    local inv=self.player.replica.inventory
    local hand=inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    -- 原版橄榄球头盔没有公开 armor 标签，以核对过的 prefab 判断，模组可额外提供 armor 标签。
    local armours={armorwood=true,armormarble=true,armorruins=true,armordragonfly=true,armorskeleton=true,armorsnurtleshell=true,footballhat=true,wathgrithrhat=true,ruinshat=true,woodcarvedhat=true}
    local body=inv and inv:GetEquippedItem(EQUIPSLOTS.BODY)
    local head=inv and inv:GetEquippedItem(EQUIPSLOTS.HEAD)
    local armour=(body and (armours[body.prefab] or body:HasTag("armor"))) or (head and (armours[head.prefab] or head:HasTag("armor")))
    return AIPLAYER.Equipment.Melee(self.player,hand) and armour and not enemy:HasTag("attack")
end

AIPLAYER.Profiles=Profiles

return true
