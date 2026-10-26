-- SGbat：扑咬持续转向，hair_attack_fail前5帧仍会附着，不能提前贴回去。
local G=require("shadowself/control/newbosses/geometry")
local M={}
function M.Build(owner,e,out,state,pad)
    local f=G.Frame(e)
    if G.Anim(e,"hair_attack") or G.Anim(e,"hair_attack_fail") and f<=5 then
        local p=e:GetPosition();local x,z=G.Basis(e)
        local length=G.Anim(e,"hair_attack") and (f<6 and 6 or 3.5) or 2
        G.Line(out,e,p,Vector3(p.x+x*length,0,p.z+z*length),.7+pad)
        -- 覆盖转向及贴头检测，不把扑咬误当作固定直线冲撞。
        G.Circle(out,e,1.1+pad,p)
    elseif G.Anim(e,"atk") and f<=10 then
        G.Circle(out,e,(TUNING.BAT_BOSS_HIT_DIST or 1.4)+pad+.65)
    end
end
function M.Blocked(e)
    return G.Anim(e,"hair_attack") or G.Anim(e,"hair_attack_fail") and G.Frame(e)<=10
        or G.Anim(e,"atk") and G.Frame(e)<=11
        or G.Anim(e,"clone_pre") or G.Anim(e,"clone") or G.Anim(e,"clone_pst")
end
return M
