local AIPLAYER=require("shadowself/legacy/registry")
-- 需求驱动的优先级行为树：条件节点生成计划，选择器决定一个输出。
local FOOD = {
    berries={h=9,s=0}, berries_cooked={h=12,s=0}, berries_juicy={h=12,s=0}, berries_juicy_cooked={h=18,s=0},
    carrot={h=12,s=0}, carrot_cooked={h=12,s=0}, corn={h=25,s=0}, corn_cooked={h=12,s=0},
    meat={h=25,s=-10}, cookedmeat={h=25,s=0}, smallmeat={h=12,s=-10}, cookedsmallmeat={h=12,s=0},
    meatballs={h=62,s=5}, meaty_stew={h=150,s=5}, pierogi={h=37,s=5,heal=40},
    honeyham={h=75,s=5,heal=30}, honeynuggets={h=37,s=5,heal=20}, butter={h=25,s=0,heal=40},
    honey={h=9,s=0,heal=3}, trailmix={h=12,s=5,heal=30}, dragonpie={h=75,s=5,heal=40},
    taffy={h=25,s=15,heal=-3}, cookedgreen_cap={h=0,s=15,heal=-1}, cookedblue_cap={h=0,s=10,heal=-3},
    driedmeat={h=25,s=15,heal=20}, smallmeat_dried={h=12,s=10,heal=8}, icecream={h=25,s=50},
    watermelon={h=12,s=5}, cookedwatermelon={h=12,s=7}, fishsticks={h=37,s=5,heal=40},
    unagi={h=18,s=5,heal=20}, waffles={h=37,s=5,heal=60}, baconeggs={h=75,s=5,heal=20},
    bonestew={h=150,s=5}, mandrakesoup={h=100,s=5,heal=100},
    potato_cooked={h=25,s=0,heal=20,type="veggie"}, pomegranate_cooked={h=12.5,s=0,heal=20,type="veggie"},
    cave_banana_cooked={h=12.5,s=0,heal=3,type="veggie"}, seeds={h=4.6875,s=0,type="veggie"},
    seeds_cooked={h=4.6875,s=0,heal=1,type="veggie"},
}
-- 从游戏实际烹饪目录补齐料理数值，包含服务器模组已注册的料理。
local cooking = require("cooking")
for _, recipes in pairs(cooking.recipes or {}) do
    for prefab, recipe in pairs(recipes) do
        if type(recipe.hunger)=="number" and type(recipe.health)=="number" and type(recipe.sanity)=="number" then
            FOOD[prefab]={h=recipe.hunger,heal=recipe.health,s=recipe.sanity,temperature=recipe.temperature,type=recipe.foodtype==FOODTYPE.MEAT and "meat" or (recipe.foodtype==FOODTYPE.GOODIES and "goodies" or "veggie")}
        end
    end
end
for _, name in ipairs({"meat","cookedmeat","smallmeat","cookedsmallmeat","driedmeat","smallmeat_dried"}) do FOOD[name].type="meat" end
FOOD.wortox_soul={h=TUNING.CALORIES_MED or 25,s=0,type="soul"}
local GATHER = {
    log={action="CHOP",tag="CHOP_workable"}, rocks={action="MINE",tag="MINE_workable"},
    flint={action="MINE",tag="MINE_workable"}, goldnugget={action="MINE",tag="MINE_workable"},
    cutgrass={action="PICK",prefabs={grass=true}}, twigs={action="PICK",prefabs={sapling=true}},
    berries={action="PICK",prefabs={berrybush=true,berrybush2=true}},
    berries_juicy={action="PICK",prefabs={berrybush_juicy=true}}, cutreeds={action="PICK",prefabs={reeds=true}},
}
local Brain = Class(function(self, player, config, model, perception, actions, humanizer, profile)
    self.player, self.config, self.model = player, config, model
    self.perception, self.actions, self.humanizer = perception, actions, humanizer
    self.profile = profile
    self.cooldowns = {}
    self.memory_visits = {}
    -- 每个条件是行为树叶节点；优先级选择器在 Evaluate 中统一评估。
    self.nodes = {
        {name="逃离威胁",priority=100,condition=function(s) return self:Flee(s) end},
        {name="夜间照明",priority=95,condition=function(s) return self:Light(s) end},
        {name="紧急进食",priority=90,condition=function(s) return s.hunger and s.hunger < .15 and self:Eat(s,"h") end},
        {name="急救",priority=87,condition=function(s) return s.health and s.health < profile:Threshold("health") and self:Heal(s) end},
        {name="应对温度",priority=85,condition=function(s) return self:Temperature(s) end},
        {name="补充饥饿",priority=82,condition=function(s) return s.hunger and s.hunger < profile:Threshold("hunger") and self:Eat(s,"h") end},
        {name="烤制食物",priority=81,condition=function(s) return self:Cook(s) end},
        {name="恢复理智",priority=80,condition=function(s) return self:Sanity(s) end},
        {name="雨中防护",priority=79,condition=function(s) return self:Rain(s) end},
        {name="完成用户任务",priority=config.task_priority == "tasks" and 70 or 60,condition=function(s) return self:Task(s) end},
        {name="日常资源",priority=config.task_priority == "resources" and 65 or 55,condition=function(s) return self:Resources(s) end},
        {name="安全灭火",priority=50,condition=function(s) return self:Extinguish(s) end},
        {name="基地巡逻",priority=15,condition=function(s) return self:Wander(s) end},
        {name="休息",priority=10,condition=function(s) return {kind="wait",duration=1+math.random()*2,name="休息"} end},
    }
end)

-- 使用战斗实体距离给候选逃跑点打分，同时排除海面和不通行路径。
function Brain:Flee(s)
    if #s.threats == 0 then return end
    if not self.combat_disabled and self.profile:CanDefend(s) and not self:Blocked(s.threats[1]) then
        local action=self.actions:FindAction("ATTACK",s.threats[1])
        if action then return {kind="action",action=action,name="ATTACK",target=s.threats[1],emergency=true} end
    end
    local best, score = nil, -math.huge
    for i=1,16 do
        local angle = 2*math.pi*i/16
        local p = Vector3(s.pos.x+math.cos(angle)*7,0,s.pos.z+math.sin(angle)*7)
        if self.actions:SafePoint(p) then
            local min = math.huge
            for _, enemy in ipairs(s.threats) do min = math.min(min, p:DistSq(enemy:GetPosition())) end
            if min > score then best, score = p, min end
        end
    end
    if best then return {kind="move",point=best,name="逃离威胁",emergency=true} end
    return {kind="wait",duration=.4,name="无安全逃跑路线",emergency=true}
end

-- 使用附近火堆烤自己的原料，拒绝替别人清空锅/烘干架；沃利保留只吃料理的限制。
function Brain:Cook(s)
    if not s.hunger or s.hunger>.65 or self.profile.data.prepared then return end
    local raw={meat=true,smallmeat=true,carrot=true,berries=true,berries_juicy=true,corn=true,green_cap=true,blue_cap=true}
    for _, entity in ipairs(s.entities) do
        if entity:HasTag("campfire") and not self:Blocked(entity) then
            for _, item in ipairs(s.items) do
                if raw[item.prefab] and (not self.profile.data.meat or item.prefab=="meat" or item.prefab=="smallmeat") then
                    local action=self.actions:FindAction("COOK",entity,item)
                    if action then return {kind="action",action=action,name="COOK",target=entity,item=item} end
                end
            end
        end
    end
end

-- 通过游戏已显示的 EAT 动作验证角色食性，自动进食仅使用已知安全食品。
function Brain:Eat(s, stat)
    local best, score
    for _, item in ipairs(s.items) do
        local food = FOOD[item.prefab]
        local value=self.profile:FoodScore(item,food,stat,s)
        if self.profile.data.souls and item.prefab=="wortox_soul" and (s.counts.wortox_soul or 0)<=2 and (s.hunger or 1)>.1 then value=nil end
        if value then
            local act = self.actions:FindAction("EAT",nil,item)
            if act and (not score or value > score) then best, score = {kind="action",action=act,name="EAT",item=item},value end
        end
    end
    return best
end

-- 治疗用品优先；植物人食物治疗无效时只尝试可用的治疗动作。
function Brain:Heal(s)
    local special, exclusive=self.profile:HealPlan(s,self.actions)
    if special then return special end
    if exclusive then return end
    for _, item in ipairs(s.items) do
        if item.prefab == "healingsalve" or item.prefab == "bandage" then
            local action = self.actions:FindAction("HEAL",nil,item)
            if action then return {kind="action",action=action,name="HEAL",item=item} end
        end
    end
    if self.profile.data.plant then return end
    return self:Eat(s,"heal")
end

-- 理智不足时先恢复食物；没有安全食物时摘附近花朵，不为理智去冒险采仙人掌。
function Brain:Sanity(s)
    if not s.sanity or s.sanity>=.3 then return end
    local plan=self:Eat(s,"s")
    if plan then return plan end
    if s.night then return end
    for _, entity in ipairs(s.entities) do
        if entity.prefab=="flower" and not self:Blocked(entity) and s.pos:DistSq(entity:GetPosition())<64 then
            local action=self.actions:FindAction("PICK",entity)
            if action then return {kind="action",action=action,name="PICK",target=entity} end
        end
    end
end

-- WX-78 在雨中优先穿雨具；其他角色只在明显潮湿时切换防雨装备。
function Brain:Rain(s)
    if not (TheWorld.state.israining and (self.profile.data.raincare or (s.moisture or 0)>40)) then return end
    local inventory=self.player.replica.inventory
    for _, prefab in ipairs({"raincoat","eyebrellahat","rainhat"}) do
        for _, item in ipairs(s.items) do
            if item.prefab==prefab then
                local equipped=false
                for _, e in pairs(inventory:GetEquips()) do if e==item then equipped=true end end
                if not equipped then
                    local action=self.actions:FindAction("EQUIP",nil,item)
                    if action then return {kind="action",action=action,name="EQUIP",item=item} end
                end
            end
        end
    end
end

-- 搜索开启的光源/火堆；火堆加燃料与拾取火把不直接修改光源组件。
function Brain:Light(s)
    local dark = s.night and (s.light == nil or s.light < .15)
    if not dark and not s.dusk then return end
    local inv = self.player.replica.inventory
    local hand = inv and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and (hand.prefab == "torch" or hand.prefab == "lantern" or hand.prefab == "lighter") and not dark then return end
    for _, e in ipairs(s.entities) do
        if e.Light and e.Light:IsEnabled() and e.Light:GetRadius() > 0 and not e:HasTag("burning") then
            local distance = s.pos:DistSq(e:GetPosition())
            local radius = math.max(1, e.Light:GetRadius()*.5)
            if distance > radius*radius then
                local point=self:Near(e:GetPosition(),s.pos,math.min(2,radius))
                if point then return {kind="move",point=point,name="靠近光源",emergency=dark} end
            end
            if dark then return {kind="wait",duration=.5,name="等待光照同步",emergency=true} end
        end
    end
    for _, item in ipairs(s.items) do
        if item.prefab == "torch" or item.prefab == "lantern" or item.prefab == "lighter" then
            if hand ~= item then
                local action = self.actions:FindAction("EQUIP",nil,item)
                if action then return {kind="action",action=action,name="EQUIP",item=item,emergency=dark} end
            elseif dark then
                local turnon = self.actions:FindAction("TURNON",nil,item)
                if turnon then return {kind="action",action=turnon,name="TURNON",item=item,emergency=true} end
            else return end
        end
    end
    for _, e in ipairs(s.entities) do
        if e:HasTag("campfire") then
            for _, item in ipairs(s.items) do
                if item.prefab == "log" or item.prefab == "cutgrass" or item.prefab == "twigs" then
                    local action = self.actions:FindAction("ADDFUEL",e,item)
                    if action then return {kind="action",action=action,name="ADDFUEL",item=item,target=e,emergency=dark} end
                end
            end
        end
    end
    if self.actions:CanCraft("torch") then return {kind="craft",recipe="torch",name="制作火把",emergency=dark} end
    if dark then return {kind="wait",duration=.5,name="缺少照明和材料，请接管",emergency=true} end
end

-- 使用当前温度应对冷暖；未知角色/世界的温度保持未定义，不调用服务端组件。
function Brain:Temperature(s)
    if not s.temperature then return end
    local equipment=s.temperature<5 and {"beefalohat","winterhat","trunkvest_winter"} or (s.temperature>65 and {"icehat","eyebrellahat","summerhat","hawaiianshirt"} or nil)
    if equipment then
        for _, prefab in ipairs(equipment) do
            for _, item in ipairs(s.items) do
                if item.prefab==prefab then
                    local equipped=false
                    for _, value in pairs(self.player.replica.inventory:GetEquips()) do if value==item then equipped=true end end
                    if not equipped then
                        local action=self.actions:FindAction("EQUIP",nil,item)
                        if action then return {kind="action",action=action,name="EQUIP",item=item} end
                    end
                    -- 同一装备部位已有合适的保温/降温帽子后不反复在两个帽子间切换。
                    if equipped then break end
                end
            end
            local inv=self.player.replica.inventory
            local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
            if head and head.prefab==prefab then break end
        end
    end
    if s.temperature < 5 then
        for _, entity in ipairs(s.entities) do
            if entity:HasTag("campfire") and entity.Light and entity.Light:IsEnabled() then
                if s.pos:DistSq(entity:GetPosition()) > 6.25 then
                    local point=self:Near(entity:GetPosition(),s.pos,2)
                    if point then return {kind="move",point=point,name="靠近火堆取暖"} end
                end
                return {kind="wait",duration=2,name="烤火"}
            end
        end
        if self.actions:CanCraft("campfire") then return {kind="craft",recipe="campfire",point=Vector3(s.pos.x+2,0,s.pos.z),name="建造火堆"} end
    elseif s.temperature > 65 then
        for _, item in ipairs(s.items) do
            if item.prefab == "ice" or item.prefab == "watermelon" then
                local action = self.actions:FindAction("EAT",nil,item)
                if action then return {kind="action",action=action,name="EAT",item=item} end
            end
        end
        for _, entity in ipairs(s.entities) do
            if entity.prefab == "coldfire" or entity.prefab == "coldfirepit" then
                if entity.Light and entity.Light:IsEnabled() and s.pos:DistSq(entity:GetPosition()) > 6.25 then
                    local point=self:Near(entity:GetPosition(),s.pos,2)
                    if point then return {kind="move",point=point,name="靠近冷火"} end
                end
            end
        end
    end
end

-- 接近实体时留出碰撞距离，从玩家方向选一个可通行的附近点。
function Brain:Near(target, origin, distance)
    local dx,dz=origin.x-target.x,origin.z-target.z
    local length=math.max(.001,math.sqrt(dx*dx+dz*dz))
    local point=Vector3(target.x+dx/length*distance,0,target.z+dz/length*distance)
    if self.actions:SafePoint(point) then return point end
end

-- 只选择当前有动作且不在失败冷却内的目标；安全范围以当前基地为准。
function Brain:Target(s, prefab)
    for _, entity in ipairs(s.entities) do
        if entity.prefab == prefab and not self:Blocked(entity) then return entity end
    end
end

-- 失败目标暂时跳过，防止每次决策重复同一无效请求。
function Brain:Blocked(entity)
    return (self.cooldowns[tostring(entity.GUID)] or 0) > GetTime()
end

-- 先拾取已掉落物品，再采集产生该物品的资源；数量任务以库存实际增长为准。
function Brain:Collect(s, prefab)
    if s.free <= 0 and (s.counts[prefab] or 0)==0 then return end
    for _, e in ipairs(s.entities) do
        local base=self.model.base
        local point=e:GetPosition()
        if e.prefab == prefab and not self:Blocked(e) and (not base or (point.x-base.x)^2+(point.z-base.z)^2<=self.config.max_wander_radius^2)
            and self.actions:SafePoint(point) then
            local action = self.actions:FindAction("PICKUP",e)
            if action then return {kind="action",action=action,name="PICKUP",target=e} end
        end
    end
    local spec = GATHER[prefab]
    if not spec then return end
    for _, e in ipairs(s.entities) do
        local base = self.model.base
        if not self:Blocked(e) and (not base or (e:GetPosition().x-base.x)^2+(e:GetPosition().z-base.z)^2 <= self.config.max_wander_radius^2)
            and self.actions:SafePoint(e:GetPosition())
            and ((spec.tag and e:HasTag(spec.tag)) or (spec.prefabs and spec.prefabs[e.prefab])) then
            local plan = self.actions:Work(spec.action,e,s)
            if plan then return plan end
        end
    end
    return self:RememberResource(s,spec)
end

-- 本地记忆引导重访已见资源；位置不生成动作/虚构实体，只在抵达后重新感知。
function Brain:RememberResource(s,spec)
    local base=self.model.base
    if not base then return end
    local best,best_distance
    for _, resource in ipairs(self.model.resources) do
        if (spec.tag and resource.work==spec.action) or (spec.prefabs and spec.prefabs[resource.prefab]) then
            local point=Vector3(resource.x,0,resource.z)
            local distance=s.pos:DistSq(point)
            local key=resource.prefab..":"..resource.x..":"..resource.z
            if distance<9 then self.memory_visits[key]=GetTime()+60 end
            if distance>=9 and (point.x-base.x)^2+(point.z-base.z)^2<=self.config.max_wander_radius^2
                and (self.memory_visits[key] or 0)<=GetTime() and (not best_distance or distance<best_distance)
                and self.actions:SafePoint(point) then
                best,best_distance={kind="move",point=point,name="重访资源："..resource.prefab,collection=true},distance
            end
        end
    end
    return best
end

-- 用户任务只读取队首，危险与生存节点可抢占；一次性任务需要实际确认后才出队。
function Brain:Task(s)
    local task = self.model.tasks[1]
    if not task then return end
    if task.blocked then return {kind="wait",duration=2,name="任务暂停："..(task.error or "连续失败")} end
    if task.kind == "collect" then
        if type(task.goal) ~= "number" or not task.prefab then task.error="损坏的收集任务"; return end
        if (s.counts[task.prefab] or 0) >= task.goal then return {kind="complete",name="收集完成",task=task} end
        local plan = self:Collect(s,task.prefab)
        if plan then plan.task=task; plan.collection=true; return plan end
        return {kind="wait",duration=2,name="等待资源："..task.prefab}
    elseif task.kind == "goto" then
        if not self.model:ValidPoint(task) then task.error="坐标无效"; return end
        local point=Vector3(task.x,0,task.z)
        if s.pos:DistSq(point)<2.25 then return {kind="complete",name="抵达任务坐标",task=task} end
        if not self.actions:SafePoint(point) then task.error="路线不可通行，请分段设置坐标"; return end
        return {kind="move",point=point,name="前往任务坐标",task=task}
    elseif task.kind == "build" then
        if not self.actions:CanCraft(task.recipe) then task.error="配方未解锁或材料不足"; return end
        return {kind="craft",recipe=task.recipe,point=Vector3(task.x or s.pos.x+2,0,task.z or s.pos.z),name="制作 "..task.recipe,task=task}
    elseif task.kind == "action" then
        local item = task.item and self.perception:FindItem(task.item,s)
        if task.item and not item then task.error="没有物品："..task.item; return end
        local target = task.target ~= "self" and task.target ~= "ground" and self:Target(s,task.target) or nil
        if task.target ~= "self" and task.target ~= "ground" and not target then task.error="附近没有目标："..tostring(task.target); return end
        local point = task.target == "ground" and Vector3(task.x or s.pos.x+2,0,task.z or s.pos.z) or nil
        local plan = target and (task.name == "CHOP" or task.name == "MINE" or task.name == "DIG") and self.actions:Work(task.name,target,s) or nil
        if not plan then
            local action = self.actions:FindAction(task.name,target,item,point)
            if action then plan={kind="action",action=action,name=task.name,target=target,item=item} end
        end
        if not plan then task.error="游戏当前未提供这个动作，请核对工具/目标/物品"; return end
        task.error=nil; plan.task=task; return plan
    elseif task.kind == "store" or task.kind == "take" then
        local target = self:Target(s,task.target)
        if not target or not target.replica.container then task.error="没有可用容器"; return end
        if not target.replica.container:IsOpenedBy(self.player) then
            local action = self.actions:FindAction("RUMMAGE",target)
            if action then return {kind="action",action=action,name="RUMMAGE",target=target,setup=true,task=task} end
            task.error="容器无法打开"; return
        end
        return {kind="transfer",direction=task.kind,prefab=task.prefab,target=target,name=task.kind,task=task}
    end
    task.error="未知任务类型"
end

-- 保存基础生存资源库存；不会自动攻击、挖掘他人建筑或转移他人容器物品。
function Brain:Resources(s)
    if s.night or #self.model.tasks>0 then return end
    local desired = {{"berries",6},{"cutgrass",12},{"twigs",10},{"flint",4},{"log",12},{"rocks",6}}
    local options={}
    for _, item in ipairs(desired) do
        if self.profile.data.lumber and item[1]=="log" then item[2]=20 end
        if self.profile.data.meat and item[1]=="berries" then item[1],item[2]="cookedmeat",4 end
        if self.profile.data.plant and item[1]=="log" and (s.sanity or 1)<.5 then item[2]=0 end
        if (s.counts[item[1]] or 0)<item[2] then
            local plan=self:Collect(s,item[1])
            if plan then plan.resource=item[1]; plan.priority=item[1]=="berries" and 60 or 55; options[#options+1]=plan end
        end
        if #options>=2 then break end
    end
    return self.humanizer:Choose(options)
end

-- 安全灭火仅在没有敌人且角色可用 SMOTHER 动作时执行。
function Brain:Extinguish(s)
    if #s.threats>0 or (s.health or 1)<.4 then return end
    for _, entity in ipairs(s.entities) do
        if entity:HasTag("burning") and s.pos:DistSq(entity:GetPosition())<16 then
            local action=self.actions:FindAction("SMOTHER",entity)
            if action then return {kind="action",action=action,name="SMOTHER",target=entity} end
        end
    end
end

-- 基地周边巡逻不在夜间或有未完成的用户任务时执行。
function Brain:Wander(s)
    if s.night or #self.model.tasks>0 then return end
    local base=self.model.base
    if not base then return end
    local radius=math.sqrt((s.pos.x-base.x)^2+(s.pos.z-base.z)^2)
    if radius>self.config.max_wander_radius then
        local p=Vector3(base.x,0,base.z)
        if self.actions:SafePoint(p) then return {kind="move",point=p,name="返回基地"} end
    end
    if math.random()<.3 then return end
    for _=1,8 do
        local angle=math.random()*math.pi*2
        local distance=math.random()*self.config.max_wander_radius
        local p=self.humanizer:Offset(Vector3(base.x+math.cos(angle)*distance,0,base.z+math.sin(angle)*distance))
        if (p.x-base.x)^2+(p.z-base.z)^2 <= self.config.max_wander_radius^2 and self.actions:SafePoint(p) then return {kind="move",point=p,name="基地巡逻"} end
    end
end

-- Selector：每个周期评估条件，拟人化只在日常节点优先级接近时改变选择。
function Brain:Evaluate(s)
    local candidates={}
    for _, node in ipairs(self.nodes) do
        local plan=node.condition(s)
        if plan then plan.priority=node.priority; plan.label=node.name; plan.emergency=plan.emergency or node.priority>=85; candidates[#candidates+1]=plan end
        -- 紧急节点不会因后续非紧急节点的条件副作用改变队列。
        if plan and node.priority>=80 then break end
    end
    return self.humanizer:Choose(candidates)
end

-- 执行中的动作只评估紧急叶节点，避免每0.1秒重复生成整套日常动作候选。
function Brain:Emergency(s)
    for _, node in ipairs(self.nodes) do
        if node.priority>=85 then
            local plan=node.condition(s)
            if plan then plan.priority=node.priority; plan.label=node.name; plan.emergency=true; return plan end
        end
    end
end

AIPLAYER.Brain = Brain

return true
