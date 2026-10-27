local W=Class(function(self) self.roster={};self.saw={} end)
local function dead(e)
 if not e:IsValid() then return false end -- 消失/暂未加载不能代表已经死亡。
 local h=e.replica and e.replica.health
 return e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()
end
function W:Update(wave,enemies,resting,entities)
 if wave==5 and self.wave~=5 then
  self.roster={};self.saw={};self.started=nil;self.finished=nil;self.active=false;self.cattle={};self.rabbits={};self.retreat=nil
 end
 self.wave=wave
 self.dogs={}
 for _,e in ipairs(entities or {}) do
  if (e.prefab=="firehound" or e.prefab=="icehound") and e:IsValid() and not dead(e) then self.dogs[#self.dogs+1]=e end
 end
 if self.finished then self.active=false;return end
 if wave==5 then
  for _,e in ipairs(enemies) do
   if e.prefab=="beefalo" then self.cattle[e]=true;self.saw.beefalo=true end
   if e.prefab=="rabbit" then self.rabbits[e]=true;self.saw.rabbit=true end
  end
  self.started=self.saw.beefalo and self.saw.rabbit
  if not self.started then self.active=false;return end
  local cattle_dead=true
  for e in pairs(self.cattle) do if not dead(e) then cattle_dead=false end end
  local rabbits_dead=true
  for e in pairs(self.rabbits) do if not dead(e) then rabbits_dead=false end end
  self.finished=resting -- 这一组合只在服务器确认结束后丢鞭，不凭局部清空提前丢。
  self.active=not resting and cattle_dead and not rabbits_dead
  return
 end
 if wave==2 then
  for _,e in ipairs(entities or {}) do
   if e.prefab=="reeds" and e:IsValid() then self.reeds=true;self.started=true end
  end
  for _,e in ipairs(enemies) do
   if e.prefab=="merm" or e.prefab=="frog" then self.roster[e]=true;self.saw[e.prefab]=true end
  end
  if self.saw.merm and self.saw.frog then self.started=true end
 end
 if not self.started then return end
 local cleared=self.saw.merm and self.saw.frog and next(self.roster)~=nil
 for e in pairs(self.roster) do if not dead(e) then cleared=false end end
 self.finished=wave~=2 or resting -- 保留到服务器确认本关结束，不能靠一次局部清空提前丢鞭
 self.active=not self.finished
end
function W:RetreatRange() return self.wave==2 and (self.reeds and 15 or 12) or 9 end
function W:CanAttack(player)
 if not self.active then self.retreat=nil;return true end
 local p=player:GetPosition();local nearest=math.huge
 for _,e in ipairs(self.dogs or {}) do if e:IsValid() and not dead(e) then nearest=math.min(nearest,p:DistSq(e:GetPosition())) end end
 if self.wave==2 and self.reeds then
  -- 芦苇可早于怪物加载；每次真正出手前检查15码，不能沿用7码触发的旧滞回。
  if nearest<=15^2 then self.retreat=true end
  if nearest>=(15.4)^2 then self.retreat=nil end
 else
  if nearest<7^2 then self.retreat=true end
  if nearest>=self:RetreatRange()^2 then self.retreat=nil end
 end
 return not self.retreat
end
function W:Clear(point,range)
 for _,e in ipairs(self.dogs or {}) do if e:IsValid() and not dead(e) and point:DistSq(e:GetPosition())<range^2 then return false end end
 return true
end
function W:CanPickup(player,item)
 local allowed
 if self.wave==2 and self.reeds then
  allowed=self:Clear(player:GetPosition(),7) -- 先安全拿鞭，再退出15码攻击圈。
 else
  allowed=self:CanAttack(player)
 end
 return self.active and allowed and (not item or self:Clear(item:GetPosition(),7))
end
function W:Evade(c)
 if self:CanAttack(c.player) then
  if self.moving then c.travel:EndDodge(c.snapshot);self.moving=nil end
  return false
 end
 local Nav=require("shadowself/control/navigation");local p=c.player:GetPosition()
 local hazards={};for _,h in ipairs(c.hazards or {}) do hazards[#hazards+1]=h end
 local retreat_range=self:RetreatRange()
 for _,dog in ipairs(self.dogs) do if dog:IsValid() and not dead(dog) then hazards[#hazards+1]={pos=dog:GetPosition(),radius=retreat_range} end end
 local context=setmetatable({hazards=hazards},{__index=c});local best,score
 for _,length in ipairs({3,6,9,12,16,18}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
  if self:Clear(q,retreat_range+.4) and Nav.Safe(context,q,c.h.ent) then
   local value=Nav.Risk(context,q,c.h.ent)*100+length
   if not score or value<score then best,score=q,value end
  end
 end end
 best=best or Nav.Escape(context,p,c.h.ent)
 if best and (p:DistSq(best)<.1^2 or not self:Clear(best,retreat_range+.4)) then best=nil end
 if not best and self.wave==2 then best=require("shadowself/control/arena_traproute").Point(c,self.dogs,retreat_range) end
 if best then
  c.bridge:PauseAttack();c.travel:BeginDodge(c.snapshot);self.moving=true
  c:Move(best,"鱼人青蛙 · 远离全部陷阱狗至"..retreat_range.."码")
  if self.evade_status~="moving" then self.evade_status="moving";print("[ShadowSelf][whip] retreat=move range="..retreat_range) end
  return true
 end
 if self.evade_status~="blocked" then self.evade_status="blocked";print("[ShadowSelf][whip] retreat=blocked reason=no_valid_trap_exit range="..retreat_range) end
 return nil
end
function W:Want(item,bag,trap)
 if not self.active or trap or not require("shadowself/control/arena_tools").Usable(item) then return false end
 for _,other in ipairs(bag) do
  if other.prefab=="whip" and require("shadowself/control/arena_tools").Usable(other) then return false end
 end
 return true
end
return W
