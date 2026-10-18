local S={}
function S.Frozen(e)
 return e and (e:HasTag("frozen") or e.sg and e.sg:HasStateTag("frozen") or e.AnimState and (e.AnimState:IsCurrentAnimation("frozen") or e.AnimState:IsCurrentAnimation("frozen_loop_pst"))) or false
end
-- 客户端通常没有 sleeper 组件，使用原版 sleep_pre/loop；sleep_pst 已开始醒来。
function S.Sleeping(e)
 if not e then return false end
 local a=e.AnimState
 if a and a:IsCurrentAnimation("sleep_pst") then return false end
 return e:HasTag("sleeping") or e.sg and e.sg:HasStateTag("sleeping")
  or a and (a:IsCurrentAnimation("sleep_pre") or a:IsCurrentAnimation("sleep_loop")) or false
end
function S.Controlled(e) return S.Frozen(e) or e and e:HasTag("fire") end
return S
