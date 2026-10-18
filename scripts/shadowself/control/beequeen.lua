-- 蜂后专用节奏：首批留一只；进入指挥阶段后主打蜂后，不循环清补兵。
local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local Nav=require("shadowself/control/navigation")
local GuardPosition=require("shadowself/control/guardposition")
local GuardHands=require("shadowself/control/guardhands")
local Debug=require("shadowself/control/queendebug")
local GuardControl=require("shadowself/control/guardcontrol")
local Queen=Class(function(self,c) self.c=c;self.stage="lure";self.next_support=0 end)
function Queen:Target(e)
    local c=self.c;c.target=e;self.allow=e;c.blocked=false;c.bridge.priority_target=e
    if c.h.ent~=e then c.h.ent=e;c.bridge.wrappers.PreTheLoop.old(c.h) end
end
-- 三阶段守卫只参与威胁观察，不得成为选敌或原生走位补刀目标。
function Queen:GuardAttackBlocked(e)
 local queen=self.queen
 local health=queen and queen.replica and queen.replica.health
 return e and e.prefab=="beeguard" and self.phase and self.phase>=3 and queen and queen:IsValid()
  and not queen:HasTag("isdead") and not queen:HasTag("dead") and not (health and health.IsDead and health:IsDead()) or false
end
function Queen:Item(prefab)
 self.item_choice=self.item_choice or {}
 local p=self.c.player;local gear=self.c.gear
 return require("shadowself/control/itemchoice").Pick(self.item_choice,prefab,A.Items(p),p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS),gear and gear.pending)
end
-- 固定战场中心，不随着蜂后/玩家的位置不断向外漂移。
function Queen:Anchor(queen)
    if self.queen==queen then return end
    require("shadowself/control/queenflute").Reset(self)
    Debug.End(self.c,"queen_changed")
    self.guard_stats={};self.recycle_guard=nil;self.first_route=nil;self.spawn_wait=nil
    self.queen=queen;self.stage="lure";self.lure_since=GetTime();self.side=1
    self.late=nil;self.phase=1;self.roster={};self.had_roster=nil;self.predicted={};self.was_command=nil;self.piped=nil;self.flute_cycle=nil;self.flute_guards=nil;self.next_flute_scan=nil;self.guard_escape=nil;self.dash_cycle=nil
    Debug.Start(self.c,queen)
    local qp=queen:GetPosition();self.anchor=Vector3(qp.x,0,qp.z)
    local nearest
    for _,e in ipairs(TheSim:FindEntities(qp.x,0,qp.z,60)) do
        if (e.prefab=="beequeenhive" or e.prefab=="beequeenhivegrown") and e:IsValid() then
            local d=qp:DistSq(e:GetPosition())
            if not nearest or d<nearest then nearest=d;local v=e:GetPosition();self.anchor=Vector3(v.x,0,v.z) end
        end
    end
end
function Queen:Lure(now)
    self.stage="lure";self.lure_since=now;self.piped=nil
end
-- Relative ordering, not radial spread: player -> queen -> awake guards.
function Queen:Formation(queen,bees,pos)
    local qp=queen:GetPosition();local dx,dz=pos.x-qp.x,pos.z-qp.z
    local d=math.sqrt(dx*dx+dz*dz)
    if d<.1 then return false end
    for _,e in ipairs(bees) do
        if not e:HasTag("sleeping") and not Status.Frozen(e) then
            local bp=e:GetPosition();local projection=((bp.x-qp.x)*dx+(bp.z-qp.z)*dz)/d
            if projection> -2 or math.sqrt(pos:DistSq(bp))<d+2 then return false end
        end
    end
    return true
end
function Queen:Return(now,queen,bees)
    self.stage="return";self.return_since=now
    -- One fixed cutting-back direction away from guards, not a new 90-degree
    -- destination every tick that keeps orbiting the queen.
    local qp=queen:GetPosition();local x,z,n=0,0,0
    for _,e in ipairs(bees) do if not e:HasTag("sleeping") and not Status.Frozen(e) then
        local bp=e:GetPosition();x=x+bp.x;z=z+bp.z;n=n+1
    end end
    local p=self.c.player:GetPosition()
    local dx,dz=n>0 and qp.x-x/n or p.x-qp.x,n>0 and qp.z-z/n or p.z-qp.z
    local d=math.sqrt(dx*dx+dz*dz);if d<.1 then dx,dz,d=1,0,1 end
    self.return_dir={x=dx/d,z=dz/d}
end
function Queen:ReleaseTravel()
    if self.travelling and self.c.travel then self.c.travel:EndDodge(self.c.snapshot) end
    self.travelling=nil
end
function Queen:Strike(queen,pos,qp,distance)
    if require("shadowself/control/attackwindow").Tick(self.c,queen) then return true end
    if self.c.gear then self.c.gear.forced_weapon=nil end
    local c=self.c;local combat=c.player.replica and c.player.replica.combat
    local reach=(c.gear and c.gear.AttackRange and c.gear:AttackRange() or combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)
        +(queen.GetPhysicsRadius and queen:GetPhysicsRadius(0) or .5)-(self.phase==1 and 0 or .3)
    if distance>reach+.15 then
        local point=Vector3(qp.x+(pos.x-qp.x)*reach/distance,0,qp.z+(pos.z-qp.z)*reach/distance)
        if not Nav.Safe(c,point,queen) then
            self:Move(point,"蜂后 · 避开蜂蜜和守卫切回本体",queen);return true
        end
    end
    require("shadowself/control/queenroute").Clear(self)
    self:ReleaseTravel();c.status="蜂后 · 守卫在后，输出蜂后本体";return true
end
-- 只为蜂后专用拉扯选短路线；沿途避蜂蜜/守卫，并约束实际落点。
-- 已在边界之外时只能缩短相应距离，不会为了绕怪继续越跑越远。
function Queen:Move(goal,label,queen)
    if self.phase==1 or self.phase and self.phase>=3 and self.dash_cycle and self.dash_cycle.mode=="solo" then
        return require("shadowself/control/queenroute").Move(self,goal,label,queen)
    end
    local c=self.c;local pos=c.player:GetPosition();local qp=queen:GetPosition()
    self.travelling=true;c.bridge.chasing=true;if c.travel then c.travel.chasing=true;c.travel:BeginDodge(c.snapshot) end
    local home=math.sqrt(pos:DistSq(self.anchor));local dist=math.sqrt(pos:DistSq(qp))
    local dx,dz=goal.x-pos.x,goal.z-pos.z;local len=math.sqrt(dx*dx+dz*dz)
    local step=math.min(4,len);local best,score
    local function bounded(v)
        local hd=math.sqrt(v:DistSq(self.anchor));local qd=math.sqrt(v:DistSq(qp))
        local home_limit=self.late and 40 or 18;local queen_limit=self.late and 18 or 12
        return (hd<=home_limit and home<=home_limit or hd<home-.1)
            and (qd<=queen_limit and dist<=queen_limit or qd<dist-.1)
    end
    local function candidate(v)
        if bounded(v) and Nav.Safe(c,v,queen) then
            local value=v:DistSq(goal)
            if not score or value<score then best,score=v,value end
        end
    end
    if len>.05 then
        candidate(Vector3(pos.x+dx/len*step,0,pos.z+dz/len*step))
        for i=0,23 do local a=i*math.pi/12;candidate(Vector3(pos.x+math.cos(a)*step,0,pos.z+math.sin(a)*step)) end
    end
    c:Move(best or Nav.Escape(c,goal,queen,bounded) or pos,label)
end
-- 攻击第14帧结算。打空在朝向前方4码，命中在目标脚下；提前保留两种候选落蜜区。
function Queen:Honey(queen,pos,now)
    local retained={};for _,v in ipairs(self.predicted or {}) do if now<v.untiltime then retained[#retained+1]=v end end;self.predicted=retained
    local attacking=queen.AnimState:IsCurrentAnimation("atk")
    local frame=queen.AnimState.GetCurrentAnimationFrame and queen.AnimState:GetCurrentAnimationFrame() or 0
    if attacking and not self.honey_attack then self.honey_attack=true;self.honey_impact=nil end
    if attacking and not self.honey_impact and frame>=12 then
        self.honey_impact=true
        local q=queen:GetPosition();local r=queen.Transform:GetRotation()*math.pi/180
        local places={Vector3(q.x+math.cos(r)*4,0,q.z-math.sin(r)*4)}
        if pos:DistSq(q)<(6+self.c.player:GetPhysicsRadius(0))^2 then places[#places+1]=Vector3(pos.x,0,pos.z) end
        for _,pt in ipairs(places) do local zone={pos=pt,radius=1.85,untiltime=now+4.8,honey=true};self.predicted[#self.predicted+1]=zone;self.c.hazards[#self.c.hazards+1]=zone end
    end
    if not attacking then self.honey_attack=nil end
end
function Queen:Tick()
    self.c.blocked=false
    if self.c.gear then self.c.gear.forced_weapon=nil end
    local c=self.c;local queen
    for _,e in ipairs(c.enemies) do if e.prefab=="beequeen" and c.bridge.allowed(e) then queen=e;break end end
    -- 直线带蜂会超过24码常规选敌半径，不能因此丢失仍有效的蜂后战。
    if not queen and self.phase and self.phase>=3 and self.queen and self.queen:IsValid() and c.bridge.allowed(self.queen) then queen=self.queen end
    if not queen then require("shadowself/control/queenflute").Reset(self);Debug.End(c,"queen_unavailable");GuardHands.Release(self);self.allow=nil;self.flute_cycle=nil;self:ReleaseTravel();return false end
    self:Anchor(queen)
    local p=c.player;local pos=p:GetPosition();local qp=queen:GetPosition();local now=GetTime()
    local distance=math.sqrt(pos:DistSq(qp))
    local flute=self:Item("panflute")
    local candidates={};local seen={}
    local function collect(list)
        for _,e in ipairs(list) do
            local health=e.replica and e.replica.health
            if e.prefab=="beeguard" and e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") and not e:HasTag("INLIMBO")
                and not (health and health.IsDead and health:IsDead()) and not seen[e] then seen[e]=true;candidates[#candidates+1]=e end
        end
    end
    collect(c.enemies)
    if self.phase>=3 then
        for known in pairs(self.roster or {}) do collect({known}) end
    end
    -- 常规战斗只扫描24码；排箫不能漏掉战场另一侧的守卫。
    if flute or self.flute_cycle or self.phase>=3 then
        if now>=(self.next_flute_scan or 0) then
            self.flute_guards=TheSim:FindEntities(qp.x,0,qp.z,40,{"sleeper"},{"INLIMBO","isdead"});self.next_flute_scan=now+.2
        end
        collect(self.flute_guards or {})
    end
    local bees={};local nearest,near= nil,math.huge;local far=true
    for _,e in ipairs(candidates) do if e.prefab=="beeguard" then
        bees[#bees+1]=e;local d=math.sqrt(pos:DistSq(e:GetPosition()))
        if not Status.Sleeping(e) and d<near then nearest,near=e,d end
        if e:GetPosition():DistSq(qp)<81 then far=false end
    end end
    self.debug_bees=bees
    GuardControl.Observe(self,bees,now)
    local health=queen.replica and queen.replica.health
    local percent=health and health.GetPercent and health:GetPercent()
    if percent then self.phase=math.max(self.phase,percent<=.25 and 4 or percent<=.5 and 3 or percent<=.75 and 2 or 1) end
    local added=false;local surviving=false;local roster={}
    for _,e in ipairs(bees) do roster[e]=true;if self.roster[e] then surviving=true else added=true end end
    if #bees>5 then self.phase=math.max(2,self.phase) end
    if added and surviving and self.had_roster then self.phase=math.max(2,self.phase) end
    self.roster=roster;self.had_roster=self.had_roster or #bees>0
    local command=false
    for _,a in ipairs({"command1","command2","command3"}) do if queen.AnimState:IsCurrentAnimation(a) then command=true end end
    local command_start=command and not self.was_command;self.was_command=command
    if command then self.phase=math.max(3,self.phase) end
    local previous_late=self.late;self.late=self.phase>1
    if self.late and not previous_late then self:Lure(now) end
    self:Honey(queen,pos,now)
    if require("shadowself/control/queenspawn").Tick(self,queen,bees,now) then return true end
    if self.late then self.recycle_guard=nil end
    local recycle=not self.late and (#bees==1 and GuardControl.Recycle(self,bees[1],now) or self.recycle_guard)
    local controlling=not recycle and not self.late and #bees==1 and nearest and not Status.Controlled(nearest)
    if not controlling then GuardHands.Release(self) end
    if self.phase>=3 and #bees>0 then
        require("shadowself/control/queenflute").Reset(self)
        return require("shadowself/control/queendash").Tick(self,queen,bees,now)
    end
    if self.late and #bees>0 and (flute or self.flute_cycle) then
        if require("shadowself/control/queenflute").Tick(self,queen,bees,flute,now) then return true end
    end
    require("shadowself/control/queenflute").Reset(self)
    if recycle then
        GuardHands.Release(self);c.gear.forced_weapon=nil
        self:Target(recycle);c.status="蜂后 · 击杀高抗性守卫，换新一只留冰";return true
    end
    if not self.late and #bees>1 and nearest then
        -- 原版第一阶段补兵阈值为1，留最后一只可避免重新补四只。
        self:Target(nearest);c.status="蜂后 · 首批守卫清至一只";return true
    end
    if controlling then
        local wand=self:Item("icestaff") or self:Item("firestaff") or self:Item("torch")
        if wand then
            self:Target(nearest);c.blocked=true
            self.casting_guard=nearest
            c.gear.forced_weapon=wand;c.bridge.chasing=nil;if c.travel then c.travel.chasing=nil end
            self:ReleaseTravel()
            if c.travel then c.travel.dodging=nil;c.travel.restore_dodge=nil end
            local radius=nearest.GetPhysicsRadius and nearest:GetPhysicsRadius(0) or .5
            local equipped=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==wand
            local combat=p.replica.combat
            local range=equipped and combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or (wand.prefab=="torch" and 2 or 8)
            local reach=range+radius-.15
            local hit=(TUNING.BEEQUEEN_HIT_RANGE or 6)+(p.GetPhysicsRadius and p:GetPhysicsRadius(0) or .5)+.3
            -- 即使人物正忙、法杖尚未装备或攻击冷却未到，蜂后出招也先走位。
            if require("shadowself/control/guarddefence").Tick(self,queen,now) then return true end
            local stats=self.guard_stats and self.guard_stats[nearest]
            if wand.prefab=="icestaff" and stats and stats.shots>=GuardControl.MAX_SHOTS then
                -- 等最后一发弹道/复制反馈，期间禁止继续补冰；近身守卫先拉开。
                local bp=nearest:GetPosition();local d=math.sqrt(pos:DistSq(bp))
                if d<3 then
                    local dx,dz=pos.x-bp.x,pos.z-bp.z
                    if d<.01 then dx,dz,d=1,0,1 end
                    local goal=Nav.Select(c,Vector3(pos.x+dx/d*3,0,pos.z+dz/d*3),queen)
                    if pos:DistSq(goal)>.25 then c:Move(goal,"蜂后 · 拉开守卫，等待冰弹反馈后换新蜂") end
                end
                c.status="蜂后 · 冰杖达到本轮上限，等待弹道反馈";return true
            end
            local ready=GuardHands.Set(self,wand,"freeze")
            equipped=ready and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==wand
            local danger=GuardPosition.Windup(queen) and distance<hit
            if danger or not GuardPosition.Shot(c,queen,nearest,pos,reach) then
                local goal,side=GuardPosition.Point(c,queen,nearest,reach,self.guard_side)
                if goal then self.guard_side=side;c:Move(goal,danger and "蜂后 · 躲开本体出招，再绕守卫冻蜂" or "蜂后 · 围绕守卫找冻蜂角度") end
            elseif now>=self.next_support and not p.components.playercontroller:IsBusy() and equipped then
                if A.Attack(p,nearest) then self.next_support=now+.5 end
            end
            if not danger then c.status="蜂后 · 抓住射程窗口冻结守卫" end
            return true
        end
    end
    if controlling and not (self:Item("icestaff") or self:Item("firestaff") or self:Item("torch")) then GuardHands.Release(self) end
    if self.casting_guard and nearest and Status.Controlled(nearest) then
        self.casting_guard=nil;c.gear.forced_weapon=nil
        c.bridge.chasing=nil;if c.travel then c.travel.chasing=nil end
    end
    if c.blocked then return true end
    self:Target(queen)
    if not self.late then return self:Strike(queen,pos,qp,distance) end
    if #bees==0 then self.stage="strike";return self:Strike(queen,pos,qp,distance) end
    if command_start and self.stage~="return" then self:Lure(now) end
    local awake=false;local threat_near=math.huge
    for _,e in ipairs(bees) do if not e:HasTag("sleeping") and not Status.Frozen(e) then
        awake=true;threat_near=math.min(threat_near,math.sqrt(pos:DistSq(e:GetPosition())))
    end end
    local formed=self:Formation(queen,bees,pos);self.formed=formed
    if awake and not formed and self.stage~="lure" then self:Lure(now) end
    local guard_attack=false
    for _,e in ipairs(bees) do
        if (c.observed or {})[e.GUID] and c.observed[e.GUID].dodge and pos:DistSq(e:GetPosition())<5^2 then guard_attack=true end
    end
    if self.stage=="strike" and awake and (threat_near<4.2 or guard_attack) then self:Lure(now) end
    if self.stage=="lure" then
        self.lure_since=self.lure_since or now
        local limit=distance>=17 or pos:DistSq(self.anchor)>=36^2 or now-self.lure_since>=7
        if not awake or formed then
            self:Return(now,queen,bees)
        else
            local dx,dz=pos.x-qp.x,pos.z-qp.z
            if dx*dx+dz*dz<.01 then dx,dz=1,0 end
            local d=math.sqrt(dx*dx+dz*dz)
            if limit then
                -- Change to a long tangent leg at the leash; never return to melee inside an unseparated pack.
                self.long_dir=self.long_dir or {x=-dz/d,z=dx/d};self.lure_since=now
                dx,dz,d=self.long_dir.x,self.long_dir.z,1
            else self.long_dir=nil end
            local step=distance<17 and math.min(4,17-distance) or 4
            local goal=Vector3(pos.x+dx/d*step,0,pos.z+dz/d*step)
            self:Move(goal,"蜂后 · 直线拉开，让蜂后超过守卫",queen);return true
        end
    end
    if self.stage=="return" then
        if distance<5 and (formed or not awake) and (threat_near>4.2 or not awake) then
            self.stage="strike";return self:Strike(queen,pos,qp,distance)
        end
        local direction=self.return_dir or {x=1,z=0}
        local goal=Vector3(qp.x+direction.x*3.2,0,qp.z+direction.z*3.2)
        self:Move(goal,"蜂后 · 换边切回，让守卫留在蜂后后方",queen);return true
    end
    -- 交回3014完成攻击与本体招式躲避，蜂蜜地面由统一路径层排除。
    return self:Strike(queen,pos,qp,distance)
end
local Tick=Queen.Tick
function Queen:Tick()
 local result=Tick(self);Debug.Sample(self);return result
end
return Queen
