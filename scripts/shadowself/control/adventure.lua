-- zom 的旺达救援、裂隙表与猪币测向；输出只进入影子窗口。
local Actions=require("shadowself/control/actions")
local Adventure=Class(function(self,owner,step,report)
    self.owner=owner;self.step=step;self.report=report
    self.tools=require("shadowself/zom/AdventureTools").new(_G,
        function(_,message) report(message) end,
        function(p,point) return Actions.Move(p,point) end,
        function(p) Actions.Stop(p) end,
        function(_,message) report(message) end)
end)
function Adventure:Tick()
    local step=self.step;local p=self.owner;local now=GetTime()
    if not self.started then
        local sender={entity=p,userid=p.userid,name=p:GetDisplayName()}
        local ok,why
        if step.kind=="wanda_revive" then
            local x,y,z=p.Transform:GetWorldPosition();local target
            for _,e in ipairs(TheSim:FindEntities(x,y,z,40,{"playerghost"},{"INLIMBO"})) do
                if not step.text or step.text==e:GetDisplayName() or step.text==e.userid then
                    if target then return "failed","附近有多个灵魂，请说清要救谁。" end
                    target=e
                end
            end
            if not target then return "failed","附近看不到要救的灵魂。" end
            ok,why=self.tools:StartRevive(p,sender,now,target,target:GetDisplayName())
        elseif step.kind=="sector_watch" then ok,why=self.tools:StartWatch(p,sender,step.sector,now)
        elseif step.kind=="pig_coin_search" then ok,why=self.tools:StartSearch(p,sender,step.grade,now) end
        if not ok then return "failed",why or "当前无法执行。" end
        self.started=true;if why then self.report(why) end
    end
    self.tools:Update(p,now,false)
    return self.tools:IsActive() and "running" or "done"
end
function Adventure:Cancel() self.tools:Cancel(self.owner) end
return Adventure
