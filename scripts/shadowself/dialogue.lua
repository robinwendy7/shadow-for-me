local Pools = {}
for category,lines in pairs(require("shadowself/data/dialogue")) do Pools[category]=lines end
for category,lines in pairs(require("shadowself/data/chat")) do Pools[category]=lines end
for category,lines in pairs(require("shadowself/data/daily").pools) do Pools[category]=lines end
local Personality=require("shadowself/personality")
local Config = require("shadowself/config")
local Thought=require("shadowself/thought")
local Questions=require("shadowself/questions")
local Matcher = require("shadowself/matcher")
local Dialogue = Class(function(self, runtime)
    self.runtime=runtime; self.last={}; self.used={}; self.previous={}; self.next=0
    self.personality=Personality.Get(runtime.options.personality).code;self.thought=Thought(runtime)
end)
function Dialogue:GetPersonality() return Personality.Get(self.personality) end
function Dialogue:SetPersonality(code,announce)
    if not Personality.Valid(code) then return false end
    self.personality=code;self.personality_chosen=true;self.previous={}
    self.runtime.memory.personality=code
    self.runtime.memory.personality_config=self.runtime.options.personality or "original"
    if self.runtime.Save then self.runtime:Save() end
    if announce~=false then
        local p=self:GetPersonality()
        self:Say("personality",100,"已选择 "..(p.code=="original" and p.name or p.code.." · "..p.name).."。"..p.description,true)
    end
    return true
end
function Dialogue:Category(event, c)
    if event=="victory" then return "encourage" end
    if c.night and c.low_sanity and c.spider then return "nightmare" end
    if event=="idle" then
        if self.runtime.memory.died_today then return "comfort" end
        if not self.runtime.memory.ate_today then return "hunger" end
    end
    return event
end
function Dialogue:Say(category, priority, fixed, manual)
    local now=GetTime()
    if not manual and not fixed and (self.runtime.quiet or now<self.next or now-(self.last[category] or -1000)<Config.category_cooldown) then return false end
    local text=fixed
    if not text then
        local fallback=Pools[category] or Pools.default
        local pool=Personality.Pool(self.personality,category,fallback,self.used,now,Config.repeat_cooldown)
        local decision=self.thought:Choose(category,pool,manual,self.current_input,self.personality,self.used)
        if decision.action=="silence" then
            self.last[category]=now;self.next=now+20;self.runtime.memory.last_speech=now;return true
        end
        text=decision.reply;self.previous[category]=text
    end
    if not text or text=="" then return false end
    for _,tail in ipairs({"不用着急回答我。","不用急着回答我。","不用马上回答我。","不用马上给我答案。","我会陪你听完。","我会听完。","我在听。","你听见就好。","慢一点也没关系。","我会在旁边。"}) do
        if text:sub(-#tail)==tail and #text>#tail then text=text:sub(1,-#tail-1) end
    end
    local u=self.used[text] or {count=0}
    u.count=u.count+1; u.time=now; self.used[text]=u
    self.last[category]=now; self.next=now+(manual and 1.5 or (self.runtime.options.frequency or 25)*self:GetPersonality().frequency)
    self.runtime.memory.last_speech=now
    if self.runtime.panel then self.runtime.panel:AddLine("影子",text) end
    if self.runtime.speech then self.runtime.speech:Say(text) end
    return true
end
function Dialogue:Input(text)
    if self.reply_task then self.reply_task:Cancel();self.reply_task=nil end
    local selected=Personality.Selection(text)
    if selected then self:SetPersonality(selected);return end
    if text=="查看人格" or text=="你是什么人格" or text=="人格介绍" then
        local p=self:GetPersonality()
        self:Say("personality",100,(p.code=="original" and p.name or p.code.." · "..p.name).."："..p.description,true)
        return
    end
    local answer,qid=Questions.Match(text,self.runtime,self.thought)
    if answer then
        local parse=self.thought:Parse(text,qid)
        local function respond()
            if not self.runtime.destroyed then self:Say(qid,50,answer,true);self.thought:Remember(parse,answer) end
        end
        local mood=self.thought:Snapshot().mood
        if qid=="there" and (mood=="sad" or mood=="quiet") and self.runtime.owner and self.runtime.owner.DoTaskInTime then
            self.reply_task=self.runtime.owner:DoTaskInTime(1.5+math.random()*1.5,function() self.reply_task=nil;respond() end)
        else respond() end
        self.runtime.memory.last_user_speech=GetTime();return
    end
    local fact,fact_id=require("shadowself/knowledge").Match(text,self.runtime)
    if fact then
        self:Say(fact_id,55,fact,true)
        local parse=self.thought:Parse(text,fact_id);self.thought:Remember(parse,fact)
        self.runtime.memory.last_user_speech=GetTime();return
    end
    if self.runtime.control and self.runtime.control:HandleText(text) then return end
    local category,hits,match=Matcher.Match(text,self.last_intent)
    local fixed=nil
    if category=="wait" then self.runtime.wait=true
    elseif category=="follow" then self.runtime.wait=false
    elseif category=="quiet" then self.runtime.quiet=true
    elseif category=="speak" then self.runtime.quiet=false end
    local r=self.runtime
    if match and match.id=="dislike" then
        fixed="你可以不喜欢我，也可以直说哪里让你不舒服。我会给你留点空隙。"
    elseif category=="why_stop" then
        fixed=r.wait and "是你让我等，我就留在这里了。想继续走，可以叫我跟上。" or "我没有停掉跟随。距离还近的时候，我会自己看看四周；你走远了，我再跟上。"
    elseif category=="memory" then
        local recent=r.memory.recent or {}
        local names={death="你倒下了",revive="你重新站起来了",amulet="你用了重生护符",hurt="你受伤了",eat="你吃了东西",attack="你在战斗",chop="你在砍树",mine="你在挖矿",cave="你进入了洞穴"}
        for i=#recent,1,-1 do
            if names[recent[i].kind] then fixed="我记得刚才"..names[recent[i].kind].."。你想聊这一段吗？";break end
        end
        fixed=fixed or (r.memory.died_today and "我记得今天你倒下过。回来以后，别急着再冒险。" or "今天的细节我只记得一部分。你想提醒我哪一段？")
    elseif category=="absent" and not r.dead and not r.memory.died_today then
        fixed="我还在附近。你继续往前走时，我会看着距离跟上；暂时看不见，也可以在这里叫我。"
    elseif match and match.id=="followup" then
        local explanations={
            self_death="因为死掉已经够难受了，再把它当成自己没用的证据，只会更疼。先把复活的路找好。",
            death_absent="你死亡后，我会以灵魂跟着你。复活作祟时才会暂时隐去，再出现抱起你。你说那时需要我，我听见了。",
            absent="死亡后我会以灵魂跟着你；复活作祟时会暂时隐去。平时我也会自己走走，距离远了再跟上。",
            tired="因为休息不是浪费时间。一直硬撑，连原本会做的事也会变难。",
            self_doubt="因为你把一件没做好的事，变成了对整个人的判决。这对你不公平。",
            work="工作里的事可以一件件拆开处理，不必把压力都留给自己扛。最难的是哪一件？",
            study="累和不会是两件事。先弄清是哪一种，才知道该休息还是换个办法。",
            comfort="因为难过的时候，人很容易只看见最糟的一面。我想先陪你缓一会儿。",
            plans="吃的、光和退路最先关系到能不能活下来；有了余地，才好决定更远的事。",
            relationship="因为操作是你的，所以接管前一定得先听见你同意。说停以后，我就还给你。",
            praise="因为有些话，我听见一次，就会在心里放很久。",
            hunger="因为先照顾自己，比硬撑着赶路更划算。",
        }
        fixed=explanations[category]
    end
    if category=="default" and self.last_intent and self.last_intent~="default" then
        local bridges={
            daily="这还是你刚才说的那件事吗？可以接着讲后来发生了什么。",
            work="听起来还在说工作的事。让你最烦的是事情本身，还是别人对你的态度？",
            study="是刚才学习上卡住的那一段吗？你可以把具体的难处说出来。",
            friends="你是在说刚才那个人吗？当时你是什么感受？",
            self_death="你是在想刚才怎么死的，还是想知道接下来怎么回来？",
            death_absent="你还在说刚才我消失的事，对吗？你需要的不是一句没关系，而是我接住你。",
        }
        fixed=bridges[self.last_intent]
    end
    local parse=self.thought:Parse(text,category)
    local function respond()
        if r.destroyed then return end
        self.current_input=parse;self:Say(category,50,fixed,true);self.current_input=nil
        local decision=self.thought.last
        self.thought:Remember(parse,fixed or decision and decision.action=="say" and decision.reply or nil)
    end
    local snapshot=self.thought:Snapshot()
    if category=="presence" and (snapshot.mood=="sad" or snapshot.mood=="quiet") and r.owner and r.owner.DoTaskInTime then
        self.reply_task=r.owner:DoTaskInTime(1.5+math.random()*1.5,function() self.reply_task=nil;respond() end)
    else respond() end
    self.last_intent=category~="default" and category or self.last_intent
    self.last_user_text=text
    r.memory.last_user_speech=GetTime()
end
return Dialogue
