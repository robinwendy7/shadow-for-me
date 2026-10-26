-- 被动证据整理；时间接近和附近怪物都不能升级为已确认伤害来源。
local M={}
function M.Cause(value)
 return type(value)=="string" and value:match("%S") and value or nil
end
function M.Loss(e,events)
 local s=e.snapshot or {};local cause=M.Cause(e.cause)
 local out={confidence=cause and "reported" or "unknown",source=cause and "healthdelta_cause" or "unavailable",
  reported_cause=cause,attacker_candidates={},environment_clues={},nearby_attacking={},nearby_hazards={}}
 local seen={};local notifications=0
 for _,a in ipairs(events or {}) do
  if a.event=="attacked" and math.abs((a.time or 0)-(e.time or 0))<=.35 then
   local x,y=a.context or {},e.context or {}
   if x.instance==y.instance and x.generation==y.generation and x.wave==y.wave then
    notifications=notifications+1
    if a.attacker and not seen[a.attacker.guid or a.attacker.prefab] then
     seen[a.attacker.guid or a.attacker.prefab]=true
     out.attacker_candidates[#out.attacker_candidates+1]={entity=a.attacker,offset_seconds=a.time-e.time,evidence="attacked_event_attacker"}
    end
   end
  end
 end
 out.nearby_notifications=notifications
 if not cause and #out.attacker_candidates>0 then out.confidence="correlated";out.source="near_time_attacked_event" end
 if s.hunger_percent==0 then out.environment_clues[#out.environment_clues+1]="饥饿值为零，可能有饥饿掉血" end
 if s.burning then out.environment_clues[#out.environment_clues+1]="客户端显示正在受火焰伤害" end
 if s.frozen then out.environment_clues[#out.environment_clues+1]="人物处于冻结状态" end
 if e.overtime then out.environment_clues[#out.environment_clues+1]="healthdelta标记为持续变化，不等于已确认饥饿或火焰" end
 for _,a in ipairs(s.nearby or {}) do
  local animation=a.animation or ""
  local name=a.prefab or ""
  if #out.nearby_hazards<3 and ((name:find("sandspike_",1,true)==1 and not animation:find("pst",1,true))
   or name=="spore_moon" and (animation=="rumble" or animation=="explode") or name=="mortarball") then
   out.nearby_hazards[#out.nearby_hazards+1]=a
  end
  if not a.dead and (animation:find("atk",1,true) or animation:find("attack",1,true)) then
   if #out.nearby_attacking<3 then out.nearby_attacking[#out.nearby_attacking+1]=a end
  end
 end
 return out
end
function M.Description(a)
 if a.reported_cause then return "同步原因="..a.reported_cause end
 local names={}
 for _,v in ipairs(a.attacker_candidates) do names[#names+1]=v.entity.prefab or "unknown" end
 if #names>0 then return "时间关联攻击者="..table.concat(names,"、").."（非逐次伤害确认）" end
 return a.nearby_notifications>0 and "伴随受击通知，攻击者未同步" or "来源未知，未匹配到受击通知"
end
function M.Report(report)
 local out={facts={},clues={},unknowns={},losses={},equipment_transitions={}}
 local events=report.recent_events or {};local frames={}
 local death=report.death or {};local at=death.at or 0
 local count,total,burst=0,0,0;local hunger_min;local hands,changes=nil,0
 for _,s in ipairs(report.recent_samples or {}) do frames[#frames+1]=s end
 -- 事件快照可能比0.25秒采样更新；排除死亡后自动卸装造成的假“护甲耗尽”。
 for _,e in ipairs(events) do
  local s=e.snapshot
  if s and s.hp and s.hp>0 and not s.ghost and not s.corpse and e.time<=at then
   local f={};for k,v in pairs(s) do f[k]=v end;f.time=e.time;frames[#frames+1]=f
  end
  if e.event=="hp_loss" and e.time<=at then
   local a=M.Loss(e,events)
   out.losses[#out.losses+1]={time=e.time,hp_before=e.hp_before,hp_after=e.hp_after,net_loss=e.observed_loss,attribution=a}
   count=count+1;total=total+(e.observed_loss or 0)
   if e.time>=at-6 then burst=burst+(e.observed_loss or 0) end
  end
 end
 table.sort(frames,function(a,b) return (a.time or 0)<(b.time or 0) end)
 local previous={}
 for _,s in ipairs(frames) do
  if s.hp and s.hp>0 and not s.ghost and not s.corpse then
   if type(s.hunger_percent)=="number" then hunger_min=math.min(hunger_min or 1,s.hunger_percent) end
   local hand=s.gear and s.gear.HANDS;local key=hand and (hand.guid or hand.prefab)
   if hands and key and hands~=key then changes=changes+1 end
   hands=key or hands
   for _,slot in ipairs({"HEAD","BODY"}) do
    local gear=s.gear and s.gear[slot];local old=previous[slot]
    if gear and old and old.gear.prefab~="empty" and gear.prefab=="empty" then
     out.equipment_transitions[#out.equipment_transitions+1]={time=s.time,slot=slot,previous=old.gear,hp=s.hp}
     out.facts[#out.facts+1]=string.format("死亡前%.2f秒，%s由%s变为空槽；上次耐久%s",math.max(0,at-(s.time or at)),slot,old.gear.prefab,
      type(old.gear.percent)=="number" and string.format("%.0f%%",old.gear.percent*100) or "未知")
    end
    if gear then previous[slot]={gear=gear,time=s.time} end
   end
  end
 end
 if #out.equipment_transitions>0 then out.clues[#out.clues+1]="空槽可能来自耐久耗尽或卸装，缺少物品移除证据时不确定为破损" end
 out.facts[#out.facts+1]=string.format("死亡前30秒记录%d次净掉血，共%.2f；最后6秒净掉血%.2f，不能当成独立攻击次数或单次伤害",count,total,burst)
 out.facts[#out.facts+1]="存活快照中的手持物切换"..changes.."次；次数本身不能证明动作被覆盖"
 if hunger_min then
  out.facts[#out.facts+1]=string.format("存活快照最低饥饿值%.0f%%",hunger_min*100)
  if hunger_min==0 then out.clues[#out.clues+1]="存在饥饿为零的窗口，需结合持续掉血标记核对，不能把全部损失归因于饥饿" end
 end
 local cause=M.Cause(report.death_cause)
 if cause then out.facts[#out.facts+1]="死亡原因同步字段："..cause
 else out.unknowns[#out.unknowns+1]="服务器未提供非空死亡原因；死亡信号health_zero只表示生命归零" end
 out.unknowns[#out.unknowns+1]="附近怪物、攻击动画和距离仅是线索；没有明确事件攻击者时，不指定伤害来源"
 return out
end
return M
