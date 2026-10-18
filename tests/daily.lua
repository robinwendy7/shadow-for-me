local M=require("shadowself/matcher")
for _,text in ipairs({"我最近一直失眠","心里乱得很，绷不住了","有木有觉得这歌很好听","我口渴，忘记喝水了","腰疼，坐累了","我想听点音乐","我想养只小猫","刚刚忘带东西了"}) do
    local category=M.Match(text)
    assert(category~="default","new daily topic must recognize: "..text)
end
assert(M.Match("我一点也不恐惧")=="default")
assert(M.Match("我不怕，但真的很孤独")=="lonely")
assert(M.Match("我又死了，你消失了")=="death_absent")
local cat=M.Match("emo了");assert(cat=="comfort" or cat=="daily_sad" or cat=="daily_stress")
local new=require("shadowself/data/daily");local rules,lines=0,0
for _,rule in ipairs(new.rules) do rules=rules+1;assert(#rule.phrases>=4) end
for _,pool in pairs(new.pools) do lines=lines+#pool end
assert(rules==59 and lines==177,"authored daily content counted independently from generated input examples")
print("PASS: 59 additional daily topics, 177 authored replies; slang normalization; existing negation/death semantics preserved")
