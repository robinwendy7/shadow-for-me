local Request=require("shadowself/control/request")
local Actions=require("shadowself/control/actions")
local Jobs=require("shadowself/control/jobs")
local Combat=require("shadowself/control/combat")
local Takeover=Class(function(self,runtime)
    self.r=runtime;self.jobs=Jobs(runtime.owner);self.combat=Combat(runtime.owner)
    self.music=require("shadowself/battlemusic")(runtime)
    self.jobs.report=function(text) if not self.battle_active then self:Speak("progress",{detail=text}) end end
end)
local battle_lines={"会赢的。","怎么敢欺负我本体的……？","我不会留手的！","我会替你揍它的！","你好好休息吧，这次换我来保护你！"}
function Takeover:BattleLine()
    self.battle_line_index=((self.battle_line_index or math.random(#battle_lines))-1)%#battle_lines+1
    self:Say(battle_lines[self.battle_line_index])
    self.battle_line_index=self.battle_line_index%#battle_lines+1
    self.next_battle_line=GetTime()+18
end
function Takeover:BeginBattle()
    if self.battle_active then return end
    self.battle_active=true;self.r.queue={}
    self:BattleLine();self.music:Start()
end
function Takeover:EndBattle() self.battle_active=nil;self.next_battle_line=nil;self.music:Stop() end
function Takeover:Say(text) self.r.dialogue:Say("control",100,text,true) end
function Takeover:Speak(key,args)
    local d=self.r.dialogue;local code=d.GetPersonality and d:GetPersonality().code or "original"
    self:Say(require("shadowself/control/language")(code,key,args))
end
function Takeover:AskPlan(plan,text)
    local ok,message=self:CanStart(plan)
    if not ok then self:Say(message);return true end
    if self.phase and self.phase~="active" then self:Say("等覆盖完成。也可以说取消。");return true end
    if self.phase=="active" then self:EndBattle();self.jobs:Cancel();self.combat:Stop();Actions.Stop(self.r.owner);self.task=nil end
    self.last_request=text;self.pending={plan=plan,until_time=math.huge}
    self:Speak("permission",{task=plan.label});self:Say("回复“同意接管”，或点人物脚下的“同意接管”。")
    if self.r.speech then self.r.speech:Pin("需要我帮你"..plan.label.."的话，点同意接管。") end
    return true
end
function Takeover:HandleCook(text)
    local likely=self.await_dish or text:find("做",1,true) or text=="肉丸" or text=="羊角冻" or text=="辣羊角冻"
    if not likely and not (STRINGS and STRINGS.NAMES) then return false end
    local food=require("shadowself/control/foodplan")
    local dish,why=food.Parse(text,self.await_dish~=nil)
    if dish=="ask" then self.await_dish=GetTime()+120;self:Speak("cook_ask");return true end
    if dish then
        self.await_dish=nil
        return self:AskPlan({kind="cook",dish=dish,target=(STRINGS and STRINGS.NAMES[dish.product:upper()]) or text,label="做"..((STRINGS and STRINGS.NAMES[dish.product:upper()]) or text),text=text},text)
    end
    if why then self:Say(why);return true end
    return false
end
function Takeover:OfferCombat()
    if self.phase or self.pending or self.r.dead then return false end
    if not self.combat:Available() then return false end
    self.pending={plan={kind="fight",target="",defensive=true,label="接手战斗"},until_time=math.huge}
    local queue={};for _,e in ipairs(self.r.queue or {}) do if e.kind~="hurt" then queue[#queue+1]=e end end;self.r.queue=queue
    self:Say("亲爱的我，你又受伤了，需要我帮忙的话点同意接管。")
    if self.r.speech then self.r.speech:Pin("亲爱的我，你又受伤了，需要我帮忙的话点同意接管。") end
    return true
end
function Takeover:CanStart(plan)
    local p=self.r.owner
    if not self.r.loaded or not self.r.actor then return false,"还没准备好，等我出现后再叫我。" end
    if p:HasTag("playerghost") or p:HasTag("corpse") or self.r.dead then return false,"你现在是灵魂。我会陪着你，但不能以人形执行这项操作。" end
    if self.r.actor.ceremony then return false,"等这段演出结束、你站稳以后再接管。" end
    if not self.phase and TUNING and TUNING.Cheatthread then return false,"3014 正在执行另一段走A。请先停掉那段进程，再让我接管。" end
    if plan.kind=="cook" and require("shadowself/control/foodplan").RequiresWarly(plan.dish) and p.prefab~="warly" then return false,"这道菜需要沃利和便携厨具。" end
    if (plan.kind=="fight" or plan.kind=="dodge") and not self.combat:Available() then
        return false,"内置战斗模块尚未准备好。"
    end
    return true
end
function Takeover:HandleText(text)
    local topics={["看看背包"]="inventory",["背包有什么"]="inventory",["查看装备"]="equipment",["查看三维"]="stats",["我在哪"]="position",["周围有什么"]="nearby",["查看天气"]="world"}
    if topics[text] then
        local result=require("shadowself/zom/StateReporter").Get(_G,self.r.owner,topics[text])
        if type(result)=="table" then for _,line in ipairs(result) do self:Say(line) end else self:Say(result) end
        return true
    end
    if text=="继续刚才的任务" or text=="再来一次" then
        if not self.last_request then self:Say("还没有可以重复的任务。");return true end
        text=self.last_request
    end
    if Request.IsStop(text) and (self.await_dish or self.pending or self.phase) then self:Stop(nil);self:Speak("stop");return true end
    if self.await_dish and GetTime()>self.await_dish then self.await_dish=nil end
    if self:HandleCook(text) then return true end
    if self.pending and Request.IsYes(text) then
        if GetTime()>self.pending.until_time then self.pending=nil;self:Say("刚才的接管请求已过期，请重新告诉我要做什么。");return true end
        local ok,why=self:CanStart(self.pending.plan)
        if not ok then self.pending=nil;if self.r.speech then self.r.speech:ClearPin() end;self:Say(why);return true end
        local plan=self.pending.plan;self.pending=nil
        if self.r.speech then self.r.speech:ClearPin() end
        if plan.kind~="fight" and plan.kind~="dodge" and plan.kind~="autonomy" and plan.kind~="arena" then plan.protect=true end
        if self.phase=="active" then
            self.task=plan;self.jobs:Set(plan);self.job_started=nil
            self:Speak("enter",{task=plan.label})
        else
            Actions.Stop(self.r.owner)
            local x,y,z=self.r.actor.inst.Transform:GetWorldPosition()
            self.origin={x=x,y=y,z=z};self.start=GetTime();self.phase="diving";self.task=plan;self.job_started=nil
            self.r.actor.inst.AnimState:PlayAnimation("jump_pre",false)
            self.r.actor.inst.AnimState:PushAnimation("jump",false)
            self.r.actor:SetRate(1)
            self:Speak("transition")
        end
        return true
    end
    local plan,why=Request.Parse(text)
    if why then self:Say(why);return true end
    if not plan then return false end
    return self:AskPlan(plan,text)
end
-- Clicking the combat HUD button is explicit consent; preserve covering animation.
function Takeover:CombatButton()
    if self.phase then self:Stop(nil);self:Speak("stop");return end
    local plan={kind="fight",target="",label="战斗接管"}
    local ok,why=self:CanStart(plan)
    if not ok then self:Say(why);return end
    self.last_request="帮我自动战斗"
    self.pending={plan=plan,until_time=math.huge}
    return self:HandleText("同意接管")
end
-- 按钮是明确的接管授权；有待确认任务时直接批准，否则开启自主生存。
function Takeover:Button()
    if self.pending then return self:HandleText("同意接管") end
    if self.phase then self:Stop(nil);self:Speak("stop");return end
    local plan={kind="autonomy",label="自主生存",text="按钮接管"}
    local ok,why=self:CanStart(plan)
    if not ok then self:Say(why);return end
    self.last_request="帮我自主托管"
    self.pending={plan=plan,until_time=math.huge}
    return self:HandleText("同意接管")
end
function Takeover:Tick()
    if self.pending and (self.r.dead or self.r.owner:HasTag("playerghost") or self.r.owner:HasTag("corpse")) then self:Stop(nil,true);return end
    if self.pending and GetTime()>self.pending.until_time then self.pending=nil;self:Say("接管确认超时了。我没有执行刚才的任务。") end
    if not self.phase then return end
    local p=self.r.owner
    if p:IsValid() and self.task and self.task.kind=="arena" and self.phase=="active"
        and (p:HasTag("playerghost") or p:HasTag("corpse") or self.r.dead) then
        self.jobs:Tick();return
    end
    if not p:IsValid() or p:HasTag("playerghost") or p:HasTag("corpse") or p.AnimState:IsCurrentAnimation("death") or self.r.dead then
        self:Stop("你倒下了，接管已经停止。我会以灵魂陪着你。");return
    end
    if self.phase~="active" or not self.task or self.pending then return end
    if self.task.kind~="fight" and self.task.kind~="dodge" and TUNING and TUNING.Cheatthread and not self.jobs:OwnsCombat() then
        self:Stop("另一段走A开始控制人物了，我先交回操作，避免争抢。");return
    end
    if self.task.kind=="fight" or self.task.kind=="dodge" then
        if not self.job_started then
            local ok,why=self.combat:Start(setmetatable({coordinated=true},{__index=self.task}),function(e,name) return self.jobs:Matches(e,name) end)
            if not ok then self:Stop(why);return end
            self.job_started=true
            if self.task.kind=="fight" then self:BeginBattle() end
        elseif self.task.kind=="fight" and not self.combat:Running() then
            self:Stop("战斗进程已结束，控制还给你。");return
        elseif self.task.kind=="dodge" and TUNING.Cheatthread then
            self:Stop("另一个走A进程启动了，我先退出接管，避免两个进程争抢。")
        end
    else
        local state,message=self.jobs:Tick()
        if self.jobs:OwnsCombat() then self:BeginBattle() elseif self.battle_active then self:EndBattle() end
        if state=="failed" then self:Stop(message)
        elseif state=="done" then
            Actions.Stop(p);self.task=nil
            self:Speak("done",{detail=message or "这一项做完了。"})
        end
    end
    if self.battle_active and self.next_battle_line and GetTime()>=self.next_battle_line
        and GetTime()-(self.r.memory.last_user_speech or -100)>5 then self:BattleLine() end
end
function Takeover:Frame(dt)
    if not self.phase then return false end
    local actor=self.r.actor;local p=self.r.owner
    if self.phase=="diving" then
        local elapsed=GetTime()-self.start
        if elapsed<.6 then
            local u=elapsed/.6
            actor.inst.Transform:SetPosition(self.origin.x,self.origin.y+math.sin(u*math.pi)*.6-u*u*u,self.origin.z)
        else
            actor.inst:Hide();actor.speech_hidden=true
            self.r.effects:Burst(self.origin.x,self.origin.y,self.origin.z,false)
            self.phase="hidden"
        end
    elseif self.phase=="hidden" and GetTime()-self.start>=.95 then
        local x,y,z=p.Transform:GetWorldPosition()
        self.r.effects:Burst(x,y,z,false)
        p.AnimState:OverrideMultColour(0,0,0,.5)
        p.AnimState:UsePointFiltering(true)
        actor.possessed=true;self.phase="active"
        if self.task then self.jobs:Set(self.task);self:Speak("enter",{task=self.task.label}) end
    end
    return true
end
function Takeover:Stop(message,silent)
    if self.task and self.task.kind=="arena" then
        print("[ShadowSelf][arena_stop] reason="..tostring(message or "manual_or_unspecified"))
    end
    if self.r.speech then self.r.speech:ClearPin() end
    self:EndBattle()
    local acted=self.phase~=nil
    self.await_dish=nil;self.pending=nil;self.task=nil;self.phase=nil;self.job_started=nil
    self.jobs:Cancel()
    self.combat:Stop()
    local p=self.r.owner;local actor=self.r.actor
    if acted and p:IsValid() then
        Actions.Stop(p)
        p.AnimState:OverrideMultColour(1,1,1,1)
        p.AnimState:UsePointFiltering(false)
        if actor then
            actor.possessed=false;actor.speech_hidden=false
            local x,y,z=p.Transform:GetWorldPosition()
            actor.inst.Transform:SetPosition(x+3,y,z);actor.inst:Show()
            actor:SetRate(1);actor:SetState("idle",0,true)
            if not silent then self.r.effects:Burst(x+3,y,z,false) end
        end
    end
    if message and not silent then self:Say(message) end
end
return Takeover
