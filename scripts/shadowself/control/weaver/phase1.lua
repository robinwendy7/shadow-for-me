-- 一阶段只有一种战斗阶段；目标位置不是每帧抢控制的独立线程。
-- center -> enter -> wait -> fight；真实骨牢结束后 return -> fight。
local R=require("shadowself/control/weaver/route")
local D=require("shadowself/control/weaver/debug")
local M={}
local function change(q,name) q.stage=name;q.waypoint=nil;q.next_plan=nil end
local function nearest(w,corners)
    local p=w.c.player:GetPosition();local goal,cost
    for _,v in ipairs(corners)do
        local via,length=R.Waypoint(w,v)
        if via and (not cost or length<cost)then goal,cost=v,length end
    end
    return goal or (p:DistSq(corners[1])<p:DistSq(corners[2])and corners[1]or corners[2])
end
function M.Observe(w)
    local s=w.state
    if s.phase>=2 then if w.phase1 then change(w.phase1,"done");w.phase1.goal=nil end;return end
    if not w.phase1 and w.center then w.phase1={stage="center",snares=0,spikes=0}end
    local q=w.phase1;if not q then return end
    if s.anim=="attack1" and q.snare~=s.snare_started then
        q.snare=s.snare_started;q.snares=q.snares+1;q.goal=nil
        change(q,q.anchor and "return" or "enter")
    end
    if s.anim=="spike" and q.spike~=s.spike_count then q.spike=s.spike_count;q.spikes=q.spikes+1 end
end
function M.KeepMask()return false end
function M.BlockAttack(w,e)
    local q=w.phase1
    return q and e==w.boss and q.stage~="fight" and q.stage~="done" or false
end
function M.Tick(w)
    local q=w.phase1
    if not q or q.stage=="done" or w.cycle or w.lure_until or w.rebait then return false end
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
    if q.stage=="fight" then return false end
    if q.stage=="wait" then
        if bp:DistSq(q.anchor)<=5.5^2 then change(q,"fight");q.goal=nil;return false end
        w:Hold("深柱脚等织影真正跟近，不提前追出去",true);return true
    end
    if q.stage=="center" then
        local br=math.sqrt(bp:DistSq(w.center));local pr=math.sqrt(p:DistSq(w.center))
        if br<=8 and pr<=7.8 and (br<=5 or pr<br-.75)then change(q,"fight");q.goal=nil;return false end
        q.goal=q.goal or R.Point(w.center,bp,4.8)
    else
        local corners=R.FightCorners(w)
        if not corners then change(q,"center");q.goal=nil;return M.Tick(w)end
        -- 回场是为了恢复战斗，Boss已跟到当前地点就完成；不再检查人为的走廊宽度。
        if q.stage=="return" and p:DistSq(bp)<=5.5^2 then change(q,"fight");q.goal=nil;return false end
        if not q.goal then
            q.goal=nearest(w,corners)
            D.Emit(w,"pillar_pair",string.format("a=%.2f,%.2f b=%.2f,%.2f",corners[1].x,corners[1].z,corners[2].x,corners[2].z))
        end
        if p:DistSq(q.goal)<=.65^2 then
            q.anchor=q.goal;change(q,"wait");return M.Tick(w)
        end
    end
    if not q.waypoint or p:DistSq(q.waypoint)<.35^2 or not R.Path(w,q.waypoint,nil,true)then
        if GetTime()>=(q.next_plan or 0)then q.waypoint=R.Waypoint(w,q.goal);q.next_plan=GetTime()+.5 end
    end
    if q.waypoint and R.Path(w,q.waypoint,nil,true)then return w:Move(q.waypoint,"沿单一回场路线引到近端，技能危险先接管",nil,true)end
    w:Hold("保留回场目标，等待合法通路",true);return true
end
return M
