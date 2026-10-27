-- Geometric routes used only by explicitly configured boss skills.
local Nav=require("shadowself/control/navigation")
local Routes=Class(function(self,boss) self.boss=boss;self.c=boss.c;self.sides={};self.data={} end)
local function anim(e,n) return e and e.AnimState and e.AnimState:IsCurrentAnimation(n) end
local function frame(e) return e.AnimState:GetCurrentAnimationFrame() or 0 end
local function distance(a,b) return math.sqrt(a:DistSq(b)) end
local function angle(e,p)
 local q=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
 local theta=math.atan2(p.z-q.z,p.x-q.x)
 return math.abs((theta+r+math.pi)%(2*math.pi)-math.pi)
end
function Routes:Orbit(e,back)
 local c=self.c;local p=c.player:GetPosition();local q=e:GetPosition()
 local radius=math.max(2.2,distance(p,q));local theta=math.atan2(p.z-q.z,p.x-q.x)
 local sign=self.sides[e] or 1
 for _,side in ipairs({sign,-sign}) do
  for _,step in ipairs({.5,.8,1.1,1.4}) do
   local a=theta+step*side;local v=Vector3(q.x+math.cos(a)*radius,0,q.z+math.sin(a)*radius)
   if (not back or angle(e,v)>angle(e,p)+.03) and Nav.Safe(c,v,e) then self.sides[e]=side;return v end
  end
 end
 -- No radial retreat fallback: stop/reassess the ring if both circular paths are blocked.
 return p
end
-- 机制扫描的沙刺区不能只在“人物已站进刺里”时生效；规划整条路线也要使用。
function Routes:AntContext()
 local c=self.c;local zones=c.mechanisms and c.mechanisms.zones
 if not zones or #zones==0 then return c end
 local hazards,seen={},{}
 for _,list in ipairs({c.hazards or {},zones}) do
  for _,zone in ipairs(list) do if not seen[zone] then seen[zone]=true;hazards[#hazards+1]=zone end end
 end
 return setmetatable({hazards=hazards},{__index=c})
end
-- 优先恒定半径的圆周路线，小步执行；每次重新检查前方完整路线。
function Routes:AntPoint(e)
 local c=self:AntContext();local p=c.player:GetPosition();local ep=e:GetPosition()
 self.ant_exit=nil;self.ant_plan=nil;self.ant_clearing=nil
 local planner=require("shadowself/control/antnavigation");local preferred=self.sides[e] or -1
 self.ant_path=planner.Plan(c,e,preferred)
 if self.ant_path then self.ant_path.target=e;self.sides[e]=self.ant_path.side end
 return self.ant_path and self.ant_path.goal or p
end
function Routes:AntReached(point)
 local c=self.c;local speed=c.Speed and c:Speed() or 6
 local ping=(TheNet and TheNet.GetPing and TheNet:GetPing() or 0)/1000
 local tolerance=math.max(.18,math.min(.65,speed*(.1+ping)+.05))
 return c.player:GetPosition():DistSq(point)<=tolerance^2
end
function Routes:AntStep(e,continue)
 local c=self:AntContext();local p=c.player:GetPosition();local planner=require("shadowself/control/antnavigation")
 local route=self.ant_path
 if route then
  while route.index<=#route.points and self:AntReached(route.points[route.index]) do
   local next_point=route.points[route.index+1]
   if next_point and not planner.Corridor(c,p,next_point,e) then break end
   route.index=route.index+1
  end
 end
 if not route or route.target~=e or not planner.Valid(c,e,route)
  or route.index>#route.points and (continue or Nav.Risk(c,p,e)>0) then self:AntPoint(e);route=self.ant_path end
 return route and (route.points[route.index] or route.goal) or nil
end
function Routes:AntRecover(e)
 self.ant_exit=nil;self.ant_plan=nil;self.ant_clearing=nil
 if not e or e.prefab~="antlion" or anim(e,"attack_pre") or anim(e,"cast_pre") or anim(e,"attack") then return end
 local c=self:AntContext();local planner=require("shadowself/control/antnavigation")
 if planner.Approach(c,c.player:GetPosition(),e) then self.ant_recovering=nil;return end
 if not self.ant_recovering then self:AntPoint(e) end
 self.ant_recovering=true
 local q=planner.Route(c,e) -- return through an attack corridor, not an endless ring
 q=q or self:AntStep(e,true)
 if not q then self.c.bridge:PauseAttack();return "support",e end
 return self.boss:Move(q,"蚁狮 · 沿环线绕过沙刺后恢复攻击",e)
end
function Routes:RememberAnt()
 local p=self.c.player:GetPosition();self.anttrail=self.anttrail or {}
 local last=self.anttrail[#self.anttrail]
 if not last or p:DistSq(last)>1 then
  self.anttrail[#self.anttrail+1]=Vector3(p.x,0,p.z)
  if #self.anttrail>16 then table.remove(self.anttrail,1) end
 end
end
function Routes:OrbitData(e,name,back)
 if back and angle(e,self.c.player:GetPosition())>=110*math.pi/180 then return false end
 local key=tostring(e.GUID)..name
 if not self.data[key] then
  self.data[key]={atkanim=name,point="target",dist=3,update=true,exclusive=true,noattack=true,
   fn=function() return self:Orbit(e,back) end}
 end
 return self.data[key]
end
function Routes:Summoning(e)
 if #((self.boss.ghosts) or {})>0 then return true end
 for _,v in ipairs(self.boss.entities or {}) do
  if v.prefab=="alterguardian_summon_fx" and v:IsValid() and v:GetPosition():DistSq(e:GetPosition())<4^2 then return true end
 end
 return false
end
function Routes:SpinPoint(e)
 local c=self.c;local p=c.player:GetPosition();local ep=e:GetPosition();local now=GetTime()
 local old=self.spin;local best,score
 if old and old.target==e then
  local q=Vector3(p.x+old.x*7,0,p.z+old.z*7)
  local far=Vector3(p.x+old.x*13,0,p.z+old.z*13)
  if Nav.Safe(c,q,e) and Nav.Safe(c,far,e) and q:DistSq(ep)>6.5^2 then return q end
 end
 for i=0,23 do
  local a=i*math.pi/12;local dx,dz=math.cos(a),math.sin(a)
  local q=Vector3(p.x+dx*7,0,p.z+dz*7)
  local far=Vector3(p.x+dx*13,0,p.z+dz*13)
  if Nav.Safe(c,q,e) and Nav.Safe(c,far,e) and q:DistSq(ep)>6.5^2 then
   local value=Nav.Risk(c,far,e)*100+distance(far,ep)*-.25+(8-Nav.Clearance(c,far))*5
   if old and old.target==e then value=value+(1-dx*old.x-dz*old.z)*3 end
   if not score or value<score then best,score={x=dx,z=dz},value end
  end
 end
 if best then self.spin={target=e,x=best.x,z=best.z,time=now};return Vector3(p.x+best.x*7,0,p.z+best.z*7) end
 local fallback=Nav.Escape(c,p,e)
 return fallback or p
end
function Routes:SpinData(e,name)
 local key=tostring(e.GUID)..name
 if not self.data[key] then
  self.data[key]={atkanim=name,point="player",dist=7,update=true,exclusive=true,noattack=true,fn=function() return self:SpinPoint(e) end}
 end
 return self.data[key]
end
function Routes:Leap(e)
 return e and e.prefab=="minotaur" and (anim(e,"jump_atk_pre") or anim(e,"jump_atk_loop") or anim(e,"jump_atk_pst"))
end
function Routes:LeapData(e,name)
 if name=="jump_atk_pst" and frame(e)>=12 then return false end
 local c=self.c;local state=self.leap
 if not state or state.target~=e or name=="jump_atk_pre" and state.last~=name then state={target=e};self.leap=state end
 state.last=name
 if not state.point then
  local p=c.player:GetPosition();local ep=e:GetPosition()
  if name=="jump_atk_loop" or name=="jump_atk_pre" and frame(e)>=30 then state.lock=Vector3(p.x,0,p.z) end
  if state.lock then
   local r=e.Transform:GetRotation()*math.pi/180;local best,score
   for _,side in ipairs({1,-1}) do
    local q=Vector3(state.lock.x+math.sin(r)*6.2*side,0,state.lock.z+math.cos(r)*6.2*side)
    if Nav.Safe(c,q,e) then
     local value=Nav.Risk(c,q,e)*100+p:DistSq(q)
     if not score or value<score then best,score=q,value end
    end
   end
   state.point=best or Nav.Select(c,Vector3(p.x+6.2,0,p.z),e)
  end
 end
 local key=tostring(e.GUID)..name
 if not self.data[key] then
  self.data[key]={atkanim=name,point="player",dist=6.2,update=true,exclusive=true,noattack=true,
   fn=function() return self.leap and self.leap.point or c.player:GetPosition() end}
 end
 return self.data[key]
end
function Routes:Bishop(e,base)
 local name
 for _,n in ipairs({"atk2_pre","atk2_loop","atk2_pst"}) do if anim(e,n) then name=n end end
 self.bishops=self.bishops or {}
 if not name then self.bishops[e]=nil;return base end
 local state=self.bishops[e]
 if not state or name=="atk2_pre" and frame(e)<(state.frame or 0) then state={};self.bishops[e]=state end
 state.frame=frame(e);self.bishop=state
 local rhythm=self.c.plan and self.c.plan.arena_clockwork
 local state_driven=rhythm and rhythm.target==e and rhythm:Live()
 if not state_driven and name=="atk2_pst" and frame(e)>20 then return false end
 local c=self.c;local p=c.player:GetPosition();local ep=e:GetPosition();local mark=state.mark or p
 if state_driven then
  -- 主教优先不处理其他发条的攻击，但其肉身仍会堵住侧移路线。
  local hazards={};for _,h in ipairs(c.hazards or {}) do hazards[#hazards+1]=h end
  local roster=c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies or {}
  for _,other in ipairs(roster) do if other~=e and other:IsValid() and not other:HasTag("dead") and not other:HasTag("isdead") then
   hazards[#hazards+1]={pos=other:GetPosition(),radius=(other.GetPhysicsRadius and other:GetPhysicsRadius(0) or .5)+c.player:GetPhysicsRadius(0)+.4}
  end end
  c=setmetatable({hazards=hazards},{__index=c})
 end
 local score
 -- dist和朝向可重建发射主教位置，防止三发条/多主教时绑到别人的标记。
 for _,fx in ipairs(self.boss.entities or {}) do if fx.prefab=="bishop_targeting_fx" and fx:IsValid() and not anim(fx,"reticule_pst") then
  local pos=fx:GetPosition();local r=fx.Transform:GetRotation()*math.pi/180
  local d=fx.dist and fx.dist.value and fx.dist:value()
  local source=d and Vector3(pos.x-math.cos(r)*d,0,pos.z+math.sin(r)*d)
  local error=source and source:DistSq(ep) or math.abs(math.sin(r)*(pos.x-ep.x)+math.cos(r)*(pos.z-ep.z))^2
  local value=error*100+p:DistSq(pos)
  if error<2.5^2 and (not score or value<score) then mark=pos;score=value end
 end end
 if name=="atk2_pst" then
  for _,fx in ipairs(self.boss.entities or {}) do if fx.prefab=="bishop_charge2_fx" and fx:IsValid() and fx:GetPosition():DistSq(mark)<3^2 then mark=fx:GetPosition();break end end
 end
 state.mark=Vector3(mark.x,0,mark.z)
 local radius=state.radius or math.max(2.2,distance(p,ep));state.radius=radius;local safe=2+c.player:GetPhysicsRadius(0)+.7
 local tracking=name~="atk2_pst"
 local function clear(v)
  if tracking then return v:DistSq(state.mark)+.02>=math.min(safe^2,c.player:GetPosition():DistSq(state.mark)) end
  return v:DistSq(state.mark)>=safe^2
 end
 local data={atkanim=name,point="player",dist=safe,update=true,exclusive=true,noattack=true,safe=clear}
 data.fn=function()
  local pos=c.player:GetPosition();local center=e:GetPosition()
  radius=math.max(2.2,distance(pos,center))
  if not tracking and clear(pos) then return pos end
  local theta=math.atan2(pos.z-center.z,pos.x-center.x)
  local preferred=state.side or 1
  for _,side in ipairs({preferred,-preferred}) do
   if tracking then
    -- 标记仍在追踪时持续同方向侧绕，不能到旧安全点就停，等标记追上。
    local step=math.min(.65,1.5/radius)
    for _,r in ipairs({radius,radius+1,radius+2}) do
     local a=theta+side*step
     local point=Vector3(center.x+math.cos(a)*r,0,center.z+math.sin(a)*r)
     if clear(point) and Nav.Safe(c,point,e) then state.side=side;return point end
    end
   else
    for step=.35,2.8,.15 do
     local a=theta+side*step;local point=Vector3(center.x+math.cos(a)*radius,0,center.z+math.sin(a)*radius)
     if clear(point) and Nav.Safe(c,point,e) then state.side=side;return point end
    end
   end
  end
  return Nav.Escape(c,Vector3(pos.x+safe,0,pos.z),e) or pos
 end
 return data
end
function Routes:Rabbit(e,base)
 local pre,loop=anim(e,"dropkick_pre"),anim(e,"dropkick_loop")
 if not pre and not loop then self.rabbit=nil;return base end
 local state=self.rabbit
 if not state or state.target~=e or pre and not state.pre then
  local p=self.c.player:GetPosition();local q=e:GetPosition();local r=e.Transform:GetRotation()*math.pi/180
  local side=math.sin(r)*(p.x-q.x)+math.cos(r)*(p.z-q.z);local sign=side<0 and -1 or 1
  local width=e:GetPhysicsRadius(0)+(TUNING.RABBITKING_ABILITY_DROPKICK_HITRADIUS or 1.5)+self.c.player:GetPhysicsRadius(0)+.5
  local amount=math.max(.1,width-math.abs(side));local best
  for _,v in ipairs({sign,-sign}) do
   local point=Vector3(p.x+math.sin(r)*amount*v,0,p.z+math.cos(r)*amount*v)
   if Nav.Safe(self.c,point,e) then best=point;break end
  end
  state={target=e,point=best or p,pre=pre};self.rabbit=state
 end
 state.pre=pre
 return {atkanim=pre and "dropkick_pre" or "dropkick_loop",exclusive=true,noattack=true,point="player",dist=3,update=false,fn=function() return state.point end}
end
function Routes:Dodge(e,base)
 local n=e.prefab
 if n=="shadowthrall_horns" and anim(e,"jump") and frame(e)<=31 then
  return {atkanim="jump",point="target",dist=2.8+self.c.player:GetPhysicsRadius(0)+.6,angle=0,update=true,noattack=true}
 end
 if n=="rabbitking_aggressive" then return self:Rabbit(e,base) end
 if n=="rabbitkingminion_bunnyman" and anim(e,"atk") and frame(e)<13 then return {atkanim="atk",point="target",dist=4,update=false,noattack=true} end
 if n=="bishop" or n=="bishop_nightmare" then return self:Bishop(e,base) end
 if n=="mutatedwarg" or n=="warg" or n=="claywarg" or n=="gingerbreadwarg" then
  for _,name in ipairs({"atk_breath_pre","atk_breath_loop","atk_breath_pst"}) do
   if anim(e,name) then return self:OrbitData(e,name,true) end
  end
  if anim(e,"atk") and frame(e)<=11+require("shadowself/control/nettiming").Frames(self.c) then return {atkanim="atk",point="target",dist=5,update=false,angle=0,noattack=true} end
 end
 if require("shadowself/control/plant").Weak(e) then return false end
 if e.HasTag and (e:HasTag("lunarthrall_plant_end") or e:HasTag("lunarthrall_plant_segment")) then
  if anim(e,"atk") and frame(e)<17 then return {atkanim="atk",point="target",dist=4.8,update=true,angle=0,noattack=true} end
 end
 if n=="mutateddeerclops" and self.boss.crystal and self.boss.crystal.eye_bare and anim(e,"atk") then
  local h=require("shadowself/native").Get().HitAndRun
  for _,entry in pairs(h and h.targetanimtable and h.targetanimtable.deerclops or {}) do
   if entry.atkanim=="atk" then
    local first=entry.atk_start_frame or 0;local last=entry.atk_stop_frame or 1000
    return frame(e)>=first and frame(e)<=last and entry or false
   end
  end
  return false
 end
 if n=="antlion" then
  self:RememberAnt()
  for _,name in ipairs({"attack_pre","attack","cast_pre"}) do
   if anim(e,name) and (name~="attack" or frame(e)<=3) then
    local state=self.antlion;local f=frame(e)
    if not state or state.target~=e or (name=="attack_pre" or name=="cast_pre") and (state.name~=name or f<state.frame) then
     state={target=e,name=name,point=self:AntPoint(e),origin=self.c.player:GetPosition(),frame=f};self.antlion=state
    end
    local previous_frame=state.frame
    if name=="cast_pre" and (not state.lock_origin or f<=3 and f>previous_frame) then
     local p=self.c.player:GetPosition();state.lock_origin=Vector3(p.x,0,p.z)
    end
    state.frame=f;state.name=name
    local origin=state.lock_origin or state.origin
    if not state.done then
     local extend=name=="cast_pre" and (f<33+require("shadowself/control/nettiming").Frames(self.c)+2 or origin and self.c.player:GetPosition():DistSq(origin)<=1.9^2)
     self:AntStep(e,extend)
     state.point=self.ant_path and self.ant_path.goal or self.c.player:GetPosition()
    end
    if (name=="cast_pre" and f>=33+require("shadowself/control/nettiming").Frames(self.c)+2 or name~="cast_pre" and self:AntReached(state.point)) and origin and self.c.player:GetPosition():DistSq(origin)>1.9^2
     and Nav.Risk(self:AntContext(),self.c.player:GetPosition(),e)==0 then
     state.done=true
    end
    if state.done then return false end
    return {atkanim=name,point="player",dist=1.8,update=true,exclusive=true,noattack=true,fn=function() return self:AntStep(e) end}
   end
  end
  self.antlion=nil
 elseif n=="vault_pillar_guard" then
  if anim(e,"atk_1") and frame(e)<29 then return self:OrbitData(e,"atk_1",true) end
  if anim(e,"atk_2") and frame(e)<26 then return self:OrbitData(e,"atk_2",true) end
 elseif n=="alterguardian_phase2" then
  for _,name in ipairs({"attk_spin_pre","attk_spin_loop","attk_spin_pst"}) do
   if anim(e,name) and (name~="attk_spin_pst" or frame(e)<10) then return self:SpinData(e,name) end
  end
  self.spin=nil
  if self:Summoning(e) and anim(e,"attk_chop") then
   if frame(e)<24 then return {atkanim="attk_chop",point="target",dist=5.5,update=true,angle=0,noattack=true} end
   return false
  end
 elseif self:Leap(e) then
  for _,name in ipairs({"jump_atk_pre","jump_atk_loop","jump_atk_pst"}) do if anim(e,name) then return self:LeapData(e,name) end end
 end
 return base
end
return Routes
