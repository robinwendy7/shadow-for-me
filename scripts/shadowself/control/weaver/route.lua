-- 织影者真实碰撞与分段路线：同一次撤离保存一条通道，实际技能/新障碍才能改变路线。
local O=require("shadowself/control/weaver/observe")
local Incoming=require("shadowself/control/incoming")
local R={}
local function distance(a,b) return math.sqrt(a:DistSq(b)) end
local function radius(e) return e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5 end
local static_radii={atrium_rubble=.5,atrium_statue=.45,atrium_statue_facing=.45,
    atrium_overgrowth=1.5,atrium_idol=1.5,pillar_atrium=2.5,atrium_light=.5,atrium_fence=.1}
local function staticbuffer(e)
    local n=e.prefab or ""
    return (n:find("^atrium_statue") or n=="atrium_rubble" or n=="atrium_light") and .01 or .2
end
function R.StaticRadius(e)
    local known=static_radii[e.prefab]
    if not known and e.prefab and e.prefab:find("^atrium_statue") then known=.45 end
    if known then return math.max(known,radius(e)) end
end
-- 只在一次监督决策内共享快照，下一次Tick重新读取；动态虫子、Boss和新骨刺不跨帧缓存。
function R.BeginFrame(w)
    local frame={player_pos=w.c.player:GetPosition(),lag=w.c:Latency(),player_radius=radius(w.c.player),bodies={},blockers={},fences={},clearance={},pointclear={},paths=0,grid_fallbacks=0}
    if w.boss then frame.boss_pos=w.boss:GetPosition();frame.boss_radius=radius(w.boss);frame.anim,frame.animframe=O.Animation(w.boss)end
    local function add(group,fence)
        for _,e in ipairs(group or {})do if e:IsValid() and not e:HasTag("INLIMBO")then
            local ep=e:GetPosition();local r=(R.StaticRadius(e) or radius(e))+frame.player_radius+staticbuffer(e)
            if fence then r=math.max(1.25,r+.15)end
            local item={entity=e,x=ep.x,z=ep.z,r=r,tight=staticbuffer(e)<.2}
            frame.blockers[#frame.blockers+1]=item
            if fence then frame.fences[#frame.fences+1]=item end
        end end
    end
    add(w.obstacles,false);add(w.fences,true)
    for _,e in ipairs(w.bodies or {})do if e:IsValid() and e~=w.boss then
        local ep=e:GetPosition();frame.bodies[#frame.bodies+1]={entity=e,x=ep.x,z=ep.z,r=radius(e)+frame.player_radius+.1}
    end end
    w.route_frame=frame
end
-- 连续线段与碰撞圆比较：不为每个障碍创建Vector3，也不在每个半码采样点重算。
local function cuts(p,q,x,z,limit)
    if limit<=0 then return false end
    local dx,dz=q.x-p.x,q.z-p.z;local len=dx*dx+dz*dz
    local fraction=len>.0001 and math.max(0,math.min(1,((x-p.x)*dx+(z-p.z)*dz)/len)) or 0
    local ox,oz=p.x+dx*fraction-x,p.z+dz*fraction-z
    return ox*ox+oz*oz<limit*limit
end
function R.Blocker(w,p,q)
    local frame=w.route_frame
    if frame then
        local minx,maxx=math.min(p.x,q.x),math.max(p.x,q.x)
        local minz,maxz=math.min(p.z,q.z),math.max(p.z,q.z)
        for _,item in ipairs(frame.blockers)do
            if item.x+item.r>minx and item.x-item.r<maxx and item.z+item.r>minz and item.z-item.r<maxz then
                local dx,dz=p.x-item.x,p.z-item.z
                local limit=math.min(item.r,math.max(0,math.sqrt(dx*dx+dz*dz)-.01))
                if cuts(p,q,item.x,item.z,limit)then return item.entity end
            end
        end
        return
    end
    local player_radius=radius(w.c.player)
    local function blocked(group)
        for _,e in ipairs(group or {})do if e:IsValid() and not e:HasTag("INLIMBO") then
            local ep=e:GetPosition();local r=(R.StaticRadius(e) or radius(e))+player_radius+staticbuffer(e)
            if e.prefab=="atrium_fence" then r=math.max(1.25,r+.15) end
            local dx,dz=p.x-ep.x,p.z-ep.z
            local limit=math.min(r,math.max(0,math.sqrt(dx*dx+dz*dz)-.01))
            if cuts(p,q,ep.x,ep.z,limit)then return e end
        end end
    end
    return blocked(w.obstacles) or blocked(w.fences)
end
function R.Point(origin,from,r)
    local dx,dz=from.x-origin.x,from.z-origin.z;local d=math.sqrt(dx*dx+dz*dz)
    if d<.01 then dx,dz,d=1,0,1 end
    return Vector3(origin.x+dx*r/d,0,origin.z+dz*r/d)
end
-- 普通清手赶路守住外围通道；紧急骨牢与回拉分支可单独选择必要的斜线。
function R.OuterPath(w,goal,origin)
    local center=w.center or w.cycle and w.cycle.center
    if not center then return true end
    local p=origin or w.c.player:GetPosition();local dx,dz=goal.x-p.x,goal.z-p.z
    local len=dx*dx+dz*dz
    local t=len>.01 and math.max(0,math.min(1,((center.x-p.x)*dx+(center.z-p.z)*dz)/len)) or 0
    local near=Vector3(p.x+dx*t,0,p.z+dz*t)
    return distance(near,center)>=math.min(7.5,distance(p,center)-.1)
end
-- 沿一条射线到安全半径所需的实际路程；比“最后落点离Boss多远”更能反映能否及时躲开。
local function exitlength(origin,endpoint,bp,safe)
    local dx,dz=endpoint.x-origin.x,endpoint.z-origin.z;local length=math.sqrt(dx*dx+dz*dz)
    if length<.01 then return 0 end
    dx,dz=dx/length,dz/length
    local x,z=origin.x-bp.x,origin.z-bp.z;local dot=x*dx+z*dz
    if x*x+z*z>=safe*safe then return 0 end
    return -dot+math.sqrt(math.max(0,dot*dot+safe*safe-x*x-z*z))
end
local function routeposition(origin,points,budget)
    local p=origin
    for _,q in ipairs(points)do
        local n=distance(p,q)
        if n>budget then return R.Point(p,q,budget) end
        budget=budget-n;p=q
    end
    return p
end
-- 原版终点布局有三根柱子。栅栏所在边的两柱不能作为横穿栅栏的往返端点；
-- 选与该边相邻、远离栅栏中点的两柱，对应两座雕像旁的长边。位置来自实际实体。
function R.FightCorners(w)
    if w.fight_corners then return w.fight_corners end
    local now=GetTime();if now<(w.corner_scan or 0) then return nil end
    w.corner_scan=now+1
    if not w.center then return nil end
    local pillars={};local fx,fz,n=0,0,0
    for _,e in ipairs(w.obstacles or {}) do
        if e.prefab=="pillar_atrium" and e:IsValid() and e:GetPosition():DistSq(w.center)<24^2 then pillars[#pillars+1]=e end
    end
    for _,e in ipairs(w.fences or {}) do if e:IsValid() then local v=e:GetPosition();fx=fx+v.x;fz=fz+v.z;n=n+1 end end
    if #pillars<3 or n==0 then return nil end
    local fence=Vector3(fx/n,0,fz/n);local pair,score
    for i=1,#pillars do for j=i+1,#pillars do
        local a,c=pillars[i]:GetPosition(),pillars[j]:GetPosition();local gap=distance(a,c)
        -- 两个相邻柱角约25码，拒绝约35码的对角线。
        if gap>18 and gap<30 then
            local midpoint=Vector3((a.x+c.x)/2,0,(a.z+c.z)/2);local value=midpoint:DistSq(fence)
            if not score or value>score then pair={a,c};score=value end
        end
    end end
    if not pair then return nil end
    local result={}
    local midpoint=Vector3((pair[1].x+pair[2].x)/2,0,(pair[1].z+pair[2].z)/2)
    local length=distance(pair[1],pair[2]);local nx,nz=-(pair[2].z-pair[1].z)/length,(pair[2].x-pair[1].x)/length
    if nx*(w.center.x-midpoint.x)+nz*(w.center.z-midpoint.z)>0 then nx,nz=-nx,-nz end
    -- 红圈在柱脚外沿的口袋，不是两柱之间靠雕像的内侧走廊。
    -- 先往场边放深，再沿柱间方向留出柱体碰撞宽度；不以“方便直走”把终点退回内侧。
    for i,a in ipairs(pair) do
        local other=pair[3-i]
        for _,outset in ipairs({1.5,1.25,1}) do
            local normal=Vector3(midpoint.x+nx*outset,0,midpoint.z+nz*outset)
            for _,along in ipairs({3.05,3.45,3.85}) do
                local near=R.Point(a,other,along)
                local q=Vector3(near.x+normal.x-midpoint.x,0,near.z+normal.z-midpoint.z)
                if R.InArena(w,q) and R.Passable(q) and R.FenceClear(w,q) then result[i]=q;break end
            end
            if result[i] then break end
        end
        if not result[i] then return nil end
    end
    w.fight_corners=result;return result
end
-- 几何规划不写战斗状态。所有候选都按命中时刻评价，且任何一段都不能重新切回更近的危险圈。
function R.MeleePlan(w,local_only)
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local s=w.state
    local safe=((TUNING and TUNING.STALKER_HIT_RANGE) or 3.8)+radius(w.c.player)+.2
    local budget=w.c:Speed()*.9*math.max(0,(32-s.frame)/30-w.c:Latency()-.1)
    local best,score
    local function candidate(points)
        local origin=p;local length=0
        for _,q in ipairs(points)do
            if distance(origin,bp)>=safe and cuts(origin,q,bp.x,bp.z,safe-.03) then return end
            if not R.Path(w,q,nil,true,false,origin,true)then return end
            length=length+distance(origin,q);origin=q
        end
        if length<.01 then return end
        local impact=distance(routeposition(p,points,budget),bp)
        local reachable=impact>=safe and distance(origin,bp)>=safe
        if not reachable then
            local from=p
            for _,q in ipairs(points)do
                if cuts(from,q,bp.x,bp.z,math.max(0,math.min(safe,distance(from,bp))-.005))then return end
                from=q
            end
        end
        local value=(reachable and 10000-length or impact*100-length*.01)
        if not score or value>score then
            best={points=points,index=1,point=points[1],exit=points[2],cast=s.melee_started,safe=safe,
                reachable=reachable,travel=length,origin=p,boss=bp};score=value
        end
    end
    local angle=math.atan2(p.z-bp.z,p.x-bp.x)
    for i=0,31 do
        local a=angle+math.ceil(i/2)*math.pi/16*(i%2==0 and -1 or 1)
        local ray=Vector3(p.x+math.cos(a)*40,0,p.z+math.sin(a)*40)
        local length=exitlength(p,ray,bp,safe+.15)
        if length>.01 then candidate({R.Point(p,ray,length)})end
    end
    if not best or not best.reachable then
        for _,via in ipairs(R.EdgePoints(w))do if distance(p,via)<=3 then
            local base=math.atan2(via.z-bp.z,via.x-bp.x)
            for i=0,7 do local a=base+i*math.pi/4
                local ray=Vector3(via.x+math.cos(a)*40,0,via.z+math.sin(a)*40)
                local length=exitlength(via,ray,bp,safe+.15)
                if length>.01 then candidate({via,R.Point(via,ray,length)})end
            end
        end end
        if not local_only then
            local graph=R.PlanRetreat(w,true,true)
            if graph.complete then candidate(graph.points)end
        end
        -- 没有完整及时解时只选增距的合法短段，不把“最终能出圈”的长路当安全路线。
        for i=0,15 do local a=angle+i*math.pi/8
            for _,n in ipairs({.75,1.5,2.5})do candidate({Vector3(p.x+math.cos(a)*n,0,p.z+math.sin(a)*n)})end
        end
    end
    return best
end
-- 只有监督Tick调用执行器；原生攻击guard只读，不能调用本函数来推进/改写路线。
function R.CornerDodge(w)
    if w.state.anim~="attack" or not R.FightCorners(w)then return nil end
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local job=w.corner_dodge
    local safe=((TUNING and TUNING.STALKER_HIT_RANGE) or 3.8)+radius(w.c.player)+.2
    if job and job.cast==w.state.melee_started then
        -- 已经躲出去就停住直到这巴掌结算，不再为追终点绕回Boss面前。
        if distance(p,bp)>=safe then job.point=p;return p end
        if job.points then
            while job.index<#job.points and p:DistSq(job.points[job.index])<.3^2
                and R.Path(w,job.points[job.index+1],nil,true,false,nil,job.reachable)do job.index=job.index+1;w.c.next_move=nil end
            job.point=job.points[job.index];job.exit=job.points[job.index+1]
        end
        if job.point and p:DistSq(job.point)>.15^2 and R.Path(w,job.point,nil,true,false,nil,job.reachable)then return job.point end
    end
    local nextjob=R.MeleePlan(w)
    if not nextjob then return nil end
    nextjob.started=job and job.cast==w.state.melee_started and job.started or false
    w.corner_dodge=nextjob;w.c.next_move=nil
    return nextjob.point
end
-- Ordinary melee only: let the existing attack thread finish another normal swing if escape still fits.
-- Never used for the melee reserved to prepare a cage escape.
function R.MeleeOutputWindow(w,goal)
    if w.moving then return false end -- 机制赶路中不重启攻击线程贪新一刀，再立刻把它停掉。
    local s=w.state;if w.corner_dodge and w.corner_dodge.cast==s.melee_started and w.corner_dodge.started then return false end
    if s.frame>=32 or w.corner_dodge and goal==w.corner_dodge.point and not w.corner_dodge.reachable then return false end
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local length=distance(p,goal)
    if length<.01 then return false end
    local safe=((TUNING and TUNING.STALKER_HIT_RANGE) or 3.8)+radius(w.c.player)+.2
    local dx,dz=(goal.x-p.x)/length,(goal.z-p.z)/length
    local x,z=p.x-bp.x,p.z-bp.z;local dot=x*dx+z*dz
    local travel=math.max(0,-dot+math.sqrt(math.max(0,dot*dot+safe*safe-x*x-z*z)))
    if w.corner_dodge and goal==w.corner_dodge.point and (w.corner_dodge.exit or w.corner_dodge.points) then
        travel=w.corner_dodge.travel -- 必须算完整两段，不能把进通道的短步当成已躲开。
    end
    local remaining=(32-s.frame)/30-w.c:Latency()-.10-travel/math.max(1,w.c:Speed()*.95)
    local name,frame=O.Animation(w.c.player)
    local commit=8/30
    if name=="atk" then commit=math.max(0,8-frame)/30 end
    -- Special weapon animations have different windups; keep their current dodge behavior.
    local held=w.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if held and (held:HasTag("whip") or held:HasTag("pocketwatch") or held:HasTag("rangedweapon")) then return false end
    return remaining>=commit+.05
end
function R.Zones(w)
    local zones={};local c=w.c;local p=c.player
    w.lanes={}
    for _,e in ipairs(w.entities or {}) do if O.Live(e) then
        local n=e.prefab;local r
        if n=="fossilspike2" and O.SpikeDanger(e,c:Latency()) then r=.7+radius(p)+.2
        elseif O.SolidCage(e) then r=radius(e)+radius(p)+.15
        elseif e~=w.boss and e~=w.focus and not O.IsMinion(e) and n~="shadowchanneler" then
            local seen=c.observed and c.observed[e.GUID]
            if seen and seen.dodge then
                r=seen.move and seen.move.radius or 4
            end
        end
        if r then zones[#zones+1]={pos=e:GetPosition(),radius=r,entity=e} end
        if e~=w.boss then local lane=Incoming.Lane(c,e);if lane then w.lanes[#w.lanes+1]=lane end end
    end end
    for _,z in ipairs(c.hazards or {}) do zones[#zones+1]=z end
    return zones
end
function R.Risk(w,q)
    local total=0
    for _,z in ipairs(w.zones or {}) do total=total+math.max(0,z.radius-distance(q,z.pos))^2 end
    for _,lane in ipairs(w.lanes or {}) do total=total+Incoming.Risk(lane,q)^2 end
    return total
end
local function terrain(q)
    local map=TheWorld and TheWorld.Map
    return not map or (not map.IsPassableAtPoint or map:IsPassableAtPoint(q.x,0,q.z))
        and (not map.IsOceanAtPoint or not map:IsOceanAtPoint(q.x,0,q.z))
end
function R.Passable(q)
    local map=TheWorld and TheWorld.Map
    return terrain(q) and (not map or not map.IsPointNearHole or not map:IsPointNearHole(q))
end
-- 战斗不钻中庭栅栏缝；按人物宽度留缓冲，不能只相信中心点寻路。
local function fencebuffer(w,e) return math.max(1.25,radius(e)+radius(w.c.player)+.35) end
function R.FenceClear(w,q)
    if w and w.route_frame then
        for _,item in ipairs(w.route_frame.blockers)do
            local dx,dz=q.x-item.x,q.z-item.z
            if dx*dx+dz*dz<item.r*item.r then return false end
        end
        return true
    end
    for _,e in ipairs(w and w.obstacles or {})do if e:IsValid() then
        local r=(R.StaticRadius(e) or radius(e))+radius(w.c.player)+staticbuffer(e)
        if q:DistSq(e:GetPosition())<r*r then return false end
    end end
    for _,e in ipairs(w and w.fences or {}) do if e:IsValid() then
        local r=fencebuffer(w,e)
        if q:DistSq(e:GetPosition())<r*r then return false end
    end end
    return true
end
function R.FencePath(w,p,q)
    for _,e in ipairs(w and w.fences or {})do if e:IsValid() then
        local ep=e:GetPosition();local limit=math.min(fencebuffer(w,e),math.max(0,distance(p,ep)-.01))
        if cuts(p,q,ep.x,ep.z,limit)then return false end
    end end
    return true
end
function R.Clearance(q,w)
    local cache=w and w.route_frame and w.route_frame.clearance
    if cache and cache[q.x] and cache[q.x][q.z]~=nil then return cache[q.x][q.z]end
    local open=0;local pf=TheWorld and TheWorld.Pathfinder
    for i=0,7 do
        local a=i*math.pi/4
        local v=Vector3(q.x+math.cos(a)*2,0,q.z+math.sin(a)*2)
        if terrain(v) and R.FenceClear(w,v) and (not w or not R.Blocker(w,q,v))
            and (not pf or pf:IsClear(q.x,0,q.z,v.x,0,v.z,{ignorecreep=true,ignorewalls=false})) then open=open+1 end
    end
    if cache then cache[q.x]=cache[q.x] or {};cache[q.x][q.z]=open end
    return open
end
-- 原版atrium_gate:IsObjectInAtriumArena按两轴14.55码判断，不是圆，也不是全部陆地。
function R.InArena(w,q)
    if not w.center then return true end
    -- 只使用原版边界和真实人物半径；不先加厚边界，再给特定雕像添加通行例外。
    local pr=w.route_frame and w.route_frame.player_radius or radius(w.c.player)
    local limit=14.55-pr-.01
    return math.abs(q.x-w.center.x)<limit and math.abs(q.z-w.center.z)<limit
end
-- 攻击结算前所有移动共享同一安全半径；巡游/清落点不能从侧面重新切回伤害圈。
function R.HitFloor(w)
    if not w.boss then return nil end
    local frame=w.route_frame
    local name,f
    if frame then name,f=frame.anim,frame.animframe else name,f=O.Animation(w.boss)end
    local lag=frame and frame.lag or w.c:Latency();local player=w.c.player
    if name=="attack" and f<=32+math.ceil(lag*30)+2 then
        if frame and frame.attack_floor then return frame.attack_floor end
        local combat=w.boss.replica.combat
        local result=math.max(3.8,(combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2.4)+1.4)
            +(frame and frame.player_radius or radius(player))+.85
        if frame then frame.attack_floor=result end
        return result
    elseif name=="spike" and w.spike_guard and w.spike_guard==w.state.spike_count
        and f<=51+math.ceil(lag*30)+2 then
        return 3.5+radius(player)+.45
    end
end
function R.Path(w,q,target,escape,edge_exit,origin,physical)
    local c=w.c;local frame=w.route_frame;local p=origin or frame and frame.player_pos or c.player:GetPosition()
    if frame then frame.paths=frame.paths+1 end
    -- Blocker已连续检查栅栏，不能在这里再跑同一遍FencePath。
    local valid
    if frame then
        local row=frame.pointclear[q.x];valid=row and row[q.z]
        if valid==nil then
            valid=R.Passable(q) and R.InArena(w,q) and R.FenceClear(w,q)
            frame.pointclear[q.x]=row or {};frame.pointclear[q.x][q.z]=valid
        end
    else valid=R.Passable(q) and R.InArena(w,q) and R.FenceClear(w,q) end
    if not valid then return false,"endpoint" end
    local blocker=R.Blocker(w,p,q)
    if blocker then return false,"static:"..tostring(blocker.prefab) end
    local pf=TheWorld and TheWorld.Pathfinder

    local player_radius=frame and frame.player_radius or radius(c.player);local hitfloor=R.HitFloor(w)
    -- geometry-only queries are explicit; object identity must not disable the melee safety floor.
    local side=physical==true
    if side then hitfloor=nil end
    if w.boss then
        local bp=frame and frame.boss_pos or w.boss:GetPosition();local initial=distance(p,bp)
        local body=(frame and frame.boss_radius or radius(w.boss))+player_radius+.15
        local limit=math.max(math.min(body,initial-.01),hitfloor and math.min(hitfloor,initial-.01) or 0)
        if w.avoid_boss and not side then
            local avoid=math.min(w.avoid_boss,initial-.01)
            if edge_exit and initial<w.avoid_boss then avoid=math.max(body,initial-.3)end
            limit=math.max(limit,avoid)
        end
        if cuts(p,q,bp.x,bp.z,limit)then return false,"boss_body" end
        if edge_exit and w.avoid_boss and distance(q,bp)<initial-.01 then return false end
    end
    -- 实体碰撞做整段精确检查；每个实体的位置/半径只读取一次。
    if frame then
        for _,item in ipairs(frame.bodies)do if item.entity~=target then
            local dx,dz=p.x-item.x,p.z-item.z
            if cuts(p,q,item.x,item.z,math.min(item.r,math.sqrt(dx*dx+dz*dz)-.01))then return false,"entity_body" end
        end end
    else
        for _,e in ipairs(w.bodies or {})do if e~=target and e~=w.boss then
            local ep=e:GetPosition();local r=radius(e)+player_radius+.1
            if cuts(p,q,ep.x,ep.z,math.min(r,distance(p,ep)-.01))then return false end
        end end
    end
    if pf and not pf:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false}) then
        -- 中庭实体已经做整段体积检查；格点墙栅不能再把实体旁的真实通道整格封死。
        -- ignorewalls只移除格点墙，下面仍检查Boss/实体身体、地形、洞口和危险区。
        if not w.center or not pf:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=true})then return false,"pathfinder" end
        if frame then frame.grid_fallbacks=frame.grid_fallbacks+1 end
    end
    local initial=R.Risk(w,p);local final=R.Risk(w,q)
    local length=distance(p,q);local steps=math.max(2,math.ceil(length/.5))
    local dx,dz=(q.x-p.x)/steps,(q.z-p.z)/steps
    local map=TheWorld and TheWorld.Map;local starting_passable
    -- 地形、洞口与动态危险区仍按原间距逐点检查；矩形中庭边界在端点已满足，线段内不会越界。
    for i=1,steps do
        local v=Vector3(p.x+dx*i,0,p.z+dz*i)
        if not terrain(v) or not R.InArena(w,v) then return false end
        if map and map.IsPointNearHole and map:IsPointNearHole(v) then
            if starting_passable==nil then starting_passable=R.Passable(p) end
            if starting_passable or length*i/steps>.55 then return false end
        end
        if R.Risk(w,v)>initial+.03 then return false end
    end
    return initial==0 and final==0 or final<initial-.01 or escape and final<=initial+.001
end
-- 雕像到真实边界的缝隙能容纳人物时，显式加入通道中线；不把贴边误判成无路。
function R.EdgePoints(w)
    local points={};local seen={};if not w.center then return points end
    local c=w.center;local pr=radius(w.c.player);local limit=14.55-pr-.01
    for _,e in ipairs(w.obstacles or {})do if e:IsValid() and staticbuffer(e)<.2 then
        local ep=e:GetPosition();local clearance=(R.StaticRadius(e) or radius(e))+pr+staticbuffer(e)
        for _,axis in ipairs({"x","z"})do
            local other=axis=="x" and "z" or "x";local sign=ep[axis]>=c[axis] and 1 or -1
            local inner=math.abs(ep[axis]-c[axis])+clearance
            if inner<limit and inner>limit-2 then
                local across=c[axis]+sign*(inner+limit)/2
                for _,along in ipairs({ep[other]-clearance-.12,ep[other],ep[other]+clearance+.12,w.c.player:GetPosition()[other]})do
                    local q=axis=="x" and Vector3(across,0,along) or Vector3(along,0,across)
                    local key=string.format("%.3f:%.3f",q.x,q.z)
                    if not seen[key] and R.InArena(w,q) and R.Passable(q) and R.FenceClear(w,q) then
                        seen[key]=true;points[#points+1]=q
                    end
                end
            end
        end
    end end
    return points
end
-- 直达被大门/栅栏挡住时，用有限场内节点找分段路线。只在调用方重规划时执行。
function R.Waypoint(w,goal,outer)
    local p=w.c.player:GetPosition()
    if (not outer or R.OuterPath(w,goal,p)) and R.Path(w,goal,nil,true) then return goal,distance(p,goal) end
    local center=w.center or w.home or p;local nodes={p,goal}
    for x=-10,10,5 do for z=-10,10,5 do
        local q=Vector3(center.x+x,0,center.z+z)
        if R.InArena(w,q) and R.Passable(q) and R.FenceClear(w,q) and R.Risk(w,q)==0 then nodes[#nodes+1]=q end
    end end
    if outer then
        for _,v in ipairs({{-13,-10},{-13,0},{-13,10},{13,-10},{13,0},{13,10},{-10,-13},{0,-13},{10,-13},{-10,13},{0,13},{10,13}}) do
            local q=Vector3(center.x+v[1],0,center.z+v[2])
            if R.InArena(w,q) and R.Passable(q) and R.FenceClear(w,q) then nodes[#nodes+1]=q end
        end
    end
    local corners=R.FightCorners(w)
    if corners then for i,q in ipairs(corners) do
        local entry=R.Point(q,corners[3-i],1.8)
        if R.InArena(w,entry) and R.Passable(entry) and R.FenceClear(w,entry) then nodes[#nodes+1]=entry end
    end end
    for _,q in ipairs(R.EdgePoints(w))do nodes[#nodes+1]=q end
    local costs={[1]=0};local first={};local done={}
    for _=1,#nodes do
        local current,value
        for i,v in pairs(costs) do if not done[i] and (not value or v<value) then current,value=i,v end end
        if not current then break end
        if current==2 then return first[2],value end
        done[current]=true
        for i,q in ipairs(nodes) do if not done[i] then
            local length=distance(nodes[current],q)
            if (i==2 or length<=7.2) and (not costs[i] or value+length<costs[i])
                and (not outer or R.OuterPath(w,q,nodes[current])) and R.Path(w,q,nil,true,false,nodes[current]) then
                costs[i]=value+length;first[i]=current==1 and q or first[current]
            end
        end end
    end
end
function R.Choose(w,goal,target,escape)
    local p=w.c.player:GetPosition()

    local length=math.min(4,distance(p,goal))
    if length<.1 then return p end
    local desired=R.Point(p,goal,length)
    local initial=R.Clearance(p,w);local edge=initial<7 or R.Clearance(desired,w)<7
    w.edge_routing=edge
    if not edge and R.Path(w,desired,target,escape) then return desired end
    local angle=math.atan2(goal.z-p.z,goal.x-p.x);local best,score
    -- 贴边时开阔程度优先于原目标；短切线能离开角落，不要求先走进死角再回头。
    local lengths={length,math.min(1.5,length)}
    local function consider(q,relax)
        if R.Path(w,q,target,escape,relax) then
            local clear=R.Clearance(q,w)
            local value=q:DistSq(goal)+R.Risk(w,q)*100+(8-clear)*40
            if edge and clear<initial then value=value+100 end
            if edge and w.center then value=value+q:DistSq(w.center)*.015 end
            if w.point then value=value+q:DistSq(w.point)*.12 end
            if not score or value<score then best,score=q,value end
        end
    end
    for _,step in ipairs(lengths) do for i=0,23 do
        local offset=math.ceil(i/2)*math.pi/12*(i%2==0 and -1 or 1)
        consider(Vector3(p.x+math.cos(angle+offset)*step,0,p.z+math.sin(angle+offset)*step),false)
    end
        -- 有长段可走时不再让半码短段靠“离目标近一点”胜出；短步仅用于真受阻脱困。
        if best then break end
    end
    if not best and edge then
        -- 已经被堵在边上时，允许短切线暂时少量靠近攻击圈，但绝不穿Boss碰撞体。
        for i=0,23 do local a=i*math.pi/12;consider(Vector3(p.x+math.cos(a)*.6,0,p.z+math.sin(a)*.6),true) end
    end
    return best
end
-- Phase one prefers the two pillar pockets; a live lap prefers its current perimeter leg.
-- Preference only ranks physically valid complete cage exits; it never weakens the hit deadline.
function R.CageSideCost(w,q)
    local pair=R.FightCorners(w);if not pair then return 0 end
    local a,c
    if w.cycle and w.cycle.route_goal then a=w.c.player:GetPosition();c=w.cycle.route_goal
    else a,c=pair[1],pair[2] end
    if not a or not c then return 0 end
    local dx,dz=c.x-a.x,c.z-a.z;local length=math.sqrt(dx*dx+dz*dz)
    if length<.1 then return 0 end
    return math.abs((q.x-a.x)*dz-(q.z-a.z)*dx)/length
end
-- 一次诱牢只保存一条完整路线：人物 -> 分段绕障碍 -> 等牢带 -> 已验证出口。
-- 局部短躲、贴边评分和外围巡游不再分别改写正在执行的诱牢路线。
local function routepath(w,points,origin)
    local p=origin or w.c.player:GetPosition();local length=0
    for _,q in ipairs(points)do length=length+distance(p,q);p=q end
    return length
end
local function installretreat(w,points,exit,complete,length,hitok,preview)
    local q={points=points,index=1,band=#points,mode="prepare",cast=w.state.melee_started,
        complete=complete,hit_ok=hitok,length=length,created=GetTime(),boss=w.boss:GetPosition()}
    if exit then q.points[#q.points+1]=exit end
    if preview then return q end
    w.retreat=q;w.corner_dodge=nil
    w.bait_point=complete and points[q.band] or nil;w.bait_hold=nil
    w.escape_point=exit or points[#points];w.escape_turn=q.band>1 and points[1] or nil;w.escape_enough=complete
    w.escape_reach=distance(w.escape_point,w.boss:GetPosition())
    return q
end
function R.PlanRetreat(w,preview,short)
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local capture,resolve=w:Ranges()
    local wanted=short and 3.8+radius(w.c.player)+.55 or math.min(capture-.1,resolve-.1)
    local nodes={p};local goals={};local exits={};local exitlengths={};local bands={}
    local function bandkey(q)return string.format("%.3f:%.3f",q.x,q.z)end
    local function add(q)
        if short and p:DistSq(q)>9^2 then return end
        if not R.InArena(w,q) or not R.Passable(q) or not R.FenceClear(w,q) or R.Risk(w,q)>0 then return end
        for i,v in ipairs(nodes)do if v:DistSq(q)<.02^2 then return i end end
        nodes[#nodes+1]=q;return #nodes
    end
    local function band(q)
        local key=bandkey(q);if bands[key] then return end;bands[key]=true
        if not R.InArena(w,q) or not R.Passable(q) or not R.FenceClear(w,q) then return end
        if short then local i=add(q);if i then goals[i]=true;exitlengths[i]=0 end;return end
        local exit,travel=R.SnareExit(w,q,0,resolve,true)
        if exit and distance(exit,bp)>=resolve+.7 then local i=add(q);if i then goals[i]=true;exits[i]=exit;exitlengths[i]=travel end end
    end
    for i=0,31 do local a=i*math.pi/16;band(Vector3(bp.x+math.cos(a)*wanted,0,bp.z+math.sin(a)*wanted)) end
    local edges=R.EdgePoints(w)
    for _,q in ipairs(edges)do
        add(q)
        -- 精确求通道中线与识别带交点，不能用15度采样漏掉只有几厘米余量的窄通道。
        local dx,dz=q.x-bp.x,q.z-bp.z
        if math.abs(dx)<wanted then local z=math.sqrt(wanted*wanted-dx*dx);band(Vector3(q.x,0,bp.z+z));band(Vector3(q.x,0,bp.z-z)) end
        if math.abs(dz)<wanted then local x=math.sqrt(wanted*wanted-dz*dz);band(Vector3(bp.x+x,0,q.z));band(Vector3(bp.x-x,0,q.z)) end
    end
    local center=w.center or w.home or p
    if not short then for x=-10,10,5 do for z=-10,10,5 do add(Vector3(center.x+x,0,center.z+z)) end end end
    for _,e in ipairs(w.obstacles or {})do if e:IsValid() and (not short or p:DistSq(e:GetPosition())<7^2) then
        local ep=e:GetPosition();local r=(R.StaticRadius(e) or radius(e))+radius(w.c.player)+staticbuffer(e)+.13
        local count=r>2 and 16 or 8
        for i=0,count-1 do local a=i*2*math.pi/count;add(Vector3(ep.x+math.cos(a)*r,0,ep.z+math.sin(a)*r)) end
    end end
    local body=radius(w.boss)+radius(w.c.player)+.25
    for i=0,15 do local a=i*math.pi/8;add(Vector3(bp.x+math.cos(a)*body,0,bp.z+math.sin(a)*body)) end
    -- 多目标A*优先走向最近完整出口；找到数条完整方案后即比较，不展开整张场地。
    -- 每条候选的实体碰撞和危险区检查不变，只有搜索顺序与展开范围改变。
    local heuristic={}
    local preparation_budget=w.c:Speed()*.85*math.max(0,25.5/30-w.c:Latency()*.5-.25)
    for i,v in ipairs(nodes)do
        local best
        for goal in pairs(goals)do
            local h=distance(v,nodes[goal])+(short and 0 or exitlengths[goal]*4+(exitlengths[goal]>preparation_budget and 1000 or 0))
            if not best or h<best then best=h end
        end
        heuristic[i]=best or 0
    end
    local costs={[1]=0};local previous={};local done={};local found=0
    for _=1,#nodes do
        local current,value,priority
        for i,v in pairs(costs)do if not done[i] and (not priority or v+heuristic[i]<priority)then current,value,priority=i,v,v+heuristic[i] end end
        if not current then break end
        done[current]=true
        if goals[current] then found=found+1;if found>=(short and 4 or 3)then break end end
        local candidates={};local origin=nodes[current]
        for i,q in ipairs(nodes)do if not done[i] then
            local n=distance(origin,q)
            if n<=8 and (not costs[i] or value+n<costs[i])then
                local sector=math.floor((math.atan2(q.z-origin.z,q.x-origin.x)+math.pi)*4/math.pi)%8
                candidates[#candidates+1]={i=i,length=n,sector=sector}
            end
        end end
        table.sort(candidates,function(a,b)return a.length<b.length end)
        local connected={}
        for _,edge in ipairs(candidates)do if not connected[edge.sector] then
            if R.Path(w,nodes[edge.i],nil,true,false,origin,true)then
                costs[edge.i]=value+edge.length;previous[edge.i]=current;connected[edge.sector]=true
            end
        end end
    end
    local function reconstruct(i)
        local reverse={};while i and i~=1 do reverse[#reverse+1]=nodes[i];i=previous[i] end
        if #reverse==0 then return {p} end
        local path={};for j=#reverse,1,-1 do path[#path+1]=reverse[j] end
        -- 只删掉已核对可直达的冗余节点，不把转角提前截成一条会切进雕像的对角线。
        local result={};local origin=p;local nextindex=1
        while nextindex<=#path do
            local chosen=nextindex
            for j=#path,nextindex,-1 do if R.Path(w,path[j],nil,true,false,origin,true)then chosen=j;break end end
            result[#result+1]=path[chosen];origin=path[chosen];nextindex=chosen+1
        end
        return result
    end
    local seconds=w.state.anim=="attack" and math.max(0,(32-(w.state.frame or 0))/30-w.c:Latency()-.1) or math.huge
    local budget=w.c:Speed()*(short and .95 or .65)*seconds;local safe=3.8+radius(w.c.player)+.2
    local best,exit,bestscore,bestlength,hitok
    for i in pairs(goals)do if costs[i] then
        local path=reconstruct(i);local length=routepath(w,path,p)
        local impact=routeposition(p,path,budget);local clear=distance(impact,bp)>=safe
        local escape_budget=w.c:Speed()*.85*math.max(0,25.5/30-w.c:Latency()*.5-.25)
        local score=(clear and 10000 or distance(impact,bp)*100)-length
        if not short then score=score+(exitlengths[i]<=escape_budget and 1000 or 0)-exitlengths[i]*4-R.CageSideCost(w,exits[i])*.1 end
        if not bestscore or score>bestscore then best,exit,bestscore,bestlength,hitok=path,exits[i],score,length,clear end
    end end
    if best then return installretreat(w,best,exit,true,bestlength,hitok,preview) end
    -- 真没有完整出口时只执行一个已验证的撤离段；不再来回调用短躲和Reposition。
    for i,value in pairs(costs)do if i~=1 then
        local gain=distance(nodes[i],bp)-distance(p,bp)
        local score=gain*10-value
        if gain>.5 and (not bestscore or score>bestscore)then best=reconstruct(i);bestscore=score;bestlength=value end
    end end
    return installretreat(w,best or {p},nil,false,bestlength or 0,false,preview)
end
function R.BeginRetreat(w)
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local capture,resolve=w:Ranges()
    local safe=3.8+radius(w.c.player)+.2
    local budget=w.c:Speed()*.65*math.max(0,(32-(w.state.frame or 0))/30-w.c:Latency()-.1)
    local band=R.CapturePoint(w,p,capture,resolve)
    local exit,travel,available=R.SnareExit(w,band,0,resolve,true)
    if exit and travel<=available and R.Path(w,band,nil,true,false,p,true) then
        local hitok=w.state.anim~="attack" or distance(routeposition(p,{band},budget),bp)>=safe
        if hitok then return installretreat(w,{band},exit,true,distance(p,band),true)end
    end
    local full=R.PlanRetreat(w,true)
    local points={};local hitok=full.hit_ok
    if not hitok and w.state.anim=="attack" then
        local melee=R.MeleePlan(w,true) -- 完整图已求过，只补局部首段，不再跑第二张图。
        if melee then
            local endpoint=melee.points[#melee.points];local join
            for i=full.band,1,-1 do
                if R.Path(w,full.points[i],nil,true,false,endpoint,true)then join=i;break end
            end
            if join then
                for _,q in ipairs(melee.points)do points[#points+1]=q end
                for i=join,full.band do points[#points+1]=full.points[i]end
                hitok=melee.reachable
            end
        end
    end
    if #points==0 then for i=1,full.band do points[i]=full.points[i]end end
    -- 去掉能直达且仍满足普攻时限的中间落点，不为同一直线多次停步。
    while #points>1 and R.Path(w,points[2],nil,true,false,p,true)
        and (w.state.anim~="attack" or distance(routeposition(p,{points[2]},budget),bp)>=safe)do table.remove(points,1)end
    hitok=w.state.anim~="attack" or distance(routeposition(p,points,budget),bp)>=safe
    return installretreat(w,points,full.complete and full.points[#full.points] or nil,full.complete,routepath(w,points),hitok)
end
function R.UpdateRetreatBand(w,point,exit)
    local q=w.retreat
    if q and q.mode=="prepare" then
        q.points[q.band]=point;q.points[#q.points]=exit;q.index=q.band;q.waited=false
    end
    w.bait_hold=nil;w.bait_point=point;w.escape_point=exit;w.escape_turn=nil;w.escape_enough=true
end
function R.RetreatCast(w)
    local q=w.retreat;if not q or q.snare==w.state.snare_started then return end
    local _,resolve=w:Ranges()
    -- 真实骨牢优先：用当前实际位置求最快可执行出口，仍由同一条路线事务执行。
    -- 不能先跑到旧等牢点才拐向出口，否则白白消耗25.5帧。
    local goal=R.SnareRun(w,w.state.frame,resolve)
    if not w.snare_run.reachable and goal:DistSq(w.c.player:GetPosition())>.1^2 then
        local origin=w.c.player:GetPosition()
        local extended=R.Point(origin,goal,exitlength(origin,goal,w.boss:GetPosition(),resolve+.7))
        if R.Path(w,extended,nil,true)then
            goal=extended;w.snare_run.point=goal;w.snare_run.travel=distance(origin,goal)
        end
    end
    q.points={goal};q.index=1;q.band=1;q.mode="escape";q.snare=w.state.snare_started
    q.remaining=w.snare_run.travel
end
function R.RetreatReady(w)
    local q=w.retreat;if not q or q.mode~="prepare" or not q.complete or q.index~=q.band then return false end
    local capture,resolve=w:Ranges();local p=w.c.player:GetPosition();local d=distance(p,w.boss:GetPosition())
    return d>=capture-.3 and d<capture-.02 and R.SnareExit(w,p,0,resolve)~=nil
end
function R.RetreatGoal(w)
    local q=w.retreat;if not q then return end
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local capture,resolve=w:Ranges()
    if q.mode=="escape" then
        if p:DistSq(q.points[q.index])<.3^2 and distance(p,bp)<=resolve+.15 then
            q.points={R.SnareRun(w,w.state.frame,resolve)};q.index=1;q.band=1
        end
    else
        while q.index<q.band and p:DistSq(q.points[q.index])<.25^2
            and R.Path(w,q.points[q.index+1],nil,true,false,p,true)do q.index=q.index+1;w.c.next_move=nil end
        if q.complete and q.index==q.band then
            if R.RetreatReady(w)then q.waited=true;return nil,true end
            -- 识别带是相对当前Boss的位置；Boss在首次到达前已经追近，也必须更新。
            -- 不能等一个从未成立的waited标记，守着旧坐标让Boss一路走到脸上。
            if q.waited or p:DistSq(q.points[q.band])<.35^2 then
                local wanted=math.min(capture-.1,resolve-.1);local last=q.points[#q.points]
                local band=distance(p,bp)>wanted and R.CapturePoint(w,p,capture,resolve)
                    or R.Point(p,last,exitlength(p,last,bp,wanted))
                local exit=R.SnareExit(w,band,0,resolve)
                if not exit or not R.Path(w,band,nil,true,false,p,true)then return nil,false,"blocked"end
                q.points[q.band]=band;q.points[#q.points]=exit
                w.bait_point=band;w.escape_point=exit;w.c.next_move=nil
            end
        end
    end
    local goal=q.points[q.index]
    local physical=w.state.anim=="attack" and distance(p,bp)<3.8+radius(w.c.player)+.2
    if R.Path(w,goal,nil,true,false,nil,physical)then
        if w.snare_run and q.mode=="escape"then w.snare_run.point=goal end
        return goal,false
    end
    return nil,false,"blocked"
end
-- 近身震地只走最短局部出圈线，不让通用贴边评分把短撤改成绕回Boss身边。
function R.ShortDodge(w,safe)
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition();local run=w.shock_run
    if run and run.cast==w.state.spike_count and R.Path(w,run.point,nil,true) then
        w.shock_point=run.point;return run.point
    end
    local angle=math.atan2(p.z-bp.z,p.x-bp.x);local best,travel
    for i=0,12 do
        local a=angle+math.ceil(i/2)*math.pi/12*(i%2==0 and -1 or 1)
        local ray=Vector3(p.x+math.cos(a)*20,0,p.z+math.sin(a)*20)
        local len=exitlength(p,ray,bp,safe)
        local q=Vector3(p.x+math.cos(a)*len,0,p.z+math.sin(a)*len)
        if R.Path(w,q,nil,true) and (not travel or len<travel) then
            best,travel=q,len;if i==0 then break end
        end
    end
    w.shock_point=best;w.shock_run=best and {cast=w.state.spike_count,point=best} or nil
    return best or R.Point(bp,p,safe)
end
-- 只接受能在25.5帧生效前走完、且起步不靠近Boss的合法出圈线。
-- origin可为准备中的诱牢点；这样“场内有远角”不再等于“从诱牢点来得及跑到”。
function R.SnareExit(w,origin,frame,resolve,geometry_only)
    local bp=w.boss:GetPosition();local safe=resolve+.15
    -- 骨牢CD晚于这次普攻busy结束时，Boss会先追近；准备路线必须为这段追击保留实际纵深。
    local chase=0
    if geometry_only and w.state.anim=="attack" and w.state.ready and w.state.ready.snare then
        local busy=math.max(0,(63-(w.state.frame or 0))/30)
        chase=math.max(0,O.ReadyIn(w.state,"snare",GetTime())-busy)*4.2
    end
    -- 客户端标称速度不是每帧有效位移；为起步与执行损耗保留余量。
    local seconds=math.max(0,(25.5-frame)/30-w.c:Latency()*.5-.25)
    local budget=math.max(0,w.c:Speed()*.85*seconds)
    if distance(origin,bp)>=safe then return origin,0,budget end
    local angle=math.atan2(origin.z-bp.z,origin.x-bp.x);local goal,travel,score
    local directions={}
    for i=0,12 do directions[#directions+1]=angle+math.ceil(i/2)*math.pi/12*(i%2==0 and -1 or 1) end
    for _,a in ipairs({0,math.pi/2,math.pi,3*math.pi/2})do directions[#directions+1]=a end
    for _,a in ipairs(directions)do
        local dx,dz=math.cos(a),math.sin(a)
        local ray=Vector3(origin.x+dx*40,0,origin.z+dz*40)
        local length=exitlength(origin,ray,bp,safe)
        local q=Vector3(origin.x+dx*length,0,origin.z+dz*length)
        local runway=chase==0 or R.Path(w,Vector3(q.x+dx*(.65+chase),0,q.z+dz*(.65+chase)),nil,true,false,origin,true)
        if runway and (geometry_only or length<=budget) and R.Path(w,q,nil,true,false,origin) and (not score or length+R.CageSideCost(w,q)*2<score) then
            score=length+R.CageSideCost(w,q)*2
            local extension=Vector3(q.x+dx*.65,0,q.z+dz*.65)
            goal,travel=R.Path(w,extension,nil,true,false,origin) and extension or q,length
            if geometry_only and length<=math.max(0,safe-distance(origin,bp))+.01
                and distance(goal,bp)>=resolve+.7 then return goal,travel,budget end
        end
    end
    return goal,travel,budget
end
-- 同一次技能连续执行；只有新障碍阻断路径才换向，不继承远角/横穿路线。
function R.SnareRun(w,frame,resolve)
    local p=w.c.player:GetPosition();local bp=w.boss:GetPosition()
    local cast=w.state.anim=="attack1" and w.state.snare_started or GetTime()-frame/30
    local run=w.snare_run
    if run and math.abs(run.cast-cast)<.25 and R.Path(w,run.point,nil,true)
        and (p:DistSq(run.point)>.5^2 or distance(p,bp)>resolve+.15) then return run.point end
    local goal,travel,budget=R.SnareExit(w,p,frame,resolve)
    local reachable=goal~=nil
    if not goal then
        -- 已无完整步行解时，仍最大化剩余帧内的径向增距；不选先绕回Boss侧面的长线。
        local angle=math.atan2(p.z-bp.z,p.x-bp.x);local score
        local directions={}
        for i=0,12 do directions[#directions+1]=angle+math.ceil(i/2)*math.pi/12*(i%2==0 and -1 or 1) end
        for _,a in ipairs({0,math.pi/2,math.pi,3*math.pi/2})do directions[#directions+1]=a end
        for _,length in ipairs({math.max(.75,budget),math.max(.75,budget*.5),.75}) do
            for _,a in ipairs(directions)do
                local q=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
                local gain=distance(q,bp)-distance(p,bp)
                if gain>0 and R.Path(w,q,nil,true) and (not score or gain>score) then
                    goal,score,travel=q,gain,length
                end
            end
        end
    end
    goal=goal or p
    w.snare_run={cast=cast,point=goal,reachable=reachable,budget=budget,travel=travel or 0}
    return goal
end
-- 识别带只是纯几何计算；它不改路线，不清转角，不保存另一个执行状态。
function R.CapturePoint(w,from,capture,resolve)
    if not capture then capture,resolve=w:Ranges()end
    return R.Point(w.boss:GetPosition(),from or w.c.player:GetPosition(),math.min(capture-.1,resolve-.1))
end
function R.BaitValid(w,capture,resolve)
    if not w.escape_enough or not w.escape_point or not w.bait_point then return false end
    local bp=w.boss:GetPosition();local wanted=math.min(capture-.1,resolve-.1)
    local target=distance(w.bait_point,bp)
    return target>=wanted-.08 and target<capture
        and distance(w.escape_point,bp)>=resolve+.7
        and R.SnareExit(w,w.bait_point,0,resolve)~=nil
end
function R.Landing(w,wanted,item)
    local c=w.c;local p=c.player:GetPosition();local picker=c.player.components.playeractionpicker
    local best,score
    local function consider(q)
        if p:DistSq(q)<4.5^2 or p:DistSq(q)>14^2 or not R.Passable(q) or not R.InArena(w,q) or not R.FenceClear(w,q) or R.Risk(w,q)>0 then return end
        if w.boss and q:DistSq(w.boss:GetPosition())<4.8^2 then return end
        local map=TheWorld and TheWorld.Map
        if map and map.IsGroundTargetBlocked and map:IsGroundTargetBlocked(q) then return end
        -- 用原版动作候选核对传送区域限制与当前宝石能力，不能把地图内一点当作可施法点。
        local legal=false
        if picker and picker.GetRightClickActions then for _,a in ipairs(picker:GetRightClickActions(q,nil) or {}) do
            if a.action==ACTIONS.BLINK and (not a.invobject or a.invobject==item) then legal=true;break end
        end end
        if not legal then return end
        local value=q:DistSq(wanted)*.1+distance(p,q)*.25+(8-R.Clearance(q,w))*16
        if w.center then value=value+q:DistSq(w.center)*.01 end
        if not score or value<score then best,score=q,value end
    end
    consider(wanted)
    for _,r in ipairs({6,8,10,12}) do for i=0,15 do
        local a=i*math.pi/8;consider(Vector3(p.x+math.cos(a)*r,0,p.z+math.sin(a)*r))
    end end
    return best
end
return R
