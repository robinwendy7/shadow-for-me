local Actions=require("shadowself/control/actions")
local Extended=Class(function(self,owner,plan,report)
    self.owner=owner;self.plan=plan;self.report=report;self.running=true
    if plan.kind=="adventure" then
        self.auto=require("shadowself/control/adventure")(owner,plan.step,report)
    elseif plan.kind=="autonomy" then
        self.auto=require("shadowself/control/autonomy")(owner,report,plan)
    else
        local Queue=require("shadowself/zom/ActionQueue")
        self.queue=Queue.new(_G,function(_,message) report(message) end,
            function(p,point) return Actions.Move(p,point) end,
            function(p) return Actions.Stop(p) end,
            function(p,point)
                for _,e in ipairs(TheSim:FindEntities(point.x,point.y or 0,point.z,5,{"hostile"},{"INLIMBO","isdead","companion"})) do
                    if not e:HasTag("player") then return true end
                end
                return false
            end,function(_,message) report(message) end)
        self.queue:Set(plan.steps,owner,owner)
    end
end)
function Extended:Tick()
    if self.auto then return self.auto:Tick() end
    local pc=self.owner.components.playercontroller
    if pc:IsBusy() then return "running" end
    local ok,err=pcall(function() self.queue:Update(self.owner,GetTime()) end)
    if not ok then self:Cancel();return "failed","任务执行异常，已停止："..tostring(err) end
    if self.queue.failure then return "failed",self.queue.failure end
    if not self.queue.current and #self.queue.steps==0 then return "done","任务队列已经结束。" end
    return "running"
end
function Extended:OwnsCombat() return self.auto and self.auto.OwnsCombat and self.auto:OwnsCombat() end
function Extended:Cancel()
    if self.auto then self.auto:Cancel() end
    if self.queue then self.queue:Cancel(self.owner) end
    self.running=false
end
return Extended
