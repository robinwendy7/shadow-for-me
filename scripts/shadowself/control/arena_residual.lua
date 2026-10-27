-- 清怪后的残留机制由Arena原tick继续扫描，不能随攻击协程停止。
local A=require("shadowself/control/actions")
local F=require("shadowself/control/arena_fire")
local M={}
function M.Tick(arena)
 if #(arena.enemies or {})>0 then return false end
 local c=arena.residual
 if not c then
  c={player=arena.player,enemies={},hazards={},plan={arena=true,arena_wave=function() return arena.wave end},Speed=function() return 6 end}
  c.bosses=require("shadowself/control/bosses")(c)
  c.mechanisms=require("shadowself/control/mechanisms")(c);arena.residual=c
 end
 local now=GetTime()
 if now>=(c.next_scan or 0) then
  c.next_scan=now+.1;c.mechanisms:Scan();c.zones={}
  for _,z in ipairs(c.mechanisms.zones) do c.zones[#c.zones+1]=z end
  local p=arena.player:GetPosition()
  for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,16,nil,{"INLIMBO"})) do
   if e:IsValid() and e.prefab=="spore_moon" and not (e.AnimState:IsCurrentAnimation("explode") and e.AnimState:GetCurrentAnimationFrame()>=4) then
    c.zones[#c.zones+1]={pos=e:GetPosition(),radius=(TUNING.MOONSPORE_ATTACK_RANGE or 3)+arena.player:GetPhysicsRadius(0)+.5,source=e}
   end
  end
 end
 local zones={};local max=7
 for _,z in ipairs(c.zones or {}) do if not z.source or z.source:IsValid() then zones[#zones+1]=z;max=math.max(max,z.radius*2+1) end end
 local q=F.Escape(arena.player,zones,{3,5,7,max})
 if not q then return false end
 arena:StopCombat();arena.pending_item=nil;arena.pick_deadline=nil
 if arena.healing and arena.healing.pending then arena.healing:Interrupt(c) end
 if now>=(c.next_move or 0) then
  require("shadowself/control/arena_late_travel").Tick(arena.player,arena.wave)
  A.Move(arena.player,q);c.next_move=now+.15
 end
 arena:Say("清怪后 · 先避开残留孢子、火焰和场地危险，再补给拾取")
 return true
end
return M
