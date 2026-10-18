-- 冻蜂以守卫为圆心找射击角度；蜂后近身范围只在实际出招时成为禁区。
local Nav=require("shadowself/control/navigation")
local G={}
local function radius(e) return e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5 end
local function segment(a,b,q)
    local x,z=b.x-a.x,b.z-a.z;local n=x*x+z*z
    local t=n>0 and math.max(0,math.min(1,((q.x-a.x)*x+(q.z-a.z)*z)/n)) or 0
    return math.sqrt((a.x+x*t-q.x)^2+(a.z+z*t-q.z)^2)
end
function G.Windup(queen)
    return queen.AnimState:IsCurrentAnimation("atk") and
        (queen.AnimState.GetCurrentAnimationFrame and queen.AnimState:GetCurrentAnimationFrame() or 0)<14
end
function G.Shot(c,queen,bee,pos,reach)
    local qp=queen:GetPosition();local bp=bee:GetPosition()
    return pos:DistSq(bp)<=reach^2 and segment(pos,bp,qp)>radius(queen)+.15
end
function G.Point(c,queen,bee,reach,side)
    local p=c.player:GetPosition();local bp=bee:GetPosition();local qp=queen:GetPosition()
    local distance=math.sqrt(p:DistSq(bp));local dx,dz=(p.x-bp.x)/math.max(.01,distance),(p.z-bp.z)/math.max(.01,distance)
    if distance<.01 then dx,dz=1,0 end
    local imminent=G.Windup(queen);local hit=(TUNING.BEEQUEEN_HIT_RANGE or 6)+radius(c.player)+.3
    local physical=radius(queen)+radius(c.player)+.2
    local best,score,bestside
    local function candidate(q,s)
        if segment(p,q,qp)<math.min(physical,math.sqrt(p:DistSq(qp)))-.02 or not Nav.Safe(c,q,queen) then return end
        local danger=imminent and math.max(0,hit-math.sqrt(q:DistSq(qp))) or 0
        local ready=G.Shot(c,queen,bee,q,reach)
        local value=danger*1000+(ready and 0 or 60)+q:DistSq(p)+(side and side~=s and 2 or 0)
        if not score or value<score then best,score,bestside=q,value,s end
    end
    local orbit=math.max(1.5,math.min(distance,reach-.35))
    for _,s in ipairs({side or 1,-(side or 1)}) do
        for _,angle in ipairs({.3,.55,.85,1.15,1.5}) do
            local a=angle*s;local x,z=dx*math.cos(a)-dz*math.sin(a),dx*math.sin(a)+dz*math.cos(a)
            candidate(Vector3(bp.x+x*orbit,0,bp.z+z*orbit),s)
        end
    end
    -- 前摇时优先脱离命中半径，结束后继续围绕守卫找角度。
    if imminent then
        for i=0,23 do local a=i*math.pi/12;candidate(Vector3(p.x+math.cos(a)*3,0,p.z+math.sin(a)*3),side or 1) end
    end
    return best,bestside
end
return G
