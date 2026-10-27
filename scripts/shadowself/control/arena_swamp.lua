-- 第五关沼泽：首轮外圈7秒两风打蚊子；蚊子清完后鱼人→青蛙→触手。
local M={}
local members={merm=true,tentacle=true,mosquito=true,frog=true}
local expected={}
for _,choice in ipairs(require("shadowself/data/arena_classic").encounters[5].default) do
 local found=false
 for _,m in ipairs(choice.monsters) do if m.prefab=="merm" then found=true end end
 if found then for _,m in ipairs(choice.monsters) do expected[m.prefab]=m.amount end;break end
end
local function dead(e)
 local h=e.replica and e.replica.health
 return e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead())
end
local function alive(e) return e:IsValid() and not dead(e) and not e:HasTag("INLIMBO") end
function M.Required(c)
 if not c.plan or not c.plan.arena or not c.plan.arena_wave or c.plan.arena_wave()~=5 then return false end
 for _,e in ipairs(c.enemies or {}) do if members[e.prefab] and alive(e) then return true end end
 return false
end
local function scan(c,state)
 for _,list in ipairs({c.plan.arena_entities and c.plan.arena_entities() or {},c.enemies or {}}) do
  for _,e in ipairs(list) do if members[e.prefab] and state.roster[e]==nil then state.roster[e]=false end end
 end
 local killed={};local remaining={}
 for e,confirmed in pairs(state.roster) do
  if confirmed or dead(e) then state.roster[e]=true;killed[e.prefab]=(killed[e.prefab] or 0)+1
  elseif alive(e) then remaining[e.prefab]=true end
 end
 -- 服务端剩余数全部由已知活目标占满时，补足漏看尸体的完成确认。
 local total=0
 for e,confirmed in pairs(state.roster) do if not confirmed and alive(e) then total=total+1 end end
 local objectives=c.plan.arena_objectives and c.plan.arena_objectives()
 local accounted=total>0 and objectives==total
 state.completed=state.completed or {}
 local function complete(name)
  if not remaining[name] and ((killed[name] or 0)>=(expected[name] or 0) or accounted) then state.completed[name]=true end
  return state.completed[name] and not remaining[name]
 end
 return complete("mosquito"),complete("merm"),complete("frog")
end
local function frogdistance(c,state,q)
 local nearest=math.huge
 for e in pairs(state.roster) do if e.prefab=="frog" and alive(e) then nearest=math.min(nearest,q:DistSq(e:GetPosition())) end end
 return nearest
end
local function fishsafe(c,state,e)
 local p=c.player:GetPosition();local q=e:GetPosition();local d=math.sqrt(p:DistSq(q))
 local combat=c.player.replica and c.player.replica.combat
 local reach=(combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)
  +(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)-.15
 local point=p
 if d>reach then point=Vector3(q.x+(p.x-q.x)*reach/d,0,q.z+(p.z-q.z)*reach/d) end
 return frogdistance(c,state,p)>=8^2 and frogdistance(c,state,point)>=8^2
end
local function separate(owner,state,target)
 local c=owner.c;local p=c.player:GetPosition();local Nav=require("shadowself/control/navigation")
 if require("shadowself/control/arena_prepare").Armor(c) then return "support",target end
 if c.healing and c.healing:Tick(c) then return "support",target end
 local before=frogdistance(c,state,p);local best,score
 for _,length in ipairs({3,5,8}) do for i=0,23 do
  local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*length,0,p.z+math.sin(a)*length)
  local clearance=frogdistance(c,state,q)
  if (clearance>=8.6^2 or clearance>before+.1) and Nav.Safe(c,q) then
   local value=(clearance>=8.6^2 and 0 or 1000-clearance)+length+q:DistSq(target:GetPosition())*.02
   if not score or value<score then best,score=q,value end
  end
 end end
 state.target=nil;c.bridge:PauseAttack()
 if best then return owner:Move(best,"沼泽组合 · 与青蛙拉开至少八码，再攻击鱼人",target),target end
 local hazards={};for _,z in ipairs(c.hazards or {}) do hazards[#hazards+1]=z end
 for e in pairs(state.roster) do if e.prefab=="frog" and alive(e) then hazards[#hazards+1]={pos=e:GetPosition(),radius=8.6,source=e} end end
 local route=setmetatable({hazards=hazards},{__index=c})
 local goal=Nav.Escape(route,p)
 if not goal then goal=Nav.Select(route,p) end
 return owner:Move(goal,"沼泽组合 · 联合避让鱼人、青蛙和触手，再寻找八码攻击点",target),target
end
function M.Allowed(c,e)
 if not M.Required(c) then return true end
 local state=c.encounters and c.encounters.swamp_state
 return state and state.phase=="melee" and state.target==e and alive(e)
  and (e.prefab~="merm" or fishsafe(c,state,e)) or false
end
function M.Tick(owner)
 local c=owner.c
 if not M.Required(c) then
  if owner.swamp_state or owner.swamp_wind then require("shadowself/control/arena_windcycle").Release(c) end
  if owner.swamp_wind then owner.swamp_wind:Stop();owner.swamp_wind=nil end
  owner.swamp_state=nil;return
 end
 owner.swamp_state=owner.swamp_state or {roster={},phase="wind"}
 local state=owner.swamp_state
 local cleared,fish_dead,frogs_dead=scan(c,state)
 if cleared then state.phase="melee" end
 if state.phase=="melee" then
  require("shadowself/control/arena_windcycle").Release(c)
  if owner.swamp_wind then owner.swamp_wind:Stop();owner.swamp_wind=nil end
  local name=not fish_dead and "merm" or not frogs_dead and "frog" or "tentacle";local target,near
  local safe_target,safe_near
  for _,e in ipairs(c.enemies) do if e.prefab==name and alive(e) and c.bridge.allowed(e) then
   local d=c.player:GetPosition():DistSq(e:GetPosition())
   if not near or d<near then target=e;near=d end
   if name=="merm" and fishsafe(c,state,e) and (not safe_near or d<safe_near) then safe_target,safe_near=e,d end
  end end
  target=safe_target or target
  state.target=target
  if not target then c.bridge:PauseAttack();return "support" end -- 消失不算死亡；鱼人未确认清完时不能抢打触手。
  if name=="merm" and not fishsafe(c,state,target) then return separate(owner,state,target) end
  owner:Release();return "attack",owner:Target(target)
 end
 local enemies={}
 for _,e in ipairs(c.enemies) do if e.prefab=="mosquito" and alive(e) and c.bridge.allowed(e) then enemies[#enemies+1]=e end end
 if #enemies==0 then
  c.bridge:PauseAttack()
  for _,e in ipairs(c.enemies) do if alive(e) then return owner:Away(e,5,"沼泽组合 · 等待蚊子死亡确认"),e end end
  return "support"
 end
 owner.swamp_wind=owner.swamp_wind or require("shadowself/control/arena_goats")(owner,"沼泽组合")
 owner.swamp_wind.first_seconds=7;owner.swamp_wind.limit=owner.swamp_wind.limit or 2
 owner.swamp_wind.gather_time=0
 owner.swamp_wind.cast_guard=function() return M.Required(c) and state.phase=="wind" end
 local mode,target=owner.swamp_wind:Tick(enemies)
 if mode then return mode,target end
 return owner:Away(enemies[1],5,"沼泽组合 · 等待补捡天气风向标，继续安全游离"),enemies[1]
end
return M
