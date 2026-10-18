-- 普通池塘与海钓都只用原版可见状态和动作；不读取服务端fishable库存。
local A=require("shadowself/control/actions")
local Fishing=Class(function(self,p,plan) self.p=p;self.plan=plan;self.token={};self.next=0;self.last=GetTime() end)
function Fishing:Cancel()
    self.token=nil;A.Stop(self.p)
    local rod=self.opened_rod
    if rod and rod:IsValid() and rod.replica.container:IsOpenedBy(self.p) then rod.replica.container:Close() end
end
function Fishing:Pause() self.token=nil end
function Fishing:Resume() self.token={};self.next=0;self.last=GetTime() end
function Fishing:Find(test,radius)
    local pos=self.p:GetPosition();local best,d
    for _,e in ipairs(TheSim:FindEntities(pos.x,pos.y,pos.z,radius,nil,{"INLIMBO"})) do
        if e:IsValid() and test(e) then local v=self.p:GetDistanceSqToInst(e);if not d or v<d then best,d=e,v end end
    end
    return best
end
function Fishing:Tick()
    if not self.token then return "running" end
    local p=self.p;local now=GetTime();local inv=p.replica.inventory
    if now<self.next then return "running" end
    self.next=now+.25
    if p:HasTag("playerghost") then return "failed","人变成灵魂了，先收竿。" end
    local sea=self.plan.mode=="sea";local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    local function suitable(e) return e.replica and (sea and e.replica.oceanfishingrod or not sea and e.replica.fishingrod) end
    if not hand or not suitable(hand) then
        local rod
        for _,e in ipairs(A.Items(p)) do if suitable(e) then rod=e;break end end
        if not rod then return "failed",sea and "需要一根装好浮标和鱼饵的海钓竿。" or "背包里没有普通钓竿。" end
        A.Self(p,rod,ACTIONS.EQUIP);return "running"
    end
    local token=self.token;local guard=function() return self.token==token end
    if sea then
        local rod=hand.replica.oceanfishingrod;local target=rod:GetTarget()
        if target then
            self.last=now
            if not p:HasTag("fishing_idle") then return "running" end
            if target:HasTag("fishinghook") then
                -- 尚未咬钩时target是浮标，不能持续REEL把浮标空拉回岸边。
                if self.float_target~=target then self.float_target=target;self.float_since=now end
                if target:HasTag("oceanfishing_catchable") or now-self.float_since>45 then
                    A.Ground(p,target:GetPosition(),ACTIONS.OCEAN_FISHING_STOP,guard)
                end
                return "running"
            end
            self.float_target=nil;self.float_since=nil
            if target:HasTag("oceanfishing_catchable") and not target:HasTag("fishinghook") then
                A.Ground(p,target:GetPosition(),ACTIONS.OCEAN_FISHING_CATCH,guard)
            elseif not rod:IsLineTensionHigh() and not target:HasTag("projectile") then
                A.Ground(p,target:GetPosition(),ACTIONS.OCEAN_FISHING_REEL,guard)
            end -- 拉力过高时松线，原版自动降低张力；不持续硬拉断线。
            return "running"
        end
        if p.components.playercontroller:IsBusy() then return "running" end
        local tackle=hand.replica.container
        if tackle then
            if not tackle:IsOpenedBy(p) then
                if A.Self(p,hand,ACTIONS.RUMMAGE) then self.opened_rod=hand end
                return "running"
            end
            local contents=tackle:GetItems()
            for slot,tag in ipairs({"oceanfishing_bobber","oceanfishing_lure"}) do
                if not contents[slot] then
                    for _,item in ipairs(A.Items(p)) do
                        if item:HasTag(tag) then A.Self(p,item,ACTIONS.CHANGE_TACKLE);self.next=now+.5;return "running" end
                    end
                    return "failed",slot==1 and "没有可用浮标，先准备一个。" or "没有可用鱼饵，先补一些。"
                end
            end
        end
        local limit=rod:GetMaxCastDist();if not limit or limit<3 then return "failed","海钓竿还不能抛投，请先装好浮标和鱼饵。" end
        local fish=self:Find(function(e) return e:HasTag("oceanfish") or e.prefab:match("^oceanfish_.*_inv$")==nil and e.prefab:match("^oceanfish_")~=nil end,limit)
        if not fish then
            if now-self.last>30 then return "failed","抛竿范围内暂时没有可见海鱼，换个钓点再来。" end
            return "running"
        end
        A.Ground(p,fish:GetPosition(),ACTIONS.OCEAN_FISHING_CAST,guard);self.next=now+1
    else
        local rod=hand.replica.fishingrod;local target=rod:GetTarget()
        if target and target:IsValid() then
            self.last=now
            if rod:HasCaughtFish() then return "running" end
            local anim=p.AnimState
            local nibble=p:HasTag("nibble") or anim:IsCurrentAnimation("bite_light_pre") or anim:IsCurrentAnimation("bite_light_loop")
            local hooked=rod:HasHookedFish() or anim:IsCurrentAnimation("bite_heavy_pre") or anim:IsCurrentAnimation("bite_heavy_loop")
            local step=hooked and "reel" or nibble and "hook" or nil
            if step and (self.reel_step~=step or self.reel_target~=target) then
                if A.ReelPond(p,hand,target,guard) then
                    self.reel_step=step;self.reel_target=target;self.reel_since=now
                end
            elseif step and self.reel_since and now-self.reel_since>8 then
                return "failed","已经提竿，但收鱼没有同步，先停下来检查一下。"
            end
            return "running"
        end
        if p.components.playercontroller:IsBusy() then return "running" end
        self.reel_step=nil;self.reel_target=nil;self.reel_since=nil
        self.pond=self.pond and self.pond:IsValid() and self.pond or self:Find(function(e) return e:HasTag("fishable") end,25)
        if not self.pond then return "failed","附近没有可钓鱼的池塘。" end
        if now-self.last>90 then return "failed","这处池塘很久没上鱼了，先换个地方。" end
        A.Scene(p,self.pond,ACTIONS.FISH,guard);self.next=now+1
    end
    return "running"
end
return Fishing
