package.path="./scripts/?.lua;"..package.path
local saved={};for _,k in ipairs({"GetTime","Vector3","TheNet","EQUIPSLOTS","print","scheduler"}) do saved[k]=_G[k] end
local key="shadowself/control/newbosses/debug";local previous=package.loaded[key];package.loaded[key]=nil
local geometrykey="shadowself/control/newbosses/geometry";local oldgeometry=package.loaded[geometrykey];package.loaded[geometrykey]=nil
local t=10;GetTime=function() return t end
Vector3=function(x,y,z) return {x=x,y=y,z=z,DistSq=function(a,b)return (a.x-b.x)^2+(a.z-b.z)^2 end} end
TheNet={GetPing=function() return 22 end};EQUIPSLOTS={HANDS="hands"}
local lines={};print=function(line) lines[#lines+1]=line end
local M=require(key);local clock=0;M.Clock=function() clock=clock+.00001;return clock end
local function ent(name,id)
    local e={prefab=name,GUID=id,Transform={},animation="idle",frame=0,replica={}}
    function e:IsValid() return not self.removed end
    function e:GetPosition() return Vector3(3,0,0) end
    function e:HasTag() return false end
    e.AnimState={IsCurrentAnimation=function(_,a) return a==e.animation end,GetCurrentAnimationFrame=function() return e.frame end}
    return e
end
local boss=ent("charlie_boss",2);local player=ent("wilson",1);local hand=ent("cane",3);local hp=100
player.replica.inventory={GetEquippedItem=function() return hand end};player.replica.health={GetCurrent=function() return hp end}
player.components={playercontroller={IsBusy=function() return false end}}
local function worker() coroutine.yield() end
local own={id="shadowself_combat_supervisor",fn=worker,co=coroutine.create(worker)}
local other={id="test_other",fn=worker,co=coroutine.create(worker)}
scheduler={tasks={[own.co]=own,[other.co]=other}}
local original_info,original_traceback=debug.getinfo,debug.traceback;local trace_calls=0
debug.traceback=function() trace_calls=trace_calls+1;error("DST must never receive a coroutine traceback request") end
debug.getinfo=function(fn,what) assert(type(fn)=="function" and what=="S");return original_info(fn,what) end
local c={player=player,h={ent=boss},gear={},bridge={supervisor=own}};function c:Speed() return 7.5 end
local o={c=c,bosses={},shapes={},bodies={},states={}};function o:Risk() return 0 end
local d=M.New(o);d:Tick(M.Clock());assert(#lines==0,"ordinary combat emits nothing")
o.bosses={boss};o.states[boss]={};boss.animation="castlift";d:Tick(M.Clock())
assert(lines[1]:find("event=start",1,true) and lines[1]:find("v=0.13.23",1,true))
assert(trace_calls==0 and table.concat(lines):find("event=thread",1,true) and table.concat(lines):find("source=",1,true))
assert(coroutine.status(own.co)=="suspended" and coroutine.status(other.co)=="suspended","metadata never runs tasks")
assert(table.concat(lines):find("anim=castlift",1,true),"use observed IsCurrentAnimation; no nonexistent name API")
for i=1,60 do t=t+.1;d:Plan(M.Clock()-.001,144,false);d:Tick(M.Clock()) end
assert(#d.ring<=20 and table.concat(lines):find("event=perf",1,true))
t=t+.3;hp=80;d:Tick(M.Clock());assert(d.totals.hits==1 and table.concat(lines):find("reason=hp_drop",1,true))
assert(table.concat(lines):find("event=before_hit",1,true),"hurt includes bounded prior context")
local hits=d.totals.hits;d:Hit({attacker=boss,damage=20});assert(d.totals.hits==hits,"deduplicate immediate health/event pair")
t=t+1;hand=ent("nightsword",4);d:Tick(M.Clock());assert(d.totals.hands==1)
d:Action({action={id="ATTACK"},target=boss,invobject=hand});d:Move(Vector3(8,0,0),"beam_run")
assert(table.concat(lines):find("event=action",1,true) and table.concat(lines):find("event=hand",1,true))
-- 爆发事件也有硬上限；不能用debug替代旧的逐帧刷屏。
for i=1,100 do d:Emit("skill",{"frame",i});d:Hit({attacker=boss,damage=1}) end
local counts={}
for _,line in ipairs(lines) do local stamp=line:match(" t=([%d.]+)");local s=math.floor(tonumber(stamp));counts[s]=(counts[s] or 0)+1 end
for _,count in pairs(counts) do assert(count<=24,"debug log budget exceeded") end
assert((d.dropped or 0)>0)
t=t+3;o.bosses={};d:Tick(M.Clock());assert(not d.active and #d.ring==0)
local n=#lines;M.Configure(false);o.bosses={boss};d:Tick(M.Clock());assert(#lines==n,"switch disables logging")
-- 空间剔除必须和完整危险计算一致，包括高速移动圆、斜矩形及三角形。
local G=require(geometrykey);local shapes={};boss.Transform.GetRotation=function() return 31 end
G.Circle(shapes,boss,2,Vector3(-9,0,2),30,-4)
G.Line(shapes,boss,Vector3(-4,0,-3),Vector3(8,0,7),1.5)
G.Rect(shapes,boss,-1,7,2,.75)
G.Triangle(shapes,boss,Vector3(-6,0,0),Vector3(5,0,-7),Vector3(3,0,9),.5)
G.Circle(shapes,boss,3,Vector3(70,0,70),0,0)
local checked=0
for x=-12,12,3 do for z=-12,12,3 do
    local a=Vector3(x,0,z);local b=Vector3(x+5,0,z+3);local subset=G.Select(shapes,a,b)
    assert(#subset<#shapes,"unreachable far hazard excluded")
    for i=0,4 do for _,time in ipairs({0,.1,.3,.6}) do
        local p=Vector3(a.x+(b.x-a.x)*i/4,0,a.z+(b.z-a.z)*i/4)
        assert(math.abs(G.Window(shapes,p,0,time)-G.Window(subset,p,0,time))<1e-9,"prefilter changed risk")
        checked=checked+1
    end end
end end
assert(trace_calls==0,"never call engine traceback, including slow/hit paths")
debug.getinfo=original_info;debug.traceback=original_traceback
package.loaded[key]=previous;package.loaded[geometrykey]=oldgeometry
for _,k in ipairs({"GetTime","Vector3","TheNet","EQUIPSLOTS","print","scheduler"}) do _G[k]=saved[k] end
print("PASS: safe DST task-function metadata without coroutine traceback, scoped hurt/performance logs and "..checked.." spatial-risk equivalence checks")
