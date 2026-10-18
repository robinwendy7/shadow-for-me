-- 只描述可验证的输出状态，不推算通用进出场预算。
local O={}
local function anim(e,n) return e and e.AnimState and e.AnimState:IsCurrentAnimation(n) end
function O.DragonDown(e)
 return e and e.prefab=="dragonfly" and (anim(e,"hit_large") or anim(e,"hit_ground") or anim(e,"sleep_loop") or e:HasTag("grounded") or e.sg and e.sg.HasStateTag and e.sg:HasStateTag("grounded"))
end
function O.Planar(c)
 local Damage=require("shadowself/control/weapon_damage");local selected,best=nil,0
 local inv=c.player.replica and c.player.replica.inventory;local held=inv and inv.GetEquippedItem and inv:GetEquippedItem(EQUIPSLOTS.HANDS)
 for _,item in ipairs(require("shadowself/control/actions").Items(c.player)) do
  local value=Damage.Planar(item)
  if value>best or value>0 and value==best and item==held then selected,best=item,value end
 end
 return selected
end
function O.Bear(c,e)
 if not e or e.prefab~="mutatedbearger" or not e.AnimState then return false end
 if anim(e,"stagger_pre") or anim(e,"stagger_loop") or anim(e,"stagger_hit") or anim(e,"stagger_pst") then return true end
 local f=e.AnimState:GetCurrentAnimationFrame() or 0
 -- butt_pst第20~40帧受位面伤害进入butt_face_hit；提前接近，避免错过窗口。
 if anim(e,"butt_pst") and f>=4 and f<=40 or anim(e,"butt_face_hit") and f<28 then
  local weapon=O.Planar(c);return weapon~=nil,weapon
 end
 return false
end
return O
