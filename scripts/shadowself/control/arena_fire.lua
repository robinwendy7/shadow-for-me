-- 火狗死亡生成houndfire；fire是燃烧物的网络特效，不能被FX过滤漏掉。
local F={}
local safe={campfire=true,firepit=true,coldfire=true,coldfirepit=true,torch=true,willow_lighter=true}
function F.Zone(e,player)
 if not e:IsValid() then return end
 local name=e.prefab
 if require("shadowself/control/arena_snails").Burning(e) then
  return {pos=e:GetPosition(),radius=3+(player.GetPhysicsRadius and player:GetPhysicsRadius(0) or .5)+1,source=e,explosive_snail=true}
 end
 if name~="houndfire" and name~="fire" then return end
 local owner=e.entity and e.entity.GetParent and e.entity:GetParent()
 if owner and (owner==player or safe[owner.prefab] or owner:HasTag("player")
  or owner.replica and owner.replica.inventoryitem and owner.replica.inventoryitem:IsHeld()) then return end
 local propagator=(owner and owner.components and owner.components.propagator) or (e.components and e.components.propagator)
 if propagator and propagator.damages==false then return end
 local radius=(propagator and propagator.damagerange or 3)+(player.GetPhysicsRadius and player:GetPhysicsRadius(0) or .5)+.35
 return {pos=e:GetPosition(),radius=radius,source=e,fire=true}
end
function F.Zones(player,entities)
 local out={}
 for _,e in ipairs(entities) do local z=F.Zone(e,player);if z then out[#out+1]=z end end
 return out
end
-- 原版spiderhole的GroundCreepEntity半径为5，额外留人物碰撞余量。
function F.WebZones(player,entities)
 local zones={}
 for _,e in ipairs(entities) do
  if e:IsValid() and (e.prefab=="spiderhole" or e.prefab=="spiderhole_rock") then
   zones[#zones+1]={pos=e:GetPosition(),radius=5+(player.GetPhysicsRadius and player:GetPhysicsRadius(0) or .5)+.5,source=e,web=true}
  end
 end
 return zones
end
function F.Safe(player,point,zones)
 local p=player:GetPosition();local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(point))/.5))
 for _,z in ipairs(zones or {}) do
  local before=math.max(0,z.radius-math.sqrt(p:DistSq(z.pos)))
  for i=1,steps do
   local q=Vector3(p.x+(point.x-p.x)*i/steps,0,p.z+(point.z-p.z)*i/steps)
   if math.max(0,z.radius-math.sqrt(q:DistSq(z.pos)))>before+.01 then return false end
  end
  if before>0 and point:DistSq(z.pos)<z.radius^2 then return false end
 end
 return true
end
function F.Escape(player,zones)
 local p=player:GetPosition();local inside=false
 for _,z in ipairs(zones) do if p:DistSq(z.pos)<z.radius^2 then inside=true;break end end
 if not inside then return end
 local map=TheWorld.Map;local best,score
 for _,distance in ipairs({3,5,7}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*distance,0,p.z+math.sin(a)*distance)
  if F.Safe(player,q,zones) then
   local clear=true
   for j=1,8 do
    local x,z=p.x+(q.x-p.x)*j/8,p.z+(q.z-p.z)*j/8
    if not map:IsPassableAtPoint(x,0,z) or map:IsOceanAtPoint(x,0,z)
     or map.IsPointNearHole and map:IsPointNearHole(Vector3(x,0,z)) then clear=false;break end
   end
   if clear and TheWorld.Pathfinder and not TheWorld.Pathfinder:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false}) then clear=false end
   if clear and (not score or distance<score) then best,score=q,distance end
  end
 end end
 return best
end
return F
