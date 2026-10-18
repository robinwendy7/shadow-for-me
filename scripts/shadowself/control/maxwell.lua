-- zom CastPillars/TrackControl/HasPillars 的独立适配，仅从3014协程调用。
local A=require("shadowself/control/actions")
local Maxwell=Class(function(self,coordinator)
    self.c=coordinator;self.player=coordinator.player;self.samples={};self.misses={};self.last_cast=-100
end)
local EXCLUDED={shadow_rook=true,shadow_bishop=true,shadow_knight=true,fused_shadeling=true,
    tentacle=true,tentacle_pillar=true,alterguardian_phase3=true,wagboss_robot=true,
    shadowchanneler=true,stalker_minion1=true,stalker_minion2=true}
local function alive(e)
    return e and e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not e:HasTag("corpse")
        and not (e.replica and e.replica.health and e.replica.health:IsDead())
end
function Maxwell:Eligible(e)
    return alive(e) and not EXCLUDED[e.prefab] and not e:HasTag("player") and not e:HasTag("playerghost")
        and not e:HasTag("wall") and not e:HasTag("shadowcreature") and not e:HasTag("nightmarecreature")
        and self.c.bridge.allowed(e)
end
function Maxwell:Book()
    for _,item in ipairs(A.Items(self.player)) do
        if item:IsValid() and item.prefab=="waxwelljournal" and item.components and item.components.spellbook then return item end
    end
end
function Maxwell:HasPillars(target)
    local p=target:GetPosition()
    local list=TheSim:FindEntities(p.x,p.y,p.z,5,{"shadow_pillar"},{"INLIMBO"})
    if #list==0 then return false,false end
    for _,pillar in ipairs(list) do
        if pillar.AnimState then for i=1,6 do
            if pillar.AnimState:IsCurrentAnimation("shake"..i) then return true,true end
        end end
    end
    return true,false
end
function Maxwell:Track(target,now)
    local pending=self.pending
    if pending and now-pending.time>=1.4 then
        if alive(pending.target) then
            local active=self:HasPillars(pending.target)
            local misses=self.misses[pending.target.GUID] or 0
            if misses<3 then self.misses[pending.target.GUID]=active and 0 or misses+1 end
        end
        self.pending=nil
    end
    if not target then return end
    local p=target:GetPosition();local old=self.samples[target.GUID];local vx,vz=0,0
    if old and now>old.time and now-old.time<1 then
        local dt,dx,dz=now-old.time,p.x-old.x,p.z-old.z
        if dx*dx+dz*dz<36 then vx,vz=dx/dt,dz/dt end
    end
    self.samples[target.GUID]={x=p.x,z=p.z,time=now,vx=vx,vz=vz}
end
function Maxwell:Point(target,now)
    local p=target:GetPosition();local origin=self.player:GetPosition()
    if (self.misses[target.GUID] or 0)>=3 then return Vector3(origin.x,origin.y,origin.z) end
    local sample=self.samples[target.GUID]
    local point=Vector3(p.x+(sample and sample.vx or 0)*.85,0,p.z+(sample and sample.vz or 0)*.85)
    local dx,dz=origin.x-point.x,origin.z-point.z;local d=math.sqrt(dx*dx+dz*dz)
    if d>0 then point.x=point.x+dx/d*3.5;point.z=point.z+dz/d*3.5 end
    return point
end
function Maxwell:Select(now)
    if now<(self.next_scan or 0) then return self.cached and self:Eligible(self.cached) and self.cached or nil end
    self.next_scan=now+.15
    local origin=self.player:GetPosition();local target,score
    for _,e in ipairs(TheSim:FindEntities(origin.x,origin.y,origin.z,50,nil,{"INLIMBO","FX","DECOR"})) do
        if self:Eligible(e) then
            self:Track(e,now)
            local d=origin:DistSq(e:GetPosition())
            local active,shaking=self:HasPillars(e)
            if d<=11.1^2 and (not active or shaking) then
                local boss=e:HasTag("epic") or e:HasTag("adventure_boss") or e:HasTag("worldboss") or e.prefab=="beequeen"
                local priority=(boss and 100 or 0)+(shaking and 30 or 0)+(e==self.c.h.ent and 10 or 0)-d*.01
                if not score or priority>score then target,score=e,priority end
            end
        end
    end
    self.cached=target
    return target
end
function Maxwell:ControlOnly()
    return self.player.prefab=="waxwell" and self:Book()~=nil and self.c.gear and not self.c.gear:Weapon()
        and self:Eligible(self.c.h.ent)
end
function Maxwell:MaintainRange()
    if not self:ControlOnly() then return false end
    local target=self.c.h.ent;local p=self.player:GetPosition();local ep=target:GetPosition()
    local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
    if d<9.5 or d>10.8 then
        if d<.01 then dx,dz,d=1,0,1 end
        local point=Vector3(ep.x+dx/d*10.4,0,ep.z+dz/d*10.4)
        if self.c:ClearApproach(point,self.c.enemies,self.c.observed) then self.c:Move(point,"暗影秘典 · 保持施法距离") end
    end
    return true
end
function Maxwell:Tick(imminent)
    if self.player.prefab~="waxwell" then return false end
    local now=GetTime();self:Track(nil,now)
    local book=self:Book();if not book then return false end
    -- 施法间隔期间仍采样位移，预判不能等到下次施法才开始追踪。
    local target=self:Select(now)
    if imminent then return false end -- 紧急躲避由原3014立即处理。
    if now<(self.hold_until or 0) then return true end
    if now-self.last_cast<1.6 then return self:MaintainRange() end
    if self.player:HasTag("attack") or self.player:HasTag("busy") then return false end
    if not target then return self:MaintainRange() end
    local point=self:Point(target,now)
    if self.player:GetPosition():DistSq(point)>7.8^2 then return self:MaintainRange() end
    -- 同zom：范围内存在排除对象时不施法，避免误控暗影棋子等。
    for _,e in ipairs(TheSim:FindEntities(point.x,point.y,point.z,4.1,nil,{"INLIMBO"})) do
        if EXCLUDED[e.prefab] and alive(e) then return false end
    end
    if self.book~=book then self:RestoreSelection();self.book=book;self.previous=book.components.spellbook:GetSelectedSpell() end
    if not A.CastBook(self.player,book,point,4) then return false end
    self.last_cast=now;self.hold_until=now+.8;self.pending={target=target,time=now}
    self.c.status="暗影秘典 · 禁锢"..(target:GetBasicDisplayName() or target.prefab)
    return true
end
function Maxwell:Interrupt() self.hold_until=0 end
function Maxwell:RestoreSelection()
    local book=self.book
    if book and book:IsValid() and book.components and book.components.spellbook then
        local s=book.components.spellbook
        if self.previous and s:GetSelectedSpell()==4 then s:SelectSpell(self.previous) end
    end
    self.book=nil;self.previous=nil
end
function Maxwell:Stop() self.pending=nil;self:RestoreSelection() end
return Maxwell
