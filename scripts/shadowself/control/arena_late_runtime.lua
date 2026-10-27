-- 第11/12关的同步确认工具；无后台线程，不读取health_replica的100血占位值。
local A=require("shadowself/control/actions")
local Inv=require("shadowself/control/arena_inventory")
local R={}
function R.Dead(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()) or false
end
function R.Live(e) return e and e:IsValid() and not R.Dead(e) and not e:HasTag("INLIMBO") end
function R.Item(p,name)
 for _,e in ipairs(A.Items(p)) do if e.prefab==name and e:IsValid() and not e:HasTag("broken") and Inv.Condition(e)>0 then return e end end
end
function R.Equip(s,name,slot)
 local p=s.player;local inv=p.replica.inventory;local e=R.Item(p,name)
 if not e then
  local arena=s.arena;local wave,id,generation=arena.wave,arena.instance,arena.generation
  for _,item in ipairs(arena.items or {}) do if item.prefab==name then
   arena:StopCombat();arena:Loot({item},false,function()
    return arena.running and arena.wave==wave and arena.instance==id and arena.generation==generation
     and (arena.stage11==s or arena.stage12==s or arena.lunar12==s)
   end);break
  end end
  s.arena:Say("等待装备 "..name);return false
 end
 if name=="armorskeleton" then e=require("shadowself/control/arena_bone_maintenance").Select(p,e) end
 if inv:GetEquippedItem(slot)==e then return true,e end
 s.arena:StopCombat()
 if not p.components.playercontroller:IsBusy() and GetTime()>=(s.next_late_equip or 0) then
  A.Self(p,e,ACTIONS.EQUIP);s.next_late_equip=GetTime()+.5
 end
 return false,e
end
function R.Phase(s,phase)
 if s.phase~=phase then s.phase=phase;print("[ShadowSelf][late] wave="..s.arena.wave.." phase="..phase) end
end
function R.Health(s,e)
 s.health_reason=nil
 if not e and s.route~="default" then return end
 if not s.health_client then
  local ok,H=pcall(require,"astra/ui/mode_hud_client");local good,D=pcall(require,"astra/net/boss_health_state")
  if ok and good then s.health_client=H.New(s.player,"boss_health",D)
  else s.health_reason="hud_module_unavailable";return end
 end
 local h=s.health_client;h:Refresh(false)
 local id,generation,kind=h:GetTarget()
 if not h:IsAvailable() then s.health_reason=h:GetDecodeError() or "hud_record_unavailable";return end
 if id~=s.arena.instance or generation~=s.arena.generation or kind~="PARTICIPANT" then s.health_reason="hud_instance_generation_mismatch";return end
 local worm,candidate;local count=0
 for _,b in ipairs(h:GetModel().bosses or {}) do
  if e and b.id==tostring(e.GUID) and b.prefab==e.prefab and not b.invincible then return b.current,b.total end
  -- boss_health_service发布的是服务端GUID字符串；并非客户端实体GUID的协议。
  -- UI直接消费这份记录。单Boss分支用同实例唯一prefab及已同步位置关联本地实体。
  if e and b.prefab==e.prefab then candidate=b;count=count+1 end
  -- 原版蠕虫根实体带INLIMBO，不会出现在场地扫描；只认同一实例唯一的服务端worm_boss记录。
  if not e and b.prefab=="worm_boss" and not b.invincible then
   if worm then s.health_reason="ambiguous_worm_records";return end
   worm=b
  end
 end
 if worm then return worm.current,worm.total end
 if e and count==1 and not candidate.invincible then
  local peers=0
  for _,other in ipairs(s.arena.enemies or {}) do
   if R.Live(other) and other.prefab==e.prefab then peers=peers+1 end
  end
  local p=e:GetPosition()
  if peers<=1 and (p.x-candidate.x)^2+(p.z-candidate.z)^2<=6^2 then
   return candidate.current,candidate.total
  end
  s.health_reason=peers>1 and "ambiguous_local_bosses" or "boss_position_mismatch";return
 end
 s.health_reason=count>1 and "ambiguous_boss_records" or candidate and candidate.invincible and "boss_invincible" or "boss_record_missing"
end
-- 只在原生走A实际到达命中帧、目标仍可攻击且在真实武器距离内时计一次。
function R.Hits(s,e)
 if s.pending_hit then
  local hp=R.Health(s,s.boss)
  if hp and hp<s.pending_hit.health then s.hits=(s.hits or 0)+1;s.pending_hit=nil
  elseif GetTime()>=s.pending_hit.deadline then s.pending_hit=nil end
 end
 local c=s.arena.bridge.coordinator;local p=s.player;local a=p.AnimState
 if not c or not c.h or not a then return s.hits or 0 end
 local f=a:GetCurrentAnimationFrame() or 0;local attacking=p:HasTag("attack")
 if not attacking or not s.hit_active or f<(s.hit_frame or 0) or s.hit_target~=e then s.hit_counted=nil end
 local combat=p.replica and p.replica.combat
 local reach=(combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or c.gear:AttackRange())+e:GetPhysicsRadius(0)
 if attacking and not s.hit_counted and R.Live(e) and not e:HasTag("notarget") and not e:HasTag("NOCLICK") and c.h.ent==e
  and p:GetPosition():DistSq(e:GetPosition())<=reach^2 and c.h.IsHitingFrame and c.h:IsHitingFrame(0,e,true) then
  if s.require_damage then
   local hp=R.Health(s,s.boss)
   if hp and not s.pending_hit then s.pending_hit={health=hp,deadline=GetTime()+3} end
  else s.hits=(s.hits or 0)+1 end
  s.hit_counted=true
 end
 s.hit_active=attacking;s.hit_frame=f;s.hit_target=e
 return s.hits or 0
end
function R.ResetHits(s) s.hits=0;s.hit_counted=nil;s.hit_active=nil;s.hit_target=nil;s.pending_hit=nil end
function R.Weapon(s,name)
 local ok,item=R.Equip(s,name,EQUIPSLOTS.HANDS)
 s.weapon=item
 local c=s.arena.bridge.coordinator;if c and c.gear then c.gear.forced_weapon=item end
 return ok
end
function R.Stop(s)
 local c=s.arena.bridge.coordinator
 if c and c.gear and c.gear.forced_weapon==s.weapon then c.gear.forced_weapon=nil end
 if s.reward then s.reward:Stop() end
 s.target=nil
end
return R
