local Inv=require("shadowself/control/arena_inventory")
local H={}
local function good(e) return e and e:IsValid() and e.prefab=="wathgrithr_improvedhat" and not e:HasTag("broken") and Inv.Condition(e)>0 end
function H.Tick(s)
 local A=require("shadowself/control/actions")
 local arena=s.arena
 if arena.wave~=11 or s.finish or s.reward then arena.collect_stage11_hats=nil;return false end
 local p=s.player;local inv=p.replica.inventory;local bag=A.Items(p);local owned={};local best
 for _,e in ipairs(bag) do owned[e]=true;if good(e) and (not best or Inv.Condition(e)>Inv.Condition(best)) then best=e end end
 local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 local ground={}
 for _,e in ipairs(arena.items or {}) do if good(e) and not owned[e] and GetTime()>=(arena.ignored[e.GUID] or 0) then ground[#ground+1]=e end end
 table.sort(ground,function(a,b) return Inv.Condition(a)>Inv.Condition(b) end)
 if s.route=="default" then
  arena.collect_stage11_hats=nil
  if good(head) then best=head end
  if best and head~=best then
   arena:StopCombat()
   if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_hat_equip or 0) then A.Self(p,best,ACTIONS.EQUIP);s.next_hat_equip=GetTime()+.5 end
   return true
  end
  if best then
   for _,e in ipairs(ground) do arena.ignored[e.GUID]=math.huge end
   for _,e in ipairs(bag) do if e.prefab=="wathgrithr_improvedhat" and e~=head then
    arena:StopCombat();arena.ignored[e.GUID]=math.huge
    if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_hat_drop or 0) then inv:DropItemFromInvTile(e,false);s.next_hat_drop=GetTime()+.5 end
    arena:Say("普通线 · 仅保留已穿戴的女武神头盔，丢弃备用");return true
   end end
   return false
  end
  -- 普通线没有已穿戴头盔时只拿一顶，不先收集整包再丢弃。
  if ground[1] then return arena:Loot({ground[1]}) end
  return false
 end
 arena.collect_stage11_hats=s
 if #ground>0 or arena.pending_item and arena.pending_item.prefab=="wathgrithr_improvedhat" then
  arena:Say("第十一关 · 收集地上全部可用女武神头盔作为备用")
  return arena:Loot(ground) or false
 end
 return false
end
return H
