local rules=require("shadowself/data/questions")
local Q={}
function Q.Match(text,r,brain)
    text=text:lower();local best,length
    for _,rule in ipairs(rules) do for _,phrase in ipairs(rule.phrases) do
        if text:find(phrase,1,true) and (not length or #phrase>length) then best=rule;length=#phrase end
    end end
    if not best then return end
    local answer=best.answer;local w=TheWorld and TheWorld.state or {}
    if answer=="@weekday" then
        local day=os and os.date and tonumber(os.date("%w"))
        answer=day and "今天星期"..({[0]="日","一","二","三","四","五","六"})[day].."。按你的电脑日期。" or "我现在读不到本机日期。"
    elseif answer=="@date" then answer=os and os.date and ("今天是"..os.date("%Y年%m月%d日").."。") or "我现在读不到本机日期。"
    elseif answer=="@weather" then answer=w.israining and "正在下雨。装备和火种留意一下。" or "现在没有下雨。"
    elseif answer=="@season" then answer="现在是"..(({autumn="秋天",winter="冬天",spring="春天",summer="夏天"})[w.season] or "暂时读不到的季节").."。"
    elseif answer=="@reason" then
        local last=brain.last
        answer=last and last.snapshot.since_eat and last.snapshot.since_eat<90 and "刚才你才吃过，饱食也不低，所以我没把那句直接当成缺食物。" or "我参考了你这句话、眼前的状态、刚发生的事和最近说过的内容。不是每次都用同一条回应。"
    end
    return answer,best.id
end
return Q
