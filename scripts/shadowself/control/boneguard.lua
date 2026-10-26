-- 角斗场骨甲防护：耐久消耗或本人护盾重新起算；未知CD不授权扛伤。
local B={}
function B.Attack(c,target)
 local stage=c.plan and c.plan.arena_stage11
 if stage and require("shadowself/control/arena_scrappig").Finishing(stage) then return false end
 if not B.Ready(c) then return false end
 if c.secondary then c.secondary.pending=nil end
 if c.bridge then c.bridge.chasing=nil end
 if c.travel then
  c.travel.chasing=nil;c.travel:EndDodge(c.snapshot);c.travel.role="attack"
 end
 c.blocked=false;c.special_active=false;c.queen_active=false
 require("shadowself/control/arena_attackwindows").Guarded(c,target)
 if c.gear then c.gear:Swap("attack",c.snapshot) end
 return true
end
-- 保留原生招式的方向、距离和命中末帧，只把已知前摇起始提前网络/收刀余量。
function B.Early(c,e,base)
 if base or not c or not e or not c.plan or not c.plan.arena then return base end
 local wave=c.plan.arena_wave and c.plan.arena_wave()
 if not wave or wave<10 or wave>15 or B.Ready(c) then return base end
 local inv=c.player.replica.inventory;local body=inv:GetEquippedItem(EQUIPSLOTS.BODY)
 if not body or body.prefab~="armorskeleton" then return base end
 local n=require("shadowself/native").Get();local entries=n.HitAndRun and n.HitAndRun.targetanimtable[e.prefab]
 if not entries then return base end
 local util=n.ENT_util;local anim=util:GetAnimation(e);local frame=e.AnimState:GetCurrentAnimationFrame() or 0
 local lead=require("shadowself/control/nettiming").Frames(c)+6
 for _,data in pairs(entries) do if not data.noused and util:FnOrNum(data.atkanim,e)==anim then
  local first=util:FnOrNum(data.atk_start_frame,e) or 0;local last=util:FnOrNum(data.atk_stop_frame,e) or 1000
  if data.atk_frame_calculate then first=math.min(util:FnOrNum(data.atk_frame_calculate,e,data.atk_start_frame,last,nil,data),last) end
  if frame>=math.max(0,first-lead) and frame<=last and (not data.checkatktag or e:HasTag("attack") or e.prefab=="daywalker" and anim=="run_pre")
   and not (data.breakdodgefn and data.breakdodgefn(e)) then return data end
 end end
 return base
end
function B.Ready(c)
 if not c or not c.plan or not c.plan.arena or not c.player then return false end
 local p=c.player;local inv=p.replica and p.replica.inventory
 local body=inv and inv:GetEquippedItem(EQUIPSLOTS.BODY)
 if not body or body.prefab~="armorskeleton" or not body:IsValid() or body:HasTag("broken") then return false end
 local f=body.components and body.components.fueled
 local ii=body.replica and body.replica.inventoryitem;local net=ii and ii.classified and ii.classified.percentused
 local percent=f and f.GetPercent and f:GetPercent() or net and net:value()~=255 and net:value()/100
 if not percent or percent<=0 then return false end
 local now=GetTime();local s=p._shadowself_bone_guard
 if not s then s={bones=setmetatable({},{__mode="k"}),shields=setmetatable({},{__mode="k"})};p._shadowself_bone_guard=s end
 local record=s.bones[body]
 if not record then record={percent=percent,ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1};s.bones[body]=record end
 if percent<record.percent-.001 then record.ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1 end
 record.percent=percent
 if now>=(s.next_scan or 0) then
 s.next_scan=now+.05
 local pos=p:GetPosition()
 for _,fx in ipairs(TheSim:FindEntities(pos.x,0,pos.z,3,{"FX"})) do
  local parent=fx.entity and fx.entity.GetParent and fx.entity:GetParent()
  if (fx.prefab or ""):match("^shadow_shield%d$") and (parent==p or p.entity and parent==p.entity) and not s.shields[fx] then
   s.shields[fx]=true;record.ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1
  end
 end
 end
 local cd=body.components and body.components.cooldown
 if cd and cd.GetTimeToCharged then return cd:GetTimeToCharged()<=0 end
 if cd and cd.IsCharged then return cd:IsCharged() end
 return now>=record.ready
end
return B
