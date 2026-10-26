-- 路径每半码取样；当前已在威胁内时允许向外脱离，不允许越走越深。
local N={}
local function threatening(c,e)
    if require("shadowself/control/arena_rabbit").Ignore(c,e) then return false end
    local rhythm=c.plan and c.plan.arena_clockwork
    if rhythm and rhythm:Live() and e~=rhythm.target then return false end
    -- A visible recovery/idle animation is not an active area attack. Keep the
    -- queen's guards as proximity obstacles for her dedicated separation tactic.
    if e.prefab=="beeguard" and c.beequeen and c.beequeen.queen then return true end
    local o=c.observed and c.observed[e.GUID]
    return not o or not o.neutral
end
function N.Radius(e)
    -- 蘑菇地精的15码是吐孢子触发范围；本体只保留碰撞余量，孢子由机制层处理。
    if e.prefab=="mushgnome" then return (e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)+.7 end
    if e.prefab=="shadowthrall_hands" then return 2.8 end
    if e.prefab=="shadowthrall_horns" and e.AnimState:IsCurrentAnimation("jump") then return 3.8 end
    if e:HasTag("lunarthrall_plant_end") or e:HasTag("lunarthrall_plant_segment") then return 4.8 end
    local c=e.replica and e.replica.combat
    return (c and c.GetAttackRangeWithWeapon and c:GetAttackRangeWithWeapon() or 2)
        +(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)+.7
end
function N.Clearance(c,q)
    if c.player.GetCurrentPlatform and c.player:GetCurrentPlatform() then return 8 end
    local map=TheWorld and TheWorld.Map
    if not map or not map.IsPassableAtPoint or not map.IsOceanAtPoint then return 8 end
    local open=0
    for i=0,7 do
        local a=i*math.pi/4;local x,z=q.x+math.cos(a)*2.5,q.z+math.sin(a)*2.5
        if map:IsPassableAtPoint(x,0,z) and not map:IsOceanAtPoint(x,0,z)
            and (not map.IsPointNearHole or not map:IsPointNearHole(Vector3(x,0,z)))
            and (not TheWorld.Pathfinder or TheWorld.Pathfinder:IsClear(q.x,0,q.z,x,0,z,{ignorecreep=true,ignorewalls=false})) then open=open+1 end
    end
    return open
end
function N.Risk(c,q,exclude)
    local risk=0
    for _,e in ipairs(c.enemies or {}) do
        if e~=exclude and threatening(c,e) and e:IsValid() and not require("shadowself/control/status").Frozen(e) and not require("shadowself/control/status").Sleeping(e) then
            risk=risk+math.max(0,N.Radius(e)-math.sqrt(q:DistSq(e:GetPosition())))^2
        end
    end
    for _,h in ipairs(c.hazards or {}) do risk=risk+math.max(0,h.radius-math.sqrt(q:DistSq(h.pos)))^2*4 end
    return risk
end
-- 只判断侧方怪/蜂蜜是否改变本次原生路线；不替原mod重判主目标与地形。
function N.Obstructed(c,q,exclude)
    if not require("shadowself/control/arena_center").Point(c,q) then return true end
    if N.Clearance(c,q)<5 then return true end
    local p=c.player:GetPosition();local zones={}
    for _,e in ipairs(c.enemies or {}) do
        if e~=exclude and threatening(c,e) and e:IsValid() and not require("shadowself/control/status").Frozen(e) and not require("shadowself/control/status").Sleeping(e) then zones[#zones+1]={pos=e:GetPosition(),radius=N.Radius(e)} end
    end
    for _,h in ipairs(c.hazards or {}) do zones[#zones+1]=h end
    local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.5))
    for _,zone in ipairs(zones) do
        local before=math.max(0,zone.radius-math.sqrt(p:DistSq(zone.pos)))
        for i=1,steps do
            local v=Vector3(p.x+(q.x-p.x)*i/steps,0,p.z+(q.z-p.z)*i/steps)
            local after=math.max(0,zone.radius-math.sqrt(v:DistSq(zone.pos)))
            if after>before+.02 then return true end
        end
        if before>0 and math.max(0,zone.radius-math.sqrt(q:DistSq(zone.pos)))>=before-.01 then return true end
    end
    return false
end
function N.Safe(c,q,exclude)
    if not require("shadowself/control/arena_center").Point(c,q) then return false end
    if not c.actions:SafePoint(q) then return false end
    if N.Clearance(c,q)<5 and N.Clearance(c,q)<=N.Clearance(c,c.player:GetPosition()) then return false end
    local p=c.player:GetPosition();local initial=N.Risk(c,p,exclude)
    local zones={}
    for _,e in ipairs(c.enemies or {}) do
        if e~=exclude and threatening(c,e) and e:IsValid() and not require("shadowself/control/status").Frozen(e) and not require("shadowself/control/status").Sleeping(e) then zones[#zones+1]={pos=e:GetPosition(),radius=N.Radius(e)} end
    end
    for _,h in ipairs(c.hazards or {}) do zones[#zones+1]=h end
    local n=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.5))
    for i=1,n do
        local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
        if not c.actions:SafePoint(v) then return false end
        for _,zone in ipairs(zones) do
            local before=math.max(0,zone.radius-math.sqrt(p:DistSq(zone.pos)))
            local after=math.max(0,zone.radius-math.sqrt(v:DistSq(zone.pos)))
            if after>before+.02 then return false end
        end
    end
    return initial==0 and N.Risk(c,q,exclude)==0 or N.Risk(c,q,exclude)<initial-.01
end
-- Only when already inside attack zones: allow brief overlap to reach a lower-risk
-- endpoint. Strict per-enemy monotonic checks can otherwise trap a surrounded player.
function N.Escape(c,goal,exclude,accept)
    local p=c.player:GetPosition();local initial=N.Risk(c,p,exclude)
    if initial<=0 then return nil end
    local best,score
    for _,length in ipairs({2,3,4}) do
        for i=0,23 do
            local angle=i*math.pi/12;local q=Vector3(p.x+math.cos(angle)*length,0,p.z+math.sin(angle)*length)
            local final=N.Risk(c,q,exclude)
            if final<initial-.01 and require("shadowself/control/arena_center").Point(c,q) and (not accept or accept(q)) then
                local pass=true;local peak,exposure=initial,0
                for j=1,8 do
                    local sample=Vector3(p.x+(q.x-p.x)*j/8,0,p.z+(q.z-p.z)*j/8)
                    if not c.actions:SafePoint(sample) then pass=false;break end
                    local risk=N.Risk(c,sample,exclude);peak=math.max(peak,risk);exposure=exposure+risk
                end
                if pass then
                    local value=peak*30+exposure+final*50+q:DistSq(goal)*.03+(8-N.Clearance(c,q))*15
                    if not score or value<score then best,score=q,value end
                end
            end
        end
    end
    return best
end
function N.Select(c,q,exclude)
    q=require("shadowself/control/arena_center").Goal(c,q)
    if N.Safe(c,q,exclude) then return q end
    if c.dodging and c.escape_until and GetTime()<c.escape_until and c.escape_point
        and N.Risk(c,c.player:GetPosition(),exclude)>0 and N.Safe(c,c.escape_point,exclude) then return c.escape_point end
    local p=c.player:GetPosition();local length=math.min(4,math.max(1,math.sqrt(p:DistSq(q))))
    local best,score
    for i=0,23 do
        local a=i*math.pi/12;local v=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
        if N.Safe(c,v,exclude) then
            local s=v:DistSq(q)+N.Risk(c,v,exclude)*100+(8-N.Clearance(c,v))*15
            if not score or s<score then best,score=v,s end
        end
    end
    if best and c.dodging then c.escape_point=best;c.escape_until=GetTime()+.45 end
    return best or N.Escape(c,q,exclude) or p
end
return N
