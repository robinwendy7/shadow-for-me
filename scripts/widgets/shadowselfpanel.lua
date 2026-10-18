local Widget=require("widgets/widget")
local Image=require("widgets/image")
local TextEdit=require("widgets/textedit")
local Panel=Class(Widget,function(self,runtime,options)
    Widget._ctor(self,"ShadowSelfPanel")
    self.runtime=runtime;self.options=options;self.input_y=-139
    self.storage="shadowself_chat_position_v1"
    self:SetHAnchor(ANCHOR_RIGHT);self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL);self:SetPosition(-240,0)
    -- Input-sized transparent hit area; no transcript rows or history capture.
    self.hit=self:AddChild(Image("images/global.xml","square.tex"))
    self.hit:ScaleToSize(410,42);self.hit:SetPosition(0,self.input_y);self.hit:SetTint(0,0,0,0)
    self.input=self:AddChild(TextEdit(CHATFONT,21,""))
    self.input:SetPosition(0,-139);self.input:SetRegionSize(390,30)
    self.input:SetTextLengthLimit(180);self.input:SetForceEdit(true)
    self.input:SetIdleTextColour(.9,.85,1,1);self.input:SetEditTextColour(1,1,1,1)
    self.input:SetTextPrompt("输入消息，回车发送",{.65,.65,.7,.85})
    self.input.OnTextEntered=function(text) self:Submit(text) end
    local inputcontrol=self.input.OnControl
    self.input.OnControl=function(input,control,down)
        if control==CONTROL_ACCEPT then
            if not input.editing then
                if not down then input:SetEditing(true) end
            elseif not down and input.editing_enter_down then
                input.editing_enter_down=false;input:OnProcess()
            end
            return true
        end
        return inputcontrol(input,control,down)
    end
    local inputmouse=self.input.OnMouseButton
    self.input.OnMouseButton=function(input,button,down,...)
        if self:ChatMouse(button,down) then return true end
        if inputmouse then return inputmouse(input,button,down,...) end
    end
    self.hit.OnMouseButton=function(_,button,down)
        if self:ChatMouse(button,down) then return true end
        if button==MOUSEBUTTON_LEFT then
            if down then self.input:SetEditing(true) end
            return true
        end
        return false
    end
    if self.input.prompt then self.input.prompt.OnMouseButton=function(_,button,down)
        if self:ChatMouse(button,down) then return true end
        if button==MOUSEBUTTON_LEFT then if down then self.input:SetEditing(true) end;return true end
        return false
    end end
    if TheSim.GetPersistentString then TheSim:GetPersistentString(self.storage,function(ok,data)
        if self.killed or self.position_touched or not ok or not data or data=="" then return end
        local success,saved=pcall(json.decode,data)
        if success and type(saved)=="table" and type(saved.x)=="number" and type(saved.y)=="number" then
            self.saved_position=saved;self:RestorePosition()
        end
    end) end
    self:StartUpdating()
end)
function Panel:Viewport()
    local scale=self.parent and self.parent:GetScale() or {x=1,y=1}
    local w,h=TheSim:GetScreenSize()
    return w/scale.x,h/scale.y,scale
end
function Panel:Place(x,y)
    local w,h=self:Viewport()
    self:SetPosition(math.max(-w+205,math.min(-205,x)),math.max(-h/2+22-self.input_y,math.min(h/2-22-self.input_y,y)))
end
function Panel:RestorePosition()
    if not self.saved_position then return end
    local w,h=self:Viewport()
    self:Place(self.saved_position.x*w,self.saved_position.y*h)
end
function Panel:SavePosition()
    local w,h=self:Viewport();local pos=self:GetPosition()
    self.saved_position={x=pos.x/w,y=pos.y/h}
    TheSim:SetPersistentString(self.storage,json.encode(self.saved_position),false)
end
function Panel:ChatMouse(button,down)
    if button==MOUSEBUTTON_RIGHT then
        if down then
            self.position_touched=true;self.input:SetEditing(false)
            self.drag={mouse=TheInput:GetScreenPosition(),position=self:GetPosition()}
        else self:EndDrag() end
        return true
    end
    return false
end
function Panel:EndDrag()
    if self.drag then self.drag=nil;self:SavePosition() end
end
function Panel:OnMouseButton(button,down,x,y)
    if self:ChatMouse(button,down) then return true end
    return Widget.OnMouseButton(self,button,down,x,y)
end
function Panel:OnControl(control,down)
    if control==CONTROL_SECONDARY and (self.focus or self.drag) then return true end
    return Widget.OnControl(self,control,down)
end
function Panel:OnUpdate(dt)
    if self.runtime.destroyed then return end
    self.runtime:Frame(dt)
    local w,h=self:Viewport()
    if w~=self.view_w or h~=self.view_h then
        self.view_w,self.view_h=w,h
        if self.saved_position and not self.drag then self:RestorePosition() end
    end
    if self.drag then
        local mouse=TheInput:GetScreenPosition();local _,_,scale=self:Viewport()
        self:Place(self.drag.position.x+(mouse.x-self.drag.mouse.x)/scale.x,self.drag.position.y+(mouse.y-self.drag.mouse.y)/scale.y)
        if not TheInput:IsMouseDown(MOUSEBUTTON_RIGHT) then self:EndDrag() end
    end
end
local basekill=Panel.Kill
function Panel:Kill()
    self:EndDrag();self.killed=true
    if self.input then self.input:SetEditing(false) end
    basekill(self)
end
function Panel:Submit(text)
    text=string.gsub(text or "","^%s*(.-)%s*$","%1")
    if text=="" then return end
    self.input:SetString(""); self.input:SetEditing(false)
    self.runtime.dialogue:Input(text)
end
-- Dialogue still calls this compatibility endpoint; only head speech is displayed.
function Panel:AddLine() end
return Panel
