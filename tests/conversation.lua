local M=require("shadowself/matcher")
local cases={
    {"我死了","self_death"},{"我又死了，而你消失不见了","death_absent"},
    {"我今天又死了一次","self_death"},{"刚才我挂掉了你却不在","death_absent"},
    {"你怎么不见了","absent"},{"你到底跑哪里去了","absent"},
    {"我复活了你看","after_revive"},{"我现在变成鬼了","ghost"},
    {"你怎么站着不走啊","why_stop"},{"你为什么一直跟着我","why_follow"},
    {"你没有理解我的意思","complaint"},{"能不能正常点，你这都答非所问了","complaint"},
    {"你是不是不想理我","complaint"},{"给我讲个笑话吧","joke"},
    {"讲个故事听听","story"},{"哈喽，你在干嘛","ask_day"},
    {"听得到吗","present"},{"今天过得怎么样啊","ask_day"},
    {"不知道做什么，有点无聊","bored"},{"今天发生了一件事","daily"},
    {"我今天去河边走了走","daily"},{"我做到了！","happy"},
    {"今天心情不好","comfort"},{"我真的有点累","tired"},
    {"我有一点害怕","fear"},{"我一个人好孤独","lonely"},
    {"气死我了","angry"},{"你怎么这么可爱","praise"},
    {"我想你了","miss_you"},{"你会想我吗","miss_you"},
    {"你到底喜不喜欢我","relationship"},{"我们是什么关系啊","relationship"},
    {"对不起，刚才凶你了","sorry"},{"幸好有你在","thanks"},
    {"嗯嗯，知道了","agree"},{"我不同意你这个说法","disagree"},
    {"哈哈哈笑死我了","laugh"},{"今天又加班了","work"},
    {"明天考试，我复习不完","study"},{"朋友不理我了","friends"},
    {"我是不是真的很没用","self_doubt"},{"接下来我们干什么","plans"},
    {"我迷路了找不到家","lost"},{"我们回营地吧","home"},
    {"背包满了放不下了","inventory"},{"我打不过它","combat_help"},
    {"我快没血了","hurt"},{"我的理智好低","sanity"},
    {"肚子饿了找点吃的吧","hunger"},{"我已经吃过了","eat"},
    {"我快冻死了","cold"},{"太热了受不了","hot"},
    {"昨晚没睡好","tired"},{"风好大啊","weather"},
    {"刚开始玩饥荒不会玩","game"},{"终于打过这个boss了","happy"},
    {"今天真倒霉","comfort"},{"答应我别忘了我","promise"},
    {"告诉你一个秘密","secret"},{"你能帮我砍树吗","ability"},
    {"你还记得刚才发生什么吗","memory"},{"你有感情吗","ask_day"},
    {"你从哪里来的","identity"},{"活着的意义是什么","meaning"},
    {"明天我们去哪","plans"},{"我先下了，下次见","bye"},
    {"我不害怕了","calm"},{"我没有死，活得好好的","after_revive"},
    {"你会死吗","relationship"},{"我想静静陪我坐会","idle"},
    {"你跟我聊聊天吧","speak"},{"放心吧我没事的","calm"},
    {"再讲一个笑话","joke"},{"我一点都不累","default"},
    {"我不觉得紧张","default"},{"我不太饿","default"},
    {"我不孤独","default"},{"我笑死了","laugh"},
    {"我吓死了","fear"},{"我还活着呢","after_revive"},
    {"我今天又挂了，影子你却没影了","death_absent"},
    {"我不喜欢你","disagree"},{"你不可爱","disagree"},{"我不是很笨","default"},
}
local failed={}
for _,case in ipairs(cases) do
    local actual=M.Match(case[1])
    if actual~=case[2] then failed[#failed+1]=case[1].." : "..actual.." expected "..case[2] end
end
for _,line in ipairs(failed) do print("MISS "..line) end
assert(#failed==0,string.format("conversation corpus: %d/%d failed",#failed,#cases))
local category,_,meta=M.Match("为什么呢","self_death")
assert(category=="self_death" and meta.id=="followup","followup remembers prior topic")
local rules=require("shadowself/data/conversation").rules
local pool={}
for k,v in pairs(require("shadowself/data/dialogue")) do pool[k]=v end
for k,v in pairs(require("shadowself/data/chat")) do pool[k]=v end
local dynamic={why_stop=true,memory=true}
local phrases=0
for _,rule in ipairs(rules) do
    assert(pool[rule.category] or dynamic[rule.category],"unhandled reply category: "..rule.category)
    phrases=phrases+#rule.phrases
    for _,group in ipairs(rule.groups or {}) do phrases=phrases+#group end
end
print(string.format("PASS: %d conversation cases; %d new intents; %d phrase/group entries; followup and reply coverage",#cases,#rules,phrases))
local chat={options={frequency=25},memory={},panel={lines={}}}
function chat.panel:AddLine(who,text) self.lines[#self.lines+1]=text end
local d=require("shadowself/dialogue")(chat)
d:Input("我又死了，而你消失不见了")
assert(d.last_intent=="death_absent","screenshot input category")
assert(not string.find(chat.panel.lines[1],"没弄明白",1,true),"no default pool for screenshot")
d:Input("为什么呢")
assert(string.find(chat.panel.lines[2],"隐去",1,true),"followup addresses disappearance")
d:Input("我死了")
assert(#chat.panel.lines==3 and d.last_intent=="self_death","rapid user messages are not silently dropped")
