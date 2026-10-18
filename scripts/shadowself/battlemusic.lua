local Music=Class(function(self,r) self.r=r end)
function Music:Volume()
    -- Read the live mixer, including options preview; Profile only changes on Save.
    local value=TheMixer and TheMixer:GetLevel("set_music")
    if type(value)~="number" then
        local saved
        if Profile then local ambient,sfx;ambient,sfx,saved=Profile:GetVolume() end
        value=type(saved)=="number" and saved/10 or 1
    end
    return math.max(0,math.min(1,value))
end
function Music:Update()
    if not self.emitter then return end
    local volume=self:Volume()
    if volume~=self.volume then
        self.emitter:SetVolume("shadowself_bgm",volume);self.volume=volume
    end
end
function Music:WatchMixer()
    local mixer=TheMixer
    if not mixer or not mixer.SetLevel then return end
    local old=mixer.SetLevel
    local hook=function(object,name,value,...)
        local result={old(object,name,value,...)}
        -- Options screens may pause/hide the gameplay HUD; update in the actual
        -- slider callback as well as gameplay frames, including Apply/Cancel.
        if name=="set_music" then self:Update() end
        return unpack(result)
    end
    self.mixer=mixer;self.old_setlevel=old;self.setlevel_hook=hook;mixer.SetLevel=hook
end
function Music:Start()
    if not (self.r.options and self.r.options.battle_music) or self.emitter then return end
    local e=TheFocalPoint and TheFocalPoint.SoundEmitter
    -- Dedicated neutral FMOD category: apply music gain exactly once to this handle.
    if e then
        self.volume=self:Volume()
        e:PlaySound("shadowself_battle/battle/theme","shadowself_bgm",self.volume);self.emitter=e;self:WatchMixer()
    end
end
function Music:Stop()
    if self.mixer and self.mixer.SetLevel==self.setlevel_hook then self.mixer.SetLevel=self.old_setlevel end
    self.mixer=nil;self.old_setlevel=nil;self.setlevel_hook=nil
    if self.emitter then self.emitter:KillSound("shadowself_bgm");self.emitter=nil end
    self.volume=nil
end
return Music
