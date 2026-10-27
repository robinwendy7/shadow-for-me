-- Lock one perpendicular line and one endpoint for each charge animation.
local Nav=require("shadowself/control/navigation")
return function(c,target,base)
    local a=target and target.AnimState
    local special=target and (target.prefab=="rook" or target.prefab=="rook_nightmare")
    local anim
    if special and a then
        for _,name in ipairs({"atk_pre","paw_loop","atk"}) do
            if a:IsCurrentAnimation(name) then anim=name;break end
        end
    end
    if not anim then
        if c.charge_target==target then c.charge_target=nil;c.charge_data=nil;c.charge_point=nil end
        if c.charge_windup==target then c.charge_windup=nil;c.charge_windup_since=nil end
        return base
    end
    local rook=target.prefab=="rook" or target.prefab=="rook_nightmare"
    if rook and anim=="atk" then
        local p=c.player:GetPosition();local q=target:GetPosition();local r=target.Transform:GetRotation()*math.pi/180
        local dx,dz=p.x-q.x,p.z-q.z
        local along=dx*math.cos(r)-dz*math.sin(r)
        local side=math.abs(dx*math.sin(r)+dz*math.cos(r))
        if along< -1 or side>target:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+1 then
            c.charge_target=nil;c.charge_data=nil;c.charge_point=nil;return false
        end
    end
    if rook and (anim=="atk_pre" or anim=="paw_loop") then
        local early=c.bridge and require("shadowself/control/targetpolicy").ClockworkRook(c.bridge)==target
        if early and require("shadowself/control/arena_rook_window").Allow(c,target) then
            if c.charge_target==target then c.charge_target=nil;c.charge_data=nil;c.charge_point=nil end
            return nil
        end
        local now=GetTime()
        if c.charge_windup~=target then
            local frame=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
            c.charge_windup=target
            c.charge_windup_since=now-(anim=="paw_loop" and .5 or frame/30)
        end
        local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
        local window=math.max(.5,.75-ping/1000)
        if not early and now-c.charge_windup_since<window then
            -- Let original 3014 land its normal swings (about two at normal speed).
            -- Never require two hits if range/speed/latency makes that impossible.
            c.charge_target=nil;c.charge_data=nil;c.charge_point=nil
            return base
        end
    elseif rook then c.charge_windup=nil;c.charge_windup_since=nil end
    if c.charge_target==target and c.charge_anim==anim and c.charge_data then return c.charge_data end
    local p=c.player:GetPosition();local rot=target.Transform:GetRotation()*math.pi/180
    local nx,nz=math.sin(rot),math.cos(rot);local best,score
    for _,sign in ipairs({1,-1}) do
        local v=Vector3(p.x+nx*4*sign,0,p.z+nz*4*sign)
        local safe=Nav.Safe(c,v,target)
        local value=Nav.Risk(c,v,target)+(safe and 0 or 1000)
        if c.actions:SafePoint(v) and (not score or value<score) then best,score=v,value end
    end
    best=best or p
    local data={};for k,v in pairs(base or {}) do data[k]=v end
    data.dist=4;data.point="player";data.update=false;data.angle=math.pi/2
    data.fn=function() return best end
    data.atkanim=function(e) return require("shadowself/native").Get().ENT_util:GetAnimation(e) end
    data.breakdodgefn=function(e)
        if require("shadowself/control/arena_rook_window").Allow(c,e) then return true end
        return require("shadowself/native").Get().ENT_util:GetAngle(e,c.player)>100
    end
    c.charge_target=target;c.charge_anim=anim;c.charge_point=best;c.charge_data=data
    return data
end
