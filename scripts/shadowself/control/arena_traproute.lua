-- 第二关陷阱退让：攻击被禁时仍可从受压位置撤出，逐段检查全部陷阱而非空等。
local T={}
local function live(e) return e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") end
function T.Point(c,dogs,range)
 local p=c.player:GetPosition();local map=TheWorld.Map;local Nav=require("shadowself/control/navigation")
 local best,score
 local function clear(q)
  local n=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.25))
  for i=0,n do
   local v=Vector3(p.x+(q.x-p.x)*i/n,0,p.z+(q.z-p.z)*i/n)
   if not map:IsPassableAtPoint(v.x,0,v.z) or map:IsOceanAtPoint(v.x,0,v.z)
    or map.IsPointNearHole and map:IsPointNearHole(v) then return false end
   if c.actions and c.actions.SafePoint and not c.actions:SafePoint(v) then return false end
   for _,dog in ipairs(dogs) do if live(dog) then
    local initial=math.max(0,range-math.sqrt(p:DistSq(dog:GetPosition())))
    if math.max(0,range-math.sqrt(v:DistSq(dog:GetPosition())))>initial+.001 then return false end
   end end
   for _,h in ipairs(c.hazards or {}) do
    local initial=math.max(0,(h.radius or 0)-math.sqrt(p:DistSq(h.pos)))
    if math.max(0,(h.radius or 0)-math.sqrt(v:DistSq(h.pos)))>initial+.001 then return false end
   end
  end
  for _,dog in ipairs(dogs) do if live(dog) and q:DistSq(dog:GetPosition())<(range+.5)^2 then return false end end
  return not TheWorld.Pathfinder or TheWorld.Pathfinder:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false})
 end
 for _,distance in ipairs({.75,1.5,3,6,9,12,16,18}) do for i=0,31 do
  local a=i*math.pi/16;local q=Vector3(p.x+math.cos(a)*distance,0,p.z+math.sin(a)*distance)
  if clear(q) then
   local value=Nav.Risk(c,q)*20+distance
   if not score or value<score then best,score=q,value end
  end
 end end
 return best
end
return T
