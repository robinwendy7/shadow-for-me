local AIPLAYER=require("shadowself/legacy/registry")
-- 托管控制器：生命周期、单动作执行、同步确认、抢占、有限失败与本地命令。
local Controller = Class(function(self, player, config)
    self.player, self.config = player, config
    self.active, self.armed, self.removed = false, false, false
    self.pending, self.ui = nil, nil
    self.last_input, self.next_action, self.next_save = GetTime(), 0, GetTime()+30
    self.errors, self.failures, self.messages = 0, {}, {}
    self.status = "停止 · 点击接管开启"
    self.model=AIPLAYER.WorldModel(player,function(message) self:Report(message) end)
    self.perception=AIPLAYER.Perception(player,config,self.model)
    self.actions=AIPLAYER.ActionLibrary(player,config,self.perception)
    self.profile=AIPLAYER.Profiles(player,config,self.model)
    self.humanizer=AIPLAYER.Humanizer(config,self.profile)
    self.brain=AIPLAYER.Brain(player,config,self.model,self.perception,self.actions,self.humanizer,self.profile)
    -- 保留旧 AI 的生存决策；战斗由外层 3014 桥接独占。
    self.combat={roles={CanRunForm=function() return false end},learning={Damage=function() end},Reset=function() end,Tick=function() return false end,StatusLine=function() return "生存避险" end}
    self.brain.combat_disabled=true
    
    self.model:Load()
    -- 由影子 Takeover:Tick 调度，禁止独立计时器在停止后继续操作。
    
end)

-- 日志只留在本地；HUD 状态也不调用角色 Say 或网络聊天。
function Controller:Report(message)
    print("[AI Player] "..tostring(message))
    self.notice=tostring(message)
    self.notice_until=GetTime()+8
    self:UpdateUI()
end

-- 同一种提示限频，无法照明等危险信息不会每帧刷日志。
function Controller:ReportOnce(key,message,interval)
    if (self.messages[key] or 0)<=GetTime() then
        self.messages[key]=GetTime()+(interval or 10)
        self:Report(message)
    end
end

-- 开启必须是当前本地活角色；持久化记忆尚未加载时等待下一次操作。
function Controller:Start()
    if not self.model.ready then self:Report("正在加载本地任务，请稍候再开启"); return false end
    if self.player~=ThePlayer or not self.player:IsValid() or self.player:HasTag("playerghost") or self.player:HasTag("isdead") then
        self:Report("当前角色不能托管"); return false
    end
    self:ValidateLoadedTasks()
    if not self.model.base then self.model:SetBase(self.player:GetPosition()) end
    self.active,self.armed=true,true
    self.pending=nil
    self.next_action=GetTime()
    self.last_input=GetTime()
    self:Report("托管开启 "..(AIPLAYER.Version or "1.1.1").." · "..self.profile.data.label.." · 说停或点击停止交回")
    return true
end

-- 手动停止会解除自动闲置接管；手动移动接管保留本会话的闲置选项。
function Controller:Stop(reason,disarm)
    if disarm~=false then self.armed=false end
    local was_active=self.active
    self.active=false
    if self.combat then self.combat:Reset() end
    self.pending=nil
    self.last_input=GetTime()
    self.status="停止 · 点击接管开启"
    local ok,error=pcall(function() self.actions:Stop() end)
    if not ok and self.config.debug then print("[AI Player] 停止接口："..tostring(error)) end
    self.model:Save()
    if was_active and reason then self:Report(reason) else self:UpdateUI() end
end

-- 启停入口供快捷键和界面复用。
function Controller:Toggle()
    if self.active then self:Stop("托管已停止") else self:Start() end
end

-- 原生输入到达时立即释放 AI；不是模拟键盘输入，因此不会被自身操作触发。
function Controller:InputTouched()
    self.last_input=GetTime()
    if self.active then self:Stop("已由你接管",false) end
end

-- 区分菜单暂停和角色消失；打开地图、聊天、库存、骑乘及变身时不自动发送动作。
function Controller:CanRun()
    local p=self.player
    if p~=ThePlayer or not p:IsValid() then return false,"角色离开当前世界",true end
    if p:HasTag("playerghost") or p:HasTag("isdead") then return false,"死亡/幽灵状态",true end
    local health=p.replica.health
    if health and health:IsDead() then return false,"角色死亡",true end
    if self.profile:IsTransformed() and not self.combat.roles:CanRunForm() then return false,"此形态暂无原生近战接管" end
    local rider=p.replica.rider
    if rider and rider:IsRiding() and (not rider.GetMount or not rider:GetMount()) then return false,"等待坐骑同步" end
    if p.GetCurrentPlatform and p:GetCurrentPlatform() and not TheWorld.Map.GetPlatformAtPoint then return false,"等待平台同步" end
    if p:HasTag("sleeping") or p:HasTag("frozen") or p:HasTag("pinned") or p:HasTag("knockout") then return false,"角色暂时无法行动" end
    local pc=p.components.playercontroller
    if not pc or not pc:IsEnabled() then return false,"控制器暂不可用" end
    local active=p.replica.inventory and p.replica.inventory:GetActiveItem()
    if active and active~=self.actions.active_item then return false,"鼠标手持物品时暂停" end
    local screen=TheFrontEnd and TheFrontEnd:GetActiveScreen()
    if not screen or screen.name~="HUD" then return false,"菜单/聊天期间暂停" end
    if p.HUD and p.HUD.IsMapScreenOpen and p.HUD:IsMapScreenOpen() then return false,"地图期间暂停" end
    if p.HUD and p.HUD.IsControllerInventoryOpen and p.HUD:IsControllerInventoryOpen() then return false,"背包界面期间暂停" end
    if TheNet and TheNet.GetIsServerPaused and TheNet:GetIsServerPaused() then return false,"服务器暂停" end
    if IsPaused and IsPaused() then return false,"游戏暂停" end
    return true
end

-- 统一错误边界；连续三次内部异常停止，不继续打扰正常游戏。
function Controller:SafeTick()
    if self.removed then return end
    local ok,error=pcall(function() self:Tick() end)
    if ok then self.errors=0
    else
        self.errors=self.errors+1
        self:ReportOnce("error","托管错误："..tostring(error),5)
        if self.errors>=3 then self:Stop("连续异常，托管已停止") end
    end
end

-- 每周期处理一个状态：感知、预定动作、发送、等待确认或失败回退。
function Controller:Tick()
    local now=GetTime()
    self:UpdateUI()
    if not self.active then
        if self.armed and self.config.idle_activate>0 and now-self.last_input>=self.config.idle_activate then
            local runnable=self:CanRun()
            if runnable then self:Start() end
        end
        return
    end
    local runnable,reason,terminal=self:CanRun()
    if not runnable then
        if terminal then self:Stop(reason); return end
        if not self.suspended then self.actions:Stop(); self.pending=nil; self.combat:Reset() end
        self.suspended=true
        self.status="暂停 · "..reason
        return
    end
    self.suspended=false
    local threats=self.perception:Threats()
    local s=self.perception:Scan(false)
    s.threats=threats
    if now>=self.next_save then self.model:Save(); self.next_save=now+30 end
    if self.combat:Tick(s) then return end
    local rider=self.player.replica.rider
    if self.profile:IsTransformed() or rider and rider:IsRiding()
        or self.player.GetCurrentPlatform and self.player:GetCurrentPlatform() then
        self.status="特殊形态/平台 · 等待战斗目标";return
    end
    -- 非紧急目标承诺：一棵树/一块矿完成前不因日常优先级细微变化来回换目标。
    if self.pending then
        local urgent=self.brain:Emergency(s)
        if urgent and (urgent.priority or 0)>=85 and ((urgent.priority or 0)>(self.pending.priority or 0)
            or (self.pending.name=="ATTACK" and urgent.kind=="move")) then
            self.actions:Stop(); self.pending=nil; self.next_action=now
        end
    end
    if self.pending then self:StepPending(s); return end
    if now<self.next_action then return end
    local plan=self.brain:Evaluate(s)
    if not plan then return end
    local task=self.model.tasks[1]
    if task and task.error and (plan.priority or 0)<80 then
        self:ReportOnce("task:"..task.error,"任务等待："..task.error.."（status 查看，skip 跳过）",30)
    end
    if plan.kind=="complete" then self:CompleteTask(plan.task); return end
    plan.due=now+self.humanizer:Delay(plan.emergency)
    self.pending=plan
    self.status=(plan.label or plan.name).." · 准备"
    self.model.last_decision=plan.name
    if self.config.debug then print("[AI Player] 决策 "..plan.name.." 优先级 "..tostring(plan.priority)) end
end

-- 发送前重新查询动作，避免反应延迟期间目标消失、工具损坏或工具刚被更换。
function Controller:RefreshAction(plan,s)
    if plan.kind=="move" then return self.actions:Walk(plan.point) end
    if plan.kind=="action" then
        if plan.target and not plan.target:IsValid() then return nil end
        if plan.item and not plan.item:IsValid() then return nil end
        local point=plan.action and plan.action.pos and plan.action:GetActionPoint() or nil
        return self.actions:FindAction(plan.name,plan.target,plan.item,point)
    end
end

-- 工作动作允许有节奏地重复敲击，消耗物品/制作/传送等非幂等请求只发送一次并等待。
function Controller:StepPending(s)
    local plan=self.pending
    local now=GetTime()
    if not plan.sent then
        if now<plan.due then return end
        local pc=self.player.components.playercontroller
        if pc:IsBusy() then
            if now-plan.due>8 then self:Fail(plan,"角色持续忙碌") end
            return
        end
        s=self.perception:Scan(true)
        if plan.kind=="action" and plan.item and plan.action and plan.action.pos then
            local ready,reason=self.actions:PrepareActive(plan.item)
            if not ready then
                self.status=reason
                if now-plan.due>5 then self:Fail(plan,reason) end
                return
            end
        end
        plan.before=self.actions:Stamp(plan,s)
        local ok=false
        if plan.kind=="wait" then
            ok=true
            if plan.name:find("请接管",1,true) or plan.name:find("无安全",1,true) then self:ReportOnce(plan.name,plan.name,15) end
            if self.config.enable_emotes and not plan.emergency and now>=self.humanizer.next_emote and #self.model.tasks==0 then
                self.humanizer.next_emote=now+120+math.random()*180
                if math.random()<.3 then require("usercommands").RunTextUserCommand("wave",self.player,false) end
            end
        elseif plan.kind=="craft" then ok=self.actions:Craft(plan.recipe,plan.point)
        elseif plan.kind=="transfer" then ok=self.actions:Transfer(plan.direction,plan.prefab,plan.target)
        elseif plan.kind=="drop" then ok=self.actions:DropSingle(plan.item)
        else
            local action=self:RefreshAction(plan,s)
            if action then plan.action=action; ok=self.actions:Execute(action) end
        end
        if not ok then self:Fail(plan,"动作不可用/路线阻挡"); return end
        plan.sent,plan.last_send,plan.strikes=now,now,1
        self.status=plan.name.." · 等待结果"
        return
    end
    if plan.kind=="wait" then
        if now-plan.sent>=(plan.duration or 1) then self:Finish(plan) end
        return
    end
    if now-plan.sent>.35 and self.actions:Confirmed(plan,plan.before,s) then self:Finish(plan); return end
    local repeated=plan.name=="CHOP" or plan.name=="MINE" or plan.name=="DIG" or plan.name=="ATTACK"
    local timeout=repeated and 30 or self.config.action_timeout
    if now-plan.sent>timeout then self:Fail(plan,"未收到可观察的完成结果（超时）"); return end
    if repeated and plan.strikes<24 and now-plan.last_send>=1.05 then
        local pc=self.player.components.playercontroller
        if not pc:IsBusy() and not self.player:HasTag("moving") then
            local action=self:RefreshAction(plan,s)
            if not action then self:Fail(plan,"目标动作已不可用"); return end
            if self.actions:Execute(action) then plan.last_send=now; plan.strikes=plan.strikes+1 end
        end
    end
end

-- 确认后出队；准备装备和收集子动作保留原任务。
function Controller:Finish(plan)
    self.pending=nil
    self.actions:ReleaseActive()
    local failurekey=plan.name..":"..(plan.target and tostring(plan.target.GUID) or tostring(plan.recipe or ""))
    self.failures[failurekey]=nil
    self.profile:OnCompleted(plan)
    if plan.task and not plan.setup and not plan.collection then self:CompleteTask(plan.task) end
    self.next_action=GetTime()+self.humanizer:AfterAction(plan.emergency)
    self.perception.next_scan=0
    self.status="托管中 · "..(plan.name or "完成")
end

-- 队首身份检查防止陈旧计划错误地删除新任务。
function Controller:CompleteTask(task)
    if self.model.tasks[1]==task then
        table.remove(self.model.tasks,1)
        self.model:Save()
        self:Report("任务完成 · 剩余 "..tostring(#self.model.tasks).." 项")
    end
end

-- 失败任务三次后暂停；资源目标冷却。只对相关目标重试，不发送不明 RPC 洪泛。
function Controller:Fail(plan,reason)
    self.actions:Stop()
    self.pending=nil
    self.next_action=GetTime()+2
    if plan.target then self.brain.cooldowns[tostring(plan.target.GUID)]=GetTime()+15 end
    if plan.task then
        plan.task.failures=(tonumber(plan.task.failures) or 0)+1
        plan.task.error=reason
        if plan.task.failures>=self.config.max_failures then plan.task.blocked=true end
        self.model:Save()
    else
        local key=plan.name..":"..(plan.target and tostring(plan.target.GUID) or tostring(plan.recipe or ""))
        self.failures[key]=(self.failures[key] or 0)+1
        if self.failures[key]>=self.config.max_failures and plan.kind~="move" then
            self:Stop("同一动作连续失败，请检查服务器权限/材料："..plan.name); return
        end
    end
    self:ReportOnce(plan.name,"动作失败："..plan.name.." · "..reason,10)
end

-- 数据检查覆盖用户命令与本地 JSON，避免错误类型进入决策层。
function Controller:ValidTask(task)
    if type(task)~="table" then return false end
    local function name(value) return type(value)=="string" and #value>0 and #value<100 and value:match("^[%w_%-]+$")~=nil end
    if task.kind=="collect" then return name(task.prefab) and type(task.goal)=="number" and task.goal>0 and task.goal<=10000 end
    if task.kind=="goto" then return self.model:ValidPoint(task) end
    if task.kind=="build" then return name(task.recipe) and AllRecipes[task.recipe]~=nil and (task.x==nil or self.model:ValidPoint(task)) end
    if task.kind=="action" then return name(task.name) and ACTIONS[task.name]~=nil and name(task.target) and (task.item==nil or name(task.item)) and (task.x==nil or self.model:ValidPoint(task)) end
    if task.kind=="store" or task.kind=="take" then return name(task.prefab) and name(task.target) end
    return false
end

-- 移除无效的旧存档任务，保留合法任务与资源记忆。
function Controller:ValidateLoadedTasks()
    for i=#self.model.tasks,1,-1 do
        local task=self.model.tasks[i]
        if not self:ValidTask(task) then table.remove(self.model.tasks,i); self:Report("已移除无效的旧任务")
        else
            task.error=type(task.error)=="string" and task.error or nil
            task.failures=tonumber(task.failures) or 0
            task.blocked=task.blocked==true
        end
    end
end

-- 新任务最大32项；添加任务不会在未授权时偷偷开启托管。
function Controller:Queue(task)
    if not self.model.ready then self:Report("本地任务仍在加载"); return end
    if not self:ValidTask(task) then self:Report("任务参数无效，输入 /autopilot help 查看用法"); return end
    if #self.model.tasks>=32 then self:Report("任务队列已满（32项）"); return end
    self.model.tasks[#self.model.tasks+1]=task
    self.model:Save()
    self:Report("任务已排队 · "..task.kind.." · 共 "..#self.model.tasks.." 项")
end

-- 状态包含队首错误，方便玩家明确地重试/跳过，而非一直猜测挂机是否有动作。
function Controller:Status()
    local task=self.model.tasks[1]
    local message=(self.active and "托管中" or "已停止").." · "..self.profile.data.label.." · 任务 "..#self.model.tasks
    if task then message=message.." · "..task.kind.." "..tostring(task.prefab or task.recipe or task.name or "") end
    if task and task.error then message=message.." · "..task.error end
    if task and task.kind=="collect" then
        local s=self.perception:Scan(true)
        message=message.." · 库存 "..tostring(s.counts[task.prefab] or 0).."/"..tostring(task.goal)
    end
    if self.combat then message=message.." · "..self.combat:StatusLine() end
    self:Report(message)
end

-- 命令仅在本客户端解析，不调用网络聊天或自定义服务端命令。
function Controller:Command(text)
    local args={}
    for token in (text or ""):gmatch("%S+") do args[#args+1]=token end
    local command=(args[1] or "toggle"):lower()
    if command=="start" or command=="on" then self:Start()
    elseif command=="stop" or command=="off" then self:Stop("托管已停止")
    elseif command=="toggle" then self:Toggle()
    elseif command=="status" then self:Status()
    elseif command=="fight" or command=="combat" then
        if args[2]=="stop" or args[2]=="off" then
            self.actions:Stop(); self.pending=nil; self.combat:Reset(); self.combat.enabled=false; self.brain.combat_disabled=true
            self:Report("自动战斗关闭，保留生存避险；fight on 重新启用")
        elseif args[2]=="on" then self.combat.enabled=true; self.brain.combat_disabled=false; self:Report("战斗走位开启，只响应已有威胁")
        else
            local ok,message=self.combat:Lock(args[2]); self:Report(message)
            if ok then self.brain.combat_disabled=false end
            if ok and not self.active and not self:Start() then self.combat:Reset() end
        end
    elseif command=="base" then
        if not self.model.ready then self:Report("等待本地记忆加载"); return end
        self.model:SetBase(self.player:GetPosition()); self:Report("基地已设为当前位置")
    elseif command=="clear" then
        self.actions:Stop(); self.pending=nil; self.model.tasks={}; self.model:Save(); self:Report("任务已清空")
    elseif command=="skip" then
        self.actions:Stop(); self.pending=nil; table.remove(self.model.tasks,1); self.model:Save(); self:Report("已跳过队首任务")
    elseif command=="retry" then
        local task=self.model.tasks[1]
        if task then task.blocked=false; task.failures=0; task.error=nil; self.model:Save(); self:Report("队首任务可重试") end
    elseif command=="collect" then
        local n=tonumber(args[3])
        if not args[2] or not n or n~=math.floor(n) or n<1 or n>500 then self:Report("用法：collect log 20（数量1–500）"); return end
        local s=self.perception:Scan(true)
        self:Queue({kind="collect",prefab=args[2],goal=(s.counts[args[2]] or 0)+n})
    elseif command=="goto" then self:Queue({kind="goto",x=tonumber(args[2]),z=tonumber(args[3])})
    elseif command=="build" then
        if args[3] and (not tonumber(args[3]) or not tonumber(args[4])) then self:Report("建筑坐标需要 x z 两个数"); return end
        self:Queue({kind="build",recipe=args[2],x=tonumber(args[3]),z=tonumber(args[4])})
    elseif command=="action" then
        local aliases={FUEL="ADDFUEL",OPEN="RUMMAGE",SLEEP="SLEEPIN",TELEPORT="JUMPIN",USE="ACTIVATE"}
        local name=(args[2] or ""):upper(); name=aliases[name] or name
        local item=args[4]~="-" and args[4] or nil
        if args[5] and (not tonumber(args[5]) or not tonumber(args[6])) then self:Report("动作坐标需要 x z 两个数"); return end
        self:Queue({kind="action",name=name,target=args[3] or "self",item=item,x=tonumber(args[5]),z=tonumber(args[6])})
    elseif command=="store" or command=="take" then self:Queue({kind=command,prefab=args[2],target=args[3]})
    elseif command=="actions" then
        local names={}; for name,def in pairs(ACTIONS) do if type(name)=="string" and type(def)=="table" and def.code then names[#names+1]=name end end
        table.sort(names)
        print("[AI Player] 游戏注册动作（是否可用取决于目标/工具/权限）：\n"..table.concat(names,", "))
        self:Report("动作名称列表已输出到本地 client_log.txt；使用 action 名称 目标 物品")
    else
        self:Report("F8启停；fight [生物prefab]、fight stop/on；/autopilot status、base、collect log 20、goto x z、build torch、action COOK cookpot、store log treasurechest；clear/skip/retry 管理队列")
    end
end

-- 用户输入与 UI 事件也有错误边界，错误不会传播到原版聊天控件。
function Controller:SafeCommand(text)
    local ok,error=pcall(function() self:Command(text) end)
    if not ok then self:Report("命令错误："..tostring(error)) end
end

-- HUD 使用自己的 Widget，不替换原版根控件；生命周期跟随角色和 Controls。
function Controller:UpdateUI()
    if self.ui and self.ui.inst and self.ui.inst:IsValid() then
        local status=(self.notice and (self.notice_until or 0)>GetTime()) and self.notice or self.status
        local toggle=self.active and "停止托管 [F8]" or "开启托管 [F8]"
        if self.ui.last_status~=status then self.ui.status:SetString(status); self.ui.last_status=status end
        if self.ui.last_toggle~=toggle then self.ui.toggle:SetText(toggle); self.ui.last_toggle=toggle end
    end
end

-- 世界卸载停止计时器；重连后的新控制器只恢复数据，始终保持停止。
function Controller:Remove()
    if self.removed then return end
    self:Stop(nil)
    self.removed=true
    if self.tick then self.tick:Cancel(); self.tick=nil end
    self.ui=nil
end

AIPLAYER.Controller=Controller

return true
