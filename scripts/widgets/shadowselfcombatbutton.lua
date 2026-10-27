local Widget=require("widgets/widget")
local TextButton=require("widgets/textbutton")
local CombatButton=Class(Widget,function(self,runtime,inventory)
    Widget._ctor(self,"ShadowSelfCombatButton")
    self.runtime=runtime;self.inventory=inventory
    self.button=self:AddChild(TextButton())
    self.button:SetText("战斗接管");self.button:SetTextSize(18)
    self.button:SetOnClick(function()
        local r=self.runtime
        if r.destroyed or r.dead then return end
        if r.panel then r.panel.input:SetEditing(false) end
        r.control:CombatButton();self:OnUpdate()
    end)
    self:Hide();self:StartUpdating()
end)
function CombatButton:OnUpdate()
    local r=self.runtime;local inv=self.inventory
    local slot=inv.equip and inv.equip[EQUIPSLOTS.BODY]
    if r.destroyed or r.dead or not r.owner:IsValid() or not slot then self:Hide();return end
    -- Parent is inventorybar itself, so slot rebuilds do not destroy this widget.
    -- Read the current slot every frame to follow HUD scale, backpacks and mods.
    local p=slot:GetWorldPosition();local origin=inv:GetWorldPosition();local scale=inv:GetScale()
    self:SetPosition((p.x-origin.x)/scale.x,(p.y-origin.y)/scale.y+48)
    self.button:SetText(r.control.pending and "同意接管" or (r.control.phase and "停止接管" or "战斗接管"))
    self:Show()
end
return CombatButton
