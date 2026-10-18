-- 导入模块使用真实代码，隔离前面测试的假模块。
package.loaded["shadowself/control/request"]=nil
local R=require("shadowself/control/request")
local p=assert(R.Parse("帮我制作2个木板然后装备长矛"))
assert(p.kind=="queue" and #p.steps==2 and p.steps[1].count==2 and p.steps[2].kind=="equip")
for _,text in ipairs({"帮我放置松果","帮我卸下长矛","帮我用噩梦燃料给暗夜灯","帮我坐下"}) do
    local plan=R.Parse(text);assert(plan and plan.kind=="queue",text)
end
assert(R.Parse("帮我自主托管").kind=="autonomy")
assert(R.Parse("帮我制作两个木板").kind=="queue")
assert(R.Parse("帮我救小明").kind=="adventure")
assert(R.Parse("/ai collect log 20").command=="collect log 20")
assert(not R.Parse("帮我制作木板然后换成旺达角色"),"unsupported compound must not execute a prefix")
assert(not R.Parse("不要帮我制作2个木板"))
-- 原版 Queue 的数量展开与取消代际；无需模拟网络。
local Queue=require("shadowself/zom/ActionQueue")
local stops=0
local q=Queue.new(_G,function() end,function() end,function() stops=stops+1 end,function() return false end)
q:Set(p.steps,{},{});assert(#q.steps==3 and stops==1)
q.current=table.remove(q.steps,1);local generation=q.generation
q:Cancel({});assert(q.generation>generation and q.current==nil and #q.steps==0)
-- 真实旧 AI 选择器：危机覆盖普通资源，不做固定延时。
package.loaded.cooking={recipes={}}
FOODTYPE={MEAT="meat",GOODIES="goodies"};TUNING=TUNING or {}
local registry=require("shadowself/legacy/registry")
require("shadowself/legacy/decision_brain")
local selected
local humanizer={Choose=function(_,list) selected=list;return list[1] end}
local brain=setmetatable({humanizer=humanizer,nodes={
    {name="逃离威胁",priority=100,condition=function(s) if s.danger then return {kind="move",name="flee"} end end},
    {name="执行任务",priority=60,condition=function() return {kind="action",name="CHOP"} end}}},{__index=registry.Brain})
local a=brain:Evaluate({danger=true});assert(a.name=="flee" and a.emergency and #selected==1)
local b=brain:Evaluate({danger=false});assert(b.name=="CHOP" and not b.emergency)
assert(brain:Emergency({danger=true}).name=="flee")
print("PASS: imported zom multi-step/count parser, queue cancellation, AI Player priority decisions")
