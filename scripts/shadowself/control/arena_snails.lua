local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local M={}
local names={snurtle="蜗牛龟",slurtle="蛞蝓龟"}
function M.Snail(e) return e and names[e.prefab]~=nil end
function M.Burning(e)
 return M.Snail(e) and (e:HasTag("fire") or e:HasTag("burning")) or false
end
-- 原版两种龟均MakeMediumBurnableCharacter(8秒)，爆炸半径3；只给本次亲自点燃的目标估时。
function M.Remaining(e)
 if not M.Burning(e) then
  if e and e._shadowself_snail_fire and e._shadowself_snail_fire.confirmed then e._shadowself_snail_fire=nil end
  return 0
 end
 local s=e._shadowself_snail_fire
 if not s then return 0 end
 if not s.confirmed then
  if GetTime()-s.requested>1.5 then return 0 end
  s.confirmed=true
 end
 return math.max(0,s.requested+7.7-GetTime())
end
function M.Explosive(e) return M.Burning(e) and M.Remaining(e)<=2 end
local function release(boss)
 local c=boss.c;local s=boss.snail_weapon
 if s and c.gear and c.gear.forced_weapon==s.torch then c.gear.forced_weapon=s.previous end
 boss.snail_weapon=nil
end
local function clearance(c,target,goal)
 local p=c.player:GetPosition()
 for _,e in ipairs(c.enemies or {}) do if e~=target and e:IsValid() and M.Burning(e) then
  local q=e:GetPosition();local dx,dz=goal.x-p.x,goal.z-p.z;local length=dx*dx+dz*dz
  local t=length>0 and math.max(0,math.min(1,((q.x-p.x)*dx+(q.z-p.z)*dz)/length)) or 0
  local near=Vector3(p.x+dx*t,0,p.z+dz*t)
  local radius=3+c.player:GetPhysicsRadius(0)+1
  local wave=c.plan and c.plan.arena_wave and c.plan.arena_wave()
  if (wave~=5 or M.Explosive(e)) and near:DistSq(q)<radius^2 then return e end
  if not M.Explosive(e) and c.observed then c.observed[e.GUID]={neutral=true} end
 end end
end
local function slugattack(e)
 return e.prefab=="slurtle" and e.AnimState and e.AnimState:IsCurrentAnimation("atk") and e.AnimState:GetCurrentAnimationFrame()<12
end
function M.Dodge(c,e,base)
 local plan=c.plan;local wave=plan and plan.arena_wave and plan.arena_wave()
 if not plan or not plan.arena or (wave~=5 and wave~=6) or not M.Snail(e) then return base end
 if M.Burning(e) then return false end -- 实际火焰/爆炸交给场地危险区，不再追着它攻击。
 if slugattack(e) then
  local range=(e.replica and e.replica.combat and e.replica.combat.GetAttackRangeWithWeapon and e.replica.combat:GetAttackRangeWithWeapon() or 2.5)
   +e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.6
  return {atkanim="atk",point="target",dist=range,angle=0,update=true,exclusive=true,noattack=true}
 end
 return base
end
function M.Tick(boss,target)
 if not M.Snail(target) then boss.snail_strike=nil;release(boss);return end
 local c=boss.c;local p=c.player;local now=GetTime()
 -- 有尚未点燃的另一只就立即转火，不等第一只爆炸；过期火源仍优先撤离。
 if M.Burning(target) then
  local nextone,near
  for _,e in ipairs(c.enemies or {}) do if M.Snail(e) and e~=target and e:IsValid()
   and not e:HasTag("dead") and not e:HasTag("isdead") and not M.Burning(e) and c.bridge.allowed(e) then
   local d=p:GetPosition():DistSq(e:GetPosition());if not near or d<near then nextone,near=e,d end
  end end
  if nextone then
   target=nextone;boss:Select(target)
   if c.plan and c.plan.arena_wave and c.plan.arena_wave()==5 then boss.snail_strike=nil;boss.next_snail_fire=nil;boss.snail_shot=nil end
  else
   release(boss);boss.snail_shot=nil;boss:Release()
   if p:GetPosition():DistSq(target:GetPosition())<5^2 then return boss:Away(target,5,names[target.prefab].." · 全部点燃后避开爆炸") end
   for _,e in ipairs(c.enemies or {}) do
    if e~=target and not M.Snail(e) and c.bridge.allowed(e) then return "attack",boss:Select(e) end
   end
   c.bridge:PauseAttack();return "support",target
  end
 end
 local torch=boss:Item("torch")
 if not torch then release(boss);return end
 c.bridge:PauseAttack()
 local pos=p:GetPosition();local q=target:GetPosition();local d=math.sqrt(pos:DistSq(q))
 local contact=(target.GetPhysicsRadius and target:GetPhysicsRadius(0) or .5)+(p.GetPhysicsRadius and p:GetPhysicsRadius(0) or .5)
 local reach=contact+(target.prefab=="snurtle" and .02 or .04)
 local dx,dz=pos.x-q.x,pos.z-q.z;if d<.01 then dx,dz,d=1,0,1 end
 local goal=Vector3(q.x+dx/d*reach,0,q.z+dz/d*reach)
 local danger=clearance(c,target,goal)
 if danger then boss.snail_strike=nil;release(boss);return boss:Away(danger,5,"蛞蝓龟/蜗牛龟 · 预留爆炸撤离时间") end
 -- 蛞蝓龟第9帧实际命中；先完成这次退避，再利用恢复段点燃。
 local attacker
 for _,e in ipairs(c.enemies or {target}) do
  if e:IsValid() and slugattack(e) then
   local r=(e.replica and e.replica.combat and e.replica.combat.GetAttackRangeWithWeapon and e.replica.combat:GetAttackRangeWithWeapon() or 2.5)
    +e:GetPhysicsRadius(0)+p:GetPhysicsRadius(0)+.6
   if e==target or pos:DistSq(e:GetPosition())<r*r then attacker=e;break end
  end
 end
 if attacker then
  boss.snail_strike=nil;boss.next_snail_fire=nil
  local r=(attacker.replica and attacker.replica.combat and attacker.replica.combat.GetAttackRangeWithWeapon and attacker.replica.combat:GetAttackRangeWithWeapon() or 2.5)
   +attacker:GetPhysicsRadius(0)+p:GetPhysicsRadius(0)+.6
  if pos:DistSq(attacker:GetPosition())<r*r then return boss:Away(attacker,r,"蛞蝓龟 · 先躲咬击，再用火把反击") end
  return "support",target
 end
 local strike=boss.snail_strike
 if strike and strike.target==target and not M.Burning(target) and now<strike.until_time
  and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==strike.torch then
  -- 保留完整出手/同步窗口，不因龟稍微移动就下发跟随打断本次攻击。
  return "support",target
 end
 boss.snail_strike=nil
 if p.components.playercontroller:IsBusy() or p:HasTag("attack") then return "support",target end
 -- 先持火把再贴近；到达后不再耗一个换装往返，避免慢速移动的龟离开接触点。
 if not boss.snail_weapon then
  boss:Release()
  if c.gear then boss.snail_weapon={torch=torch,previous=c.gear.forced_weapon};c.gear.forced_weapon=torch end
 end
 if not c.mechanisms:Equip(torch) then return "support",target end
 if math.sqrt(pos:DistSq(q))>reach+.03 then
  if Nav.Safe(c,goal,target) then
   -- 这段短距离接近保留火把，不启动会切回手杖的通用躲避装备流程。
   boss:Release();c:Move(goal,names[target.prefab].." · 持火把贴近后停步点燃");return "move",target
  end
  return "support",target
 end
 boss:Release()
 if c.mechanisms:Equip(torch) and now>=(boss.next_snail_fire or 0) then
  A.Stop(p) -- 紧贴、停步、立即攻击，同一次调度完成。
  if A.Attack(p,target,function() return target:IsValid() and not M.Burning(target)
   and not target:HasTag("dead") and not target:HasTag("isdead") and c.bridge.allowed(target)
   and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==torch
   and p:GetPosition():DistSq(target:GetPosition())<=((p.replica.combat and p.replica.combat.GetAttackRangeWithWeapon
    and p.replica.combat:GetAttackRangeWithWeapon() or c.gear:AttackRange())+target:GetPhysicsRadius(0))^2
   and not clearance(c,target,target:GetPosition()) end) then
   local window=1.1+require("shadowself/control/nettiming").Delay(c)
   boss.snail_strike={target=target,torch=torch,until_time=now+window}
   boss.next_snail_fire=now+window;boss.snail_shot=target
   target._shadowself_snail_fire={requested=now}
  end
 end
 return "support",target
end
return M
