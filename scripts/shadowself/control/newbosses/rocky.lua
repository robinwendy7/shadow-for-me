-- SGrocky：15帧原地钳击；12帧扫掠冲刺，17帧追加钳击；连冲不能当停顿输出。
local G=require("shadowself/control/newbosses/geometry")
local M={}
local function snip(out,e,pad,dash)
    local s=TUNING.ROCKY_BOSS_SCALE or 1.4;local dist=(dash and 3.6 or 2.8)*s
    if dash then G.Circle(out,e,1.2*s+pad,G.Point(e,.5,0));G.Circle(out,e,1.2*s+pad,G.Point(e,1.9*s,0))
    else G.Circle(out,e,1.2*s+pad,G.Point(e,1.1*s,0)) end
    G.Circle(out,e,.8*s+pad,G.Point(e,(dash and 2.9 or 2.1)*s,0))
    local a,b=G.Point(e,dist,.3*s),G.Point(e,dist,-.3*s)
    G.Triangle(out,e,a,b,G.Point(e,dist+7*s,0),pad)
    G.Triangle(out,e,a,b,G.Point(e,dist-7*s,0),pad)
end
function M.Build(owner,e,out,state,pad)
    local f=G.Frame(e)
    if G.Anim(e,"atk_snip") then
        if f<=15 then snip(out,e,pad,false) end
    elseif G.Anim(e,"atk_dash") then
        if not state.dash or f<(state.frame or 0) then
            state.origin=e:GetPosition();state.direction={G.Basis(e)};state.chain=(state.chain or 0)+1
        end
        state.dash=true;state.frame=f
        if f<=14 then
            local s=TUNING.ROCKY_BOSS_SCALE or 1.4;local p=state.origin;local d=state.direction
            local length=(TUNING.ROCKY_BOSS_DASH_RANGE or 9)*s
            G.Line(out,e,p,Vector3(p.x+d[1]*length,0,p.z+d[2]*length),1.2*s+pad)
        end
        if f<=17 then snip(out,e,pad,true) end
        return
    end
    if state.dash then state.dash=nil;state.chain=0 end
end
function M.Blocked(e) return G.Anim(e,"atk_dash") or G.Anim(e,"atk_snip") and G.Frame(e)<=19 end
return M
