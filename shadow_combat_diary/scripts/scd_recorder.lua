local Context=require("scd_context")
local Analysis=require("scd_analysis")
local M={};M.__index=M
local function push(list,item,limit) list[#list+1]=item;if #list>limit then table.remove(list,1) end end
local function copylist(list) local out={};for i,v in ipairs(list) do out[i]=v end;return out end
local function n(v) return type(v)=="number" and string.format("%.2f",v) or "未知" end
local function levelname(c)
    c=c or {};return (c.wave and ("第"..c.wave.."关") or c.wave_label or "未识别关卡").." / "..(c.route or "路线未知")
end
local function stagekey(c) return table.concat({tostring(c.instance or ""),tostring(c.generation or ""),tostring(c.wave or c.wave_label or ""),tostring(c.route or "")},"|") end
function M.New(G,options)
    options=options or {}
    return setmetatable({G=G,json=options.json or require("json"),context=Context.New(G),
        interval=options.interval or .25,enabled=options.enabled~=false,samples={},events={},stages={},
        listeners={},seq=0,deaths=0,errors=0,save_busy=false},M)
end
function M:Now() return self.G.GetTime() end
function M:Wall()
    local os=rawget(self.G,"os")
    return os and os.date and os.date("%Y-%m-%d %H:%M:%S") or "wall_clock_unavailable"
end
function M:Emit(kind,data)
    data=data or {};self.seq=self.seq+1
    data.schema=1;data.kind=kind;data.session=self.session;data.seq=self.seq
    data.time=self:Now();data.wall_time=self:Wall()
    data.test_build=self.test_build
    local raw=self.json.encode(data)
    if #raw<=2800 then
        self.G.print("[SCD] "..raw)
    else
        local a,b=1,0
        for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end
        local checksum=string.format("%08x",b*65536+a)
        local count=math.ceil(#raw/1000)
        for i=1,count do
            local part=raw:sub((i-1)*1000+1,i*1000):gsub(".",function(c) return string.format("%02x",c:byte()) end)
            self.G.print("[SCD] "..self.json.encode({schema=1,kind="record_chunk",session=self.session,seq=self.seq,
                encoding="hex-adler32-v1",chunk_index=i,chunk_count=count,checksum=checksum,data=part}))
        end
    end
    return data
end
function M:Safe(fn,...)
    local ok,why=pcall(fn,self,...)
    if ok then self.errors=0;return end
    self.errors=self.errors+1
    if self.errors==1 or self.errors==3 then self.G.print("[SCD_ERROR] "..tostring(why)) end
    if self.errors>=3 then self.enabled=false end
end
function M:Level()
    if self.manual_stage then return {source="manual",wave_label=self.manual_stage,route="手动标记"} end
    local c=self.context:Level(self.player)
    if c.source~="unavailable" then self.last_level=c;self.last_level_time=self:Now()
    elseif self.last_level and self:Now()-(self.last_level_time or 0)<=10 then
        local t={};for k,v in pairs(self.last_level) do t[k]=v end
        c=t;c.source="last_seen_astra_hud";c.age_seconds=self:Now()-self.last_level_time
    end
    return c
end
function M:UpdateStage()
    local c=self:Level();self.level=c;local key=stagekey(c)
    if not self.stage or self.stage.key~=key then
        if self.stage then self:Emit("stage_end",{stage=self.stage}) end
        self.stage={key=key,context=c,started=self:Now(),hits=0,loss_events=0,observed_hp_loss=0,healed=0,ping_sum=0,ping_count=0,ping_max=0}
        push(self.stages,self.stage,64)
        self:Emit("stage_start",{context=c})
    end
end
function M:Remember(kind,data)
    data=data or {};data.event=kind;data.time=self:Now();data.life_seconds=self:Now()-self.life_started
    data.stage_seconds=self.stage and self:Now()-self.stage.started or nil;data.context=self.level
    push(self.events,data,500)
    self:Emit(kind,{event=data})
end
function M:CheckHealth(snapshot,source,data)
    local hp,max=snapshot.hp,snapshot.max_hp
    if type(hp)~="number" or type(max)~="number" then return end
    if self.last_hp~=nil and self.last_max==max then
        local delta=hp-self.last_hp
        if delta<0 then
            self.stage.loss_events=self.stage.loss_events+1
            self.stage.observed_hp_loss=self.stage.observed_hp_loss-delta
            self.life_hp_loss=self.life_hp_loss-delta
            local event={time=self:Now(),context=self.level,hp_before=self.last_hp,hp_after=hp,observed_loss=-delta,
                source=source,overtime=data and data.overtime,cause=data and data.cause,
                note="客户端同步生命净下降；可能合并多次变化，不能当作单次攻击伤害",snapshot=snapshot}
            event.attribution=Analysis.Loss(event,self.events)
            self:Remember("hp_loss",event)
        elseif delta>0 then self.stage.healed=self.stage.healed+delta;self:Remember("heal",{amount=delta,hp_after=hp,source=source}) end
    elseif self.last_hp~=nil and self.last_max~=max then
        self:Remember("health_rebase",{old_max=self.last_max,new_max=max,hp=hp,note="最大生命改变，重设基准，不计受伤"})
    end
    self.last_hp=hp;self.last_max=max
end
function M:Attacked(data)
    if not self.enabled or not self.player or not self.was_alive or self.death_done then return end
    self:UpdateStage();local s=self.context:Snapshot(self.player,true)
    self.stage.hits=self.stage.hits+1
    self.life_hits=self.life_hits+1
    self:Remember("attacked",{notification=self.stage.hits,
        attacker=Context.Entity(data and data.attacker,self.player),redirected=data and data.redirected,
        server_damage=data and data.damage,snapshot=s,
        note="原版客户端受击通知；attacker为空表示未同步，附近敌人仅供排查"})
end
function M:Health(data)
    if not self.enabled or not self.player or not self.was_alive or self.death_done then return end
    self:UpdateStage();local s=self.context:Snapshot(self.player,true)
    s.time=self:Now()
    if s.hp and s.hp>0 and not s.ghost and not s.corpse then self.last_alive_snapshot=s end
    self:CheckHealth(s,"healthdelta",data)
    if s.hp and s.hp<=0 then self:Death("health_zero") end
end
function M:Death(signal)
    if not self.enabled or not self.was_alive or self.pending or self.death_done then return end
    self:UpdateStage()
    self.pending={at=self:Now(),wall_time=self:Wall(),signal=signal,stage=self.stage,context=self.level,
        predeath=self.last_alive_snapshot,snapshot=self.context:Snapshot(self.player,true)}
end
function M:Summary(report)
    local s=report.stage or {};local d=report.death or {};local pre=report.predeath or {}
    local gear=pre.gear or {};local near={}
    for _,e in ipairs(pre.nearby or {}) do near[#near+1]=e.prefab.."("..n(e.distance).."码)" end
    local lines={"# 战斗死亡反馈", "", "报告ID："..report.id,
        "时间："..(d.wall_time or self:Wall()).."（本机时间）；本次生命存活 "..n(report.life_seconds).." 秒。",
        "死亡关卡："..levelname(report.context).."；来源："..tostring(report.context.source).."；关卡已进行 "..n(report.stage_seconds).." 秒。",
        "关卡受击通知 "..tostring(s.hits or 0).." 次；生命下降记录 "..tostring(s.loss_events or 0).." 次；观测生命损失 "..n(s.observed_hp_loss).."；恢复 "..n(s.healed).."。",
        "本次生命累计受击 "..tostring(report.life_hits).." 次；观测生命损失 "..n(report.life_hp_loss).."。",
        "关卡平均延迟 "..n(s.ping_count and s.ping_count>0 and s.ping_sum/s.ping_count).." ms；最高 "..n(s.ping_max).." ms。",
        "角色："..tostring(pre.character or "unknown").."；接管："..tostring(pre.takeover_phase or "unknown").."；任务："..tostring(pre.task or "unknown"),
        "实际加载版本："..self.json.encode(report.test_build or {}).."；人物配置跑速："..n(pre.run_speed).."（非服务器实测移速）。",
        "当时阶段："..tostring(pre.arena_status or "未记录").."；战斗动作："..tostring(pre.combat_status or "未记录").."；平台："..tostring(pre.platform and pre.platform.prefab or "未记录"),
        "死亡前装备：手持 "..tostring(gear.HANDS and gear.HANDS.prefab or "unknown").."；头部 "..tostring(gear.HEAD and gear.HEAD.prefab or "unknown").."；身体 "..tostring(gear.BODY and gear.BODY.prefab or "unknown"),
        "附近敌人（候选）："..(#near>0 and table.concat(near,"、") or "未采到"),
        "死亡信号："..tostring(d.signal).."；同步死亡原因："..tostring(Analysis.Cause(report.death_cause) or "未提供"),""}
    local analysis=report.analysis or Analysis.Report(report)
    for _,section in ipairs({{"已确认观测",analysis.facts},{"关联线索（不是伤害定论）",analysis.clues},{"仍未知",analysis.unknowns}}) do
        lines[#lines+1]="## "..section[1];lines[#lines+1]=""
        if #section[2]==0 then lines[#lines+1]="- 无额外线索。" end
        for _,text in ipairs(section[2]) do lines[#lines+1]="- "..text end
        lines[#lines+1]=""
    end
    lines[#lines+1]="## 死亡前30秒事件";lines[#lines+1]=""
    for _,e in ipairs(report.recent_events) do
        local detail=e.event
        if e.event=="attacked" then detail="受击通知，攻击者="..tostring(e.attacker and e.attacker.prefab or "未同步")
        elseif e.event=="hp_loss" then
            local a=Analysis.Loss(e,report.recent_events)
            detail="净掉血 "..n(e.observed_loss).."，"..n(e.hp_before).." → "..n(e.hp_after).."；"..Analysis.Description(a)
            if #a.environment_clues>0 then detail=detail.."；线索："..table.concat(a.environment_clues,"、") end
            local near={}
            for _,v in ipairs(a.nearby_attacking) do near[#near+1]=v.prefab.."/"..v.animation.."第"..tostring(v.frame).."帧/"..n(v.distance).."码" end
            if #near>0 then detail=detail.."；附近攻击动作（非归因）："..table.concat(near,"、") end
            local hazards={}
            for _,v in ipairs(a.nearby_hazards) do hazards[#hazards+1]=v.prefab.."/"..v.animation.."/"..n(v.distance).."码" end
            if #hazards>0 then detail=detail.."；附近危险物（非归因）："..table.concat(hazards,"、") end
        end
        local relative=d.at-e.time
        lines[#lines+1]="- "..(relative>=0 and "死亡前 "..n(relative).." 秒：" or "死亡后 "..n(-relative).." 秒（结算同步）：")..detail
    end
    if report.recent_events_truncated then lines[#lines+1]="- 事件缓冲达到500条上限，较早事件已截断。" end
    lines[#lines+1]="";lines[#lines+1]="## 给合伙人的排查重点"
    if (s.hits or 0)>1 then lines[#lines+1]="- 核对连续受击期间的目标动作帧、撤离距离与装备切换（见JSON回放）；不能仅凭候选敌人认定攻击者。" end
    if (s.ping_max or 0)>150 then lines[#lines+1]="- 本关出现较高延迟，检查前摇余量及动作确认等待。" end
    if gear.HEAD and gear.HEAD.prefab=="empty" or gear.BODY and gear.BODY.prefab=="empty" then lines[#lines+1]="- 死亡前护甲存在空槽，核对拾取、耐久耗尽和换装恢复。" end
    lines[#lines+1]="- 对照同一报告ID的JSON：关卡信息、受击事件、生命变化和死亡前30秒采样。"
    lines[#lines+1]="- 这些是客户端观测，时间为本机收到同步的时间；同步可合并事件。真实伤害来源、精确命中时刻和根因需服务端日志确认。"
    return table.concat(lines,"\n")
end
function M:FinalizeDeath()
    local d=self.pending;if not d then return end
    self.pending=nil;self.death_done=true;self.deaths=self.deaths+1
    local now=d.at;local recent,frames={},{}
    for _,e in ipairs(self.events) do if e.time>=now-30 and e.time<=now+.3 then recent[#recent+1]=e end end
    for _,e in ipairs(self.samples) do if e.time>=now-30 and e.time<=now then frames[#frames+1]=e end end
    local classified=self.player and self.player.player_classified
    local cause=Analysis.Cause(classified and classified.deathcause and Context.Call(classified.deathcause,"value"))
    local report={id=self.session.."-death-"..self.deaths,test_build=self.test_build,context=d.context,death=d,stage=d.stage,
        predeath=d.predeath,death_cause=cause,life_seconds=now-self.life_started,stage_seconds=now-d.stage.started,
        life_hits=self.life_hits,life_hp_loss=self.life_hp_loss,recent_events=recent,recent_samples=frames,
        recent_events_truncated=#self.events==500 and self.events[1].time>now-30,
        note="客户端被动观测；未发送任何控制或聊天请求"}
    report.analysis=Analysis.Report(report)
    report.summary_text=self:Summary(report)
    self.last_report=report;self:Emit("death_report",{report=report})
    self:Save(report)
end
function M:Save(report)
    -- Stable local fallback in addition to client_log. Queue to prevent old async writes winning.
    self.save_next=self.json.encode(report)
    self:DrainSave()
end
function M:DrainSave()
    if self.save_busy or not self.save_next or not self.G.TheSim.SetPersistentString then return end
    self.save_busy=true;local text=self.save_next;self.save_next=nil
    local success=pcall(self.G.TheSim.SetPersistentString,self.G.TheSim,"shadow_combat_diary_latest",text,false,function(ok)
        self.save_busy=false
        self.G.print(ok and "[SCD_SAVE] 最新反馈已保存：shadow_combat_diary_latest" or "[SCD_SAVE_ERROR] 本地备份失败，请从client_log.txt导出")
        self:DrainSave()
    end)
    if not success then self.save_busy=false;self.G.print("[SCD_SAVE_ERROR] 本地备份失败，请从client_log.txt导出") end
end
function M:ResetLife()
    self.life_started=self:Now();self.samples={};self.events={};self.stages={};self.stage=nil
    self.pending=nil;self.death_done=false;self.last_hp=nil;self.last_max=nil;self.was_alive=false
    self.life_hits=0;self.life_hp_loss=0
    self.last_alive_snapshot=nil
end
function M:Bind(p)
    self.player=p;self.session=tostring((rawget(self.G,"os") or {}).time and self.G.os.time() or self:Now()).."-"..tostring(p.GUID).."-"..tostring(self:Now())
    self:ResetLife();self.last_level=nil;self.last_level_time=nil
    self.test_build=self.context:Build()
    self:Emit("session_start",{character=p.prefab,mod_version="1.2.0",sample_interval=self.interval,
        build=rawget(self.G,"APP_VERSION"),note="自动记录；不采集聊天、服务器地址、账号或密钥"})
    local handlers={attacked=function(_,data) self:Safe(self.Attacked,data) end,
        healthdelta=function(_,data) self:Safe(self.Health,data) end,
        death=function() self:Safe(self.Death,"death_event") end,
        onremove=function() self:Safe(self.Unbind,"player_removed") end}
    for event,fn in pairs(handlers) do p:ListenForEvent(event,fn);self.listeners[event]=fn end
end
function M:Unbind(reason)
    if self.pending then self:FinalizeDeath() end
    local p=self.player
    if p then for event,fn in pairs(self.listeners) do p:RemoveEventCallback(event,fn) end end
    self.listeners={};self.player=nil
    if p then self:Emit("session_end",{reason=reason}) end
end
function M:Tick()
    local p=self.G.ThePlayer
    if p~=self.player then self:Unbind("player_changed");if p and p.player_classified then self:Bind(p) end end
    if not self.player or not self.enabled then return end
    p=self.player;self:UpdateStage()
    local s=self.context:Snapshot(p,true);s.time=self:Now();s.context=self.level
    local dead=s.dead or s.ghost or s.corpse or (s.hp and s.hp<=0)
    if self.pending and not dead then self:FinalizeDeath() end
    if not dead and s.hp and s.hp>0 then
        if self.death_done then self:ResetLife();self:UpdateStage();self:Emit("revived",{}) end
        self.was_alive=true;self.last_alive_snapshot=s
    end
    if self.was_alive and not self.death_done then self:CheckHealth(s,"poll") end
    if dead then self:Death(s.ghost and "ghost_tag" or s.corpse and "corpse_tag" or "dead_or_zero") end
    if self.pending and self:Now()-self.pending.at>=.25 then self:FinalizeDeath() end
    if not dead and not self.death_done then
        push(self.samples,s,math.ceil(30/self.interval)+2)
        if type(s.ping_ms)=="number" then local t=self.stage;t.ping_sum=t.ping_sum+s.ping_ms;t.ping_count=t.ping_count+1;t.ping_max=math.max(t.ping_max,s.ping_ms) end
    end
end
function M:Toggle()
    if self.pending then self:FinalizeDeath() end
    self.enabled=not self.enabled
    if self.player then self:ResetLife();self.last_level=nil end
    self:Emit("recording",{enabled=self.enabled,note="切换后重新开始统计生命和关卡"})
end
function M:MarkStage(label)
    assert(label==nil or type(label)=="string" and #label<=200,"关卡标记须为200字节以内的文本，nil清除")
    self.manual_stage=label
    if self.player then self:UpdateStage() end
end
function M:Note(label)
    if self.player and self.enabled then self:Remember("manual_note",{text=tostring(label or "")}) end
end
function M:Export()
    if self.pending then self:FinalizeDeath() end
    if self.last_report then self:Emit("death_report",{report=self.last_report,export_again=true});self:Save(self.last_report);return end
    self:Emit("checkpoint",{context=self.level,stage=self.stage,note="尚无死亡报告；当前关卡快照"})
end
return M
