-- 只读取客户端动画、标签和网络变量；技能计时是保守预测，不读取服务端sg/timer。
local M={}
local names={"idle","walk_pre","walk_loop","walk_pst","attack","attack1","spike","control_pre","control_loop","control_pst",
    "taunt3_pre","taunt3_loop","taunt3_pst","summon_pre","summon_loop","summon_pst",
    "taunt2_pre","taunt2_loop1","taunt2_loop2","taunt2_loop3","taunt2_pst"}
local cds={snare=10,spikes=8,mindcontrol=15,channelers=20,minions=20}
local shared={"snare","spikes","mindcontrol"}
function M.Live(e)
    return e and e:IsValid() and not e:HasTag("INLIMBO") and not e:HasTag("isdead")
        and not e:HasTag("dead") and not e:HasTag("NOCLICK")
end
function M.IsMinion(e) return e and (e.prefab=="stalker_minion1" or e.prefab=="stalker_minion2") end
function M.Animation(e)
    local a=e and e.AnimState
    if a then for _,name in ipairs(names) do if a:IsCurrentAnimation(name) then
        return name,a:GetCurrentAnimationFrame() or 0
    end end end
    return "other",0
end
function M.Is(e,name) return e and e.AnimState and e.AnimState:IsCurrentAnimation(name) end
-- appear动画结束时结算一次伤害；impact残留不持续伤人，保留短暂网络余量即可。
function M.SpikeDanger(e,lag)
    if not M.Live(e) or M.Is(e,"empty") then return false end
    if M.Is(e,"appear") then
        local a=e.AnimState;local length=a and a.GetCurrentAnimationLength and a:GetCurrentAnimationLength()
        if type(length)=="number" and length>0 then
            return length-(a:GetCurrentAnimationFrame() or 0)/30<=.6+(lag or 0)
        end
    end
    if M.Is(e,"impact") then
        local a=e.AnimState
        return not a or not a.GetCurrentAnimationFrame or a:GetCurrentAnimationFrame()<=math.ceil((lag or 0)*30)+2
    end
    return true
end
function M.SolidCage(e)
    -- fossil_pst是骨柱长出的动画，不是消退！一直到NOCLICK/物理关闭才失去碰撞。
    return e and e.prefab=="fossilspike" and M.Live(e) and not M.Is(e,"empty")
        and (not e.Physics or not e.Physics.IsActive or e.Physics:IsActive())
end
function M.Controlled(p)
    local pc=p.components and p.components.playercontroller
    return M.Is(p,"mindcontrol_pre") or M.Is(p,"mindcontrol_loop") or M.Is(p,"mindcontrol_pst")
        or pc and pc.IsEnabled and not pc:IsEnabled()
end
function M.Sanity(p)
    local s=p.replica and p.replica.sanity
    return s and s.GetPercentNetworked and s:GetPercentNetworked() or nil
end
function M.Shield(boss)
    local n=boss and boss._hasshield
    if n and n.value then return n:value() end
    return nil -- 未同步与确认无盾必须区分。
end
function M.New() return {phase=1,ready={},minions={},previous_shield=nil} end
local function delay(s,ability,now)
    -- 原版是同一个maxdt同时加到另外两个计时器，不是各自截到半CD。
    -- 客户端未观测到的计时按已就绪估计；ready仍是估计，实际起手始终优先。
    local remaining={};local maxdt=0
    for _,name in ipairs(shared) do if name~=ability then
        local left=math.max(0,(s.ready[name] or now)-now)
        remaining[name]=left;maxdt=math.max(maxdt,cds[name]*.5-left)
    end end
    for name,left in pairs(remaining) do s.ready[name]=now+left+maxdt end
end
function M.Update(s,boss,now)
    local name,f=M.Animation(boss)
    local changed=name~=s.anim or f+2<(s.frame or 0)
    local fresh=name~=s.anim -- 循环动画回零不是新一次召唤。
    if name=="attack" and changed then s.melee_started=now-f/30 end
    if fresh then
        local ability=name=="attack1" and "snare" or name=="spike" and "spikes"
            or name=="control_pre" and "mindcontrol" or name=="taunt3_pre" and "channelers"
            or name=="summon_pre" and "minions"
        if ability then
            s.ready[ability]=now-f/30+cds[ability]
            if ability=="spikes" then s.spike_shared_at=now-f/30+6/30;s.spike_count=(s.spike_count or 0)+1 end
        end
        if name=="attack1" then s.snare_started=now-f/30;s.snare_result=nil end
        if name=="control_loop" then s.control_observed=true;delay(s,"mindcontrol",now) end
        if name=="summon_pre" then s.summon_started=now-f/30 end
    end
    -- 只有亲眼见到pre才知道是不是第一遍loop；中途接管不能凭第一眼loop多借一整段时间。
    if fresh and name=="summon_pre" then s.summon_count_known=true;s.summon_loops=0 end
    if name=="summon_loop" and changed and s.summon_count_known then s.summon_loops=s.summon_loops+1 end
    if name:find("summon_",1,true)~=1 then s.summon_count_known=nil;s.summon_loops=nil end
    -- SpawnSpikes在第6帧才真正重置/推迟共享组，不能从动画起手提前算。
    if s.spike_shared_at and now>=s.spike_shared_at then
        delay(s,"spikes",s.spike_shared_at);s.spike_shared_at=nil
    end
    -- MindControl在每帧调用ResetAbilityCooldown，不能从control_pre起手算完15秒。
    if name=="control_loop" then s.ready.mindcontrol=now+15 end
    local shield=M.Shield(boss)
    if shield~=nil then
        if s.previous_shield==true and not shield then s.ready.channelers=now+20 end
        s.previous_shield=shield
    end
    if name:find("control_",1,true)==1 or name:find("taunt3_",1,true)==1
        or name:find("summon_",1,true)==1 or name:find("taunt2_",1,true)==1 or shield then s.phase=2 end
    local health=boss.replica and boss.replica.health
    -- 普通远程Boss的health replica会返回默认100/100，不能冒充真实血量。
    local maximum=health and health.Max and health:Max()
    local current=maximum and maximum>1000 and health.GetCurrent and health:GetCurrent()
    if type(current)=="number" and current>0 then
        s.health=current
        if current<((TUNING and TUNING.STALKER_ATRIUM_PHASE2_HEALTH) or 10000) then s.phase=2 end
    end
    s.anim=name;s.frame=f;s.shield=shield
    s.feasting=name:find("taunt2_",1,true)==1 and name~="taunt2_pst"
    s.summoning=name:find("summon_",1,true)==1
    s.channeling=name:find("taunt3_",1,true)==1
    s.controlling=name:find("control_",1,true)==1
    return changed
end
function M.Minions(s,entities,now)
    local retained={};local events={}
    for _,e in ipairs(entities) do if M.IsMinion(e) then
        local old=s.minions[e]
        local why=M.Is(e,"eaten") and "consumed" or M.Is(e,"hit") and "killed" or nil
        if why and not (old and old.reported) then
            events[#events+1]={entity=e,reason=why}
            -- 普通死亡每只都会刷新20秒；吞食不走health death事件。
            if why=="killed" then s.ready.minions=now+20 end
        end
        retained[e]={reported=why~=nil or old and old.reported}
    end end
    for e,old in pairs(s.minions) do if not retained[e] and not old.reported then
        events[#events+1]={entity=e,reason="unknown"};s.minions_uncertain=true
        -- 失去可见性/自然移除均不能冒充确认冷却开始。
    end end
    s.minions=retained
    return events
end
function M.SnareResult(s,caught,now)
    if s.snare_result~=nil then return end
    s.snare_result=caught
    if caught then delay(s,"snare",now) end
end
function M.ReadyIn(s,key,now) return math.max(0,(s.ready[key] or now)-now) end
return M
