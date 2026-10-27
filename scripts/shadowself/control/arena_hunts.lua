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
 if not self.pirates then
  local found=false
  for _,e in ipairs(entities) do if live(e) and (e.prefab=="prime_mate" or e.prefab=="powder_monkey") then found=true;break end end
  if not found then return end
 end
 self.pirates=self.pirates or require("shadowself/control/arena_pirates")(self.owner)
 return self.pirates:Tick(entities)
end
function S:Tick(target)
 local c=self.c;local entities=c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies
 local mode,picked=self:Pirates(entities)
 if mode then return mode,picked end
 return self:Little(target,entities)
end
return S
