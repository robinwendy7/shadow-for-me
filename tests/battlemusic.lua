local old,oldm,oldp=TheFocalPoint,TheMixer,Profile
local plays,stops,updates=0,0,0;local level=.7;local volume
local setlevel=function(_,name,value) if name=="set_music" then level=value end end
TheMixer={SetLevel=setlevel,GetLevel=function(_,name) assert(name=="set_music");return level end}
TheFocalPoint={SoundEmitter={PlaySound=function(_,event,handle,gain)
 assert(event=="shadowself_battle/battle/theme" and handle=="shadowself_bgm");plays=plays+1;volume=gain end,
 SetVolume=function(_,handle,gain) assert(handle=="shadowself_bgm");updates=updates+1;volume=gain end,
 KillSound=function(_,handle) assert(handle=="shadowself_bgm");stops=stops+1 end}}
local Music=require("shadowself/battlemusic");local runtime={options={battle_music=false}};local music=Music(runtime)
music:Start();assert(plays==0)
runtime.options.battle_music=true;music:Start();music:Start();assert(plays==1 and volume==.7)
TheMixer:SetLevel("set_music",.2);assert(volume==.2 and plays==1,"changing music slider updates the existing track without restart")
TheMixer:SetLevel("set_music",0);assert(volume==0,"zero music slider mutes active BGM")
TheMixer:SetLevel("set_music",1);assert(volume==1,"unmute resumes original playback position")
local n=updates;music:Update();assert(updates==n,"unchanged volume needs no emitter call")
local hooked_mixer=TheMixer
TheMixer=nil;Profile={GetVolume=function() return 3,8,4 end};music:Update();assert(volume==.4,"fallback reads third profile volume, never SFX")
music:Stop();music:Stop();assert(stops==1 and hooked_mixer.SetLevel==setlevel,"stop restores native mixer method")
level=.1;music:Update();assert(updates==n+1,"stopped track receives no more volume updates")
TheFocalPoint,TheMixer,Profile=old,oldm,oldp
print("PASS: battle BGM opt-out, live mixer .7/.2/0/1 gain, no restart, profile music fallback and stop")
