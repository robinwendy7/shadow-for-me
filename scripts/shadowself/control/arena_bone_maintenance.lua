-- 参考2129374112：低耐久单次补燃料、冷却后择甲；只维护装备，不控制移动。
local A=require("shadowself/control/actions")
local B={reference="workshop-2129374112"}
local function percent(item)
 local f=item.components and item.components.fueled
 if f and f.GetPercent then return f:GetPercent() end
 local ii=item.replica and item.replica.inventoryitem
 local n=ii and ii.classified and ii.classified.percentused
 if n then local v=n:value();if v~=255 then return v/100 end end
end
local function scope(arena)
 local p=arena.player
 return arena.running and arena.instance and (arena.wave or 0)>=11 and p:IsValid()
  and not p:HasTag("playerghost") and not p:HasTag("corpse") and not p:HasTag("dead")
end
function B.External()
 local manager=rawget(_G,"ModManager")
 return manager and manager.GetMod and manager:GetMod(B.reference)~=nil or false
end
local function state(player)
 local arena=player._shadowself_arena_move_owner
 return arena and scope(arena) and arena.bone_maintenance or nil
end
function B.Busy(player)
 local s=state(player)
 return s and (s.pending~=nil and GetTime()<s.pending.deadline or s.repair_due and GetTime()<(s.repair_until or 0)) or false
end
-- 内部按名称取甲时认可当前这件骨甲，兼容外部Mod的多骨甲轮换。
function B.Select(player,item)
 if not item or item.prefab~="armorskeleton" then return item end
 local arena=player._shadowself_arena_move_owner
 if not arena or not scope(arena) then return item end
 local s=arena.bone_maintenance
 if s and s.pending and s.pending.item:IsValid() then return s.pending.item end
 local body=player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
 if body and body.prefab=="armorskeleton" and body:IsValid() and (percent(body) or 0)>0 then return body end
 return item
end
local function available(arena)
 local p=arena.player;local pc=p.components and p.components.playercontroller
 if not pc or pc:IsBusy() or p:HasTag("attack") or p:HasTag("hit") then return false end
 local inv=p.replica.inventory
 if inv.GetActiveItem and inv:GetActiveItem() then return false end
 if arena.pending_item or arena.equip_pending or arena.healing and arena.healing.pending then return false end
 if arena.stage11 and arena.stage11.buffs and arena.stage11.buffs.pending then return false end
 local c=arena.bridge and arena.bridge.coordinator
 if c and arena.bridge.Running and arena.bridge:Running() and (c.dodging or c.travel and c.travel.dodging) then return false end
 return true
end
local function trace(s,key,text)
 if s.logkey==key then return end
 s.logkey=key;print("[ShadowSelf][bone] "..text)
end
function B.Tick(arena)
 local s=arena.bone_maintenance
 if not s or not s.active or not scope(arena) then return end
 local p=arena.player;local inv=p.replica.inventory;local now=GetTime()
 if s.wave~=arena.wave or s.generation~=arena.generation or s.instance~=arena.instance then
  s.pending=nil;s.wave=arena.wave;s.generation=arena.generation;s.instance=arena.instance
 end
 local items=A.Items(p);local owned={};local fuel;local bones={};local observed={}
 local body=inv:GetEquippedItem(EQUIPSLOTS.BODY)
 for _,e in ipairs(items) do if e:IsValid() then
  owned[e]=true
  -- 已由实际库存枚举确认所有权；背包物品本就可能带INLIMBO，不能据此排除燃料。
  if e.prefab=="nightmarefuel" then fuel=e end
  if e.prefab=="armorskeleton" then
   local v=percent(e)
   if v then
    observed[e]=true
    local record=s.bones[e]
    if not record then record={value=v,ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1};s.bones[e]=record end
    if v<record.value-.001 then record.ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1 end
    record.value=v;bones[#bones+1]=e
   end
  end
 end end
 -- 同步护盾特效同样能确认骨甲刚消耗过一次防护。
 if body and s.bones[body] and TheSim then
  local pos=p:GetPosition()
  for _,fx in ipairs(TheSim:FindEntities(pos.x,0,pos.z,3,{"FX"})) do
   if (fx.prefab or ""):match("^shadow_shield%d$") and fx.entity and fx.entity.GetParent
    and fx.entity:GetParent()==p.entity and not s.shields[fx] then
    s.shields[fx]=true;s.bones[body].ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5)+.1
   end
  end
 end
 -- 先给参考Mod处理耐久事件；低耐久长期未修复时只做一次确认式兜底。
 local external=B.External()
 if external~=s.external then s.external=external;trace(s,"owner"..tostring(external),external and "owner=workshop-2129374112" or "owner=shadowself") end
 if external and not s.pending then
  local v=body and percent(body)
  if not s.external_wait or s.external_wait.item~=body or s.external_wait.value~=v then s.external_wait={item=body,value=v,since=now};s.external_fallback=nil end
  if now-s.external_wait.since<2.5 or now-(s.external_request or -math.huge)<2.5 then s.pending=nil;s.repair_due=nil;return end
  s.external_fallback=true
 elseif not external then s.external_wait=nil;s.external_fallback=nil end
 local pending=s.pending
 if pending then
  local v=percent(pending.item)
  if pending.kind=="equip" and body==pending.item then
   s.pending=nil;s.repair_due=nil;trace(s,"equip_ack"..tostring(pending.item.GUID),"equip_confirmed")
  elseif pending.kind=="fuel" and v and v>pending.before+.001 then
   s.serviced[pending.item]=v;s.pending=nil;s.repair_due=nil;s.failures=0
   trace(s,"fuel_ack"..tostring(now),string.format("refuel_confirmed=%.0f%%",v*100))
  elseif not owned[pending.item] or pending.kind=="fuel" and body~=pending.item or now>=pending.deadline then
   s.pending=nil;s.failures=(s.failures or 0)+1;s.next_try=now+(s.failures>=3 and 5 or 1)
   trace(s,"unconfirmed"..tostring(now),"action_unconfirmed="..pending.kind)
  else return end
 end
 if not body or body.prefab~="armorskeleton" or not observed[body] or not s.bones[body] or now<(s.next_try or 0) then s.repair_due=nil;return end
 local runtime=p._shadowself;local limit=runtime and runtime.options and runtime.options.bone_refuel or 25
 local reward=arena.stage11 and arena.stage11.reward
 if reward and (reward.opened or reward.pending) then s.repair_due=nil;return end
 local v=s.bones[body].value;local serviced=s.serviced[body]
 local due=limit>=0 and v<=limit/100 and not (serviced and v>=serviced-.001) and fuel~=nil
 if due and not s.repair_due then s.repair_due=true;s.repair_until=now+2 end
 if not due then s.repair_due=nil end
 if not available(arena) then
  if s.repair_due and now>=s.repair_until then s.repair_due=nil;s.next_try=now+1 end
  return
 end
 local function ready(e)
  local cd=e.components and e.components.cooldown
  return cd and cd.GetTimeToCharged and cd:GetTimeToCharged()<=0 or not (cd and cd.GetTimeToCharged) and now>=s.bones[e].ready
 end
 local best=body
 for _,e in ipairs(bones) do if not external and s.bones[e].value>0 and ready(e)
  and (not ready(best) or s.bones[e].value>s.bones[best].value+.001) then best=e end end
 if best~=body then
  s.pending={kind="equip",item=best,deadline=now+2}
  if not A.Self(p,best,ACTIONS.EQUIP) then s.pending=nil;s.next_try=now+1 end
  return
 end
 if not due then return end
 local token={kind="fuel",item=body,before=v,deadline=now+2};s.pending=token
 local function valid()
  return arena.bone_maintenance==s and s.active and scope(arena) and arena.wave==s.wave and arena.generation==s.generation
   and arena.instance==s.instance and (not B.External() or s.external_fallback and GetTime()-(s.external_request or -math.huge)>=2.5) and s.pending==token
   and not p:HasTag("attack") and body:IsValid() and fuel:IsValid() and inv:GetEquippedItem(EQUIPSLOTS.BODY)==body
   and (function() local a,b=false,false;for _,e in ipairs(A.Items(p)) do a=a or e==body;b=b or e==fuel end;return a and b end)()
 end
 if A.RefuelArmor(p,fuel,body,valid) then
  s.next_try=now+.5;trace(s,"fuel_sent"..tostring(now),string.format("refuel_request=%.0f%%",v*100))
 else s.pending=nil;s.next_try=now+1 end
end
function B.Start(arena)
 if not scope(arena) or arena.bone_maintenance then return end
 local start=rawget(_G,"StartThread")
 if not start then return end
 local s={active=true,bones=setmetatable({},{__mode="k"}),serviced=setmetatable({},{__mode="k"}),shields=setmetatable({},{__mode="k"})}
 arena.bone_maintenance=s
 if arena.player.ListenForEvent then
  s.external_listener=function() s.external_request=GetTime() end
  arena.player:ListenForEvent("AddFuelToArmorskeleton",s.external_listener)
 end
 s.thread=start(function()
  while s.active and scope(arena) do B.Tick(arena);Sleep(.2) end
  s.active=false;s.pending=nil
 end)
end
function B.Stop(arena)
 local s=arena.bone_maintenance
 if not s then return end
 s.active=false;s.pending=nil;arena.bone_maintenance=nil
 if s.external_listener and arena.player.RemoveEventCallback then arena.player:RemoveEventCallback("AddFuelToArmorskeleton",s.external_listener) end
 if s.thread and s.thread.co~=coroutine.running() then KillThreadsWithID(s.thread.id);s.thread:SetList(nil) end
 s.thread=nil
end
function B.Sync(arena)
 if scope(arena) then B.Start(arena) else B.Stop(arena) end
end
return B
