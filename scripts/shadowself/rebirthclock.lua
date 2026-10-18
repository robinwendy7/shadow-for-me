-- 读取真实玩家复活动画进度，避免把5.73秒演出串在3.33秒护符复活之后。
local Clock=Class(function(self,owner,name)
    self.owner=owner;self.name=name
    self.duration=math.max(.1,owner.AnimState:GetCurrentAnimationLength())
end)
function Clock:Progress()
    local a=self.owner.AnimState
    if not a:IsCurrentAnimation(self.name) then return 1 end
    return math.max(0,math.min(1,a:GetCurrentAnimationTime()/self.duration))
end
function Clock:Pose(progress)
    if self.name=="wendy_resurrect" then return progress*172/30 end
    -- 护符原版第20帧已升起；将托抱姿态提前并合并到同一条时间线上。
    local points={{0,0},{.14,78},{.20,90},{.60,125},{.86,158},{1,172}}
    for i=2,#points do
        local a,b=points[i-1],points[i]
        if progress<=b[1] then return (a[2]+(b[2]-a[2])*(progress-a[1])/(b[1]-a[1]))/30 end
    end
    return 172/30
end
return Clock
