local Data=require("shadowself/data/personalities")
local P={order={"INTJ","INTP","ENTJ","ENTP","INFJ","INFP","ENFJ","ENFP","ISTJ","ISFJ","ESTJ","ESFJ","ISTP","ISFP","ESTP","ESFP"}}
local original={code="original",name="原版影子",description="安静，偶尔毒舌，偶尔温柔，在乎你但不总说出来。",frequency=1}
function P.Valid(code) return code=="original" or type(code)=="string" and Data[code]~=nil end
function P.Get(code) return Data[code] or original end
function P.Resolve(memory,configured)
    if configured==nil and P.Valid(memory.personality) then return memory.personality end
    configured=P.Valid(configured) and configured or "original"
    if memory.personality_config==configured and P.Valid(memory.personality) then return memory.personality end
    return configured
end
local groups={greeting="greeting",bye="bye",comfort="comfort",self_doubt="comfort",sorry="comfort",
    fear="fear",you_fear="fear",tired="tired",quit="tired",lonely="lonely",miss_you="lonely",
    angry="angry",complaint="angry",hunger="hunger",plans="plans",work="plans",study="plans",
    lost="plans",joke="joke",tease="joke",playful="joke",identity="identity",default="default",
    daily="default",idle="default",encourage="encourage",death="death",self_death="death"}
-- 定制台词用完短期回到原类别池，避免两句之间机械来回；已有事实/功能台词不改写。
function P.Pool(code,category,fallback,used,now,repeat_time)
    local profile=Data[code];local group=groups[category]
    local lines=profile and group and profile.pools[group]
    if not lines then return fallback end
    for _,line in ipairs(lines) do
        local item=used and used[line]
        if not item or now-item.time>=repeat_time then return lines end
    end
    return fallback
end
function P.Selection(text)
    local s=(text or ""):gsub("%s+",""):upper()
    if Data[s] then return s end
    if s=="原版影子" or s=="恢复原版人格" or s=="原版人格" then return "original" end
    for _,prefix in ipairs({"我的人格是","我的MBTI是","切换人格为","切换人格","选择人格","人格设为","改成人格","人格","我是"}) do
        if s:sub(1,#prefix)==prefix then
            local rest=s:sub(#prefix+1)
            for _,suffix in ipairs({"型人格","人格","型"}) do
                if rest:sub(-#suffix)==suffix then rest=rest:sub(1,-#suffix-1);break end
            end
            if Data[rest] then return rest end
        end
    end
end
return P
