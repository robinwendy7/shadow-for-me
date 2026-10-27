-- 第11关：分别读取daywalker与daywalker2的可见前摇，不混用两套状态机。
local R=require("shadowself/control/arena_late_runtime")
local P={}
local function anim(e,n) return e and e.AnimState and e.AnimState:IsCurrentAnimation(n) end
function P.Digging(e)
 return R.Live(e) and e.prefab=="daywalker2" and (anim(e,"rummage_pre") or anim(e,"rummage_loop") or anim(e,"rummage_hit"))
end
function P.Finishing(s)
 return s and s.finish and s.arena and s.arena.wave==11 and s.boss and (s.boss.prefab=="daywalker2" or s.boss.prefab=="daywalker")
  and s.reward and s.reward.BoxesDone and s.reward:BoxesDone() or false
end
function P.Kind(e,finishing)
 if not R.Live(e) then return end
 if e.prefab=="daywalker" then
  if anim(e,"run_pre") or anim(e,"atk3") then return "pounce",12 end
  if anim(e,"atk_slam_pre") or anim(e,"atk_slam") then return "slam",9 end
  return
 end
 if e.prefab~="daywalker2" then return end
 local f=e.AnimState and e.AnimState:GetCurrentAnimationFrame() or 0
 if anim(e,"laser_pre") or anim(e,"laser_pst") and f<=16 then return "laser",15 end
 if anim(e,"throw_pre") or anim(e,"throw_loop") or anim(e,"throw") or anim(e,"throw_pst") then return "throw",30 end
 if anim(e,"tackle_pre") or anim(e,"tackle_loop") then return "tackle",12 end
 if anim(e,"atk_object") and f<=23 then return "swing",5.5 end
 if finishing and (anim(e,"run_pre") or anim(e,"atk3") and f<=18) then return "pounce",12 end
end
function P.MimicZones(s,entities)
 local zones={}
 if not P.Finishing(s) then return zones end
 local lead=require("shadowself/control/nettiming").Frames(s.context)+2
 for _,e in ipairs(entities or {}) do if R.Live(e) and e.prefab=="chest_mimic_revealed" then
  local f=e.AnimState and e.AnimState:GetCurrentAnimationFrame() or 0
  if anim(e,"attack") and f<=18+lead or anim(e,"spawn") and f<=42+lead then
   zones[#zones+1]={pos=e:GetPosition(),radius=require("shadowself/control/navigation").Radius(e)+1,source=e}
  end
 end end
 return zones
end
function P.MimicDanger(s,entities)
 if not P.Finishing(s) then return false end
 local p=s.player:GetPosition()
 for _,z in ipairs(P.MimicZones(s,entities)) do if p:DistSq(z.pos)<z.radius^2 then return true end end
 return false
end
function P.ShieldLoot(c,e)
 local s=c and c.s
 if not s or not s.finish or s.arena.wave~=11 or s.reward~=c or c.retreat or c.complete
  or not R.Live(e) or (e.prefab~="daywalker2" and e.prefab~="daywalker") then return false end
 local count=0;for _ in pairs(c.visited) do count=count+1 end
 return count<4 and require("shadowself/control/boneguard").Ready(s.context)
end
function P.Context(c,entities)
 -- 只解除正在翻找者的通用追近预测，仍保留其肉身、地面和其他怪物。
 local context=c.s.context;local enemies,hazards={},{}
 for _,z in ipairs(context.hazards or {}) do hazards[#hazards+1]=z end
 for _,e in ipairs(context.enemies or entities or {}) do
  if P.Digging(e) or P.ShieldLoot(c,e) then
   local radius=e.prefab=="daywalker" and (e:GetPhysicsRadius(0)+c.s.player:GetPhysicsRadius(0)+.3) or 3.5
   hazards[#hazards+1]={pos=e:GetPosition(),radius=radius,source=e}
  else enemies[#enemies+1]=e end
 end
 return setmetatable({enemies=enemies,hazards=hazards},{__index=context})
end
function P.LootSafe(c,e,box)
 if not P.Digging(e) and not P.ShieldLoot(c,e) then return false end
 local q=e:GetPosition()
 local radius=e.prefab=="daywalker" and (e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.3) or 3.5
 return c.player:GetPosition():DistSq(q)>radius^2 and (not box or box:GetPosition():DistSq(q)>radius^2)
end
function P.Retreat(s,entities)
 local reward=s.reward;local r=reward and reward.retreat
 if not r then return false end
 if P.Finishing(s) then reward.retreat=nil;reward.reward_route=nil;return false end
 local boss=s.boss
 if not R.Live(boss) then reward.retreat=nil;return false end
 local p=s.player:GetPosition();local ep=boss:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z
 local d=math.sqrt(dx*dx+dz*dz);if d<.01 then dx,dz,d=1,0,1 end
 local kind=P.Kind(boss);local mode="unknown"
 if P.Digging(boss) or kind=="throw" then mode="pile_throw"
 elseif kind=="laser" then mode="cannon"
 elseif r.boss_pos and (ep.x-r.boss_pos.x)*dx+(ep.z-r.boss_pos.z)*dz>.01 then mode="following" end
 r.boss_pos=ep
 if mode~="unknown" then r.mode=mode end
 if r.mode~=r.logged and GetTime()>=(r.next_log or 0) then
  print("[ShadowSelf][rewards] retreat boss="..tostring(r.mode or "unknown"));r.logged=r.mode;r.next_log=GetTime()+1
 end
 local safe=kind=="laser" and 16 or 10
 if d>=safe and p:DistSq(r.start)>=3^2 then
  reward.retreat=nil
  if r.mode=="following" then require("shadowself/control/arena_reward_route").Begin(reward,"开箱后 · 拾荒疯猪继续追击，拉开后等待下一护盾窗口") end
  return false
 end
 local Nav=require("shadowself/control/navigation");local context=P.Context({s=s},entities);local q
 local target=math.max(kind=="laser" and 16 or 12,d+4)
 for _,side in ipairs({s.pig_dodge_side or 1,-(s.pig_dodge_side or 1)}) do
  local point=Vector3(ep.x+dx/d*target-dz/d*6*side,0,ep.z+dz/d*target+dx/d*6*side)
  if Nav.Safe(context,point,boss) then q=point;s.pig_dodge_side=side;break end
 end
 q=q or Nav.Select(context,Vector3(p.x-dz/d*6,0,p.z+dx/d*6),boss)
 s.arena:StopCombat();s.target=nil;s.arena.bridge.priority_target=nil
 s.arena.encounters:Move(q,"开箱后 · 立即远离，观察拾荒疯猪追击或回堆投掷")
 return true
end
function P.AfterBox(c,entities)
 local s=c.s
 if c:BoxesDone() then c.retreat=nil;return end
 if s.arena.wave==11 and s.finish and R.Live(s.boss) and s.boss.prefab=="daywalker2" then
  c.retreat={start=c.player:GetPosition()};P.Retreat(s,entities)
 end
end
function P.Approach(c,entities,box,context)
 local Nav=require("shadowself/control/navigation")
 local digging=false
 for _,e in ipairs(entities or {}) do if P.LootSafe(c,e,box) then digging=true;break end end
 if not digging then return false end
 local q=Nav.Select(context,box:GetPosition())
 if c.player:GetPosition():DistSq(q)<.25^2 then return false end
 if c.arena.healing and not c.arena.healing:Path(context,q) then return false end
 c.arena.encounters:Move(q,"奖励流程 · 翻找窗口，绕过垃圾堆接近宝箱")
 return true
end
function P.AttackWindow(s)
 local e=s.boss
 if not P.Digging(e) then s.pig_dig=nil;return false end
 local now=GetTime();local d=s.pig_dig
 if not d or d.entity~=e then d={entity=e,since=now};s.pig_dig=d end
 -- SG最短翻找1秒；留出收刀与网络余量，不把整个翻找循环当作无限输出窗口。
 return now-d.since<math.max(0,1-.5-require("shadowself/control/nettiming").Delay(s.context))
end
function P.Dodge(s,entities)
 local Nav=require("shadowself/control/navigation")
 if s.arena.wave~=11 then return false end
 if P.Retreat(s,entities) then return true end
 local p=s.player:GetPosition();local boss,kind
 for _,e in ipairs(entities or {}) do
  local k,range=P.Kind(e,P.Finishing(s))
  if e.prefab=="daywalker" and P.ShieldLoot(s.reward,e) then k=nil end
  if (k=="laser" or k=="throw") and P.ShieldLoot(s.reward,e) then k=nil end
  if k=="swing" and not s.finish and require("shadowself/control/boneguard").Ready(s.context) then k=nil end
  if k and p:DistSq(e:GetPosition())<range^2 then boss,kind=e,k;break end
 end
 if not P.Digging(s.boss) then s.pig_dig=nil end
 -- 投掷落点的可见特效仍有伤害，不能因本体退出throw动画立刻站回去。
 local zones=P.MimicZones(s,entities)
 for _,e in ipairs(entities or {}) do if R.Live(e) and e.prefab=="junkball_fall_fx" and not P.ShieldLoot(s.reward,s.boss) then zones[#zones+1]={pos=e:GetPosition(),radius=4,source=e} end end
 local context=P.Context({s=s},entities)
 local near=false;for _,z in ipairs(zones) do if p:DistSq(z.pos)<z.radius^2 then near=true;break end end
 local q=require("shadowself/control/arena_fire").Escape(s.player,zones,{5,7,9})
 if near and not q then
  local hazards={};for _,z in ipairs(context.hazards or {}) do hazards[#hazards+1]=z end
  for _,z in ipairs(zones) do hazards[#hazards+1]=z end
  q=Nav.Escape(setmetatable({hazards=hazards},{__index=context}),p)
 end
 if boss then
  local ep=boss:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
  if d<.01 then dx,dz,d=1,0,1 end
  -- 激光跟踪到laser_pst第5帧，近处只绕圈仍会被瞄准；提前斜撤出整条射程。
  local step=kind=="laser" and 8 or kind=="swing" and 4 or 6
  local choices={}
  for _,side in ipairs({s.pig_dodge_side or 1,-(s.pig_dodge_side or 1)}) do
   local point=Vector3(p.x-dz/d*step*side,0,p.z+dx/d*step*side)
   if kind=="laser" then point=Vector3(ep.x+dx/d*16-dz/d*step*side,0,ep.z+dz/d*16+dx/d*step*side) end
   if kind=="swing" then point=Vector3(ep.x+dx/d*6.5,0,ep.z+dz/d*6.5) end
   if Nav.Safe(context,point,boss) then choices[#choices+1]={point=point,side=side} end
  end
  if not q and choices[1] then q=choices[1].point;s.pig_dodge_side=choices[1].side end
  if not q then q=Nav.Select(context,Vector3(p.x-dz/d*step,0,p.z+dx/d*step),boss) end
 end
 if not boss and not q and not near then return false end
 s.arena:StopCombat();s.target=nil;s.arena.bridge.priority_target=nil
 if s.reward then
  local reward=s.reward;local box=reward.opened;local c=box and box:IsValid() and box.replica and box.replica.container
  if c and c:IsOpenedBy(s.player) then c:Close() end
  reward.opened=nil;reward.confirmed_open=nil;reward.open_since=nil;reward.quiet_since=nil
  reward.route_revision=(reward.route_revision or 0)+1 -- 保留尚未确认的入包事务。
 end
 if s.buffs and s.buffs.pending then s.buffs.pending.interrupted=true;s.buffs:Tick() end
 if s.arena.healing and s.arena.healing.pending then s.arena.healing:Interrupt(s.context) end
 if q then s.arena.encounters:Move(q,"拾荒疯猪 · "..(kind or "落点").."预警，先侧移避险再继续原流程") end
 return true
end
return P
