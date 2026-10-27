-- 龙蝇场景四角岩浆池约在中心(±14,±14)；战斗以中心8码为主，躲避预留至10码。
local M={}
function M.Anchor(c)
 local plan=c.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=10 or not plan.arena_center then return end
 for _,e in ipairs(c.enemies or {}) do
  local h=e.replica and e.replica.health
  if e.prefab=="dragonfly" and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead()) then return plan.arena_center() end
 end
end
function M.RoadAt(c,q)
 local map=TheWorld and TheWorld.Map;local road=WORLD_TILES and WORLD_TILES.ROAD
 if not map or not map.GetTileAtPoint or not road then return true end
 local radius=c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5
 if map:GetTileAtPoint(q.x,0,q.z)~=road then return false end
 for i=0,7 do
  local a=i*math.pi/4
  if map:GetTileAtPoint(q.x+math.cos(a)*radius,0,q.z+math.sin(a)*radius)~=road then return false end
 end
 return true
end
function M.RoadPath(c,q)
 if not M.RoadAt(c,q) then return false end
 local p=c.player:GetPosition();local steps=math.max(1,math.ceil(math.sqrt(p:DistSq(q))/.4));local entered=M.RoadAt(c,p)
 for i=1,steps do
  local v=Vector3(p.x+(q.x-p.x)*i/steps,0,p.z+(q.z-p.z)*i/steps)
  local onroad=M.RoadAt(c,v)
  if entered and not onroad then return false end
  entered=entered or onroad
 end
 return true
end
-- Boss站在中央地毯上时，攻击接近点放在邻近道路，不把地毯中心当作移动目标。
function M.Goal(c,q)
 local center=M.Anchor(c);if not center or M.RoadAt(c,q) then return q end
 local p=c.player:GetPosition();local best,score
 for _,radius in ipairs({3,4,6}) do for i=0,15 do
  local a=i*math.pi/8;local v=Vector3(q.x+math.cos(a)*radius,0,q.z+math.sin(a)*radius)
  if v:DistSq(center)<=10^2 and M.RoadPath(c,v) then
   local value=v:DistSq(q)+p:DistSq(v)*.1
   if not score or value<score then best,score=v,value end
  end
 end end
 return best or p
end
function M.Point(c,q)
 local center=M.Anchor(c);if not center then return true end
 local before=c.player:GetPosition():DistSq(center);local after=q:DistSq(center)
 return (before>10^2 and after<before-.01 or before<=10^2 and after<=10^2) and M.RoadPath(c,q)
end
function M.AttackAllowed(c,target)
 local center=M.Anchor(c);if not center or not target then return true end
 return M.RoadAt(c,c.player:GetPosition()) and c.player:GetPosition():DistSq(center)<=10^2 and target:GetPosition():DistSq(center)<=10^2
end
function M.Tick(owner,target)
 local c=owner.c;local center=M.Anchor(c);if not center then return end
 local p=c.player:GetPosition();local outer=target:GetPosition():DistSq(center)>10^2
 if not M.RoadAt(c,p) or p:DistSq(center)>8^2 or outer and p:DistSq(center)>5^2 then
  local q=require("shadowself/control/navigation").Select(c,center)
  return owner:Move(q,"龙蝇 · 沿中央加速地皮走位，避开毛皮地毯及岩浆池",target),target
 end
 if outer then c.bridge:PauseAttack();owner:Release();return "support",target end
end
return M
