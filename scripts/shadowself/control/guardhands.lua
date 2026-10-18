-- 冻蜂与躲避共用 Gear 的唯一在途换装队列，禁止另发直接 EQUIP。
local H={}
function H.Set(q,item,phase)
 local gear=q.c.gear;local current=gear.support_hand
 if not current or current.owner~=q or current.item~=item or current.phase~=phase then
  gear.support_hand={owner=q,item=item,phase=phase}
  require("shadowself/control/queendebug").Event(q.c,"support_hand",{phase=phase,item=require("shadowself/control/queendebug").Entity(item)})
  -- 旧请求仍等实际手持确认；不因 native move/attack 事件来回取消它。
  if not gear.pending then gear.next_request=GetTime() end
 end
 return gear:Swap(phase=="escape" and "move" or "attack",q.c.snapshot)
end
function H.Release(q)
 local gear=q.c.gear
 if gear.support_hand and gear.support_hand.owner==q then gear.support_hand=nil end
 q.guard_escape=nil;q.casting_guard=nil
end
return H
