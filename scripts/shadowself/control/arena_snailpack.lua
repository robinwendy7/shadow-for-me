local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local Snails=require("shadowself/control/arena_snails")
local Tools=require("shadowself/control/arena_tools")
local P=Class(function(self,boss) self.boss=boss;self.c=boss.c;self.slurpers={};self.snails={} end)
local function dead(e)
 local h=e.replica and e.replica.health
 return e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()) or false
end
local function live(e) return e and e:IsValid() and not dead(e) end
local function expected()
 for _,set in ipairs(require("shadowself/data/arena_classic").encounters[5].default) do
  local snail,count=false,0
  for _,m in ipairs(set.monsters) do
   snail=snail or m.prefab=="slurtle" or m.prefab=="snurtle"
   if m.prefab=="slurper" then count=count+m.amount end
  end
  if snail and count>0 then return count end
 end
 return math.huge
end
function P:Clear(q)
 for e in pairs(self.snails) do if live(e) and q:DistSq(e:GetPosition())<=6^2 then return false end end
 return true
end
function P:Context()
 local hazards={};for _,z in ipairs(self.c.hazards or {}) do hazards[#hazards+1]=z end
 for e in pairs(self.snails) do if live(e) then hazards[#hazards+1]={pos=e:GetPosition(),radius=6.1,source=e} end end
 return setmetatable({hazards=hazards},{__index=self.c})
end
function P:CanAttack(e)
 if not self.active then return true end
 if not e then return false end
 if self.phase=="torch" then return Snails.Snail(e) end
 return self.phase=="fight" and e==self.target and not require("shadowself/control/arena_attackwindows").Block(self.c,e)
  and self:Clear(self.c.player:GetPosition()) and self:Clear(e:GetPosition())
end
function P:Kite(target)
 self.phase="separate";self.bait_seen=nil;self.standing=nil
 local q=require("shadowself/control/arena_perimeter")(self.c,self,0)
 if q then return self.boss:Move(Nav.Select(self:Context(),q,target),"蜗牛组合 · 场边巡游，先与蜗牛拉开6码",target) end
 local snail;for e in pairs(self.snails) do if live(e) then snail=e;break end end
 if snail then return self.boss:Away(snail,6.5,"蜗牛组合 · 先避开蜗牛再骗啜食者") end
 self.c.bridge:PauseAttack();return "support",target
end
function P:Weapon(target)
 local best,score;local c=self.c
 require("shadowself/legacy/combat_equipment")
 local E=require("shadowself/legacy/registry").Equipment
 local damage=require("shadowself/control/weapon_damage")
 local wet=target and (target.GetIsWet and target:GetIsWet() or target:HasTag("wet"))
 local electric=damage.Electric(c.player)
 local threshold=damage.Score(c.player,{prefab="hambat"},59.5,target)
 for _,item in ipairs(A.Items(c.player)) do if item.prefab=="hambat" then threshold=damage.Score(c.player,item,c.gear:Damage(item),target);break end end
 for _,item in ipairs(A.Items(c.player)) do
  if item.prefab~="whip" and item.prefab~="torch" and item.prefab~="cane"
   and (item.prefab~="nightstick" or wet and not electric) and E.Melee(c.player,item) and Tools.Usable(item) then
   local physical=c.gear:Damage(item)
   local value=damage.Score(c.player,item,physical,target)
   if value>=threshold then
    if not score or value>score then best,score=item,value end
   end
  end
 end
 if best then c.gear.forced_weapon=best;self.weapon=best;return true end
 if Tools.Recover(c,"hambat") then return false end
 c.status="蜗牛组合 · 等待火腿棒或更好的近战武器";return false
end
function P:Tick()
 local c=self.c;local plan=c.plan
 if not plan or not plan.arena or not plan.arena_wave or (plan.arena_wave()~=5 and plan.arena_wave()~=6) then return end
 local roster=plan.arena_entities and plan.arena_entities() or plan.arena_remaining and plan.arena_remaining() or c.enemies
 for _,e in ipairs(roster or {}) do
  if Snails.Snail(e) then self.snails[e]=true;self.active=true end
  if e.prefab=="slurper" and self.slurpers[e]==nil then self.slurpers[e]=false end
 end
 if not self.active then return end
 c.arena_snailpack=self
 if c.arena_wind then c.arena_wind:Stop() end
 local count,cleared=0,true;local target=self.target
 for e,confirmed in pairs(self.slurpers) do
  count=count+1
  if not confirmed and dead(e) then self.slurpers[e]=true;confirmed=true end
  if not confirmed then cleared=false end
 end
 cleared=cleared and count>=expected()
 if cleared then
  self.phase="torch";self.target=nil
  if self.weapon and c.gear.forced_weapon==self.weapon then c.gear.forced_weapon=nil;self.weapon=nil end
  local snail,nearest
  for e in pairs(self.snails) do if live(e) then
   local d=c.player:GetPosition():DistSq(e:GetPosition())
   if not snail or Snails.Burning(snail) and not Snails.Burning(e)
    or Snails.Burning(snail)==Snails.Burning(e) and d<nearest then snail,nearest=e,d end
  end end
  if not snail then c.bridge:PauseAttack();return "support" end
  local mode,picked=Snails.Tick(self.boss,snail)
  if mode then return mode,picked end
  Tools.Recover(c,"torch");return "support",snail
 end
 target=require("shadowself/control/arena_slurper").Nearest(c,self.slurpers,function(e) return self:Clear(e:GetPosition()) end,self.target)
 if self.target~=target then
  self.target=target;self.phase="bait";self.bait_seen=nil;self.standing=nil
 end
 if not target or not self:Clear(c.player:GetPosition()) or not self:Clear(target:GetPosition()) then return self:Kite(target) end
 if self.phase=="separate" then self.phase="bait" end
 self.boss:Select(target)
 if self.phase=="bait" then
  local a=target.AnimState;local atk=a and a:IsCurrentAnimation("atk");local head=a and a:IsCurrentAnimation("headslurp")
  if atk or head then self.bait_seen=true end
  if require("shadowself/control/arena_attackwindows").Committed(c,target) then self.phase="fight";self.standing=nil
  elseif self.bait_seen then return "attack",target -- 原DoDodge完成真实前摇，CanAttack仍封锁补刀。
  else
   local p=c.player:GetPosition();local q=target:GetPosition();local d=math.sqrt(p:DistSq(q))
   local combat=target.replica and target.replica.combat
   local range=(combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)+target:GetPhysicsRadius(0)-.15
   if d>range+.15 then
    self.standing=nil
    local goal=Vector3(q.x+(p.x-q.x)/d*range,0,q.z+(p.z-q.z)/d*range)
    if Nav.Safe(self:Context(),goal,target) then return self.boss:Move(goal,"蜗牛组合 · 回头靠近，骗啜食者先出手",target) end
    return self:Kite(target)
   end
   c.bridge:PauseAttack();if not self.standing then A.Stop(c.player);self.standing=true end
   return "support",target
  end
 end
 if not self:Weapon(target) then c.bridge:PauseAttack();return "support",target end
 self.boss:Release();return "attack",target
end
return P
