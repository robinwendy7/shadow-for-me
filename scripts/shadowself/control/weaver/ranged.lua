-- 法杖弹道生命周期：提交动作不是命中；零SAN覆盖首发与弹跳，真实危险期限优先。
local A=require("shadowself/control/actions")
local O=require("shadowself/control/weaver/observe")
local R=require("shadowself/control/weaver/route")
local S=require("shadowself/control/weaver/sanity")
local D=require("shadowself/control/weaver/debug")
local M={}
local function distance(a,b)return math.sqrt(a:DistSq(b)) end
function M.Item(w)
    local selected;local q=w.cycle
    for _,e in ipairs(A.Items(w.c.player)) do
        if e:IsValid() and e.prefab=="staff_lunarplant" and not e:HasTag("broken") then
            if q and q.staff==e then return e end
            selected=selected or e
        end
    end
    if q then q.staff=selected end
    return selected
end
function M.GhostReady(w,e)
    if not O.Live(e) or e:HasTag("notarget") or O.Is(e,"disappear") then return false end
    -- 所有清手入口使用同一个真实疯狂状态，不能用15%血条近似。
    if not S.Ready(w) then return false end
    local combat=e.replica and e.replica.combat
    return not combat or not combat.CanBeAttacked or combat:CanBeAttacked(w.c.player)
end
function M.BusyLeft(w)
    local s=w.state
    if not (s.channeling or s.summoning) then return 0 end
    local length=w.boss.AnimState:GetCurrentAnimationLength()
    local left=math.max(0,length-s.frame/30)
    if s.anim=="summon_pst" then return math.max(0,math.min(left,(7-s.frame)/30)) end
    -- 第一次召虫loop必接同长第二遍；不猜受攻击后还有多少后续循环。
    if s.anim=="summon_loop" and s.summon_count_known and s.summon_loops==1 then left=left+length end
    -- 只借源码保证存在的后续段；taunt3也可能是skullache，二者均经过loop。
    -- 未观察过长度时用该动画最后一个原版FrameEvent作下界，不猜额外循环。
    s.animation_lengths=s.animation_lengths or {}
    s.animation_lengths[s.anim]=length
    local known=s.animation_lengths
    if s.anim=="taunt3_pre" then left=left+(known.taunt3_loop or 35/30)
    elseif s.anim=="summon_pre" then left=left+2*(known.summon_loop or 5/30) end
    return left
end
function M.EscapeBudget(w)
    local capture,resolve=w:Ranges()
    local needed=math.max(0,math.min(capture-.1,resolve-.1)-distance(w.c.player:GetPosition(),w.boss:GetPosition()))
    return needed/math.max(1,w.c:Speed()*.65)+w.c:Latency()+.35
end
local function reserve(w)
    local now=GetTime();local s=w.state
    local locked=M.BusyLeft(w)
    if s.anim=="attack" then locked=math.max(0,(63-s.frame)/30) end
    if s.ready.snare and O.ReadyIn(s,"snare",now)>locked+.5 then return w.c:Latency()+.35 end
    return M.EscapeBudget(w)
end
function M.SubmitBudget(w,e)
    local launch=8/30+2*w.c:Latency()+.15
    -- 不需要疯狂状态的虫子弹道，确认留足抛出时间后可以持手杖移动；不能把它和鬼手摘护符混为一谈。
    if e.prefab~="shadowchanneler" and not S.Wearing(w) then return launch end
    return launch+distance(w.c.player:GetPosition(),e:GetPosition())/(O.IsMinion(e) and 12 or 15)
end
function M.CanLaunch(w,e)
    local first=M.SubmitBudget(w,e)
    return M.SafeUntil(w,e)>GetTime()+first+.15
end
function M.SafeUntil(w,target)
    local s=w.state;local now=GetTime();local busy=M.BusyLeft(w)
    local function foodgap(locked)
        if not O.IsMinion(target) or S.Wearing(w) or not s.ready.snare then return 0 end
        -- 虫子不需要护符。Boss解除busy后还须走到近身才能普攻；CD充足才借这段真实距离。
        -- 骨牢所需回程预算保留，未知CD与鬼手均不借用。
        local gap=math.max(0,(distance(w.c.player:GetPosition(),w.boss:GetPosition())-5.5)/4.2)
        return math.max(0,math.min(gap,O.ReadyIn(s,"snare",now)-locked-M.EscapeBudget(w)-.15))
    end
    if busy>0 then
        local extra=foodgap(busy)
        return now+busy+extra-(extra>0 and w.c:Latency()+.12 or reserve(w))
    end
    if s.controlling then
        if s.anim~="control_pre" then return now end
        return now+w.boss.AnimState:GetCurrentAnimationLength()-s.frame/30-math.max(.4,w.c:Latency()*2+.2)
    end
    if s.anim=="attack" then
        if s.frame<=32+math.ceil(w.c:Latency()*30)
            and distance(w.c.player:GetPosition(),w.boss:GetPosition())<5.15 then return now end
        -- 无虫时允许利用3秒普攻间隔的后半段；真实新起手/控制仍由监督器抢占。
        -- 有虫时不借busy后的时间，避免低SAN让Boss停下控制而被虫群追上。
        local duration=#w.minions==0 and ((TUNING and TUNING.STALKER_ATRIUM_ATTACK_PERIOD) or 3) or 63/30
        return s.melee_started+duration-reserve(w)
    end
    if s.feasting then
        -- 所有吞食清虫入口都享有当前可见busy，不限等牢带root_work。
        -- eat_idle可能立刻退出，但仍须完成当前动画及pst的8帧busy。
        local length=w.boss.AnimState:GetCurrentAnimationLength()
        local left=math.max(0,length-s.frame/30)+8/30
        return now+left+foodgap(left)-w.c:Latency()-.12
    end
    if s.anim=="spike" or s.anim=="attack1" and s.frame<=30 then return now end
    local d=distance(w.c.player:GetPosition(),w.boss:GetPosition())
    local safe=(d-5.5)/4.2-w.c:Latency()-.35
    if s.ready.snare then safe=math.min(safe,O.ReadyIn(s,"snare",now)-.5) else safe=0 end
    return now+math.max(0,safe)
end
function M.Window(w)
    return M.Item(w)~=nil and M.BusyLeft(w)>0 and M.SafeUntil(w)-GetTime()>.85
end
function M.Sent(w,e,held)
    if not held or held.prefab~="staff_lunarplant" then return end
    local now=GetTime();local d=distance(w.c.player:GetPosition(),e:GetPosition())
    local hat=w.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
    local hops=hat and hat.prefab=="lunarplanthat" and ((TUNING and TUNING.STAFF_LUNARPLANT_SETBONUS_BOUNCES) or 7)
        or ((TUNING and TUNING.STAFF_LUNARPLANT_BOUNCES) or 5)
    -- SG普通攻击8帧；初速15。移动虫子按最高3速度预留追踪飞行。
    local first=8/30+d/(O.IsMinion(e) and 12 or 15)+2*w.c:Latency()+.15
    local moving=#w.minions>0
    local chain=(hops-1)*((moving and 25 or 12)/10+.1)
    local ghosts={};for _,g in ipairs(w.channelers)do ghosts[#ghosts+1]=g end
    if O.IsMinion(e) and w.light_sent and w.light_sent.target==e then w.light_sent.impact_until=now+first end
    w.staff_action={phase="flight",target=e,submitted=now,first_until=now+first,until_time=now+first+chain,
        ghosts=ghosts,launch_until=now+8/30+2*w.c:Latency()+.15,needs_mask=S.Wearing(w) or e.prefab=="shadowchanneler"}
    D.Emit(w,"ranged_pending",string.format("target=%s first=%.2f chain=%.2f",tostring(e.GUID),first,chain))
end
function M.Pending(w)
    local flight=w.staff_action;if not flight or flight.phase~="flight" then return false end
    local now=GetTime();local reason
    if O.Controlled(w.c.player) or M.SafeUntil(w,flight.target)<=now then reason="safety_deadline"
    elseif not flight.needs_mask and now>=flight.launch_until then reason="launch_budget_elapsed_worm_chain_continues_without_mask"
    elseif now>=flight.until_time then reason="flight_budget_elapsed_retry_unconfirmed"
    elseif flight.needs_mask and now>=flight.first_until and #flight.ghosts>0 then
        local done=true
        for _,e in ipairs(flight.ghosts)do
            -- notarget、透明或SAN恢复都不是死亡证据。
            if e:IsValid() and not e:HasTag("NOCLICK") and not e:HasTag("isdead") and not e:HasTag("dead") and not O.Is(e,"disappear") then done=false;break end
        end
        if done then reason="all_snapshot_ghosts_confirmed_dead" end
    end
    if reason then
        if w.cycle then w.cycle.spent=true end
        D.Emit(w,"ranged_complete",reason);w.staff_action=nil;return false
    end
    return true
end
-- 单一动作状态：approach -> prepare -> flight -> 完成/恢复。
-- cycle/round只提供目标与窗口，不再各自保存法杖攻击、换装或弹道状态。
local function alive(e)
    return O.Live(e) and not e:HasTag("notarget") and not O.Is(e,"disappear")
        and not O.Is(e,"hit") and not O.Is(e,"eaten")
end
local function setupbudget(w,e,item)
    local now=GetTime();local inv=w.c.player.replica.inventory
    local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)~=item
    local mask=e.prefab=="shadowchanneler" and not S.Ready(w)
    local wait=math.max(0,(w.next_equip or now)-now);local ack=w.c:Latency()+.12
    if w.support and w.support.slot then wait=0 end -- 已发出的换装只等回执，不重等下一次限流。
    if hand and mask then return wait+.4+ack end
    if hand or mask then return wait+ack end
    return 0
end
function M.Interrupt(w,reason)
    if not w.staff_action then return end
    D.Emit(w,"staff_cancel",reason);w.staff_action=nil;w:CancelSupport()
    if w.sanity_round then w.sanity_round.restoring=true end
end
function M.Keep(w)
    local job=w.staff_action;if not job then return false end
    if job.phase=="flight" then return M.Pending(w) end
    return job.phase=="prepare" and alive(job.target) and not w.state.controlling
        and M.SafeUntil(w,job.target)>GetTime()+M.SubmitBudget(w,job.target)+.15
end
function M.Allowed(w,e)
    local job=w.staff_action
    return job and job.target==e and (job.phase=="flight" and M.Pending(w)
        or job.phase=="prepare" and M.CanLaunch(w,e)) or false
end
local function incoming(w,e)
    local sent=w.light_sent
    return sent and sent.target==e and sent.impact_until and GetTime()<sent.impact_until
end
-- 优先消灭Boss身边的食物，玩家距离只用于同距排序；不把扫描顺序当威胁顺序。
function M.FoodTarget(w)
    local bp=w.boss:GetPosition();local p=w.c.player:GetPosition();local best,bd,pd
    for _,e in ipairs(w.minions)do if alive(e) and not incoming(w,e) then
        local d=bp:DistSq(e:GetPosition());local near=p:DistSq(e:GetPosition())
        if not bd or d<bd-.001 or math.abs(d-bd)<=.001 and near<pd then best,bd,pd=e,d,near end
    end end
    return best
end
-- 直射不到最危险的虫时，用射程内最靠Boss且能弹入该虫群的一只作首发。
-- 原版弹跳由服务器选目标，这里只保证入口相连，不把可能弹到当成击杀。
function M.FoodShot(w,food)
    if not food then return nil end
    local p=w.c.player:GetPosition()
    if distance(p,food:GetPosition())<=7.5 then return food end
    local bp=w.boss:GetPosition();local best,bd
    for _,e in ipairs(w.minions)do if alive(e) and not incoming(w,e) and distance(p,e:GetPosition())<=7.5
        and e:GetPosition():DistSq(food:GetPosition())<=11*11 then
        local d=bp:DistSq(e:GetPosition())
        if not bd or d<bd then best,bd=e,d end
    end end
    return best or food
end
function M.Work(w,preferred,reason)
    local q=w.cycle;local item=M.Item(w);local job=w.staff_action
    if job and job.phase=="flight" then return M.Tick(w) end
    if not item or not q or w.state.controlling then M.Interrupt(w,"no_staff_or_control");return false end
    local now=GetTime();local p=w.c.player:GetPosition()
    local food=(w.state.feasting or O.IsMinion(preferred) or job and O.IsMinion(job.target)) and M.FoodTarget(w)
    if food then
        preferred=M.FoodShot(w,food)
        if job and job.target.prefab=="shadowchanneler" and (w.state.feasting or q.food) then
            M.Interrupt(w,"feeding_food_before_uncommitted_ghost");job=nil
        end
        if not job and w.sanity_round and S.Restore(w) then return true end
    end
    local until_time=M.SafeUntil(w,food or preferred or job and job.target)
    local function approach(e)
        if w.rebait or w.lure_until and not w.state.feasting then return nil end
        if job and job.point and now<(job.step_until or 0) and p:DistSq(job.point)>.3^2
            and R.Path(w,job.point,nil,true) then return job.point end
        local point=R.Point(e:GetPosition(),p,7.1)
        local waypoint,length
        if R.Path(w,point,nil,true) then waypoint=point;length=distance(p,point)
        else waypoint,length=R.Waypoint(w,point) end
        -- 目标周围的径向射击点可能在门/雕像里面；换一个实际可站的射击方向。
        if not waypoint then
            local ep=e:GetPosition();local angle=math.atan2(p.z-ep.z,p.x-ep.x)
            for i=1,12 do
                local a=angle+math.ceil(i/2)*math.pi/12*(i%2==0 and -1 or 1)
                local candidate=Vector3(ep.x+math.cos(a)*7.1,0,ep.z+math.sin(a)*7.1)
                if R.Path(w,candidate,nil,true) then point=candidate;waypoint=candidate;length=distance(p,candidate);break end
            end
        end
        local retreat=0
        if w.lure_until then
            local capture,resolve=w:Ranges()
            retreat=math.max(0,math.min(capture-.1,resolve-.1)-distance(point,w.boss:GetPosition()))/math.max(1,w.c:Speed()*.65)+w.c:Latency()+.35
        end
        if not waypoint then return nil end
        local speed=math.max(1,w.c:Speed()*.65)
        if now+length/speed+setupbudget(w,e,item)+M.SubmitBudget(w,e)+.15+retreat<until_time then return waypoint end
        -- 接近和出手是两个动作，跨吞食/召虫循环逐段接近，不能要求同一圈完成整条路。
        -- 每一步仍留在普攻范围外，且在下一次可能的骨牢前留足回识别带的时间。
        if not (w.state.feasting or w.state.summoning or w.state.channeling) then return nil end
        local seconds=until_time-now-w.c:Latency()-.1
        if seconds<.15 then return nil end
        local step=R.Point(p,waypoint,math.min(distance(p,waypoint),speed*seconds,2))
        if distance(step,w.boss:GetPosition())<5.5 or not R.Path(w,step,nil,true) then return nil end
        local capture,resolve=w:Ranges()
        local back=math.max(0,math.min(capture-.1,resolve-.1)-distance(step,w.boss:GetPosition()))/speed+w.c:Latency()+.35
        local castleft=math.max(until_time-now,O.ReadyIn(w.state,"snare",now))
        if distance(p,step)/speed+back+.15>=castleft then return nil end
        return step
    end
    local function staging(e)
        -- 换武器和抛弹分开验算；短循环不能要求从空手到出弹一次全塞完，导致永远不换装。
        return w.state.feasting and O.IsMinion(e) and alive(e) and not incoming(w,e) and distance(p,e:GetPosition())<=7.5
            and now+setupbudget(w,e,item)+.1<until_time
    end
    local function fits(e,started)
        return alive(e) and not incoming(w,e) and distance(p,e:GetPosition())<=7.5
            and (e.prefab~="shadowchanneler" or S.CanPrepare(w))
            and now+(started and 0 or setupbudget(w,e,item))+M.SubmitBudget(w,e)+.15<until_time
    end
    if job and not alive(job.target) then M.Interrupt(w,"target_finished");job=nil end
    if job and job.phase=="prepare" and not fits(job.target,true) and not staging(job.target) then
        M.Interrupt(w,"preparation_deadline");return false
    end
    if job and job.phase=="approach" then
        -- 接近途中出现可用弹跳入口就原地准备；未发出的动作无需继续追超射程旧目标。
        if food and preferred~=job.target and (fits(preferred) or staging(preferred)) then
            job.target=preferred;job.phase="prepare"
        end
    end
    if job and job.phase=="approach" then
        if w.rebait or w.lure_until and not w.state.feasting then M.Interrupt(w,"cage_route_priority");return false end
        if distance(p,job.target:GetPosition())>7.5 then
            local waypoint=approach(job.target)
            if not waypoint then M.Interrupt(w,"no_safe_approach_window");return false end
            if job.point~=waypoint then job.step_until=now+.25 end
            job.point=waypoint
            return w:Move(job.point,"法杖优先织影身边食物，沿合法路线接近射程",nil,true)
        end
        if not fits(job.target) then M.Interrupt(w,"arrived_without_window");return false end
        job.phase="prepare"
    end
    if not job then
        if q.perimeter and not preferred then return false end
        local target
        if preferred and (fits(preferred) or staging(preferred)) then target=preferred end
        if not target and not food and not q.perimeter then for _,e in ipairs(w.channelers)do if fits(e) then target=e;break end end end
        if not target and not food and not q.perimeter then
            local closest=M.FoodTarget(w);if closest and fits(closest) then target=closest end
        end
        if not target then
            if preferred and alive(preferred) and distance(p,preferred:GetPosition())>7.5 and (not w.lure_until or w.state.feasting) and not w.rebait then
                local waypoint=approach(preferred)
                if waypoint then
                    w.staff_action={phase="approach",target=preferred,weapon=item,point=waypoint}
                    return M.Work(w,preferred,reason)
                end
            end
            return false
        end
        job={phase="prepare",target=target,weapon=item};w.staff_action=job
        D.Emit(w,"staff_prepare",string.format("target=%s food=%s relay=%s boss_distance=%.2f player_distance=%.2f budget=%.2f available=%.2f",tostring(target.GUID),
            food and tostring(food.GUID) or "none",tostring(food~=nil and food~=target),distance(w.boss:GetPosition(),target:GetPosition()),distance(p,target:GetPosition()),
            setupbudget(w,target,item)+M.SubmitBudget(w,target)+.15,until_time-now))
    end
    local target=job.target
    if w:Equip(job.weapon,EQUIPSLOTS.HANDS,"法杖固定目标，确认武器") then return true end
    if not M.CanLaunch(w,target) then
        w:Hold("法杖已备好，等当前吞食循环的可抛弹帧")
        return true
    end
    if target.prefab=="shadowchanneler" then
        if S.Prepare(w) then return true end
        if not M.GhostReady(w,target) then w:Hold("法杖固定目标，等待疯狂状态生效");return true end
    end
    local previous=w.light_sent
    local result=w:Hand(target,reason or "法杖清手／虫，等待真实弹道结算")
    if previous~=w.light_sent then q.hand=target;q.sent=w.light_sent.time end -- 仅留最后一手的战果记录。
    return result
end
function M.Approach(w,target,point)
    if not w.staff_action then w.staff_action={phase="approach",target=target,weapon=M.Item(w),point=point} end
    return M.Work(w)
end
function M.Tick(w)
    local job=w.staff_action;if not job then return false end
    if job.phase~="flight" then return M.Work(w) end
    if not M.Pending(w) then return false end
    w:Hold("法杖弹道在途，保留SAN至命中或安全截止")
    return true
end
return M
