-- 左右夹击方向回归：保留骗招/攻击状态机，仅测试候选方向与防抖。
local oldtime,oldvec=GetTime,Vector3
local now=0;GetTime=function() return now end
Vector3=function(x,y,z) local q={x=x,y=y,z=z};function q:DistSq(v) return (self.x-v.x)^2+(self.z-v.z)^2 end;return q end
local function enemy(x,z)
    local e={replica={combat={GetAttackRangeWithWeapon=function() return 2 end}}}
    function e:GetPosition() return Vector3(x,0,z) end
    function e:GetPhysicsRadius() return 0 end
    function e:IsValid() return true end
    function e:HasTag() return false end
    return e
end
local left,right=enemy(-2,0),enemy(2,0)
local c={player={GetPosition=function() return Vector3(0,0,0) end},enemies={left,right},hazards={},dodging=true,
    actions={SafePoint=function() return true end}}
local N=require("shadowself/control/navigation")
local q=N.Select(c,Vector3(-4,0,0))
assert(math.abs(q.z)>2,"left/right simultaneous attacks escape perpendicular to the pincer")
assert(N.Safe(c,q),"whole escape path is safe against both enemies")
now=.1;local same=N.Select(c,Vector3(4,0,0))
assert(same==q,"opposite next threat does not reverse escape within commitment window")
now=1;c.escape_until=nil;c.enemies[3]=enemy(q.x,q.z)
local other=N.Select(c,Vector3(q.x,0,q.z))
assert(other.z*q.z<0,"third attack zone blocks previous escape side, so pick the other direction")
c.enemies={};c.escape_until=nil;c.hazards={{pos=Vector3(0,0,2),radius=1.3}}
local dry=N.Select(c,Vector3(0,0,4))
assert(N.Safe(c,dry) and not N.Safe(c,Vector3(0,0,4)),"honey must be avoided along the whole path, not just at destination")
-- 原主目标的3014侧移点必须原样通过；协调器不再用圆形危险区重算。
local Co=require("shadowself/control/coordinator")
c.h={ent=left};c.target=left;c.enemies={left};c.hazards={};c.actions.SafePoint=function() return false end
setmetatable(c,{__index=Co})
for _,p in ipairs({Vector3(-1,0,4),Vector3(3,0,-2),Vector3(0,0,6)}) do
 assert(c:SafeMovePoint(p)==p,"all native single-target dodge points retain identity, distance and direction")
end
GetTime=oldtime;Vector3=oldvec
print("PASS: left/right pincer -> third direction; short escape commitment avoids oscillation; third enemy and honey route checks")
