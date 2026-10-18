-- 第一阶段留一只守卫：只读观察冻结转变，达到高抗性后轮换新个体。
local Status=require("shadowself/control/status")
local Debug=require("shadowself/control/queendebug")
local G={MAX_FREEZES=3,MAX_SHOTS=4,PROJECTILE_WAIT=1}
function G.Observe(q,bees,now)
 q.guard_stats=q.guard_stats or {}
 for e in pairs(q.guard_stats) do if not e:IsValid() or e:HasTag("isdead") or e:HasTag("dead") then q.guard_stats[e]=nil end end
 local seen={}
 for _,e in ipairs(bees) do
  seen[e]=true
  local s=q.guard_stats[e] or {freezes=0,shots=0};q.guard_stats[e]=s
  local frozen=Status.Frozen(e)
  if frozen and not s.frozen then
   s.freezes=s.freezes+1;s.shots=0
   Debug.Event(q.c,"guard_frozen",{guard=Debug.Entity(e),freezes=s.freezes,estimated_resistance=math.min(5,2+s.freezes*.5)})
  end
  s.frozen=frozen
 end
 if q.recycle_guard and (not seen[q.recycle_guard] or not q.recycle_guard:IsValid() or q.recycle_guard:HasTag("isdead") or q.recycle_guard:HasTag("dead")) then
  Debug.Event(q.c,"guard_replaced",{guard=Debug.Entity(q.recycle_guard)});q.recycle_guard=nil
 end
end
function G.Recycle(q,bee,now)
 if q.recycle_guard then return q.recycle_guard end
 if not bee or Status.Controlled(bee) then return nil end
 local s=q.guard_stats and q.guard_stats[bee]
 if not s then return nil end
 local reason=s.freezes>=G.MAX_FREEZES and "freeze_cycles" or
   s.shots>=G.MAX_SHOTS and now-(s.last_shot or now)>=G.PROJECTILE_WAIT and "four_shots_without_freeze" or nil
 -- 客户端无freezable组件时仅以观察计数判断，不假装能读取服务端隐藏抗性。
 if reason then
  q.recycle_guard=bee
  Debug.Event(q.c,"guard_recycle",{guard=Debug.Entity(bee),reason=reason,freezes=s.freezes,shots=s.shots})
  return bee
 end
end
function G.OnAction(c,data)
 local q=c and c.beequeen
 if not q or q.phase~=1 or type(data)~="table" then return end
 local act=data;if type(data.action)=="table" and data.action.action then act=data.action end
 local target=act.target
 if act.action~=ACTIONS.ATTACK or not target or target.prefab~="beeguard" or q.recycle_guard==target then return end
 local item=act.invobject or c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
 if not item or item.prefab~="icestaff" then return end
 q.guard_stats=q.guard_stats or {};local s=q.guard_stats[target] or {freezes=0,shots=0};q.guard_stats[target]=s
 s.shots=s.shots+1;s.last_shot=GetTime()
 Debug.Event(c,"guard_ice_shot",{guard=Debug.Entity(target),shots=s.shots,freezes=s.freezes})
end
return G
