local A=require("shadowself/control/actions")
local R=require("shadowself/control/arena_late_runtime")
local Inv=require("shadowself/control/arena_inventory")
local Nav=require("shadowself/control/navigation")
local F={}
function F.BoneReady(s)
 local armor=s.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
 if not armor or armor.prefab~="armorskeleton" or Inv.Condition(armor)<=0 then s.bone=nil;return false end
 local now=GetTime();local percent=Inv.Condition(armor)
 if s.bone~=armor then s.bone=armor;s.bone_after=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.3;s.bone_percent=percent end
 if percent<(s.bone_percent or percent)-.001 then s.bone_after=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.3 end
 s.bone_percent=percent
 local cd=armor.components and armor.components.cooldown
 if cd and cd.GetTimeToCharged then return cd:GetTimeToCharged()<=0 end
 -- 纯客户端不能直接读取cooldown；耐久下降或本人的真实护盾特效重新起算。
 local p=s.player:GetPosition()
 s.shield_seen=s.shield_seen or setmetatable({},{__mode="k"})
 for _,e in ipairs(TheSim:FindEntities(p.x,0,p.z,3,{"FX"})) do
  if (e.prefab or ""):match("^shadow_shield%d$") and e.entity and e.entity.GetParent and e.entity:GetParent()==s.player.entity
   and not s.shield_seen[e] then s.shield_seen[e]=true;s.bone_after=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.3 end
 end
 return now>=(s.bone_after or math.huge)
end
function F.Orbit(s,entities)
 s.arena:StopCombat();s.target=nil;s.arena.bridge.priority_target=nil
 local route=require("shadowself/control/arena_junkroute")
 local center=route.Anchor(s,entities)
 if not center then s.arena:Say("拾荒疯猪 · 等待垃圾堆位置同步");return "hold" end
 if not s.junk_logged_center or center:DistSq(s.junk_logged_center)>1 then
  s.junk_logged_center=center
  local p=s.player:GetPosition()
  print(string.format("[ShadowSelf][junk] center=%.2f,%.2f radius=%.2f from=%.2f,%.2f source=%s",center.x,center.z,
   (s.junk_radius or 3.6)+(s.player.GetPhysicsRadius and s.player:GetPhysicsRadius(0) or .5)+.3,p.x,p.z,s.junk_center and "junk_pile_big" or "arena_center"))
 end
 local q=route.Point(s,center)
 if q then
  s.junk_blocked=nil
  s.arena.encounters:Move(q,"拾荒疯猪 · 只绕中央垃圾堆，手杖等待骨甲冷却");return "hold"
 end
 if not s.junk_blocked then
  s.junk_blocked=true;A.Stop(s.player)
  print(string.format("[ShadowSelf][junk] blocked center=%.2f,%.2f reason=terrain_or_hazard",center.x,center.z))
 end
 s.arena:Say("拾荒疯猪 · 中央垃圾堆环路被地形或危险地面阻挡，重查环路")
 return "hold"
end
function F.FishSafe(s,q)
 return not R.Live(s.boss) or s.boss.prefab~="daywalker2" or q:DistSq(s.boss:GetPosition())>=7^2
end
function F.Rewards(s,entities,worm)
 s.reward=s.reward or require("shadowself/control/arena_rewards")(s,worm)
 if not s.reward:Ready(worm) then
  R.Phase(s,"rewards")
  if not s.reward:Tick(entities) then return "hold" end
 end
 return nil
end
function F.Pig(s,entities)
 if not s:Cleared() then return end
 -- 收尾一经开始就完成取物；Boss提前死亡不应把控制交给附近拟态箱。
 if s.finish then
  if F.Rewards(s,entities,false) then return "hold" end
  if not s.reward:Ready() then return "hold" end
  if not R.Live(s.boss) then s.target=nil;s.arena.bridge.priority_target=nil;return "hold" end
  R.Phase(s,"staff_finish");s.target=s.boss;s.arena.bridge.priority_target=s.boss;return "fight"
 end
 if not R.Live(s.boss) then return end
 for _,e in ipairs(s.arena.enemies or {}) do if R.Live(e) and e~=s.boss then return end end
 local hp=R.Health(s,s.boss)
 s.health_wait=hp==nil
 if hp and hp<=200 then s.finish=true end
 if s.finish then return F.Pig(s,entities) end
 if s.boss.prefab=="daywalker" then
  local armor=R.Item(s.player,"armorskeleton")
  if not armor then return s:Patrol("暗影疯猪 · 缺少可用骨甲，先安全补捡，不空甲追击") end
  if not R.Equip(s,"armorskeleton",EQUIPSLOTS.BODY) then return "hold" end
 end
 if not hp then
  s.arena:StopCombat();s.target=nil
  if GetTime()>=(s.next_hp_log or 0) then print("[ShadowSelf][late] exact_boss_health=unavailable prefab="..s.boss.prefab.." reason="..tostring(s.health_reason));s.next_hp_log=GetTime()+15 end
  if s.boss.prefab=="daywalker2" then return F.Orbit(s,entities) end
  return s:Patrol("疯猪 · 等待服务器精确血量，禁止用100血占位值决定收尾")
 end
 if s.boss.prefab~="daywalker2" then return end
 if not R.Equip(s,"armorskeleton",EQUIPSLOTS.BODY) then
  local body=s.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
  if body and body.prefab=="armorskeleton" and Inv.Condition(body)<=0 then return F.Orbit(s,entities) end
  return "hold"
 end
 local ready=F.BoneReady(s)
 if require("shadowself/control/arena_scrappig").AttackWindow(s) then
  R.Phase(s,"pig_dig_attack");s.target=s.boss;s.arena.bridge.priority_target=s.boss;return "fight"
 end
 if require("shadowself/control/boneguard").Ready(s.context) then
  if s.phase~="pig_four" or R.Hits(s,s.boss)>=4 then R.ResetHits(s) end
  s.orbit_until=nil;R.Phase(s,"pig_four");s.target=s.boss;s.arena.bridge.priority_target=s.boss;return "fight"
 end
 if s.phase=="pig_four" then
  if R.Hits(s,s.boss)>=4 then s.orbit_until=GetTime()+6;R.Phase(s,"pig_orbit")
  else s.target=s.boss;s.arena.bridge.priority_target=s.boss;return "fight" end
 end
 if GetTime()<(s.orbit_until or 0) or not ready then return F.Orbit(s,entities) end
 R.ResetHits(s);R.Phase(s,"pig_four");s.target=s.boss;s.arena.bridge.priority_target=s.boss;return "fight"
end
function F.WormDanger(s,entities)
 if s.route~="default" then return false end
 local zones={}
 for _,e in ipairs(entities or {}) do if R.Live(e) then
  local n=e.prefab;local a=e.AnimState
  if n=="worm_boss_segment" or n=="worm_boss_tail" then
   zones[#zones+1]={pos=e:GetPosition(),radius=math.max(2,e.GetPhysicsRadius and e:GetPhysicsRadius(0) or 0)+s.player:GetPhysicsRadius(0)+.5,source=e}
  elseif n=="worm_boss_dirt_ground_fx" or n=="worm_boss_head" and a and (a:IsCurrentAnimation("emerge_eat") or a:IsCurrentAnimation("emerge_full") or a:IsCurrentAnimation("emerge_taunt")) then
   zones[#zones+1]={pos=e:GetPosition(),radius=4.5,source=e}
  end
 end end
 local q=require("shadowself/control/arena_fire").Escape(s.player,zones)
 if not q then return false end
 s.arena:StopCombat();s.target=nil;s.arena.bridge.priority_target=nil;s.arena.encounters.worm_target=nil
 s.arena.encounters:Move(q,"普通线 · 先躲蠕虫钻出和体节刮伤，再近战")
 return true
end
function F.Worm(s,entities)
 s.require_damage=true
 if F.WormDanger(s,entities) then return "hold" end
 if not s:Cleared() then
  R.Phase(s,"mites_melee");local target,nearest;local p=s.player:GetPosition()
  for e,confirmed in pairs(s.seen or {}) do if not confirmed and R.Live(e) and e.prefab=="cave_vent_mite" then
   local d=p:DistSq(e:GetPosition());if not nearest or d<nearest then target,nearest=e,d end
  end end
  s.target=target;s.arena.bridge.priority_target=target
  if target then return "fight" end
  s.arena:StopCombat();s.arena:Say("普通线 · 等待地热螨真实死亡确认");return "hold"
 end
 local hp=R.Health(s,s.boss)
 s.health_wait=hp==nil
 if not hp then s.arena:StopCombat();s.target=nil;s.arena:Say("普通线 · 等待服务器精确蠕虫血量，保留残血开箱窗口");return "hold" end
 if hp<=200 then s.finish=true end
 if s.finish then
  if F.Rewards(s,entities,true) or not s.reward:Ready(true) then return "hold" end
 end
 local target
 if s.head and s.head.AnimState then
  local a=s.head.AnimState
  local chewing=a:IsCurrentAnimation("chew_small") or a:IsCurrentAnimation("chew_big") or a:IsCurrentAnimation("chew_shock_loop") or a:IsCurrentAnimation("chew_shock_pst")
  if chewing then for _,e in ipairs(s.dirts or {}) do
   if R.Live(e) and not e:HasTag("notarget") and e:GetPosition():DistSq(s.head:GetPosition())<4^2 then target=e;break end
  end end
 end
 s.target=target;s.arena.encounters.worm_target=target;s.arena.bridge.priority_target=target
 if target then
  if s.finish and not R.Weapon(s,"staff_lunarplant") then return "hold" end
  R.Phase(s,s.finish and "staff_finish" or "worm_melee");return "fight"
 end
 s.arena:StopCombat();s.arena:Say("普通线 · 等待蠕虫可攻击的真实咀嚼窗口，不进行固定巡游")
 return "hold"
end
function F.Allowed(s,e)
 local pig=require("shadowself/control/arena_scrappig")
 if pig.MimicDanger(s,s.arena.entities or s.arena.enemies) then return false end
 if e and e.prefab=="daywalker2" then
  local kind=pig.Kind(e,pig.Finishing(s))
  if kind and (kind~="swing" or s.finish or not require("shadowself/control/boneguard").Ready(s.context)) then return false end
 end
 if e and e.prefab=="daywalker" and pig.Kind(e) and (s.finish or not require("shadowself/control/boneguard").Ready(s.context)) then return false end
 if s.health_wait then return false end
 if s.route~="default" and s.boss and s:Cleared() and not s.finish then
  local hp=R.Health(s,s.boss)
  if hp and hp<=200 then s.finish=true;return false end
 end
 if s.reward and not s.reward:Ready() then return false end
 if s.finish and s.route~="default" then return s.phase=="staff_finish" and e==s.boss and R.Live(e) end
 if s.route=="default" then
  if not s:Cleared() then return e and e==s.target and e.prefab=="cave_vent_mite" and R.Live(e) end
  local hp=R.Health(s,s.boss)
  if hp and hp<=200 and not s.finish then s.finish=true;return false end
  if s.finish and (not s.reward or not s.reward:Ready()) then return false end
  local a=s.head and s.head.AnimState
  local chewing=a and (a:IsCurrentAnimation("chew_small") or a:IsCurrentAnimation("chew_big") or a:IsCurrentAnimation("chew_shock_loop") or a:IsCurrentAnimation("chew_shock_pst"))
  return (s.phase=="worm_melee" or s.phase=="staff_finish") and e==s.target and R.Live(e) and not e:HasTag("notarget") and chewing and hp~=nil
 end
 if s.boss and s.boss.prefab=="daywalker2" and s:Cleared() then
  if s.phase=="pig_dig_attack" then return e==s.boss and require("shadowself/control/arena_scrappig").AttackWindow(s) end
  return s.phase=="pig_four" and e==s.boss and R.Hits(s,e)<4
 end
 if s.boss and s.boss.prefab=="daywalker" and s:Cleared() then
  local body=s.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
  return e==s.boss and R.Live(e) and body and body.prefab=="armorskeleton" and Inv.Condition(body)>0 or false
 end
 return nil
end
return F
