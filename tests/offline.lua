-- 离线模拟：不等同于 DST 引擎或联机实测。
package.path="./scripts/?.lua;"..package.path
local passed=0
local function check(ok,label) assert(ok,label); passed=passed+1 end
function Class(base,ctor)
    if ctor==nil then ctor=base; base=nil end
    local t={}; t.__index=t
    setmetatable(t,{__index=base,__call=function(c,...)
        local self=setmetatable({},c); ctor(self,...); return self
    end})
    return t
end
local time=1000
function GetTime() return time end
local Matcher=require("shadowself/matcher")
for _,case in ipairs({
    {"我好害怕","fear"},{"我不怕","default"},{"我不害怕","default"},
    {"我一点也不恐惧","default"},{"我不太饿","default"},
    {"我不怕，但是好孤独","lonely"},{"你怕吗","you_fear"},
    {"你饿吗","you_hunger"},{"你冷吗","you_cold"},{"你是谁啊","identity"},
    {"请你别说话","quiet"},{"不要说话","quiet"},{"陪我聊聊","speak"},
    {"等等我","wait"},{"跟我来","follow"},{"今天不想玩了","quit"},
    {"没有饥饿的感觉","default"},{"下雨了","rain"},{"未知话题","default"},
}) do check(Matcher.Match(case[1])==case[2],"matcher: "..case[1].." -> "..Matcher.Match(case[1])) end
local Pools=require("shadowself/data/dialogue")
local categories,expressions=0,0
for category,pool in pairs(Pools) do
    local unique={}
    for _,text in ipairs(pool) do check(not unique[text],"unique: "..category);unique[text]=true end
    check(#pool>=5,"pool size "..category); categories=categories+1; expressions=expressions+#pool
end
check(categories==52 and expressions>=260,"dialogue totals")
local Context=require("shadowself/context")
check(Context.Index({sanity=0,hunger=0},{})==0,"context lower bound")
check(Context.Index({phase_index=3,season_index=3,tile=7,sanity=1,hunger=1,danger=3,snow=true,company=3},{died_today=true,ate_today=true})==524287,"context upper bound")
for shard=0,63 do
    local values=require(string.format("shadowself/data/context_%02d",shard))
    check(#values==8192,"shard length "..shard)
    for _,v in ipairs(values) do assert(type(v)=="number" and v>=0 and v<256) end
end
local c={night=true,low_sanity=true,spider=true}
local r={options={frequency=25},memory={last_speech=0},panel={lines={}}}
function r.panel:AddLine(who,text) self.lines[#self.lines+1]=text end
local Dialogue=require("shadowself/dialogue")
local d=Dialogue(r);r.dialogue=d
check(d:Category("chop",c)=="nightmare","compound context")
check(d:Say("greeting",1),"initial speech")
check(not d:Say("fire",1),"global cooldown")
time=time+30
check(not d:Say("greeting",1),"category cooldown")
time=time+100
check(d:Say("greeting",1),"cooldown expiry")
check(r.panel.lines[1]~=r.panel.lines[2],"no immediate repeat")
d:Input("请等我");check(r.wait==true,"wait command")
time=time+2; d:Input("跟着我");check(r.wait==false,"follow command")
time=time+2; d:Input("别说话");check(r.quiet==true,"quiet command")
time=time+2; d:Input("说话吧");check(r.quiet==false,"speak command")
-- 用真正的运行时验证死亡、护符复活、清理；仅隔离渲染和传感器。
package.loaded["shadowself/actor"]=Class(function(self,p)
    self.owner=p; self.inst={}; self.states={}
    function self:SetState(state) self.state=state end
    function self:BeginCeremony(kind) self.states[#self.states+1]=kind end
    function self:Step(dt) self.frames=(self.frames or 0)+1;self.last_dt=dt end
    function self:CopyAppearance() end
    function self:Destroy() self.removed=true end
end)
package.loaded["shadowself/sensor"]=Class(function(self,runtime)
    function self:Sample() runtime.context=runtime.context or {} end
    function self:ObserveAction() end
end)
package.loaded["shadowself/effects"]=Class(function(self)
    function self:Burst() end; function self:Step() end; function self:Destroy() self.removed=true end
end)
json={encode=function() return "{}" end,decode=function() return {} end}
TheSim={GetPersistentString=function(_,key,cb) cb(false,"") end,SetPersistentString=function() end}
local owner={ghost=false,animation="idle_loop",listeners={},replica={}}
function owner:HasTag(tag) return tag=="playerghost" and self.ghost end
function owner:IsValid() return true end
function owner:ListenForEvent(event,fn) self.listeners[event]=fn end
function owner:DoPeriodicTask(period,fn) return {Cancel=function(task) task.cancelled=true end,fn=fn} end
owner.Transform={GetWorldPosition=function() return 0,0,0 end}
owner.AnimState={IsCurrentAnimation=function(_,name) return name==owner.animation end}
local Runtime=require("shadowself/runtime")
local rt=Runtime(owner,{frequency=25,ceremony=true});rt.panel=r.panel;rt:Start()
check(rt.actor~=nil and rt.task~=nil,"startup")
rt:Step(.05);check(rt.actor.frames==nil,"logic timer does not move actor")
rt:Frame(1/60);rt:Frame(1/60);check(rt.actor.frames==2 and rt.actor.last_dt==1/60,"visual movement uses frame dt")
IsSimPaused=function() return true end;rt:Frame(1/60);check(rt.actor.frames==2,"paused frame does not move")
IsSimPaused=nil
owner.ghost=true;rt:Step(.05)
check(rt.dead and rt.memory.first_death and rt.memory.died_today,"death flags")
check(rt.actor.states[#rt.actor.states]=="death","death ceremony")
time=time+3;owner.animation="amulet_rebirth";rt:Step(.05)
check(rt.actor.states[#rt.actor.states]=="amulet","amulet detected")
check(r.panel.lines[#r.panel.lines]=="亲爱的我，请不要再死了。","fixed amulet line")
time=time+1;owner.ghost=false;rt:Step(.05)
check(not rt.dead and rt.memory.first_revive,"revive flags")
check(rt.actor.states[#rt.actor.states]=="amulet","no duplicate revival ceremony")
rt:Destroy();rt:Destroy()
check(rt.actor.removed and rt.effects.removed and rt.task.cancelled,"cleanup")
print(string.format("PASS: %d assertions; %d categories; %d expressions; 524288 context parameters",passed,categories,expressions))
