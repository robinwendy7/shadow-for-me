-- 真实人格数据、对话路由、冷却、持久化与选择菜单的离线交互测试。
package.loaded["shadowself/dialogue"]=nil
local P=require("shadowself/personality")
local data=require("shadowself/data/personalities")
local Dialogue=require("shadowself/dialogue")
local now=5000;GetTime=function() return now end
local count,seen=0,{}
for _,code in ipairs(P.order) do
    local p=assert(data[code]);assert(p.code==code and p.frequency>=.7 and p.frequency<=1.5)
    local n=0
    for category,pool in pairs(p.pools) do
        assert(#pool==2,code..category)
        for _,line in ipairs(pool) do assert(not seen[line],"authored lines unique");seen[line]=true;n=n+1 end
    end
    assert(n==28,code);count=count+n
end
assert(count==448 and #P.order==16)
assert(P.Selection("我是 infp")=="INFP" and P.Selection("人格INTJ")=="INTJ")
assert(P.Selection("切换人格ENTP")=="ENTP" and P.Selection("我的人格是ISTJ型人格")=="ISTJ")
assert(P.Selection("恢复原版人格")=="original")
assert(not P.Selection("我朋友是INTJ") and not P.Selection("我不是INTJ") and not P.Selection("INTJ和INFP谁好"))
local saved=0
local r={options={frequency=25,personality="original",opacity=.75,history=200},memory={},loaded=true,
    panel={lines={}},speech={lines={}},control={calls=0}}
function r.panel:AddLine(who,text) self.lines[#self.lines+1]=text end
function r.speech:Say(text) self.lines[#self.lines+1]=text end
function r:Save() saved=saved+1 end
function r:Frame() end
function r.control:HandleText(text) self.calls=self.calls+1;return text=="停" end
local d=Dialogue(r);r.dialogue=d
local example={}
for _,code in ipairs(P.order) do
    d:Input("人格"..code);assert(d.personality==code and r.memory.personality==code)
    local calls=r.control.calls
    d:Input("我累了")
    local text=r.panel.lines[#r.panel.lines]
    assert(text==data[code].pools.tired[1] or text==data[code].pools.tired[2],code.." uses its authored reply")
    assert(r.speech.lines[#r.speech.lines]==text,"same reply overhead and in panel")
    assert(not example[text]);example[text]=true
    d:Input("停");assert(r.control.calls==calls+2,"personality does not consume stop request")
    now=now+300
end
assert(saved==16)
assert(P.Resolve(r.memory,"original")=="ESFP","local saved choice restores")
assert(P.Resolve(r.memory,"INTJ")=="INTJ","changed mod config overrides saved selection")
assert(P.Resolve({personality="INVALID",personality_config="original"},"original")=="original")
d:SetPersonality("INTJ",false);d.used={};d.previous={}
d:Say("tired",50,nil,true);local first=r.panel.lines[#r.panel.lines]
d:Say("tired",50,nil,true);assert(r.panel.lines[#r.panel.lines]~=first,"two authored variants do not repeat immediately")
local pool=P.Pool("INTJ","tired",{"fallback"},d.used,now,240)
assert(pool[1]=="fallback","exhausted short-term variants fall back without cycling")
d:Say("amulet",100,"亲爱的我，请不要再死了。",true)
assert(r.panel.lines[#r.panel.lines]=="亲爱的我，请不要再死了。","fixed resurrection line preserved")
r.quiet=true;now=now+300
assert(not d:Say("greeting",10),"quiet applies to all profiles")
r.quiet=false;d.last={};d.next=0;d:Say("greeting",10)
assert(math.abs(d.next-now-25*data.INTJ.frequency)<.001,"profile affects automatic frequency")
d:Input("查看人格");assert(r.panel.lines[#r.panel.lines]:find("INTJ",1,true))
d:Input("恢复原版人格");assert(d.personality=="original")
-- 真实Runtime:Save写入人格与配置版本，沿用现有本地存档入口。
local captured
json={encode=function(copy) captured=copy;return "saved" end}
TheSim.SetPersistentString=function() end
local Runtime=require("shadowself/runtime")
Runtime.Save({loaded=true,memory={personality="INFP",personality_config="original"},storage="mock"})
assert(captured.personality=="INFP" and captured.personality_config=="original")
print("PASS: 16 profiles / 448 authored lines, text personality selection, commands, fixed text, frequency and save")
