-- 跨帧模拟：新箭头、实际横移、实际过洞、公告死亡、战斗控制权。
package.path="./scripts/?.lua;"..package.path
local saved={}
local modules={"actions","travel","combat","adventureworld/config","adventureworld/registry",
    "adventureworld/locator","adventureworld/watch","adventureworld/controller","request"}
for _,name in ipairs(modules) do local key="shadowself/control/"..name;saved[key]=package.loaded[key];package.loaded[key]=nil end
local old={Class=Class,GetTime=GetTime,Vector3=Vector3,TheWorld=TheWorld,TheSim=TheSim,STRINGS=STRINGS,ACTIONS=ACTIONS,EQUIPSLOTS=EQUIPSLOTS}
Class=function(ctor) local c={};c.__index=c;return setmetatable(c,{__call=function(_,...) local o=setmetatable({},c);ctor(o,...);return o end}) end
local now=10;GetTime=function() return now end
Vector3=function(x,y,z) return {x=x,y=y,z=z,Get=function(s) return s.x,s.y,s.z end,
    DistSq=function(a,b) return (a.x-b.x)^2+(a.z-b.z)^2 end} end
STRINGS={NAMES={SHADOWTHRALL_HORNS="墨角",SHADOWTHRALL_WINGS="墨羽",SHADOWTHRALL_HANDS="墨爪"}}
EQUIPSLOTS={HANDS="hands",BACK="back"};ACTIONS={JUMPIN={},GIVE={}}
TheWorld={Map={IsPassableAtPoint=function() return true end}}
local entities={};TheSim={FindEntities=function() return entities end}
local function ent(prefab,x,z,tags)
    local e={prefab=prefab,pos=Vector3(x,0,z),tags=tags or {},GUID=math.random(10000000),replica={}}
    function e:IsValid() return not self.invalid end;function e:HasTag(t) return self.tags[t] or false end
    function e:GetPosition() return self.pos end;function e:GetBasicDisplayName() return self.name or self.prefab end
    function e:GetDistanceSqToInst(other) return self.pos:DistSq(other:GetPosition()) end
    function e:GetDistanceSqToPoint(x,y,z) return self.pos:DistSq(Vector3(x,y,z)) end
    e.Transform={GetWorldPosition=function() return e.pos:Get() end,GetRotation=function() return e.rotation or 0 end}
    return e
end
local p=ent("wanda",0,0,{pocketwatchcaster=true});p.userid="test"
local items,bagitems={},{};local active;local casts,stops,moves=0,0,0;local scene_guard
local bag={GetItemInSlot=function(_,i) return bagitems[i] end,GetNumSlots=function() return 10 end}
local inv={GetItems=function() return items end,GetEquips=function() return {} end,
    GetOverflowContainer=function() return bag end,GetEquippedItem=function() end,
    GetNumSlots=function() return 15 end,GetItemInSlot=function(_,i) return items[i] end,
    GetActiveItem=function() return active end,UseItemFromInvTile=function() casts=casts+1 end,
    classified={},PutAllOfActiveItemInSlot=function(_,i) items[i]=active;active=nil end,
    ControllerUseItemOnItemFromInvTile=function() active=nil end,
    ReturnActiveItem=function() active=nil end}
p.replica.inventory=inv;p.components={playercontroller={IsBusy=function() return p.busy end,
    GetItemUseAction=function() return {action=ACTIONS.GIVE} end}}
package.loaded["shadowself/control/actions"]={Items=function() local a={};for _,e in pairs(items) do a[#a+1]=e end;return a end,
    Stop=function() stops=stops+1 end,Move=function() moves=moves+1 end,
    Scene=function(_,target,act,guard) assert(act==ACTIONS.JUMPIN);scene_guard=guard;return true end}
local R=require("shadowself/control/adventureworld/registry");R.Reset(TheWorld)
R.OnAnnouncement("冒险世界的旅者级巨鹿已刷新");assert(R.Available(1))
R.OnAnnouncement("冒险世界的旅者级巨鹿被测试玩家击杀");assert(not R.Available(1) and R.WasKilled(1,"巨鹿",9))
for cycle=1,2 do
    R.OnAnnouncement("冒险世界的专家级墨荒三相已刷新")
    R.OnAnnouncement("冒险世界的专家级墨角被玩家击杀");assert(R.Available(2))
    R.OnAnnouncement("冒险世界的专家级墨羽被玩家击杀");assert(R.Available(2))
    R.OnAnnouncement("冒险世界的专家级墨爪被玩家击杀");assert(not R.Available(2))
end
local seen=0;local history={OnAnnouncement=function() seen=seen+1 end}
R.Install({ChatHistory=history});local hook=history.OnAnnouncement;R.Install({ChatHistory=history});assert(hook==history.OnAnnouncement)
history:OnAnnouncement("冒险世界的大师级龙蝇已刷新");assert(seen==1 and R.Available(3))
TheWorld={Map=TheWorld.Map};assert(not R.Available(3),"world change clears old announcements")
assert(not R.InWorld({}),"ordinary world cannot silently consume vanilla pig coins")
TheWorld.net={_shardid={value=function() return "7" end}};assert(R.InWorld({}))
local L=require("shadowself/control/adventureworld/locator")
local hit=L.Intersect({x=0,z=0,dx=1,dz=0},{x=10,z=10,dx=0,dz=-1});assert(hit.x==10 and hit.z==0)
assert(not L.Intersect({x=0,z=0,dx=1,dz=0},{x=0,z=1,dx=1,dz=0}))
local coin=ent("pig_coin",0,0);coin.replica.stackable={StackSize=function() return 1 end};items[1]=coin
local loc=L(p,1);assert(loc:Tick(function() end)=="running" and casts==1)
assert(loc:Tick(function() end)=="running" and casts==1,"no repeated cast while waiting for arrow")
local marker=ent("archive_resonator_base",0,0);marker.rotation=-90;entities={marker}
loc:Tick(function() end);assert(loc.phase=="move")
loc:Tick(function() end);assert(loc.phase=="move" and casts==1,"no second cast before actual movement")
p.pos=loc.destination;loc:Tick(function() end);assert(loc.phase=="prepare")
loc:Tick(function() end);assert(casts==2)
local m2=ent("archive_resonator_base",p.pos.x,p.pos.z)
m2.rotation=math.deg(math.atan2(-p.pos.z,100-p.pos.x))*(-1)-90
entities={marker,m2};local state,result=loc:Tick(function() end)
assert(state=="done" and math.abs(result.x-100)<.01 and math.abs(result.z)<.01)
local empty=L(p,1);empty:Tick(function() end);now=now+5
assert(empty:Tick(function() end)=="empty","missing arrow is unknown/absent, not a fake boss position")
local W=require("shadowself/control/adventureworld/watch")
local watch=ent("pocketwatch_portal",0,0,{pocketwatch_inactive=true});bagitems[1]=watch
p.pos=Vector3(0,0,0);entities={};local w=W(p,1);local before=casts
assert(w:Tick(function() end)=="running" and casts==before+1)
w:Tick(function() end);assert(casts==before+1,"wait for spawned entrance instead of spamming watch")
local portal=ent("pocketwatch_portal_entrance",0,0);entities={portal}
w:Tick(function() end);assert(w.phase=="jump" and scene_guard())
w:Tick(function() end);assert(w.phase=="jump","jump request alone is not arrival")
p.pos=Vector3(100,0,100);p.busy=true;assert(w:Tick(function() end)=="running")
p.busy=false;assert(w:Tick(function() end)=="done")
w:Cancel();assert(not scene_guard(),"cancel invalidates delayed jump action")
bagitems[1]=ent("pocketwatch_recall",0,0,{recall_unmarked=true})
assert(W(p,1):Tick(function() end)=="failed","never overwrites an unmarked watch")
bagitems[1]=ent("pocketwatch_recall",0,0);active=ent("purplegem",0,0)
assert(W(p,1):Tick(function() end)=="failed","does not take over player's cursor gem")
active=nil
-- 真实总调度，替换动作/原生协程边界：同一时刻仅一个战斗所有者。
local starts,ends,walking=0,0,0
package.loaded["shadowself/control/combat"]=Class(function(self)
    function self:Start(plan) assert(not self.on);self.on=true;self.plan=plan;starts=starts+1;return true end
    function self:Running() return self.on end
    function self:Stop() if self.on then ends=ends+1 end;self.on=false end
end)
package.loaded["shadowself/control/travel"]=Class(function(self)
    function self:Tick() walking=walking+1 end;function self:Reset() end
end)
local Controller=require("shadowself/control/adventureworld/controller")
p.pos=Vector3(0,0,0);local boss=ent("deerclops",10,0,{adventure_boss=true,level1=true});boss.replica.combat={}
entities={boss};R.Observe(entities);assert(R.Available(1) and R.Report():find("deerclops",1,true))
local c=Controller(p,{grade=1},function() end)
assert(c:Tick()=="running" and c:OwnsCombat() and c.phase=="fight" and starts==1)
assert(c.bridge.plan.adventure_contains(boss))
local other=ent("dragonfly",10,0,{adventure_boss=true,level2=true});assert(not c.bridge.plan.adventure_contains(other))
local count=moves;for i=1,4 do now=now+.3;c:Tick() end
assert(moves==count and walking==0 and starts==1,"adventure movement must not fight the native combat thread")
boss.tags.dead=true;now=now+.4;c:Tick();assert(not R.Available(1));assert(not c:OwnsCombat() and c.phase=="select" and ends==1)
boss.tags.dead=nil;now=now+1;c:Tick();assert(c:OwnsCombat())
boss.invalid=true;c:Tick();assert(c.phase=="select" and not c:OwnsCombat(),"unloaded target is not declared killed")
c:Cancel();assert(c:Tick()=="done")
entities={};local c2=Controller(p,{},function() end);assert(c2:Grade()==1,"only probe grades inventory can prepare")
items={};assert(not c2:Grade(),"no coin does not start endless invalid grade attempts")
-- 实际Jobs路由与停止清理；自动冒险不进入旧的单次adventure/工作guard。
package.loaded["shadowself/control/jobs"]=nil
local Jobs=require("shadowself/control/jobs");local jobs=Jobs(p)
boss.invalid=nil;entities={boss};jobs:Set({kind="adventureworld",grade=1})
assert(jobs.adventureworld and not jobs.extended and not jobs.guard)
jobs:Tick();assert(jobs:OwnsCombat());jobs:Cancel();assert(not jobs.adventureworld and not jobs:OwnsCombat())
package.loaded["shadowself/control/request"]=nil
local req=require("shadowself/control/request")
for _,s in ipairs({"帮我自动冒险","接管冒险世界","帮我打冒险世界"}) do assert(req.Parse(s).kind=="adventureworld",s) end
assert(req.Parse("帮我接管冒险世界，只打旅者").grade==1)
assert(not req.Parse("不要帮我自动冒险"));assert(not req.Parse("你会不会自动冒险"))
-- 真实源码协议核验，防止客户端把猪币当成私有RPC或忘记服务器免控设定。
local f=assert(io.open("D:/Steam/steamapps/workshop/content/322330/2067228865/scripts/adventure/main.lua","r"))
local server=f:read("*a");f:close()
for _,s in ipairs({'"adventure_boss"','"level"..q','"archive_resonator_base"','SetRotation(aq+90)','sleeper.AddSleepiness=function','freezable.Freeze=function'}) do
    assert(server:find(s,1,true),s)
end
for key,value in pairs(saved) do package.loaded[key]=value end
for key,value in pairs(old) do _G[key]=value end
print("PASS: adventure announcements, triangulation, actual watch arrival, cancellation, native combat ownership and server protocol")
