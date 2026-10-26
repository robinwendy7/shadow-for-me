-- 真实场地砖环为中心±20，向内留2码；抵达外沿后才开始计时。
return function(c,state,seconds)
 local center=c.plan.arena_center and c.plan.arena_center()
 if not center then return nil,false end
 local p=c.player:GetPosition();local points={}
 for i=0,7 do points[#points+1]=Vector3(center.x-18+i*4.5,0,center.z-18) end
 for i=0,7 do points[#points+1]=Vector3(center.x+18,0,center.z-18+i*4.5) end
 for i=0,7 do points[#points+1]=Vector3(center.x+18-i*4.5,0,center.z+18) end
 for i=0,7 do points[#points+1]=Vector3(center.x-18,0,center.z+18-i*4.5) end
 if not state.edge_index then
  local best
  for i,q in ipairs(points) do local d=p:DistSq(q)
   if not best or d<best then best=d;state.edge_index=i end
  end
 end
 local q=points[state.edge_index]
 if p:DistSq(q)<=1.5^2 then
  state.edge_since=state.edge_since or GetTime()
  state.edge_index=state.edge_index%#points+1;q=points[state.edge_index]
 end
 return q,state.edge_since and GetTime()-state.edge_since>=seconds or false
end
