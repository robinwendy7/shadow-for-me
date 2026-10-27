-- 文档指定的瓦器人与天体后裔机制；由现有监督tick调用，不启动新线程。
local A=require("shadowself/control/actions")
local I=require("shadowself/control/arena_inventory")
local Nav=require("shadowself/control/navigation")
local M={}
local robot="wagboss_robot"
local champion="alterguardian_phase4_lunarrift"
local missile_anims={"atk_missile_pre1","atk_missile_pre2","atk_missile","atk_missile_idle","atk_missile_hit","atk_missile_pst"}
local nova_anims={"atk_burst_pre","atk_burst_charge_loop","atk_burst_charge_to_shoot","atk_burst_shoot_loop","atk_burst_pst"}
local names={orangestaff=true,cane=true,armorskeleton=true,voidclothhat=true,voidcloth_scythe=true,voidcloth_kit=true,armorsnurtleshell=true}
local function live(e)
 local h=e and e.replica and e.replica.health
 return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
local function anim(e,n) return e and e.AnimState and e.AnimState:IsCurrentAnimation(n) end
local function any(e,list) for _,n in ipairs(list) do if anim(e,n) then return true end end;return false end
local function frame(e) return e and e.AnimState and e.AnimState:GetCurrentAnimationFrame() or 0 end
local function distance(a,b) return math.sqrt(a:DistSq(b)) end
local function busy(c) local pc=c.player.components.playercontroller;return pc.IsBusy and pc:IsBusy() end
local function items(c) return A.Items(c.player) end
local function item(c,name,broken)
 for _,e in ipairs(items(c)) do if e.prefab==name and e:IsValid() and (broken or not e:HasTag("broken") and I.Condition(e)>0) then return e end end
end
local function equipped(c,slot) return c.player.replica.inventory:GetEquippedItem(slot) end
local function context(c) return c.doc_boss_state end
local function missing(s,name)
 s.missing_item=name
 if s.last_missing~=name then s.last_missing=name;print("[ShadowSelf][doc_boss] prefab="..s.target.prefab.." missing="..name) end
end
function M.Required(c,e)
 return e and (e.prefab==champion or e.prefab==robot and c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==15) and live(e) or false
end
function M.Want(c,e)
 local target=c.h and c.h.ent
 if not M.Required(c,target) then
  for _,v in ipairs(c.enemies or {}) do if M.Required(c,v) then target=v;break end end
 end
 return M.Required(c,target) and names[e.prefab] or false
end
function M.Items(c,e) return M.Required(c,e) and names or nil end
local function state(c,e)
 local s=c.doc_boss_state
 if not s or s.target~=e then
  if s then M.Stop(c) end
  s={target=e};c.doc_boss_state=s
 end
 return s
end
local function phase(c,s,name)
 if s.phase~=name then
  if s.phase=="hat_repair" then s.repair=nil end
  s.phase=name;s.next_action=nil;s.blink=nil
  if c.bridge and c.bridge.PauseAttack then c.bridge:PauseAttack() end
  c.blocked=true
  print("[ShadowSelf][doc_boss] prefab="..s.target.prefab.." phase="..name)
 end
end
local function ownhand(c,s,e)
 if not c.gear then return end
 if not s.owns_hand then s.old_forced=c.gear.forced_weapon;s.owns_hand=true end
 s.forced=e;c.gear.forced_weapon=e
end
local function releasehand(c,s)
 if s and s.owns_hand and c.gear and c.gear.forced_weapon==s.forced then c.gear.forced_weapon=s.old_forced end
 if s then s.owns_hand=nil;s.forced=nil;s.old_forced=nil end
end
local function equip(c,s,e,slot)
 if not e then return false end
 s.equip_intent=s.equip_intent or {};s.equip_intent[slot]=e
 if equipped(c,slot)==e then return true end
 if slot==EQUIPSLOTS.HANDS then ownhand(c,s,e) end
 if not busy(c) and GetTime()>=(s.next_action or 0) then
  if A.Self(c.player,e,ACTIONS.EQUIP,function() return c.doc_boss_state==s and s.equip_intent[slot]==e end) then s.next_action=GetTime()+.4 end
 end
 return false
end
local function safe(c,q,e)
 if not q or not c.actions:SafePoint(q) then return false end
 for _,zone in ipairs(M.Zones(c)) do if q:DistSq(zone.pos)<zone.radius^2 then return false end end
 return Nav.Safe(c,q,e)
end
-- Blink checks its destination, not the intervening walking route (which may cross a leg or fissures).
local function landing(c,q,e)
 local map=TheWorld and TheWorld.Map
 if not q or not map or not map:IsPassableAtPoint(q.x,0,q.z)
  or map.IsOceanAtPoint and map:IsOceanAtPoint(q.x,0,q.z)
  or map.IsGroundTargetBlocked and map:IsGroundTargetBlocked(q) then return false end
 local p=c.player:GetPosition()
 if IsTeleportingPermittedFromPointToPoint and not IsTeleportingPermittedFromPointToPoint(p.x,0,p.z,q.x,0,q.z) then return false end
 for _,zone in ipairs(M.Zones(c)) do if q:DistSq(zone.pos)<zone.radius^2 then return false end end
 return Nav.Risk(c,q,e)==0
end
local function move(c,s,q,label)
 if not q or not safe(c,q,s.target) then
  local hazards={};for _,z in ipairs(c.hazards or {}) do hazards[#hazards+1]=z end
  for _,z in ipairs(M.Zones(c)) do hazards[#hazards+1]=z end
  local route=setmetatable({hazards=hazards},{__index=c})
  q=Nav.Select(route,q or c.player:GetPosition(),s.target)
  if not safe(c,q,s.target) then q=Nav.Escape(route,c.player:GetPosition(),s.target) or c.player:GetPosition() end
 end
 if c.travel then c.travel:BeginDodge(c.snapshot) end
 c:Move(q,label);return "move",s.target
end
local function allentities(c)
 local p=c.player:GetPosition();local result,seen={},{}
 for _,list in ipairs({c.plan and c.plan.arena_entities and c.plan.arena_entities() or {},c.enemies or {},TheSim:FindEntities(p.x,0,p.z,55)}) do
  for _,e in ipairs(list) do if e:IsValid() and not seen[e] then seen[e]=true;result[#result+1]=e end end
 end
 return result
end
function M.Zones(c,entities)
 local out={};local radius=math.sqrt(8)+(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)+.15
 for _,e in ipairs(entities or allentities(c)) do
  if e.prefab=="wagboss_beam_fx" and live(e) and not anim(e,"beam_pst") then
   out[#out+1]={pos=e:GetPosition(),radius=3+(c.player.GetPhysicsRadius and c.player:GetPhysicsRadius(0) or .5)+.3,source=e,doc_beam=true}
  elseif e.prefab=="alterguardian_lunar_fissures" and e:IsValid() then
   local ending=false
   for i=1,4 do if anim(e,"tile"..i.."_pst") then ending=true end end
   if not ending then out[#out+1]={pos=e:GetPosition(),radius=radius,source=e,doc_fissure=true} end
  end
 end
 return out
end
local function corner(c,e)
 local center=c.plan and c.plan.arena_center and c.plan.arena_center()
 center=center or e:GetPosition()
 local p=c.player:GetPosition();local best,score
 for _,r in ipairs({18,16,14}) do
  for _,x in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
   local q=Vector3(center.x+x*r,0,center.z+z*r)
   if p:DistSq(q)>4^2 and p:DistSq(q)<=36^2 and landing(c,q,e) then
    local value=q:DistSq(e:GetPosition())-p:DistSq(q)*.05
    if not score or value>score then best,score=q,value end
   end
  end end
  if best then break end
 end
 return best
end
local function farpoint(c,e)
 local p=c.player:GetPosition();local ep=e:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
 if d<.01 then dx,dz,d=1,0,1 end
 local q=Vector3(ep.x+dx/d*14,0,ep.z+dz/d*14)
 return safe(c,q,e) and q or corner(c,e)
end
local function support(c,s,e)
 if s.missing_item or s.no_landing then return move(c,s,farpoint(c,e),"瓦器人／天体后裔 · 缺少关键工具或安全落点，先撤离再补捡") end
 return "support",e
end
-- Completion is observed position near the requested destination, never callback return or timeout.
local function blink(c,s,q)
 if not q or not landing(c,q,s.target) then s.blink=nil;s.no_landing=true;return false end
 local p=c.player:GetPosition();local pending=s.blink
 if pending and pending.point:DistSq(q)>.1^2 then s.blink=nil;pending=nil end
 if pending then
  if p:DistSq(pending.point)<=2.5^2 and p:DistSq(pending.origin)>=2^2 then s.blink=nil;return true end
  if GetTime()<pending.deadline then return false end
  s.blink=nil -- retry later from the current position; no fictitious success
 end
 local staff=item(c,"orangestaff")
 if not staff then missing(s,"orangestaff");return false end
 ownhand(c,s,staff)
 if equip(c,s,staff,EQUIPSLOTS.HANDS) and not busy(c) and GetTime()>=(s.next_blink or 0) then
  local pending={origin=Vector3(p.x,0,p.z),point=q,deadline=GetTime()+1.8};s.blink=pending
  if landing(c,q,s.target) and A.Ground(c.player,q,ACTIONS.BLINK,function()
   return c.doc_boss_state==s and s.blink==pending and live(s.target) and equipped(c,EQUIPSLOTS.HANDS)==staff and landing(c,q,s.target)
  end) then
   s.next_blink=GetTime()+.5
  else s.blink=nil end
 end
 return false
end
local function shell(c)
 local p=c.player
 -- shell_enter/idle/hit are server state names; these are the actual networked animations.
 return p:HasTag("shell") or p.sg and p.sg:HasStateTag("shell")
  or anim(p,"hideshell") or anim(p,"hideshell_idle") or anim(p,"hitshell")
end
local function missiles(c,e)
 if any(e,missile_anims) then return true end
 for _,v in ipairs(allentities(c)) do if live(v) and (v.prefab=="wagboss_missile" or v.prefab=="wagboss_missile_projectile") then return true end end
 return false
end
local function setup(c,s,e)
 if e.prefab~=robot then return true end
 -- Missing items are preparation, never a successful loadout acknowledgement.
 for _,name in ipairs({"armorskeleton","voidclothhat","voidcloth_scythe","orangestaff","armorsnurtleshell","voidcloth_kit"}) do
  if not item(c,name) then missing(s,name);return false end
 end
 for _,spec in ipairs({{"armorskeleton",EQUIPSLOTS.BODY},{"voidclothhat",EQUIPSLOTS.HEAD},{"voidcloth_scythe",EQUIPSLOTS.HANDS}}) do
  local v=item(c,spec[1]);if spec[2]==EQUIPSLOTS.HANDS then ownhand(c,s,v) end
  if not equip(c,s,v,spec[2]) then return false end
 end
 return true
end
local function repair(c,s,hat)
 local condition=I.Condition(hat);local pending=s.repair
 if pending then
  if hat:IsValid() and not hat:HasTag("broken") and I.Condition(hat)>pending.before then s.repair=nil;return true end
  if GetTime()<pending.deadline then return false end
  s.repair=nil
 end
 local kit=item(c,"voidcloth_kit")
 if not kit then missing(s,"voidcloth_kit");return false end
 if busy(c) or GetTime()<(s.next_repair or 0) then return false end
 local picker=c.player.components.playeractionpicker;local pc=c.player.components.playercontroller
 for _,right in ipairs({true,false}) do
  for _,act in ipairs(picker:GetUseItemActions(hat,kit,right) or {}) do if act.action==ACTIONS.REPAIR then
   act._shadowself_native=true
   local pending={before=condition,deadline=GetTime()+2};s.repair=pending
   if pc.ismastersim then pc:DoAction(act)
   else
    local sent=false
    local function send()
     if sent or c.doc_boss_state~=s or s.repair~=pending or s.phase~="hat_repair" or not hat:IsValid() or not kit:IsValid() then return end
     sent=true;SendRPCToServer(RPC.ControllerUseItemOnItemFromInvTile,ACTIONS.REPAIR.code,hat,kit,ACTIONS.REPAIR.mod_name)
    end
    if pc.locomotor then
     if not pc:CanLocomote() then return false end
     act.preview_cb=send;pc.locomotor:PreviewAction(act,true)
    else
     if act.action.pre_action_cb then act.action.pre_action_cb(act) end;send()
    end
   end
   s.next_repair=GetTime()+.5;return false
  end end
 end
 return false
end
local function chooseleg(c,e)
 local p=c.player:GetPosition();local best,score
 for _,leg in ipairs(allentities(c)) do if leg.prefab=="wagboss_robot_leg" and live(leg) and leg:HasTag("lunarsupernovablocker") then
  local q=leg:GetPosition();local bp=e:GetPosition();local dx,dz=q.x-bp.x,q.z-bp.z;local d=math.sqrt(dx*dx+dz*dz)
  if d>2 then
   local r=leg:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(0)+.6
   local goal=Vector3(q.x+dx/d*r,0,q.z+dz/d*r)
   if r<4 and landing(c,goal,e) then
    local v=p:DistSq(goal);if not score or v<score then best,score={entity=leg,point=goal},v end
   end
  end
 end end
 return best
end
local function sheltervalid(c,e,leg,q)
 if not leg or not live(leg) or not leg:HasTag("lunarsupernovablocker") or not q then return false end
 local src=e:GetPosition();local b=leg:GetPosition();local vx,vz=q.x-src.x,q.z-src.z;local lx,lz=b.x-src.x,b.z-src.z
 local v2=vx*vx+vz*vz;local l2=lx*lx+lz*lz
 if l2>=v2 or q:DistSq(b)>4^2 then return false end
 local cross=math.abs(vx*lz-vz*lx)/math.sqrt(v2)
 return cross<leg:GetPhysicsRadius(0)*.85 and landing(c,q,e)
end
function M.Shelter(c,e) return chooseleg(c,e) end
local function championtick(c,s,e)
 local nova=any(e,nova_anims) or e:HasTag("supernova")
 if nova then
  if not s.nova then s.nova={origin=c.player:GetPosition()};phase(c,s,"nova_shelter") end
  local n=s.nova
  if not n.leg or not sheltervalid(c,e,n.leg,n.point) then
   local chosen=chooseleg(c,e)
   if chosen then n.leg=chosen.entity;n.point=chosen.point end
  end
  if not n.point then return move(c,s,farpoint(c,e),"天体后裔 · 未确认瓦器人腿遮挡，先撤离超新星") end
  if c.player:GetPosition():DistSq(n.point)>1.2^2 then
   blink(c,s,n.point);return support(c,s,e)
  end
  -- The leg must actually lie between source and player, not merely be nearby.
  if not sheltervalid(c,e,n.leg,c.player:GetPosition()) then n.point=nil;return "support",e end
  if s.blink then blink(c,s,n.point) end
  phase(c,s,"nova_wait");return "support",e
 elseif s.nova then
  local origin=s.nova.origin
  phase(c,s,"nova_return")
  if origin and landing(c,origin,e) and c.player:GetPosition():DistSq(origin)>3^2 then
   if not blink(c,s,origin) then return support(c,s,e) end
  end
  s.nova=nil;s.phase=nil;releasehand(c,s)
 end
 if anim(e,"taunt") then
  phase(c,s,"slam_bait")
  local leg=chooseleg(c,e);local ep=e:GetPosition();local p=c.player:GetPosition()
  local q=leg and leg.entity:GetPosition() or p
  local dx,dz=ep.x-q.x,ep.z-q.z;local d=math.sqrt(dx*dx+dz*dz);if d<.01 then dx,dz,d=1,0,1 end
  s.bait=Vector3(ep.x+dx/d*7,0,ep.z+dz/d*7)
  return move(c,s,s.bait,"天体后裔 · 吼叫时在瓦器人腿相反方向勾引")
 elseif anim(e,"slam") then
  if s.phase~="slam_cross" then
   phase(c,s,"slam_cross");local ep=e:GetPosition();local p=c.player:GetPosition();local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
   if d<.01 then dx,dz,d=1,0,1 end
   s.cross=Vector3(ep.x-dx/d*7,0,ep.z-dz/d*7)
  end
  if frame(e)<78 or not safe(c,c.player:GetPosition(),e) then return move(c,s,s.cross,"天体后裔 · 拍地前径直穿至对立面，避开后续裂隙") end
  s.phase=nil;s.cross=nil;releasehand(c,s);return nil
 elseif s.phase=="slam_cross" or s.phase=="slam_bait" then s.phase=nil;s.cross=nil;releasehand(c,s) end
end
function M.Target(c,e)
 if M.Required(c,e) then return e end
 local current=context(c)
 if current and M.Required(c,current.target) then return current.target end
 for _,v in ipairs(c.enemies or {}) do if M.Required(c,v) then return v end end
end
function M.Tick(c,e)
 e=M.Target(c,e)
 if not M.Required(c,e) then if context(c) then M.Stop(c) end;return end
 local s=state(c,e)
 s.missing_item=nil;s.no_landing=nil
 if e.prefab==champion then return championtick(c,s,e) end
 local signal=anim(e,"atk_signal_pre") or anim(e,"atk_signal_loop")
 if signal and not s.signal_seen then s.signal_seen=true;s.beam_goal=corner(c,e);phase(c,s,"beam_blink") end
 if not signal then s.signal_seen=nil end
 if s.phase=="beam_blink" then
  if not landing(c,s.beam_goal,e) then s.beam_goal=corner(c,e) end
  if blink(c,s,s.beam_goal) then phase(c,s,"beam_wait") end
  return support(c,s,e)
 end
 if s.phase=="beam_wait" then
  local beams=signal;local threat
  for _,v in ipairs(allentities(c)) do if v.prefab=="wagboss_beam_fx" and live(v) and not anim(v,"beam_pst") then
   beams=true
   if c.player:GetPosition():DistSq(v:GetPosition())<6^2 then threat=v end
  end end
  if threat then
   s.beam_jumps=s.beam_jumps or setmetatable({},{__mode="k"})
   if anim(threat,"beam_pre") and frame(threat)>=28 and not s.beam_jumps[threat] then
    s.beam_jumps[threat]=true;s.beam_goal=corner(c,e);phase(c,s,"beam_blink")
    blink(c,s,s.beam_goal);return support(c,s,e)
   end
   -- Beam pre tracks the player until its animation ends: never wait motionless in its footprint.
   local p=c.player:GetPosition();local q=threat:GetPosition();local dx,dz=p.x-q.x,p.z-q.z;local d=math.sqrt(dx*dx+dz*dz)
   if d<.01 then local b=e:GetPosition();dx,dz=p.x-b.x,p.z-b.z;d=math.sqrt(dx*dx+dz*dz);if d<.01 then dx,dz,d=1,0,1 end end
   releasehand(c,s)
   return move(c,s,Vector3(p.x+dx/d*5,0,p.z+dz/d*5),"瓦器人 · 光束仍跟踪，继续离开预警范围")
  end
  if any(e,missile_anims) then s.phase=nil;s.beam_goal=nil;releasehand(c,s)
  elseif beams then s.beam_quiet=nil;return "support",e
  else
   s.beam_quiet=s.beam_quiet or GetTime()
   if GetTime()-s.beam_quiet<.8 then return "support",e end
   s.phase=nil;s.beam_goal=nil;s.beam_quiet=nil;releasehand(c,s)
  end
 end
 local firing=missiles(c,e)
 if not s.missile and firing then s.missile={goal=corner(c,e)};phase(c,s,"missile_blink") end
 if s.missile then
  if firing then s.missile.quiet=nil else s.missile.quiet=s.missile.quiet or GetTime() end
  if s.missile.quiet and GetTime()-s.missile.quiet>=.8 then
   phase(c,s,"missile_restore")
   if shell(c) then
    if GetTime()>=(s.next_exit or 0) then local p=c.player:GetPosition();A.Move(c.player,Vector3(p.x+.6,0,p.z));s.next_exit=GetTime()+.5 end
    return "support",e
   end
   local bone=item(c,"armorskeleton")
   if not bone then missing(s,"armorskeleton");return support(c,s,e) end
   if not equip(c,s,bone,EQUIPSLOTS.BODY) then return "support",e end
   s.missile=nil;s.phase=nil;releasehand(c,s)
  elseif s.phase=="missile_blink" then
   if not landing(c,s.missile.goal,e) then s.missile.goal=corner(c,e) end
   if blink(c,s,s.missile.goal) then phase(c,s,"missile_shell") end
   return support(c,s,e)
  else
   if not shell(c) and s.phase=="missile_hold" then phase(c,s,"missile_shell") end
   local armor=item(c,"armorsnurtleshell")
   if not armor then missing(s,"armorsnurtleshell");return support(c,s,e) end
   if armor and equip(c,s,armor,EQUIPSLOTS.BODY) and not shell(c) and not busy(c) and GetTime()>=(s.next_shell or 0) then
    if A.Self(c.player,armor,ACTIONS.USEITEM,function() return c.doc_boss_state==s and s.missile~=nil and s.phase=="missile_shell" and equipped(c,EQUIPSLOTS.BODY)==armor and not shell(c) end) then s.next_shell=GetTime()+.5 end
   end
   if shell(c) then phase(c,s,"missile_hold") end
   return "support",e
  end
 end
 local hat=item(c,"voidclothhat",true)
 if hat and (hat:HasTag("broken") or I.Condition(hat)<=0 or s.repairing) then
  if not s.repairing or s.phase~="hat_escape" and s.phase~="hat_repair" then
   s.repairing=true;s.repair_goal=corner(c,e);phase(c,s,"hat_escape")
  end
  if s.phase=="hat_escape" then
   if not landing(c,s.repair_goal,e) then s.repair_goal=corner(c,e) end
   if blink(c,s,s.repair_goal) then phase(c,s,"hat_repair") end
   return support(c,s,e)
  end
  if distance(c.player:GetPosition(),e:GetPosition())<9 then return move(c,s,farpoint(c,e),"瓦器人 · 先闪离并拉开距离再修帽") end
  if repair(c,s,hat) or not hat:HasTag("broken") and I.Condition(hat)>0 and not s.repair then
   if not equip(c,s,hat,EQUIPSLOTS.HEAD) then return "support",e end
   s.repairing=nil;s.phase=nil;s.repair_goal=nil;releasehand(c,s)
  else return support(c,s,e) end
 end
 if not setup(c,s,e) then phase(c,s,"prepare_gear");return nil end
 if s.phase=="prepare_gear" then s.phase=nil;s.last_missing=nil end
 return nil -- existing robot ordinary attacks/dodge retain control, with requested scythe selection
end
function M.Preparing(c) local s=context(c);return s and (s.phase=="prepare_gear" or s.missing_item~=nil) or false end
function M.Owns(c) local s=context(c);return s and s.phase~=nil and s.phase~="prepare_gear" or false end
function M.Hands(c) local s=context(c);return s and s.forced end
function M.Block(c,e)
 local s=context(c);return s and M.Required(c,s.target) and s.phase~=nil or false
end
function M.Dodge(c,e,base)
 if M.Owns(c) then return false end
 return base
end
function M.Stop(c)
 local s=context(c);if not s then return end
 releasehand(c,s);c.doc_boss_state=nil
end
return M
