-- 角斗场专用阶段动作；只向原版控制器提交操作，成功以实体/平台/动画同步为准。
local A=require("shadowself/control/actions")
local Inventory=require("shadowself/control/arena_inventory")
local S=Class(function(self,arena) self.arena=arena;self.player=arena.player end)
local function alive(e)
 if not e or not e:IsValid() or e:HasTag("INLIMBO") or e:HasTag("isdead") or e:HasTag("dead") then return false end
 local h=e.replica and e.replica.health
 return not (h and h:IsDead())
end
local function animation(e,name) return e and e.AnimState and e.AnimState:IsCurrentAnimation(name) end
local function unit(a,b,d)
 local x,z=b.x-a.x,b.z-a.z;local n=math.sqrt(x*x+z*z)
 if n<.01 then x,z,n=1,0,1 end
 return Vector3(a.x+x/n*d,0,a.z+z/n*d)
end
function S:Reset() self.corner_point=nil;self.corner_done=nil;self.start_point=nil;self.return_point=nil;self.return_stage=nil;self.next_return=nil;self.crab=nil;self.center=nil;self.boat=nil;self.deploy=nil;self.ice=nil;self.second_phase=nil;self.retreat=nil;self.worm_target=nil;self.add_target=nil;self.lure=nil;self.next_move=nil;self.last_goal=nil;self.next_equip=nil;self.next_row=nil;self.row_pending=nil;self.row_stroke=nil;self.row_count=nil;self.row_wait_stopped=nil;self.wait_scene=nil;self.wait_water=nil;self.wait_oar=nil end
-- 识别角斗场有限水域，不把普通开放海洋当成场地中心。
function S:WaterCenter()
 local map=TheWorld.Map;local p=self.player:GetPosition()
 if not map.GetTileCenterPoint then return end
 local cx,_,cz=map:GetTileCenterPoint(p.x,0,p.z);if not cx then return end
 local seed,dist
 for x=cx-40,cx+40,4 do for z=cz-40,cz+40,4 do
  if map:IsOceanAtPoint(x,0,z) then local d=(x-p.x)^2+(z-p.z)^2
   if not dist or d<dist then seed,dist={x=x,z=z},d end
  end
 end end
 if not seed then return end
 local queue={seed};local seen={};local head=1;local count=0;local minx,maxx,minz,maxz
 while head<=#queue do
  local q=queue[head];head=head+1;local key=q.x..":"..q.z
  if not seen[key] then
   seen[key]=true
   if map:IsOceanAtPoint(q.x,0,q.z) then
    count=count+1;if count>144 or math.abs(q.x-cx)>44 or math.abs(q.z-cz)>44 then return end
    minx=math.min(minx or q.x,q.x);maxx=math.max(maxx or q.x,q.x);minz=math.min(minz or q.z,q.z);maxz=math.max(maxz or q.z,q.z)
    for _,d in ipairs({{4,0},{-4,0},{0,4},{0,-4}}) do queue[#queue+1]={x=q.x+d[1],z=q.z+d[2]} end
   end
  end
 end
 if count>=16 and maxx-minx>=12 and maxz-minz>=12 and maxx-minx<=40 and maxz-minz<=40 then
  return Vector3((minx+maxx)/2,0,(minz+maxz)/2)
 end
end
function S:FindCenter()
 if self.center then return self.center end
 if GetTime()<(self.next_center or 0) then return nil end
 self.next_center=GetTime()+.5
 local p=self.player:GetPosition();local map=TheWorld.Map;local tile=WORLD_TILES and WORLD_TILES.COTL_BRICK
 self.center=self:WaterCenter();if self.center then return self.center end
 if not tile or not map.GetTileAtPoint or not map.GetTileCenterPoint then return nil end
 local minx,maxx,minz,maxz;local hits=0
 local cx,_,cz=map:GetTileCenterPoint(p.x,0,p.z)
 if not cx then return nil end
 for x=cx-44,cx+44,4 do for z=cz-44,cz+44,4 do
  if map:GetTileAtPoint(x,0,z)==tile then
   minx=math.min(minx or x,x);maxx=math.max(maxx or x,x);minz=math.min(minz or z,z);maxz=math.max(maxz or z,z);hits=hits+1
  end
 end end
 -- 服务器场地外围为中心±20的固定砖环，不能把入场位置误当场地中心。
 if hits>=12 and maxx-minx>=36 and maxx-minx<=44 and maxz-minz>=36 and maxz-minz<=44 then
  self.center=Vector3((minx+maxx)/2,0,(minz+maxz)/2)
 end
 return self.center
end
function S:Move(point,label)
 self.arena:StopCombat();self.arena:Say(label)
 require("shadowself/control/arena_late_travel").Tick(self.player,self.arena.wave)
 if not self.last_goal or self.last_goal:DistSq(point)>1 or GetTime()>=(self.next_move or 0) then
  A.Move(self.player,point);self.last_goal=point;self.next_move=GetTime()+.2
 end
 return "hold"
end
function S:Equip(item)
 local inv=self.player.replica.inventory
 if inv:GetEquippedItem(EQUIPSLOTS.HANDS)==item then return true end
 self.arena:StopCombat()
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_equip or 0) then
  A.Self(self.player,item,ACTIONS.EQUIP);self.next_equip=GetTime()+.6
 end
 return false
end
function S:ShorePoint(center)
 local map=TheWorld.Map;local p=self.player:GetPosition();local best,score
 -- 只在场地外圈找陆地，离开内侧会碎的冰面。
 for i=0,31 do local a=i*math.pi/16
  local q=Vector3(center.x+math.cos(a)*20,0,center.z+math.sin(a)*20)
  if map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and (not WORLD_TILES.OCEAN_ICE or map:GetTileAtPoint(q.x,0,q.z)~=WORLD_TILES.OCEAN_ICE) then
   local d=p:DistSq(q);if not score or d<score then best,score=q,d end
  end
 end
 return best
end
local function rowanimation(player)
 for _,name in ipairs({"row_pre","row_medium","row_medium_off"}) do if animation(player,name) then return name end end
end
function S:ConfirmRow(boat)
 local player=self.player;local name=rowanimation(player)
 local frame=player.AnimState and player.AnimState:GetCurrentAnimationFrame() or 0
 local rowing=player:HasTag("is_rowing");local now=GetTime()
 if self.arena.wave~=8 or self.second_phase or self.retreat or player:GetCurrentPlatform()~=boat then
  self.row_pending=nil;self.row_stroke=nil;return
 end
 local pending=self.row_pending
 if pending then
  if pending.boat~=boat then self.row_pending=nil
  elseif rowing and (not pending.rowing or name~=pending.animation or frame<pending.frame) then
   self.row_stroke=pending;self.row_pending=nil
  elseif now>=pending.deadline then self.row_pending=nil end
 end
 -- 原版 row_pre 第8帧执行划桨；进入 row_medium/off 也证明已经越过实际动作帧。
 if self.row_stroke and rowing and (name=="row_pre" and frame>=8 or name=="row_medium" or name=="row_medium_off") then
  self.row_count=(self.row_count or 0)+1;self.row_stroke=nil
 end
end
function S:WaitCrab()
 self.arena:StopCombat()
 if not self.row_wait_stopped then A.Stop(self.player);self.row_wait_stopped=true end
 if not self:CrabWeapon() then return "hold" end
 if self.arena.Rest then self.arena:Rest(nil,true,true) end
 local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
 local weapon=hand and (hand.prefab=="ruins_bat" and "铥棒" or hand.prefab=="nightsword" and "影刀") or "武器"
 self.arena:Say("帝王蟹 · 已完成6次划桨，"..(weapon or "武器").."待战并补充状态")
 return "hold"
end
function S:RowReady(boat,oar)
 local p=self.player;local pc=p.components.playercontroller
 if self.arena.wave~=8 or self.second_phase or self.retreat or (self.row_count or 0)>=6 or pc:IsBusy()
  or p:GetCurrentPlatform()~=boat or not alive(boat)
  or p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)~=oar
  or not require("shadowself/control/arena_tools").Usable(oar)
  or p:HasTag("is_row_failing") or p:HasTag("boathopping") then return false end
 -- componentactions.Row：row_pre期间和row_medium前4帧重划会变成ROW_FAIL。
 if p:HasTag("is_rowing") and p.AnimState then
  local fail_frame=animation(p,"row_pre") and 30 or 4
  if p.AnimState:GetCurrentAnimationFrame()<fail_frame then return false end
 end
 return true
end
function S:Row(boat,goal,retreat)
 self:ConfirmRow(boat)
 if (self.row_count or 0)>=6 then return self:WaitCrab() end
 local oar
 for _,item in ipairs(A.Items(self.player)) do
  if (item.prefab=="oar_driftwood" or item:HasTag("oar")) and require("shadowself/control/arena_tools").Usable(item) then
   if item.prefab=="oar_driftwood" then oar=item;break end
   oar=oar or item
  end
 end
 if not oar then
  self.arena:StopCombat()
  local oars={}
  for _,item in ipairs(self.arena.items or {}) do
   if item.prefab=="oar_driftwood" or item:HasTag("oar") then oars[#oars+1]=item end
  end
  if self.arena:Loot(oars) then self.wait_oar=nil;return "hold" end
  self.wait_oar=self.wait_oar or GetTime()
  if GetTime()-self.wait_oar<8 then self.arena:Say("帝王蟹 · 等待并拾取船桨");return "hold" end
  self.arena:Say("帝王蟹 · 等待船桨同步，不结束循环");return "hold"
 end
 self.wait_oar=nil
 if not self:Equip(oar) then return "hold" end
 self.arena:StopCombat()
 local player=self.player;local p=player:GetPosition();local pc=player.components.playercontroller
 local now=GetTime();local name=rowanimation(player)
 local frame=player.AnimState and player.AnimState:GetCurrentAnimationFrame() or 0
 local rowing=player:HasTag("is_rowing")
 if self.row_pending then return "hold" end
 if not self:RowReady(boat,oar) then return "hold" end
 -- 鼠标ROW由原版直接朝船外划，不要求先走到船沿；手柄方向取决于站位，仍走前沿。
 if pc.isclientcontrollerattached then
  local edge=unit(boat:GetPosition(),goal,math.max(1,(boat.GetPhysicsRadius and boat:GetPhysicsRadius(0) or 4)-.6))
  if p:DistSq(edge)>1.2^2 then return self:Move(edge,"帝王蟹 · 走到船沿准备划桨") end
 end
 local aim=unit(p,goal,12)
 local function ready()
  return self:RowReady(boat,oar)
 end
 if now>=(self.next_row or 0) then
  local action=pc.isclientcontrollerattached and ACTIONS.ROW_CONTROLLER or ACTIONS.ROW
  if A.Ground(player,aim,action,ready) then
   local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
   self.row_pending={boat=boat,rowing=rowing,animation=name,frame=frame,deadline=now+math.max(.3,(ping or 0)/1000+.2)}
  end
  -- 动作列表拒绝时短间隔复查；成功后等待新划桨状态确认，不按固定0.9秒空等。
  self.next_row=now+.1
 end
 self.arena:Say(retreat and "帝王蟹 · 划回外圈安全陆地" or "帝王蟹 · 划向场地中央")
 return "hold"
end
function S:BoatKit()
 local kit
 for _,item in ipairs(A.Items(self.player)) do
  if item.prefab=="boat_item" then return item elseif item.prefab=="boat_grass_item" then kit=item end
 end
 if kit then return kit end
 -- 船套可以先于水面和中心坐标同步；先拿船套，不先做普通Prune。
 self.arena:StopCombat()
 local kits={}
 for _,item in ipairs(self.arena.items or {}) do
  if item.prefab=="boat_item" or item.prefab=="boat_grass_item" then kits[#kits+1]=item end
 end
 self.arena:Loot(kits)
 self.arena:Say(#kits>0 and "帝王蟹 · 立即拾取船套，准备放船" or "帝王蟹 · 等待船套同步并拾取")
end
function S:CrabWeapon()
 local bat,sword
 for _,item in ipairs(A.Items(self.player)) do
  if require("shadowself/control/arena_tools").Usable(item) then
   if item.prefab=="ruins_bat" then bat=item;break end
   if item.prefab=="nightsword" then sword=item end
  end
 end
 local weapon=bat or sword
 if weapon then
  if self.arena.bridge.Running and self.arena.bridge:Running() then return true end
  return self:Equip(weapon)
 end
 for _,item in ipairs(self.arena.items or {}) do
  if item.prefab=="ruins_bat" and require("shadowself/control/arena_tools").Usable(item) then
   self.arena:StopCombat();self.arena:Loot({item});return false
  end
 end
 return true -- 两种指定武器均没有时，保留原来的普通战斗武器选择。
end
function S:BoatPoint(kit,center)
 local p=self.player:GetPosition();local ii=kit.replica.inventoryitem;local point
 for d=4,require("shadowself/control/arena_boat").Range(kit),.5 do
  for i=0,15 do local a=i*math.pi/8;local q=Vector3(p.x+math.cos(a)*d,0,p.z+math.sin(a)*d)
   if TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) and ii:CanDeploy(q,nil,self.player,0) then
    if not point or q:DistSq(center or p)<point:DistSq(center or p) then point=q end
   end
  end
  if point then break end
 end
 return point
end
-- 从传送角落沿两条边任选可走的一边，先到下一块地皮中心再部署。
function S:CrabCorner(center)
 if self.corner_done then return false end
 local map=TheWorld.Map;local origin=self.start_point
 if not map.GetTileCenterPoint or not origin or not center then return false end
 local dx,dz=center.x-origin.x,center.z-origin.z
 if math.abs(dx)<12 or math.abs(dz)<12 then self.corner_done=true;return false end
 if not self.corner_point then
  local x,_,z=map:GetTileCenterPoint(origin.x,0,origin.z)
  if not x or not z then return true end
  local candidates={Vector3(x+(dx>0 and 4 or -4),0,z),Vector3(x,0,z+(dz>0 and 4 or -4))}
  for _,q in ipairs(candidates) do
   local safe=map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   if safe then
    for i=1,8 do
     local t=i/8;local px,pz=origin.x+(q.x-origin.x)*t,origin.z+(q.z-origin.z)*t
     if not map:IsPassableAtPoint(px,0,pz) or map:IsOceanAtPoint(px,0,pz) then safe=false;break end
    end
   end
   if safe then self.corner_point=q;break end
  end
 end
 if not self.corner_point then
  self.arena:StopCombat();self.arena:Say("帝王蟹 · 等待角落两侧陆地地皮同步");return true
 end
 if self.player:GetPosition():DistSq(self.corner_point)>.35^2 then
  self:Move(self.corner_point,"帝王蟹 · 沿边移到相邻地皮中心后放船");return true
 end
 self.corner_done=true;self.last_goal=nil;self.next_move=nil
 return false
end
local function kitcount(kit)
 local stack=kit.replica and kit.replica.stackable
 return stack and stack:StackSize() or 1
end
function S:DeployBoat(kit,point,pending)
 self.arena:StopCombat()
 if not self.player.components.playercontroller:IsBusy() and A.Deploy(self.player,kit,point) then
  local now=GetTime();local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
  pending=pending or {deadline=now+6,count=kitcount(kit),attempts=0}
  pending.kit=kit;pending.point=point;pending.attempts=pending.attempts+1
  pending.retry_at=now+math.max(.75,(ping or 0)/1000+.4)
  self.deploy=pending;self.arena:Say("帝王蟹 · 放船并等待服务器确认")
  print(string.format("[ShadowSelf][boat_deploy] phase=request attempt=%d kit=%s guid=%s distance=%.2f retry_after=%.2f",
   pending.attempts,kit.prefab,tostring(kit.GUID),math.sqrt(self.player:GetPosition():DistSq(point)),pending.retry_at-now))
 end
 return "hold"
end
function S:WaitBoat()
 local pending=self.deploy;local p=self.player;local pc=p.components.playercontroller;local owned=false
 self.arena:StopCombat()
 for _,item in ipairs(A.Items(p)) do if item==pending.kit then owned=true;break end end
 -- 船套已消耗/堆叠减少说明部署可能已执行；只等真实船实体，不再花第二份船套。
 if not owned or not pending.kit:IsValid() or kitcount(pending.kit)<pending.count then
  self.arena:Say("帝王蟹 · 船套已消耗，等待船实体同步")
  return "hold"
 end
 local buffered=p.GetBufferedAction and p:GetBufferedAction()
 local deploying=buffered and (buffered.action==ACTIONS.DEPLOY or buffered.action==ACTIONS.DEPLOY_FLOATING)
 if pc:IsBusy() or p:HasTag("moving") or p:HasTag("boathopping") or deploying then return "hold" end
 local now=GetTime()
 if now>=pending.deadline then
  self.deploy=nil;self.arena:Say("帝王蟹 · 船实体确认延迟，重新核对船套与附近船只");return "hold"
 end
 if now>=pending.retry_at and pending.attempts<3 then
  local ii=pending.kit.replica and pending.kit.replica.inventoryitem
  if not ii or not ii:CanDeploy(pending.point,nil,p,0) then
   self.deploy=nil;self.arena:Say("帝王蟹 · 原放船点已失效，重新寻找合法水面");return "hold"
  end
  return self:DeployBoat(pending.kit,pending.point,pending)
 end
 return "hold"
end
function S:WaitReturn(label)
 self.arena:StopCombat()
 -- 停止上一次点击寻路，否则“等待退路”期间仍会继续走进攻击或水域。
 if self.last_goal then A.Stop(self.player);self.last_goal=nil;self.next_move=nil end
 self.arena:Say(label)
 return "hold"
end
function S:Crab(entities)
 local p=self.player:GetPosition();local king;local boats={}
 if not self.start_point then
  self.start_point=Vector3(p.x,0,p.z)
  print(string.format("[ShadowSelf][boat] entry x=%.2f z=%.2f",p.x,p.z))
 end
 for _,e in ipairs(entities) do
  if e.prefab=="crabking" then king=e end
  if alive(e) and (e.prefab=="boat" or e.prefab=="boat_grass") then boats[#boats+1]=e end
 end
 if king then self.crab=king;self.center=king:GetPosition() end
 king=king or self.crab
 if alive(king) and king:HasTag("icewall") then self.second_phase=true end
 -- 只有本体实际死亡才返程；二阶段计时、融冰和旧撤离标记不打断输出。
 self.retreat=self.crab and not alive(self.crab) or nil
 local current_platform=self.player.GetCurrentPlatform and self.player:GetCurrentPlatform()
 local kit
 if not self.second_phase and not current_platform and #boats==0 and not self.deploy and not self.retreat
  and (not king or alive(king) and not king:HasTag("icewall")) then
  kit=self:BoatKit()
  if not kit then return "hold" end
 end
 local center=self:FindCenter()
 if not center then
  -- 中心用于后续划行；已有原版许可落点时，不能用“等待中心”挡住放船。
  local point=kit and self:BoatPoint(kit)
  if point then return self:DeployBoat(kit,point) end
  if not current_platform and #boats>0 then
   local nearest=boats[1]
   for _,boat in ipairs(boats) do if p:DistSq(boat:GetPosition())<p:DistSq(nearest:GetPosition()) then nearest=boat end end
   self.boat=nearest;self.deploy=nil
   return self:Move(nearest:GetPosition(),"帝王蟹 · 上船，继续识别划行中心")
  end
  if self.deploy then return self:WaitBoat() end
  self.arena:StopCombat();self.wait_scene=self.wait_scene or GetTime()
  if GetTime()-self.wait_scene<8 then self.arena:Say("帝王蟹 · 等待场地地形同步");return "hold" end
  self.arena:Say("帝王蟹 · 等待有限水域中心同步，不等待Boss生成");return "hold"
 end
 if not current_platform and #boats==0 and not self.deploy and not self.second_phase and not self.retreat
  and self:CrabCorner(center) then return "hold" end
 local inice=alive(king) and king:HasTag("icewall")
 if self.retreat then
  if require("shadowself/control/arena_doc_early").ReturnCane(self.arena) then return "hold" end
  local route=require("shadowself/control/arena_return")
  local home=self.start_point
  -- 确认击杀就直接返入场原点；现存冰面与陆地均可走，不再先等永久岸边。
  local stage="home"
  if self.return_stage~=stage then
   self.return_stage=stage;self.return_point=nil;self.next_return=nil
   print(string.format("[ShadowSelf][boat] return=%s from=%.2f,%.2f home=%.2f,%.2f",stage,p.x,p.z,home.x,home.z))
  end
  if not self.return_point or p:DistSq(self.return_point)<.7^2 or not route.Clear(p,self.return_point) then
   self.return_point=nil
   if GetTime()>=(self.next_return or 0) then
    self.next_return=GetTime()+.2
    self.return_point=route.Point(self.player,home,center)
   end
  end
  if stage=="home" and p:DistSq(home)<=2^2 then
   return self:WaitReturn("帝王蟹 · 已返回入场点，等待服务器切换下一关")
  end
  if self.return_point then return self:Move(self.return_point,"帝王蟹 · 忽略小蟹，沿冰面或陆地直接返回入场原点") end
  if GetTime()>=(self.return_wait_log or 0) then
   self.return_wait_log=GetTime()+3
   local map=TheWorld.Map
   print(string.format("[ShadowSelf][boat] return_wait stage=%s tile=%s ocean=%s passable=%s platform=%s",stage,
    tostring(map.GetTileAtPoint and map:GetTileAtPoint(p.x,0,p.z)),tostring(map:IsOceanAtPoint(p.x,0,p.z)),
    tostring(map:IsPassableAtPoint(p.x,0,p.z)),current_platform and current_platform.prefab or "none"))
  end
  return self:WaitReturn("帝王蟹 · 冰陆路径已断，重新寻路返回入场点")
 end
 local platform=self.player.GetCurrentPlatform and self.player:GetCurrentPlatform()
 local onboat=platform and (platform.prefab=="boat" or platform.prefab=="boat_grass")
 if inice then
  -- 原有战斗模块负责落地确认、排箫催眠小蟹和破冰；这里只负责从船登上冰陆。
  if onboat then
   local map=TheWorld.Map;local goal,score
   for _,r in ipairs({6,8,10,12}) do for i=0,15 do local a=i*math.pi/8
    local q=Vector3(center.x+math.cos(a)*r,0,center.z+math.sin(a)*r)
    local under=map.GetPlatformAtPoint and map:GetPlatformAtPoint(q.x,q.z)
    if map:GetTileAtPoint(q.x,0,q.z)==WORLD_TILES.OCEAN_ICE and under~=platform then
     local d=p:DistSq(q);if not score or d<score then goal,score=q,d end
    end
   end end
   if goal then return self:Move(goal,"帝王蟹 · 登上冰陆催眠小蟹") end
   self.arena:Say("帝王蟹 · 等待可登上的冰陆同步");return "hold"
  end
  if not self:CrabWeapon() then return "hold" end
  return "fight"
 end
 if self.second_phase and alive(king) then
  if not self:CrabWeapon() then return "hold" end
  return "fight"
 end
 if not onboat then
  local nearest,dist
  for _,boat in ipairs(boats) do local d=p:DistSq(boat:GetPosition());if not dist or d<dist then nearest,dist=boat,d end end
  if nearest then
   self.boat=nearest;self.deploy=nil
   return self:Move(nearest:GetPosition(),"帝王蟹 · 上船")
  end
  if self.deploy then return self:WaitBoat() end
  kit=kit or self:BoatKit()
  if not kit then return "hold" end
  local point=self:BoatPoint(kit,center)
  if not point then
   self.wait_water=self.wait_water or GetTime()
   -- 第八关先到刷新点；合法岸水配对已同步时立即放船，不固定空等8秒。
   local shore,water=require("shadowself/control/arena_boat")(self.player,kit,center)
   if shore then
    if p:DistSq(shore)>.15^2 then return self:Move(shore,"帝王蟹 · 靠近水边放船") end
    -- 岸角的合法点可能落在旧的16方向离散采样之间，使用成对确认的落点。
    return self:DeployBoat(kit,water)
   end
   self.arena:StopCombat();self.arena:Say("帝王蟹 · 等待可部署的水边位置同步");return "hold"
  end
  self.wait_water=nil
  return self:DeployBoat(kit,point)
 end
 self.boat=platform
 local distance=math.sqrt(p:DistSq(center))
 local reach=alive(king) and (king.GetPhysicsRadius and king:GetPhysicsRadius(0) or 2)+2.5 or 7
 self:ConfirmRow(platform)
 if (self.row_count or 0)<6 then return self:Row(platform,center) end
 if distance>reach or not alive(king) then return self:WaitCrab() end
 if not self:CrabWeapon() then return "hold" end
 return "fight"
end
function S:Worm(entities)
 self.add_target=nil
 local head;local dirt;local bait;local protections={};local p=self.player:GetPosition();local best
 local _,bag=self.arena:Inventory()
 -- 钻出前的地裂是客户端可见预警，优先于捡装备和诱饵停留。
 for _,e in ipairs(entities) do
  if alive(e) and e.prefab=="worm_boss_dirt_ground_fx" and p:DistSq(e:GetPosition())<4^2 then
   self.worm_target=nil
   return self:Move(unit(e:GetPosition(),p,4.5),"巨大蠕虫 · 提前离开地裂吞食范围")
  end
 end
 for _,e in ipairs(entities) do
  if alive(e) and e.prefab=="worm_boss_head" then head=e end
 end
 for _,e in ipairs(entities) do if alive(e) then
  if e.prefab=="worm_boss_dirt" and e.replica and e.replica.combat then
   local d=(head and head:GetPosition() or p):DistSq(e:GetPosition())
   if not best or d<best then dirt,best=e,d end
  end
  local ii=e.replica and e.replica.inventoryitem
  if ii and not ii:IsHeld() and not e:HasTag("NOCLICK") then
   local armor=Inventory.Armor(e)
   if armor and Inventory.Want(e,bag,self.player,self.arena.wave) then protections[#protections+1]=e
   elseif not armor and not e:HasTag("irreplaceable") and not Inventory.Special(e.prefab,self.arena.wave)
    and not (Inventory.Weapon(e,self.player) and Inventory.Want(e,bag,self.player,self.arena.wave)) then
    if not bait or p:DistSq(e:GetPosition())<p:DistSq(bait:GetPosition()) then bait=e end
   end
  end
 end end
 if self.lure and self.lure.bait:IsValid() and not self.lure.bait.replica.inventoryitem:IsHeld() then
  for _,e in ipairs(entities) do if e==self.lure.bait then bait=e;break end end
 end
 -- 收回高防具优先，但不能在即将钻出的嘴边停下来捡。
 local emerging=head and (animation(head,"emerge_eat") or animation(head,"emerge_full") or animation(head,"emerge_taunt"))
 if #protections>0 and not emerging then
  self.arena:StopCombat()
  table.sort(protections,function(a,b) return Inventory.Armor(a)>Inventory.Armor(b) end)
  if self.arena:Loot(protections) then self.arena:Say("巨大蠕虫 · 先收回高防具，避免被吞");return "hold" end
 end
 local chewing=animation(head,"chew_small") or animation(head,"chew_big") or animation(head,"chew_shock_loop") or animation(head,"chew_shock_pst")
 if chewing and dirt and best<4^2 then
  self.worm_target=dirt;self.lure=nil;return "fight"
 end
 self.worm_target=nil
 -- 咀嚼结束马上停手；土堆冒头会吞1.5码内生物，诱饵仅需进入2码物品范围。
 if emerging and head and p:DistSq(head:GetPosition())<4^2 then
  return self:Move(unit(head:GetPosition(),p,4.5),"巨大蠕虫 · 避开吞食冒头")
 end
 if not emerging then
  local policy=require("shadowself/control/arena_policy");local distance
  for _,e in ipairs(entities) do
   if alive(e) and policy.monsters[e.prefab] and not e:HasTag("worm_boss_piece") and e.prefab~="worm_boss"
    and e.replica and e.replica.combat and not e:HasTag("sleeping") then
    local d=p:DistSq(e:GetPosition())
    if d<5^2 and (not distance or d<distance) then self.add_target=e;distance=d end
   end
  end
  if self.add_target then return "fight" end
 end
 if bait then
  local bp=bait:GetPosition()
  if not self.lure or self.lure.bait~=bait or self.lure.baitpos:DistSq(bp)>.5^2 then
   local toward=head and head:GetPosition() or dirt and dirt:GetPosition() or self.center or p
   self.lure={bait=bait,baitpos=bp,goal=unit(bp,toward,-2.8),since=GetTime()}
  end
  local goal=self.lure.goal
  -- 固定一轮诱饵落点，不能每次按玩家新位置反向计算而左右折返。
  if GetTime()-self.lure.since>5 and head and dirt and not emerging and not dirt:HasTag("notarget") then
   self.worm_target=dirt;return "fight"
  end
  if TheWorld.Map:IsPassableAtPoint(goal.x,0,goal.z) and not TheWorld.Map:IsOceanAtPoint(goal.x,0,goal.z) then
   if p:DistSq(goal)>.8^2 then return self:Move(goal,"巨大蠕虫 · 引向地面物品，等待咀嚼窗口") end
   self.arena:StopCombat();self.arena:Say("巨大蠕虫 · 诱饵旁保持安全距离，等待吞食")
   return "hold"
  end
 end
 -- 没有合适诱饵时不永久等咀嚼；由原走位攻击可伤害的土堆。
 if not emerging and dirt and not dirt:HasTag("notarget") then self.worm_target=dirt;return "fight" end
 self.arena:StopCombat()
 return "hold"
end
function S:MaintainCombat()
 -- 结冰时本体带notarget，原走A可能找不到主目标；仍要推进既有的小蟹催眠/破冰状态机。
 if self.arena.wave~=8 or not alive(self.crab) then return end
 local c=self.arena.bridge.coordinator
 if not c then return end
 c.crabking=c.crabking or require("shadowself/control/crabking")(c)
 c.crabking.king=self.crab
 local mode,target=c.crabking:Tick(self.crab)
 if mode=="support" or mode=="move" then self.arena.bridge:PauseAttack()
 elseif target then self.arena.bridge.priority_target=target end
end
function S:Tick(entities)
 if self.arena.wave==12 and (self.arena.detected_route=="shadow" or self.arena.route=="shadow") then
  self.arena.stage12=self.arena.stage12 or require("shadowself/control/arena_stage12")(self.arena)
  return self.arena.stage12:Tick(entities)
 end
 if self.arena.wave==8 then return self:Crab(entities) end
 if self.arena.wave==11 then
  self.arena.stage11=self.arena.stage11 or require("shadowself/control/arena_stage11")(self.arena)
  return self.arena.stage11:Tick(entities)
 end
 for _,e in ipairs(entities) do if alive(e) and (e.prefab=="worm_boss" or e.prefab=="worm_boss_head" or e.prefab=="worm_boss_dirt" or e.prefab=="worm_boss_dirt_ground_fx") then return self:Worm(entities) end end
 self.worm_target=nil;self.add_target=nil
end
function S:Allowed(e)
 -- 日志中的暗影土堆单独走已有普通选敌，不能被原版蠕虫的进食目标锁挡住。
 if self.arena.wave==13 and e.prefab=="worm_boss_shadow_dirt" then return true end
 if e.prefab=="worm_boss" or e:HasTag("worm_boss_piece") then return e==self.worm_target end
 return true
end
return S
