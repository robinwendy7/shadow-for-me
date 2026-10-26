local saved=TheWorld
local savedTiles=WORLD_TILES
WORLD_TILES={OCEAN_ICE=10}
local Return=require('shadowself/control/arena_return')
local center=Vector3(0,0,0)
local p={pos=Vector3(0,0,0),GetPosition=function(self) return self.pos end}
local melted=false
local function ice(x,z)
 -- Bent ice corridor: the shore is not visible from the initial position.
 return not melted and (math.abs(x)<=1 and z>=-1 and z<=7
  or math.abs(z-6)<=1 and x>=-1 and x<=19)
end
local floe={prefab='boat_ice_crabking'}
local boat={prefab='boat'}
local under
TheWorld={Map={
 IsOceanAtPoint=function(_,x) return x<18 end,
 IsPassableAtPoint=function(_,x,_,z) return x>=18 or ice(x,z) end,
 GetTileAtPoint=function(_,x,_,z) return ice(x,z) and WORLD_TILES.OCEAN_ICE or 0 end,
 GetPlatformAtPoint=function(x,z) end,
}}
TheWorld.Map.GetPlatformAtPoint=function(_,x,z)
 if under and math.abs(x)<=1 and math.abs(z)<=1 then return under end
end
assert(not Return.Stable(p.pos),'temporary ice is never acknowledged as safe land')
for i=1,8 do
 local q=Return.Escape(p,center)
 assert(q and Return.Clear(p.pos,q),'bent ice corridor yields a walkable escape leg')
 p.pos=q
 if Return.Stable(p.pos) then break end
end
assert(Return.Stable(p.pos),'escape reaches permanent shore before returning home')
-- 新策略直接以入场点为目标，弯曲冰路也不必先完成单独的上岸阶段。
p.pos=Vector3(0,0,0)
for i=1,10 do
 local q=Return.Point(p,Vector3(20,0,6),center)
 assert(q and Return.Clear(p.pos,q),'direct return plans through a bent ice corridor')
 p.pos=q;if p.pos:DistSq(Vector3(20,0,6))<.01 then break end
end
assert(p.pos:DistSq(Vector3(20,0,6))<.01,'ice-to-home routing reaches the entry target')
local home=Vector3(20,0,-12)
local q=Return.Point(p,home,center)
assert(q and Return.Clear(p.pos,q,true),'after escape use permanent ground rather than crossing ice again')
-- A real crab ice floe supports walking even when terrain underneath is ocean.
melted=true;under=floe;p.pos=Vector3(0,0,0)
assert(Return.Clear(p.pos,Vector3(.5,0,0)) and not Return.Stable(p.pos),'floe is walkable but not permanent safety')
under=boat
assert(not Return.Clear(p.pos,Vector3(.5,0,0)),'ordinary boat is never a walking shortcut')
under=nil
assert(not Return.Escape(p,center),'melted disconnected ice does not authorize walking across open water')
-- The nearest shore wins, even when the entry point is on the opposite side.
TheWorld.Map.IsOceanAtPoint=function(_,x) return math.abs(x)<18 end
TheWorld.Map.IsPassableAtPoint=function() return true end
TheWorld.Map.GetTileAtPoint=function(_,x) return math.abs(x)<18 and WORLD_TILES.OCEAN_ICE or 0 end
p.pos=Vector3(-16,0,0)
q=Return.Escape(p,center)
assert(q and q.x<=-18 and Return.Stable(q),'escape chooses nearby left shore before home on the right')
local pathCalls=0
TheWorld.Pathfinder={IsClear=function(_,ax,ay,az,bx,by,bz,caps)
 pathCalls=pathCalls+1;return caps.allowocean==true
end}
assert(Return.Clear(Vector3(-16,0,0),Vector3(-18,0,0)) and pathCalls==1,
 'sample-verified ice route tells the engine pathfinder that underlying water is traversable')
TheWorld.Map.GetTileAtPoint=function() return 0 end
assert(not Return.Clear(Vector3(-16,0,0),Vector3(-18,0,0)) and pathCalls==1,
 'allowocean never authorizes a bare-water route because surface samples reject it first')
assert(not Return.Clear(Vector3(-20,0,0),Vector3(-22,0,0),true),
 'ordinary land keeps its normal pathfinder obstacle rejection')
TheWorld=saved
WORLD_TILES=savedTiles
print('PASS: wave8 escape ignores crab threats, walks bent ice/floes to nearest permanent shore, and never crosses open water or boats')
