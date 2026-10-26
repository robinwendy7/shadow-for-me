local G=require("shadowself/control/newbosses/geometry")
local M={}
local function aim(owner,e,state,f)
    -- 身体8帧后不再转，但内部发射方向到22帧才锁定。用同步仇恨目标估算，
    -- 每帧遵循源码最多2度的转向；不能把身体朝向直接当三路弹道。
    local reset=not state.cast_frame or f<state.cast_frame
    if reset then state.dodge_side=nil end
    local combat=e.replica and e.replica.combat
    local target=combat and combat.GetTarget and combat:GetTarget() or owner.c.player
    local rotation=e.Transform:GetRotation()
    if reset or f<=8 then state.cast_rot=rotation end
    if target and target:IsValid() and f>8 then
        local p,q=e:GetPosition(),target:GetPosition()
        local desired=math.atan2(p.z-q.z,q.x-p.x)*180/math.pi
        local first=reset and 8 or math.max(8,state.cast_frame)
        for _=first+1,math.min(f,22) do
            local delta=(desired-state.cast_rot+180)%360-180
            state.cast_rot=state.cast_rot+math.max(-2,math.min(2,delta*.5))
        end
    end
    state.cast_frame=f
    local a=state.cast_rot*math.pi/180;return {math.cos(a),-math.sin(a)}
end
local function lanes(out,e,origin,basis,pad)
    local x,z=basis[1],basis[2]
    local function point(front,side) return Vector3(origin.x+x*front-z*side,0,origin.z+z*front+x*side) end
    -- 不是从Boss前方1码开始的矩形：侧路出生在(2,+/-4)，本身已有2.4码伤害半径。
    -- 胶囊两端保留圆形，身后约1.5码仍可能被侧路出生判定命中。
    G.Line(out,e,point(3,0),point(11,0),2.4+pad+.35)
    for _,side in ipairs({-4,4}) do G.Line(out,e,point(2,side),point(9,side),2.4+pad+.35) end
end
local function volley(e,state)
    return G.Anim(e,"castlift") and G.Frame(e)<=60
        or state and state.volley_until and GetTime()<state.volley_until or false
end
local function counterwindup(e,state)
    if not G.Anim(e,"hit") or G.Frame(e)>8 or state and state.reflect==true then return false end
    local h=e.replica and e.replica.health
    local percent=h and h.GetPercent and h:GetPercent()
    return not percent or percent<=.95
end
function M.Build(owner,e,out,state,pad)
    local f=G.Frame(e)
    local casting=G.Anim(e,"castlift")
    if not casting then state.cast_frame=nil;state.cast_rot=nil end
    if G.Anim(e,"air_cast") and f>=23 then state.reflect=true
    elseif G.Anim(e,"vine_cast") and f>=23 then state.reflect=false end
    -- hit第8帧即可转反击；提前利用这8帧后撤，不能等aoe开始才跑。
    if counterwindup(e,state) or G.Anim(e,"aoe") and f<=39 then G.Circle(out,e,6+pad+.35) end
    if casting and f<=60 then
        local basis=aim(owner,e,state,f);local origin=e:GetPosition()
        state.aim_basis=basis
        lanes(out,e,origin,basis,pad)
        if f>=33 then
            local finish=f>=40 and 60 or f>=37 and 57 or 53
            state.volley_until=GetTime()+math.max(0,(finish-f)*(FRAMES or 1/30))+owner.c:Latency()
            state.volley_origin=origin;state.volley_basis=basis
        end
    elseif state.volley_until and GetTime()<state.volley_until then
        -- 动画被反击/换模式打断时，已经放出的三批攻击不会跟着消失。
        lanes(out,e,state.volley_origin,state.volley_basis,pad)
    end
    if not volley(e,state) then state.dodge_side=nil end
end
function M.Blocked(e,state)
    return G.Anim(e,"aoe") and G.Frame(e)<=39
        or counterwindup(e,state) or volley(e,state)
        or G.Anim(e,"air_cast") or G.Anim(e,"vine_cast")
        or e:HasTag("NOCLICK") or e:HasTag("noattack")
end
function M.MoveBias(owner,q)
    local p=owner.c.player:GetPosition();local value=0
    for _,e in ipairs(owner.bosses) do if e.prefab=="charlie_boss" then
        local state=owner.states[e]
        if volley(e,state) then
            local o=e:GetPosition();local cross=(p.x-o.x)*(q.z-o.z)-(p.z-o.z)*(q.x-o.x)
            if state.dodge_side and cross*state.dodge_side<-.1 then value=value+30 end
            local b=G.Anim(e,"castlift") and state.aim_basis or state.volley_basis or {G.Basis(e)}
            local front=(q.x-o.x)*b[1]+(q.z-o.z)*b[2]
            value=value+math.max(0,front+1.5)*2+math.max(0,math.sqrt(q:DistSq(o))-5)*2
        end
    end end
    return value
end
function M.Commit(owner,q)
    local p=owner.c.player:GetPosition()
    for _,e in ipairs(owner.bosses) do if e.prefab=="charlie_boss" then
        local state=owner.states[e]
        if volley(e,state) and not state.dodge_side then
            local o=e:GetPosition();local cross=(p.x-o.x)*(q.z-o.z)-(p.z-o.z)*(q.x-o.x)
            if math.abs(cross)>.1 then state.dodge_side=cross>0 and 1 or -1 end
        end
    end end
end
function M.Extra(owner,e,out,state,pad)
    local n=e.prefab
    local fallback=n=="charlie_boss_vines" and 9 or n=="charlie_boss_minion1" and 24*.7 or 24
    local vx,vz=owner:Velocity(e,state,fallback)
    if n=="charlie_boss_vines" then
        if not G.Net(e._emerged,false) then G.Circle(out,e,1.2+pad,nil,vx,vz) end
    elseif n=="charlie_boss_minion1" or n=="charlie_boss_minion2" then
        local impact=n=="charlie_boss_minion1" and 17 or 13
        if G.Frame(e)>=impact then vx,vz=0,0 end
        if G.Frame(e)<impact+3 then G.Circle(out,e,2.4+pad+.35,nil,vx,vz) end
    elseif n=="charlie_boss_projectile" then
        local p=e:GetPosition()
        -- 高空弹不是整条地面封锁；仅预测下降到碰撞高度的短时落点。
        if p.y<4 then G.Circle(out,e,1.2+pad,Vector3(p.x,0,p.z),vx,vz) end
    elseif n=="charlie_boss_runner" then
        if G.Anim(e,"attack") or G.Anim(e,"attack_quick") or G.Anim(e,"run_loop") or G.Anim(e,"run_pre") then
            G.Circle(out,e,1.5+pad,nil,vx,vz)
        end
    end
end
return M
