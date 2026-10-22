-- AI Player 原 Pack/Choose 与换装；只有 3014 协程调用此协调层。
-- 不载入旧 CombatController，不运行旧攻击/走位线程。
local Basic=require("shadowself/control/actions")
local Coordinator=Class(function(self,bridge,plan)
    for _,name in ipairs({"action_library","combat_equipment","combat_tactics"}) do require("shadowself/legacy/"..name) end
    local R=require("shadowself/legacy/registry")
    self.bridge=bridge;self.h=bridge.h;self.player=bridge.player;self.plan=plan
    self.owner=plan.context or {config={combat_style="pressure",combat_mode="character"},
        perception={Inventory=function() return Basic.Items(bridge.player) end}}
    self.actions=R.ActionLibrary(self.player,self.owner.config)
    self.roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end,TargetBias=function() return 0 end}
    self.gear=R.CombatEquipment(self);self.tactics=R.CombatTactics(self)
    self.travel=require("shadowself/control/travel")(self.player,self.gear)
    self.hazards={};self.profiles={};self.observed={};self.enemies={}
    self.bosses=require("shadowself/control/bosses")(self)
    self.encounters=require("shadowself/control/encounters")(self)
    self.supplies=require("shadowself/control/supplies")(self)
    if plan.arena then self.healing=plan.arena_healing or require("shadowself/control/arena_healing")(self.player) end
    if self.player.prefab=="waxwell" then self.maxwell=require("shadowself/control/maxwell")(self) end
end)
function Coordinator:Trace(text) self.status=text end
function Coordinator:Latency()
    local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
    return math.min(.6,(ping or 0)/1000+.1), (ping or 0)/1000
end
function Coordinator:Speed() return self.h.GetSpeed and self.h:GetSpeed() or 6 end
function Coordinator:AttackTiming() return .25,.4 end
function Coordinator:Profile(e)
    local combat=e.replica and e.replica.combat
    local range=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2
    local profile={range=range+(self.player.GetPhysicsRadius and self.player:GetPhysicsRadius(0) or .5)+.5}
    self.profiles[e]=profile;return profile
end
function Coordinator:Risk(point,e,profile,o)
    local r=o and o.move and o.move.radius or profile.range
    return r-math.sqrt(point:DistSq(e:GetPosition()))
end
function Coordinator:HazardRisk(point,h) return h.radius-math.sqrt(point:DistSq(h.pos)) end
function Coordinator:ClearApproach(point,enemies,observed,unused,primary)
    return require("shadowself/control/navigation").Safe(self,point,primary or self.target)
end
function Coordinator:SafeMovePoint(point)
    -- 主目标由原3014招式表决定闪避，不用圆形危险区覆盖其原生侧闪。
    -- 只检查原落点是否会进入其他怪的攻击圈或蜂蜜，安全则原样返回。
    -- A charge sidestep is already selected along one straight line; do not orbit/replan it.
    if self.charge_target==self.h.ent and self.charge_point and point:DistSq(self.charge_point)<.001 then return point end
    local primary=self.h.ent or self.target
    local nav=require("shadowself/control/navigation")
    if not nav.Obstructed(self,point,primary) then return point end
    return nav.Select(self,point,primary)
end
function Coordinator:Move(point,label)
    if self.crabking then self.crabking:Interrupt() end
    require("shadowself/control/queenflute").Interrupt(self,"external_move:"..tostring(label))
    self.blocked=true;self.status=label;self.last_action_kind="move";self.last_point=point
    if GetTime()>=(self.next_move or 0) then
        require("shadowself/native").Get().POS_util:GoToPoint(point.x,point.z);self.next_move=GetTime()+.1
        require("shadowself/control/queendebug").Move(self,point,label)
    end
end
function Coordinator:Dodge(enemies,observed,label)
    self.blocked=true;self.status=label
    local best,score
    for _,e in ipairs(enemies) do
        local o=observed[e.GUID]
        if o and o.dodge then
            local risk=self:Risk(self.player:GetPosition(),e,self:Profile(e),o)
            if not score or risk>score then best,score=e,risk end
        end
    end
    if best then
        self.h.ent=best;self.bridge.wrappers.PreTheLoop.old(self.h)
        self.h:DoDodge(observed[best.GUID].dodge)
    end
end
function Coordinator:Scan()
    local now=GetTime()
    if now<(self.next_scan or 0) then return end
    self.next_scan=now+.05;self.enemies={};self.observed={}
    local pos=self.player:GetPosition()
    self.hazards={}
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,24)) do
        if e.prefab=="honey_trail" and e:IsValid() and not (e._isfading and e._isfading:value()) then
            local scale=e.Transform:GetScale();self.hazards[#self.hazards+1]={pos=e:GetPosition(),radius=(scale or 1)+.55,honey=true}
        end
    end
    if self.beequeen then
        for _,v in ipairs(self.beequeen.predicted or {}) do if now<v.untiltime then self.hazards[#self.hazards+1]=v end end
    end
    local s=self.owner.perception.Scan and self.owner.perception:Scan(false) or nil
    self.snapshot=s or {night=TheWorld.state.isnight}
    local rawpre=self.bridge.wrappers.IsAttackPre and self.bridge.wrappers.IsAttackPre.old or self.h.IsAttackPre
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,24,nil,{"INLIMBO","FX","DECOR","isdead"})) do
        local ec=e.replica and e.replica.combat
        local ally=self.player.replica.combat and self.player.replica.combat.IsAlly and self.player.replica.combat:IsAlly(e)
        local threat=ec and not ally and not e:HasTag("player") and not e:HasTag("isdead")
            and (e:HasTag("hostile") or e:HasTag("monster") or ec.GetTarget and ec:GetTarget()==self.player)
        if self.bridge.allowed(e) or threat or require("shadowself/control/plant").Middle(e) then
            self.enemies[#self.enemies+1]=e
            -- 攻击前摇来自 3014 原表，不使用旧 AI 的攻击帧表。
            local idle=self.h.idle_ticks
            local dodge=rawpre(self.h,e,0)
            if e.prefab=="sharkboi" and self.mechanisms then dodge=self.mechanisms:Dodge(e,dodge) end
            if self.encounters then dodge=self.encounters:Dodge(e,dodge) end
            if self.bosses then dodge=self.bosses:Dodge(e,dodge) end
            self.h.idle_ticks=idle
            local profile=self:Profile(e)
            local radius=profile.range
            -- Dodge travel distance is not a secondary monster's damage radius.
            self.observed[e.GUID]=dodge and {dodge=dodge,clock=0,move={hold=999,hit=0,lock=0,radius=radius}}
                or {neutral=true,recovery=true}
        end
    end
    table.sort(self.enemies,function(a,b) return pos:DistSq(a:GetPosition())<pos:DistSq(b:GetPosition()) end)
end
-- A veto must issue an escape, not leave the previous stopped/hit action idle.
function Coordinator:Escape(label)
    local p=self.player:GetPosition();local dx,dz=0,0
    for _,e in ipairs(self.enemies) do
        if self.observed[e.GUID] and self.observed[e.GUID].dodge then
            local q=e:GetPosition();local d=math.max(.25,p:DistSq(q));dx=dx+(p.x-q.x)/d;dz=dz+(p.z-q.z)/d
        end
    end
    for _,h in ipairs(self.hazards) do
        local d=math.max(.25,p:DistSq(h.pos));dx=dx+(p.x-h.pos.x)/d;dz=dz+(p.z-h.pos.z)/d
    end
    if dx*dx+dz*dz<.01 then dx,dz=1,0 end
    local d=math.sqrt(dx*dx+dz*dz)
    local point=require("shadowself/control/navigation").Select(self,Vector3(p.x+dx/d*3,0,p.z+dz/d*3))
    self:Move(point,label)
end
function Coordinator:HitRecovery()
    local a=self.player.AnimState
    local hit=a and (a:IsCurrentAnimation("hit") or a:IsCurrentAnimation("hit_spike")
        or a:IsCurrentAnimation("channelcast_hit") or a:IsCurrentAnimation("channelcast_oh_hit"))
    local health=self.player.replica and self.player.replica.health
    local percent=health and health.GetPercent and health:GetPercent()
    local hurt=percent and self.last_health and percent<self.last_health-.0001
    if percent then self.last_health=percent end
    if hurt or hit and not self.hit_active then
        -- Called by a read-only observer even while 3014 is sleeping/yielding.
        -- Hit state clears buffered actions; cancel only stale local equip waits.
        self.gear.pending=nil;self.gear.failed={};self.gear.next_request=GetTime();self.next_move=nil
        self.h.guid=0;self.last_action_kind=nil;self.attack_until=nil
        if self.healing then self.healing:Interrupt(self) end
    end
    self.hit_active=hit or false
end
-- Minimal native bridge. Old Pack/PermitAttack/gear movement code is not called
-- by combat.lua; ordinary enemies retain the exact original 3014 execution path.
function Coordinator:NativePulse()
    self.blocked=false;self.special_active=false;self.queen_active=false;self.target=self.h.ent
    local target=self.h.ent
    if self.brightshade_target and self.bosses then
        local picked=self.bosses:WeakHead();self.brightshade_target=picked
        if picked and self.h.ent~=picked then self.h.ent=picked;self.target=picked;self.bridge.wrappers.PreTheLoop.old(self.h) end
        target=self.h.ent
    end
    local queenfight=target and (target.prefab=="beequeen" or target.prefab=="beeguard")
        or self.beequeen and self.beequeen.queen
    if queenfight or self.maxwell then
        self:Scan()
        self.beequeen=self.beequeen or require("shadowself/control/beequeen")(self)
        if self.beequeen:Tick() then self.special_active=true;self.queen_active=true;return end
        if self.maxwell then
            local imminent=false
            for _,o in pairs(self.observed) do if o.dodge then imminent=true;break end end
            if self.maxwell:Tick(imminent) then self.special_active=true;self.blocked=true;return end
        end
    end
    if target and (target.prefab=="crabking" or target.prefab=="crabking_icewall" or self.crabking and self.crabking:Active()) then
        self.crabking=self.crabking or require("shadowself/control/crabking")(self)
        local mode,picked=self.crabking:Tick(target)
        if mode then self.special_active=true;self.blocked=mode=="support";self.target=picked;return end
    end
    if target and target:IsValid() then
        local reach=self.gear:AttackRange()+(target.GetPhysicsRadius and target:GetPhysicsRadius(0) or .5)
        local danger=self.charge_target==target or self.secondary and self.secondary:Danger(target)
            or self.secondary and self.secondary.data and self.secondary.data[target]
        if not self.bridge.supervisor then self.travel:Tick(target:GetPosition(),reach,danger,self.snapshot)
        elseif not self.travel.dodging and not self.bridge.chasing then self.gear:Swap("attack",self.snapshot) end
    end
end
function Coordinator:Pulse()
    self:Scan();self:HitRecovery();self.blocked=false;self.target=self.h.ent;self.primary_target=self.primary_target or self.target
    if self.player:HasTag("attack") then self.last_action_kind="attack";self.attack_until=GetTime()+FRAMES end
    if self.plan.kind=="dodge" then return end
    self.beequeen=self.beequeen or require("shadowself/control/beequeen")(self)
    if self.beequeen:Tick() then return end
    local eligible={};for _,e in ipairs(self.enemies) do if self.bridge.allowed(e) then eligible[#eligible+1]=e end end
    local picked=self.tactics:Choose(eligible,self.observed)
    if picked and self.bridge.allowed(picked) then self.target=picked end
    -- 各怪前摇都参与威胁判断；优先把最紧迫者交给原 DoDodge。
    local danger,score
    for _,e in ipairs(self.enemies) do
        local o=self.observed[e.GUID]
        if o and o.dodge then
            local risk=self:Risk(self.player:GetPosition(),e,self:Profile(e),o)
            if not score or risk>score then danger,score=e,risk end
        end
    end
    if danger and score>0 and self.bridge.allowed(danger) then self.target=danger end
    if self.target and self.h.ent~=self.target then self.h.ent=self.target;self.bridge.wrappers.PreTheLoop.old(self.h) end
    if self.maxwell and self.maxwell:Tick(danger~=nil) then self.blocked=true;return end
    -- A reachable recovery target gets its strike before any optional gathering.
    if self.target and not (self.observed[self.target.GUID] or {}).dodge then
        local reach=self.gear:AttackRange()+(self.target.GetPhysicsRadius and self.target:GetPhysicsRadius(0) or .5)
        if self.player:GetPosition():DistSq(self.target:GetPosition())<=reach^2
            and self.tactics:SafeWindow(self.player:GetPosition(),self.enemies,self.observed,.3,self.target) then
            self.status="战斗 · 抓空档出手";return
        end
    end
    if #eligible>=3 then self.blocked=self.tactics:Pack(eligible,self.observed) or self.blocked end
end
function Coordinator:PermitAttack()
    self:HitRecovery() -- a prior yielding dodge must not leave hit_active latched
    if self.h.ent and not self.bridge.allowed(self.h.ent) then return false end
    if self.maxwell and self.maxwell:ControlOnly() then return false end
    if self.blocked then return false end
    local target=self.h.ent
    if target and target:IsValid() then
        local pos,ep=self.player:GetPosition(),target:GetPosition()
        local reach=math.max(.5,self.gear:AttackRange()+(target.GetPhysicsRadius and target:GetPhysicsRadius(0) or .5)-.55)
        local d=math.sqrt(pos:DistSq(ep))
        if d>reach then
            local point=Vector3(ep.x+(pos.x-ep.x)*reach/d,0,ep.z+(pos.z-ep.z)*reach/d)
            local nav=require("shadowself/control/navigation")
            if not nav.Safe(self,point,target) then
                self:Move(nav.Select(self,point,target),"战斗 · 绕开蜂蜜和侧方攻击圈再追击")
                return false
            end
        end
    end
    -- Movement takes precedence over waiting for a weapon acknowledgement.
    if not self.tactics:SafeWindow(self.player:GetPosition(),self.enemies,self.observed,.3,self.h.ent) then
        self:Escape("战斗 · 受威胁时撤步，继续寻找攻击窗口");return false
    end
    if self.hit_active then return false end
    if self.gear:Weapon() and not self.gear:Swap("attack",self.snapshot) then return false end
    -- 装备同步完成后更新3014当前持物和攻击距离，不把旧手杖参数带入这一刀。
    local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if self.h.hand~=hand and self.h.ent then self.bridge.wrappers.PreTheLoop.old(self.h) end
    -- 旧 AI 的联合作战窗口：当前目标以外的前摇覆盖落点时不补刀。
    return true
end
function Coordinator:Stop() if self.encounters then self.encounters:Stop() end;if self.mechanisms then self.mechanisms:Stop() end;if self.maxwell then self.maxwell:Stop() end;self.actions:Stop();self.gear:Reset();self.tactics:Reset() end
return Coordinator
