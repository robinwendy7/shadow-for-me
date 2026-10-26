local P={}
function P.Rook(e) return e and (e.prefab=="rook" or e.prefab=="rook_nightmare") end
function P.Creature(e)
 if not e or not e:IsValid() or e:HasTag("dead") or e:HasTag("isdead") or e:HasTag("INLIMBO") then return false end
 local n=e.prefab or ""
 return not (n:find("sandspike_",1,true)==1 or n=="sandblock" or n=="crabking_icewall" or e:HasTag("structure") or e:HasTag("wall") or e:HasTag("FX") or e:HasTag("DECOR"))
end
function P.Boss(e) return e and e:HasTag("epic") or false end
local birdranks={smallbird=1,teenbird=2,tallbird=3}
-- 关卡中的幼鸟仍带原版companion标记；睡眠清掉仇恨后会被IsAlly误过滤。
-- 只认第二关当前名单，不覆盖玩家实际领养的鸟或其它友方单位。
function P.ArenaBird(bridge,e)
 local plan=bridge.plan or bridge.coordinator and bridge.coordinator.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=2
  or not plan.arena_remaining or not e or not birdranks[e.prefab] or not P.Creature(e)
  or not e.replica or not e.replica.combat then return false end
 local follower=e.replica and e.replica.follower
 if follower and follower.GetLeader and follower:GetLeader() then return false end
 if plan.arena_contains and not plan.arena_contains(e) then return false end
 for _,member in ipairs(plan.arena_remaining()) do if member==e then return true end end
 return false
end
function P.Bird(bridge)
 local plan=bridge.plan or bridge.coordinator and bridge.coordinator.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=2 or not plan.arena_remaining then return end
 local ranks=birdranks;local best,rank
 for _,e in ipairs(plan.arena_remaining()) do
  local r=ranks[e.prefab]
  if r and P.Creature(e) and bridge.allowed(e) and (not rank or r<rank) then best,rank=e,r end
 end
 return best
end
function P.KnightOnly(bridge,target)
 local plan=bridge.plan or bridge.coordinator and bridge.coordinator.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=3 then return false end
 if not target or (target.prefab~="knight" and target.prefab~="knight_nightmare") then return false end
 local roster=plan.arena_remaining and plan.arena_remaining() or {}
 local found=false
 for _,e in ipairs(roster) do if P.Creature(e) and bridge.allowed(e) then
  if e.prefab~="knight" and e.prefab~="knight_nightmare" then return false end
  if e==target then found=true end
 end end
 return found
end
-- 第三关主教已死的残局例外：骑士仍参与危险扫描，输出只追战车。
function P.ClockworkRook(bridge)
 local plan=bridge.plan or bridge.coordinator and bridge.coordinator.plan
 if not plan or not plan.arena or not plan.arena_wave or plan.arena_wave()~=3 then return end
 local roster={}
 if plan.arena_remaining then roster=plan.arena_remaining()
 else for e in pairs(bridge.h.selected_ents or {}) do roster[#roster+1]=e end end
 local rook
 for _,e in ipairs(roster) do
  if P.Creature(e) and bridge.allowed(e) then
   if P.Rook(e) then rook=e
   elseif e.prefab~="knight" and e.prefab~="knight_nightmare" then return end
  end
 end
 return rook
end
-- 战车仍然允许参与威胁扫描，只在攻击目标的选择上排最后。
function P.Other(bridge,rook)
 if P.ClockworkRook(bridge)==rook then return end
 local p=bridge.player:GetPosition();local best,distance
 for e in pairs(bridge.h.selected_ents or {}) do
  if e~=rook and not P.Rook(e) and P.Creature(e) and bridge.allowed(e) then
   local d=p:DistSq(e:GetPosition())
   if not distance or d<distance then best,distance=e,d end
  end
 end
 return best
end
function P.Nearest(bridge)
 local priority=P.ClockworkRook(bridge);if priority then return priority end
 local p=bridge.player:GetPosition();local best,distance;local rook,rookdist
 for e in pairs(bridge.h.selected_ents or {}) do
  local combat=bridge.player.replica and bridge.player.replica.combat
  if P.Creature(e) and bridge.allowed(e) and (not combat or not combat.CanTarget or combat:CanTarget(e)) then
   local d=p:DistSq(e:GetPosition())
   if P.Rook(e) then if not rookdist or d<rookdist then rook,rookdist=e,d end
   elseif not distance or d<distance then best,distance=e,d end
  end
 end
 return best or rook
end
return P
