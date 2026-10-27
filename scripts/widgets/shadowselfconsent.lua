-- 同意接管合并到护甲槽上方的按钮；人物脚下只保留停止入口。
local Widget=require("widgets/widget")
local TextButton=require("widgets/textbutton")
local Consent=Class(Widget,function(self,runtime)
    Widget._ctor(self,"ShadowSelfConsent")
    self.runtime=runtime;self:SetScaleMode(SCALEMODE_PROPORTIONAL)
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
    self.stop:Hide();self:StartUpdating()
end)
function Consent:OnUpdate()
    local r=self.runtime;local owner=r.owner;local c=r.control
    if r.destroyed or r.dead or not owner:IsValid() then
        self.stop:Hide();return
    end
    local active=c and c.phase~=nil
    if not active then self.stop:Hide();return end
    local x,y=TheSim:GetScreenPos(owner.Transform:GetWorldPosition())
    self:SetPosition(x,y-26,0)
    self.stop:SetScale(TheFrontEnd:GetHUDScale())
    self.stop:Show()
end
return Consent
