-- 清完首轮鬼手后的循环：等共享技能 -> 外侧落脚点骗A -> 控制前摇输出 -> 召唤清路 -> 绕圈清手。
-- 只使用实际动画、实体及合法路径，不猜血线，不按截图的屏幕坐标走。
local O=require("shadowself/control/weaver/observe")
local R=require("shadowself/control/weaver/route")
local S=require("shadowself/control/weaver/sanity")
local D=require("shadowself/control/weaver/debug")
local Ranged=require("shadowself/control/weaver/ranged")
local M={}
local function dist(a,b) return math.sqrt(a:DistSq(b)) end
local function set(w,name)
    local q=w.cycle
    if q.round~=name then q.round=name;q.round_since=GetTime();D.Emit(w,"round_stage",name) end
end
-- 当前静止Boss被虫子追到进食圈的最短时间；沿用原版两种虫子的移速。
local function foodtime(w)
    local bp=w.boss:GetPosition();local r=.3+(w.boss.GetPhysicsRadius and w.boss:GetPhysicsRadius(0) or .75)+1
    local earliest=math.huge
    for _,e in ipairs(w.minions) do if O.Live(e) and not O.Is(e,"hit") and not O.Is(e,"eaten") then
        earliest=math.min(earliest,math.max(0,dist(bp,e:GetPosition())-r)/(e.prefab=="stalker_minion1" and 3 or 1.5))
    end end
    return earliest
end
function M.KeepMask(w)
    return w.cycle and w.cycle.round=="control" and not S.ControlDue(w) and foodtime(w)>1 or false
end
function M.AllowsBoss(w)
    local q=w.cycle
    return q and (q.round=="wait_skill" or q.round=="control") or false
end
function M.SpawnLeft(w) return Ranged.BusyLeft(w) end
function M.Dodge(w,safe)
    local q=w.cycle;if not q or q.round~="corner" then return nil end
    local s=w.state;local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
    if q.round_dodge_cast==s.melee_started and q.round_dodge and R.Path(w,q.round_dodge,nil,true) then return q.round_dodge end
    local best,score,nextindex
    -- 红圈/黑圈是相对站位：优先沿相邻边撤，拒绝穿Boss或沿墙向场外退。
    for _,i in ipairs({q.index%4+1,(q.index+2)%4+1}) do
        local corner=q.corners[i];local d=dist(p,corner)
        if d>.1 then for _,length in ipairs({3,4,5,6}) do
            local n=math.min(length,d);local v=Vector3(p.x+(corner.x-p.x)*n/d,0,p.z+(corner.z-p.z)*n/d)
            local seconds=math.max(0,(32-s.frame)/30-w.c:Latency()-.15)
            local ray=R.Point(p,v,40)
            local dx,dz=(ray.x-p.x)/40,(ray.z-p.z)/40
            local x,z=p.x-bp.x,p.z-bp.z;local dot=x*dx+z*dz
            local needed=-dot+math.sqrt(math.max(0,dot*dot+safe*safe-x*x-z*z))
            if needed<=w.c:Speed()*.85*seconds and dist(v,bp)>=safe and R.Path(w,v,nil,true) and (not score or n<score) then best,score,nextindex=v,n,i end
        end end
    end
    if best then q.round_dodge=best;q.round_dodge_cast=s.melee_started;q.index=nextindex end
    return best
end
function M.Observe(w)
    local q=w.cycle;local s=w.state;if not q then return end
    if #w.channelers>0 then q.had_hands=true end
    if q.had_hands and #w.channelers==0 and not w:Shielded() and not (s.channeling or s.summoning)
        and (not q.round or q.round=="lap") then
        -- 最后一只必须确认死亡；普通清手仍每刀摘，只有最后一只保留当前护符接控制。
        local last=q.hand and not O.Live(q.hand) and q.sent and w.sanity_round and not w.sanity_round.restoring
        if last and q.round=="lap" and foodtime(w)>3.5 then set(w,"control")
        else
            q.round_snare=s.snare_started;q.round_spike=s.spike_count
            set(w,"wait_skill")
        end
    end
    if not q.round then return end
    if s.feasting then
        if q.round~="recover" then set(w,"recover") end
    elseif q.round=="recover" and q.feeding==0 and not (s.summoning or s.channeling) then
        set(w,"lap")
    end
    if q.round=="wait_skill" then
        local snare=s.snare_started and s.snare_started~=q.round_snare
        local spike=s.spike_count and s.spike_count~=q.round_spike
        if snare or spike then q.round_skill_seen=true end
        if q.round_skill_seen and not (s.anim=="attack1" or s.anim=="spike" or s.feasting) then
            q.round_skill_seen=nil;q.corner=nil;q.corner_reached=nil;q.corner_waypoint=nil;q.corner_next_plan=nil;set(w,"corner")
        end
    end
    if (q.round=="control" or q.round=="await_wave") and (s.channeling or s.summoning or #w.channelers>0) then
        q.hand=nil;q.sent=nil;q.spent=nil;q.control_seen=nil;set(w,"lap")
    end
    if q.round=="control" and s.anim=="control_pre" then q.control_seen=true end
    if q.round=="control" and q.control_seen and not s.controlling then
        q.control_seen=nil;set(w,"await_wave")
    end
end
function M.Tick(w)
    local q=w.cycle;local s=w.state;if not q or not q.round then return false end
    if q.round=="lap" or q.round=="recover" then return false end
    if q.round=="wait_skill" or q.round=="await_wave" then
        if w.sanity_round and S.Restore(w) then return true end
        if w:Shielded() then return false end
        return w:Attack(w.boss,"等实际共享技能／下一轮召唤，安全窗口输出")
    end
    if q.round=="corner" then
        if w.sanity_round and S.Restore(w) then return true end
        local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
        if not q.corner and GetTime()>=(q.corner_next_plan or 0) then
            q.corner_next_plan=GetTime()+.75
            local best
            for i,v in ipairs(R.FightCorners(w) or q.corners) do
                local waypoint,length=R.Waypoint(w,v)
                if waypoint then
                    local score=length*length
                    if not best or score<best then q.corner=v;best=score end
                end
            end
        end
        if not q.corner then
            -- 暂时没有合法转场路线仍保留corner；不能反复lap -> wait_skill重新等一轮技能。
            if GetTime()>=(q.corner_retry or 0) then
                q.corner_retry=GetTime()+.75;D.Emit(w,"corner_blocked","no_legal_segmented_route")
            end
            w:Hold("转场受阻，保留角落阶段等待合法退路",true);return true
        end
        if s.anim=="attack" then
            q.corner_melee=s.melee_started
            -- 真正躲完这次平A才戴护符；Threat优先负责前半段撤离。
            if s.frame>32+math.ceil(w.c:Latency()*30) and dist(p,bp)>5.15 and q.corner_melee==s.melee_started and q.corner_reached then
                if foodtime(w)>3.5 and S.CanPrepare(w) then set(w,"control")
                else q.corner=nil;set(w,"lap");return false end
            end
        else
            if p:DistSq(q.corner)>.25^2 then
                q.corner_reached=nil
                if not q.corner_waypoint or p:DistSq(q.corner_waypoint)<.5^2
                    or not R.Path(w,q.corner_waypoint,nil,true) or GetTime()>=(q.corner_plan or 0) then
                    q.corner_waypoint=R.Waypoint(w,q.corner);q.corner_plan=GetTime()+.75
                end
                if q.corner_waypoint then return w:Move(q.corner_waypoint,"分段绕障碍去红圈落脚点，等织影跟上",nil,true) end
                q.corner=nil;w:Hold("角落路线变化，重新选择可达落脚点",true);return true
            end
            q.corner_reached=true
            if dist(p,bp)>2.7 then w:Hold("红圈等织影走到近身黑圈，不提前戴护符",true);return true end
            w:Hold("外侧落脚点等真实普攻起手",true);return true
        end
    end
    if q.round=="control" then
        -- 没血量同步就不假定控制已经解锁；观察不到起手不能一直戴着等。
        if not q.control_seen and not s.controlling and GetTime()-q.round_since>3 then
            set(w,"await_wave")
            if w.sanity_round and S.Restore(w) then return true end
            return w:Attack(w.boss,"未观察到控制起手，恢复装备继续输出等下一轮")
        end
        if not S.CanPrepare(w) or foodtime(w)<=1 or s.feasting then
            if w.sanity_round and S.Restore(w) then return true end
            q.corner=nil;set(w,"lap");return false
        end
        if S.ControlDue(w) or q.control_seen and w.sanity_round and w.sanity_round.restoring then
            if w.sanity_round and S.Restore(w) then return true end
            return w:Attack(w.boss,"控制前摇临界点已摘护符，继续安全输出")
        end
        if S.Prepare(w) then return true end
        return w:Attack(w.boss,"临时低SAN诱控制，前摇输出，临界点恢复")
    end
    return false
end
return M
