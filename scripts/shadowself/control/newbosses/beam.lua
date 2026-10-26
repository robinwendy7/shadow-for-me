-- 光束从起手到落地结束持续跑动，不复用“走出危险区就停”的普通闪避。
local G=require("shadowself/control/newbosses/geometry")
local Shrouden=require("shadowself/control/newbosses/shrouden")
local Diagnostics=require("shadowself/control/newbosses/debug")
local M={}
function M.Active(owner)
    for _,e in ipairs(owner.bosses) do
        if e.prefab=="shrouden" and Shrouden.Running(e) then return e end
    end
    for _,h in ipairs(owner.shapes) do if h.beam then return h.source end end
end
local function point(owner,state,source)
    local started=Diagnostics.Clock();local candidates=0
    local c=owner.c;local p=c.player:GetPosition();local initial=owner:Risk(p,.1)
    local renew=math.max(2.5,c:Speed()*.45)
    if state.point and p:DistSq(state.point)>renew^2 then
        local final,peak=owner:Path(state.point)
        if final and final<=.001 and peak<=initial+.15 then owner.debug:Plan(started,0,true);return state.point end
    end
    local dx,dz=state.dx,state.dz
    if not dx then
        local q=source:GetPosition();dx,dz=p.x-q.x,p.z-q.z
        local d=math.sqrt(dx*dx+dz*dz)
        if d>.1 then dx,dz=dx/d,dz/d else dx,dz=G.Basis(c.player) end
    end
    local heading=math.atan2(dz,dx);local best,score,best_safe
    -- 优先6~10码的连续路段，只有地形挤压时才退到短段；不用靠近Boss的评分。
    for _,length in ipairs({8,10,6,4,2}) do for i=0,23 do
        candidates=candidates+1
        local a=heading+i*math.pi/12;local x,z=math.cos(a),math.sin(a)
        local q=Vector3(p.x+x*length,0,p.z+z*length)
        local final,peak,exposure=owner:Path(q)
        if final then
            local safe=final<=.001
            local value=final*250+peak*35+exposure*12+(1-x*dx-z*dz)*12+math.abs(length-8)*2
            value=value+(8-require("shadowself/control/navigation").Clearance(c,q))*4
            if not score or safe and not best_safe or safe==best_safe and value<score then best,score,best_safe=q,value,safe end
        end
    end end
    if best then
        local d=math.sqrt(p:DistSq(best));state.dx,state.dz=(best.x-p.x)/d,(best.z-p.z)/d
        state.point=best
    end
    owner.debug:Plan(started,candidates,false)
    return best
end
function M.Tick(owner)
    local source=M.Active(owner)
    if not source then
        if owner.beam_run then owner.point=nil;owner.commit_until=nil end
        owner.beam_run=nil;return false
    end
    local c=owner.c;local state=owner.beam_run or {};owner.beam_run=state
    c.bridge:PauseAttack();owner.holding=true;c.blocked=true;c.special_active=true
    c.travel:BeginDodge(c.snapshot);owner.moving=true
    local q=point(owner,state,source)
    if q then
        owner.stopped=nil;owner.waiting=nil
        c:Move(q,"暗影憎恶 · 全程跑动躲光束及落地余波")
    end
    -- 暂时找不到通路时不取消已在执行的移动，不反复StopWalking重置预测会话。
    return true
end
return M
