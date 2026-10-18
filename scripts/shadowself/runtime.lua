local Actor=require("shadowself/actor")
local Sensor=require("shadowself/sensor")
local Dialogue=require("shadowself/dialogue")
local Context=require("shadowself/context")
local C=require("shadowself/config")
local Effects=require("shadowself/effects")
local Takeover=require("shadowself/takeover")
local Runtime=Class(function(self,owner,options)
    self.owner=owner; self.options=options; self.queue={}; self.events={}; self.context={}
    self.memory={day=-1,tiles={},last_speech=GetTime(),died_today=false,ate_today=false}
    self.storage="shadowself_v1_"..tostring(owner.userid or "local")
    self.dialogue=Dialogue(self); self.sensor=Sensor(self)
    self.effects=Effects()
    self.voice=require("shadowself/voice")(self)
    self.control=Takeover(self)
    self.concern=require("shadowself/concern")(self)
    self.dead=owner:HasTag("playerghost")
end)
function Runtime:Emit(kind,priority,fixed)
    if self.destroyed then return end
    local now=GetTime()
    if now<(self.events[kind] or 0) then return end
    self.events[kind]=now+((priority or C.priorities[kind] or 20)>=85 and 2 or 12)
    priority=priority or C.priorities[kind] or 20
    if self.dialogue.thought then self.dialogue.thought:Observe(kind) end
    if kind=="eat" then self.memory.last_eat=now end
    self.memory.recent=self.memory.recent or {}
    table.insert(self.memory.recent,{kind=kind,time=now})
    if #self.memory.recent>10 then table.remove(self.memory.recent,1) end
    if kind=="hurt" or kind=="attack" or kind=="boss" then self.combat_until=now+8 end
    if self.control.battle_active and kind~="death" and kind~="revive" and kind~="amulet" then return end
    if kind=="hurt" and self.control.pending and self.control.pending.plan and self.control.pending.plan.defensive then return end
    local posture=C.postures[kind]
    if self.actor and posture then self.actor:SetState(posture,priority>=80 and 3 or 1,priority>=80) end
    if priority>=85 or fixed then
        self.dialogue:Say(kind,priority,fixed or nil,false)
        -- 危险事件打断普通台词的全局冷却，但仍受同类去抖约束。
        if not fixed and self.dialogue.last[kind]~=now and not self.quiet then
            self.dialogue.next=0; self.dialogue.last[kind]=nil; self.dialogue:Say(kind,priority)
        end
        return
    end
    for _,e in ipairs(self.queue) do if e.kind==kind then return end end
    local bonus=Context.Score(self.context,self.memory)
    table.insert(self.queue,{kind=kind,priority=priority+bonus*.05,time=now})
    table.sort(self.queue,function(a,b) if a.priority==b.priority then return a.time<b.time end return a.priority>b.priority end)
    if #self.queue>C.queue_limit then table.remove(self.queue) end
end
function Runtime:Save()
    if not self.loaded then return end
    local m=self.memory
    local copy={day=m.day,tiles=m.tiles,died_today=m.died_today,ate_today=m.ate_today,
        first_death=m.first_death,first_revive=m.first_revive,first_cave=m.first_cave,
        first_boss=m.first_boss,first_starve=m.first_starve,
        personality=m.personality,personality_config=m.personality_config,social=m.social}
    TheSim:SetPersistentString(self.storage,json.encode(copy),false)
end
function Runtime:Start()
    self.owner:ListenForEvent("onremove",function() self:Destroy() end)
    TheSim:GetPersistentString(self.storage,function(success,data)
        if self.destroyed then return end
        if success and data and data~="" then
            local ok,m=pcall(json.decode,data)
            if ok and type(m)=="table" then
                for k,v in pairs(m) do self.memory[k]=v end
                self.memory.tiles=self.memory.tiles or {}
            end
        end
        local Personality=require("shadowself/personality")
        if not self.dialogue.personality_chosen then
            self.dialogue.personality=Personality.Resolve(self.memory,self.options.personality)
        end
        self.memory.personality=self.dialogue.personality
        self.memory.personality_config=self.options.personality or "original"
        if self.dialogue.thought then self.dialogue.thought:Bind() end
        self.loaded=true
        self.sensor:Sample()
        self.actor=Actor(self.owner)
        local handoff=require("shadowself/handoff")
        if handoff.plan and handoff.userid==self.owner.userid and GetTime()-(handoff.time or 0)<10 then
            self.memory=handoff.memory or self.memory
            self.control.pending={plan=handoff.plan,until_time=math.huge}
            handoff.plan=nil;handoff.memory=nil
            self.control:HandleText("同意接管")
        else self:Emit("greeting") end
        self.task=self.owner:DoPeriodicTask(C.tick,function() self:Step(C.tick) end)
        self.savetask=self.owner:DoPeriodicTask(30,function() self:Save() end)
    end)
end
function Runtime:Step(dt)
    if self.destroyed then return end
    if not self.owner:IsValid() or ThePlayer and self.owner~=ThePlayer or self.owner.components and not self.owner.components.playercontroller then
        self:Destroy();return
    end
    local now=GetTime()
    local anim=self.owner.AnimState
    local dead=self.owner:HasTag("playerghost") or self.owner:HasTag("corpse") or anim:IsCurrentAnimation("death")
    self.control:Tick()
    local native=nil
    for _,name in ipairs({"amulet_rebirth","wendy_resurrect","rebirth"}) do
        if anim:IsCurrentAnimation(name) then native=name;break end
    end
    local amulet=native~=nil
    local jumping=anim:IsCurrentAnimation("jump_pre") or anim:IsCurrentAnimation("heavy_jump_pre")
    if jumping and not self.jumping and not self.dead then
        local x,y,z=self.owner.Transform:GetWorldPosition()
        self.actor:BeginCeremony("transition"); self.effects:Burst(x,y,z,false)
    end
    self.jumping=jumping
    if amulet and not self.amulet_active then
        if self.control.phase then self.control:Stop(nil,true) end
        self.amulet_until=now+18
        if self.options.ceremony then self.actor:BeginCeremony("amulet",native) end
        self:Emit(native=="amulet_rebirth" and "amulet" or "revive",100,"亲爱的我，请不要再死了。")
    end
    self.amulet_active=amulet
    self.sensor:ObserveAction()
    if dead and not self.dead and not amulet then
        self.dead=true; self.memory.died_today=true;self.owner._shadowself_combat_buffs=nil
        local x,y,z=self.owner.Transform:GetWorldPosition(); self.deathpos={x=x,y=y,z=z}
        local fixed=not self.memory.first_death and "别急着走。让我再陪你待一会儿。" or nil
        self.memory.first_death=true
        if (self.context.hunger or 1)<=.005 and not self.memory.first_starve then
            self.memory.first_starve=true; fixed="你把最后一口留给了谁？下次，先留给自己。"
        end
        self:Emit("death",100,fixed)
        self.actor:BeginCeremony("death"); self:Save()
    elseif not dead and self.dead then
        self.dead=false
        if now>(self.amulet_until or 0) then
            self.actor:BeginCeremony("revive")
            self:Emit("revive",100,not self.memory.first_revive and "回来了就好。我没有走远。" or nil)
        end
        self.memory.first_revive=true; self:Save()
    end
    if now>(self.nextscan or 0) then
        self.nextscan=now+C.scan; self.sensor:Sample()
    end
    if now>(self.nextappearance or 0) and not self.actor.ceremony then
        self.nextappearance=now+5; self.actor:CopyAppearance()
    end
    if now-self.memory.last_speech>C.idle_talk*self.dialogue:GetPersonality().frequency then self:Emit("idle") end
    for i=#self.queue,1,-1 do if now-self.queue[i].time>C.event_ttl then table.remove(self.queue,i) end end
    if self.control.battle_active then self.queue={} end
    for i,e in ipairs(self.queue) do
        if self.dialogue:Say(self.dialogue:Category(e.kind,self.context),e.priority) then table.remove(self.queue,i); break end
    end
    self.effects:Step()
end
-- 视觉运动从定时逻辑任务分离，使用前端逐帧 dt；面板关闭或最小化仍更新。
function Runtime:Frame(dt)
    -- Keep the live music slider in sync even while the simulation is paused.
    if not self.destroyed and (ThePlayer and ThePlayer~=self.owner or self.owner.components and not self.owner.components.playercontroller) then self:Destroy();return end
    if not self.destroyed and self.control.music then self.control.music:Update() end
    if self.destroyed or not self.loaded or not self.actor then return end
    if IsSimPaused and IsSimPaused() then return end
    if not dt or dt<=0 then return end
    if self.actor.RefreshAppearance then self.actor:RefreshAppearance() end
    if not self.control:Frame(dt) then self.actor:Step(math.min(dt,.1),self) end
end
function Runtime:Destroy()
    if self.destroyed then return end
    local handoff=require("shadowself/handoff")
    if ThePlayer and (ThePlayer~=self.owner or self.owner.components and not self.owner.components.playercontroller) and self.control.phase=="active" and self.control.task
        and self.control.task.kind=="fight" and ThePlayer.userid==self.owner.userid then
        handoff.plan=self.control.task;handoff.userid=self.owner.userid;handoff.time=GetTime();handoff.memory=self.memory
    end
    if handoff.runtime==self then handoff.runtime=nil end
    self:Save(); self.destroyed=true
    if self.dialogue.reply_task then self.dialogue.reply_task:Cancel() end
    if self.task then self.task:Cancel() end
    if self.savetask then self.savetask:Cancel() end
    self.control:Stop(nil,true)
    if self.actor then self.actor:Destroy() end
    if self.speech then self.speech:Kill(); self.speech=nil end
    if self.consent then self.consent:Kill();self.consent=nil end
    if self.combat_button then self.combat_button:Kill();self.combat_button=nil end
    if self.personality_picker then self.personality_picker:Kill();self.personality_picker=nil end
    if self.voice then self.voice:Stop() end
    self.effects:Destroy()
    if self.panel and self.panel.Kill then self.panel:Kill();self.panel=nil end
    self.owner._shadowself=nil
end
return Runtime
