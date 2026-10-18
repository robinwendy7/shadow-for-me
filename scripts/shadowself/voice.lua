-- 原版 SGwilson/SGwilsonghost 的语音选择规则，独立本地音轨。
-- 原版部分字段只在主机初始化，所以为官方角色保留对应路径映射。
local paths={webber="dontstarve_DLC001/characters/",wathgrithr="dontstarve_DLC001/characters/",
    wanda="wanda2/characters/",wonkey="monkeyisland/characters/"}
local Voice=Class(function(self,runtime) self.runtime=runtime end)
function Voice:Resolve(ghost)
    local p=self.runtime.owner
    if not p then return nil end
    local ending
    if ghost then ending=p.endghosttalksound else ending=p.endtalksound end
    if p.talksoundoverride then return p.talksoundoverride,ending end
    -- 韦斯在原版没有说话声音，不虚构一个不存在的音效。
    if p:HasTag("mime") or p.prefab=="wes" then return nil end
    local name=p.soundsname or (p.prefab=="waxwell" and "maxwell" or p.prefab)
    if not name then return nil end
    local path=p.talker_path_override or paths[p.prefab] or "dontstarve/characters/"
    if not ghost and not ending and p.prefab=="wormwood" then ending="dontstarve/characters/wormwood/end" end
    return path..name..(ghost and "/ghost_LP" or "/talk_LP"),ending
end
function Voice:Stop(finished)
    local emitter=self.emitter
    if emitter then
        emitter:KillSound("shadowself_voice")
        if finished and self.ending then emitter:PlaySound(self.ending,nil,.8) end
    end
    self.emitter=nil;self.remaining=nil;self.ending=nil
end
function Voice:Say(text,ghost)
    self:Stop()
    if self.runtime.destroyed or self.runtime.options and self.runtime.options.speech_voice==false then return end
    local sound,ending=self:Resolve(ghost)
    local emitter=TheFocalPoint and TheFocalPoint.SoundEmitter
    if not sound or not emitter then return end
    local count=0
    for _ in string.gmatch(text or "","[%z\1-\127\194-\244][\128-\191]*") do count=count+1 end
    if count==0 then return end
    self.remaining=math.min(3.2,math.max(1.2,.9+count*.045))
    self.emitter=emitter;self.ending=ending
    -- 不使用玩家自己的 talk 音轨，不触发 ontalk/状态机/服务器聊天。
    emitter:PlaySound(sound,"shadowself_voice",.8)
end
function Voice:Step(dt)
    if self.remaining then
        self.remaining=self.remaining-(dt or 0)
        if self.remaining<=0 then self:Stop(true) end
    end
end
return Voice
