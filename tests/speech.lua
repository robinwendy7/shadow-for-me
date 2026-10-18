-- UI 模拟只验证文本分页、可见性与暂停，不替代真实头顶位置检查。
local function init(self,font,size)
    self.fontsize=size
    self.text={visible=false}
    function self.text:Hide() self.visible=false end
    function self.text:Show() self.visible=true end
    function self.text:SetString(text) self.string=text end
    function self.text:SetColour(...) self.colour={...} end
    function self.text:SetRegionSize() end
    function self.text:SetHAlign() end
    function self:SetOffset(offset) self.offset=offset end
end
local fake=Class(init)
fake._ctor=init
function fake:OnUpdate() self.follow_updates=(self.follow_updates or 0)+1 end
package.loaded["widgets/followtext"]=fake
Vector3=function(x,y,z) return {x=x,y=y,z=z} end
TALKINGFONT="test";ANCHOR_MIDDLE=0
local actor={hidden=false,target={}}
function actor:SpeechTarget() return not self.hidden and self.target or nil end
local Speech=require("widgets/shadowselfspeech")
local speech=Speech({actor=actor})
assert(speech.fontsize==35,"matches native talker default size")
local Style=require("shadowself/speechstyle")
assert(speech.text.colour[1]==1 and speech.text.colour[2]==.15,"default text red")
local n=0
for name,rgba in pairs(Style.colors) do
 n=n+1;local custom=Speech({actor=actor,options={speech_color=name}})
 for i=1,4 do assert(custom.text.colour[i]==rgba[i],"selected overhead color applied") end
end
assert(n==7 and Style.Color({speech_color="invalid"})==Style.colors.red)
local text=string.rep("影子陪你走。",20)
speech:Say(text)
assert(#speech.pages==3,"long speech pages without losing UTF8")
speech:OnUpdate(.016)
assert(speech.text.visible and speech.target==actor.target,"speech follows shadow target")
actor.ghost=true;speech:OnUpdate(0);assert(speech.symbol=="ghost_eyes","ghost speech follows actual animated head")
actor.ghost=false
local remaining=speech.remaining;actor.hidden=true;speech:OnUpdate(10)
assert(not speech.text.visible and speech.remaining==remaining,"buried speech timer waits")
actor.hidden=false;IsSimPaused=function() return true end;speech:OnUpdate(10)
assert(speech.remaining==remaining,"speech timer pauses with game")
IsSimPaused=nil;speech:OnUpdate(20);speech:OnUpdate(.016)
assert(speech.page==2 and speech.text.visible,"speech advances to next page")
speech:Say("亲爱的我，请不要再死了。")
speech:OnUpdate(.016);assert(speech.text.string=="亲爱的我，请不要再死了。","new line replaces older speech")
local dialog={options={frequency=25},memory={},speech={messages={}}}
function dialog.speech:Say(line) self.messages[#self.messages+1]=line end
require("shadowself/dialogue")(dialog):Input("你好")
assert(#dialog.speech.messages==1,"dialogue appears overhead without chat panel")
print("PASS: speech follows actor, UTF8 pages, buried/pause timers and dialogue routing")

actor.possessed=true;speech:Say("你好好休息吧，\n这次换我来保护你！")
assert(#speech.pages==1 and not speech.pages[1].text:find("\n",1,true),"possessed head speech is one unwrapped native-size line")
actor.possessed=false

speech:Pin("亲爱的我，你又受伤了，需要我帮忙的话点同意接管。")
speech:OnUpdate(100);speech:Say("不该覆盖申请");speech:OnUpdate(100)
assert(speech.pinned and speech.page==1 and speech.text.string==speech.pinned,"consent stays visible and cannot be replaced or timed out")
speech:ClearPin();speech:Say("交给我。");speech:OnUpdate(.01)
assert(not speech.pinned and speech.text.string=="交给我。","accept/cancel releases pinned consent")
