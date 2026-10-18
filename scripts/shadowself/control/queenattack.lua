-- SGbeequeen: locked target DoAttack at frame 14, HIT_RANGE=6. No cone dodge.
return function(c,queen,base)
    local a=queen.AnimState
    if not a:IsCurrentAnimation("atk") or a:GetCurrentAnimationFrame()>=14 then return base end
    local radius=c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5
    c.queen_dodge=c.queen_dodge or {atkanim="atk",point="target",update=true,angle=0}
    c.queen_dodge.dist=(TUNING.BEEQUEEN_HIT_RANGE or 6)+radius+.25
    if c.beequeen and c.player.GetPosition then
        c.queen_dodge.fn=function(_,start,finish,angle,dist)
            local pos=c.player:GetPosition();local q=queen:GetPosition()
            local dx,dz=pos.x-q.x,pos.z-q.z;local d=math.max(.01,math.sqrt(dx*dx+dz*dz))
            local goal=Vector3(q.x+dx/d*dist,0,q.z+dz/d*dist)
            local Nav=require("shadowself/control/navigation")
            if not Nav.Obstructed(c,goal,queen) then return goal end
            local best,score
            for i=0,23 do local a=i*math.pi/12;local v=Vector3(q.x+math.cos(a)*dist,0,q.z+math.sin(a)*dist)
                if Nav.Safe(c,v,queen) then local value=pos:DistSq(v);if not score or value<score then best,score=v,value end end
            end
            return best or Nav.Escape(c,goal,queen) or goal
        end
    end
    return c.queen_dodge
end
