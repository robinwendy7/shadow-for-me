-- SGsharkboi: 240度扇形扫击绕近背面；钻出/跳跃/鱼雷保持各自AOE间距。
local Nav=require("shadowself/control/navigation")
local R={}
local function anim(e,n) return e.AnimState and e.AnimState:IsCurrentAnimation(n) end
function R.IceState(c,e)
 c.shark_ice=c.shark_ice or {};local state=c.shark_ice[e]
 local f=e.AnimState:GetCurrentAnimationFrame() or 0
 if anim(e,"ice_summon") then
  if not state or not state.summoning or f<(state.frame or 0) then state={summoning=true};c.shark_ice[e]=state end
  state.frame=f
  if not state.locked then
   state.rotation=e.Transform:GetRotation();state.pos=e:GetPosition()
   if f>=35 then state.locked=true;state.untiltime=GetTime()+math.max(0,(58-f)/30)+.3 end
  end
 elseif state then state.summoning=nil end
 return state
end
function R.IceZones(c,e)
 local state=R.IceState(c,e);local zones={}
 if not state or not state.locked or GetTime()>=(state.untiltime or 0) then return zones end
 local theta=state.rotation*math.pi/180;local pos=state.pos
 -- 原版每侧20根，间隔1.65码，漂移可达±1.5；前方整条生长区都避开。
 for distance=4,34,5 do
  zones[#zones+1]={pos=Vector3(pos.x+math.cos(theta)*distance,0,pos.z-math.sin(theta)*distance),radius=6.1,source=e,ice_rail=true}
 end
 return zones
end
function R.Dodge(c,e,base)
 local a=e.AnimState;local f=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
 local swipe=anim(e,"atk1") and f<=16 or anim(e,"atk2") and f<=4 or anim(e,"atk2_delay") or anim(e,"atk3") and f<=12
 local ice=anim(e,"ice_summon") and f<58
 local ice_state=R.IceState(c,e)
 local emerging=anim(e,"icedive_standing_jump_pre") or anim(e,"icedive_dig_pst") and f<4 or anim(e,"icedive_jump_pre") or anim(e,"icedive_jump") or anim(e,"icedive_dig_pre") or anim(e,"spawn") and f<20
 local torpedo=anim(e,"torpedo_pre") or anim(e,"torpedo_jump") or anim(e,"torpedo_loop")
 if not torpedo then c.shark_torpedo=nil end
 if not swipe and not emerging and not torpedo and not ice then return base end
 local name
 for _,n in ipairs({"atk1","atk2","atk2_delay","atk3","ice_summon","torpedo_pre","torpedo_jump","torpedo_loop","icedive_standing_jump_pre","icedive_jump_pre","icedive_jump","icedive_dig_pre","icedive_dig_pst","spawn"}) do if anim(e,n) then name=n;break end end
 local data={atkanim=name,point="target",dist=swipe and 3 or ice and 6 or torpedo and 4 or 3.1,update=true,exclusive=true,noattack=true}
 if ice then
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition();local rot=(ice_state and ice_state.rotation or e.Transform:GetRotation())*math.pi/180
   local back=math.pi-rot;local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
   local side=delta<0 and -1 or 1;local radius=math.max(3.4,math.min(4.2,math.sqrt(p:DistSq(ep))))
   local hazards={};for _,h in ipairs(c.hazards or {}) do hazards[#hazards+1]=h end
   for _,h in ipairs(R.IceZones(c,e)) do hazards[#hazards+1]=h end
   local view=setmetatable({hazards=hazards},{__index=c})
   for _,sign in ipairs({side,-side}) do
    local a=theta+sign*math.min(.65,math.abs(delta));local point=Vector3(ep.x+math.cos(a)*radius,0,ep.z+math.sin(a)*radius)
    if Nav.Safe(view,point,e) then return point end
   end
   return Nav.Select(view,Vector3(ep.x+math.cos(back)*radius,0,ep.z+math.sin(back)*radius),e)
  end
 elseif swipe then
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition();local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local back=math.pi-e.Transform:GetRotation()*math.pi/180;local delta=(back-theta+math.pi)%(2*math.pi)-math.pi
   -- 扫击中心前移2码，240度弧后界在本体前方0.25码。
   -- 绕到该界后即安全，不必绕到正背；半径按真实碰撞体贴身。
   local rot=e.Transform:GetRotation()*math.pi/180
   local forward=(p.x-ep.x)*math.cos(rot)-(p.z-ep.z)*math.sin(rot)
   if forward<=.1 then return p end
   local body=(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or 1)+(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)
   local radius=math.max(body+.15,math.min(body+.3,math.sqrt(p:DistSq(ep))))
   local preferred=delta<0 and -1 or 1
   for _,side in ipairs({preferred,-preferred}) do
    local step=math.min(.55,math.abs(delta));local v=Vector3(ep.x+math.cos(theta+side*step)*radius,0,ep.z+math.sin(theta+side*step)*radius)
    if Nav.Safe(c,v,e) then return v end
   end
   return Nav.Select(c,Vector3(ep.x+math.cos(back)*radius,0,ep.z+math.sin(back)*radius),e)
  end
 else
  -- 地下跃出是全圆近身伤害，不能把它当作扫击贴身绕背。
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition();local radius=data.dist+c.player:GetPhysicsRadius(0)+.3
   local theta=math.atan2(p.z-ep.z,p.x-ep.x)
   local rot=e.Transform:GetRotation()*math.pi/180
   if torpedo then
    local state=c.shark_torpedo
    if not state or state.target~=e then
     local nx,nz=math.sin(rot),math.cos(rot);local side=nx*(p.x-ep.x)+nz*(p.z-ep.z);local sign=side<0 and -1 or 1
     local amount=math.max(0,3+c.player:GetPhysicsRadius(0)+.6-math.abs(side))
     state={target=e,point=Nav.Select(c,Vector3(p.x+nx*amount*sign,0,p.z+nz*amount*sign),e)};c.shark_torpedo=state
    end
    return state.point
   end
   return Nav.Select(c,Vector3(ep.x+math.cos(theta)*radius,0,ep.z+math.sin(theta)*radius),e)
  end
 end
 return data
end
return R
