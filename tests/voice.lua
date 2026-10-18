-- Character sound lookup and local-only loop lifetime; no claim of audible in-game validation.
local Voice=require("shadowself/voice")
local saved_focal=TheFocalPoint
local played,killed={},{}
local emitter={}
function emitter:PlaySound(sound,handle,volume) played[#played+1]={sound=sound,handle=handle,volume=volume} end
function emitter:KillSound(handle) assert(handle=="shadowself_voice","never alter native player talk channel");killed[#killed+1]=handle end
TheFocalPoint={SoundEmitter=emitter}
local owner={prefab="wilson",tags={}}
function owner:HasTag(tag) return self.tags[tag] end
local r={owner=owner};local voice=Voice(r);r.voice=voice
local cases={wilson="dontstarve/characters/wilson",waxwell="dontstarve/characters/maxwell",
    webber="dontstarve_DLC001/characters/webber",wathgrithr="dontstarve_DLC001/characters/wathgrithr",
    wanda="wanda2/characters/wanda",wonkey="monkeyisland/characters/wonkey"}
for prefab,path in pairs(cases) do
    owner.prefab=prefab
    assert(voice:Resolve(false)==path.."/talk_LP")
    assert(voice:Resolve(true)==path.."/ghost_LP")
end
owner.prefab="wes";assert(voice:Resolve(false)==nil and voice:Resolve(true)==nil)
owner.prefab="custom";owner.tags.mime=true;assert(voice:Resolve()==nil)
owner.talksoundoverride="custom/voice";assert(voice:Resolve()=="custom/voice","native explicit override precedes mime")
owner.tags.mime=nil;owner.talksoundoverride=nil;owner.soundsname="soundalias";owner.talker_path_override="custom/"
assert(voice:Resolve()=="custom/soundalias/talk_LP")
owner.soundsname=nil;owner.talker_path_override=nil;owner.prefab="wormwood"
local sound,ending=voice:Resolve(false);assert(ending=="dontstarve/characters/wormwood/end")
assert(select(2,voice:Resolve(true))==nil,"human ending never leaks into ghost sound")
voice:Say("别再挨打了。",false)
assert(#played==1 and played[1].sound==sound and played[1].handle=="shadowself_voice")
voice:Step(.1);assert(voice.remaining and #killed==0)
voice:Step(10);assert(not voice.remaining and #killed==1 and played[2].sound==ending)
voice:Say("上一句。",false);voice:Say("下一句。",true)
assert(#killed==2 and played[#played].sound=="dontstarve/characters/wormwood/ghost_LP","replacement kills old loop and chooses ghost voice")
voice:Stop();local n=#killed;voice:Stop();assert(#killed==n,"cleanup is idempotent")
r.destroyed=true;voice:Say("不应播放",false);assert(not voice.remaining);r.destroyed=false
-- Integrate with actual paged speech: hidden, replacement, pause, possession, ending.
local target={};local actor={ghost=false}
function actor:SpeechTarget() return not self.hidden and target or nil end
r.actor=actor;owner.prefab="wilson"
local Speech=require("widgets/shadowselfspeech");local speech=Speech(r)
speech:Say("你好。")
local before=#played;actor.hidden=true;speech:OnUpdate(.1);assert(#played==before,"buried shadow defers voice until text appears")
actor.hidden=false;speech:OnUpdate(.016);assert(#played==before+1 and voice.remaining)
local loop_count=#played;speech:OnUpdate(.016);assert(#played==loop_count,"same page does not restart sound every frame")
actor.hidden=true;speech:OnUpdate(.1);assert(not voice.remaining,"hidden shadow stops voice")
actor.hidden=false;actor.ghost=true;speech:Say("回来了。");speech:OnUpdate(.016)
assert(played[#played].sound=="dontstarve/characters/wilson/ghost_LP")
actor.possessed=true;speech:Say("交给我。");speech:OnUpdate(.016)
assert(played[#played].sound=="dontstarve/characters/wilson/talk_LP","possession has one human voice on independent channel")
IsSimPaused=function() return true end;speech:OnUpdate(1);assert(not voice.remaining,"pause kills local loop")
IsSimPaused=nil;actor.possessed=false;actor.ghost=false
speech:Say(string.rep("影",60));speech:OnUpdate(.016);local count=#played
speech:OnUpdate(20);speech:OnUpdate(.016);assert(#played==count+1,"new page starts one new voice burst")
r.options={speech_voice=false};local previous=#played
voice:Say("关闭声音",false);voice:Step(10);voice:Stop(true)
assert(#played==previous and not voice.remaining,"voice off kills prior loop and skips both talk and ending sounds")
r.options.speech_voice=true;voice:Say("开启声音",false);assert(#played==previous+1,"voice on restores character sound")
voice:Stop();TheFocalPoint=saved_focal
-- Check the non-default paths against this installed game's actual source.
if read_source then
    for _,prefab in ipairs({"webber","wathgrithr","wanda","wonkey"}) do
        assert(read_source("prefabs/"..prefab..".lua"):find(cases[prefab]:match("^(.*)/[^/]+$").."/",1,true))
    end
    assert(read_source("prefabs/waxwell.lua"):find('inst.soundsname = "maxwell"',1,true))
    assert(read_source("stategraphs/SGwilson.lua"):find('"/talk_LP"',1,true))
    assert(read_source("stategraphs/SGwilsonghost.lua"):find('"/ghost_LP"',1,true))
end
print("PASS: native prefab/alias/override paths, Wes silence, ghost, per-page local voice, interrupt/pause/hide/cleanup; native player talk channel untouched")
