-- 只诊断查理/暗影憎恶；复用战斗监督更新，不创建线程，不改调度器，不逐帧打印。
local M={VERSION="0.13.23",enabled=true}
local Geometry=require("shadowself/control/newbosses/geometry")
local sequence=0
local function now() return GetTime() end
function M.Clock() return os.clock() end
function M.Configure(value) M.enabled=value~=false end
local function entity(e)
    return e and (e.prefab or "?")..":"..tostring(e.GUID or "?") or "none"
end
local function valid(e) return e and e.IsValid and e:IsValid() end
local function pos(e)
    if not valid(e) or not e.Transform then return "invalid" end
    local p=e:GetPosition();return string.format("%.2f,%.2f",p.x,p.z)
end
local animations={"castlift","aoe","hit","air_cast","vine_cast","idle","walk_loop","run_loop","run_pre",
    "teleport_pre","teleport_loop","teleport_pst","punch_pre","punch_loop","optic_blast_pre1","optic_blast_pre2",
    "optic_blast_pre3","optic_blast_loop","optic_blast_pst","death_puddle_loop","death_puddle_loop2","death",
    "spawn","spawn_loop","spawn_pst","taunt","taunt2","charlie_atk","beam_pre","beam_basic_loop","beam_basic_pst",
    "beam_wide_pre","beam_wide_loop","beam_wide_pst","shrouden_jump","portal_appear","bite_loop","shrouden_disappear"}
local function anim(e)
    if not valid(e) or not e.AnimState then return "invalid",-1 end
    local name=e.AnimState.GetCurrentAnimationName and e.AnimState:GetCurrentAnimationName() or "?"
    if name=="?" then for _,a in ipairs(animations) do if e.AnimState:IsCurrentAnimation(a) then name=a;break end end end
    return tostring(name),e.AnimState:GetCurrentAnimationFrame() or -1
end
local function safe(value)
    if type(value)=="number" then return string.format("%.3f",value) end
    return tostring(value):gsub("[\r\n\t ]","_"):sub(1,220)
end
local D={};D.__index=D
function M.New(owner) return setmetatable({owner=owner,ring={},last=setmetatable({},{__mode="k"}),totals={hits=0,moves=0,hands=0,plans=0}},D) end
function D:Emit(event,fields)
    if not self.active or not M.enabled then return end
    local second=math.floor(now())
    if self.second~=second then self.second=second;self.lines=0 end
    local priority=event=="hit" or event=="before_hit" or event=="hazard"
    if self.lines>=(priority and 24 or 16) then self.dropped=(self.dropped or 0)+1;return end
    self.lines=self.lines+1
    local parts={"[ShadowSelf][BossDebug]","v="..M.VERSION,"sid="..self.sid,"t="..safe(now()),"event="..event}
    for i=1,#fields,2 do parts[#parts+1]=fields[i].."="..safe(fields[i+1]) end
    print(table.concat(parts," "))
end
function D:Trace(reason)
    if now()<(self.next_trace or 0) then return end
    self.next_trace=now()+2
    if not debug or not debug.getinfo then return end
    local b=self.owner.c.bridge
    local seen={}
    local function describe(task,name)
        -- DST的调试栈接口不接受Lua标准库式协程参数；只读取Task保留的入口函数。
        -- getinfo(function,"S")与原版class.lua一致，不执行函数、不读取协程栈。
        local info=type(task.fn)=="function" and debug.getinfo(task.fn,"S") or nil
        local state=type(task.co)=="thread" and coroutine.status(task.co) or "missing"
        self:Emit("thread",{"reason",reason,"task",name,"id",task.id or "?","state",state,
            "source",info and (info.short_src or info.source) or "unknown","line",info and info.linedefined or -1})
    end
    for _,name in ipairs({"supervisor","thread"}) do
        local task=b[name]
        if task and task.co then
            seen[task.co]=true
            describe(task,name)
        end
    end
    -- 给出其他协程的名称、状态及入口位置，辅助核对scheduler警告归属。
    local others={}
    for co,task in pairs(scheduler and scheduler.tasks or {}) do
        if not seen[co] and type(co)=="thread" and coroutine.status(co)~="dead" then
            others[#others+1]=task;if #others>=64 then break end
        end
    end
    for i=1,math.min(3,#others) do
        local index=((self.trace_cursor or 0)+i-1)%#others+1;local task=others[index]
        describe(task,"other")
    end
    self.trace_cursor=(self.trace_cursor or 0)+3
end
function D:Snapshot()
    local o=self.owner;local c=o.c;local p=c.player;local inv=p.replica.inventory
    local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS);local health=p.replica.health
    local hp=health and health.GetCurrent and health:GetCurrent()
    local pending=c.gear.pending;local locked=c.gear.action_hold
    local point=c.last_point or c.point
    local a,f=anim(c.h.ent)
    local bosses={}
    for i=1,math.min(4,#o.bosses) do local e=o.bosses[i];local ba,bf=anim(e);bosses[#bosses+1]=entity(e)..":"..ba..":"..bf end
    return {"pos",pos(p),"hp",hp or -1,"hand",entity(hand),"target",entity(c.h.ent),"anim",a,"frame",f,
        "speed",c:Speed(),"ping",TheNet and TheNet.GetPing and TheNet:GetPing() or -1,
        "mode",o.beam_run and "beam_run" or o.gel_escape and "gel_blink" or o.moving and "dodge" or o.holding and "hold" or "attack",
        "goal",point and string.format("%.2f,%.2f",point.x,point.z) or "none",
        "shapes",#o.shapes,"bodies",#o.bodies,"entities",o.scene_count or 0,"bosses",table.concat(bosses,","),
        "pending",pending and entity(pending.item) or "none","role",pending and pending.role or "none",
        "lock",locked and "yes" or "no","busy",p.components.playercontroller:IsBusy(),"gel",p:HasTag("gelblobbed"),"pinned",p:HasTag("pinned")},hp,entity(hand)
end
function D:Hit(data,reason)
    if not self.active or now()<(self.next_hit or 0) then return end
    self.next_hit=now()+.2;self.last_hit=now();self.totals.hits=self.totals.hits+1
    local fields=self:Snapshot()
    fields[#fields+1]="attacker";fields[#fields+1]=entity(data and data.attacker)
    fields[#fields+1]="damage";fields[#fields+1]=data and data.damage or -1
    fields[#fields+1]="weapon";fields[#fields+1]=entity(data and data.weapon)
    fields[#fields+1]="projectile";fields[#fields+1]=entity(data and data.projectile)
    fields[#fields+1]="hp_before";fields[#fields+1]=self.hp or -1
    fields[#fields+1]="reason";fields[#fields+1]=reason or "attacked"
    self:Emit("hit",fields)
    local count=#self.ring
    for i=math.max(1,count-5),count do self:Emit("before_hit",self.ring[i]) end
    -- 给出最近技能实体的GUID和动画，便于和Stale Component Reference对应。
    local nearby={};local p=self.owner.c.player:GetPosition()
    for _,h in ipairs(self.owner.shapes) do nearby[#nearby+1]={shape=h,depth=Geometry.Depth(h,p,0)} end
    table.sort(nearby,function(a,b) return a.depth>b.depth end)
    local seen,count={},0
    for _,item in ipairs(nearby) do
        local h=item.shape
        if not seen[h.source] then
            seen[h.source]=true;count=count+1;local a,f=anim(h.source)
            self:Emit("hazard",{"source",entity(h.source),"anim",a,"frame",f,"kind",h.kind,"pos",pos(h.source),
                "plan_radius",h.radius or -1,"depth",item.depth,"future_depth",Geometry.Depth(h,p,.2),"wide",Geometry.Net(h.source and h.source.wide,-1)})
            if count>=5 then break end
        end
    end
    self:Trace("hit")
end
function D:Action(act)
    if not self.active or not act or not act.action then return end
    if now()<(self.next_action or 0) then return end;self.next_action=now()+.25
    self:Emit("action",{"action",act.action.id or act.action.code or "?","target",entity(act.target),"item",entity(act.invobject)})
end
function D:Move(point,label)
    if not self.active then return end
    self.totals.moves=self.totals.moves+1
    if now()<(self.next_move or 0) then return end;self.next_move=now()+.5
    self:Emit("move",{"goal",string.format("%.2f,%.2f",point.x,point.z),"label",label,"risk",self.owner:Risk(point,.2)})
end
function D:Plan(start,candidates,reused)
    if not self.active then return end
    local ms=(M.Clock()-start)*1000
    local perf=self.perf
    perf.plans=perf.plans+1;perf.plan_ms=perf.plan_ms+ms;perf.plan_max=math.max(perf.plan_max,ms)
    perf.candidates=perf.candidates+candidates;perf.reused=perf.reused+(reused and 1 or 0)
    self.totals.plans=self.totals.plans+1
end
function D:Finish(reason)
    if not self.active then return end
    self:Emit("end",{"reason",reason,"duration",now()-self.started,"hits",self.totals.hits,"moves",self.totals.moves,"hands",self.totals.hands,"plans",self.totals.plans,"dropped",self.dropped or 0})
    self.active=false;self.ring={};self.last=setmetatable({},{__mode="k"});self.perf=nil;self.hp=nil;self.hand=nil;self.last_tick=nil
end
function D:Tick(start)
    if not M.enabled then if self.active then self:Finish("disabled") end;return end
    local o=self.owner;local focused=false
    for _,e in ipairs(o.bosses) do if e.prefab=="charlie_boss" or e.prefab=="shrouden" then focused=true;break end end
    if focused then self.last_boss=now() end
    if not focused and (not self.active or now()-(self.last_boss or 0)>2) then self:Finish("boss_gone");return end
    if not self.active then
        sequence=sequence+1;self.active=true;self.sid=tostring(sequence).."-"..string.format("%.2f",now())
        self.started=now();self.last_boss=now();self.next_perf=now()+5;self.dropped=0
        self.perf={ticks=0,ms=0,max_ms=0,plans=0,plan_ms=0,plan_max=0,candidates=0,reused=0,gap=0}
        self.totals={hits=0,moves=0,hands=0,plans=0};self:Emit("start",{"player",entity(o.c.player),"build",M.VERSION})
        self:Trace("start")
    end
    local perf=self.perf;local ms=(M.Clock()-start)*1000
    perf.ticks=perf.ticks+1;perf.ms=perf.ms+ms;perf.max_ms=math.max(perf.max_ms,ms)
    local gap=self.last_tick and now()-self.last_tick or 0;self.last_tick=now()
    if gap<2 then perf.gap=math.max(perf.gap,gap) end
    local player=o.c.player;local health=player.replica.health
    local hp=health and health.GetCurrent and health:GetCurrent()
    local hand=entity(player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS));local fields
    if self.hand and self.hand~=hand then self.totals.hands=self.totals.hands+1;self:Emit("hand",{"from",self.hand,"to",hand}) end
    self.hand=hand
    if hp and self.hp and hp<self.hp and now()-(self.last_hit or -100)>.25 then self:Hit(nil,"hp_drop") end
    self.hp=hp
    for _,e in ipairs(o.bosses) do
        if e.prefab=="charlie_boss" or e.prefab=="shrouden" then
            local a,f=anim(e)
            if self.last[e]~=a then self.last[e]=a;self:Emit("skill",{"boss",entity(e),"anim",a,"frame",f,"pos",pos(e)}) end
        end
    end
    if now()>=(self.next_ring or 0) then
        self.next_ring=now()+.25;local record={"sample_t",now()};fields=self:Snapshot()
        for _,v in ipairs(fields) do record[#record+1]=v end
        self.ring[#self.ring+1]=record;if #self.ring>20 then table.remove(self.ring,1) end
    end
    if now()>=(self.next_sample or 0) then self.next_sample=now()+1;self:Emit("sample",fields or self:Snapshot()) end
    if now()>=self.next_perf then
        self.next_perf=now()+5
        self:Emit("perf",{"ticks",perf.ticks,"avg_ms",perf.ms/math.max(1,perf.ticks),"max_ms",perf.max_ms,
            "plan_calls",perf.plans,"plan_avg_ms",perf.plan_ms/math.max(1,perf.plans),"plan_max_ms",perf.plan_max,
            "candidates",perf.candidates,"reused",perf.reused,"max_gap",perf.gap,"shapes",#o.shapes,"entities",o.scene_count or 0,"dropped",self.dropped or 0})
        for e in pairs(o.states) do if not valid(e) and self.last[e]~=false then
            self.last[e]=false;self:Emit("expired_ref",{"entity",entity(e)})
        end end
        if perf.max_ms>20 or perf.gap>.15 then self:Trace("slow_tick") end
        self.perf={ticks=0,ms=0,max_ms=0,plans=0,plan_ms=0,plan_max=0,candidates=0,reused=0,gap=0}
    end
end
return M
