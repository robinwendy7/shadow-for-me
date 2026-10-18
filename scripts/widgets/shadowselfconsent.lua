-- 人物脚下：待授权显示同意，交接/接管期间显示停止；没有状态时全部隐藏。
local Widget=require("widgets/widget")
local TextButton=require("widgets/textbutton")
local Consent=Class(Widget,function(self,runtime)
    Widget._ctor(self,"ShadowSelfConsent")
    self.runtime=runtime;self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.button=self:AddChild(TextButton())
    self.button:SetText("同意接管");self.button:SetTextSize(24)
    self.button:SetOnClick(function()
        local c=self.runtime.control;local request=self.request
        if request and c and c.pending==request and GetTime()<=request.until_time and not self.runtime.destroyed and not self.runtime.dead then
            if self.runtime.panel then self.runtime.panel.input:SetEditing(false) end
            c:HandleText("同意接管")
        end
        self.request=nil;self.button:Hide()
    end)
    self.stop=self:AddChild(TextButton())
    self.stop:SetText("停止接管");self.stop:SetTextSize(24)
    self.stop:SetOnClick(function()
        local r=self.runtime;local c=r.control
        if c and c.phase and not r.destroyed and not r.dead then
            if r.panel then r.panel.input:SetEditing(false) end
            c:HandleText("停止接管")
        end
        self:OnUpdate()
    end)
    self.button:Hide();self.stop:Hide();self:StartUpdating()
end)
function Consent:OnUpdate()
    local r=self.runtime;local owner=r.owner;local c=r.control
    local request=c and c.pending
    if r.destroyed or r.dead or not owner:IsValid() then
        self.request=nil;self.button:Hide();self.stop:Hide();return
    end
    if request and GetTime()>request.until_time then request=nil end
    self.request=request
    local active=c and c.phase~=nil
    if not request and not active then self.button:Hide();self.stop:Hide();return end
    local x,y=TheSim:GetScreenPos(owner.Transform:GetWorldPosition())
    self:SetPosition(x,y-26,0)
    self.button:SetScale(TheFrontEnd:GetHUDScale())
    self.stop:SetScale(TheFrontEnd:GetHUDScale())
    self.button:SetPosition(active and -75 or 0,0)
    self.stop:SetPosition(request and 75 or 0,0)
    if request then self.button:Show() else self.button:Hide() end
    if active then self.stop:Show() else self.stop:Hide() end
end
return Consent
