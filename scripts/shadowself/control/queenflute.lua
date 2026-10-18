-- 蜂后二阶段：全员覆盖 -> 吹奏并等待同步 -> 只打本体 -> 醒蜂后重新催眠。
local Status=require("shadowself/control/status")
local Nav=require("shadowself/control/navigation")
local F={}
function F.Range(flute)
    local instrument=flute.components and flute.components.instrument
    return instrument and instrument.range or TUNING.PANFLUTE_SLEEPRANGE or 15
end
function F.Covered(point,queen,bees,range)
    if point:DistSq(queen:GetPosition())>range^2 then return false end
    for _,bee in ipairs(bees) do if point:DistSq(bee:GetPosition())>range^2 then return false end end
    return true
end
-- 覆盖圆的边界交点给出可行站位；找不到共同覆盖点时向群体中心收拢，不作长跑拉扯。
function F.Point(c,queen,bees,range)
    local points={queen:GetPosition()};for _,bee in ipairs(bees) do points[#points+1]=bee:GetPosition() end
    local p=c.player:GetPosition();local best,score;local x,z=0,0
    local function consider(q)
        local excess=0
        for _,v in ipairs(points) do excess=math.max(excess,math.sqrt(q:DistSq(v))-range) end
        local value=excess*excess*1000+p:DistSq(q)
        if not score or value<score then best,score=q,value end
    end
    for _,v in ipairs(points) do x=x+v.x;z=z+v.z;consider(v) end
    consider(Vector3(x/#points,0,z/#points))
    for i=1,#points do for j=i+1,#points do
        local a,b=points[i],points[j];local dx,dz=b.x-a.x,b.z-a.z;local d=math.sqrt(dx*dx+dz*dz)
        if d>.01 and d<=2*range then
            local h=math.sqrt(math.max(0,range*range-d*d/4));local mx,mz=(a.x+b.x)/2,(a.z+b.z)/2
            consider(Vector3(mx-dz/d*h,0,mz+dx/d*h));consider(Vector3(mx+dz/d*h,0,mz-dx/d*h))
        end
    end end
    local goal=best or queen:GetPosition();local dx,dz=goal.x-p.x,goal.z-p.z;local d=math.sqrt(dx*dx+dz*dz)
    if d>3 then goal=Vector3(p.x+dx/d*3,0,p.z+dz/d*3) end
    return goal
end
local Debug=require("shadowself/control/queendebug")
local Safety=require("shadowself/control/queenflutesafety")
local function release(q)
 -- 吹箫交接不调用EndDodge；它会立即发出恢复武器请求。
 local c=q.c;q.travelling=nil;c.bridge.chasing=nil
 if c.travel then
  c.travel.chasing=nil;c.travel.dodging=nil;c.travel.restore_dodge=nil;c.travel.finish_deferred=nil
 end
end
local function unlock(q)
 local gear=q.c.gear
 if gear and gear.action_hold and gear.action_hold.owner==q then gear.action_hold=nil end
end
function F.Reset(q)
 unlock(q);q.flute_cycle=nil
end
function F.Interrupt(c,reason)
 local q=c and c.beequeen;local state=q and q.flute_cycle
 if not state or not state.pending then return end
 Debug.Event(c,"flute_cancel",{reason=reason,elapsed=GetTime()-(state.requested or GetTime()),performed=state.performed~=nil})
 state.pending=nil;state.confirmed=nil;state.performed=nil;state.interrupted=reason
 state.next_play=GetTime()+.35;state.recover_until=GetTime()+.6;unlock(q)
 -- 请求已经被受击/走位中断；恢复时先躲避，不让旧确认窗口扣住角色。
 c.next_move=nil
end
function F.Performed(c)
 local q=c and c.beequeen;local state=q and q.flute_cycle
 if state and state.pending then
  state.performed=GetTime();Debug.Event(c,"flute_performed",{elapsed=GetTime()-(state.requested or GetTime())})
 end
end
function F.OnAction(c,data)
 if type(data)~="table" then return end
 local act=data
 if type(data.action)=="table" and data.action.action then act=data.action end
 if act.action==ACTIONS.PLAY then F.Performed(c) end
end
local function move(q,queen,bees,now,reason,range)
 local c=q.c;range=range or 15
 local state=q.flute_cycle;local pos=c.player:GetPosition();local cache=state.route
 local signature={};for _,bee in ipairs(bees) do signature[bee]=true end
 local same=cache~=nil
 if cache then
  for bee in pairs(signature) do if not cache.roster[bee] then same=false end end
  for bee in pairs(cache.roster) do if not signature[bee] then same=false end end
 end
 -- 每帧检查实际前摇，新的攻击立即使缓存失效；普通站位搜索最多每0.2秒一次。
 local winding=Safety.Imminent(q,queen,bees,pos,Safety.Window(c))
 if not same or now>=cache.expires or pos:DistSq(cache.start)>6^2
   or cache.point and pos:DistSq(cache.point)<.25 or winding and not cache.winding then
  local goal=F.Point(c,queen,bees,math.max(1,range-.6))
  local point=Safety.Point(q,queen,bees,goal,now,math.max(1,range-.6))
  cache={point=point,start=pos,expires=now+.2,roster=signature,winding=winding};state.route=cache
 end
 if cache.point then
  -- Safety.Point已检查整段路径，直接提交，避免Queen:Move再次作24方向搜索。
  require("shadowself/control/queendashroute").Begin(q,state)
  c:Move(cache.point,reason)
 else
  c.blocked=true;c.status="蜂后 · 催眠路线受阻，等待可通行窗口"
  Debug.Throttle(c,"flute_route_blocked",1,"flute_wait",{reason="no_open_path"})
 end
end
function F.Tick(q,queen,bees,flute,now)
 if require("shadowself/control/queenspawn").Tick(q,queen,bees,now) then return true end
 local c=q.c;local p=c.player;local pc=p.components.playercontroller;local pos=p:GetPosition()
 local state=q.flute_cycle or {};q.flute_cycle=state
 Safety.Observe(q,queen,bees,now)
 local asleep=true
 for _,bee in ipairs(bees) do if not Status.Sleeping(bee) then asleep=false;break end end
 q:Target(queen)
 if state.solo and not asleep then state.solo=nil;state.in_solo=nil;state.next_play=now end
 if state.pending then
  -- 每轮重新核对全部守卫，不能沿用补兵/唤醒前的confirmed。
  state.confirmed=asleep and (Status.Sleeping(queen) or state.performed~=nil) or nil
  if state.confirmed and not pc:IsBusy() then
   Debug.Event(c,"flute_confirmed",{guards=#bees,performed=state.performed~=nil})
   state.pending=nil;state.confirmed=nil;state.solo=true;unlock(q)
  else
   local elapsed=now-(state.requested or now)
   local hit=p.AnimState and p.AnimState:IsCurrentAnimation("hit")
   local remaining=math.max(0,Safety.Window(c)-elapsed)
   if hit then F.Interrupt(c,"hit_animation")
   elseif not state.performed and not state.confirmed and Safety.Imminent(q,queen,bees,pos,remaining) then F.Interrupt(c,"incoming_before_sleep")
   elseif elapsed>Safety.Window(c)+.5 and not pc:IsBusy() and not state.confirmed then F.Interrupt(c,"sleep_effect_missing")
   elseif not state.performed and elapsed>(c.Latency and c:Latency() or .1)+.4 and not Safety.Playing(p) and not state.confirmed then
    F.Interrupt(c,"play_animation_interrupted")
   elseif now>=state.pending then
    Debug.Event(c,"flute_timeout",{guards=#bees})
    F.Interrupt(c,"sleep_confirmation_timeout")
   else
    c.blocked=true;c.status="蜂后 · 正在吹奏，等待实际催眠结算";return true
   end
  end
 end
 if asleep and (state.solo or Status.Sleeping(queen)) then
  state.solo=true;q.stage="strike"
  if not state.in_solo then release(q);state.in_solo=true end
  return q:Strike(queen,pos,queen:GetPosition(),math.sqrt(pos:DistSq(queen:GetPosition())))
 end
 if not flute then F.Reset(q);q:Lure(now);return false end
 c.blocked=true;q.stage="flute"
 if now<(state.recover_until or 0) then
  move(q,queen,bees,now,"蜂后 · 吹奏中断，先脱离攻击再催眠",F.Range(flute));return true
 end
 local covered=F.Covered(pos,queen,bees,F.Range(flute))
 local ready,reason,eta=Safety.Ready(q,queen,bees,now)
 if not ready or not covered then
  Debug.Throttle(c,"flute_unsafe",.7,"flute_wait",{reason=not covered and "coverage" or reason,hit_eta=eta,window=Safety.Window(c),coverage_missing=Safety.Coverage(pos,queen,bees,F.Range(flute))})
  move(q,queen,bees,now,"蜂后 · 躲开攻击，寻找安全的共同催眠站位",F.Range(flute));return true
 end
 release(q)
 -- 等已发送的换装落地，不能让它在开始吹箫后覆盖动作。
 local pending=c.gear and c.gear.pending
 if pending then
  local held=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
  if held==pending.item then
   Debug.Equip(c,"ack",pending.item,pending.role,{latency=pending.senttime and now-pending.senttime or -1});c.gear.pending=nil
  elseif now<(pending.untiltime or now)+(c.Latency and c:Latency() or .1) then
   c.status="蜂后 · 等待已有换装完成再吹奏";return true
  else
   c.gear.pending=nil;c.actions:Stop();state.next_play=now+.2
   Debug.Event(c,"flute_wait",{reason="stale_equip_cancelled"});return true
  end
 end
 if now>=(state.next_play or 0) and not pc:IsBusy() then
  -- 先暂停原线程并清掉旧移动，再提交唯一PLAY；持锁到成功或明确中断。
  if c.bridge.PauseAttack then c.bridge:PauseAttack() end
  if c.actions and c.actions.Stop then c.actions:Stop() end
  c.last_action_kind=nil;c.last_point=nil
  if c.gear then c.gear.action_hold={owner=q,kind="queen_flute"} end
  state.requested=now;state.pending=now+math.max(4,2+Safety.Window(c));state.performed=nil;state.confirmed=nil
  if require("shadowself/control/actions").Self(p,flute,ACTIONS.PLAY) then
   Debug.Event(c,"flute_request",{guards=#bees,range=F.Range(flute),hit_eta=eta,window=Safety.Window(c)})
  else
   F.Interrupt(c,"PLAY_unavailable")
  end
 end
 c.status="蜂后 · 安全窗口内吹奏催眠"
 return true
end
return F
