-- Off-target motion is a swept lane, not the attacker's small current melee circle.
local Nav=require("shadowself/control/navigation")
local M={}
local function anim(e,n) return e.AnimState and e.AnimState:IsCurrentAnimation(n) end
function M.Lane(c,e)
 local n=e.prefab;local speed;local width
 if (n=="rook" or n=="rook_nightmare") and (anim(e,"atk") or anim(e,"paw_loop") or anim(e,"atk_pre") and e.AnimState:GetCurrentAnimationFrame()>=math.max(0,15-require("shadowself/control/nettiming").Frames(c))) then speed=16
 elseif n=="rabbitking_aggressive" and (anim(e,"dropkick_loop") or anim(e,"dropkick_pre") and e.AnimState:GetCurrentAnimationFrame()>=math.max(0,6-require("shadowself/control/nettiming").Frames(c))) then speed=12
 elseif (n=="eyeofterror" or n=="twinofterror1" or n=="twinofterror2") and (anim(e,"charge_loop") or anim(e,"charge_pre") and e.AnimState:GetCurrentAnimationFrame()>=math.max(0,25-require("shadowself/control/nettiming").Frames(c))) then speed=16
 elseif n=="daywalker" and (anim(e,"atk3") or anim(e,"run_pre")) then speed=11;width=3+c.player:GetPhysicsRadius(0)+.6
 elseif n=="shadowthrall_hands" and (anim(e,"run_pre") or anim(e,"run_loop")) then speed=12;width=1.8+c.player:GetPhysicsRadius(0)+.5
 elseif n=="sharkboi" and (anim(e,"torpedo_loop") or anim(e,"torpedo_jump")) then speed=16;width=3+c.player:GetPhysicsRadius(0)+.8
 end
 if not speed then return end
 local r=e.Transform:GetRotation()*math.pi/180
 return {e=e,pos=e:GetPosition(),x=math.cos(r),z=-math.sin(r),length=speed*(.65+(c.Latency and c:Latency() or .1)),width=width or e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+(n=="rabbitking_aggressive" and 1.8 or .8)}
end
function M.Risk(l,p)
 local dx,dz=p.x-l.pos.x,p.z-l.pos.z
 local along=dx*l.x+dz*l.z;local side=math.abs(-dx*l.z+dz*l.x)
 if along>=-l.width and along<=l.length and side<l.width then return (l.width-side)+1 end
 return 0
end
-- A尚未出手时，也检查走到攻击边缘的短路径，不能迈进侧方冲撞通道。
function M.ApproachBlocked(c,entities,target)
 if not target then return false end
 local lanes={}
 for _,e in ipairs(entities or {}) do if e~=target and e:IsValid() then
  local lane=M.Lane(c,e);if lane then lanes[#lanes+1]=lane end
 end end
 if #lanes==0 then return false end
 local p=c.player:GetPosition();local q=target:GetPosition();local d=math.max(.01,math.sqrt(p:DistSq(q)))
 local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or 2)+target:GetPhysicsRadius(0)
 local length=math.max(0,d-reach)
 for _,lane in ipairs(lanes) do for i=0,4 do
  local step=length*i/4;local point=Vector3(p.x+(q.x-p.x)*step/d,0,p.z+(q.z-p.z)*step/d)
  if M.Risk(lane,point)>0 then return true end
 end end
 return false
end
function M.Point(c,entities)
 local lanes={};local danger=false;local p=c.player:GetPosition()
 for _,e in ipairs(entities or {}) do if e~=c.h.ent and e:IsValid() then
  local lane=M.Lane(c,e);if lane then lanes[#lanes+1]=lane;if M.Risk(lane,p)>0 then danger=true end end
 end end
 if not danger then return end
 local best,score
 for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*4,0,p.z+math.sin(a)*4)
  local risk=0;for _,l in ipairs(lanes) do risk=risk+M.Risk(l,q) end
  if risk==0 and Nav.Safe(c,q) then
   local value=Nav.Risk(c,q)*100+p:DistSq(q)+(8-Nav.Clearance(c,q))*10
   if not score or value<score then best,score=q,value end
  end
 end
 return best
end
return M
