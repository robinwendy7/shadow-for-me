-- 二阶段战术层：决定清脚下食物、外围路线与近战窗口；控制输出轮次由round管理。
-- 有法杖只向ranged提出目标/接近位置，不在这里换法杖或管理弹道。
local O=require("shadowself/control/weaver/observe")
local R=require("shadowself/control/weaver/route")
local S=require("shadowself/control/weaver/sanity")
local D=require("shadowself/control/weaver/debug")
local Ranged=require("shadowself/control/weaver/ranged")
local Round=require("shadowself/control/weaver/round")
local M={}
local function distance(a,b) return math.sqrt(a:DistSq(b)) end
local function alive(e) return O.Live(e) and not e:HasTag("notarget") and not O.Is(e,"hit") and not O.Is(e,"eaten") end
-- 定位与交互分开：高SAN不影响已同步鬼手的固定坐标，不用“现在能否选中”决定去哪里。
local function located(e) return O.Live(e) and e.prefab=="shadowchanneler" and not O.Is(e,"disappear") end
local function stage(w,name)
    local q=w.cycle
    if q.stage~=name then
        q.stage=name;q.light=nil;if name=="clear_feed" then q.cleanup_started=nil end
        D.Emit(w,"cycle_stage",name)
    end
end
local function restore(w) return w.sanity_round and S.Restore(w) end
local function staff(w) return Ranged.Item(w) end
local function reach(w)
    local held=w.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if held and held.prefab=="staff_lunarplant" and not held:HasTag("broken") then return 7.5 end
    local c=w.c.player.replica.combat
    return math.max(1,(c and c.GetAttackRangeWithWeapon and c:GetAttackRangeWithWeapon() or 2)-.3)
end
local function feeding(w)
    -- 原版ShouldFeast: .3 + Boss物理半径 + 1；额外留接近余量。
    local bp=w.boss:GetPosition();local r=.3+(w.boss.GetPhysicsRadius and w.boss:GetPhysicsRadius(0) or .75)+(w.state.feasting and 5 or 1)+.75
    local best,score,n= nil,nil,0
    for _,e in ipairs(w.minions) do if alive(e) and bp:DistSq(e:GetPosition())<=r*r then
        n=n+1
        -- 先清贴身食物，避免把最靠近Boss的一只留到收尾才杀。
        local d=bp:DistSq(e:GetPosition())*4+w.c.player:GetPosition():DistSq(e:GetPosition())*.1
        if not score or d<score then best,score=e,d end
    end end
    return best,n
end
function M.SidePoints(w,center)
 center=center or w.center or w.home or w.boss:GetPosition();local points={}
 for _,v in ipairs({{10.5,10.5},{-10.5,10.5},{-10.5,-10.5},{10.5,-10.5}})do
  local chosen
  for _,offset in ipairs({0,-1,1,-2,2})do
   local p=Vector3(center.x+v[1]+offset,0,center.z+v[2])
   if R.InArena(w,p)and R.Passable(p)and R.FenceClear(w,p)then chosen=p;break end
  end
  points[#points+1]=chosen or Vector3(center.x+v[1],0,center.z+v[2])
 end
 local pair=R.FightCorners(w)
 if pair then for _,p in ipairs(pair)do
  local best,index
  for i,q in ipairs(points)do local d=p:DistSq(q);if not best or d<best then best,index=d,i end end
  points[index]=p
 end end
 table.sort(points,function(a,b)return math.atan2(a.z-center.z,a.x-center.x)<math.atan2(b.z-center.z,b.x-center.x)end)
 return points
end
function M.Observe(w)
    local s=w.state;local q=w.cycle
    -- 只认技能/实体，不以客户端默认100血或者攻击次数启动二阶段。
    if not q and (s.channeling or s.summoning or s.feasting or s.controlling or s.shield==true or #w.channelers>0 or #w.minions>0) then
        q={stage="patrol",center=w.center or w.home or w.boss:GetPosition(),perimeter=true};w.cycle=q
        q.corners=M.SidePoints(w,q.center)
        local best;local p=w.c.player:GetPosition()
        for i,v in ipairs(q.corners) do local d=p:DistSq(v);if not best or d<best then q.index=i;best=d end end
        D.Emit(w,"cycle_stage","observe_actual_phase2_plan_perimeter")
    end
    if not q then return end
    q.perimeter=true
    if (q.round=="lap" or not q.round) and w.c.player:GetPosition():DistSq(q.corners[q.index])<.7^2 then
        q.index=q.index%#q.corners+1;q.route_waypoint=nil;q.route_next=nil
    end
    q.route_goal=q.corners[q.index]
    if s.channeling and not q.was_channeling then
        if w.spawn_lure then
            w.lure_until=nil;w.spawn_lure=nil;w.rebait=nil;w.bait_hold=nil;w.bait_point=nil
            w.escape_point=nil;w.escape_turn=nil;w.next_escape=nil
        end
        q.round="lap";q.route_waypoint=nil;q.route_next=nil
        q.await_snare=true;q.spawn_snare=s.snare_started;q.spawn_spike=s.spike_count;q.shared_seen=nil
        D.Emit(w,"lap_plan","channeler_windup_plan_outer_route")
    end
    local first_loop=s.anim=="summon_loop" and s.summon_count_known and s.summon_loops==1 and q.open_loop~=s.summon_started
    if s.summoning and not q.was_summoning or first_loop then
        if first_loop then q.open_loop=s.summon_started end
        -- 新的长召虫动画取代上一个召手收尾准备；只在真实新动画开始时释放，不能每帧互相取消。
        if w.spawn_lure then
            w.lure_until=nil;w.spawn_lure=nil;w.rebait=nil;w.bait_hold=nil;w.bait_point=nil
            w.escape_point=nil;w.escape_turn=nil;w.next_escape=nil
        end
        q.await_snare=true;q.spawn_snare=s.snare_started;q.spawn_spike=s.spike_count;q.shared_seen=nil;q.round="lap"
        D.Emit(w,"lap_wave","clear_edge_food_before_summon_end")
    end
    q.was_channeling=s.channeling;q.was_summoning=s.summoning
    if q.await_snare then
        if s.snare_started~=q.spawn_snare or s.spike_count~=q.spawn_spike then q.shared_seen=true end
        if q.shared_seen and not(s.anim=="attack1" and s.frame<=30 or s.anim=="spike" or s.summoning) then
            q.await_snare=nil;q.route_waypoint=nil;q.route_next=nil
            D.Emit(w,"lap_release","post_spawn_shared_cast_complete")
        end
    end
    q.hand_positions=q.hand_positions or {}
    for _,e in ipairs(w.channelers) do if located(e) then q.hand_positions[e]=q.hand_positions[e] or e:GetPosition() end end
    for e in pairs(q.hand_positions) do if not located(e) then q.hand_positions[e]=nil end end
    q.food,q.feeding=feeding(w)
    if s.feasting then q.saw_feast=true end
    if s.summoning then q.seen_summon=true end
    if #w.channelers>0 then q.seen_summon=true end
    q.bugs=0;for _,e in ipairs(w.minions) do if alive(e) then q.bugs=q.bugs+1 end end
    if q.bugs>0 then q.seen_summon=true end
    if s.anim=="attack" and q.melee~=s.melee_started then
        if w.sanity_round then w.sanity_round.restoring=true end
        q.melee=s.melee_started;q.hand=nil;q.sent=nil;q.spent=nil;q.light=nil
        -- 第63帧解除busy；必须在此之前完成攻击和临时装备恢复确认。
        q.deadline=s.melee_started+63/30-w.c:Latency()-.15
    end
    local clearing=s.feasting
    if q.stage=="clear_feed" and not clearing then
        if q.feeding==0 and not(s.summoning or s.channeling) then
            q.clear_since=q.clear_since or GetTime()
            clearing=GetTime()-q.clear_since<.3
        else q.clear_since=nil;clearing=true end
    else q.clear_since=nil end
    if not q.await_snare and not (s.channeling or s.summoning) then Round.Observe(w) end
    if (q.round=="lap" or not q.round and q.stage=="patrol") and not (w.lure_until or w.rebait or s.feasting or s.channeling or s.summoning or s.controlling)
        and (s.anim=="walk_pre" or s.anim=="walk_loop" or s.anim=="idle") and s.ready.snare then
        local left=O.ReadyIn(s,"snare",GetTime())
        local approach=math.max(0,distance(w.c.player:GetPosition(),w.boss:GetPosition())-2.6)/math.max(1,w.c:Speed()*.65)+w.c:Latency()+.2
        local attackready=math.max(0,(s.melee_started or GetTime()-3)+3-GetTime())
        -- 清下一只手之前先安排“最后一次骗A”；不能等CD归零、Boss还在走路时才逃。
        if left>w.c:Latency()+.1 and left<=math.max(approach,attackready)+.35 and attackready<left
            and (q.round=="lap" or approach+.15<left) then
            w.rebait=true;q.hand_point=nil;q.approach=nil
            D.Emit(w,"cycle_bait_reserved",string.format("snare=%.2f approach=%.2f",left,approach))
        end
    end
    local desired
    if s.channeling or s.summoning then desired="spawn"
    elseif clearing then desired="clear_feed"
    elseif q.await_snare then desired="post_spawn"
    elseif q.bugs==0 and #w.channelers==0 and not w:Shielded() then desired="fight"
    else desired="patrol" end
    stage(w,desired)

end
-- taunt2_pst第8帧已解除busy；不能等骨牢起手才取消最后的清虫动作。
function M.FeastExit(w)
    local q=w.cycle;local s=w.state
    return q and q.stage=="clear_feed" and q.saw_feast
        and (s.anim=="taunt2_pst" or s.feasting and q.feeding==0)
        and s.ready.snare and O.ReadyIn(s,"snare",GetTime())<=3
end
function M.HasFood(w) return w.cycle and w.cycle.feeding>0 or false end
function M.RangedWindow(w)return not w.rebait and not M.RootExit(w) and Ranged.Window(w) end
local function reserve(w) return Ranged.EscapeBudget(w) end
function M.RootExit(w)
    local q=w.cycle;local s=w.state;if not q then return nil end
    local budget=reserve(w)
    -- await_snare只是“这波还没见共享技能”，不是整波召唤的等牢锁。
    -- 只有CD和可见busy都已接近退路预算，才真正交出清理/移动控制权。
    if q.await_snare and not q.shared_seen and not (s.feasting or s.anim=="taunt2_pst")
        and O.ReadyIn(s,"snare",GetTime())<=budget
        and (not(s.channeling or s.summoning) or Ranged.BusyLeft(w)<=budget) then return "spawn" end
    if M.FeastExit(w) then return "feast" end
    -- 远处持杖不能因CD估计就旁观吞食；接近后CD真正逼近回程预算时仍须退回可逃的带上。
    -- 纯近战保留原有撤离预算；已提交的撤离由同一个retreat走完，不能下一帧又取消。
    if (not staff(w) or distance(w.c.player:GetPosition(),w.boss:GetPosition())<select(1,w:Ranges())-.5) and s.feasting and q.feeding>0 and s.ready.snare and O.ReadyIn(s,"snare",GetTime())<=reserve(w) then return "feast_tail" end
end
function M.Kiting(w) return w.cycle and w.cycle.stage~="fight" end
function M.BaitAllowed() return true end
function M.OpeningAllowed(w)
    local q=w.cycle;local s=w.state;local now=GetTime()
    if not q or q.stage~="patrol" or s.anim~="attack" or w.lure_until or w.rebait or q.spent then return false end
    local p=w.c.player;local bp=w.boss:GetPosition()
    if q.opening_cast==s.melee_started then
        return q.opening_hand and located(q.opening_hand)
            and now+(q.sent and 0 or 8/30+.02)<q.opening_deadline
    end
    local held=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    -- 只借手杖/橙宝石国王手杖的普通8帧近战；不把弹道武器或一次换武器也塞进前摇。
    if not held or held.prefab~="cane" and held.prefab~="king_cane" or held:HasTag("rangedweapon")
        or staff(w) or s.frame>3 or not S.CanPrepare(w) or p.components.playercontroller:IsBusy() then return false end
    local safe=(R.HitFloor(w) or 5.15)+.3
    if distance(p:GetPosition(),bp)>=safe then return false end
    local retreat=math.max(0,safe-distance(p:GetPosition(),bp))/math.max(1,w.c:Speed())+w.c:Latency()+.1
    local deadline=s.melee_started+32/30-retreat
    if now+(S.Wearing(w) and .3 or .45)>=deadline then return false end
    for _,e in ipairs(w.channelers) do if located(e) and distance(p:GetPosition(),e:GetPosition())<=reach(w) then
        q.opening_cast=s.melee_started;q.opening_hand=e;q.opening_deadline=deadline
        D.Emit(w,"ghost_opening",string.format("ghost=%s clear_budget=%.2f retreat=%.2f",tostring(e.GUID),deadline-now,retreat))
        return true
    end end
    return false
end
function M.BlockAttack(w,e) return w.cycle and e==w.boss and w.cycle.stage~="fight" and not Round.AllowsBoss(w) or false end
function M.KeepMask(w) return Ranged.Keep(w) or Round.KeepMask(w) end
function M.RoundDodge(w,safe) return Round.Dodge(w,safe) end
local function window(w,budget)
    local q=w.cycle
    if not q then return false end
    budget=budget or 1.05
    if w.state.anim=="attack" then return q.deadline and GetTime()+budget<q.deadline end
    if q.round=="lap" and (w.state.channeling or w.state.summoning) then
        return Ranged.SafeUntil(w)>GetTime()+budget
    end
    local s=w.state
    -- 第一轮虫子已清空，骨牢后Boss远在另一边时可就地清手，不能等它走近再被迫离开鬼手。
    -- 预留换装、攻击、恢复及追近时间；有虫时仍严格用真实普攻窗口，避免诱控制让虫子追上。
    local walking=s.anim=="idle" or s.anim=="walk_pre" or s.anim=="walk_loop" or s.anim=="walk_pst"
        or s.anim=="attack1" and s.frame>30
    local reserve=budget+.55+2*w.c:Latency()
    return q.stage=="patrol" and q.bugs==0 and walking and not (s.controlling or s.feasting or s.summoning or s.channeling)
        and s.ready.snare and O.ReadyIn(s,"snare",GetTime())>reserve
        and distance(w.c.player:GetPosition(),w.boss:GetPosition())>
            3.8+(w.c.player.GetPhysicsRadius and w.c.player:GetPhysicsRadius(0) or .5)+.2+((TUNING and TUNING.STALKER_SPEED) or 4.2)*reserve
end
function M.RestoreDue(w)
    if Ranged.Keep(w) then return false end
    local q=w.cycle
    if q and q.root_work then
        local work=q.root_work
        return w.sanity_round and (not M.RootWorkAllowed(w,work.target) or work.sent and GetTime()-work.sent>=.4) or false
    end
    return q and w.sanity_round and not Round.KeepMask(w) and (q.spent or not window(w,.45)) or false
end
function M.RootWorkAllowed(w,e)
    local q=w.cycle;local work=q and q.root_work;local s=w.state
    return work and work.target==e and alive(e) and not work.done
        and GetTime()+8/30<work.deadline and (s.feasting or s.summoning or s.channeling)
        and distance(w.c.player:GetPosition(),w.boss:GetPosition())>=select(1,w:Ranges())-.3 or false
end
-- CD已就绪且Boss还在吞食：不能回近身贪虫，也不能整轮站着看。
-- 保住可出圈的等牢带，只借当前可见busy动画清手/清通道；移位始终仍需骨牢完整退路。
function M.RootedWork(w)
    local q=w.cycle;local s=w.state
    if not q or not (s.feasting or s.summoning or s.channeling) then return false end
    if staff(w) then
        if w.staff_action then return Ranged.Work(w) end
        local p=w.c.player:GetPosition()
        local food=Ranged.FoodTarget(w)
        if food and (s.feasting or q.food) and Ranged.Work(w,food,"先清织影身边即将被吞食的虫子") then return true end
        for _,group in ipairs({w.channelers,w.minions}) do for _,e in ipairs(group) do
            if alive(e) and distance(p,e:GetPosition())<=7.5 then
                if Ranged.Work(w,e,"等牢带借当前定身窗口清够得到的目标，不追中央") then return true end
            end
        end end
        return false
    end
    local now=GetTime();local work=q.root_work
    if work then
        if not alive(work.target) or work.sent and now-work.sent>=.4
            or now+(work.sent and .18 or .45)>=work.deadline then work.done=true end
        if work.done then
            if restore(w) then return true end
            q.root_work=nil;q.next_root_work=now+.2;return false
        end
        if work.target.prefab=="shadowchanneler" and S.Prepare(w) then return true end
        if not alive(work.target) then return false end
        q.light=work.target
        local sent=w.light_sent;w:Hand(work.target,"吞食定身时在等牢带清眼前鬼手／虫子，不回近身")
        if sent~=w.light_sent then work.sent=w.light_sent.time end
        return true
    end
    if now<(q.next_root_work or 0) then return false end
    local capture,resolve=w:Ranges()
    if not R.RetreatReady(w) then return false end
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
    local left=w.boss.AnimState:GetCurrentAnimationLength()-s.frame/30-w.c:Latency()-.2
    if s.feasting then left=left+8/30 end
    local target
    if left>.72 then
        for _,e in ipairs(w.channelers) do if alive(e) and distance(p,e:GetPosition())<=reach(w) and S.CanPrepare(w) then target=e;break end end
    end
    if not target and left>.65 then
        for _,e in ipairs(w.minions) do if alive(e) and distance(p,e:GetPosition())<=reach(w) then target=e;break end end
    end
    if target then
        q.root_work={target=target,deadline=now+left}
        D.Emit(w,"root_work_start",target.prefab..":"..tostring(target.GUID))
        return M.RootedWork(w)
    end
    for _,e in ipairs(w.channelers) do
        if located(e) and distance(p,e:GetPosition())<=reach(w) and S.CanPrepare(w) then return false end
    end
    -- 当前手杖够不到时，只沿识别带短移接下一只手，不追进Boss吞食圈。
    q.next_root_work=now+.75
    local best,score
    local angle=math.atan2(p.z-bp.z,p.x-bp.x)
    for _,offset in ipairs({15,-15}) do
        local a=angle+offset*math.pi/180;local v=Vector3(bp.x+math.cos(a)*(capture-.1),0,bp.z+math.sin(a)*(capture-.1))
        local exit=R.SnareExit(w,v,0,resolve)
        if exit and R.Path(w,v,nil,true) then
            for _,e in ipairs(w.channelers) do if located(e) and S.CanPrepare(w) then
                local d=v:DistSq(e:GetPosition())
                if d<p:DistSq(e:GetPosition())-1 and (not score or d<score) then best,score={point=v,exit=exit},d end
            end end
        end
    end
    if best then
        R.UpdateRetreatBand(w,best.point,best.exit)
        return w:Move(best.point,"保持等牢带退路，沿外侧接近下一只鬼手",nil,true)
    end
    return false
end
-- 实际骨牢命中/精神控制接管后，旧窗口不能在补救结束后复活。
function M.Interrupt(w,reason)
    local q=w.cycle
    if q then
        q.root_work=nil;q.light=nil
        q.hand=nil;q.sent=nil;q.spent=true
    end
    Ranged.Interrupt(w,reason)
    if w.sanity_round then w.sanity_round.restoring=true end
end
function M.LightAllowed(w,e)
    if Ranged.Allowed(w,e) then return true end
    local q=w.cycle;if not q then return true end
    if w.state.anim=="taunt2_pst" then return false end
    if q.root_work and q.root_work.target==e then return M.RootWorkAllowed(w,e) end
    if q.light~=e or not alive(e) then return false end
    if e.prefab=="shadowchanneler" then
        return not q.spent and window(w,.45) and not w.state.controlling
    end
    return not w.lure_until and not w.rebait
end
local function light(w,e,reason)
    local q=w.cycle;local item=staff(w);local p=w.c.player:GetPosition()
    if item then
        if Ranged.Work(w,e,reason) then return true end
        w:Hold("法杖等待实际安全窗口，不重复换装",true);return true
    end
    local range=reach(w)
    if distance(p,e:GetPosition())>range then
        if restore(w) then return true end
        q.light=nil
        return w:Move(R.Point(e:GetPosition(),p,math.max(1,range-.3)),reason.."先持移速装备接近",nil,true)
    end
    q.light=e
    local old=w.light_sent;local result=w:Hand(e,reason)
    if O.IsMinion(e) and old~=w.light_sent then q.cleanup_started=q.cleanup_started or GetTime() end
    return result
end
local function roadblock(w,goal)
    local p=w.c.player:GetPosition();local dx,dz=goal.x-p.x,goal.z-p.z;local len=math.max(.01,dx*dx+dz*dz)
    for _,e in ipairs(w.minions) do if alive(e) and p:DistSq(e:GetPosition())<(staff(w) and 7.5 or 3.5)^2 then
        local ep=e:GetPosition();local t=math.max(0,math.min(1,((ep.x-p.x)*dx+(ep.z-p.z)*dz)/len))
        if Vector3(p.x+dx*t,0,p.z+dz*t):DistSq(ep)<1.5^2 then return e end
    end end
end
-- 预测Boss下一小段追击，而非只检查人物自己的脚前；FindMinions(1)会使它停下吞食。
local function encounter(w,goal)
    local bp=w.boss:GetPosition();local dx,dz=goal.x-bp.x,goal.z-bp.z
    local length=math.sqrt(dx*dx+dz*dz);if length<.01 then return nil end
    local travel=math.min(3.5,length);dx,dz=dx/length*travel,dz/length*travel
    local limit=.3+(w.boss.GetPhysicsRadius and w.boss:GetPhysicsRadius(0) or .75)+1+1.1
    local target,nearest
    for _,e in ipairs(w.minions) do if alive(e) then
        local ep=e:GetPosition();local t=math.max(0,math.min(1,((ep.x-bp.x)*dx+(ep.z-bp.z)*dz)/(travel*travel)))
        local near=Vector3(bp.x+dx*t,0,bp.z+dz*t)
        local current=bp:DistSq(ep);local future=near:DistSq(ep)
        if future<limit*limit and future<current-.1 and (not nearest or current<nearest) then target,nearest=e,current end
    end end
    return target
end
local function pullpoint(w,bug)
    local bp=w.boss:GetPosition();local ep=bug:GetPosition();local p=w.c.player:GetPosition()
    local dx,dz=bp.x-ep.x,bp.z-ep.z;local len=math.sqrt(dx*dx+dz*dz)
    if len<.01 then return nil end
    dx,dz=dx/len,dz/len
    local chosen,score
    -- 先选虫子->Boss的延长方向；直线会穿Boss/撞栅栏时，从合法侧翼接过去。
    for _,degrees in ipairs({0,30,-30,60,-60}) do
        local a=degrees*math.pi/180;local ux,uz=dx*math.cos(a)-dz*math.sin(a),dx*math.sin(a)+dz*math.cos(a)
        for _,r in ipairs({5,4,6}) do
            local goal=Vector3(bp.x+ux*r,0,bp.z+uz*r)
            if p:DistSq(goal)>.8^2 and R.Path(w,goal,nil,true) and not encounter(w,goal) then
                local value=p:DistSq(goal)+math.abs(degrees)*.2+(r-5)^2
                if not score or value<score then chosen,score=goal,value end
            end
        end
    end
    return chosen
end
local function divert(w)
    local q=w.cycle;local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
    local route=q.corners[q.index];local now=GetTime()
    -- 普攻忙碌窗口留给顺路清手；技能和吞食由监督器/clear_feed优先处理。
    if w.state.anim=="attack" or w.state.controlling then return false end
    local pull=q.pull
    if pull and (not alive(pull.bug) or bp:DistSq(pull.bug:GetPosition())>=(pull.gap+.9)^2
        and not encounter(w,p) and not encounter(w,route)) then
        D.Emit(w,"cycle_pull_end","boss_clear_of_worms_resume_perimeter")
        q.pull=nil;q.pull_point=nil;pull=nil
    end
    local bug=pull and pull.bug or encounter(w,p) or encounter(w,route)
    if not bug then return false end
    if pull and q.pull_point and p:DistSq(q.pull_point)>.9^2 and R.Path(w,q.pull_point,nil,true)
        and not encounter(w,q.pull_point) then
        return w:Move(q.pull_point,"回身引织影远离虫群，沿已确认路线连续走",nil,true)
    end
    if now<(q.next_pull or 0) then
        -- 找不到合法反侧路线时交回原来的清路/巡游，不能站着反复找路。
        return false
    end
    q.next_pull=now+.35
    local goal=pullpoint(w,bug)
    if not goal then q.pull_point=nil;return false end
    if not pull then
        pull={bug=bug,gap=distance(bp,bug:GetPosition())};q.pull=pull
        D.Emit(w,"cycle_pull_start",string.format("worm=%s gap=%.2f goal=%.2f,%.2f",tostring(bug.GUID),pull.gap,goal.x,goal.z))
    end
    q.pull_point=goal
    if restore(w) then return true end
    return w:Move(goal,"回身引织影远离虫群，沿已确认路线连续走",nil,true)
end
local function outergoal(w)
    local q=w.cycle;local p=w.c.player:GetPosition()
    if p:DistSq(q.corners[q.index])<.7^2 then q.index=q.index%#q.corners+1;q.route_waypoint=nil end
    q.route_goal=q.corners[q.index]
    if q.route_waypoint and p:DistSq(q.route_waypoint)>.35^2 and R.Path(w,q.route_waypoint,nil,true) and R.OuterPath(w,q.route_waypoint) then return q.route_waypoint end
    if GetTime()<(q.route_next or 0) then return nil end
    q.route_next=GetTime()+.6;q.route_waypoint=R.Waypoint(w,q.route_goal,true)
    return q.route_waypoint
end
local function spawnwork(w)
    local q=w.cycle;local goal=outergoal(w)
    if M.RootExit(w) then return false end
    if staff(w) and #w.minions>0 and Ranged.Work(w,Ranged.FoodTarget(w),"召虫动画提前清织影身边虫群") then return true end
    if not goal then w:Hold("召唤期间保留外围路线，等待绕障碍入口",true);return true end
    local bug=roadblock(w,goal)
    if bug then
        if staff(w) then if Ranged.Work(w,bug,"召虫安全动画先清下一段外围边虫") then return true end
        elseif window(w,.8) then return light(w,bug,"召虫空档清脚前边虫，收尾预留骨牢") end
    end
    local p=w.c.player:GetPosition()
    for _,e in ipairs(w.channelers) do if located(e) and distance(p,e:GetPosition())<=reach(w) then
        if staff(w) and Ranged.Work(w,e,"召唤长动画顺路清手，保留SAN到弹道结束") then return true end
    end end
    if Ranged.Work(w) then return true end
    if restore(w) then return true end
    return w:Move(goal,"鬼手前摇开始按外围路线移动，召虫只清沿途",nil,true)
end
local function patrol(w)
    local q=w.cycle;local p=w.c.player:GetPosition();local goal=outergoal(w)
    if not goal then w:Hold("外围路线受阻，保留环向等待入口重算",true);return true end
    local road=roadblock(w,goal)
    if road and (distance(p,w.boss:GetPosition())>=5 or window(w,.8)) then
        return light(w,road,"清除外围行进路线上的虫子")
    end
    q.light=nil
    if distance(p,w.boss:GetPosition())>5.5 and not (w.state.feasting or w.state.summoning or w.state.channeling or w.state.controlling) then
        -- 等Boss继续跟随，不为追一次普攻反向抄回中央虫群。
        w:Hold("外围等织影跟上，不戴疯狂装备、不跑回中央",true);return true
    end
    return w:Move(goal,"沿中庭外围同向带走织影，清手清路",nil,true)
end
local function approachhand(w)
    local q=w.cycle;local p=w.c.player:GetPosition();local range=staff(w) and 7.5 or reach(w)
    if not S.CanPrepare(w) then return false end
    local s=w.state;local d=distance(p,w.boss:GetPosition())
    local walking=s.anim=="idle" or s.anim=="walk_pre" or s.anim=="walk_loop" or s.anim=="walk_pst"
    -- 已经在远处且骨牢会先于下一次近身普攻就绪，不能为了等鬼手骗A让Boss走到脸上。
    if walking and s.ready.snare and d>=6.5
        and O.ReadyIn(s,"snare",GetTime())<math.max(0,d-2.6)/((TUNING and TUNING.STALKER_SPEED) or 4.2)+w.c:Latency() then
        w:ReserveRetreat("hand")
        return w:Retreat()
    end
    local target,goal
    for _,e in ipairs(w.channelers) do if located(e) then
        local ep=q.hand_positions and q.hand_positions[e] or e:GetPosition()
        if distance(p,ep)<=range then
            target=e;break
        end
        if q.approach==e and q.hand_point and R.Path(w,q.hand_point,e,true) and not encounter(w,q.hand_point)
            and (q.round~="lap" or R.OuterPath(w,q.hand_point)) then
            target,goal=e,q.hand_point;break
        end
        local angle=math.atan2(p.z-ep.z,p.x-ep.x)
        for _,offset in ipairs({0,30,-30,60,-60}) do
            local a=angle+offset*math.pi/180
            local v=Vector3(ep.x+math.cos(a)*math.max(1,range-.2),0,ep.z+math.sin(a)*math.max(1,range-.2))
            if R.Path(w,v,e,true) and not encounter(w,v) and (q.round~="lap" or R.OuterPath(w,v)) then target,goal=e,v;break end
        end
        if target then break end
    end end
    if not target then q.approach=nil;q.hand_point=nil;return false end
    if q.approach~=target then
        D.Emit(w,"ghost_plan",string.format("ghost=%s distance=%.2f range=%.2f",tostring(target.GUID),distance(p,target:GetPosition()),range))
    end
    q.approach=target;q.hand_point=goal
    if goal then
        if staff(w) then return Ranged.Approach(w,target,goal) end
        return w:Move(goal,"沿安全外侧接近最近鬼手，等骗A清手窗口",target,true)
    end
    -- 已进入鬼手攻击距离时留在附近，让Boss跟近出招；不再继续跑去下一个远角。
    w:Hold("鬼手已在攻击距离，持手杖等织影普攻窗口",true);return true
end
function M.Tick(w)
    local q=w.cycle;if not q then return false end
    local s=w.state;local now=GetTime()
    -- 骨牢准备路线不能被清手或清虫改写。临时装备先恢复，由监督器继续执行诱牢。
    if w.lure_until or w.rebait then return false end
    if q.stage=="spawn" then return spawnwork(w) end
    -- 实际吞食/脚下食物先于清鬼手轮次；不能让round先拿走整段清虫窗口。
    if staff(w) and (s.feasting or q.food) and not s.controlling then
        local food=Ranged.FoodTarget(w)
        if food and Ranged.Work(w,food,"优先清织影身边食物，超射程用虫群弹跳入口") then return true end
    end
    if Round.Tick(w) then return true end
    if staff(w) and not w.staff_action then
        local p=w.c.player:GetPosition();local target=q.stage=="clear_feed" and q.food or nil
        if target and distance(p,target:GetPosition())>7.5 then target=nil end
        if not target and q.stage=="clear_feed" then for _,e in ipairs(w.minions) do if alive(e) and distance(p,e:GetPosition())<=7.5 then target=e;break end end end
        if not target then for _,e in ipairs(w.channelers) do if located(e) and distance(p,e:GetPosition())<=7.5 then target=e;break end end end
        target=target or roadblock(w,q.route_waypoint or q.corners[q.index])
        if target and Ranged.Work(w,target,"外围战术选定目标，借真实窗口清手清路") then return true end
    end
    if Ranged.Work(w) then return true end
    if q.sent and not staff(w) then
        if not alive(q.hand) or now-q.sent>=.65 or not window(w,.45) then q.spent=true end
        if q.spent then
            q.light=nil
            if restore(w) then return true end
        else
            -- 暂停本体走A即可；STOP会把已经提交、尚未命中的清手攻击也取消。
            w:Hold("本次鬼手攻击已提交，等出手后立即恢复原装备");return true
        end
    end
    if s.controlling then
        q.light=nil;q.spent=true
        if restore(w) then return true end
        if q.food then return light(w,q.food,"偶发控制停步，清除即将被吞食的虫子") end
        return patrol(w)
    end
    if q.stage=="clear_feed" then
        if s.anim=="taunt2_pst" then q.light=nil;w:Hold("吞食起身立刻停手，骨牢准备优先",true);return true end
        q.pull=nil;q.pull_point=nil;q.approach=nil;q.hand_point=nil
        if restore(w) then return true end
        if q.food then return light(w,q.food,"优先清除织影脚下／即将进入吞食圈的虫子") end
        q.light=nil
        -- 吞食圈暂时没有目标也不能假装Boss在跟随。等待扫描/吞食收尾，骨牢准备由监督器抢占。
        w:Hold("先清吞食等待圈的虫子，未确认结束前不巡游拉Boss",true);return true
    end
    if q.round=="lap" then
        local goal=q.corners[q.index]
        local road=roadblock(w,q.hand_point or goal)
        if road and window(w,.8) then return light(w,road,"骗A／召唤空档清下一段路线虫子，保留中央虫群") end
    end
    if q.stage~="fight" and divert(w) then return true end
    if q.stage=="fight" then
        if restore(w) then return true end
        return false
    end
    if q.hand and not located(q.hand) then q.spent=true;q.hand=nil end
    if not staff(w) and not q.spent and window(w,w.sanity_round and .85 or 1.05) then
        -- 只清眼前最近且当前可攻击的鬼手，不戴着护符跨场追手。
        local target
        local range=reach(w)
        for _,e in ipairs(w.channelers) do if located(e) and distance(w.c.player:GetPosition(),e:GetPosition())<=range then target=e;break end end
        if target then
            q.hand=target
            if not S.CanPrepare(w) then
                return patrol(w) -- 缺少疯狂装备也不在Boss身边原地等待。
            end
            if S.Prepare(w) then return true end
            if not alive(target) or not S.Ready(w) then
                w:Hold("已锁定固定鬼手位置，等待疯狂状态／可攻击确认",true);return true
            end
            q.light=target
            local old=w.light_sent
            w:Hand(target,"骗出普攻后临时疯狂，只打最近一只鬼手")
            if w.light_sent~=old then q.sent=w.light_sent.time end
            return true
        end
    end
    q.light=nil
    if restore(w) then return true end
    if approachhand(w) then return true end
    if #w.channelers>0 and distance(w.c.player:GetPosition(),w.channelers[1]:GetPosition())<= (staff(w) and 7.5 or reach(w))
        and distance(w.c.player:GetPosition(),w.boss:GetPosition())<=5.5 and s.anim~="attack" then
        return w:Move(R.Point(w.boss:GetPosition(),w.c.player:GetPosition(),2.6),"附近鬼手等一次真实普攻，禁止提前戴护符",w.boss,true)
    end
    return patrol(w)
end
return M
