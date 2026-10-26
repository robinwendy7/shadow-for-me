-- 新Boss的真实形状：圆、扫掠胶囊、矩形、三角。只读取同步位置/动画。
local G={}
function G.Anim(e,name) return e and e.AnimState and e.AnimState:IsCurrentAnimation(name) or false end
function G.Frame(e) return e.AnimState and e.AnimState:GetCurrentAnimationFrame() or 0 end
function G.Net(field,default) if field and field.value then return field:value() end;return default end
function G.Live(e)
    return e and e:IsValid() and not e:HasTag("INLIMBO") and not e:HasTag("dead") and not e:HasTag("isdead")
        and not (e.replica and e.replica.health and e.replica.health:IsDead())
end
function G.Basis(e)
    local a=e.Transform:GetRotation()*math.pi/180;return math.cos(a),-math.sin(a)
end
function G.Local(e,p)
    local q=e:GetPosition();local x,z=G.Basis(e);local dx,dz=p.x-q.x,p.z-q.z
    return dx*x+dz*z,-dx*z+dz*x
end
function G.Point(e,x,z)
    local p=e:GetPosition();local dx,dz=G.Basis(e);return Vector3(p.x+dx*x-dz*z,0,p.z+dz*x+dx*z)
end
function G.Circle(out,e,r,point,vx,vz)
    out[#out+1]={kind="circle",source=e,pos=point or e:GetPosition(),radius=r,vx=vx or 0,vz=vz or 0}
    return out[#out]
end
function G.Line(out,e,a,b,r)
    out[#out+1]={kind="line",source=e,pos=a,finish=b,radius=r};return out[#out]
end
function G.Rect(out,e,from,to,width,pad,basis)
    local x,z=G.Basis(e)
    if basis then x,z=basis[1],basis[2] end
    out[#out+1]={kind="rect",source=e,pos=e:GetPosition(),x=x,z=z,from=from,to=to,width=width,pad=pad}
    return out[#out]
end
function G.Triangle(out,e,a,b,c,pad)
    out[#out+1]={kind="triangle",source=e,pos=a,b=b,c=c,pad=pad}
end
local function segmentxz(px,pz,ax,az,bx,bz)
    local x,z=bx-ax,bz-az;local n=x*x+z*z
    local t=n>0 and math.max(0,math.min(1,((px-ax)*x+(pz-az)*z)/n)) or 0
    return math.sqrt((px-ax-t*x)^2+(pz-az-t*z)^2)
end
local function segment(p,a,b)
    return segmentxz(p.x,p.z,a.x,a.z,b.x,b.z)
end
function G.Depth(h,p,time)
    local a=h.pos;local t=math.min(time or 0,.6)
    if h.kind=="circle" then
        return h.radius-math.sqrt((p.x-a.x-(h.vx or 0)*t)^2+(p.z-a.z-(h.vz or 0)*t)^2)
    elseif h.kind=="line" then return h.radius-segment(p,a,h.finish)
    elseif h.kind=="rect" then
        local dx,dz=p.x-a.x,p.z-a.z;local x,z=dx*h.x+dz*h.z,math.abs(-dx*h.z+dz*h.x)
        if x>=h.from and x<=h.to and z<=h.width then return h.pad+math.min(x-h.from,h.to-x,h.width-z) end
        return h.pad-math.sqrt(math.max(h.from-x,0,x-h.to)^2+math.max(0,z-h.width)^2)
    else
        local b,c=h.b,h.c
        local function cross(u,v) return (p.x-v.x)*(u.z-v.z)-(u.x-v.x)*(p.z-v.z) end
        local d1,d2,d3=cross(a,b),cross(b,c),cross(c,a)
        local inside=not ((d1<0 or d2<0 or d3<0) and (d1>0 or d2>0 or d3>0))
        local d=math.min(segment(p,a,b),segment(p,b,c),segment(p,c,a))
        return h.pad+(inside and d or -d)
    end
end
function G.Risk(shapes,p,time)
    local risk=0;for _,h in ipairs(shapes) do local d=math.max(0,G.Depth(h,p,time));risk=risk+d*d end
    return risk
end
local function bounds(h)
    if h.minx then return end
    local a=h.pos
    if h.kind=="circle" then
        local x,z=a.x+(h.vx or 0)*.6,a.z+(h.vz or 0)*.6;local r=h.radius
        h.minx,h.maxx=math.min(a.x,x)-r,math.max(a.x,x)+r
        h.minz,h.maxz=math.min(a.z,z)-r,math.max(a.z,z)+r
    elseif h.kind=="line" then
        local b,r=h.finish,h.radius
        h.minx,h.maxx=math.min(a.x,b.x)-r,math.max(a.x,b.x)+r
        h.minz,h.maxz=math.min(a.z,b.z)-r,math.max(a.z,b.z)+r
    elseif h.kind=="rect" then
        h.minx,h.maxx,h.minz,h.maxz=math.huge,-math.huge,math.huge,-math.huge
        for _,front in ipairs({h.from,h.to}) do for _,side in ipairs({-h.width,h.width}) do
            local x,z=a.x+h.x*front-h.z*side,a.z+h.z*front+h.x*side
            h.minx,h.maxx=math.min(h.minx,x-h.pad),math.max(h.maxx,x+h.pad)
            h.minz,h.maxz=math.min(h.minz,z-h.pad),math.max(h.maxz,z+h.pad)
        end end
    else
        h.minx,h.maxx=math.min(a.x,h.b.x,h.c.x)-h.pad,math.max(a.x,h.b.x,h.c.x)+h.pad
        h.minz,h.maxz=math.min(a.z,h.b.z,h.c.z)-h.pad,math.max(a.z,h.b.z,h.c.z)+h.pad
    end
end
-- 只剔除在未来0.6秒内也绝不可能与本段路相交的技能；不降低扫描/躲避频率。
function G.Select(shapes,a,b)
    local out={};local minx,maxx=math.min(a.x,b.x),math.max(a.x,b.x)
    local minz,maxz=math.min(a.z,b.z),math.max(a.z,b.z)
    for _,h in ipairs(shapes) do
        bounds(h)
        if h.maxx>=minx and h.minx<=maxx and h.maxz>=minz and h.minz<=maxz then out[#out+1]=h end
    end
    return out
end
-- 连续移动的光束/冲击不能只测未来终点：期间扫过玩家同样会命中。
function G.Window(shapes,p,from,to)
    from=math.max(0,math.min(.6,from or 0));to=math.max(from,math.min(.6,to or from))
    local risk=0
    for _,h in ipairs(shapes) do
        local depth
        if h.kind=="circle" then
            local vx,vz=h.vx or 0,h.vz or 0
            depth=h.radius-segmentxz(p.x,p.z,h.pos.x+vx*from,h.pos.z+vz*from,h.pos.x+vx*to,h.pos.z+vz*to)
        else depth=G.Depth(h,p,from) end
        depth=math.max(0,depth);risk=risk+depth*depth
    end
    return risk
end
return G
