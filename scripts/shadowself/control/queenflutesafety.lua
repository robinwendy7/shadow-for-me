-- 只用于蜂后二阶段排箫：以原版命中帧估计站定至第30帧是否安全。
local Status=require("shadowself/control/status")
local Nav=require("shadowself/control/navigation")
local S={}
local function anim(e,name) return e.AnimState and e.AnimState:IsCurrentAnimation(name) end
local function frame(e) return e.AnimState and e.AnimState.GetCurrentAnimationFrame and e.AnimState:GetCurrentAnimationFrame() or 0 end
function S.Playing(p)
 return anim(p,"action_uniqueitem_pre") or anim(p,"flute") or p.sg and p.sg.HasStateTag and p.sg:HasStateTag("playing") or false
end
function S.Window(c) return 30*(FRAMES or 1/30)+(c.Latency and c:Latency() or .1)+.12 end
function S.Observe(q,queen,bees,now)
 local state=q.flute_cycle;state.impacts=state.impacts or {}
 local list={queen};for _,e in ipairs(bees) do list[#list+1]=e end
 for _,e in ipairs(list) do
  if anim(e,"atk") then
   local hit=e==queen and 14 or 13
   state.impacts[e]=now+(hit-frame(e))*(FRAMES or 1/30)
  end
 end
end
function S.Earliest(q,queen,bees,point,now)
 local c=q.c;local earliest=math.huge;local source="clear"
 local list={queen};for _,e in ipairs(bees) do list[#list+1]=e end
 for _,e in ipairs(list) do if e:IsValid() and not Status.Sleeping(e) and not Status.Frozen(e) then
  local boss=e==queen;local hit=boss and 14 or 13
  local radius=(boss and (TUNING.BEEQUEEN_HIT_RANGE or 6) or (TUNING.BEEGUARD_ATTACK_RANGE or 1.5))
      +(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)+.25
  local speed=boss and (TUNING.BEEQUEEN_SPEED or 4) or (TUNING.BEEGUARD_SPEED or 3)
  local distance=math.sqrt(point:DistSq(e:GetPosition()))
  local arrival=math.max(0,distance-radius)/speed
  local eta=arrival+hit*(FRAMES or 1/30)
  local impact=q.flute_cycle.impacts and q.flute_cycle.impacts[e]
  if anim(e,"atk") and frame(e)<hit then
   if distance<radius then eta=(hit-frame(e))*(FRAMES or 1/30) end
  elseif impact then
   local cooldown=(boss and (TUNING.BEEQUEEN_ATTACK_PERIOD or 2) or (TUNING.BEEGUARD_ATTACK_PERIOD or 2))
   -- StartAttack在进入攻击时启动冷却，不能把命中时刻当冷却开始。
   eta=math.max(arrival,impact-hit*(FRAMES or 1/30)+cooldown-now)+hit*(FRAMES or 1/30)
  end
  if eta<earliest then earliest=eta;source=boss and "queen_attack" or "guard_attack" end
 end end
 return earliest,source
end
function S.Ready(q,queen,bees,now)
 if anim(queen,"screech") and frame(queen)<35 then return false,"screech_wakes_guards",0 end
 local pos=q.c.player:GetPosition()
 for _,z in ipairs(q.c.hazards or {}) do if pos:DistSq(z.pos)<z.radius^2 then return false,"hazard_underfoot",0 end end
 local eta,source=S.Earliest(q,queen,bees,pos,now)
 return eta>S.Window(q.c),source,eta
end
-- 覆盖不足是需要缩小的误差，不以“离怪越远越好”替代共同站位。
function S.Coverage(point,queen,bees,range)
 local excess=math.max(0,math.sqrt(point:DistSq(queen:GetPosition()))-range)
 for _,e in ipairs(bees) do excess=math.max(excess,math.sqrt(point:DistSq(e:GetPosition()))-range) end
 return excess
end
-- 吹奏开始后，仅实际前摇能取消；不每帧重算假想追击推翻已选安全窗口。
function S.Imminent(q,queen,bees,point,remaining)
 local list={queen};for _,e in ipairs(bees) do list[#list+1]=e end
 for _,e in ipairs(list) do if not Status.Sleeping(e) and not Status.Frozen(e) and anim(e,"atk") then
  local hit=e==queen and 14 or 13
  local radius=(e==queen and (TUNING.BEEQUEEN_HIT_RANGE or 6) or (TUNING.BEEGUARD_ATTACK_RANGE or 1.5))
   +(q.c.player.GetPhysicsRadius and q.c.player:GetPhysicsRadius(0) or .5)+.25
  local f=frame(e)
  if f<hit and (hit-f)*(FRAMES or 1/30)<remaining and point:DistSq(e:GetPosition())<radius^2 then return true end
 end end
 return false
end
-- 距离亏损在命中圈内部仍有梯度；只比较ETA会在圈内得到相同前摇时间。
function S.Shortfall(q,queen,bees,point,now)
 if S.Earliest(q,queen,bees,point,now)>S.Window(q.c) then return 0 end
 local deficit=0;local list={queen};for _,e in ipairs(bees) do list[#list+1]=e end
 for _,e in ipairs(list) do if not Status.Sleeping(e) and not Status.Frozen(e) then
  local boss=e==queen
  local radius=(boss and (TUNING.BEEQUEEN_HIT_RANGE or 6) or (TUNING.BEEGUARD_ATTACK_RANGE or 1.5))
    +(q.c.player.GetPhysicsRadius and q.c.player:GetPhysicsRadius(0) or .5)+.25
  local speed=boss and (TUNING.BEEQUEEN_SPEED or 4) or (TUNING.BEEGUARD_SPEED or 3)
  local safe=radius+speed*math.max(0,S.Window(q.c)-(boss and 14 or 13)*(FRAMES or 1/30))
  deficit=deficit+math.max(0,safe-math.sqrt(point:DistSq(e:GetPosition())))^2
 end end
 return deficit
end
function S.Point(q,queen,bees,goal,now,range)
 local c=q.c;local pos=c.player:GetPosition();local best,score
 range=range or 14.4
 local initial=S.Coverage(pos,queen,bees,range)
 local urgent=S.Earliest(q,queen,bees,pos,now)<S.Window(c)
 local winding=S.Imminent(q,queen,bees,pos,S.Window(c))
 local function consider(v)
  if not v or pos:DistSq(v)<.16 then return end
  if q.anchor and v:DistSq(q.anchor)>40^2 and v:DistSq(q.anchor)>=pos:DistSq(q.anchor) then return end
  if v:DistSq(queen:GetPosition())>18^2 and v:DistSq(queen:GetPosition())>=pos:DistSq(queen:GetPosition()) then return end
  if winding and S.Imminent(q,queen,bees,v,S.Window(c)) then return end
  local eta=S.Earliest(q,queen,bees,v,now)
  local missing=S.Coverage(v,queen,bees,range)
  -- 非紧急时必须收敛覆盖；不能为扩大安全余量无限跑出15码。
  if not urgent and missing>initial+.02 then return end
  local deficit=math.max(0,S.Window(c)-eta)
  local value=missing*missing*1000+S.Shortfall(q,queen,bees,v,now)*1000+deficit*deficit*100+Nav.Risk(c,v,queen)*80+v:DistSq(goal)
  if (not score or value<score) and Nav.Safe(c,v,queen) then best,score=v,value end
 end
 consider(goal)
 for _,d in ipairs({1.5,3,4}) do for i=0,23 do
  local a=i*math.pi/12;consider(Vector3(pos.x+math.cos(a)*d,0,pos.z+math.sin(a)*d))
 end end
 if not best and urgent then best=Nav.Escape(c,goal,queen) end
 return best
end
return S
