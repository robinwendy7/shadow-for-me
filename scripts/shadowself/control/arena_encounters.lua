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
function S:Reset() self.crab=nil;self.center=nil;self.boat=nil;self.deploy=nil;self.ice=nil;self.retreat=nil;self.worm_target=nil;self.add_target=nil;self.lure=nil;self.next_move=nil;self.last_goal=nil;self.next_equip=nil;self.next_row=nil;self.wait_scene=nil;self.wait_water=nil end
function S:FindCenter()
 if self.center then return self.center end
 local p=self.player:GetPosition();local map=TheWorld.Map;local tile=WORLD_TILES and WORLD_TILES.COTL_BRICK
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
function S:Row(boat,goal,retreat)
 local oar
 for _,item in ipairs(A.Items(self.player)) do if item.prefab=="oar_driftwood" or item:HasTag("oar") then oar=item;break end end
 if not oar then return "failed","帝王蟹关缺少船桨，无法划向场地中央。" end
 if not self:Equip(oar) then return "hold" end
 self.arena:StopCombat()
 local p=self.player:GetPosition();local bp=boat:GetPosition();local aim=unit(bp,goal,12)
 -- ROW目标必须在船外；站在划桨方向的船沿，原版控制器负责划桨动作与冷却。
 local edge=unit(bp,goal,math.max(1,(boat.GetPhysicsRadius and boat:GetPhysicsRadius(0) or 4)-.6))
 if p:DistSq(edge)>1.2^2 then return self:Move(edge,"帝王蟹 · 走到船沿准备划桨") end
 if not self.player.components.playercontroller:IsBusy() and GetTime()>=(self.next_row or 0) then
  A.Ground(self.player,aim,ACTIONS.ROW);self.next_row=GetTime()+.9
 end
 self.arena:Say(retreat and "帝王蟹 · 划回外圈安全陆地" or "帝王蟹 · 划向场地中央")
 return "hold"
end
function S:Crab(entities)
 local p=self.player:GetPosition();local king;local boats={};local walls=0;local ice=false
 for _,e in ipairs(entities) do
  if e.prefab=="crabking" then king=e end
  if alive(e) and (e.prefab=="boat" or e.prefab=="boat_grass") then boats[#boats+1]=e end
  if alive(e) and e.prefab=="crabking_icewall" then walls=walls+1 end
  if e.prefab=="boat_ice_crabking" and (animation(e,"idle3") or animation(e,"cracked2")) then ice=true end
 end
 if king then self.crab=king;self.center=king:GetPosition() end
 local center=self:FindCenter()
 if not center then
  self.arena:StopCombat();self.wait_scene=self.wait_scene or GetTime()
  if GetTime()-self.wait_scene<8 then self.arena:Say("帝王蟹 · 等待场地地形同步");return "hold" end
  return "failed","未识别到帝王蟹场地中心，停止自动下海。"
 end
 if self.crab and not alive(self.crab) then self.retreat=true end
 local inice=alive(king) and king:HasTag("icewall")
 if inice then
  if not self.ice then self.ice={walls=walls} end
  if walls<self.ice.walls then self.ice.first_break=self.ice.first_break or GetTime() end
  self.ice.walls=walls
  if self.ice.first_break then
   -- 此单人第8关的adapter固定8绿+珍珠，珍珠令blue=3；原版首次破墙后19秒融冰。
   local blue=king.gemcount and king.gemcount.blue or 3
   local duration=math.max(3,25-blue*2)
   local shore=self:ShorePoint(center)
   local locomotor=self.player.components.locomotor
   local speed=locomotor and locomotor.GetRunSpeed and locomotor:GetRunSpeed() or 6
   local reserve=shore and math.sqrt(p:DistSq(shore))/math.max(3.5,speed)+1 or 5
   if GetTime()+reserve>=self.ice.first_break+duration then self.retreat=true end
  end
 elseif self.ice then self.retreat=true end
 if ice then self.retreat=true end
 local platform=self.player.GetCurrentPlatform and self.player:GetCurrentPlatform()
 local onboat=platform and (platform.prefab=="boat" or platform.prefab=="boat_grass")
 if self.retreat then
  local shore=self:ShorePoint(center)
  if not shore then return "failed","帝王蟹退场未找到外圈安全陆地。" end
  if p:DistSq(shore)>2^2 then
   if onboat and platform:GetPosition():DistSq(shore)>7^2 then return self:Row(platform,shore,true) end
   return self:Move(shore,"帝王蟹 · 离开即将碎裂的冰面，退到场地边缘")
  end
  if alive(king) then
   if not king:HasTag("icewall") then self.retreat=nil;self.ice=nil end
   self.arena:Say("帝王蟹 · 在外圈等待本轮融冰结束")
   return "hold"
  end
  self.arena:StopCombat();self.arena:Say("帝王蟹 · 在安全边缘等待服务器切换下一关")
  return "hold"
 end
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
  return "fight"
 end
 if not onboat then
  local nearest,dist
  for _,boat in ipairs(boats) do local d=p:DistSq(boat:GetPosition());if not dist or d<dist then nearest,dist=boat,d end end
  if nearest then
   self.boat=nearest;self.deploy=nil
   return self:Move(nearest:GetPosition(),"帝王蟹 · 上船")
  end
  if self.deploy then
   if GetTime()<self.deploy.deadline then self.arena:StopCombat();return "hold" end
   return "failed","放船后未收到船实体确认；服务器可能禁止DEPLOY，已停止下海流程。"
  end
  local kit
  for _,item in ipairs(A.Items(self.player)) do
   if item.prefab=="boat_item" then kit=item;break elseif item.prefab=="boat_grass_item" then kit=item end
  end
  if not kit then
   if self.arena:Loot(self.arena.items or {}) then return "hold" end
   self.arena:Say("帝王蟹 · 等待船套同步并拾取")
   return "hold"
  end
  local ii=kit.replica.inventoryitem;local point
  for d=4,9 do
   for i=0,15 do local a=i*math.pi/8;local q=Vector3(p.x+math.cos(a)*d,0,p.z+math.sin(a)*d)
    if TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) and ii:CanDeploy(q,nil,self.player,0) then
     if not point or q:DistSq(center)<point:DistSq(center) then point=q end
    end
   end
   if point then break end
  end
  if not point then
   self.wait_water=self.wait_water or GetTime()
   if GetTime()-self.wait_water<8 then self.arena:StopCombat();self.arena:Say("帝王蟹 · 等待水面及放船位置同步");return "hold" end
   return "failed","附近没有可放船水面，停止下海以免落水。"
  end
  self.wait_water=nil
  self.arena:StopCombat()
  if not self.player.components.playercontroller:IsBusy() and A.Deploy(self.player,kit,point) then
   self.deploy={deadline=GetTime()+6,point=point};self.arena:Say("帝王蟹 · 放船并等待服务器确认")
  end
  return "hold"
 end
 self.boat=platform
 local distance=math.sqrt(p:DistSq(center))
 local reach=alive(king) and (king.GetPhysicsRadius and king:GetPhysicsRadius(0) or 2)+2.5 or 7
 if distance>reach then return self:Row(platform,center) end
 if not alive(king) then self.arena:StopCombat();self.arena:Say("帝王蟹 · 已到中央，等待本体出现");return "hold" end
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
 if self.arena.wave==8 then return self:Crab(entities) end
 for _,e in ipairs(entities) do if alive(e) and (e.prefab=="worm_boss" or e.prefab=="worm_boss_head" or e.prefab=="worm_boss_dirt" or e.prefab=="worm_boss_dirt_ground_fx") then return self:Worm(entities) end end
 self.worm_target=nil;self.add_target=nil
end
function S:Allowed(e)
 if e.prefab=="worm_boss" or e:HasTag("worm_boss_piece") then return e==self.worm_target end
 return true
end
return S
