local W=require('shadowself/control/arena_attackwindows')
local frame,anim,wave=0,'idle',5;local tags={}
local e={prefab='slurper',GUID=90001,Transform={GetRotation=function() return 0 end},
 AnimState={IsCurrentAnimation=function(_,n) return n==anim end,GetCurrentAnimationFrame=function() return frame end}}
function e:IsValid() return true end;function e:HasTag(t) return tags[t] end
local c={plan={arena=true,arena_wave=function() return wave end}}
assert(not W.Block(c,e) and not W.Committed(c,e),'fresh idle still needs bait rather than an invented completed cycle')
for cycle=1,2 do
 anim='atk';frame=0;assert(W.Block(c,e) and not W.Committed(c,e))
 frame=31;assert(W.Block(c,e),'rolling remains blocked until the real transition')
 anim='headslurp';frame=0;assert(W.Block(c,e) and not W.Committed(c,e),'roll and jump form one uninterrupted evade cycle')
 frame=25;assert(W.Block(c,e),'no return strike before observed miss')
 anim='headslurpmiss';assert(W.Committed(c,e) and not W.Block(c,e) and W.Dodge(c,e,{atkanim='atk'})==false,
  'miss animation grants output immediately even though the server state still has attack/busy tags')
 anim='idle';assert(W.Committed(c,e),'window persists until the next actual lock')
end
-- Source-supported HatTest-false branch: a roll can end without ever jumping.
anim='atk';frame=0;W.Block(c,e);anim='idle'
assert(W.Committed(c,e),'do not wait forever for a pounce the actual server did not perform')
tags.INLIMBO=true;assert(not W.Committed(c,e),'attached/held slurper cannot become a punish target');tags.INLIMBO=nil
wave=6;anim='headslurpmiss';assert(W.Committed(c,e),'same slurper cycle is supported in the sixth-wave pack')
wave=4;assert(W.Committed(c,e) and W.Dodge(c,e,'original')==false,'shared slurper punish window applies in every arena wave')
wave=5;c.plan.arena=false;assert(not W.Committed(c,e));c.plan.arena=true
-- Execute the actual native keyframe body with the live slurper hold-ground decision.
local f=assert(io.open('scripts/shadowself/native/engine/HitAndRun.lua'));local src=f:read('*a');f:close()
local a=assert(src:find('\tfunction HitAndRun:OnKeyFrame()',1,true))
local z=assert(src:find('\nend\n--[[HitAndRun.resetguidanims',a,true))
local attacks,walks=0,0;local H={ent=e,walktime=1,shadowself_hold_ground=function() return W.Committed(c,e) end,
 GetSpeed=function() return 6 end,CloseAndAttack=function() attacks=attacks+1 end,
 WalkTo=function() walks=walks+1 end,PredictWalkTo=function() walks=walks+1 end}
local env=setmetatable({HitAndRun=H,ThePlayer={HasTag=function() return false end,PushEvent=function() end},
 MOD_util={GetMOption=function(_,_,default) return default end},FRAMES=1/30,GetTime=function() return 1 end},{__index=_G})
local fn=assert(loadstring(src:sub(a,z-1)));setfenv(fn,env);fn()
anim='headslurpmiss';H:OnKeyFrame();H:OnKeyFrame()
assert(attacks==2 and walks==0,'punish keyframes dispatch attacks without the ordinary step-away cancelling them')
print('PASS: repeated roll/pounce/miss cycle, no boundary-frame attacks, immediate persistent punish, next-lock cancellation, no-pounce and held/scope branches, real native keyframe continuous melee')
