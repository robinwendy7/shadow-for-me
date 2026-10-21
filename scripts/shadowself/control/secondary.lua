-- Other enemies' real 3014 windups, scoped to the owned combat bridge.
-- No movement hooks, extra action thread, gear switching or idle crowd fleeing.
local Nav=require("shadowself/control/navigation")
local Secondary=Class(function(self,c)
    self.c=c;self.cache={};self.enemies={};self.observed={};self.hazards={}
    self.player=c.player;self.actions=c.actions
end)
function Secondary:Scan()
    local now=GetTime()
    self.hazards=self.c.hazards or {}
    if now<(self.next_scan or 0) then return end
    self.next_scan=now+.05;self.enemies={};self.observed={};self.data={}
    local c=self.c;local p=self.player:GetPosition()
    local old=c.bridge.wrappers.IsAttackPre.old
    for _,e in ipairs(TheSim:FindEntities(p.x,p.y,p.z,18,nil,{"INLIMBO","FX","DECOR","isdead"})) do
        if (c.bridge.allowed(e) or e.prefab=="crabking_mob" or e.prefab=="crabking_mob_knight" or e:HasTag("lunarthrall_plant_end") or e:HasTag("lunarthrall_plant_segment")) and not e:HasTag("sleeping") and not require("shadowself/control/status").Frozen(e) then
            local idle=c.h.idle_ticks;local data=old(c.h,e,0);c.h.idle_ticks=idle
            if e.prefab=="sharkboi" and c.mechanisms then data=c.mechanisms:Dodge(e,data) end
            if c.encounters then data=c.encounters:Dodge(e,data) end
            if c.bosses then data=c.bosses:Dodge(e,data) end
            -- Exclude idle fallback entries: only the animation it describes is real danger.
            local anim=data and data.atkanim
            if type(anim)=="function" then anim=anim(e) end
            if data and anim and e.AnimState and e.AnimState:IsCurrentAnimation(anim) then
                self.enemies[#self.enemies+1]=e;self.data[e]=data
                self.observed[e.GUID]={dodge=data}
            elseif e.prefab=="rook" or e.prefab=="rook_nightmare" or e.prefab=="knight" or e.prefab=="knight_nightmare" or e.prefab=="bishop" or e.prefab=="bishop_nightmare" then
                -- 发条即使尚未挥击，走位也不要钻进它的近身攻击圈。
                self.enemies[#self.enemies+1]=e;self.observed[e.GUID]={neutral=false}
            end
        end
    end
end
function Secondary:Danger(primary)
    self:Scan()
    local p=self.player:GetPosition();local best,score
    for _,e in ipairs(self.enemies) do
        if e~=primary and self.data[e] then
            local data=self.data[e]
            local lane=require("shadowself/control/incoming").Lane(self.c,e)
            local risk=lane and require("shadowself/control/incoming").Risk(lane,p) or Nav.Radius(e)-math.sqrt(p:DistSq(e:GetPosition()))
            if data.safe then risk=data.safe(p) and 0 or math.max(.1,risk) end
            if risk>0 and (not score or risk>score) then best,score=e,risk end
        end
    end
    return best
end
function Secondary:Select(e)
    local c=self.c
    c.h.ent=e;c.target=e;c.bridge.wrappers.PreTheLoop.old(c.h)
end
function Secondary:Pulse()
    if self.c.queen_active and self.c.beequeen and self.c.beequeen.late then self.pending=nil;return end
    local c=self.c;local primary=c.h.ent
    if not primary then return end
    self:Scan()
    -- Current target's actual windup stays with the original 3014; its aim will
    -- consider the others only if its requested route intersects their attacks.
    if self.data[primary] or c.charge_target==primary then return end
    local other=self:Danger(primary)
    if other then
        self:Select(other)
    elseif c.h.selected_ents and not self.player:HasTag("attack") and not c.special_active and not c.bridge.priority_target then
        -- 每刀起手前重新选最近目标；挥刀中保留目标，避免改目标造成空刀。
        local nearest=require("shadowself/control/targetpolicy").Nearest(c.bridge)
        if nearest and nearest~=primary then self:Select(nearest) end
    end
end
-- 侧方战车等的冲撞是整条扫掠路径，不能只看怪物当前脚下的小圆。
function Secondary:LaneBlocked(point,primary)
 local incoming=require("shadowself/control/incoming");local p=self.player:GetPosition()
 for _,e in ipairs(self.enemies) do if e~=primary then
  local lane=incoming.Lane(self.c,e)
  if lane then
   local initial=incoming.Risk(lane,p)
   local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(point))/.4))
   for i=1,steps do
    local sample=Vector3(p.x+(point.x-p.x)*i/steps,0,p.z+(point.z-p.z)*i/steps)
    if incoming.Risk(lane,sample)>initial+.02 then return true end
   end
   if initial>0 and incoming.Risk(lane,point)>=initial then return true end
  end
 end end
 return false
end
function Secondary:Point(point,primary,accept)
    self:Scan()
    if not Nav.Obstructed(self,point,primary) and not self:LaneBlocked(point,primary) and (not accept or accept(point)) then return point end
    local p=self.player:GetPosition();local ep=primary:GetPosition()
    local radius=math.sqrt(point:DistSq(ep));local best,score
    -- Preserve native distance from primary, instead of shortening a boss dodge
    -- to a generic four-unit step. Only the blocked group direction changes.
    for i=0,23 do
        local a=i*math.pi/12;local q=Vector3(ep.x+math.cos(a)*radius,0,ep.z+math.sin(a)*radius)
        if q:DistSq(p)<=math.max(6,math.sqrt(point:DistSq(p))+1)^2 and (not accept or accept(q)) and not self:LaneBlocked(q,primary) and Nav.Safe(self,q,primary) then
            local value=q:DistSq(point)+q:DistSq(p)*.1+(8-Nav.Clearance(self,q))*15
            if not score or value<score then best,score=q,value end
        end
    end
    if best then return best end
    local fallback=Nav.Select(self,point,primary)
    return not self:LaneBlocked(fallback,primary) and (not accept or accept(fallback)) and fallback or p
end
function Secondary:Wrap(primary,data,checktab)
    if primary and primary.prefab=="shadowthrall_hands" then return data end
    if data and data.exclusive and primary.prefab~="bishop" and primary.prefab~="bishop_nightmare" and primary.prefab~="sharkboi" and primary.prefab~="daywalker" then return data end
    if self.c.queen_active and self.c.beequeen and self.c.beequeen.late then self.pending=nil;return data end
    self:Scan()
    if not data then
        local other=self:Danger(primary)
        if other then
            -- A native dodge may be finishing with a captured old target. Let it
            -- finish, skip its old-target follow-up, then the same thread dodges other.
            if checktab then self.pending=other else self:Select(other);return self:Wrap(other,self.data[other]) end
        end
        return data
    end
    local c=self.c
    if c.charge_target==primary then return data end -- keep fixed straight charge dodge
    local has_other=#self.hazards>0
    for _,e in ipairs(self.enemies) do if e~=primary then has_other=true;break end end
    if not has_other then return data end
    local cached=self.cache[primary]
    if cached and (cached.base==data or cached.value==data) then return cached.value end
    local wrapped={};for k,v in pairs(data) do wrapped[k]=v end
    wrapped.fn=function(_,start,finish,angle,dist)
        local point=data.fn and data:fn(start,finish,angle,dist) or require("shadowself/native").Get().POS_util:CalculateAimPos(start,finish,angle,dist)
        return point and self:Point(point,primary,data.safe) or nil
    end
    self.cache[primary]={base=data,value=wrapped}
    return wrapped
end
function Secondary:AfterDodge(captured)
 local c=self.c
 if c.queen_active or c.crabking and c.crabking:Active() or c.bridge.priority_target and c.bridge.allowed(c.bridge.priority_target) and not require("shadowself/control/targetpolicy").Rook(c.bridge.priority_target) then return captured end
 c.h:GetAttackTargets(24)
 local nearest=require("shadowself/control/targetpolicy").Nearest(c.bridge)
 if nearest then self:Select(nearest);return nearest end
 return captured
end
function Secondary:BeforeAttack(check_only)
    if self.c.queen_active and self.c.beequeen and self.c.beequeen.late then self.pending=nil;return true end
    local preferred=self.c.brightshade_target
    if preferred and not require("shadowself/control/plant").Weak(preferred) then self.c.brightshade_target=nil;preferred=nil end
    if preferred and preferred:IsValid() and self.c.h.ent~=preferred then self.pending=nil;self:Select(preferred);return false end
    self:Scan()
    local e=self.pending;self.pending=nil
    -- 每次攻击都检查侧方真实前摇，不依赖上次走位留下的pending。
    local danger=self:Danger(self.c.h.ent)
    if danger then
        if check_only then self.pending=danger else self:Select(danger) end
        return false
    end
    if require("shadowself/control/incoming").ApproachBlocked(self.c,self.enemies,self.c.h.ent) then return false end
    return true
end
return Secondary
