-- 第十一关起所有主动移动共用手杖切换；请求不阻塞紧急移动，无独立循环。
local M={}
function M.Tick(player,wave)
 if not wave or wave<11 then return end
 local A=require("shadowself/control/actions");local cane
 for _,item in ipairs(A.Items(player)) do
  if item.prefab=="cane" and require("shadowself/control/arena_tools").Usable(item) then cane=item;break end
 end
 if not cane or player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==cane then return end
 local pc=player.components.playercontroller
 if not pc:IsBusy() and GetTime()>=(player._shadowself_late_cane_after or 0) then
  if A.Self(player,cane,ACTIONS.EQUIP) then player._shadowself_late_cane_after=GetTime()+.4 end
 end
end
return M
