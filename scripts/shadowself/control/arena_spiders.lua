-- 第二关蛛蝠组：开局居中等刷新，两种洞穴蜘蛛不攻击。
local A=require("shadowself/control/actions")
local S=Class(function(self,opening) self.opening=opening;self.arena=opening.arena end)
local special={spider_hider=true,spider_spitter=true}
local victims={spider=true,bat=true}
local function live(e) local h=e.replica and e.replica.health;return e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not(h and h.IsDead and h:IsDead()) end
function S:Active()
 if self.arena.wave~=2 then return false end
 local spider,bat=false,false
 for _,e in ipairs(self.arena.entities or self.arena.enemies or {}) do if live(e) then
  if special[e.prefab] then self.active=true end
  spider=spider or e.prefab=="spider";bat=bat or e.prefab=="bat"
 end end
 if spider and bat then self.active=true;self.ready=true end
 return self.active or false
end
function S:Allowed(e) return not self:Active() or self.ready and e and victims[e.prefab] or false end
function S:Tick()
 if not self:Active() then return false,false end
 if self.ready then return true,false end
 local arena=self.arena;arena:StopCombat()
 local center=arena.encounters:FindCenter()
 if center and arena.player:GetPosition():DistSq(center)>1 then
  if GetTime()>=(self.next_move or 0) then A.Move(arena.player,center);self.next_move=GetTime()+.2 end
 elseif not self.stopped then A.Stop(arena.player);self.stopped=true end
 arena:Say("第二关蛛蝠 · 中间等待蝙蝠和普通蜘蛛刷新，不打洞穴蜘蛛")
 return true,true
end
return S
