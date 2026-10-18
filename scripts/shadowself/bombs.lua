-- Follower bombs can be missing from FindEntities. Observe the actual owner event too.
local M={tracked=setmetatable({},{__mode="k"})}
function M.Track(e,owner)
 if not e or e.prefab~="sporebomb" then return end
 M.tracked[e]=true;e._shadowself_born=e._shadowself_born or e.spawntime or GetTime()
 if owner then e._shadowself_bomb_owner=owner end
end
function M.Bind(player)
 if player._shadowself_bomb_watch or not player.ListenForEvent then return end
 player._shadowself_bomb_watch=true
 player:ListenForEvent("startfumedebuff",function(_,bomb) M.Track(bomb,player) end)
end
function M.Near(player)
 M.Bind(player)
 for child in pairs(player.children or {}) do M.Track(child,player) end
 local result={};local p=player:GetPosition()
 for e in pairs(M.tracked) do
  if e:IsValid() then
   local parent=e._shadowself_bomb_owner or e.entity and e.entity:GetParent()
   local q=parent and parent.GetPosition and parent:GetPosition() or e:GetPosition()
   if parent==player or q:DistSq(p)<40^2 then result[#result+1]=e end
  else M.tracked[e]=nil end
 end
 return result
end
return M
