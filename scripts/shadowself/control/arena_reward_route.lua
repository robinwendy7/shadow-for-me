-- 四箱取物前的独占巡游阶段；借用Arena tick，不另开移动线程。
local R=require("shadowself/control/arena_late_runtime")
local F=require("shadowself/control/arena_fire")
local Nav=require("shadowself/control/navigation")
local Policy=require("shadowself/control/arena_policy")
local Pig=require("shadowself/control/arena_scrappig")
local M={}
local function piece(e)
 return e.prefab=="worm_boss_segment" or e.prefab=="worm_boss_tail"
  or e.prefab=="worm_boss_shadow_segment" or e.prefab=="worm_boss_shadow_tail"
end
local function monster(e)
 if not R.Live(e) or e.prefab=="chest_mimic" then return false end
 if e.prefab=="worm_boss_head" or e.prefab=="worm_boss_shadow_head" then return true end
 if (e.prefab or ""):find("worm_boss",1,true)==1 or e:HasTag("worm_boss_piece") then return false end
 return Policy.Monster(e.prefab,11) or e:HasTag("monster") or e:HasTag("hostile")
end
function M.Near(c,entities,box)
 local p=c.player:GetPosition()
 for _,e in ipairs(entities or {}) do if monster(e) and not Pig.LootSafe(c,e,box) then
  local kind,range=Pig.Kind(e);local ep=e:GetPosition()
  if p:DistSq(ep)<=6^2 or kind and (p:DistSq(ep)<range^2 or box and box:GetPosition():DistSq(ep)<range^2) then return true end
 end end
 return false
end
function M.Segment(c,entities,box)
 local p=c.player:GetPosition();local q=box and box:GetPosition() or p
 local dx,dz=q.x-p.x,q.z-p.z;local length=dx*dx+dz*dz
 for _,e in ipairs(entities or {}) do if R.Live(e) and piece(e) then
  local ep=e:GetPosition();local radius=math.max(2,e.GetPhysicsRadius and e:GetPhysicsRadius(0) or 0)+c.player:GetPhysicsRadius(0)+.7
  local t=length>0 and math.max(0,math.min(1,((ep.x-p.x)*dx+(ep.z-p.z)*dz)/length)) or 0
  if ep:DistSq(Vector3(p.x+dx*t,0,p.z+dz*t))<=radius^2 then return true end
 end end
 return false
end
function M.Begin(c,reason)
 if c.reward_route and c.reward_route.patrol then return end
 c.reward_route={patrol=true,elapsed=0};c.route_revision=(c.route_revision or 0)+1
 if c.opened then
  local inv=c.opened:IsValid() and c.opened.replica and c.opened.replica.container
  if inv and inv:IsOpenedBy(c.player) then inv:Close() end
 end
 c.opened=nil;c.confirmed_open=nil;c.open_since=nil
 c.arena:Say(reason)
end
function M.Tick(c,entities)
 local s=c.reward_route
 local boss=c.s.boss
 if c.opened and R.Live(boss) and boss.prefab=="daywalker" and M.Near(c,entities,c.opened) then
  M.Begin(c,"暗影疯猪 · 护盾已消耗，关闭宝箱先拉开再继续");s=c.reward_route
 end
 if s and s.patrol then
  for _,e in ipairs(entities or {}) do if Pig.ShieldLoot(c,e) and not M.Near(c,entities,s.target) and not M.Segment(c,entities,s.target) then
   s.patrol=nil
   local p=c.player:GetPosition();local dist
   for id,box in pairs(c.boxes) do if not c.visited[id] and R.Live(box) then
    local d=p:DistSq(box:GetPosition());if not dist or d>dist then s.target=box;dist=d end
   end end
   break -- 护盾实际就绪后优先利用开箱窗口，不再机械等足七秒。
  end end
 end
 if not s or not s.patrol then
  if c.opened and M.Segment(c,entities,c.opened) then M.Begin(c,"奖励流程 · 体节影响开箱，放弃本次尝试并继续外圈巡游");s=c.reward_route
  else return false end
 end
 local context=c.s.context;local center=context.plan and context.plan.arena_center and context.plan.arena_center()
 if not center and c.arena.encounters.FindCenter then center=c.arena.encounters:FindCenter() end
 if not center then c.arena:Say("奖励流程 · 等待场地中心，尚未开始计巡游七秒");return true end
 local zones={};for _,z in ipairs(context.hazards or {}) do zones[#zones+1]=z end
 for _,e in ipairs(entities or {}) do if R.Live(e) then
  if monster(e) then zones[#zones+1]={pos=e:GetPosition(),radius=6,source=e}
  elseif piece(e) then zones[#zones+1]={pos=e:GetPosition(),radius=math.max(2,e.GetPhysicsRadius and e:GetPhysicsRadius(0) or 0)+c.player:GetPhysicsRadius(0)+.7,source=e} end
 end end
 local p=c.player:GetPosition();local now=GetTime()
 if s.last_pos and now-s.last_time<=.5 and p:DistSq(s.last_pos)>.05^2 and math.max(math.abs(p.x-center.x),math.abs(p.z-center.z))>=16 then
  s.elapsed=s.elapsed+now-s.last_time
 end
 s.last_pos=p;s.last_time=now
 if s.elapsed>=7 then
  s.patrol=nil;local best,dist
  for id,e in pairs(c.boxes) do if not c.visited[id] and R.Live(e) then
   local d=p:DistSq(e:GetPosition());if not dist or d>dist then best,dist=e,d end
  end end
  s.target=best
  return false
 end
 local route=setmetatable({enemies={},hazards=zones,plan={arena=true,arena_center=function() return center end}},{__index=context})
 local q
 if R.Live(boss) and boss.prefab=="daywalker" then
  local wanted=require("shadowself/control/arena_perimeter")(route,s,7)
  if wanted then q=Nav.Select(route,wanted);if p:DistSq(q)<.1^2 then q=nil end end
 end
 q=q or F.Escape(c.player,zones)
 if not q then
  local wanted=require("shadowself/control/arena_perimeter")(route,s,7)
  if wanted then q=Nav.Select(route,wanted) end
 end
 if q then c.arena.encounters:Move(q,"奖励流程 · 场地外圈巡游七秒，再走向最远未完成宝箱") end
 return true
end
function M.Before(c,entities,box)
 if M.Near(c,entities,box) or M.Segment(c,entities,box) then
  M.Begin(c,"奖励流程 · 六码内有怪或体节阻挡，先外圈巡游七秒")
  M.Tick(c,entities);return true
 end
 return false
end
function M.Valid(c,box,revision)
 if revision~=(c.route_revision or 0) or c.reward_route and c.reward_route.patrol or c.opened~=box then return false end
 local p=c.player:GetPosition();local entities=TheSim:FindEntities(p.x,0,p.z,60,nil,{"INLIMBO","FX","DECOR"})
 if M.Near(c,entities,box) or M.Segment(c,entities,box) then
  M.Begin(c,"奖励流程 · 开箱发出前出现新危险，取消本次并重新巡游");return false
 end
 return true
end
return M
