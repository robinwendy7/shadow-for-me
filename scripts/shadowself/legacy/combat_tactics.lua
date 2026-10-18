local AIPLAYER=require("shadowself/legacy/registry")
-- Combat windows, target commitment and one-shot support actions.
-- All observations are client-visible; no remote components or SG access.
local function distance(a,b)return math.sqrt(a:DistSq(b)) end
local Tactics=Class(function(self,combat)
    self.combat=combat;self.next_switch=0;self.next_support=0
end)
function Tactics:Reset()self.next_switch=0;self.next_support=0;self.support=nil;self.pack=nil end
function Tactics:Attackable(e)
    if e:HasTag("noattack") or e:HasTag("invisible") or e:HasTag("flight") then return false end
    local replica=e.replica and e.replica.combat
    if replica and replica.CanBeAttacked then
        local ok,value=pcall(replica.CanBeAttacked,replica,self.combat.player)
        if ok and value==false then return false end
    end
    return self.combat.actions:FindAction("ATTACK",e)~=nil
end
function Tactics:Unsafe(point,e,o,horizon)
    local c=self.combat;local profile=c:Profile(e)
    if not profile then return true end
    if o and (o.neutral or o.trial) then return false end
    local move=o and o.move
    if move and o.clock then
        if move.hold<10 and o.clock>=move.hold+.05 then return false end
        local next_hit
        for _,time in ipairs(move.hits or {move.hit}) do
            if time>=o.clock-.05 then next_hit=math.min(next_hit or time,time) end
        end
        if move.hold<10 and next_hit and next_hit-o.clock>horizon+c:Latency() then return false end
    end
    return c:Risk(point,e,profile,o or {},.25)>0
end
function Tactics:SafeWindow(point,enemies,observed,horizon,exclude)
    local c=self.combat
    for _,e in ipairs(enemies) do
        if e~=exclude and self:Unsafe(point,e,observed[e.GUID],horizon) then return false end
    end
    for _,h in ipairs(c.hazards or {}) do
        if c:HazardRisk(point,h)>0 then return false end
    end
    return true
end
function Tactics:Point(e,reach)
    local c=self.combat;local pos=c.player:GetPosition();local ep=e:GetPosition();local d=distance(pos,ep)
    return d>reach and Vector3(ep.x+(pos.x-ep.x)*(reach-.15)/d,0,ep.z+(pos.z-ep.z)*(reach-.15)/d) or pos
end
function Tactics:Choose(enemies,observed)
    local c=self.combat;local now=GetTime();local pos=c.player:GetPosition()
    local own_hit=c:AttackTiming(select(2,c:Latency()));local reach=c.gear:AttackRange()
    local best,bscore,current_score
    -- Keep a committed swing; only the joint danger check can interrupt it.
    if c.last_action_kind=="attack" and now<(c.attack_until or 0) then return c.target end
    for i,e in ipairs(enemies) do
        if i>12 then break end
        local profile=c:Profile(e);local o=observed[e.GUID] or {}
        if profile and self:Attackable(e) and (c.owner.config.combat_style=="pressure" or not profile.evade_only) then
            local r=math.max(.5,reach+(e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5)-.55)
            local point=self:Point(e,r);local approach=distance(pos,point)/c:Speed()
            local active=o.move and o.clock and (o.move.hold>=10 or o.clock<o.move.hold+.05)
            local flank=active and o.move.shape~=nil and o.clock>=o.move.lock and c:Risk(point,e,profile,o)<0
            local available=o.neutral or o.trial or not active and o.move or flank
            if available and self:SafeWindow(point,enemies,observed,approach+own_hit,e)
                and c:ClearApproach(point,enemies,observed,false,e) then
                local score=10-approach*4-distance(pos,e:GetPosition())*.15
                if o.recovery then score=score+2 end
                if e==c.primary_target then score=score+.8 end
                if e==c.target then score=score+(now<self.next_switch and 3 or 1) end
                score=score+c.roles:TargetBias(e,enemies)
                if e==c.target then current_score=score end
                if not bscore or score>bscore then best,bscore=e,score end
            end
        end
    end
    if best and best~=c.target and (not current_score or bscore>current_score+1) then
        c.actions:Stop();c.last_action_kind=nil;c.last_point=nil;c.issued_attack=nil;c.attack_until=0;c.next_send=now;c.next_attack=0
        self.next_switch=now+.65;c:Trace("抓后摇转火 "..best.prefab)
        return best
    end
    return c.target or best
end
-- Gather dispersed ordinary enemies, bait their real windups, then punish.
-- No numeric crowd threshold is a blanket attack ban.
function Tactics:Pack(enemies,observed)
    local c=self.combat;if c.owner.config.combat_style~="pressure" or c.owner.config.combat_mode=="flee" then return false end
    local ordinary={};for _,e in ipairs(enemies)do if not e:HasTag("epic") then ordinary[#ordinary+1]=e end end
    if #ordinary<3 then self.pack=nil;return false end
    local now=GetTime();local pos=c.player:GetPosition();local x,z=0,0
    local count=math.min(8,#ordinary)
    for i=1,count do local p=ordinary[i]:GetPosition();x=x+p.x;z=z+p.z end
    local center=Vector3(x/count,0,z/count);local spread,attacks=0,0
    for i=1,count do
        local e=ordinary[i];spread=math.max(spread,distance(e:GetPosition(),center))
        local o=observed[e.GUID] or {}
        if o.move and o.clock and (o.move.hold>=10 or o.clock<o.move.hold) then attacks=attacks+1 end
    end
    local g=self.pack
    if not g then g={stage="bait",started=now,turn=1};self.pack=g end
    if attacks>0 then g.saw_attack=true;g.last_windup=now;g.stage="evade"
    elseif g.saw_attack then g.stage="punish"
    elseif #ordinary>=4 and spread>3.5 and now-g.started<1.2 then g.stage="gather"
    else g.stage="bait" end
    if g.stage=="punish" then
        -- Give the joint scheduler actual attack opportunities before gathering again.
        if g.last_windup and now-g.last_windup>2 then g.saw_attack=false;g.started=now end
        return false
    end
    if g.stage=="evade" then
        local hit=c:AttackTiming(select(2,c:Latency()))
        if not self:SafeWindow(pos,enemies,observed,hit) then
            c:Dodge(enemies,observed,"战斗 · 群怪骗招成功，短步避开交叠伤害",false);return true
        end
        return false -- A safe edge/add remains attackable during others' windups.
    end
    if g.stage=="bait" and #ordinary>=4 and spread<=3.5 and now>=(g.next_bait or 0)
        and not (c.last_action_kind=="attack" and now<(c.attack_until or 0)) then
        local front,dist
        for _,e in ipairs(ordinary)do
            local d=distance(pos,e:GetPosition());if not dist or d<dist then front,dist=e,d end
        end
        local profile=c:Profile(front);local reach=c.gear:AttackRange()+(front.GetPhysicsRadius and front:GetPhysicsRadius(0) or .5)-.55
        local edge=math.max(reach+.12,profile.range-.5)
        if dist>reach+.1 then
            g.bait_deadline=g.bait_deadline or now+.8
            if now<g.bait_deadline then
                if dist>edge+.08 then
                    local point=self:Point(front,edge)
                    if c:ClearApproach(point,enemies,observed,false) then
                        c:Move(point,"战斗 · 贴群怪前缘骗A，等实际前摇");c:Trace("贴边统一骗招");return true
                    end
                elseif c.last_action_kind=="move" then
                    c.actions:Stop();c.last_point=nil;c.last_action_kind=nil
                    c.owner.status="战斗 · 已贴近群怪，等骗出的前摇";return true
                else c.owner.status="战斗 · 已贴近群怪，等骗出的前摇";return true end
            end
            g.bait_deadline=nil;g.next_bait=now+2 -- Refused baits fall back to hitting.
        end
    end
    if g.stage~="gather" or c.last_action_kind=="attack" and now<(c.attack_until or 0) then return false end
    local dx,dz=pos.x-center.x,pos.z-center.z
    local angle=math.atan2(dz,dx);local ring=math.max(3,math.min(9,spread+1.2))
    for _,turn in ipairs({g.turn,-g.turn})do
        local a=angle+turn*.38
        local point=Vector3(center.x+ring*math.cos(a),0,center.z+ring*math.sin(a))
        if c:ClearApproach(point,enemies,observed,false) and self:SafeWindow(point,enemies,observed,.6) then
            g.turn=turn;c:Move(point,"战斗 · 圆周聚怪，然后贴边骗招");c:Trace("圆周聚怪")
            return true
        end
    end
    g.stage="bait" -- A blocked orbit falls back to engagement, never permanent fleeing.
    return false
end
function Tactics:Support(s,enemies,observed)
    local c=self.combat;local now=GetTime()
    if self.support then
        local p=self.support
        if c.actions:Confirmed(p.plan,p.before,s) then
            c.owner.profile:OnCompleted(p.plan);self.support=nil;self.next_support=now+2
        elseif now>=p.deadline then
            c.actions:Stop();self.support=nil;self.next_support=now+4
        elseif not self:SafeWindow(s.pos,enemies,observed,.5) then
            c.actions:Stop();self.support=nil;self.next_support=now+2
        else c.owner.status="战斗 · 完成一次补给，等待同步";return true end
    end
    if now<self.next_support or now<(c.attack_until or 0) or c.gear.pending then return false end
    local plan
    if s.health and s.health<c.owner.profile:Threshold("health") then plan=c.owner.brain:Heal(s) end
    if not plan and s.hunger and s.hunger<c.owner.profile:Threshold("hunger") then plan=c.owner.brain:Eat(s,"h") end
    if not plan and now>=(self.next_ability or 0) then plan=c.roles:SupportPlan(s,enemies) end
    if not plan or not (plan.kind=="action" and plan.action or plan.kind=="drop" and plan.item and plan.item.prefab=="wortox_soul") then return false end
    -- Full native eat/fertilize/cast busy interval, not just item consumption.
    local duration=plan.busy or (plan.kind=="drop" and .3 or plan.name=="EAT" and 2.5 or plan.name=="FERTILIZE" and 3.2 or 1.8)
    if not self:SafeWindow(s.pos,enemies,observed,duration) then return false end
    for _,e in ipairs(enemies) do
        local o=observed[e.GUID] or {};local profile=c:Profile(e)
        if not o.neutral and not (o.move and o.clock and o.move.hold<10 and o.clock>=o.move.hold) then return false end
        -- Need an observed recovery/cooldown, not a speculative long idle.
        if c:Risk(s.pos,e,profile,{})>0 and not (o.safe_until and o.safe_until-now>duration+.15) then return false end
        if o.neutral and not (o.safe_until and o.safe_until-now>duration+.15) then
            local approach=math.max(0,distance(s.pos,e:GetPosition())-profile.range-.5)/(e:HasTag("epic") and 12 or 6)
            if approach<duration+c:Latency() then return false end
        end
    end
    local before=c.actions:Stamp(plan,s)
    c.actions:Stop();c.last_action_kind=nil;c.issued_attack=nil
    local sent=plan.kind=="drop" and c.actions:DropSingle(plan.item) or plan.kind=="action" and c.actions:Execute(plan.action)
    if sent then
        if plan.ability then self.next_ability=now+30 end
        self.support={plan=plan,before=before,deadline=now+duration+1}
        c.owner.status="战斗 · 空档补给 "..plan.name;self.next_support=now+duration+2;return true
    end
    self.next_support=now+2;return false
end
AIPLAYER.CombatTactics=Tactics

return true
