local A=require("shadowself/control/actions")
local Aliases=require("shadowself/control/aliases")
local Jobs=Class(function(self,player) self.player=player end)
local actionnames={chop="CHOP",mine="MINE",pickup="PICKUP",pick="PICK",dig="DIG",hammer="HAMMER"}
function Jobs:Matches(e,name)
    if not name or name=="" then return true end
    local prefab=Aliases.Resolve(name,_G)
    if prefab and prefab==e.prefab then return true end
    local display=e:GetBasicDisplayName() or ""
    return display==name or e.prefab==name
end
function Jobs:Set(plan)
    if self.travel then self.travel:Reset();self.travel=nil end
    if self.fishing then self.fishing:Cancel();self.fishing=nil end
    if plan.kind=="fish" then self.fishing=require("shadowself/control/fishing")(self.player,plan) end
    if self.guard then self.guard:Cancel();self.guard=nil end
    self.guard_active=nil
    if self.cooking then self.cooking:Cancel();self.cooking=nil end
    if plan.kind=="cook" then self.cooking=require("shadowself/control/cooking")(self.player,plan,self.report or function() end) end
    if plan.protect then
        self.guard=require("shadowself/control/autonomy")(self.player,self.report or function() end,{guard_only=true})
    end
    if self.extended then self.extended:Cancel();self.extended=nil end
    if plan.kind=="queue" or plan.kind=="autonomy" or plan.kind=="adventure" then
        self.extended=require("shadowself/control/extended")(self.player,plan,self.report or function() end)
    end
    self.plan=plan;self.token={};self.item=nil;self.target=nil;self.before=nil;self.sent=nil;self.attempts=0
    self.ignored={};self.started=GetTime();self.last_progress=GetTime()
end
function Jobs:Cancel() if self.travel then self.travel:Reset();self.travel=nil end;if self.fishing then self.fishing:Cancel();self.fishing=nil end;if self.cooking then self.cooking:Cancel();self.cooking=nil end;if self.guard then self.guard:Cancel();self.guard=nil end;self.guard_active=nil;if self.extended then self.extended:Cancel();self.extended=nil end;self.token=nil;self.plan=nil;self.target=nil;self.item=nil end
function Jobs:Eligible(e,kind)
    if not e:IsValid() or e==self.player or e:HasTag("INLIMBO") or e:HasTag("player") then return false end
    if kind=="pickup" then return e:HasTag("_inventoryitem") and e.replica.inventoryitem and not e.replica.inventoryitem:IsHeld() end
    if kind=="pick" then return e:HasTag("pickable") end
    local name=actionnames[kind]
    return name and e:HasTag(name.."_workable")
end
function Jobs:Select()
    local p=self.player;local plan=self.plan
    local x,y,z=p.Transform:GetWorldPosition();local closest,best=nil,25*25
    for _,e in ipairs(TheSim:FindEntities(x,y,z,25,nil,{"INLIMBO","FX","DECOR"})) do
        local generic=(plan.kind=="chop" and (plan.target=="树" or plan.target=="木头" or plan.target=="树木"))
            or (plan.kind=="mine" and (plan.target=="石头" or plan.target=="矿石" or plan.target=="矿" or plan.target=="岩石"))
            or (plan.kind=="dig" and plan.target=="树桩" and e:HasTag("stump"))
        if not self.ignored[e.GUID] and self:Eligible(e,plan.kind) and (generic or self:Matches(e,plan.target)) then
            local d=p:GetDistanceSqToInst(e)
            if d<best then closest,best=e,d end
        end
    end
    return closest
end
function Jobs:Item(name)
    for _,e in ipairs(A.Items(self.player)) do if self:Matches(e,name) then return e end end
end
function Jobs:OwnsCombat() return self.guard and self.guard:OwnsCombat() or self.extended and self.extended:OwnsCombat() end
function Jobs:Tick()
    if self.guard then
        local state,message=self.guard:Tick()
        if state=="failed" then return "failed",message end
        if state~="idle" then
            if not self.guard_active then
                if self.cooking then self.cooking:Pause() end
                if self.fishing then self.fishing:Pause() end
                self.guard_active=GetTime();self.token={} -- 撤销工作动作的旧预演回调
                if self.extended and self.extended.queue then
                    local q=self.extended.queue;q.generation=(q.generation or 0)+1;q:Suspend(GetTime())
                end
            end
            self.last_progress=GetTime();return "running"
        elseif self.guard_active then
            if self.cooking then self.cooking:Resume() end
            if self.fishing then self.fishing:Resume() end
            self.guard_active=nil;self.last_progress=GetTime()
        end
    end
    if self.cooking then
        local state,message=self.cooking:Tick()
        if state~="running" then self.cooking:Cancel();self.cooking=nil end
        return state,message
    end
    if self.fishing then return self.fishing:Tick() end
    if self.extended then return self.extended:Tick() end
    local plan=self.plan;if not plan then return "done" end
    local p=self.player;local now=GetTime();local pc=p.components.playercontroller
    if now-self.last_progress>35 then return "failed","这项操作很久没有完成，我先停下来。检查距离、工具或材料后再试。" end
    if pc:IsBusy() then return "running" end
    if plan.kind=="craft" then
        local prefab=Aliases.Resolve(plan.target,_G)
        local recipe=prefab and GetValidRecipe(prefab)
        local builder=p.replica.builder
        if not self.sent then
            if not recipe or not builder or not builder:KnowsRecipe(recipe) or not builder:HasIngredients(recipe) then return "failed","还不会制作，或没有足够材料："..plan.target end
            if recipe.placer then return "failed","这个配方需要明确放置位置，暂时不自动放置建筑。" end
            self.before=A.Count(p,prefab);self.sent=now;builder:MakeRecipeFromMenu(recipe)
        elseif A.Count(p,prefab)>self.before then return "done","做好了："..plan.target end
        return "running"
    elseif plan.kind=="equip" or plan.kind=="eat" then
        local item=self.item or self:Item(plan.target)
        if not item then return "failed","身上找不到："..plan.target end
        self.item=item
        local inv=p.replica.inventory
        if plan.kind=="equip" then
            for _,e in pairs(inv:GetEquips()) do if e==item then return "done","已经装备："..plan.target end end
        elseif self.sent then
            if A.Count(p,item.prefab)<self.before then return "done","已经吃下："..plan.target end
        end
        if not self.sent then
            self.before=A.Count(p,item.prefab)
            if not A.Self(p,item,ACTIONS[plan.kind=="equip" and "EQUIP" or "EAT"]) then return "failed","现在没有可用动作："..plan.target end
            self.sent=now
        end
        return "running"
    elseif plan.kind=="goto" then
        local x,z=plan.target:match("^%s*([%-%.%d]+)%s*[,， ]%s*([%-%.%d]+)%s*$")
        local nx,nz=tonumber(x),tonumber(z)
        local point=nx and nz and Vector3(nx,0,nz) or nil
        if not point then
            local px,py,pz=p.Transform:GetWorldPosition()
            for _,e in ipairs(TheSim:FindEntities(px,py,pz,40,nil,{"INLIMBO","FX"})) do
                if self:Matches(e,plan.target) then point=e:GetPosition();break end
            end
        end
        if not point then return "failed","看不到目标的位置："..plan.target end
        self.travel=self.travel or require("shadowself/control/travel")(p)
        self.travel:Tick(point)
        if p:GetDistanceSqToPoint(point:Get())<4 then A.Stop(p);return "done","到达目标了。" end
        if now-(self.sent or -100)>.7 then A.Move(p,point);self.sent=now end
        return "running"
    end
    if self.target then
        if plan.kind=="pickup" and A.Count(p,self.target.prefab)>self.before then
            self.ignored[self.target.GUID]=true;self.target=nil;self.last_progress=now
        elseif not self.target:IsValid() or not self:Eligible(self.target,plan.kind) then
            self.ignored[self.target.GUID]=true;self.target=nil;self.last_progress=now
            if (plan.kind=="dig" or plan.kind=="hammer") and not plan.all then return "done","这个目标已经处理完了。" end
        end
    end
    if not self.target then
        self.target=self:Select();self.sent=nil;self.attempts=0
        if not self.target then return "done","附近没有更多可处理的目标了。" end
        self.before=A.Count(p,self.target.prefab)
    end
    if now-(self.sent or -100)<1 then return "running" end
    local wanted=ACTIONS[actionnames[plan.kind]]
    local token=self.token
    if A.Scene(p,self.target,wanted,function() return self.token==token end) then
        self.sent=now;self.attempts=self.attempts+1
    else
        -- 按 zom 的流程，先检查工具，等服务器装备同步后再提交工作动作。
        local tool=nil
        for _,item in ipairs(A.Items(p)) do if item:HasTag(wanted.id.."_tool") then tool=item;break end end
        if tool then
            local equipped=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            if tool==equipped then
                self.ignored[self.target.GUID]=true;self.target=nil
            elseif A.Self(p,tool,ACTIONS.EQUIP) then self.sent=now end
        else return "failed","缺少可用工具，或目标当前不能执行这个动作。" end
    end
    return "running"
end
return Jobs
