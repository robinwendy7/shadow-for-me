local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local M={}
function M.Snail(e) return e and (e.prefab=="slurtle" or e.prefab=="snurtle") end
function M.Burning(e)
 return M.Snail(e) and (e:HasTag("fire") or e:HasTag("burning")) or false
end
function M.Tick(boss,target)
 if not M.Snail(target) then return end
 local c=boss.c;local p=c.player;local now=GetTime()
 if M.Burning(target) then
  boss.snail_shot=nil;boss:Release()
  if p:GetPosition():DistSq(target:GetPosition())<5^2 then return boss:Away(target,5,"蜗牛 · 点燃后避开爆炸") end
  for _,e in ipairs(c.enemies or {}) do
   if e~=target and c.bridge.allowed(e) then return "attack",boss:Select(e) end
  end
  c.bridge:PauseAttack();return "support",target
 end
 local torch=boss:Item("torch")
 if not torch then return end -- 没有火把保留原有战斗，不强行假装点燃成功。
 c.bridge:PauseAttack()
 if p.components.playercontroller:IsBusy() then return "support",target end
 local pos=p:GetPosition();local q=target:GetPosition();local d=math.sqrt(pos:DistSq(q))
 local reach=2+(target.GetPhysicsRadius and target:GetPhysicsRadius(0) or .5)
 if d>reach then
  local goal=Vector3(q.x+(pos.x-q.x)/d*(reach-.1),0,q.z+(pos.z-q.z)/d*(reach-.1))
  if Nav.Safe(c,goal,target) then return boss:Move(goal,"蜗牛 · 靠近用火把点燃",target) end
  for _,e in ipairs(c.enemies or {}) do
   if e~=target and not M.Burning(e) and c.bridge.allowed(e) then return "attack",boss:Select(e) end
  end
  return "support",target
 end
 if c.mechanisms:Equip(torch) and now>=(boss.next_snail_fire or 0) then
  boss:Release()
  if A.Attack(p,target,function() return target:IsValid() and not M.Burning(target) end) then
   -- 等着火同步，不能每帧重复打；未命中或点燃失败才允许稍后重试。
   boss.next_snail_fire=now+1.2;boss.snail_shot=target
  end
 end
 return "support",target
end
return M
