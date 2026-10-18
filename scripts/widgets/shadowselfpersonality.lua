-- 本地影子的右键命中区域；不让装饰实体参与服务器交互。
local Widget=require("widgets/widget")
local Image=require("widgets/image")
local TextButton=require("widgets/textbutton")
local Personality=require("shadowself/personality")
local Picker=Class(Widget,function(self,runtime)
    Widget._ctor(self,"ShadowSelfPersonality")
    self.runtime=runtime;self:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.hit=self:AddChild(Image("images/global.xml","square.tex"))
    self.hit:ScaleToSize(54,90);self.hit:SetPosition(0,45);self.hit:SetTint(0,0,0,0)
    self.hit.OnMouseButton=function(_,button,down)
        if button~=MOUSEBUTTON_RIGHT then return false end
        if down then self.until_time=GetTime()+12;self.menu:Hide();self.button:Show() end
        return true
    end
    self.button=self:AddChild(TextButton())
    self.button:SetText("MBTI人格");self.button:SetTextSize(23);self.button:SetPosition(0,115)
    self.button:SetOnClick(function()
        self.until_time=GetTime()+30
        if self.menu.shown then self.menu:Hide() else self.menu:Show() end
    end)
    self.menu=self:AddChild(Widget("ShadowSelfPersonalityChoices"))
    self.choices={}
    for i,code in ipairs(Personality.order) do
        local selected=code;local profile=Personality.Get(code)
        local button=self.menu:AddChild(TextButton())
        button:SetText(code.." · "..profile.name);button:SetTextSize(21)
        button:SetPosition(((i-1)%4-1.5)*145,72-math.floor((i-1)/4)*40)
        button:SetOnClick(function() self:Choose(selected) end)
        self.choices[#self.choices+1]=button
    end
    self.original=self.menu:AddChild(TextButton())
    self.original:SetText("恢复原版影子");self.original:SetTextSize(21);self.original:SetPosition(0,-98)
    self.original:SetOnClick(function() self:Choose("original") end)
    self.button:Hide();self.menu:Hide();self:StartUpdating()
end)
function Picker:Choose(code)
    local r=self.runtime
    if not r.destroyed and r.dialogue then
        if r.panel then r.panel.input:SetEditing(false) end
        r.dialogue:SetPersonality(code)
    end
    self.until_time=nil;self.menu:Hide();self.button:Hide()
end
function Picker:OnControl(control,down)
    if control==CONTROL_SECONDARY and self.focus then return true end
    return Widget.OnControl(self,control,down)
end
function Picker:OnUpdate()
    local r=self.runtime;local actor=r.actor;local target=actor and actor.inst
    if r.destroyed or not target or not target:IsValid() or actor.possessed or actor.speech_hidden then
        self:Hide();self.menu:Hide();self.button:Hide();self.until_time=nil;return
    end
    self:Show()
    local x,y=TheSim:GetScreenPos(target.Transform:GetWorldPosition())
    self:SetPosition(x,y,0)
    local scale=TheFrontEnd:GetHUDScale()
    if target.AnimState then
        local hx,hy=TheSim:GetScreenPos(target.AnimState:GetSymbolPosition(actor.ghost and "ghost_eyes" or "headbase",0,-20,0))
        self.button:SetPosition(hx-x,hy-y+20*scale)
    end
    self.hit:SetScale(scale);self.button:SetScale(scale);self.menu:SetScale(scale)
    local w,h=TheSim:GetScreenSize()
    local mx=math.max(300*scale,math.min(w-300*scale,x))-x
    local my=y+330*scale<h and 245*scale or -130*scale
    self.menu:SetPosition(mx,my,0)
    if self.until_time and GetTime()>self.until_time then
        self.until_time=nil;self.menu:Hide();self.button:Hide()
    end
end
return Picker
