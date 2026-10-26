-- 织影者专属决策，由已有监督协程调用；攻击仍使用原走A，不增加操作线程。
local A=require("shadowself/control/actions")
local O=require("shadowself/control/weaver/observe")
local R=require("shadowself/control/weaver/route")
local D=require("shadowself/control/weaver/debug")
local S=require("shadowself/control/weaver/sanity")
local Cycle=require("shadowself/control/weaver/cycle")
local Ranged=require("shadowself/control/weaver/ranged")
local Phase1=require("shadowself/control/weaver/phase1")
local W=Class(function(self,c) self.c=c;self.state=O.New();self.entities={};self.channelers={};self.minions={};self.bodies={} end)
local function dist(a,b) return math.sqrt(a:DistSq(b)) end
local function pr(e) return e.GetPhysicsRadius and e:GetPhysicsRadius(0) or .5 end
function W:Active() return O.Live(self.boss) end
function W:Participant(e) return e and (e==self.boss or e.prefab=="shadowchanneler" or O.IsMinion(e)) end
function W:Holding() return self:Active() and self.holding or false end
function W:SetMode(mode)
    if self.mode~=mode then self.mode=mode;self.point=nil;self.next_path=nil;D.Emit(self,"mode") end
    self.c.status="织影者 · "..mode
end
function W:Scan()
    local now=GetTime();local p=self.c.player:GetPosition()
    if now<(self.next_scan or 0) then return end
    self.next_scan=now+(self:Active() and .1 or .3)
    local entities=TheSim:FindEntities(p.x,0,p.z,40,nil,{"INLIMBO","DECOR"})
    local boss=self:Active() and self.boss or nil
    if not boss then for _,e in ipairs(entities) do
        if e.prefab=="stalker_atrium" and O.Live(e) and self.c.bridge.allowed(e) then boss=e;break end
    end end
    if not boss then if self.boss then self:Stop() end;return end
    if boss~=self.boss then
        self.boss=boss;self.state=O.New();self.old_priority=self.c.bridge.priority_target;self.started=now
        self.home=p
        D.Emit(self,"begin","client_observation_only")
    end
    self.entities={};self.channelers={};self.minions={};self.bodies={};self.fences={};self.obstacles={};self.cages={};self.marker=nil
    local bp=boss:GetPosition()
    for _,e in ipairs(entities) do if e:IsValid() and (e:GetPosition():DistSq(bp)<32^2 or e.prefab=="atrium_fence" or O.IsMinion(e) and R.InArena(self,e:GetPosition())) then
        self.entities[#self.entities+1]=e
        if e.prefab~="atrium_fence" and R.StaticRadius(e) then self.obstacles[#self.obstacles+1]=e end
        -- 原版栅栏没有wall/structure标签，且寻路网格不能代表人物能穿过缝隙。
        if e.prefab=="atrium_fence" and not e:HasTag("INLIMBO") then self.fences[#self.fences+1]=e end
        if e.prefab=="shadowchanneler" and O.Live(e) then self.channelers[#self.channelers+1]=e
        elseif O.IsMinion(e) and O.Live(e) then self.minions[#self.minions+1]=e
        elseif e.prefab=="atrium_gate" then self.center=e:GetPosition()
        elseif e.prefab=="blinkfocus_marker" and p:DistSq(e:GetPosition())<3^2 then self.marker=e end
        if O.SolidCage(e) then self.cages[#self.cages+1]=e end
        if O.Live(e) and e~=self.c.player and (O.IsMinion(e) or e:HasTag("wall") or e:HasTag("structure") or e==boss) and not e:HasTag("NOBLOCK") then self.bodies[#self.bodies+1]=e end
    end end
    table.sort(self.channelers,function(a,b) return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition()) end)
    table.sort(self.minions,function(a,b) return p:DistSq(a:GetPosition())<p:DistSq(b:GetPosition()) end)
    for _,event in ipairs(O.Minions(self.state,self.entities,now)) do
        if event.reason=="consumed" then self.fed=(self.fed or 0)+1 end
        if event.reason=="unknown" and self.state.feasting then self.feed_uncertain=(self.feed_uncertain or 0)+1 end
        D.Emit(self,"minion_"..event.reason,event.entity.GUID)
    end
    self.zones=R.Zones(self)
end
function W:Ranges()
    local t=TUNING or {};local adventure=self.boss:HasTag("adventure")
    local capture=adventure and 24 or t.STALKER_SNARE_RANGE or 12
    local resolve=adventure and 24 or t.STALKER_SNARE_MAX_RANGE or 15
    if self.expanded_snare then capture=math.max(capture,24);resolve=math.max(resolve,24) end
    return capture,resolve
end
function W:CancelSupport()
    if self.c.gear.action_hold==self.support then self.c.gear.action_hold=nil end
    self.support=nil
end
function W:Halt()
    -- A.Stop会清服务器走路状态；必须同时清原生预测标志，下次才能发送isstart=true。
    local c=self.c
    if c.h.StopPredictWalk then c.h:StopPredictWalk() end
    A.Stop(c.player)
    self.moving=nil;self.point=nil;self.motion=nil;c.next_move=nil
    c.last_point=nil;c.last_action_kind=nil
end
function W:Hold(mode,stop)
    local c=self.c;self.holding=true;c.blocked=true;c.special_active=true
    c.bridge:PauseAttack();c.bridge.chasing=nil;c.travel.chasing=nil
    if stop and self.moving then
        self:Halt()
    end
    self:SetMode(mode)
end
function W:Move(goal,mode,target,urgent)
    local previous=self.point;local wasmoving=self.moving
    self:CancelSupport();self:Hold(mode)
    local c=self.c;local now=GetTime();local p=c.player:GetPosition()
    local short=self.shock_point and goal==self.shock_point
    if self.corner_dodge and goal==self.corner_dodge.point and not self.corner_dodge.started then
        -- 短躲也必须撤销旧的朝Boss接近预测，不能继承PauseAttack重发旧点后的移动限流。
        self:Halt()
    end
    if short and self.shock_command~=self.shock_run then
        self:Halt();self.shock_command=self.shock_run
        D.Emit(self,"shock_run","cancel_old_attack_prediction_before_short_retreat")
    end
    if urgent then c.travel:BeginDodge(c.snapshot) end
    -- 已选路线走完一段再续接，不能每0.15秒重新挑脚前的小点。
    local remaining=self.point and dist(p,self.point) or 0
    local behind=self.point and (self.point.x-p.x)*(goal.x-p.x)+(self.point.z-p.z)*(goal.z-p.z)<=0
    local retreatleg=self.retreat and goal==self.retreat.points[self.retreat.index]
    local planned=retreatleg or self.staff_action and goal==self.staff_action.point or self.corner_dodge and goal==self.corner_dodge.point or self.phase1 and goal==self.phase1.waypoint or goal==self.bait_point or goal==self.escape_point or self.cycle and (goal==self.cycle.route_waypoint or goal==self.cycle.pull_point or goal==self.cycle.hand_point or goal==self.cycle.corner_waypoint or goal==self.cycle.corner or goal==self.cycle.round_dodge)
    local critical=self.snare_run and goal==self.snare_run.point
    local segment=goal

    local physical_melee=self.corner_dodge and goal==self.corner_dodge.point
        and dist(p,self.boss:GetPosition())<3.8+pr(c.player)+.2
        and self.state.anim=="attack" and self.corner_dodge.cast==self.state.melee_started
    physical_melee=physical_melee or retreatleg and self.state.anim=="attack"
        and dist(p,self.boss:GetPosition())<3.8+pr(c.player)+.2
    if (planned or critical or short) and R.Path(self,segment,target,urgent,false,nil,physical_melee) then
        -- 已验证的整段直接执行，不能再让局部边缘打分把它改成斜走/短步。
        self.point=segment;self.edge_routing=nil
    elseif not self.point or remaining<math.max(.9,c:Speed()*.18)
        or behind
        or not R.Path(self,self.point,target,urgent)
        or now>=(self.next_path or 0) and self.point:DistSq(goal)>6^2 then
        self.point=R.Choose(self,goal,target,urgent);self.next_path=now+.6
    end
    if self.edge_routing then c.status=c.status.."（贴边转向开阔区域）" end
    local cornerleg=self.corner_dodge and self.corner_dodge.points and goal==self.corner_dodge.point
    local turning=retreatleg and self.retreat.index<self.retreat.band or cornerleg and self.corner_dodge.index<#self.corner_dodge.points
    local arrival=turning and .005 or (retreatleg or cornerleg) and .04 or goal==self.bait_point and .08 or .2
    if self.point and p:DistSq(self.point)>arrival^2 then
        if critical and self.snare_command~=self.snare_run.cast then
            -- 骨牢起手可能发生在回身追近途中；立即撤销朝Boss的旧预测，不继承0.1秒移动限流。
            local bp=self.boss:GetPosition()
            local carry=wasmoving and previous and dist(previous,bp)>dist(p,bp)
                and (previous.x-p.x)*(goal.x-p.x)+(previous.z-p.z)*(goal.z-p.z)>0
            if not carry and c.h.StopPredictWalk then c.h:StopPredictWalk() end
            self.snare_command=self.snare_run.cast;c.next_move=nil;self.motion=nil
            local run=self.snare_run
            D.Emit(self,"snare_run",string.format("radial_deadline_locked reachable=%s budget=%.2f travel=%.2f",
                tostring(run.reachable),run.budget or -1,run.travel or -1))
        end
        -- 所有机制移动持移速装备，只有真正接近攻击目标时才允许恢复武器。
        local reach=target and c.gear:AttackRange()+pr(target) or 0
        if not urgent and (not target or c.travel.dodging or dist(p,target:GetPosition())>reach+2) then c.travel:BeginDodge(c.snapshot) end
        -- 追击期间不EndDodge换武器；真正到攻击位置后先Halt清预测，再统一恢复武器。
        local pc=c.player.components.playercontroller
        if self.motion and now-self.motion.time>=.5 then
            local moved=dist(p,self.motion.pos)
            if moved<.15 and p:DistSq(self.point)>1 and not pc:IsBusy() then
                self:Halt()
                self.point=(planned or critical or short) and R.Path(self,segment,target,urgent) and segment or R.Choose(self,goal,target,urgent)
                D.Emit(self,"movement_restart",string.format("displacement=%.2f",moved))
            end
            self.motion=nil
        end
        self.motion=self.motion or {pos=p,time=now}
        if not self.point then return true end
        if self.corner_dodge and goal==self.corner_dodge.point then self.corner_dodge.started=true end
        c:Move(self.point,c.status);self.moving=true;self.stuck_since=nil
    else
        local arrived=self.point and p:DistSq(self.point)<=arrival^2
        if self.moving then self:Halt() end
        if arrived then self.stuck_since=nil;return true end
        self.stuck_since=self.stuck_since or now
        if now>=(self.next_block_log or 0) then
            self.next_block_log=now+1
            local blocker=R.Blocker(self,p,goal)
            local _,path_reason=R.Path(self,goal,target,urgent)
            local ep=blocker and blocker:GetPosition()
            D.Emit(self,"route_blocked","clearance="..R.Clearance(p,self).." passable="..tostring(R.Passable(p))
                .." blocker="..(blocker and (blocker.prefab..":"..tostring(blocker.GUID)..string.format("@%.2f,%.2f",ep.x,ep.z)) or path_reason or "terrain/hole/hazard"))
        end
    end
    return true
end
function W:BeginRetreat()
    self.retreat=nil
    local q=R.BeginRetreat(self)
    D.Emit(self,"retreat_plan",string.format("complete=%s hit_ok=%s nodes=%d length=%.2f",tostring(q.complete),tostring(q.hit_ok),q.band,q.length))
end
-- 所有诱牢请求只在这里建立一个路线事务；阶段模块只请求，不各自保存另一条退路。
function W:ReserveRetreat(kind,until_time)
    Ranged.Interrupt(self,"reserve_"..kind);self:CancelSupport()
    self.rebait=nil;self.bait_waited=nil;self.lure_walk_since=nil;self.lure_pursuit=nil;self.bait_hold=nil
    self.escape_point=nil;self.escape_turn=nil;self.next_escape=nil
    self.feast_lure=kind=="feast" or kind=="feast_tail";self.feast_tail=kind=="feast_tail";self.spawn_lure=kind=="spawn"
    self.lure_until=until_time or GetTime()+4
    self:BeginRetreat()
    D.Emit(self,"lure_after_"..kind,"single_retreat_owner")
end
function W:Retreat()
    if not self.retreat then self:BeginRetreat() end
    local q=self.retreat
    if self.staff_action and (self.state.feasting or self.state.summoning or self.state.channeling) and Ranged.Tick(self) then return true end
    local goal,waiting,blocked=R.RetreatGoal(self)
    if blocked or not q.complete and q.points[q.index]:DistSq(self.c.player:GetPosition())<.06^2 then
        if q.mode=="escape" then
            self.retreat=nil
            local _,resolve=self:Ranges()
            return self:Move(R.SnareRun(self,self.state.frame,resolve),"骨牢实际起手后绕新障碍继续撤离",nil,true)
        end
        if GetTime()>=(self.next_retreat_plan or 0) then
            self.next_retreat_plan=GetTime()+.75;self:BeginRetreat()
            goal,waiting,blocked=R.RetreatGoal(self);q=self.retreat
        end
    end
    if waiting then
        self.bait_waited=true
        if Cycle.RootedWork and Cycle.RootedWork(self) then return true end
        self:Hold("已到完整路线的识别带，保留出口等实际骨牢",true);return true
    end
    if goal then
        self.avoid_boss=nil
        return self:Move(goal,q.mode=="escape" and "沿已选完整通道跑出实际骨牢" or "持手杖沿同一完整通道准备骨牢",nil,true)
    end
    self:Hold("完整通道出现新障碍，等待合法路线重算",true);return true
end
function W:Equip(item,slot,mode)
    local c=self.c;local p=c.player;local now=GetTime()
    if p.replica.inventory:GetEquippedItem(slot)==item then self:CancelSupport();return false end
    self:Hold(mode,true)
    if not self.support or self.support.item~=item then
        self:CancelSupport();self.support={item=item,slot=slot,deadline=math.max(now,self.next_equip or now)+1.5};c.gear.pending=nil;c.gear.action_hold=self.support
    end
    if now>self.support.deadline then self:CancelSupport();self.next_equip=now+2;return true end
    local pc=p.components.playercontroller
    if now>=(self.next_equip or 0) and not pc:IsBusy() and not O.Controlled(p) then
        A.Self(p,item,ACTIONS.EQUIP);self.next_equip=now+.4
    end
    return true
end
function W:Item(name)
    local selected
    for _,e in ipairs(A.Items(self.c.player)) do if e.prefab==name and e:IsValid() then
        if self.amulet==e or self.blinkstaff==e or self.support and self.support.item==e then return e end
        selected=selected or e
    end end
    return selected
end
function W:Shielded()
    local shield=O.Shield(self.boss)
    return shield==true or shield==nil and (#self.channelers>0 or self.state.channeling)
end
function W:Threat()
    local name,f=O.Animation(self.boss);local p=self.c.player:GetPosition();local bp=self.boss:GetPosition()
    local lag=self.c:Latency()
    local hitrange=math.max(3.8,(self.boss.replica.combat and self.boss.replica.combat.GetAttackRangeWithWeapon and self.boss.replica.combat:GetAttackRangeWithWeapon() or 2.4)+1.4)+pr(self.c.player)+.6
    if name=="attack" and f<=32+math.ceil(lag*30) then
        -- 先骗到真实普攻才拉远；利用它到63帧才解除busy的时间预留骨牢退路。
        local capture,resolve=self:Ranges()
        if self.lure_until then
            if self.state.anim~="attack" then return p,"等待实际普攻观察，保留撤退接管",hitrange end
            if not self.retreat then self:BeginRetreat() end
            local goal,waiting,blocked=R.RetreatGoal(self)
            if blocked or not self.retreat.complete and goal and goal:DistSq(p)<.06^2 then return nil end
            if waiting then self.bait_waited=true end
            -- 不把完整路线失败重新交给CornerDodge；重算也由同一个Retreat状态负责。
            return goal or p,"持手杖沿同一完整通道准备骨牢",hitrange
        end
        -- 普攻锁定且已在判定范围外，才能利用busy窗口处理鬼手。
        -- 与路径的5.15码保护边界一致；目标留更大余量，实际已安全时不因0.02码回弹抢换装。
        local actual_hit=((TUNING and TUNING.STALKER_HIT_RANGE) or 3.8)+pr(self.c.player)+.2
        local dodge=self.corner_dodge
        local committed=dodge and dodge.cast==self.state.melee_started and dodge.started
        if not self.lure_until and not committed and dist(p,bp)>=(self.cycle and hitrange+.25 or actual_hit) then return nil end
        -- 已执行的短躲持续占有这一巴掌的结算窗口；安全后不提前恢复原走A追近。
        if committed and not self.lure_until and dist(p,bp)>=actual_hit-.03 then
            local fixed=R.CornerDodge(self,hitrange+.55)
            return fixed or p,"沿既定方向完成短躲，等普攻实际结算后输出",hitrange
        end
        if Cycle.OpeningAllowed and Cycle.OpeningAllowed(self) then return nil end
        local side=R.CornerDodge(self,hitrange+.55)
        local pillar_side=side~=nil
        side=side or Cycle.RoundDodge and Cycle.RoundDodge(self,hitrange+.55)
        if side then
            if pillar_side and not self.lure_until and R.MeleeOutputWindow(self,side) then return nil end
            if self.corner_dodge and not self.corner_dodge.logged then
                self.corner_dodge.logged=true
                D.Emit(self,"corner_side_dodge",string.format("point=%.2f,%.2f boss=%.2f,%.2f frame=%d reachable=%s",side.x,side.z,bp.x,bp.z,f,tostring(self.corner_dodge.reachable)))
            end
            return side,"柱旁骗A后沿边横移，躲完继续输出",hitrange
        end
        local retreat=R.Point(bp,p,hitrange+(self.cycle and .55 or .35))
        if not self.lure_until and R.FightCorners(self) and R.Path(self,retreat,nil,true) and R.MeleeOutputWindow(self,retreat) then return nil end
        return retreat,"躲普攻结算",hitrange
    elseif name=="attack1" and f<=26+math.ceil(lag*30) then
        if self.retreat then
            R.RetreatCast(self)
            local goal=R.RetreatGoal(self)
            if goal then return goal,"沿已选完整通道跑出实际骨牢",3.5+pr(self.c.player)+.3 end
            self.retreat=nil
        end
        local _,resolve=self:Ranges()
        return R.SnareRun(self,f,resolve),"骨牢前摇向外脱离",3.5+pr(self.c.player)+.3
    elseif name=="spike" then
        -- 螺旋落点由实际fossilspike2危险区局部避让，不为整段动画跑出大门圈。
        -- 第51帧仍有3.5码近身震地；按当前距离/移速只提前足够跑开的时间。
        local safe=3.5+pr(self.c.player)+.3
        local travel=math.max(0,safe-dist(p,bp))/math.max(1,self.c:Speed())
        local lead=math.ceil((travel+lag+.35)*30)
        if (f>=51-lead or self.spike_guard==self.state.spike_count) and f<=51+math.ceil(lag*30)+2 then
            self.spike_guard=self.state.spike_count
            -- 短撤到位不能压住脚下正在落地的螺旋骨刺，交回下方局部危险区避让。
            if R.Risk(self,p)>0 then return nil end
            return dist(p,bp)>=safe+.15 and p or R.ShortDodge(self,safe+.3),"短撤避开骨刺末段近身震地",safe+.15
        end
    end
end
-- 原生ShouldAttack/DoAttack只检查已经存在的决策，不允许在预览/RPC guard里规划或推进路线。
function W:AttackDanger(e)
    local name,f=O.Animation(self.boss);local p=self.c.player:GetPosition();local bp=self.boss:GetPosition()
    local lag=self.c:Latency()
    if name=="attack" and f<=32+math.ceil(lag*30) then
        local q=self.cycle
        if q and q.opening_hand==e and q.opening_cast==self.state.melee_started
            and GetTime()+8/30<q.opening_deadline then return false end
        local dodge=self.corner_dodge
        if dodge and dodge.cast==self.state.melee_started then
            return dodge.started or not R.MeleeOutputWindow(self,dodge.point)
        end
        return dist(p,bp)<((TUNING and TUNING.STALKER_HIT_RANGE) or 3.8)+pr(self.c.player)+.2
    elseif name=="attack1" and f<=26+math.ceil(lag*30) then return true
    elseif name=="spike" then
        local safe=3.5+pr(self.c.player)+.3
        local travel=math.max(0,safe-dist(p,bp))/math.max(1,self.c:Speed())
        return f>=51-math.ceil((travel+lag+.35)*30) and f<=51+math.ceil(lag*30)+2 and dist(p,bp)<safe+.15
    end
    return false
end
function W:AttackBlocked(e)
    if not self:Active() then return false end
    if not self:Participant(e) then return self.holding end
    if self.rebait or self.lure_until and GetTime()<self.lure_until or Phase1.BlockAttack(self,e) or Cycle.BlockAttack(self,e) then return true end
    if not O.Live(e) or e:HasTag("notarget") or O.Controlled(self.c.player) then return true end
    if e==self.boss and self:Shielded() then return true end
    if e~=self.focus or self.holding then return true end
    if self:AttackDanger(e) then return true end
    return R.Risk(self,self.c.player:GetPosition())>0
end
function W:Hand(e,mode)
    local c=self.c;local p=c.player;local now=GetTime()
    self:CancelSupport();self.focus=e;c.target=e;self:Hold(mode)
    local combat=p.replica.combat
    local held=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    local reach=(held and held.prefab=="staff_lunarplant" and 8 or combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 2)+pr(e)
    if dist(p:GetPosition(),e:GetPosition())>reach-.1 then
        return self:Move(R.Point(e:GetPosition(),p:GetPosition(),math.max(1,reach-.3)),mode.."持手杖接近",e,true)
    end
    if self.moving then self:Halt() end
    if held and held.prefab=="staff_lunarplant" and e.prefab=="shadowchanneler"
        and (not Ranged.GhostReady(self,e) or not Ranged.CanLaunch(self,e)) then
        self:Hold("鬼手尚未可受击／安全期限不足以覆盖首发弹道，保留目标重试");return true
    end
    if now>=(self.next_hand or 0) and not p.components.playercontroller:IsBusy() and not p:HasTag("attack") then
        -- 鬼手只有1滴血，直接使用当前手持物；不恢复主武器，也不启动会请求fight换装的走A。
        if A.Attack(p,e,function()
            return self:Active() and self.focus==e and O.Live(e) and not e:HasTag("notarget")
                and (e.prefab~="shadowchanneler" or S.Ready(self))
                and not self.rebait and (not self.lure_until or Ranged.Allowed(self,e)
                    or Cycle.RootWorkAllowed and Cycle.RootWorkAllowed(self,e)) and not O.Controlled(p)
                and Cycle.LightAllowed(self,e) and S.HandWindow(self) and not self:AttackDanger(e) and R.Risk(self,p:GetPosition())==0
        end) then
            self.next_hand=now+.65;self.light_sent={target=e,time=now}
            Ranged.Sent(self,e,held)
            D.Emit(self,"hand_attack",held and held.prefab or "empty_hands")
        end
    end
    return true
end
function W:Attack(e,mode)
    if e.prefab=="shadowchanneler" then return self:Hand(e,mode) end
    local c=self.c;local p=c.player:GetPosition()
    self:CancelSupport()
    if c.player:HasTag("attack") and O.Live(self.focus) and not (self.focus==self.boss and self:Shielded()) then e=self.focus end
    self.focus=e;c.target=e;self.holding=false;c.blocked=false;c.special_active=true
    self.zones=R.Zones(self)
    local reach=math.max(1,c.gear:AttackRange()+pr(e))
    -- 余下最后一段由原走A追近并攻击，不能卡在移动到达半径与出手距离之间。
    -- 已接手后完全交给原走A；只由实际技能威胁暂停，不再以距离二次抢走线程。
    if not c.bridge:OwnsThread() and dist(p,e:GetPosition())>reach+1.2 then
        return self:Move(R.Point(e:GetPosition(),p,reach+.3),mode.."接近",e,false)
    end
    if self.moving then self:Halt() end
    self.point=nil;c.travel:EndDodge(c.snapshot)
    self:SetMode(mode);c.bridge.priority_target=e
    if c.h.ent~=e then c.h.ent=e;c.target=e;c.bridge.wrappers.PreTheLoop.old(c.h) end
    if self:AttackBlocked(e) then self:Hold("等待本次攻击结算",true);return true end
    if not c.bridge:OwnsThread() then
        c.gear:Swap("attack",c.snapshot)
        local weapon=c.gear:Weapon()
        if not weapon or c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==weapon then
            c.bridge:ResumeAttack();D.Emit(self,"attack_resume","native_close_and_attack")
        end
    end
    return true
end
local function blinkable(item)
    if not item or not item:IsValid() or item:HasTag("nomagiccast") then return false end
    if item.prefab=="king_cane" and item._gem and item._gem.value then
        return item._gem:value()=="orangegem"
    end
    return item.prefab=="orangestaff" or item.HasActionComponent and item:HasActionComponent("blinkstaff")
end
function W:BlinkItem()
    local held=self.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if blinkable(held) then return held end
    local selected
    for _,item in ipairs(A.Items(self.c.player)) do if blinkable(item) then
        if item==self.blinkstaff then return item end
        if not selected or (item.GUID or 0)<(selected.GUID or 0) then selected=item end
    end end
    return selected
end
function W:Blink(point)
    local c=self.c;local p=c.player;local now=GetTime()
    if self.blink_sent then
        self:Hold("等待瞬移确认",true)
        if dist(p:GetPosition(),self.blink_before)>4 then
            local arrived=self.blink_destination and p:GetPosition():DistSq(self.blink_destination)<2.5^2
            self.blink_sent=nil;self.blink_destination=nil;self:CancelSupport();self.next_blink=now+1
            D.Emit(self,arrived and "blink_arrived" or "external_displacement",arrived and "requested_destination_reached" or "not_our_requested_destination")
            return true
        elseif now-self.blink_sent<1.5 then return true
        else self.blink_sent=nil;self.blink_destination=nil;self:CancelSupport();self.next_blink=now+2;D.Emit(self,"blink_timeout");return false end
    end
    self.blinkstaff=self:BlinkItem()
    if not self.blinkstaff or not ACTIONS.BLINK then self:CancelSupport();return false end
    if now<(self.next_blink or 0) then return false end
    if self:Equip(self.blinkstaff,EQUIPSLOTS.HANDS,"装备懒人魔杖脱困") then return true end
    local landing=R.Landing(self,point,self.blinkstaff)
    if not landing then
        self.next_blink=now+.35;D.Emit(self,"blink_no_landing","no_native_legal_point")
        return false
    end
    self:Hold("骨牢命中后瞬移脱困",true)
    local request={item=self.blinkstaff,kind="blink"}
    self.support=request;c.gear.action_hold=request
    if not p.components.playercontroller:IsBusy() and A.Ground(p,landing,ACTIONS.BLINK,function()
        return self.support==request and c.gear.action_hold==request and self:Active()
            and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==request.item and blinkable(request.item) and not O.Controlled(p)
    end) then
        self.blink_before=p:GetPosition();self.blink_destination=landing;self.blink_sent=now
        D.Emit(self,"blink_requested",string.format("item=%s landing=%.2f,%.2f",request.item.prefab,landing.x,landing.z))
    else
        self:CancelSupport()
        self.next_blink=now+.4
        D.Emit(self,"blink_rejected","busy_or_native_action_not_sent")
        return false
    end
    return true
end
function W:PrepareSanity() return S.Prepare(self) end
function W:PickChanneler()
    local now=GetTime();self.blocked_targets=self.blocked_targets or {}
    if self.stuck_since and now-self.stuck_since>.7 and self.focus then self.blocked_targets[self.focus]=now+2 end
    if O.Live(self.focus) and self.focus.prefab=="shadowchanneler" and not self.focus:HasTag("notarget")
        and now>=(self.blocked_targets[self.focus] or 0) then return self.focus end
    for _,e in ipairs(self.channelers) do if not e:HasTag("notarget") and now>=(self.blocked_targets[e] or 0) then return e end end
end
function W:BodyBlocker(target)
    local p=self.c.player:GetPosition();local q=target:GetPosition();local dx,dz=q.x-p.x,q.z-p.z
    local length=math.max(.01,dx*dx+dz*dz)
    for _,e in ipairs(self.minions) do if e~=self.reserve and not e:HasTag("notarget") then
        local ep=e:GetPosition();local t=math.max(0,math.min(1,((ep.x-p.x)*dx+(ep.z-p.z)*dz)/length))
        local foot=Vector3(p.x+dx*t,0,p.z+dz*t)
        if ep:DistSq(foot)<(pr(e)+pr(self.c.player)+.45)^2 and p:DistSq(ep)<5^2 then return e end
    end end
end
function W:_Tick()
    self:Scan();if not self:Active() then return false end
    local c=self.c;local s=self.state;local now=GetTime();local p=c.player:GetPosition();local bp=self.boss:GetPosition()
    if O.Update(s,self.boss,now) then D.Emit(self,"animation") end
    if s.anim=="attack1" then
        local m=self.snare_motion
        if not m or m.cast~=s.snare_started then
            m={cast=s.snare_started,time=now,origin=p,last=p,walked=0,startdist=dist(p,bp),hp=c.player.replica.health and c.player.replica.health:GetPercent()};self.snare_motion=m
        else m.walked=m.walked+dist(p,m.last);m.last=p end
        local hp=c.player.replica.health and c.player.replica.health:GetPercent()
        if hp and m.hp and hp<m.hp then m.hurt=true end
        m.hp=hp
        if O.Is(c.player,"hit") or O.Is(c.player,"hit_amulet") then m.hit_animation=true end
        if not m.delay and dist(p,m.origin)>.2 then m.delay=now-m.time end
    end
    R.BeginFrame(self)
    self.avoid_boss=nil -- 每次决策重新设威胁距离，不把上一招的禁止靠近半径遗留到后摇巡游。
    Phase1.Observe(self)
    Cycle.Observe(self)
    -- 从旧版本接管时也不能把疯狂装备遗留在身上；纳入同一个恢复事务。
    if self.cycle and not self.sanity_round and S.Wearing(self) then S.Prepare(self) end
    self.zones=R.Zones(self);self.avoid_boss=nil
    if O.Controlled(c.player) then
        self.retreat=nil
        if not self.was_controlled then Cycle.Interrupt(self,"actual_player_control") end
        self:CancelSupport();self:Hold("精神控制中等待实际解除")
        self.was_controlled=true;return true
    elseif self.was_controlled then self.was_controlled=nil;D.Emit(self,"control_released") end
    if self.blink_sent then return self:Blink(bp) end
    local cagecount=0;local solid={}
    for _,e in ipairs(self.cages) do if O.SolidCage(e) then
        solid[#solid+1]=e
        if p:DistSq(e:GetPosition())<3^2 then cagecount=cagecount+1 end
    end end
    self.cages=solid
    local centerx,centerz=0,0
    if cagecount>=3 then for _,e in ipairs(self.cages) do if p:DistSq(e:GetPosition())<3^2 then
        local q=e:GetPosition();centerx=centerx+q.x/cagecount;centerz=centerz+q.z/cagecount
    end end end
    local trapped=cagecount>0 and self.marker and p:DistSq(self.marker:GetPosition())<.9^2
        or cagecount>=3 and p:DistSq(Vector3(centerx,0,centerz))<1.1^2
    if trapped then
        self.retreat=nil
        Cycle.Interrupt(self,"actual_cage_hit")
        if self.caught_cast~=s.snare_started then
            self.caught_cast=s.snare_started
            local m=self.snare_motion or {}
            D.Emit(self,"snare_caught",string.format("start=%.2f reachable=%s initial=%.2f walked=%.2f delay=%.2f elapsed=%.2f hurt=%s hit_anim=%s",
                s.snare_started or -1,tostring(self.snare_run and self.snare_run.reachable),m.startdist or -1,m.walked or 0,m.delay or -1,now-(m.time or now),tostring(m.hurt==true),tostring(m.hit_animation==true)))
        end
        O.SnareResult(s,true,now)
        local _,resolve=self:Ranges()
        if dist(p,bp)>15.1 and resolve<=15 then self.expanded_snare=true;D.Emit(self,"expanded_snare_detected") end
        if self:Blink(R.Point(bp,p,math.min(dist(p,bp)+8,28))) then return true end
        -- 没有可用瞬移也不能跳过本体攻击判断；骨柱开口后立即走出，不等标记7.5秒消失。
        local goal,reason,avoid=self:Threat()
        self.avoid_boss=avoid
        local exit=R.Choose(self,goal or R.Point(bp,p,dist(p,bp)+4),nil,true)
        if exit and p:DistSq(exit)>.35^2 then return self:Move(exit,"沿骨牢缺口脱离／"..(reason or "远离本体"),nil,true) end
        self:Hold("骨牢未开口且无可用瞬移，监视本体攻击",true);return true
    end
    if s.snare_started and now>s.snare_started+1.05 and s.snare_result==nil then
        O.SnareResult(s,cagecount>0,now);D.Emit(self,"snare_result",cagecount>0 and "cage_visible" or "no_local_cage_shared_cd_uncertain")
    end
    -- Boss改变决定开始吞食，旧的“等它放骨牢”必须释放，否则有虫也永远进不了清理。
    local food=Cycle.HasFood and Cycle.HasFood(self)
    local cancel=s.feasting and not self.feast_lure
        or self.feast_lure and food and not self.feast_tail and s.feasting
    if cancel and (self.lure_until or self.rebait) then
        self.lure_until=nil;self.feast_lure=nil;self.feast_tail=nil;self.spawn_lure=nil;self.rebait=nil;self.bait_waited=nil;self.lure_walk_since=nil;self.lure_pursuit=nil
        self.bait_point=nil;self.escape_turn=nil;self.next_escape=nil
        if self.moving then self:Halt() end
        D.Emit(self,"lure_cancelled_feast","return_to_actual_food_cleanup")
    end
    if Cycle.RangedWindow and Cycle.RangedWindow(self) and self.spawn_lure then
        self.lure_until=nil;self.spawn_lure=nil;self.rebait=nil;self.bait_hold=nil;self.retreat=nil
    end
    local rooted=Cycle.RootExit and Cycle.RootExit(self)
    if rooted and not self.lure_until and not self.rebait then self:ReserveRetreat(rooted,now+4)end
    -- 这次已骗出的普攻是下一次技能选择前最后的退路窗口，不能等CD归零再找下一巴掌。
    if s.anim=="attack" and self.lure_attack~=s.melee_started then
        self.lure_attack=s.melee_started
        -- 3秒用于涵盖下一次普攻前可能就绪的技能，不代表busy持续3秒。
        local window=math.max(0,((TUNING and TUNING.STALKER_ATRIUM_ATTACK_PERIOD) or 3)-s.frame/30)+.5+c:Latency()
        if s.frame<=32 and Cycle.BaitAllowed(self) and (self.rebait or s.ready.snare and O.ReadyIn(s,"snare",now)<=window) then
            self:ReserveRetreat("melee",now+math.max(0,(63-s.frame)/30)+3)
        end
    end
    if s.anim=="attack1" and self.retreat then R.RetreatCast(self) end
    if s.anim=="spike" or s.controlling or (s.channeling or s.summoning) and not self.spawn_lure then self.retreat=nil end
    if not self.lure_until and self.retreat and self.retreat.mode=="prepare" then self.retreat=nil end
    if self.retreat and self.retreat.mode=="escape" and now>=(s.snare_started or now)+1.05 then self.retreat=nil end
    if s.anim=="attack1" or s.anim=="spike" or s.controlling or (s.channeling or s.summoning) and not self.spawn_lure then
        self.lure_until=nil;self.feast_lure=nil;self.feast_tail=nil;self.spawn_lure=nil;self.bait_waited=nil;self.lure_walk_since=nil;self.lure_pursuit=nil;self.rebait=nil
        self.bait_hold=nil
        if self.cycle then self.cycle.root_work=nil end
    end
    -- 到识别带却等来追击，说明这次诱牢没有成立。旧出口不能随Boss追击不停外推。
    -- 实际技能在上面先解除诱牢；召唤/吞食等停身动画仍保留其安全撤离准备。
    local walking=s.anim=="walk_pre" or s.anim=="walk_loop" or s.anim=="walk_pst"
    local pursuit=self.lure_pursuit
    if self.lure_until and walking then
        if not pursuit then
            pursuit={since=now,origin=bp,player=p,ready_since=nil};self.lure_pursuit=pursuit
        end
        if O.ReadyIn(s,"snare",now)<=0 then pursuit.ready_since=pursuit.ready_since or now
        else pursuit.ready_since=nil end
    else self.lure_pursuit=nil;pursuit=nil end
    local remaining=O.ReadyIn(s,"snare",now)
    -- CD临近时不能从识别带冲回即将落下的骨牢。只有来得及回身骗A，
    -- 或预计就绪后仍持续追击而未实际施法，才确认这次诱牢落空。
    local return_time=math.max(0,dist(p,bp)-2.6)/math.max(1,c:Speed())+c:Latency()+.25
    -- 至少跨过两次原版.5秒能力选择及往返观察余量，且Boss真的向等待位置追近。
    -- lure_until只标记计划寿命，不能绕过实际追击确认；idle/walk_pre本身不是落空。
    local observed=pursuit and now-pursuit.since>=1+2*c:Latency()
        and dist(bp,pursuit.origin)>=1.5
        and dist(bp,pursuit.player)<=dist(pursuit.origin,pursuit.player)-1
    local ready_missed=pursuit and pursuit.ready_since and now-pursuit.ready_since>=1+2*c:Latency()
    local missed=observed and (remaining>return_time or ready_missed)
        and (self.bait_waited or now>=self.lure_until)
    if self.lure_until and missed then
        self.retreat=nil
        Ranged.Interrupt(self,"lure_missed_rebait")
        self:CancelSupport()
        self.lure_until=nil;self.feast_lure=nil;self.feast_tail=nil;self.spawn_lure=nil
        self.bait_waited=nil;self.lure_walk_since=nil;self.lure_pursuit=nil;self.bait_hold=nil;self.bait_point=nil
        self.escape_point=nil;self.escape_turn=nil;self.next_escape=nil;self.escape_enough=nil
        self.avoid_boss=nil;self.rebait=true
        if self.moving then self:Halt() end
        D.Emit(self,"lure_missed_rebait","no_cast_return_for_fresh_melee_no_attack")
    end
    local goal,reason,avoid=self:Threat()
    if goal then
        Ranged.Interrupt(self,"actual_attack_threat")
        self.avoid_boss=avoid
        local capture,resolve=self:Ranges()
        if self.lure_until and s.anim=="attack" and R.RetreatReady(self) then
            self.bait_waited=true;self:Hold("已到骨牢识别范围内沿，等待起手",true);return true
        end
        -- 起手只步行躲避；确认骨牢实体命中后才由上面的trapped分支请求瞬移。
        return self:Move(goal,reason,nil,true)
    end
    if R.Risk(self,p)>0 then
        Ranged.Interrupt(self,"actual_ground_hazard")
        local near,score
        for _,z in ipairs(self.zones) do local risk=z.radius-dist(p,z.pos);if risk>0 and (not score or risk>score) then near,score=z,risk end end
        if not near then
            local lane=self.lanes[1];local q=Vector3(p.x-lane.z*4,0,p.z+lane.x*4)
            return self:Move(q,"清目标时横移避开侧方冲撞",nil,true)
        end
        return self:Move(R.Point(near.pos,p,near.radius+2),"清目标时避开侧方技能／残留骨刺",nil,true)
    end
    if not self.lure_until and not self.retreat and Ranged.Tick(self) then return true end
    if self.rebait then
        local reach=2.6
        if dist(p,bp)>reach+.1 then
            return self:Move(R.Point(bp,p,reach-.25),"持手杖回身，只骗新的普攻起手",self.boss,true)
        end
        self:Hold("已近身，持手杖等普攻前摇，不补刀",true)
        c.travel:BeginDodge(c.snapshot);return true
    end
    local interior=self.center or self.home
    local clearance=R.Clearance(p,self)
    if clearance<6 then self.edge_return=true end
    if clearance>=7 then self.edge_return=nil end
    if self.edge_return and interior and p:DistSq(interior)>5^2 and not self.support and not self.lure_until and not self.cycle and not self.phase1 then
        local goal=R.Point(interior,p,math.max(4.5,dist(p,interior)-4))
        return self:Move(goal,"先离开场地边缘，再恢复诱招／输出",nil,true)
    end
    -- 普通摘护符不抢占连续撤退；到识别带后恢复。真正控制临界点仍必须立即恢复。
    local restore_here=not self.lure_until or S.ControlDue(self)
        or R.RetreatReady(self)
    if restore_here and self.cycle and Cycle.RestoreDue and Cycle.RestoreDue(self) then
        self:CancelSupport()
        if S.Restore(self) then return true end
    end
    if self.lure_until or self.retreat and self.retreat.mode=="escape" then return self:Retreat() end
    -- 控制在control_loop进入时生效。前摇末段才摘，留足网络/换装确认时间。
    if s.controlling and S.ControlDue(self) then
        if not self.sanity_round and S.Wearing(self) then S.Prepare(self) end
        if self.sanity_round then
            if not self.sanity_round.restoring then self:CancelSupport();self.sanity_round.restoring=true end
            if S.Restore(self) then return true end
        end
    end
    if self.sanity_round and self.sanity_round.restoring and S.Restore(self) then return true end
    if self.support and self.support.slot then
        local pending=self.support
        if not pending.item:IsValid() or self:Item(pending.item.prefab)~=pending.item then self:CancelSupport()
        elseif c.player.replica.inventory:GetEquippedItem(pending.slot)==pending.item then self:CancelSupport()
        elseif now<pending.deadline then return self:Equip(pending.item,pending.slot,self.mode)
        else self:CancelSupport();self.next_equip=now+2 end
    end
    -- 正在吃的物品等待回执；新的回SAN进食不能抢走实际吞食期间的清虫首发。
    local urgent_food=s.feasting and self.cycle and self.cycle.feeding>0 and Ranged.Item(self)
    if (self.sanity_food or not urgent_food) and S.Feed(self) then return true end
    if Phase1.Tick(self) then return true end
    if Cycle.Tick(self) then return true end
    if s.controlling then
        local target=self:PickChanneler()
        if S.HandWindow(self) and target and self.sanity_round and not self.sanity_round.restoring then
            return self:Attack(target,"精神控制前摇窗口清鬼手，末段摘装备")
        end
        self:Hold("保持自然SAN，等待精神控制动作结束",true);return true
    end
    if self:Shielded() or s.channeling then
        if self:PrepareSanity() then return true end
        local target=self:PickChanneler()
        if target then
            local blocker=self:BodyBlocker(target)
            return self:Attack(blocker or target,blocker and "吞食窗口清理挡路虫子" or "清理鬼手，确认破盾")
        end
        self:Hold("等待鬼手生成／屏障网络确认",true);return true
    end
    self.reserve=nil
    if not (Cycle.KeepMask and Cycle.KeepMask(self)) and not Phase1.KeepMask(self) and self.sanity_round and S.Restore(self) then return true end
    local minion
    if not s.feasting then for _,e in ipairs(self.minions) do
        if not e:HasTag("notarget") and e:GetPosition():DistSq(bp)<3^2 and p:DistSq(e:GetPosition())<4^2 then minion=e;break end
    end end
    return self:Attack(minion or self.boss,minion and "清除即将被吞食的虫子" or "破盾／后摇窗口输出本体")
end
function W:Tick()
    local started=os.clock();local active=self:_Tick()
    self.route_paths=self.route_frame and self.route_frame.paths or 0
    self.route_grid_fallbacks=self.route_frame and self.route_frame.grid_fallbacks or 0
    self.route_frame=nil
    if active then D.Sample(self,os.clock()-started) end
    return active
end
function W:Stop()
    if self.boss then D.Emit(self,"end") end
    self:CancelSupport()
    if self.c.bridge.priority_target==self.focus then self.c.bridge.priority_target=self.old_priority end
    if self.moving then self:Halt() end
    self.boss=nil;self.focus=nil;self.holding=nil;self.moving=nil;self.point=nil;self.state=O.New()
    self.phase1=nil;self.cycle=nil;self.reserve=nil;self.center=nil;self.blink_sent=nil;self.blink_destination=nil;self.channelers={};self.minions={};self.entities={};self.bodies={};self.fences={}
    self.old_priority=nil;self.expanded_snare=nil;self.transition_lured=nil;self.stuck_since=nil
    self.sanity_round=nil;self.sanity_food=nil;self.next_sanity_food=nil;self.blinkstaff=nil;self.feed_started=nil;self.fed=nil;self.feed_uncertain=nil
    self.last_channel_cycle=nil;self.next_scan=nil;self.next_equip=nil;self.next_blink=nil;self.next_path=nil
    self.blocked_targets=nil
    self.edge_return=nil;self.home=nil;self.next_block_log=nil
    self.spawn_lure=nil;self.shock_point=nil;self.shock_run=nil;self.shock_command=nil;self.feast_lure=nil;self.feast_tail=nil;self.spike_guard=nil;self.light_sent=nil;self.next_hand=nil;self.rebait=nil;self.snare_run=nil;self.snare_command=nil;self.snare_motion=nil
    self.retreat=nil;self.next_retreat_plan=nil
    self.staff_action=nil
    self.fight_corners=nil;self.corner_scan=nil;self.corner_dodge=nil
    self.lure_attack=nil;self.lure_until=nil;self.bait_waited=nil;self.lure_walk_since=nil;self.lure_pursuit=nil;self.bait_point=nil;self.escape_point=nil;self.escape_turn=nil;self.next_escape=nil;self.escape_reach=nil;self.escape_enough=nil
end
return W
