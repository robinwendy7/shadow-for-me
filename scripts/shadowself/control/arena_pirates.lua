local A=require("shadowself/control/actions")
local Tools=require("shadowself/control/arena_tools")
local Nav=require("shadowself/control/navigation")
local Cycle=require("shadowself/control/arena_windcycle")
local P=Class(function(self,owner) self.owner=owner;self.c=owner.c end)
local function live(e)
 local h=e.replica and e.replica.health
 return e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
function P:Clear(entities,point)
 for _,e in ipairs(entities) do if live(e) and point:DistSq(e:GetPosition())<7^2 then return false end end
 return true
end
function P:Kite(entities,target)
 local c=self.c;Cycle.Hold(c);local p=c.player:GetPosition();local best,score
 local seconds=self.budget==Cycle.repeat_casts and Cycle.repeat_seconds or Cycle.first_seconds
 local label="海盗猴 · 外圈巡游"..seconds.."秒后拉开7码施法"
 local q=require("shadowself/control/arena_perimeter")(c,self,seconds)
 if q then return self.owner:Move(q,label,target),target end
 for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*6,0,p.z+math.sin(a)*6)
  if Nav.Safe(c,q) then
   local nearest=math.huge
   for _,e in ipairs(entities) do nearest=math.min(nearest,q:DistSq(e:GetPosition())) end
   local value=math.min(nearest,11^2)-Nav.Risk(c,q)*20
   if not score or value>score then best,score=q,value end
  end
 end
 if best then return self.owner:Move(best,label,target),target end
 return self.owner:Away(target,5,"海盗猴 · 优先脱离包围"),target
end
function P:Tick(entities)
 local c=self.c
 if c.plan.arena_wave and c.plan.arena_wave()~=5 then return end
 local opening=c.plan.arena_pirate_opening
 if opening and not opening.ready then c.bridge:PauseAttack();return "support",entities[1] end
 local all,monkeys={},{};local captain
 for _,e in ipairs(entities) do if live(e) and c.bridge.allowed(e) then
  if e.prefab=="powder_monkey" then monkeys[#monkeys+1]=e;all[#all+1]=e
  elseif e.prefab=="prime_mate" then captain=e;all[#all+1]=e end
 end end
 if #all==0 then if self.wind then self.wind:Stop() end;return end
 if #monkeys==0 and captain then
  Cycle.Release(c)
  if self.wind then self.wind:Stop();self.wind=nil end
  self.owner:Target(captain)
  local burning=captain:HasTag("fire") or captain:HasTag("burning")
  if not burning then
   local torch=Tools.Owned(c,"torch")
   if not torch then
    if Tools.Recover(c,"torch") then return "support",captain end
    return self.owner:Away(captain,5,"大副 · 等待可用火把，先完成点燃"),captain
   end
   c.bridge:PauseAttack()
   if not self.torch_owner then self.torch_owner={item=torch,previous=c.gear.forced_weapon};c.gear.forced_weapon=torch end
   self.owner:Release()
   if not c.mechanisms:Equip(torch) then return "support",captain end
   local p=c.player;local pos=p:GetPosition();local q=captain:GetPosition()
   local d=math.sqrt(pos:DistSq(q));local contact=p:GetPhysicsRadius(0)+captain:GetPhysicsRadius(0)+.1
   local hit=self.ignite_pending
   if hit and GetTime()<hit then return "support",captain end
   self.ignite_pending=nil
   if d>contact+.1 then
    local goal=Vector3(q.x+(pos.x-q.x)/d*contact,0,q.z+(pos.z-q.z)/d*contact)
    if Nav.Safe(c,goal,captain) then c:Move(goal,"大副 · 持火把靠近后点燃");return "move",captain end
    return "support",captain
   end
   if p.components.playercontroller:IsBusy() or p:HasTag("attack") then return "support",captain end
   A.Stop(p)
   if A.Attack(p,captain,function() return live(captain) and not captain:HasTag("fire") and not captain:HasTag("burning")
    and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==torch end) then self.ignite_pending=GetTime()+1.1 end
   return "support",captain
  end
  self.ignite_pending=nil
  if self.torch_owner then
   if c.gear.forced_weapon==self.torch_owner.item then c.gear.forced_weapon=self.torch_owner.previous end
   self.torch_owner=nil
  end
  c.bridge.chasing=nil;if c.travel then c.travel.chasing=nil;c.travel:EndDodge(c.snapshot) end

  self.owner:Release();return "attack",captain
 end
 local now=GetTime();self.since=self.since or now;self.budget=self.budget or Cycle.first_casts
 if self.wind then self.wind:ConfirmCast() end
 if self.wind and (self.wind.completed or 0)>=self.budget then
  self.wind:Stop();self.wind=nil;self.budget=Cycle.repeat_casts;self.since=now;self.edge_since=nil;self.edge_index=nil
 end
 local seconds=self.budget==Cycle.repeat_casts and Cycle.repeat_seconds or Cycle.first_seconds
 local waited=now-self.since>=seconds
 local point,done=require("shadowself/control/arena_perimeter")(c,self,seconds)
 if point then waited=done end
 if not waited or not self:Clear(all,c.player:GetPosition()) then
  if self.wind then self.wind:Stop() end
  -- 游离阶段仍推进原有安全回血；它不能提前开放旋风。
  if c.healing and c.healing:Tick(c) then return "support",monkeys[1] end
  return self:Kite(all,monkeys[1])
 end
 Cycle.Release(c)
 self.wind=self.wind or require("shadowself/control/arena_goats")(self.owner,"火药猴")
 self.wind.minimum_distance=7;self.wind.gather_time=0;self.wind.limit=self.budget
 self.wind.cast_guard=function() return self:Clear(all,c.player:GetPosition()) end
 local mode,picked=self.wind:Tick(monkeys)
 if mode then return mode,picked end
 return self:Kite(all,monkeys[1]) -- 工具耗尽时保持游离并由原工具路径补捡。
end
return P
