local D = require("shadowself/data/keywords")
local Conversation = require("shadowself/data/conversation")
local M = {}
local rules={}
for _,rule in ipairs(Conversation.rules) do rules[#rules+1]=rule end
for _,rule in ipairs(require("shadowself/data/daily").rules) do rules[#rules+1]=rule end
local replacements={{"为啥","为什么"},{"咋不","怎么不"},{"干啥","干什么"},{"咋样","怎么样"},{"整不会","没搞懂"},{"听不明白","没听懂"},{"没太懂","没听懂"},{"肿么","怎么"},{"咋办","怎么办"},{"咋回事","怎么回事"},{"蟹蟹","谢谢"},{"栓q","谢谢"},{"栓Q","谢谢"},{"稀饭你","喜欢你"},{"好稀饭","好喜欢"},{"木有","没有"},{"有木有","有没有"},{"肿么了","怎么了"},{"咋啦","怎么了"},{"桑心","伤心"},{"伐开心","不开心"},{"累鼠了","累死了"},{"饿鼠了","饿死了"},{"困鼠了","困死了"},{"破防了","绷不住"},{"emo了","心情不好"},{"开森","开心"},{"烦鼠了","烦死了"}}

function M.Match(text, previous)
    text = string.lower(text or "")
    for _,pair in ipairs(replacements) do text=text:gsub(pair[1],pair[2]) end
    local rawtext=text
    -- 先移除完整否定短语；避免“不害怕”里的“怕”抢先命中。
    local phrases={}
    for _,key in ipairs({"fear","hunger","tired","lonely","angry","cold","calm"}) do
        for _,word in ipairs(D.synonyms[key]) do
            for _,neg in ipairs(D.negations) do phrases[#phrases+1]=neg..word end
        end
    end
    table.sort(phrases,function(a,b) return #a>#b end)
    for _,phrase in ipairs(phrases) do
        local start=1
        while true do
            local a,b=string.find(text,phrase,start,true)
            if not a then break end
            text=string.sub(text,1,a-1).." "..string.sub(text,b+1)
            start=a+1
        end
    end
    local hits = {}
    for key, aliases in pairs(D.synonyms) do
        for _,word in ipairs(aliases) do
            local start = 1
            while true do
                local a,b = string.find(text,word,start,true)
                if not a then break end
                local prefix = string.sub(text,math.max(1,a-15),a-1)
                local blocked = false
                for _,neg in ipairs(D.negations) do
                    if string.sub(prefix,-#neg)==neg then blocked=true; break end
                end
                if not blocked then hits[key]=true; break end
                start=b+1
            end
            if hits[key] then break end
        end
    end
    local best, score = "default", -1
    for _,rule in ipairs(D.rules) do
        local count=0
        for _,key in ipairs(rule.keys) do if hits[key] then count=count+1 end end
        if count >= (rule.minimum or #rule.keys) then
            local s=count*100+(rule.priority or 0)
            if s>score then best,score=rule.category,s end
        end
    end
    score=score/3
    local matched_id=best
    local daily_gate
    for _,rule in ipairs(rules) do
        if rule.daily and daily_gate==nil then daily_gate=best=="default" end
        local longest=0
        for _,phrase in ipairs(rule.phrases) do
            if string.find(rawtext,phrase,1,true) then longest=math.max(longest,#phrase) end
        end
        local groups=0
        if rule.groups then
            for _,alternatives in ipairs(rule.groups) do
                local found=false
                for _,phrase in ipairs(alternatives) do
                    if string.find(rawtext,phrase,1,true) then found=true; break end
                end
                if found then groups=groups+1 end
            end
        end
        local eligible=rule.groups and groups==#rule.groups or not rule.groups and longest>0
        if rule.daily and not daily_gate then eligible=false end
        if eligible and rule.exclude then
            for _,phrase in ipairs(rule.exclude) do
                if string.find(rawtext,phrase,1,true) then eligible=false; break end
            end
        end
        local value=(rule.priority or 0)+math.min(longest,90)/3+groups*10
        if eligible and value>score then best,score,matched_id=rule.category,value,rule.id end
    end
    local followup=false
    if #text<=36 then
        for _,phrase in ipairs(Conversation.followups) do
            if string.find(text,phrase,1,true) then followup=true; break end
        end
    end
    if followup and (best=="why" or best=="default") and previous and previous~="default" and previous~="why" then
        return previous,hits,{id="followup",followup=true,previous=previous}
    end
    return best,hits,{id=matched_id,followup=followup}
end
return M
