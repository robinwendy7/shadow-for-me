local P={}
function P.Rook(e) return e and (e.prefab=="rook" or e.prefab=="rook_nightmare") end
function P.Creature(e)
 if not e or not e:IsValid() or e:HasTag("dead") or e:HasTag("isdead") or e:HasTag("INLIMBO") then return false end
 local n=e.prefab or ""
 return not (n:find("sandspike_",1,true)==1 or n=="sandblock" or n=="crabking_icewall" or e:HasTag("structure") or e:HasTag("wall") or e:HasTag("FX") or e:HasTag("DECOR"))
end
function P.Boss(e) return e and e:HasTag("epic") or false end
-- 战车仍然允许参与威胁扫描，只在攻击目标的选择上排最后。
function P.Other(bridge,rook)
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
