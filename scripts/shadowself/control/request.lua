local M={}
local function trim(s)
    s=(s or ""):gsub("^%s+",""):gsub("%s+$","")
    for _,p in ipairs({"。","！","!","，",",","？","?"}) do
        while s:sub(-#p)==p do s=s:sub(1,-#p-1) end
    end
    return s
end
local stops={"停","停下","停一下","停止","等等","等一下","别动","不要动","先停","暂停","暂停接管","停止接管","取消","取消接管","还给我","我自己来","让我来","别接管","不用帮了","不要接管"}
function M.IsStop(text)
    text=trim(text)
    for _,s in ipairs({"别停","不要停","不用停"}) do if text:sub(1,#s)==s then return false end end
    for _,s in ipairs(stops) do
        if text==s or text==s.."吧" or text==s.."啊" or text=="影子"..s then return true end
    end
    for _,s in ipairs({"停止接管","取消接管","暂停接管","停止自动战斗","停止走位","把操作还给我","把控制还给我"}) do
        if text:find(s,1,true) then return true end
    end
    for _,s in ipairs({"停一下","停下","先停","等一下","等等","停止","暂停","取消","我自己来","还给我"}) do
        if text:sub(1,#s)==s then return true end
    end
    return false
end
function M.IsYes(text)
    text=trim(text)
    for _,s in ipairs({"同意接管","允许接管","确认接管","同意","允许","好","好的","可以","接管吧","你来吧","交给你","确认"}) do
        if text==s then return true end
    end
    return false
end
local function BasicParse(text)
    local s=trim(text)
    local at=s:find("帮我",1,true) or s:find("替我",1,true)
    if not at then return nil end
    local prefix=s:sub(1,at-1)
    for _,neg in ipairs({"不要","不需要","不用","不许","不","别"}) do
        if prefix:sub(-#neg)==neg then return nil,"好，我不会接管这件事。" end
    end
    s=trim(s:sub(at+#"帮我"))
    if s:sub(1,#"不要")=="不要" or s:sub(1,#"别")=="别" then return nil,"你是在让我别做这件事，我不会接管。" end
    local verbs={
        {"自动走位","dodge","自动走位"},{"自动躲避","dodge","自动走位"},
        {"自动战斗","fight","自动战斗"},{"打怪","fight","打怪"},{"战斗","fight","战斗"},
        {"走A","fight","走A"},{"走a","fight","走A"},{"攻击","fight","攻击"},{"打","fight","攻击"},
        {"砍树","chop","砍树"},{"砍","chop","砍树"},
        {"挖矿","mine","挖矿"},{"采矿","mine","挖矿"},{"敲矿","mine","挖矿"},
        {"拾取","pickup","拾取"},{"捡起","pickup","拾取"},{"捡","pickup","拾取"},
        {"采摘","pick","采摘"},{"收获","pick","收获"},{"采集","pick","采集"},
        {"挖掉","dig","挖掘"},{"挖","dig","挖掘"},
        {"拆掉","hammer","拆除"},{"敲掉","hammer","拆除"},
        {"制作","craft","制作"},{"做","craft","制作"},
        {"装备","equip","装备"},{"穿上","equip","装备"},{"吃","eat","进食"},
        {"走到","goto","前往"},{"去","goto","前往"},
    }
    for _,v in ipairs(verbs) do
        if s:sub(1,#v[1])==v[1] then
            local name=trim(s:sub(#v[1]+1))
            local all=name:find("所有",1,true) or name:find("全部",1,true)
            for _,suffix in ipairs({"吗","吧","啊","呀","呢"}) do if name:sub(-#suffix)==suffix then name=trim(name:sub(1,-#suffix-1)) end end
            for _,filler in ipairs({"附近的","附近","地上的","脚下的","所有的","所有","全部的","全部","一点","一些","一下","点"}) do
                if name:sub(1,#filler)==filler then name=trim(name:sub(#filler+1)) end
            end
            if name=="一下" or name=="一会" or name=="一会儿" then name="" end
            local counted=name:match("^%d+")~=nil
            for _,unit in ipairs({"个","棵","只","份","次","件","组"}) do if name:find("%d+"..unit) then counted=true end end
            if counted and v[2]~="goto" then return nil,"这版先按附近目标连续处理，不支持精确数量。可以说“帮我砍树”或“帮我捡木头”。" end
            if (v[2]=="craft" or v[2]=="equip" or v[2]=="eat" or v[2]=="goto" or v[2]=="dig" or v[2]=="hammer") and name=="" then
                return nil,"想让我"..v[3].."什么？请把目标也说出来。"
            end
            local kind=v[2]
            if kind=="dig" and (name=="石头" or name=="矿石" or name=="矿" or name=="岩石") then kind="mine" end
            return {kind=kind,target=name,all=all~=nil,label=v[3]..(name~="" and "："..name or ""),text=text}
        end
    end
    return nil,"这件事我还不会接管。现在支持砍树、挖矿、捡取、采摘、挖掘、拆除、制作、装备、进食、前往可见目标，以及自动战斗和走位。"
end
-- 旧基础行为保留；新增 zom 的多步、数量及更多交互。
function M.Parse(text)
    local fish=(text:find("钓鱼",1,true) or text:find("海钓",1,true) or text:find("钓海鱼",1,true) or text:find("池塘钓",1,true))
    local fishing_command=text:find("帮我",1,true) or text:find("替我",1,true) or text:match("^海钓") or text:match("^钓鱼") or text:match("^去钓") or text:match("^自动钓")
    if fish and fishing_command and not (text:find("不要",1,true) or text:find("别",1,true) or text:find("不会",1,true) or text:find("会不会",1,true)) then
        local sea=text:find("海",1,true)~=nil
        return {kind="fish",mode=sea and "sea" or "pond",label=sea and "海钓" or "池塘钓鱼",text=text}
    end
    local basic,why=BasicParse(text)
    local command=text:match("^/ai%s+(.+)$")
    if command then
        local verb=command:match("^(%S+)")
        local allowed={collect=true,build=true,action=true,store=true,take=true,base=true,["goto"]=true}
        if allowed[verb] then return {kind="autonomy",command=command,label="执行 "..command,text=text} end
        return nil,"高级任务支持 collect/build/action/store/take/base/goto；停止仍用停止按钮或说停。"
    end
    local at=text:find("帮我",1,true) or text:find("替我",1,true)
    if not at then return basic,why end
    local prefix=text:sub(1,at-1)
    for _,neg in ipairs({"不要","不用","别","不需要","不许","不"}) do if prefix:sub(-#neg)==neg then return basic,why end end
    local body=trim(text:sub(at+#"帮我"))
    if body:sub(1,#"不要")=="不要" or body:sub(1,#"别")=="别" then return basic,why end
    if body=="自主托管" or body=="生存" or body=="照顾自己" or body=="自动生存" then return {kind="autonomy",label="自主生存",text=text} end
    local compound=body:find("然后",1,true) or body:find("接着",1,true) or body:find("之后",1,true)
    local counted=body:find("%d") and not (basic and basic.kind=="goto")
    for _,number in ipairs({"一","二","两","三","四","五","六","七","八","九","十"}) do
        for _,unit in ipairs({"个","件","把","份","只","次","块","颗"}) do
            if body:find(number..unit,1,true) then counted=true end
        end
    end
    if basic and not compound and not counted then return basic end
    local parser=require("shadowself/zom/CommandParser")
    local steps=parser.ParseCommand(body)
    local allowed={pickup=true,drop=true,equip=true,unequip=true,eat=true,use=true,craft=true,
        chop=true,mine=true,harvest=true,hammer=true,dig=true,use_on=true,place=true,interact=true,
        sit=true,find=true,["goto"]=true,retreat=true,pickup_nearby=true,jump_wormhole=true}
    if steps and #steps==1 and (steps[1].kind=="wanda_revive" or steps[1].kind=="sector_watch" or steps[1].kind=="pig_coin_search") then
        return {kind="adventure",step=steps[1],label=body,text=text}
    end
    if steps and #steps>0 then
        for _,step in ipairs(steps) do
            if not allowed[step.kind] then return nil,why or "这个组合中的步骤暂时不能执行："..tostring(step.kind) end
        end
        return {kind="queue",steps=steps,label=body,text=text}
    end
    return basic,why
end
return M

