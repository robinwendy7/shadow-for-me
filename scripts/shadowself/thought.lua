-- 本地评估器：输入结构 -> 快照 -> 时效记忆/情绪 -> 候选评分 -> 表达。
-- 不把规则评估称作语言模型理解；保留选句依据供后续对话追问。
local Thought=Class(function(self,r)
    self.r=r;r.memory.social=r.memory.social or {interactions=0,history={},emotions={},valence=0,energy=1}
    self.m=r.memory.social;self.m.history=self.m.history or {};self.m.emotions=self.m.emotions or {}
end)
function Thought:Bind()
    self.r.memory.social=self.r.memory.social or {interactions=0,history={},emotions={},valence=0}
    self.m=self.r.memory.social;self.m.history=self.m.history or {};self.m.emotions=self.m.emotions or {}
    self.m.updated=GetTime()
    for _,entry in pairs(self.m.emotions) do entry.time=GetTime()-120 end
    for _,entry in ipairs(self.m.history) do entry.time=GetTime()-120 end
end
local feelings={lonely="lonely",fear="fear",angry="angry",tired="tired",comfort="sad",self_doubt="sad",hunger="hunger"}
local function read(p,key)
    local replica=p and p.replica and p.replica[key]
    return replica and replica.GetPercent and replica:GetPercent() or nil
end
function Thought:Snapshot()
    local r=self.r;local c=r.context or {};local p=r.owner;local w=TheWorld and TheWorld.state or {}
    local now=GetTime();local elapsed=math.max(0,now-(self.m.updated or now))
    self.m.valence=(self.m.valence or 0)*math.exp(-elapsed/480);self.m.updated=now
    local day=w.cycles or 0;local absent=self.m.last_day and day-self.m.last_day or 0
    local valence=self.m.valence
    local mood=valence<-.55 and "sad" or valence<-.15 and "worried" or valence>.25 and "bright" or absent>=3 and "quiet" or "calm"
    return {time=now,day=day,phase=w.phase or c.phase,season=w.season or c.season,rain=w.israining or c.rain,
        cave=c.cave,health=read(p,"health") or c.health,hunger=read(p,"hunger") or c.hunger,
        sanity=read(p,"sanity") or c.sanity,danger=c.danger or 0,recent=r.memory.recent or {},
        since_eat=r.memory.last_eat and math.max(0,now-r.memory.last_eat),mood=mood,
        relation=math.min(1,math.sqrt(self.m.interactions or 0)/20),previous=self.m.history[#self.m.history],died_today=r.memory.died_today,ate_today=r.memory.ate_today}
end
function Thought:Parse(text,category)
    local joke=false
    for _,word in ipairs({"哈哈","开玩笑","逗你","嘴馋","只是想吃"}) do if text:find(word,1,true) then joke=true end end
    if text:find("不是开玩笑",1,true) or text:find("没开玩笑",1,true) then joke=false end
    local intensity=.5
    for _,word in ipairs({"好孤独","特别","很怕","超级","受不了","一直","真的好"}) do if text:find(word,1,true) then intensity=1 end end
    local question=text:find("?",1,true) or text:find("？",1,true) or text:find("吗",1,true) or text:find("什么",1,true) or text:find("为什么",1,true)
    local help=text:find("救",1,true) or text:find("帮",1,true)
    return {text=text,category=category,intent=question and "question" or feelings[category] and "emotion" or "conversation",
        emotion=feelings[category] or "neutral",intensity=intensity,help=help~=nil,joking=joke,question=question~=nil}
end
function Thought:Observe(kind)
    local delta={hurt=-.18,death=-.7,revive=.3,amulet=.3,victory=.6,eat=.08}
    if delta[kind] then self:Snapshot();self.m.valence=math.max(-1,math.min(1,(self.m.valence or 0)+delta[kind])) end
end
function Thought:Remember(parse,reply)
    local m=self.m;m.interactions=(m.interactions or 0)+1;m.last_day=(TheWorld and TheWorld.state and TheWorld.state.cycles) or 0
    m.last_contact=GetTime();m.history[#m.history+1]={input=parse.text,category=parse.category,reply=reply,time=GetTime(),emotion=parse.emotion}
    while #m.history>12 do table.remove(m.history,1) end
    if parse.emotion~="neutral" then m.emotions[parse.emotion]={time=GetTime(),reply=reply,intensity=parse.intensity} end
end
function Thought:Choose(category,pool,manual,parse,personality,used)
    local s=self:Snapshot();parse=parse or {category=category,intent="event",emotion="neutral",intensity=.5}
    local list={};local profile=require("shadowself/data/personalities")[personality]
    local own={};if profile then for _,lines in pairs(profile.pools) do for _,line in ipairs(lines) do own[line]=true end end end
    for _,text in ipairs(pool) do list[#list+1]={text=text,topic=category,tone="calm",fit=.55,personality=own[text] and 1 or .35} end
    local function add(text,fit,tone) list[#list+1]={text=text,topic=category,fit=fit,tone=tone or "calm",personality=1} end
    if category=="hunger" then
        if s.hunger and s.hunger>.65 and s.since_eat and s.since_eat<90 then
            local playful=personality=="ENTP" or personality=="ENFP" or personality=="ESFP" or personality=="ESTP"
            add(parse.joking and (playful and "刚吃完又饿了？锅都没喘过气。" or "刚吃过就来逗我。还想吃什么？") or "你刚吃过，饱食也不低。是真没吃够，还是嘴馋？",1,"bright")
            for _,v in ipairs(list) do if v.fit==.55 then v.fit=.1 end end
        elseif s.hunger and s.hunger<.25 then
            add("你现在确实快饿空了。先找吃的，别继续赶路。",1,"worried")
        elseif parse.joking then add("这句像在逗我。想吃东西，还是想找我说句话？",.95,"bright") end
    end
    if (category=="comfort" or category=="self_doubt") and s.died_today then
        add("你今天已经倒下过一次。先别把失手都算在自己身上，找回东西以后再说。",.95,"sad")
    end
    if category=="tired" and s.phase=="night" then add("天已经黑了。找个有光的地方歇一会儿，路留到明天。",.95,"calm") end
    if category=="cold" and s.rain then add("衣服淋湿了，光赶路暖不回来。先找火，把身上烘干。",1,"worried") end
    if category=="fear" and s.sanity and s.sanity<.25 and s.phase=="night" then add("天黑，脑袋又在吵。先把光拿稳，别追着那些影子看。",1,"worried") end
    if category=="angry" and s.danger>0 then add("先躲开眼前的东西。生气归生气，别把自己也搭进去。",1,"worried") end
    if category=="fear" and s.danger>0 then add("先把眼前这波躲开。现在不是逞强的时候。",1,"worried") end
    if category=="lonely" and self.m.emotions.lonely and GetTime()-self.m.emotions.lonely.time>60 and s.relation>.1 then
        add("你上次也提起过孤独。这段时间，是同一件事还压着你吗？",.95,"sad")
    end
    local best,score,rank
    for _,v in ipairs(list) do
        local history=used[v.text];local age=history and math.max(0,s.time-history.time) or 10000
        local novelty=history and (1-math.exp(-age/240))/(1+history.count*.15) or 1
        local mood=(v.tone==s.mood or v.tone=="calm") and .8 or .35
        if v.tone=="worried" and (s.danger>0 or category=="hunger" and s.hunger and s.hunger<.25) then mood=1 end
        local keyword=v.topic==parse.category and 1 or .4
        local value=.30*keyword+.25*v.fit+.20*mood+.15*novelty+.10*v.personality+(math.random()-.5)*.035
        if history and age<8 then value=value-.4 end
        if not score or value>score then best,score,rank=v,value,{keyword=keyword,context=v.fit,mood=mood,memory=novelty,personality=v.personality} end
    end
    local silence=(category=="idle" or category=="default") and (s.mood=="quiet" or s.mood=="sad")
        and (not manual or not parse.question and not parse.help and math.random()<.35)
    self.last={parse=parse,snapshot=s,score=score,factors=rank,reply=best and best.text,action=silence and "silence" or "say"}
    return self.last
end
return Thought
