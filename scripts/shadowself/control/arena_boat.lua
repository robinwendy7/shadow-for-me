-- 配对可站立的岸边与整只船可部署的水面，始终保留原版CanDeploy检查。
local B={}
function B.Range(kit)
 local ii=kit.replica and kit.replica.inventoryitem
 local spacing=ii and ii.DeploySpacingRadius and ii:DeploySpacingRadius() or (kit.prefab=="boat_grass_item" and 3.2 or 4)
 return 1+spacing+1-.15 -- 原版控制器DEPLOY距离1，加部署间距与额外距离1，留同步余量。
end
local function find(player,kit,center)
 local map=TheWorld.Map;local p=player:GetPosition();local ii=kit.replica.inventoryitem
 local radius=kit._boat_radius or TUNING.BOAT and TUNING.BOAT.RADIUS or 4
 local best,point,score
 for d=0,28,4 do for i=0,31 do
  local a=i*math.pi/16;local shore=Vector3(p.x+math.cos(a)*d,0,p.z+math.sin(a)*d)
  if map:IsPassableAtPoint(shore.x,0,shore.z) and not map:IsOceanAtPoint(shore.x,0,shore.z)
   and (not score or p:DistSq(shore)<=score) then
   local dx,dz=center.x-shore.x,center.z-shore.z;local length=math.sqrt(dx*dx+dz*dz)
   if length>.01 then for offset=radius+.25,B.Range(kit),.5 do
    -- 岸角朝中心的对角线可能需要超出部署距离；同时检查沿岸法线方向。
    for j=0,15 do
     local angle=j*math.pi/8
     local water=Vector3(shore.x+math.cos(angle)*offset,0,shore.z+math.sin(angle)*offset)
     if map:IsOceanAtPoint(water.x,0,water.z) and ii:CanDeploy(water,nil,player,0) then
      local value=p:DistSq(shore)+water:DistSq(center)*.001+offset*.01
      if not score or value<score then best,point,score=shore,water,value end
     end
    end
   end end
  end
 end end
 return best,point
end

return setmetatable(B,{__call=function(_,...) return find(...) end})
