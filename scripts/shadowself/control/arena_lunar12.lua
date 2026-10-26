-- 实测0.13.63天体12：普通帽无位面防御；原生表将lunar_grazer标为makeNoUsed。
local R=require("shadowself/control/arena_late_runtime")
local Nav=require("shadowself/control/navigation")
local L={}
function L.Prepare(arena)
 if arena.wave~=12 or (arena.detected_route or arena.route)~="lunar" then return false end
 arena.lunar12=arena.lunar12 or {arena=arena,player=arena.player}
 local s=arena.lunar12
 if not R.Equip(s,"voidclothhat",EQUIPSLOTS.HEAD) then return true end
 if not R.Equip(s,"armor_voidcloth",EQUIPSLOTS.BODY) then return true end
 return false
end
function L.Dodge(c,e,base)
 if not c.plan or not (c.plan.arena_lunar12 or c.plan.arena and c.plan.arena_route=="lunar" and c.plan.arena_wave and c.plan.arena_wave()==13)
  or not e or e.prefab~="lunar_grazer" then return base end
 local a=e.AnimState
 if not a or not a:IsCurrentAnimation("devour") or a:GetCurrentAnimationFrame()>=32 then return base end
 local radius=(TUNING.LUNAR_GRAZER_HIT_RANGE or 1.7)+c.player:GetPhysicsRadius(0)+.5
 return {atkanim="devour",point="target",dist=radius,update=true,noattack=true,exclusive=true,
  fn=function()
   local p=c.player:GetPosition();local q=e:GetPosition();local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
   if d>=radius then return p end
   if d<.01 then dx,dz,d=1,0,1 end
   return Nav.Select(c,Vector3(q.x+dx/d*radius,0,q.z+dz/d*radius),e)
  end,
  breakdodgefn=function() return not e:IsValid() or not a:IsCurrentAnimation("devour") or a:GetCurrentAnimationFrame()>=32 end}
end
return L
