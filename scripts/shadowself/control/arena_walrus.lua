local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local Tools=require("shadowself/control/arena_tools")
local W=Class(function(self,arena) self.arena=arena;self.traps={};self.escorts={};self.engaged={} end)
local function live(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
local function radius(e) return e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5 end
function W:Escort(e) return self.active and self.escorts[e] and not self.traps[e] or false end
function W:Close(e)
 return self.arena.player:GetPosition():DistSq(e:GetPosition())<=(radius(e)+radius(self.arena.player)+.25)^2
end
function W:Committed(e)
 return self.active and self.control_done and e==self.target and self.engaged[e]
  and (e.prefab=="walrus" or e.prefab=="little_walrus") and live(e) or false
end
function W:CanAttack(e)
 if not self.active then return true end
 if not self.control_done or not e or e~=self.target then return false end
 return (e.prefab~="walrus" and e.prefab~="little_walrus") or self:Committed(e) or self:Close(e)
end
function W:Asleep()
 if live(self.walrus) and not Status.Sleeping(self.walrus) then return false end
 if live(self.little) and not Status.Sleeping(self.little) then return false end
 for e in pairs(self.escorts) do if live(e) and not Status.Sleeping(e) then return false end end
 return true
end
function W:Covered(point)
 local range=TUNING.PANFLUTE_SLEEPRANGE or 15
 for _,e in ipairs({self.walrus,self.little}) do
  if live(e) and point:DistSq(e:GetPosition())>(range-1)^2 then return false end
 end
 for e in pairs(self.escorts) do
  if live(e) and point:DistSq(e:GetPosition())>(range-1)^2 then return false end
 end
 for e in pairs(self.traps) do
  if live(e) and point:DistSq(e:GetPosition())<=(range+1)^2 then return false end
 end
 return true
end
function W:Point()
 local p=self.arena.player:GetPosition();local center=self.walrus:GetPosition();local candidates={p}
 for _,r in ipairs({0,3,6,9,12,14}) do for i=0,31 do
  local a=i*math.pi/16;candidates[#candidates+1]=Vector3(center.x+math.cos(a)*r,0,center.z+math.sin(a)*r)
 end end
 local best,score;local map=TheWorld.Map
 for _,q in ipairs(candidates) do
  if self:Covered(q) and map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and require("shadowself/control/arena_fire").Safe(self.arena.player,q,self.arena.fire_zones) then
   local d=p:DistSq(q);if not score or d<score then best,score=q,d end
  end
 end
 return best
end
function W:Tick(enemies,entities)
 local arena=self.arena;local p=arena.player;local pc=p.components.playercontroller;local now=GetTime()
 for _,e in ipairs(entities or enemies) do
  if e.prefab=="walrus" and live(e) then self.walrus=e;self.active=true end
  if e.prefab=="little_walrus" then self.little=e end
 end
 if not self.active then return false,false end
 for _,e in ipairs(entities or enemies) do
  if e.prefab=="icehound" or e.prefab=="firehound" then
   if not self.sent and not self.control_done and Status.Sleeping(e) and not self.escorts[e] then self.traps[e]=true end
   if e.prefab=="icehound" and not self.traps[e] and live(e) then self.escorts[e]=true end
  end
 end
 self.target=live(self.walrus) and self.walrus or live(self.little) and self.little or nil
 if not self.target then
  local near;for e in pairs(self.escorts) do if live(e) then
   local d=p:GetPosition():DistSq(e:GetPosition());if not near or d<near then self.target=e;near=d end
  end end
 end
 arena.bridge.priority_target=self.target
 if not self.target then self.active=false;return true,false end
 if self.control_done and not next(self.engaged) and not self:Asleep() then
  self.control_done=nil;self.sent=nil;self.control_result="woke_before_engagement"
 end
 if not self.control_done then
  arena:StopCombat()
  if self.sent then
   local asleep=self:Asleep()
   if asleep and now-self.sent>=1.85 and not pc:IsBusy() then self.control_done=true;self.control_result="sleep_confirmed"
   elseif now-self.sent<3.5 or pc:IsBusy() then return true,true
   else
    self.sent=nil;self.next_try=now+.5;self.control_result="sleep_unconfirmed"
    arena:Say("海象 · 催眠未确认，停止进攻并重新控制")
    print("[ShadowSelf][walrus] sleep_unconfirmed; retrying without melee")
    return true,true
   end
  else
   if not self.little then arena:Say("海象 · 等待完整组合同步");return true,true end
   local flute
   for _,item in ipairs(A.Items(p)) do if item.prefab=="panflute" and Tools.Usable(item) then flute=item;break end end
   if not flute then
    for _,item in ipairs(arena.items or {}) do if item.prefab=="panflute" and Tools.Usable(item) then arena:Loot({item});return true,true end end
    self.control_result="missing_flute";arena:Say("海象 · 缺少可用排箫，等待补捡，禁止提前进攻");return true,true
   elseif pc:IsBusy() or now<(self.next_try or 0) then return true,true
   elseif not self:Covered(p:GetPosition()) then
    local q=self:Point()
    arena:Say("海象 · 选择排箫不覆盖冰狗陷阱的位置")
    if q and now>=(self.next_move or 0) then A.Move(p,q);self.next_move=now+.2 end
    return true,true
   else
    A.Stop(p)
    if A.Self(p,flute,ACTIONS.PLAY) then self.sent=now end
    return true,true
   end
  end
 end
 if (self.target.prefab=="walrus" or self.target.prefab=="little_walrus") and not self:Committed(self.target) and not self:Close(self.target) then
  arena:StopCombat();local q=self.target:GetPosition();local pos=p:GetPosition()
  local dx,dz=pos.x-q.x,pos.z-q.z;local d=math.max(.01,math.sqrt(dx*dx+dz*dz))
  local touch=radius(self.target)+radius(p)+.1
  if not pc:IsBusy() and now>=(self.next_move or 0) then
   A.Move(p,Vector3(q.x+dx/d*touch,0,q.z+dz/d*touch));self.next_move=now+.15
  end
  arena:Say("海象组合 · 先贴近"..self.target.prefab.."再攻击")
  return true,true
 end
 if self.target.prefab=="walrus" or self.target.prefab=="little_walrus" then self.engaged[self.target]=true end
 return true,false
end
return W
