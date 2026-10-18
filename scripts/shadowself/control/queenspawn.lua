-- 下崽动画结束且守卫名单稳定后，才允许清蜂/催眠；等待期间仍避近身威胁。
local S={SETTLE=.4}
local function anim(e,name) return e.AnimState and e.AnimState:IsCurrentAnimation(name) end
function S.Tick(q,queen,bees,now)
 if q.phase and q.phase>=3 then q.spawn_wait=nil;return false end
 local spawning=anim(queen,"spawn")
 for _,bee in ipairs(bees) do spawning=spawning or anim(bee,"spawn_in") end
 local state=q.spawn_wait
 if spawning and not state then
  state={roster={}};q.spawn_wait=state
  require("shadowself/control/queenflute").Reset(q)
  require("shadowself/control/guardhands").Release(q)
  if q.c.actions and q.c.actions.Stop then q.c.actions:Stop() end
  require("shadowself/control/queendebug").Event(q.c,"spawn_wait_start",{guards=#bees,phase=q.phase})
 end
 if not state then return false end
 local changed=false;local roster={}
 for _,bee in ipairs(bees) do roster[bee]=true;if not state.roster[bee] then changed=true end end
 for bee in pairs(state.roster) do if not roster[bee] then changed=true end end
 state.roster=roster
 if spawning or changed then state.untiltime=now+S.SETTLE end
 if not spawning and now>=(state.untiltime or now) then
  q.spawn_wait=nil
  require("shadowself/control/queendebug").Event(q.c,"spawn_wait_end",{guards=#bees,phase=q.phase})
  return false
 end
 local c=q.c;local pos=c.player:GetPosition();q:Target(queen);c.blocked=true;q.stage="spawn_wait"
 c.status="蜂后 · 等待本轮下崽结束，再清蜂或催眠"
 -- 正在生成的蜂不动；已存在的醒蜂仍可能攻击，不能原地硬等。
 local nearest,distance;local Status=require("shadowself/control/status")
 for _,bee in ipairs(bees) do
  if not anim(bee,"spawn_in") and not Status.Controlled(bee) then
   local d=pos:DistSq(bee:GetPosition())
   if not distance or d<distance then nearest,distance=bee,d end
  end
 end
 if nearest and distance<4^2 then
  if not state.point or now>=(state.next_route or 0) or pos:DistSq(state.point)<.25 then
   local bp=nearest:GetPosition();local dx,dz=pos.x-bp.x,pos.z-bp.z;local len=math.sqrt(dx*dx+dz*dz)
   if len<.01 then dx,dz,len=1,0,1 end
   state.point=require("shadowself/control/navigation").Select(c,Vector3(pos.x+dx/len*3,0,pos.z+dz/len*3),queen)
   state.next_route=now+.2
  end
  if state.point then require("shadowself/control/queendashroute").Begin(q,state);c:Move(state.point,c.status);state.moving=true end
 elseif state.moving then
  if c.actions and c.actions.Stop then c.actions:Stop() end
  state.moving=nil;state.point=nil
 end
 return true
end
return S
