-- 准备动作继续使用Arena tick；危险时移动，不站着等待拾取/进食。
local M={}
function M.Armor(c)
 if c.healing and c.healing.pending then return false end
 local A=require("shadowself/control/actions");local I=require("shadowself/control/arena_inventory");local P=require("shadowself/control/arena_policy")
 local p=c.player;local inv=p.replica and p.replica.inventory
 if not inv or not inv.GetEquippedItem then return false end
 local wave=c.plan and c.plan.arena_wave and c.plan.arena_wave() or 5
 for _,slot in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
  local current=inv:GetEquippedItem(slot)
  if not current or I.Condition(current)<=.1 then
   local best,score
   for _,item in ipairs(A.Items(p)) do
    local eq=item.replica and item.replica.equippable
    if eq and eq:EquipSlot()==slot and item:IsValid() and not item:HasTag("broken") and I.Condition(item)>0 and P.AllowArmor(item,wave,c.enemies) then
     local value=I.Protection(item)*math.min(1,I.Condition(item)*5)
     if value>0 and (not score or value>score) then best,score=item,value end
    end
   end
   if best and best~=current and not p.components.playercontroller:IsBusy() and not p:HasTag("attack") then
    c.bridge:PauseAttack()
    if GetTime()>=(c.next_prepare_armor or 0) then A.Self(p,best,ACTIONS.EQUIP);c.next_prepare_armor=GetTime()+.4 end
    return true
   end
  end
 end
 return false
end
function M.Head(s)
 if s.arena.wave~=11 or s.finish or s.buffs and s.buffs.pending or s.arena.healing and s.arena.healing.pending then return false end
 local A=require("shadowself/control/actions");local I=require("shadowself/control/arena_inventory")
 local p=s.player;local inv=p.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
 if head and I.Protection(head)>0 and I.Condition(head)>.1 then return false end
 local best,score
 for _,item in ipairs(A.Items(p)) do
  local eq=item.replica and item.replica.equippable
  if eq and eq:EquipSlot()==EQUIPSLOTS.HEAD and item:IsValid() and not item:HasTag("broken") and I.Condition(item)>0 then
   local value=I.Protection(item)*math.min(1,I.Condition(item)*5)
   if value>0 and (not score or value>score) then best,score=item,value end
  end
 end
 if not best or best==head or p.components.playercontroller:IsBusy() or p:HasTag("attack") then return false end
 s.arena:StopCombat()
 if GetTime()>=(s.next_emergency_hat or 0) then A.Self(p,best,ACTIONS.EQUIP);s.next_emergency_hat=GetTime()+.4 end
 return true
end
function M.Context(arena)
 local c=arena.bridge and arena.bridge.coordinator
 return {player=arena.player,healing=arena.healing,enemies=arena:NearbyEnemies(60),hazards=arena.fire_zones or {},observed=c and c.observed or {},
  bridge={PauseAttack=function() arena:StopCombat() end},
  plan={arena=true,arena_wave=function() return arena.wave end,arena_center=function() return arena.encounters:FindCenter() end},
  actions=arena.rest_actions or {SafePoint=function(_,q) return TheWorld.Map:IsPassableAtPoint(q.x,0,q.z) and not TheWorld.Map:IsOceanAtPoint(q.x,0,q.z) end}}
end
function M.Escape(arena,c,label)
 local Nav=require("shadowself/control/navigation");local R=require("shadowself/control/arena_late_runtime")
 local hazards={};for _,z in ipairs(c.hazards or {}) do hazards[#hazards+1]=z end
 for _,e in ipairs(c.enemies or {}) do if R.Live(e) then hazards[#hazards+1]={pos=e:GetPosition(),radius=Nav.Radius(e)+3,source=e} end end
 local route=setmetatable({hazards=hazards},{__index=c})
 arena.preparation_route=arena.preparation_route or {}
 local p=arena.player:GetPosition();local goal=require("shadowself/control/arena_perimeter")(route,arena.preparation_route,0) or p
 local q=Nav.Select(route,goal)
 if p:DistSq(q)<.1^2 then q=Nav.Escape(route,goal) end
 if q and p:DistSq(q)>.1^2 then arena.encounters:Move(q,label);return true end
 arena:Say(label.." · 重查可通行出口");return false
end
function M.FoodMove(s,label)
 local h=s.arena.healing;local c=s.context;local p=s.player:GetPosition();local best,score
 local window=s.food_window
 if window and h then for _,length in ipairs({3,6,9,12}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
  if require("shadowself/control/arena_center").Point(c,q) and h:Safe(c,q,window) then
   if not score or length<score then best,score=q,length end
  end
 end end end
 if best then
  local q=require("shadowself/control/navigation").Select(c,best)
  if p:DistSq(q)>.1^2 then s.arena.encounters:Move(q,label);return "hold" end
 end
 M.Escape(s.arena,c,label);return "hold"
end
return M
