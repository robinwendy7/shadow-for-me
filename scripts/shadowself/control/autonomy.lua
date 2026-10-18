-- 从旧 AI Player 合并的需求决策，隔离注册表、存档与调度器。
local Auto=Class(function(self,owner,report,plan)
    for _,name in ipairs({"config","world_model","humanizer","perception","action_library","combat_equipment","character_profiles","decision_brain","autopilot_main"}) do require("shadowself/legacy/"..name) end
    local registry=require("shadowself/legacy/registry")
    local config=registry.Config(function(key)
        local values={humanization_level=1,mistake_frequency=0,idle_activate=0,enable_emotes=false,auto_combat=false}
        return values[key]
    end)
    self.plan=plan
    self.controller=registry.Controller(owner,config)
    self.bridge=require("shadowself/control/combat")(owner)
    self.travel=registry.CombatEquipment({player=owner,owner=self.controller,actions=self.controller.actions,
        roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end}})
    self.controller.Report=function(c,message) c.notice=message;if not (plan and plan.guard_only and message:find("托管开启",1,true)) then report(message) end end
    local brain=self.controller.brain;local evaluate=brain.Evaluate
    brain.Evaluate=function(b,s)
        local plan=evaluate(b,s)
        if plan and plan.name~=self.last_decision and GetTime()>=(self.next_report or 0) then
            self.last_decision=plan.name;self.next_report=GetTime()+8
            report("我看了周围和你的状态。先"..(plan.label or plan.name).."。")
        end
        return plan
    end
end)
function Auto:Tick()
    local c=self.controller
    if c.removed then return "failed","接管已停止。" end
    if not c.model.ready then return "running" end
    if not self.started then
        if not c:Start() then return "failed","自主托管未能启动。" end
        self.started=true
        if self.plan and self.plan.command then
            c.humanizer.Delay=function() return 0 end
            c:SafeCommand(self.plan.command)
        end
    end
    local runnable,why,terminal=c:CanRun()
    if not runnable then
        if self.bridge:Running() then self.bridge:Stop() end
        if terminal then c:Stop(why);return "failed",why end
        return "running"
    end
    local s=c.perception:Scan(false);local threats=c.perception:Threats();s.threats=threats
    local defend=false
    for _,e in ipairs(threats) do
        local combat=e.replica and e.replica.combat
        local target=combat and combat.GetTarget and combat:GetTarget()
        if target==c.player or (not target and not e:HasTag("epic") and c.player:GetDistanceSqToInst(e)<25) then defend=true;break end
    end
    if self.bridge:Running() then
        if defend then self.clear_since=nil
        else self.clear_since=self.clear_since or GetTime() end
        if self.clear_since and GetTime()-self.clear_since>.8 then
            self.bridge:Stop();self.clear_since=nil;c.next_action=GetTime();c.perception.next_scan=0
        else return "running" end
    elseif self.bridge.thread then
        self.bridge:Stop();return "failed","原生战斗线程已结束，接管暂停。"
    end
    local health=s.health or 1
    local can_control=false
    if c.player.prefab=="waxwell" then
        for _,item in ipairs(s.items) do
            if item.prefab=="waxwelljournal" and item.components and item.components.spellbook then can_control=true;break end
        end
    end
    if defend and (self.travel:Weapon() or can_control) and self.bridge:Available() then
        c.actions:Stop();c.pending=nil
        local ok,message=self.bridge:Start({kind="fight",target="",defensive=true,coordinated=true,context=c},function() return true end)
        if ok then c:ReportOnce("nativefight","遇到威胁，交给3014战斗；群怪按聚怪、骗招、转火处理。",10);return "running" end
        return "failed",message
    end
    if self.plan and self.plan.guard_only and #threats==0 then
        if c.pending then c.actions:Stop();c.pending=nil end
        return "idle"
    end
    if c.pending and c.pending.kind=="move" and not c.pending.sent then
        -- 移动前借用最快可用手持物；黑暗时保留唯一照明。
        self.travel:Swap("move",s)
        if self.travel.pending then return "running" end
    end
    c:SafeTick()
    if not c.active then return "failed",c.notice or "自主托管已停止。" end
    return "running"
end
function Auto:OwnsCombat() return self.bridge:Running() end
function Auto:Cancel() self.bridge:Stop();self.travel:Reset();self.controller:Remove() end
return Auto
