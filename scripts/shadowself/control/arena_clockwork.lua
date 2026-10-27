-- 第三关主教：第一次实际瞄准至发射结束期间躲避，随后锁定持续攻击至死亡。
local Nav=require("shadowself/control/navigation")
local R=Class(function(self,target) self.target=target;self.phase="attack" end)
function R:Live()
 local e=self.target;local h=e and e.replica and e.replica.health
 return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
function R:AttackState()
 local a=self.target.AnimState
 if a then
  for _,name in ipairs({"atk2_pre","atk2_loop","atk2_pst","atk"}) do
   if a:IsCurrentAnimation(name) then return name end
  end
 end
end
function R:Observe(c)
 if not self:Live() then self.phase="done";self.evading=nil;return end
 local state=self:AttackState()
 if self.evading and not state then self.committed=true end
 if self.committed then self.phase="attack";self.evading=nil;self.state=nil;return end
 self.phase=state and "evade" or "attack";self.evading=state~=nil;self.state=state
end
function R:Block(c)
 self:Observe(c)
 return self.phase=="evade"
end
function R:AfterDodge(c)
 self:Observe(c)
 if self.phase~="attack" or not self:Live() then return end
 -- 发射结束即交还武器与本目标；不能沿用手杖追击/其他怪留下的pending继续摆动。
 if c.secondary then c.secondary.pending=nil end
 if c.bridge then c.bridge.priority_target=self.target;c.bridge.chasing=nil end
 if c.h then c.h.ent=self.target end
 if c.travel then c.travel.chasing=nil;if c.travel.EndDodge then c.travel:EndDodge(c.snapshot) end end
 c.blocked=false;c.special_active=false
 return self.target
end
function R:VolleyDone(c) return not self:Block(c) end
function R:Point(c)
 local p=c.player:GetPosition();local q=self.target:GetPosition()
 local theta=math.atan2(p.z-q.z,p.x-q.x);local radius=math.max(2.2,math.sqrt(p:DistSq(q)))
 local angle=theta+.5
 return Nav.Select(c,Vector3(q.x+math.cos(angle)*radius,0,q.z+math.sin(angle)*radius),self.target)
end
function R:Dodge(c,target,base)
 self:Observe(c)
 if self.phase=="done" then return base end
 if target~=self.target or self.phase~="evade" then return nil end
 self.dodge_started=true
 -- 沿用按实际瞄准标记计算的圆周路线；不再用固定落点或帧数结束躲避。
 local value={};for k,v in pairs(base or {}) do value[k]=v end
 value.atkanim=self.state;value.noattack=true;value.exclusive=true;value.update=true
 value.point=value.point or "player";value.dist=value.dist or 3
 value.fn=base and base.fn or function() return self:Point(c) end
 value.breakdodgefn=function() return self:VolleyDone(c) end
 return value
end
return R
