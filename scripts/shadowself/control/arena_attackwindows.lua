-- 本次指定的群怪扑击和第十关挥击：状态结束才交回输出，仍借用原生DoDodge。
local Nav=require("shadowself/control/navigation")
local W={}
local function dragon(c,e)
 if not c or not c.plan or not c.plan.arena or not c.plan.arena_wave or c.plan.arena_wave()~=10
  or not e or e.prefab~="dragonfly" or not e.AnimState then return end
 c.dragon_windows=c.dragon_windows or {};local s=c.dragon_windows[e] or {};c.dragon_windows[e]=s
 local a=e.AnimState;local atk=a:IsCurrentAnimation("atk");local f=atk and a:GetCurrentAnimationFrame() or 0
 if atk then
  if not s.atk or f<(s.frame or 0) then s.guarded=nil end
  local finish=15+require("shadowself/control/nettiming").Frames(c)+2
  s.phase=(s.guarded and f>=15 or f>finish) and "punish" or "evade"
 elseif s.atk or s.phase=="punish" then
  s.phase=(a:IsCurrentAnimation("idle") or a:IsCurrentAnimation("walk_loop") or a:IsCurrentAnimation("walk_pre")) and "punish" or nil
 end
 s.atk=atk;s.frame=f;return s
end
function W.Guarded(c,e)
 local s=dragon(c,e);if s and s.atk then s.guarded=true end
end
local function slurper(c,e)
 if not c or not c.plan or not c.plan.arena or not e or e.prefab~="slurper" or not e.AnimState then return end
 if not e:IsValid() or e:HasTag("INLIMBO") or e:HasTag("dead") or e:HasTag("isdead") then return end
 c.slurper_routes=c.slurper_routes or {}
 local s=c.slurper_routes[e]
 if not s then s={phase="bait"};c.slurper_routes[e]=s end
 local a=e.AnimState;local name
 for _,n in ipairs({"atk","headslurp","headslurpmiss"}) do if a:IsCurrentAnimation(n) then name=n;break end end
 local frame=(name=="atk" or name=="headslurp") and a:GetCurrentAnimationFrame() or 0
 if name=="atk" or name=="headslurp" then
  if s.anim~=name or frame<(s.frame or 0) then
   local rotation=e.Transform:GetRotation()*math.pi/180
   s.nx=math.sin(rotation);s.nz=math.cos(rotation)
   if name=="atk" then s.side=nil end
  end
  s.phase="evade"
 elseif name=="headslurpmiss" or s.phase=="evade" then
  -- 扑头落空是明确输出窗；原版HatTest不成立时翻滚也可能直接返回idle。
  s.phase="punish"
 end
 s.anim=name;s.frame=frame
 return s,name
end
function W.Committed(c,e)
 local s=slurper(c,e) or dragon(c,e)
 return s and s.phase=="punish" or false
end
local function active(c,e)
 if not c or not c.plan or not c.plan.arena or not e or not e.AnimState then return end
 local wave=c.plan.arena_wave and c.plan.arena_wave()
 if e.prefab=="slurper" then
  local s,name=slurper(c,e)
  if s and s.phase=="evade" then return name,"slurper" end
 elseif wave==10 and e.prefab=="dragonfly" then
  local s=dragon(c,e);if s and s.phase=="evade" then return "atk","dragonfly" end
 end
end
function W.Block(c,e) return active(c,e)~=nil end
function W.Dodge(c,e,base)
 local name,kind=active(c,e)
 if not name then
  if W.Committed(c,e) then return false end
  return base
 end
 local data={atkanim=name,noattack=true,exclusive=true,update=true,point="target",dist=kind=="slurper" and 4.2 or 6}
 data.breakdodgefn=function() return not active(c,e) end
 if kind=="slurper" then
  local state=c.slurper_routes[e]
  data.fn=function()
   local p=c.player:GetPosition();local ep=e:GetPosition()
   local side=(p.x-ep.x)*state.nx+(p.z-ep.z)*state.nz
   state.side=state.side or (side<0 and -1 or 1)
   -- 滚动20帧启动、30帧近身命中；随实体推进刷新侧移距离，不能守旧的固定落点。
   local width=2+c.player:GetPhysicsRadius(0)+.7
   if math.abs(side)>=width then return p end
   for _,sign in ipairs({state.side,-state.side}) do
    local amount=width-side*sign
    local q=Vector3(p.x+state.nx*amount*sign,0,p.z+state.nz*amount*sign)
    if Nav.Safe(c,q,e) then state.side=sign;return q end
   end
   return Nav.Select(c,Vector3(p.x+state.nx*width*state.side,0,p.z+state.nz*width*state.side),e)
  end
 elseif base then
  -- 保留原版计算的离开距离，不缩短已有的狂暴火焰范围。
  for k,v in pairs(base) do if data[k]==nil then data[k]=v end end
  data.dist=math.max(6,type(base.dist)=="number" and base.dist or 0)
 end
 return data
end
return W
