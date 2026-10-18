-- 独立于聊天面板的本地头顶文字，不接入 talker 网络组件。
local FollowText=require("widgets/followtext")
local Speech=Class(FollowText,function(self,runtime)
    FollowText._ctor(self,TALKINGFONT,35,"")
    self.runtime=runtime
    self.symbol="headbase"
    self.normal_offset=Vector3(0,-75,0)
    self.ghost_offset=Vector3(0,-85,0)
    self:SetOffset(self.normal_offset)
    self.text:SetColour(unpack(require("shadowself/speechstyle").Color(runtime.options)))
    self.text:SetRegionSize(440,115)
    self.text:SetHAlign(ANCHOR_MIDDLE)
    self.text:Hide()
end)
function Speech:Pin(text)
    self.pinned=nil;self:Say(text);self.pinned=text
    self.pages={{text=text:gsub("[\r\n]+"," "),duration=math.huge}};self.page=1;self.displayed=nil
end
function Speech:ClearPin()
    self.pinned=nil;self.pages=nil;self.displayed=nil;self.remaining=nil
    self.text:Hide()
end
function Speech:Say(text)
    if self.pinned then return false end
    if self.runtime.voice then self.runtime.voice:Stop() end
    self.pages={};self.page=1
    if self.runtime.actor and self.runtime.actor.possessed then
        local line=text:gsub("[\r\n]+"," ")
        self.pages={{text=line,duration=2*math.min(12,3+#line/3*.075)}}
        self.remaining=nil;self.displayed=nil;return
    end
    local chars={}
    for c in string.gmatch(text,"[%z\1-\127\194-\244][\128-\191]*") do chars[#chars+1]=c end
    for start=1,#chars,48 do
        local lines={}
        local last=math.min(start+47,#chars)
        for i=start,last,16 do lines[#lines+1]=table.concat(chars,"",i,math.min(i+15,last)) end
        self.pages[#self.pages+1]={text=table.concat(lines,"\n"),duration=2*(3+(last-start+1)*.075)}
    end
    self.remaining=nil;self.displayed=nil
end
function Speech:OnUpdate(dt)
    local actor=self.runtime and self.runtime.actor
    local target=actor and actor:SpeechTarget()
    local page=self.pages and self.pages[self.page]
    local voice=self.runtime.voice
    local paused=IsSimPaused and IsSimPaused()
    if not target or not page then
        if voice then voice:Stop() end
        self.text:Hide();return
    end
    if paused and voice then voice:Stop() end
    self.target=target
    self.symbol=actor.ghost and not actor.possessed and "ghost_eyes" or "headbase"
    self.offset=actor.ghost and not actor.possessed and self.ghost_offset or self.normal_offset
    if self.displayed~=self.page then
        self.text:SetRegionSize((actor.possessed or self.pinned) and 4000 or 440,(actor.possessed or self.pinned) and 60 or 115)
        self.text:SetString(page.text);self.displayed=self.page;self.remaining=page.duration
        if voice and not paused then voice:Say(page.text,actor.ghost and not actor.possessed) end
    end
    self.text:Show()
    FollowText.OnUpdate(self,dt)
    if not paused then
        self.remaining=self.remaining-(dt or 0)
        if voice then voice:Step(dt) end
    end
    if self.remaining<=0 then self.page=self.page+1;self.displayed=nil end
end
return Speech
