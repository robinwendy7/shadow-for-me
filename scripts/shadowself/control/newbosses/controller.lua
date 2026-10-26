-- 由既有监督协程调用；没有新的移动线程，不读服务端sg/私有能力开关。
local A=require("shadowself/control/actions")
local G=require("shadowself/control/newbosses/geometry")
local profiles={rocky_boss_shadow=require("shadowself/control/newbosses/rocky"),
    bat_boss_shadow=require("shadowself/control/newbosses/bat"),charlie_boss=require("shadowself/control/newbosses/charlie"),
    shrouden=require("shadowself/control/newbosses/shrouden")}
local charlie=require("shadowself/control/newbosses/charlie")
local shrouden=require("shadowself/control/newbosses/shrouden")
local escape=require("shadowself/control/newbosses/escape")
local beam=require("shadowself/control/newbosses/beam")
local Diagnostics=require("shadowself/control/newbosses/debug")
local extras={charlie_boss_minion1=true,charlie_boss_minion2=true,charlie_boss_projectile=true,
    charlie_boss_vines=true,charlie_boss_runner=true,shrouden_optic_blast_fx=true,charliearena_spike=true,
    shadowthrall_horns=true,shadowthrall_hands=true,shadowthrall_wings=true,shadowthrall_mouth=true,
    honey_trail_shrouden_fx=true,gelblob_attach_fx=true}
local thralls={shadowthrall_horns=true,shadowthrall_hands=true,shadowthrall_wings=true,shadowthrall_mouth=true}
local New=Class(function(self,c)
    self.c=c;self.states=setmetatable({},{__mode="k"});self.shapes={};self.bodies={};self.bosses={}
    self.debug=Diagnostics.New(self)
end)
function New.Known(e) return e and profiles[e.prefab]~=nil end
function New.Unattackable(e)
    return e and thralls[e.prefab] and e:HasTag("NOCLICK") and e:HasTag("notarget") or false
end
function New:Velocity(e,state,fallback,point)
    local p=point or e:GetPosition();local now=GetTime();local old=state.sample
    if old and now>old.time and now-old.time<.3 then
        local dt=now-old.time;local vx,vz=(p.x-old.pos.x)/dt,(p.z-old.pos.z)/dt
        if vx*vx+vz*vz<35^2 then state.vx,state.vz=vx,vz else state.vx,state.vz=0,0 end
    end
    if not old or now>old.time then state.sample={pos=p,time=now} end
    local x,z=G.Basis(e)
    return state.vx or x*fallback,state.vz or z*fallback
end
function New:Scan()
    local now=GetTime()
    if now<(self.next_scan or 0) then
        local fresh=New.Known(self.c.h.ent) and not self.states[self.c.h.ent]
        if not fresh then for _,e in ipairs(self.c.enemies or {}) do if New.Known(e) and not self.states[e] then fresh=true;break end end end
        if not fresh then return end
    end
    self.next_scan=now+(FRAMES or 1/30);self.shapes={};self.bodies={};self.bosses={};self.gel_attached=nil
    local c=self.c;local p=c.player:GetPosition();local pad=c.player:GetPhysicsRadius(.5)+.25
    self.reaction=math.min(.3,c:Latency()+2*(FRAMES or 1/30))
    local entities=TheSim:FindEntities(p.x,0,p.z,36,nil,{"INLIMBO","DECOR"});self.scene_count=#entities
    for _,e in ipairs(entities) do
        if G.Live(e) then
            local module=profiles[e.prefab]
            if module or extras[e.prefab] then
                local state=self.states[e] or {};self.states[e]=state
                if module then
                    self.bosses[#self.bosses+1]=e;module.Build(self,e,self.shapes,state,pad)
                    if not module.Passthrough or not module.Passthrough(e) then self.bodies[#self.bodies+1]=e end
                elseif e.prefab=="shrouden_optic_blast_fx" or e.prefab=="charliearena_spike" or thralls[e.prefab]
                    or e.prefab=="honey_trail_shrouden_fx" or e.prefab=="gelblob_attach_fx" then
                    shrouden.Extra(self,e,self.shapes,state,pad)
                    if e.prefab=="charliearena_spike" and not G.Anim(e,"spike_pst") then self.bodies[#self.bodies+1]=e end
                else charlie.Extra(self,e,self.shapes,state,pad) end
            end
        end
    end
    if #self.bosses==0 and #self.shapes==0 then self.next_scan=now+.25;return end -- 普通战斗仅低频检查新Boss。
    -- 侧方旧怪仍参与联合危险判断，不能为了躲新Boss踏进另一只怪的冲撞。
    local incoming=require("shadowself/control/incoming")
    for _,e in ipairs(c.enemies or {}) do if G.Live(e) and not profiles[e.prefab] then
        self.bodies[#self.bodies+1]=e
        local lane=incoming.Lane(c,e)
        if lane then G.Line(self.shapes,e,lane.pos,Vector3(lane.pos.x+lane.x*lane.length,0,lane.pos.z+lane.z*lane.length),lane.width)
        elseif c.observed and c.observed[e.GUID] and c.observed[e.GUID].dodge then
            G.Circle(self.shapes,e,require("shadowself/control/navigation").Radius(e))
        end
    end end
end
function New:Reflecting()
    local e=self.c.h.ent;local s=e and self.states[e]
    return e and e.prefab=="charlie_boss" and (not s or s.reflect~=false) or false
end
function New:WeaponAllowed(item)
    return not self:Reflecting() or not (item:HasTag("rangedweapon") or item:HasTag("slingshot")
        or item:HasTag("projectile") or item:HasTag("complexprojectile"))
end
function New:Holding() return self.holding or false end
function New:Risk(point,time,shapes)
    local reaction=self.reaction or math.min(.3,self.c:Latency()+2*(FRAMES or 1/30))
    return G.Window(shapes or self.shapes,point,math.max(0,(time or 0)-reaction),(time or 0)+reaction)
end
function New:Pursuit()
    local p=self.c.player:GetPosition();local best,score
    for _,h in ipairs(self.shapes) do if h.pursuit then
        local d=math.sqrt(p:DistSq(h.pos))-h.radius
        if d<3.5 and (not score or d<score) then best,score=h,d end
    end end
    return best
end
function New:ClearFocus()
    if self.focus and self.c.bridge.priority_target==self.focus then self.c.bridge.priority_target=self.old_priority end
    self.focus=nil;self.old_priority=nil
end
function New:Focus(target)
    if self.focus and (not G.Live(self.focus) or self.focus:GetPosition():DistSq(self.c.player:GetPosition())>30^2) then self:ClearFocus() end
    if not self.focus and target and target.prefab=="bat_boss_shadow" and G.Live(target) then
        local previous=self.c.bridge.priority_target
        if not previous or previous.prefab=="bat_boss_shadow" then
            self.focus=target;self.old_priority=previous;self.c.bridge.priority_target=target
        end
    end
end
function New:Blocked(e)
    self:Scan()
    if New.Unattackable(e) then return true end
    if self.holding then return true end
    if beam.Active(self) then return true end
    local module=e and profiles[e.prefab]
    if module and module.Blocked(e,self.states[e]) then return true end
    local p=self.c.player:GetPosition()
    if self:Risk(p,.12)>0 or self:Pursuit() then return true end
    if e and e:IsValid() and self:ApproachRisk(e)>0 then return true end
    local hand=self.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    return hand and not self:WeaponAllowed(hand) or false
end
function New:ApproachRisk(target,point)
    if #self.shapes==0 or not target then return 0 end
    local p=point or self.c.player:GetPosition();local q=target:GetPosition()
    local d=math.sqrt(p:DistSq(q));local reach=self.c.gear:AttackRange()+target:GetPhysicsRadius(0)-.3
    local length=math.max(0,d-reach);local risk=0
    if length==0 then return self:Risk(p,.15) end
    local speed=math.max(1,self.c:Speed())
    length=math.min(length,8);local steps=math.max(2,math.ceil(length/.5))
    local endpoint=Vector3(p.x+(q.x-p.x)*length/d,0,p.z+(q.z-p.z)*length/d)
    local shapes=G.Select(self.shapes,p,endpoint)
    for i=0,steps do
        local step=length*i/steps;local t=math.min(.6,step/speed)
        local v=Vector3(p.x+(q.x-p.x)*step/d,0,p.z+(q.z-p.z)*step/d)
        risk=math.max(risk,self:Risk(v,t,shapes))
    end
    return risk
end
function New:Path(q)
    local c=self.c;local p=c.player:GetPosition();local speed=math.max(1,c:Speed())
    local length=math.sqrt(p:DistSq(q));local steps=math.max(2,math.ceil(length/.5));local peak,exposure=0,0
    local shapes=G.Select(self.shapes,p,q)
    local pad=c.player:GetPhysicsRadius(.5)+.12
    for i=1,steps do
        local v=Vector3(p.x+(q.x-p.x)*i/steps,0,p.z+(q.z-p.z)*i/steps)
        if not c.actions:SafePoint(v) then return end
        for _,e in ipairs(self.bodies) do
            local r=e:GetPhysicsRadius(0)+pad
            local before=math.max(0,r-math.sqrt(p:DistSq(e:GetPosition())))
            if r-math.sqrt(v:DistSq(e:GetPosition()))>before+.04 then return end
        end
        for _,h in ipairs(c.hazards or {}) do
            local before=math.max(0,h.radius-math.sqrt(p:DistSq(h.pos)))
            if h.radius-math.sqrt(v:DistSq(h.pos))>before+.02 then return end
        end
        local risk=self:Risk(v,length*i/steps/speed,shapes)
        peak=math.max(peak,risk);exposure=exposure+risk/steps
    end
    return self:Risk(q,math.min(.6,length/speed),shapes),peak,exposure
end
function New:Point(target,pursuit)
    local started=Diagnostics.Clock();local candidates=0
    local c=self.c;local p=c.player:GetPosition();local now=GetTime()
    local initial=self:Risk(p,.1);local goal=target and target:GetPosition() or p
    if self.point and now<(self.commit_until or 0) and p:DistSq(self.point)>.9^2 then
        local final,peak=self:Path(self.point)
        if final and final<=.001 and peak<=initial+.1
            and (not pursuit or self.point:DistSq(pursuit.pos)>p:DistSq(pursuit.pos)+.5) then self.debug:Plan(started,0,true);return self.point end
    end
    local best,score,best_safe
    for _,length in ipairs({1.5,2.5,4,6,8,10}) do for i=0,23 do
        candidates=candidates+1
        local angle=i*math.pi/12;local q=Vector3(p.x+math.cos(angle)*length,0,p.z+math.sin(angle)*length)
        local final,peak,exposure=self:Path(q)
        if final and (initial>0 and final<initial-.01 or initial==0 and final==0 and peak==0)
            and (not pursuit or q:DistSq(pursuit.pos)>p:DistSq(pursuit.pos)+.5) then
            local safe=final<=.001
            local remaining=initial==0 and target and self:ApproachRisk(target,q) or 0
            local value=final*250+peak*35+exposure*12+remaining*50+length*1.5+q:DistSq(goal)*.015
            if self.point and now<(self.commit_until or 0) then value=value+q:DistSq(self.point)*.25 end
            -- 在岸边保留后续出口，避免连续躲避一步步走进死角。
            value=value+(8-require("shadowself/control/navigation").Clearance(c,q))*3
            value=value+charlie.MoveBias(self,q)
            if pursuit then value=value-math.min(16,math.sqrt(q:DistSq(pursuit.pos)))*3 end
            -- 必须优先真正走出整个攻击区；只减小一点风险会导致走两步就停、继续中招。
            if not score or safe and not best_safe or safe==best_safe and value<score then best,score,best_safe=q,value,safe end
        end
    end end
    if best then self.point=best;self.commit_until=now+.25;charlie.Commit(self,best) end
    self.debug:Plan(started,candidates,false)
    return best
end
function New:Release()
    if self.moving then self.c.travel:EndDodge(self.c.snapshot);self.moving=nil end
    self.holding=nil
end
function New:Halt()
    -- A.Stop会终止服务器预测走路；同时清理原走位的会话标记，下次才能正常起跑。
    if self.c.h.StopPredictWalk then self.c.h:StopPredictWalk() end
    A.Stop(self.c.player)
end
function New:DetachBat()
    local c=self.c;local p=c.player;local inv=p.replica.inventory;local head=inv:GetEquippedItem(EQUIPSLOTS.HEAD)
    if head and head.prefab=="bat_boss_shadow" then
        c.bridge:PauseAttack();self.holding=true;c.blocked=true
        if GetTime()>=(self.next_detach or 0) and not p.components.playercontroller:IsBusy() then
            A.Self(p,head,ACTIONS.UNEQUIP);self.next_detach=GetTime()+.5
        end
        self.was_attached=true;return true
    end
    if self.was_attached then
        -- 交给已有防具拾取/装备流程，不能将活蝙蝠再次当作头盔穿回去。
        self.was_attached=nil;self.next_detach=nil
    end
end
function New:_Tick()
    self.holding=nil;self:Scan()
    local c=self.c;local target=c.h.ent
    self:Focus(target)
    if self:DetachBat() then return true end
    local active=#self.bosses>0 or #self.shapes>0
    if not active then self:Release();return false end
    if c.player:HasTag("pinned") then c.bridge:PauseAttack();self.holding=true;return true end
    if escape.Tick(self) then return true end
    if beam.Tick(self) then return true end
    local p=c.player:GetPosition();local risk=self:Risk(p,.12);local pursuit=self:Pursuit()
    local approach=target and self:ApproachRisk(target) or 0
    if risk>0 or approach>0 or pursuit then
        local point=self:Point(target,pursuit)
        c.bridge:PauseAttack();self.holding=true;c.blocked=true;c.special_active=true
        if point then
            self.stopped=nil
            c.travel:BeginDodge(c.snapshot);self.moving=true
            c:Move(point,"新Boss · 联合避让技能及侧方攻击")
        elseif not self.stopped then self:Halt();self.stopped=true end
        return true
    end
    self.stopped=nil
    local module=target and profiles[target.prefab]
    if module and module.Blocked(target,self.states[target]) then
        c.bridge:PauseAttack();self.holding=true;c.blocked=true;c.special_active=true
        if not self.waiting then self:Halt();self.waiting=true end
        return true
    end
    self.waiting=nil;self:Release();return false
end
function New:Tick()
    local started=Diagnostics.Clock();local result=self:_Tick()
    self.debug:Tick(started);return result
end
function New:Stop()
    -- 停止时由Coordinator统一清理装备/移动，不额外发一条恢复武器请求。
    self.debug:Finish("takeover_stop")
    escape.Clear(self);self.beam_run=nil;self.moving=nil;self.holding=nil;self:ClearFocus()
    self.states=setmetatable({},{__mode="k"});self.shapes={};self.point=nil
end
return New
