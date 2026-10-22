local A=require("shadowself/control/actions")
local Tools=require("shadowself/control/arena_tools")
local Status=require("shadowself/control/status")
local S=Class(function(self,owner) self.owner=owner;self.c=owner.c;self.ignited={} end)
local function live(e) return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") end
function S:Little(target,entities)
 if target.prefab~="little_walrus" then self.little=nil;return end
 local c=self.c;local pos=c.player:GetPosition()
 for _,e in ipairs(entities) do
  if e~=target and live(e) and c.bridge.allowed(e) then return "attack",self.owner:Target(e) end
 end
 local now=GetTime();local d=math.sqrt(pos:DistSq(target:GetPosition()))
 if Status.Sleeping(target) then self.little=nil;self.owner:Release();return "attack",self.owner:Target(target) end
 if d<=2.5 then self.little=nil;return end
 if not self.little or self.little.target~=target then self.little={target=target,since=now} end
 local state=self.little
 if now-state.since<3 then return end
 local flute=Tools.Owned(c,"panflute")
 if not flute then if Tools.Recover(c,"panflute") then return "support",target end;return end
 c.bridge:PauseAttack()
 if c.player.components.playercontroller:IsBusy() then return "support",target end
 if state.sent and now-state.sent<3.5 then return "support",target end
 local range=(TUNING.PANFLUTE_SLEEPRANGE or 15)-1
 if d>range then
  local q=target:GetPosition()
  return self.owner:Move(Vector3(q.x+(pos.x-q.x)/d*(range-.5),0,q.z+(pos.z-q.z)/d*(range-.5)),"小海象 · 靠近催眠范围",target),target
 end
 if A.Self(c.player,flute,ACTIONS.PLAY) then state.sent=now end
 return "support",target
end
function S:Pirates(entities)
 local c=self.c;local monkeys={};local captain
 for _,e in ipairs(entities) do if live(e) and c.bridge.allowed(e) then
  if e.prefab=="powdermonkey" then monkeys[#monkeys+1]=e elseif e.prefab=="primemate" then captain=e end
 end end
 if not captain then return end
 if #monkeys>0 then
  self.wind=self.wind or require("shadowself/control/arena_goats")(self.owner,"火药猴")
  local mode,picked=self.wind:Tick(monkeys)
  if mode then return mode,picked end
  return "attack",self.owner:Target(monkeys[1])
 end
 self.owner:Target(captain)
 if captain:HasTag("fire") or captain:HasTag("burning") then self.ignited[captain]=true end
 if self.ignited[captain] then
  self.owner:Release()
  local weapon=c.gear:Weapon();c.gear:Swap("attack",c.snapshot)
  if weapon and c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)~=weapon then return "support",captain end
  return "attack",captain
 end
 local torch=Tools.Owned(c,"torch")
 if not torch then return "attack",captain end
 c.bridge:PauseAttack()
 if c.player.components.playercontroller:IsBusy() then return "support",captain end
 local p=c.player:GetPosition();local q=captain:GetPosition();local d=math.sqrt(p:DistSq(q));local reach=2+captain:GetPhysicsRadius(0)
 if d>reach then
  return self.owner:Move(Vector3(q.x+(p.x-q.x)/d*(reach-.1),0,q.z+(p.z-q.z)/d*(reach-.1)),"大副 · 靠近火把点燃",captain),captain
 end
 if c.mechanisms:Equip(torch) and GetTime()>=(self.next_fire or 0) then
  self.owner:Release()
  if A.Attack(c.player,captain,function() return captain:IsValid() and not captain:HasTag("fire") end) then self.next_fire=GetTime()+1.2 end
 end
 return "support",captain
end
function S:Tick(target)
 local c=self.c;local entities=c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies
 local mode,picked=self:Pirates(entities)
 if mode then return mode,picked end
 return self:Little(target,entities)
end
return S
