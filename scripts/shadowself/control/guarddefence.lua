-- 冻蜂是独立支持流程，不能等已暂停的走A线程替它处理蜂后攻击。
local G={}
function G.Tick(q,queen,now)
 local c=q.c;local p=c.player;local a=queen.AnimState
 local frame=a.GetCurrentAnimationFrame and a:GetCurrentAnimationFrame() or 0
 local winding=a:IsCurrentAnimation("atk") and frame<14
 local hit=(TUNING.BEEQUEEN_HIT_RANGE or 6)+(p.GetPhysicsRadius and p:GetPhysicsRadius(0) or .5)+.25
 local inside=p:GetPosition():DistSq(queen:GetPosition())<(hit+.15)^2
 local state=q.guard_escape
 if winding and inside then
  if not state then
   require("shadowself/control/queenroute").Clear(q)
   state={hand=c.gear:Mobile(c.snapshot) or c.gear.forced_weapon};q.guard_escape=state;c.next_move=nil
   require("shadowself/control/queendebug").Event(c,"guard_dodge_start",{queen_frame=frame,pos=require("shadowself/control/queendebug").Point(p:GetPosition())})
  end
  local latency=c.Latency and c:Latency() or .1
  state.untiltime=now+(14-frame)*(FRAMES or 1/30)+latency
  -- 与蜂后本体走位共用实际径向逃脱算法，不再在守卫环绕候选里折中躲避。
  if not state.point then
  local data=require("shadowself/control/queenattack")(c,queen,false)
  state.point=data.fn and data:fn(nil,nil,0,hit+.5) or nil
  if not state.point or state.point:DistSq(queen:GetPosition())<hit^2 then
   local Nav=require("shadowself/control/navigation");local qp=queen:GetPosition();local pos=p:GetPosition();local best,score
   for i=0,23 do
    local angle=i*math.pi/12;local point=Vector3(qp.x+math.cos(angle)*(hit+.5),0,qp.z+math.sin(angle)*(hit+.5))
    if c.actions:SafePoint(point) then
     local risk=Nav.Risk(c,point,queen)*100+pos:DistSq(point)
     if not score or risk<score then best,score=point,risk end
    end
   end
   state.point=best
  end
  end
 end
 if state and now<(state.untiltime or 0) then
  require("shadowself/control/guardhands").Set(q,state.hand,"escape")
  if state.point then c:Move(state.point,q.casting_guard and "蜂后 · 冻蜂先停手，立即躲本体攻击" or "蜂后 · 暂停绕蜜，先躲本体攻击") end
  c.blocked=true;return true
 end
 if state then require("shadowself/control/queendebug").Event(c,"guard_dodge_end",{queen_frame=frame});q.next_support=math.min(q.next_support or now,now) end
 q.guard_escape=nil;return false
end
return G
