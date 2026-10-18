-- 同类支持物品按实体固定选择，库存/手持槽重新排列不能改变已选目标。
local M={}
function M.Pick(cache,name,items,hand,pending)
 local candidates={};local first
 for _,item in ipairs(items) do
  if item.prefab==name and item:IsValid() and not item:HasTag("broken") then
   candidates[item]=true
   if not first or (item.GUID or math.huge)<(first.GUID or math.huge) then first=item end
  end
 end
 local chosen=cache[name]
 if not candidates[chosen] then
  chosen=pending and candidates[pending.item] and pending.item or candidates[hand] and hand or first
 end
 cache[name]=chosen;return chosen
end
return M
