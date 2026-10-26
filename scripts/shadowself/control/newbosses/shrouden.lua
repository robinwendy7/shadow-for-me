-- SGshrouden/optic_blast：门前矩形、地下追踪扩圈、独立光束落点与落地冲击。
local G=require("shadowself/control/newbosses/geometry")
local M={}
local function optic(e)
    return G.Anim(e,"optic_blast_pre1") or G.Anim(e,"optic_blast_pre2")
        or G.Anim(e,"optic_blast_pre3") or G.Anim(e,"optic_blast_loop")
end
function M.Running(e)
    return optic(e) or G.Anim(e,"optic_blast_pst") and G.Frame(e)<=18
end
function M.Passthrough(e)
    return optic(e) and (not G.Anim(e,"optic_blast_pre1") or G.Frame(e)>=11)
        or G.Anim(e,"teleport_loop")
        or G.Anim(e,"teleport_pst") and G.Frame(e)<27
end
function M.Build(owner,e,out,state,pad)
    local f=G.Frame(e)
    if G.Anim(e,"punch_pre") or G.Anim(e,"punch_loop") then
        G.Rect(out,e,0,math.sqrt(6.7^2+3.5^2),3.5,pad)
    elseif G.Anim(e,"teleport_loop") then
        local vx,vz=owner:Velocity(e,state,0)
        local h=G.Circle(out,e,3.9+pad,nil,vx,vz);h.pursuit=true;h.gel=true
    elseif G.Anim(e,"teleport_pst") and f<=28 then G.Circle(out,e,3.9+pad)
    elseif G.Anim(e,"optic_blast_pst") and f<=18 then G.Circle(out,e,3.6+pad)
    elseif optic(e) and not G.Anim(e,"optic_blast_pre1") then
        -- Follower特效可能尚未进入空间查询；从Boss同步动画的跟随符号补足光束落点。
        -- 真正的光束FX仍独立检测，绝不把Boss脚下当成唯一的激光判定。
        local point=e:GetPosition()
        if e.AnimState.GetSymbolPosition then
            local x,_,z,found=e.AnimState:GetSymbolPosition("optic_blast_fx_follow",0,0,0)
            if x and z and found~=false then point=Vector3(x,0,z) end
        end
        local vx,vz=owner:Velocity(e,state,0,point)
        -- 窄光束起手就按宽光束预留距离，变宽时不能才开始往外挪。
        local h=G.Circle(out,e,5+pad+.35,point,vx,vz)
        h.pursuit=true;h.beam=true
    end
end
function M.Blocked(e)
    return G.Anim(e,"punch_pre") or G.Anim(e,"punch_loop")
        or G.Anim(e,"teleport_pre") or G.Anim(e,"teleport_loop")
        or G.Anim(e,"teleport_pst") and G.Frame(e)<=28
        or G.Anim(e,"optic_blast_pre1") or G.Anim(e,"optic_blast_pre2")
        or G.Anim(e,"optic_blast_pre3") or G.Anim(e,"optic_blast_loop")
        or G.Anim(e,"optic_blast_pst") and G.Frame(e)<=18
        or G.Anim(e,"death_puddle_loop") or G.Anim(e,"death_puddle_loop2")
        or e:HasTag("NOCLICK") or e:HasTag("noattack")
end
function M.Extra(owner,e,out,state,pad)
    local n=e.prefab;local f=G.Frame(e)
    if n=="honey_trail_shrouden_fx" then
        if not G.Net(e._isfading,false) then
            local scale=e.Transform.GetScale and e.Transform:GetScale() or 1.35
            local h=G.Circle(out,e,(scale or 1.35)+pad);h.gel_trail=true
            h.contact_radius=scale or 1.35
        end
        return
    elseif n=="gelblob_attach_fx" then
        local blob=G.Net(e.mainblob)
        if blob and blob.prefab=="shrouden" and not G.Net(e.killed,false)
            and e.entity and e.entity:GetParent()==owner.c.player then owner.gel_attached=true end
        return
    end
    if n=="charliearena_spike" then
        if G.Anim(e,"spike_pst") then return end
        local r,g,b=1,1,1
        if e.AnimState and e.AnimState.GetMultColour then r,g,b=e.AnimState:GetMultColour() end
        if r and g and b and r>.8 and g<.9 and b<.9 then G.Circle(out,e,3+pad)
        else
            for i=1,3 do if G.Anim(e,"spike"..i.."_pre") then G.Circle(out,e,1+pad);break end end
        end
        return
    end
    local summoned=e:HasTag("NOCLICK") and e:HasTag("notarget")
    if n=="shadowthrall_horns" and G.Anim(e,"shrouden_jump") and f<=12 then
        local vx,vz=owner:Velocity(e,state,18)
        G.Circle(out,e,(TUNING.SHADOWTHRALL_HORNS_FACEPLANT_RADIUS or 3)+pad,nil,vx,vz);return
    elseif n=="shadowthrall_hands" and summoned and (G.Anim(e,"portal_appear") or G.Anim(e,"run_loop")) then
        local vx,vz=owner:Velocity(e,state,TUNING.SHADOWTHRALL_HANDS_RUNSPEED or 12)
        G.Circle(out,e,1.8+pad,G.Point(e,.5,0),vx,vz);return
    elseif n=="shadowthrall_mouth" and summoned and (G.Anim(e,"portal_appear")
        or G.Anim(e,"bite_loop") or G.Anim(e,"shrouden_disappear") and f<=6) then
        local vx,vz=owner:Velocity(e,state,8)
        G.Circle(out,e,1+pad,G.Point(e,.75,0),vx,vz);return
    end
    if n~="shrouden_optic_blast_fx" then return end
    if G.Anim(e,"beam_basic_pst") or G.Anim(e,"beam_wide_pst") then return end
    local vx,vz=owner:Velocity(e,state,0)
    -- 跟随的是optic_blast_fx_follow符号，必须读特效真实世界坐标，而非Boss脚下。
    local h=G.Circle(out,e,5+pad+.35,nil,vx,vz);h.pursuit=true;h.beam=true
end
function M.Contact(owner)
    local p=owner.c.player;local point=p:GetPosition()
    if owner.gel_attached then return true end
    for _,h in ipairs(owner.shapes) do
        if h.gel_trail and point:DistSq(h.pos)<(h.contact_radius+.1)^2 then return true end
        if h.gel and p:HasTag("gelblobbed") then return true end
    end
    return false
end
return M
