-- 桥接已启用的 3014188454 / 3750329397，保留原作者进程和怪物动作表。
-- 走A：StartHitAndRun -> IsAttackPre -> DoDodge；纯走位复用 IsAttackPre/DoDodge。
local Debug=require("shadowself/control/queendebug")
local Bridge=Class(function(self,player) self.player=player end)
function Bridge:Available()
    local n=require("shadowself/native").Get();local h=n.HitAndRun
    return h and h.StartHitAndRun and h.StopHitAndRun and h.IsAttackPre and h.DoDodge and n.MOD_util and n.POS_util and n.ENT_util
end
function Bridge:Start(plan,matches)
    if not self:Available() then return false,"内置战斗模块尚未初始化。" end
    if (self.tuning or require("shadowself/native").Get().TUNING).Cheatthread then return false,"3014 已有走A进程在运行。请先停止它，再让我接管，避免争抢操作。" end
    local n=require("shadowself/native").Get();local h=n.HitAndRun;self.native=n;self.tuning=n.TUNING
    self.h=h;self.saved={};self.options={};self.wrappers={}
    local function option(key,field,value)
        self.saved[field]={value=h[field]};h[field]=value
        local options=self.native and self.native.m_options
        if options then self.options[key]={present=options[key]~=nil,value=options[key]};options[key]=value end
    end
    option("hitandrun_dodgetest","dodgetest",true)
    option("hitandrun_walkway","walkway",true)
    option("hitandrun_walktime","walktime",1)
    option("hitandrun_targetmode","targetmode",false)
    option("hitandrun_priority_undermouse","priority_undermouse",false)
    self.plan=plan;self.clear_since=nil;self.next_finish_scan=nil;self.finished=false
    local function allowed(e)
        if not e or not e:IsValid() or e==self.player or e:HasTag("player") or e:HasTag("playerghost") then return false end
        if plan.arena and plan.arena_wave and plan.arena_wave()==11 and (e.prefab=="chest_mimic" or e.prefab=="chest_mimic_revealed") then return false end
        if plan.arena and require("shadowself/control/arena_snails").Burning(e) then return false end
        local n=e.prefab or ""
        if n:find("sandspike_",1,true)==1 or n=="sandblock" then return false end
        local crab=self.coordinator and self.coordinator.crabking
        if crab and crab:Active() and not crab:Allowed(e) then return false end
        local queen=self.coordinator and self.coordinator.beequeen
        if queen and queen.GuardAttackBlocked and queen:GuardAttackBlocked(e) then Debug.Block(self.coordinator,"select",e);return false end
        if e.prefab=="beeguard" and require("shadowself/control/status").Sleeping(e) then return false end
        if e.prefab=="icehound" or e.prefab=="firehound" then
            local a=e.AnimState
            if (e:HasTag("sleeping") or a and (a:IsCurrentAnimation("sleep_pre") or a:IsCurrentAnimation("sleep_loop") or a:IsCurrentAnimation("sleep_pst")))
             and not (plan.arena_walrus and plan.arena_walrus:Escort(e)) then return false end
        end
        if plan.arena_spider_control and not plan.arena_spider_control(e) then return false end
        local combat=self.player.replica.combat
        local arena_bird=require("shadowself/control/targetpolicy").ArenaBird(self,e)
        if combat and combat:IsAlly(e) and not arena_bird then return false end
        if e:HasTag("INLIMBO") or e:HasTag("isdead") or e:HasTag("dead") then return false end
        local health=e.replica and e.replica.health
        if health and health.IsDead and health:IsDead() then return false end
        if arena_bird then return true end
        if plan.arena and plan.arena_contains and plan.arena_contains(e) and e.replica and e.replica.combat then return true end
        if self.resume_target==e or self.priority_target==e then return true end
        if self.coordinator and self.coordinator.encounters and self.coordinator.encounters.allowed[e] then return true end
        if self.coordinator and self.coordinator.beequeen and self.coordinator.beequeen.allow==e then return true end
        if plan.target and plan.target~="" and matches(e,plan.target) then return true end
        local ec=e.replica and e.replica.combat
        local target=ec and ec.GetTarget and ec:GetTarget()
        local follower=target and target.replica and target.replica.follower
        local helping=follower and follower.GetLeader and follower:GetLeader()==self.player
        local ef=e.replica and e.replica.follower
        local leader=ef and ef.GetLeader and ef:GetLeader()
        local sleeping=e:HasTag("sleeping") and not e:HasTag("epic") and ec~=nil and not leader and not e:HasTag("companion") and not e:HasTag("structure")
        return target==self.player or helping or sleeping or false
    end
    self.allowed=allowed
    local original=h.GetAttackTargets
    self.wrappers.GetAttackTargets={old=original}
    local wrapper=function(object,range)
        original(object,plan.arena and math.max(range or 0,30) or range)
        for e in pairs(object.selected_ents or {}) do if not allowed(e) then object.selected_ents[e]=nil end end
        -- 原生扫描内部也排除IsAlly，补回经过当前关卡名单确认的鸟。
        if plan.arena_remaining then
            local policy=require("shadowself/control/targetpolicy")
            for _,e in ipairs(plan.arena_remaining()) do
                if policy.ArenaBird(self,e) and allowed(e) then object.selected_ents[e]=true end
            end
        end
    end
    self.wrappers.GetAttackTargets.current=wrapper;h.GetAttackTargets=wrapper
    local closest=h.GetClosestTarget
    if closest then
        local pick=function(object,...)
            local bird=require("shadowself/control/targetpolicy").Bird(self)
            if bird then return bird end
            local e=self.priority_target
            if e and e.prefab=="slurper" and plan.arena then
                local c=self.coordinator or {player=self.player,plan=plan,bridge=self}
                e=require("shadowself/control/arena_slurper").Nearest(c,object.selected_ents,e and function(v) return allowed(v) end,e) or e
                self.priority_target=e;self.resume_target=e
            end
            if e and e:IsValid() and allowed(e) then
                return require("shadowself/control/targetpolicy").Rook(e) and require("shadowself/control/targetpolicy").Other(self,e) or e
            end
            e=plan.kind=="fight" and require("shadowself/control/targetpolicy").Nearest(self) or closest(object,...)
            return require("shadowself/control/targetpolicy").Rook(e) and (require("shadowself/control/targetpolicy").Other(self,e) or e) or e
        end
        self.wrappers.GetClosestTarget={old=closest,current=pick};h.GetClosestTarget=pick
    end
    if plan.coordinated then self:Coordinate(plan) end
    if plan.kind=="fight" then
        h:StartHitAndRun()
        self.thread=(self.tuning or require("shadowself/native").Get().TUNING).Cheatthread
        if not self.thread then self:Stop();return false,"3014 没有启动走A进程，操作已经交回。" end
    else
        -- DoDodge 原实现会在结束时补刀；纯走位会临时禁用这两处攻击入口。
        for _,name in ipairs({"CloseAndAttack","ShouldAtkWhenDodging"}) do
            local fn=function() return false end
            local entry=self.wrappers[name]
            self.wrappers[name]={old=entry and entry.old or h[name],current=fn};h[name]=fn
        end
        h.PC=self.player.components.playercontroller;h.combat=self.player.replica.combat
        h.inv=self.player.replica.inventory;h.rangeoffset=.5;h.selected_ents={}
        self.dodge_thread=StartThread(function()
            while self.dodge_thread do
                h:GetAttackTargets(18)
                local target=h:GetClosestTarget()
                if target and allowed(target) then
                    h.ent=target;h:PreTheLoop()
                    local data=h:IsAttackPre(target,1)
                    if data then h:DoDodge(data) end
                end
                Sleep(FRAMES)
            end
        end,"shadowself_dodge")
    end
    if plan.kind=="fight" and n~=_G then self:Supervise() end
    return true
end
function Bridge:Running()
    return self.supervisor~=nil or self:OwnsThread()
end
-- 追击时物理停止走A协程；到达出手距离后重启，只有一个阶段能下发操作。
function Bridge:PauseAttack()
    -- Never remove the coroutine that is still executing this call stack.
    if self.thread and self.thread.co and self.thread.co==coroutine.running() then
        self.pause_requested=true;return
    end
    local stopping=self:OwnsThread()
    local c=self.coordinator
    local resume_point=(stopping or self.pause_requested) and c and c.blocked
        and (self.pause_requested or c.last_action_kind=="move") and c.last_point
    self.pause_requested=nil
    if self:OwnsThread() then
        Debug.Event(self.coordinator,"native_pause",{target=Debug.Entity(self.h.ent)})
        local thread=self.thread;if self.native==_G or self:PlayerReady() then self.h:StopHitAndRun() end
        -- 原停止入口在聊天/菜单时会跳过；仍须真正暂停自己的攻击协程。
        if self.tuning.Cheatthread==thread then
            KillThreadsWithID(thread.id);thread:SetList(nil);self.tuning.Cheatthread=nil
            if self.h.movementflag then self.player:EnableMovementPrediction(true) end
        end
    end
    self.thread=nil
    if self.h then self.h.shadowself_dodging=nil end
    if resume_point then
        -- 无论监督协程还是攻击协程暂停，StopWalking后都重发本轮机制移动。
        self.native.POS_util:GoToPoint(resume_point.x,resume_point.z)
        self.coordinator.next_move=GetTime()+.1
    end
end
function Bridge:ResumeAttack()
    if self:OwnsThread() then return end
    Debug.Event(self.coordinator,"native_resume",{target=Debug.Entity(self.h.ent)})
    self.h:StartHitAndRun();self.thread=self.tuning.Cheatthread
end
function Bridge:RetreatFromTraps(c)
 local whip=c.plan and c.plan.arena_whip_state
 if whip and whip.active and c.plan.arena_wave and c.plan.arena_wave()==2 and not whip:CanAttack(c.player) then
  -- 还没拿到猫鞭时保留原有“安全捡鞭再退”的顺序，避免走近掉落鞭时反复折返。
  if c.plan.arena_ground and not require("shadowself/control/arena_tools").Owned(c,"whip") then
   for _,item in ipairs(c.plan.arena_ground()) do
    if item.prefab=="whip" and require("shadowself/control/arena_tools").Usable(item)
     and whip:CanPickup(c.player,item) then return false end
   end
  end
  whip:Evade(c);return true
 end
 return false
end
function Bridge:Supervise()
    local pc=self.player.components.playercontroller
    self.action_pc=pc
    self.action_old=pc.DoAction
    self.action_hook=function(object,act,...)
        if act and not act._shadowself_native and not object._shadowself_native_rpc and (act.action==ACTIONS.WALKTO or act.action==ACTIONS.JUMPIN or act.action==ACTIONS.JUMPOFF) then
            self.manual_until=GetTime()+1.5
            self:PauseAttack()
        end
        return self.action_old(object,act,...)
    end
    pc.DoAction=self.action_hook
    self.supervisor=StartThread(function()
        while self.supervisor do
            if not self:PlayerReady() then self:PauseAttack();break end
            if self.pause_requested then self:PauseAttack() end
            local c=self.coordinator;local h=self.h
            h.atktag_tick=self.player:HasTag("attack") and (h.atktag_tick or 0)+1 or 0
            local manual=self:ManualAction()
            if manual then
                self:PauseAttack()
            else
                h.PC=self.player.components.playercontroller;h.combat=self.player.replica.combat
                h.inv=self.player.replica.inventory;h.rangeoffset=.5
                local armor_busy=require("shadowself/control/arena_emergency_armor").Tick(c)
                if not armor_busy then
                h:GetAttackTargets(24)
                local target=h:GetClosestTarget()
                if target and self.allowed(target) then
                    if not self:OwnsThread() then h.ent=target;self.wrappers.PreTheLoop.old(h) end
                    c:Scan();c:HitRecovery()
                    c.mechanisms=c.mechanisms or require("shadowself/control/mechanisms")(c)
                    local opening=c.plan and c.plan.arena_clockwork
                    local hunt=c.plan and c.plan.arena_walrus
                    local doc=require("shadowself/control/arena_doc_control")
                    local docboss=require("shadowself/control/arena_doc_boss")
                    doc.Protect(c)
                    local exclusive,exclusive_target=docboss.Tick(c,docboss.Target(c,target) or target)
                    if exclusive then c.doc_exclusive=true
                    elseif c.doc_exclusive then
                        c.doc_exclusive=nil;c.travel:EndDodge(c.snapshot);h.shadowself_dodging=nil;c.blocked=false
                    end
                    local continuous=doc.Continuous(c,target)
                    if not exclusive and continuous then doc.Commit(c,target) end
                    local tank=not exclusive and (continuous or require("shadowself/control/boneguard").Tank(c,target))
                    if tank then require("shadowself/control/boneguard").Attack(c,target) end
                    local bishop_evading=not tank and opening and opening:Live() and opening:Block(c)
                    local committed=c.plan and c.plan.arena_bird_committed and c.plan.arena_bird_committed(target)
                     or c.plan and c.plan.arena_strategy and c.plan.arena_strategy.target==target
                     or opening and opening:Live() and not bishop_evading
                     or hunt and hunt.Committed and hunt:Committed(target)
                     or require("shadowself/control/sharkroute").Committed(c,target) or tank
                    local support=exclusive or self:RetreatFromTraps(c) -- 技能传送/缩壳拥有当前动作。
                    if not support then support=not bishop_evading and not committed and require("shadowself/control/arena_disarm").Tick(c) end
                    if bishop_evading then c.mechanisms:Scan() end -- 只更新瞄准标记，不让补给动作抢走躲避。
                    if not bishop_evading and not support and not committed then support=c.mechanisms:Tick() end
                    local mode,picked
                    if tank then mode,picked="attack",target;c.blocked=false end
                    if not doc.Late(c) and not support and not mode and (target.prefab=="beequeen" or target.prefab=="beeguard" or c.beequeen and c.beequeen.queen) then
                        c:NativePulse()
                        if c.queen_active then mode=c.blocked and "support" or "attack";picked=c.h.ent end
                    end
                    if not support and not mode then
                        c.crabking=c.crabking or require("shadowself/control/crabking")(c)
                        mode,picked=c.crabking:Tick(target)
                    end
                    if not bishop_evading and not committed and not support and not mode and c.bosses then mode,picked=c.bosses:Tick(target) end
                    if not doc.Late(c) and not bishop_evading and not committed and not support and not mode and c.encounters then mode,picked=c.encounters:Tick(target) end
                    local late_support=not doc.Late(c) and c.plan and c.plan.arena_stage12
                    if not bishop_evading and (not committed or late_support) and not support and mode~="move" and mode~="support" and c.healing then support=c.healing:Tick(c) end
                    if not bishop_evading and (not committed or late_support) and not support and mode~="move" and mode~="support" and c.supplies
                     and not (c.healing and (c.healing.pending or GetTime()<(c.healing.draining_until or 0))) then support=c.supplies:Tick() end
                    if picked and picked~=target then target=picked;h.ent=target;self.wrappers.PreTheLoop.old(h) end
                    if support or mode=="move" or mode=="support" then
                        self:PauseAttack()
                    elseif self:OwnsThread() and h.shadowself_dodging then
                        c.travel:UpdateDodge(c.snapshot)
                    else
                        local d=math.sqrt(self.player:GetPosition():DistSq(target:GetPosition()))
                        local reach=c.gear:AttackRange()+target:GetPhysicsRadius(0)
                        local rook=c.bosses and c.bosses.rooks[target]
                        local attack_approach=committed or require("shadowself/control/arena_doc_early").AttackApproach(c,target) or require("shadowself/control/arena_attackwindows").Committed(c,target) or c.bosses and c.bosses:KnightCommitted(target) or rook and rook.ready
                         and require("shadowself/control/targetpolicy").ClockworkRook(self)==target
                        local bird=c.plan and c.plan.arena_bird_committed and c.plan.arena_bird_committed(target)
                        if bird then reach=require("shadowself/control/arena_bird_range").Reach(c,target) end
                        local chasing=bird and require("shadowself/control/arena_bird_range").Chase(c,target) or not bird and not attack_approach and (self.chasing and d>reach+.25 or d>reach+2)
                        if chasing then
                            self:PauseAttack();self.chasing=true;c.travel.chasing=true;h.ent=target;self.wrappers.PreTheLoop.old(h)
                            c.travel.restore_dodge=nil;c.travel.role="move"
                            c.special_active=false;c.queen_active=false;c.blocked=false
                            local data=h:IsAttackPre(target,1)
                            if data then
                                -- 原线程执行躲避，监督协程继续检查侧方。
                                self.chasing=nil;c.travel.chasing=nil;self:ResumeAttack()
                            else
                                local special=not doc.Late(c) and (target.prefab=="beequeen" or target.prefab=="beeguard")
                                if special then c:NativePulse() end
                                if not c.blocked then
                                    c.travel:Tick(target:GetPosition(),reach,false,c.snapshot)
                                    local q=require("shadowself/control/navigation").Select(c,target:GetPosition(),target)
                                    self.native.POS_util:GoToPoint(q.x,q.z)
                                end
                            end
                        else
                            if self.chasing then
                                self.chasing=nil;c.travel.chasing=nil;c.travel:EndDodge(c.snapshot);c.travel.role="attack";c.gear.next_request=GetTime()
                            end
                            if not self:OwnsThread() then
                                c.gear:Swap("attack",c.snapshot)
                                local weapon=c.gear:Weapon()
                                if not weapon or self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==weapon then self:ResumeAttack() end
                            end
                        end
                    end
                else
                    self:PauseAttack();self.chasing=nil;c.travel.chasing=nil
                    c:Scan();c.mechanisms=c.mechanisms or require("shadowself/control/mechanisms")(c)
                    local danger=self:RetreatFromTraps(c)
                    if not danger then danger=c.mechanisms:Tick() end
                    if not danger and c.healing then c.healing:Tick(c) end
                end
                end -- urgent replacement owns this supervisor frame
            end
            Debug.Sample(self.coordinator and self.coordinator.beequeen)
            Sleep(FRAMES)
        end
    end,"shadowself_combat_supervisor")
end
function Bridge:PlayerReady()
    local p=self.player
    return p and p:IsValid() and (not ThePlayer or ThePlayer==p) and p.components and p.components.playercontroller
        and p.replica and p.replica.inventory and p.replica.combat
end
function Bridge:ManualAction()
    if not self:PlayerReady() then return true end
    local p=self.player;local pc=p.components.playercontroller
    local n=self.native
    if n.GAME_util and not n.GAME_util:InGame() or IsSimPaused and IsSimPaused() then return true end
    if pc.IsHopping and pc:IsHopping() or p:HasTag("boathopping") then self.manual_until=GetTime()+.4;return true end
    if n.KEY_util:MoveKeyDown() then self.manual_until=GetTime()+.2;return true end
    return GetTime()<(self.manual_until or 0)
end
function Bridge:Coordinate(plan)
    local h=self.h
    self.coordinator=require("shadowself/control/coordinator")(self,plan)
    self.coordinator.secondary=require("shadowself/control/secondary")(self.coordinator)
    self.after_dodge_old=h.shadowself_after_dodge
    self.after_dodge=function(captured)
        local c=self.coordinator
        require("shadowself/control/arena_moose").AfterDodge(c,captured)
        local approach=require("shadowself/control/arena_doc_early").AfterDodge(c,captured)
        if approach then return approach end
        if c.plan and c.plan.arena_clockwork then
            local bishop=c.plan.arena_clockwork:AfterDodge(c)
            if bishop then return bishop end
        end
        return c.secondary:AfterDodge(captured)
    end
    h.shadowself_after_dodge=self.after_dodge
    self.hold_ground_old=h.shadowself_hold_ground
    self.hold_ground=function()
        local r=plan.arena_clockwork
        local hunt=plan.arena_walrus
        local bosses=self.coordinator and self.coordinator.bosses
        local crab=self.coordinator and self.coordinator.crabking
        return plan.arena_bird_committed and plan.arena_bird_committed(h.ent)
         or require("shadowself/control/arena_doc_control").Continuous(self.coordinator,h.ent)
         or require("shadowself/control/boneguard").Tank(self.coordinator,h.ent)
         or require("shadowself/control/arena_attackwindows").Committed(self.coordinator,h.ent)
         or bosses and bosses:KnightCommitted(h.ent)
         or require("shadowself/control/arena_moose").Hold(self.coordinator,h.ent)
         or require("shadowself/control/arena_rook_window").Allow(self.coordinator,h.ent)
         or crab and crab:Active() and crab:Allowed(h.ent) and (crab.stage=="king" or crab.stage=="break")
         or require("shadowself/control/sharkroute").Committed(self.coordinator,h.ent)
         or hunt and hunt.Committed and hunt:Committed(h.ent)
         or r and r:Live() and not r:Block(self.coordinator) and h.ent==r.target
    end
    h.shadowself_hold_ground=self.hold_ground
    -- Subscribe to the original event instead of replacing the original dodge.
    if self.player.ListenForEvent then
        self.manual_listener=function(_,data)
            local act=data and (data.action or data)
            Debug.Performed(self.coordinator,data)
            require("shadowself/control/queenflute").OnAction(self.coordinator,data)
            require("shadowself/control/guardcontrol").OnAction(self.coordinator,data)
            local wind=self.coordinator.arena_wind
            if wind and act and act.action==ACTIONS.CASTSPELL then wind:Performed(act) end
            if act and (act.action==ACTIONS.JUMPIN or act.action==ACTIONS.JUMPOFF or act.action==ACTIONS.HOP) then self.manual_until=GetTime()+2 end
        end
        self.player:ListenForEvent("performaction",self.manual_listener)
        self.debug_hurt_listener=function(_,data)
            if data then
                if self.coordinator.crabking then self.coordinator.crabking:Interrupt() end
                Debug.Hit(self.coordinator,data)
                require("shadowself/control/queenflute").Interrupt(self.coordinator,"attacked:"..Debug.Entity(data.attacker))
            end
        end
        self.player:ListenForEvent("attacked",self.debug_hurt_listener)
        self.equip_listener=function(_,data)
            local c=self.coordinator
            if not c or not data then return end
            if data.type=="walk_hands" then
                if not require("shadowself/control/boneguard").Attack(c,c.h.ent) then c.travel:BeginDodge(c.snapshot) end
            elseif data.type=="fight" and self.chasing then return
            elseif data.type=="fight" and c.travel.dodging then
                if c.beequeen and c.beequeen.travelling then return end
                if c.secondary.pending then c.travel.finish_deferred=true
                else c.travel:EndDodge(c.snapshot) end
            end
        end
        self.player:ListenForEvent("EquipItem",self.equip_listener)
    end
    local function wrap(name,fn)
        local old=h[name];if not old then return end
        local current=function(object,...) return fn(old,object,...) end
        self.wrappers[name]={old=old,current=current};h[name]=current
    end
    wrap("PreTheLoop",function(old,object,...)
        old(object,...);self.coordinator:NativePulse()
        if not self.coordinator.special_active then self.coordinator.secondary:Pulse() end
    end)
    -- Ordinary fights pass straight through. Only an active queen support/move
    -- or Maxwell cast can hold attacks; no generic gear/safety gate remains.
    for _,name in ipairs({"OnKeyFrame","OnNormalFrame","CloseAndAttack","ShouldAtkWhenDodging"}) do
        wrap(name,function(old,object,...)
            local c=self.coordinator
            if self.pause_requested then return false end
            if require("shadowself/control/arena_windcycle").Blocked(c) then return false end
            if name=="CloseAndAttack" and c.plan and c.plan.arena then
                local hand=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                if hand and hand.prefab=="torch" then return false end
            end
            if c.healing and c.healing:BlockAttack(name) then return false end
            if c.plan and c.plan.arena_clockwork and c.plan.arena_clockwork:Block(c) then return false end
            if c.plan and c.plan.arena_whip_state and not c.plan.arena_whip_state:CanAttack(c.player) then return false end
            local explicit=...;local victim=(name=="CloseAndAttack" or name=="ShouldAtkWhenDodging") and type(explicit)=="table" and explicit.prefab and explicit or object.ent
            if not require("shadowself/control/arena_doc_control").Allowed(c,victim) then return false end
            if c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()==4 and victim and victim.prefab=="bearger" then
                local weapon=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                if not weapon or not require("shadowself/control/arena_inventory").Weapon(weapon,c.player)
                    or not require("shadowself/control/arena_tools").Usable(weapon) then return false end
            end
            if c.plan and c.plan.arena_bone_busy and c.plan.arena_bone_busy() then return false end
            if c.plan and c.plan.arena_spider_control and not c.plan.arena_spider_control(victim) then return false end
            if c.plan and c.plan.arena_stage11 and not c.plan.arena_stage11:Allowed(victim) then return false end
            if not require("shadowself/control/arena_doc_control").Late(c) and c.plan and c.plan.arena_stage12 and not c.plan.arena_stage12:Allowed(victim) then return false end
            if c.plan and c.plan.arena_bird_committed and c.plan.arena_bird_committed(victim) then
                if require("shadowself/control/arena_bird_range").Chase(c,victim) then return false end
            end
            if c.plan and c.plan.arena_snail_scene and not c.arena_snailpack then return false end
            if c.arena_snailpack and not c.arena_snailpack:CanAttack(victim) then return false end
            local bird=require("shadowself/control/targetpolicy").Bird(self)
            if bird and victim~=bird then return false end
            if c.plan and c.plan.arena_walrus and not c.plan.arena_walrus:CanAttack(victim) then return false end
            if not require("shadowself/control/arena_doc_control").Continuous(c,victim) and require("shadowself/control/targetpolicy").Rook(victim) and require("shadowself/control/targetpolicy").Other(self,victim) then return false end
            if c.crabking and c.crabking:Active() and not c.crabking:Allowed(victim) then return false end
            if c.beequeen and c.beequeen.GuardAttackBlocked and c.beequeen:GuardAttackBlocked(victim) then Debug.Block(c,name,victim);return false end
            if victim and c.bosses and c.bosses.AttackBlocked and c.bosses:AttackBlocked(victim) then return false end
            if victim and victim.prefab=="beeguard" and c.beequeen and c.beequeen.queen
                and not (c.beequeen.phase==1 and c.beequeen.recycle_guard==victim) and (require("shadowself/control/status").Frozen(victim) or require("shadowself/control/status").Sleeping(victim)) then return false end
            if object.ent and not self.allowed(object.ent) then return false end
            if c.bosses and c.bosses.AttackBlocked and c.bosses:AttackBlocked(object.ent) then return false end
            if self.chasing then return false end
            if c.blocked and (c.special_active or not self:OwnsThread()) then return false end
            if not c.secondary:BeforeAttack(name=="ShouldAtkWhenDodging") then return false end
            if name=="CloseAndAttack" then
                if c.travel.finish_deferred then c.travel:EndDodge(c.snapshot) end
                c.travel:UpdateDodge(c.snapshot)
            end
            local argv={...}
            if name=="ShouldAtkWhenDodging" and not c.queen_active and not (c.crabking and c.crabking:Active()) then
                local nearest=c.secondary:Preferred() or require("shadowself/control/targetpolicy").Nearest(self)
                if nearest and nearest~=victim then return false end
            end
            if name=="ShouldAtkWhenDodging" and argv[2] and argv[2].noattack then return false end
            if name=="ShouldAtkWhenDodging" and c.queen_dodging then return false end
            if name=="ShouldAtkWhenDodging" and c.charge_target and c.charge_target==object.ent then return false end
            if name=="CloseAndAttack" then Debug.Throttle(c,"attack_dispatch",.25,"attack_dispatch",{target=Debug.Entity(victim)}) end
            -- 与玩家正常强制攻击同一路径；无预测模式也不能被客户端友方判断静默拒绝。
            if name=="CloseAndAttack" and require("shadowself/control/targetpolicy").ArenaBird(self,victim) then
                return old(object,victim,true)
            end
            return old(object,...)
        end)
    end
    -- Never replace POS_util.GoToPoint/WalkTo/DoDodge: native movement is intact.
    wrap("IsAttackPre",function(old,object,target,...)
        if require("shadowself/control/arena_doc_boss").Owns(self.coordinator) or require("shadowself/control/arena_doc_control").Continuous(self.coordinator,target) or require("shadowself/control/boneguard").Tank(self.coordinator,target) then return false end
        self.coordinator.travel:UpdateDodge(self.coordinator.snapshot)
        local data=require("shadowself/control/boneguard").Early(self.coordinator,target,old(object,target,...))
        local c=self.coordinator;local queen=c.beequeen and c.beequeen.queen
        c.queen_dodging=nil
        if queen and queen:IsValid() and queen~=target and self.player:GetPosition():DistSq(queen:GetPosition())<10^2 then
            local qdata=require("shadowself/control/queenattack")(c,queen,false)
            if qdata then c.queen_dodging=true;return qdata end
        end
        if target and target.prefab=="beequeen" and not require("shadowself/control/arena_doc_control").Late(c) then
            return require("shadowself/control/queenattack")(self.coordinator,target,data)
        end
        data=require("shadowself/control/charge")(self.coordinator,target,data)
        if self.coordinator.mechanisms then data=self.coordinator.mechanisms:Dodge(target,data) end
        if self.coordinator.encounters then data=self.coordinator.encounters:Dodge(target,data) end
        if self.coordinator.bosses then data=self.coordinator.bosses:Dodge(target,data) end
        if c.plan and c.plan.arena_bird_committed and c.plan.arena_bird_committed(target) then return nil end
        local hunt=c.plan and c.plan.arena_walrus
        if hunt and hunt.Committed and hunt:Committed(target) then return nil end
        if c.plan and c.plan.arena_clockwork then data=c.plan.arena_clockwork:Dodge(c,target,data) end
        local args={...}
        return self.coordinator.secondary:Wrap(target,data,args[2])
    end)
end
-- 仇恨/指定目标连续消失一秒才判定结束，避免换目标和死亡同步间隙误退。
function Bridge:Finished()
    local now=GetTime()
    if now<(self.next_finish_scan or 0) then return self.finished or false end
    self.next_finish_scan=now+.2
    local p=self.player:GetPosition();local any=false
    for _,e in ipairs(TheSim:FindEntities(p.x,p.y,p.z,24,nil,{"INLIMBO","FX","DECOR","isdead"})) do
        if self.allowed(e) then any=true;break end
    end
    if any then self.clear_since=nil;self.finished=false
    else
        self.clear_since=self.clear_since or now
        self.finished=now-self.clear_since>=1
    end
    return self.finished
end
function Bridge:OwnsThread() return self.thread~=nil and (self.tuning or require("shadowself/native").Get().TUNING).Cheatthread==self.thread end
function Bridge:Stop()
    if self.h and self.h.shadowself_hold_ground==self.hold_ground then self.h.shadowself_hold_ground=self.hold_ground_old end
    if self.h and self.h.shadowself_after_dodge==self.after_dodge then self.h.shadowself_after_dodge=self.after_dodge_old end
    Debug.End(self.coordinator,"takeover_stop")
    local pc=self.action_pc or self.player.components and self.player.components.playercontroller
    if pc and self.action_hook and pc.DoAction==self.action_hook then pc.DoAction=self.action_old end
    self.action_hook=nil;self.action_old=nil
    if self.supervisor then KillThreadsWithID(self.supervisor.id);self.supervisor:SetList(nil);self.supervisor=nil end
    if self.manual_listener and self.player.RemoveEventCallback then self.player:RemoveEventCallback("performaction",self.manual_listener) end
    self.manual_listener=nil
    if self.debug_hurt_listener and self.player.RemoveEventCallback then self.player:RemoveEventCallback("attacked",self.debug_hurt_listener) end
    self.debug_hurt_listener=nil
    if self.equip_listener and self.player.RemoveEventCallback then self.player:RemoveEventCallback("EquipItem",self.equip_listener) end
    self.equip_listener=nil
    if self.recovery_task then self.recovery_task:Cancel();self.recovery_task=nil end
    local h=self.h
    if not h then return end
    if self.thread and (self.tuning or require("shadowself/native").Get().TUNING).Cheatthread==self.thread then
        if self.native==_G or self:PlayerReady() then h:StopHitAndRun() end
        -- 离开游戏时 InGame() 已为false，原模组停止入口会跳过；只回收自己拥有的线程。
        if (self.tuning or require("shadowself/native").Get().TUNING).Cheatthread==self.thread then
            KillThreadsWithID(self.thread.id);self.thread:SetList(nil);(self.tuning or require("shadowself/native").Get().TUNING).Cheatthread=nil
            if h.movementflag and self.player:IsValid() then self.player:EnableMovementPrediction(true) end
        end
    end
    if self.dodge_thread then KillThreadsWithID(self.dodge_thread.id);self.dodge_thread:SetList(nil);self.dodge_thread=nil end
    if self.position_hook and self.native.POS_util.GoToPoint==self.position_hook.current then self.native.POS_util.GoToPoint=self.position_hook.old end
    self.position_hook=nil
    for name,entry in pairs(self.wrappers or {}) do
        if h[name]==entry.current then h[name]=entry.old end
    end
    for field,entry in pairs(self.saved or {}) do h[field]=entry.value end
    local options=self.native and self.native.m_options
    if options then
        for key,entry in pairs(self.options or {}) do
            if entry.present then options[key]=entry.value else options[key]=nil end
        end
    end
    if self.coordinator then self.coordinator:Stop();self.coordinator=nil end
    h.ent=nil;self.thread=nil;self.h=nil
end
return Bridge
