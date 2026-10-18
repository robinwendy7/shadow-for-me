-- Interaction-only simulation; no claim of live HUD rendering validation.
local now=100;GetTime=function() return now end
MOUSEBUTTON_LEFT=1;MOUSEBUTTON_RIGHT=2;MOUSEBUTTON_SCROLLUP=3;MOUSEBUTTON_SCROLLDOWN=4
CONTROL_ACCEPT=42
local function init(self) self.children={};self.shown=true;self.value="";self.pos={x=0,y=0,z=0};self.scale={x=1,y=1} end
local Fake=Class(init);Fake._ctor=init
function Fake:AddChild(c) c.parent=self;self.children[#self.children+1]=c;return c end
function Fake:SetPosition(x,y,z) self.pos={x=x,y=y,z=z or 0} end
function Fake:GetPosition() return self.pos end
function Fake:GetScale() return self.scale end
function Fake:SetScale(x) self.scale={x=x,y=x} end
function Fake:Show() self.shown=true end;function Fake:Hide() self.shown=false end
function Fake:SetString(s) self.value=s end;function Fake:GetString() return self.value end
function Fake:SetText(s) self.label=s end;function Fake:SetOnClick(fn) self.click=fn end
function Fake:SetEditing(v) self.editing=v end
function Fake:OnProcess() self:SetEditing(false);self.OnTextEntered(self:GetString()) end
function Fake:SetTextPrompt() self.prompt=self:AddChild(Fake()) end
function Fake:SetTint(r,g,b,a) self.alpha=a end
function Fake:Kill() self.killed=true end
function Fake:OnMouseButton() return false end
function Fake:OnControl() return false end
for _,name in ipairs({"SetHAnchor","SetVAnchor","SetScaleMode","ScaleToSize","SetRegionSize","SetHAlign","SetVAlign","SetTextLengthLimit","SetForceEdit","SetIdleTextColour","SetEditTextColour","StartUpdating","SetColour","SetTextSize"}) do Fake[name]=function() end end
for _,name in ipairs({"widget","image","text","textedit","textbutton"}) do package.loaded["widgets/"..name]=Fake end
package.loaded["widgets/shadowselfpanel"]=nil;package.loaded["widgets/shadowselfconsent"]=nil
local width,height=1920,1080;local mouse={x=100,y=100};local held=false
local loads,writes={},{}
TheInput={GetScreenPosition=function() return mouse end,IsMouseDown=function(_,b) return b==MOUSEBUTTON_RIGHT and held end}
json={encode=function(t) return tostring(t.x)..","..tostring(t.y) end,decode=function(s) local x,y=s:match("([^,]+),([^,]+)");return {x=tonumber(x),y=tonumber(y)} end}
TheSim={GetScreenSize=function() return width,height end,GetPersistentString=function(_,key,cb) loads[#loads+1]=cb end,
    SetPersistentString=function(_,key,data) writes[#writes+1]={key=key,data=data} end,
    GetScreenPos=function(_,x,y,z) return x*10,z*10 end}
TheFrontEnd={GetHUDScale=function() return 1.25 end}
local inputs={};local r={owner={Transform={GetWorldPosition=function() return 10,0,20 end},IsValid=function() return true end},
    dialogue={Input=function(_,s) inputs[#inputs+1]=s end},control={},frames=0}
function r:Frame() self.frames=self.frames+1 end
local parent=Fake();parent.scale={x=2,y=2}
local Panel=require("widgets/shadowselfpanel")
local panel=parent:AddChild(Panel(r,{history=20}));r.panel=panel
assert(panel.hit.alpha==0 and not panel.background and not panel.takeover and not panel.toggle and not panel.personality_button,"transparent chat without HUD controls")
panel.input.OnTextEntered("  你好  ")
assert(#inputs==1 and inputs[1]=="你好" and panel.input:GetString()=="","enter sends one private message")
panel.input:SetString("只用回车发送");panel.input:SetEditing(true);panel.input.editing_enter_down=false
panel.input:OnControl(CONTROL_ACCEPT,false);assert(#inputs==1 and panel.input.editing,"clicking the input never sends text")
panel.input.editing_enter_down=true;panel.input:OnControl(CONTROL_ACCEPT,false)
assert(#inputs==2 and inputs[2]=="只用回车发送","native enter press/release submits exactly once")
for i=1,12 do panel:AddLine("我","消息"..i) end
assert(not panel.lines and not panel.history and not panel.scroll,"input-only panel creates no transcript widgets or stored log")
assert(not panel:ChatMouse(MOUSEBUTTON_SCROLLUP,true),"removed history does not capture wheel input")
panel.focus=true;assert(panel:OnControl(CONTROL_SECONDARY,true),"right drag consumes secondary control rather than acting in the world")
held=true;assert(panel.hit.OnMouseButton(nil,MOUSEBUTTON_RIGHT,true))
mouse={x=-100,y=160};panel:OnUpdate(.016)
assert(panel:GetPosition().x==-340 and panel:GetPosition().y==30,"right drag respects HUD parent scale")
held=false;panel:OnUpdate(.016)
assert(not panel.drag and #writes==1 and writes[1].key=="shadowself_chat_position_v1","release persists position locally")
local x,y=panel:GetPosition().x,panel:GetPosition().y
loads[1](true,"-0.5,0.1");assert(panel:GetPosition().x==x and panel:GetPosition().y==y,"late load never overwrites a new drag")
local restored=parent:AddChild(Panel(r,{history=20}));loads[2](true,writes[1].data)
assert(math.abs(restored:GetPosition().x-x)<.001 and math.abs(restored:GetPosition().y-y)<.001,"new HUD restores saved position")
width,height=2560,1440;restored:OnUpdate(.016)
assert(math.abs(restored:GetPosition().x-x*4/3)<.001 and math.abs(restored:GetPosition().y-y*4/3)<.001,"position adapts to changed resolution")
held=true;panel.input.OnMouseButton(panel.input,MOUSEBUTTON_RIGHT,true);panel:Kill();assert(panel.killed and not panel.input.editing and not panel.drag)
local accepted=0
function r.control:HandleText(text) assert(text=="同意接管");accepted=accepted+1;self.pending=nil;return true end
local Consent=require("widgets/shadowselfconsent")
local consent=Consent(r);consent:OnUpdate();assert(not consent.button.shown,"no request, no control button")
r.control.pending={until_time=now+20};consent:OnUpdate()
assert(consent.button.shown and consent:GetPosition().x==100 and consent:GetPosition().y==174,"request button follows actual player feet projection")
consent.button.click();assert(accepted==1 and not r.control.pending and not consent.button.shown)
consent.button.click();assert(accepted==1,"absent request never starts autonomous takeover")
r.control.pending={until_time=now+20};consent:OnUpdate();r.control.pending={until_time=now+20};consent.button.click()
assert(accepted==1,"stale click cannot approve a replacement request")
consent:OnUpdate();now=now+21;consent:OnUpdate();assert(not consent.button.shown)
consent.button.click();assert(accepted==1,"expired consent is not accepted")
r.control.pending={until_time=now+20};r.dead=true;consent:OnUpdate();assert(not consent.button.shown)
r.dead=false;r.control.pending=nil;r.control.phase="active";consent:OnUpdate()
assert(not consent.button.shown and consent.stop.shown,"active takeover shows only feet stop button")
local stopped=0
local approve=r.control.HandleText
function r.control:HandleText(text)
    if text=="停止接管" then stopped=stopped+1;self.phase=nil;self.pending=nil;return true end
    return approve(self,text)
end
consent.stop.click();assert(stopped==1 and not r.control.phase and not consent.stop.shown)
consent.stop.click();assert(stopped==1,"stale stop click cannot start another takeover")
r.control.phase="diving";consent:OnUpdate();assert(consent.stop.shown,"can cancel possession transition from feet")
consent.stop.click();assert(stopped==2 and not consent.stop.shown)
r.control.phase="active";r.control.pending={until_time=now+20};consent:OnUpdate()
assert(consent.stop.shown and consent.button.shown and consent.button:GetPosition().x<consent.stop:GetPosition().x,"new task consent keeps stop available alongside")
r.dead=true;consent:OnUpdate();assert(not consent.stop.shown and not consent.button.shown)
print("PASS: input-only chat, no transcript/history, enter-only send, right drag/save/resize; feet consent and stop retained")

-- The floating personality picker belongs to the local shadow, not the chat HUD.
local changed
r.dialogue.SetPersonality=function(_,code) changed=code end
r.actor={inst={Transform={GetWorldPosition=function() return 12,0,22 end},IsValid=function() return true end}}
local Picker=require("widgets/shadowselfpersonality")
local picker=Picker(r);picker:OnUpdate()
assert(picker.shown and not picker.button.shown and #picker.choices==16,"right-click target exists, selector initially hidden")
assert(not picker.hit.OnMouseButton(nil,MOUSEBUTTON_LEFT,true),"left mouse is not an MBTI command")
assert(picker.hit.OnMouseButton(nil,MOUSEBUTTON_RIGHT,true) and picker.button.shown and not picker.menu.shown)
picker.button.click();assert(picker.menu.shown,"head button opens all sixteen choices")
picker.choices[1].click();assert(changed=="INTJ" and not picker.menu.shown and not picker.button.shown)
picker.hit.OnMouseButton(nil,MOUSEBUTTON_RIGHT,true);picker.button.click();picker.original.click()
assert(changed=="original","original personality can be restored")
picker.hit.OnMouseButton(nil,MOUSEBUTTON_RIGHT,true);now=now+13;picker:OnUpdate()
assert(not picker.button.shown,"unused head menu expires")
r.actor.possessed=true;picker:OnUpdate();assert(not picker.shown,"hidden shadow does not leave a HUD hitbox during possession")
r.actor.possessed=false;r.actor.speech_hidden=true;picker:OnUpdate();assert(not picker.shown)
assert(require("shadowself/personality").Resolve({personality="INFP",personality_config="ENTJ"},nil)=="INFP","new UI retains previously saved personality")
print("PASS: local-shadow right-click -> head MBTI button -> sixteen choices, restore, timeout, possession/buried hiding and saved personality migration")

-- The inventory button follows BODY slot, not fixed screen coordinates.
r.dead=false;r.control.phase=nil;r.destroyed=false
EQUIPSLOTS=EQUIPSLOTS or {BODY="body"}
local clicked=0;r.control.CombatButton=function(self) clicked=clicked+1;if self.phase then self.phase=nil else self.phase="diving" end end
local inventory=Fake();inventory.equip={}
inventory.GetWorldPosition=function() return {x=100,y=50} end
-- Use actual game Widget:GetScale, with no UITransform:GetWorldScale available.
if read_source then
local native_widget=read_source("widgets/widget.lua")
local first=assert(native_widget:find("function Widget:GetScale()",1,true))
local last=assert(native_widget:find("function Widget:GetLooseScale()",first,true))
local methods={};local getter=assert(loadstring(native_widget:sub(first,last-1)))
setfenv(getter,setmetatable({Widget=methods,Vector3=function(x,y,z) return {x=x,y=y,z=z} end},{__index=_G}));getter()
inventory.inst={UITransform={GetScale=function() return 4,4,4 end}}
inventory.parent={GetScale=function() return {x=.5,y=.5,z=.5} end}
inventory.GetScale=methods.GetScale
else
 -- Secondary Lua 5.5 syntax harness has no game-source/5.1 environment bridge.
 -- The actual getter is executed by verify51 (the DST runtime version).
 inventory.GetScale=function() return {x=2,y=2,z=2} end
end
inventory.GetWorldScale=function() error("unsupported native UITransform:GetWorldScale must never be used") end
local armor={GetWorldPosition=function() return {x=500,y=150} end}
inventory.equip[EQUIPSLOTS.BODY]=armor
local Combat=require("widgets/shadowselfcombatbutton")
local button=inventory:AddChild(Combat(r,inventory));button:OnUpdate()
assert(button.shown and button:GetPosition().x==200 and button:GetPosition().y==98,"button sits 48 local units above actual armor slot: "..tostring(button:GetPosition().x)..","..tostring(button:GetPosition().y).." scale="..tostring(inventory:GetScale().x))
button.button.click();assert(clicked==1 and button.button.label=="停止接管","combat click grants consent and updates stop state")
button.button.click();assert(clicked==2 and button.button.label=="战斗接管")
inventory.equip[EQUIPSLOTS.BODY]={GetWorldPosition=function() return {x=700,y=250} end};button:OnUpdate()
assert(button:GetPosition().x==300 and button:GetPosition().y==148,"inventory slot rebuild/scaling does not orphan button")
inventory.equip[EQUIPSLOTS.BODY]=nil;button:OnUpdate();assert(not button.shown,"no armor slot hides button without a guessed position")
r.dead=true;button.button.click();assert(clicked==2,"ghost/stale click cannot start combat")
print("PASS: armor-slot combat button follows inventory rebuild/scale, starts/stops, and blocks ghost clicks")
