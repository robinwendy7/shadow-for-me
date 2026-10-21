local path="scripts/shadowself/native/engine/HitAndRun.lua"
local f=assert(io.open(path));local src=f:read("*a");f:close()
local a=assert(src:find("do --功能性函数",1,true));local z=assert(src:find("\n\t--执行打断攻击的操作",a,true))
local part=src:sub(a,z-1).."\nend"
local frame,anim,attacking,predicting,about,clock=0,"atk",true,false,false,1
local H={guid=7,ent={GUID=7,prefab="hound"},last_fa_time=0,delay=11,keyframe=0,isserver=false}
H.PC={CanLocomote=function() return predicting end}
H.combat={GetAttackRangeWithWeapon=function() return 2 end}
H.DoubleSwitching=function() return false end
local player={HasTag=function(_,tag) return tag=="attack" and attacking end,
 sg={HasStateTag=function(_,tag) return tag=="abouttoattack" and about end},
 AnimState={GetCurrentAnimationFrame=function() return frame end},entity={GetDebugString=function() return "wilson" end}}
local env=setmetatable({HitAndRun=H,ThePlayer=player,TheWorld={ismastersim=false},FRAMES=1/30,
 TheNet={GetPing=function() return 80 end},GetTime=function() return clock end,TUNING={},
 MOD_util={GetMOption=function(_,_,default) return default end},
 ENT_util={GetAnimation=function() return anim end,FnOrNum=function(_,v,target) return type(v)=="function" and v(target) or v end}},{__index=_G})
local fn=assert(loadstring(part));setfenv(fn,env);fn()
fn=assert(loadfile("scripts/shadowself/native/engine/PlayerAnim.lua"));setfenv(fn,env);fn()
-- The former subsequent-swing branch returned true solely because 12 frames had elapsed.
assert(clock-H.last_fa_time>(H.delay+1)/30)
for _,prediction in ipairs({false,true}) do
 predicting=prediction
 for _,entry in ipairs({{"atk",2},{"whip",4},{"pocketwatch_atk",2},{"punch",7},{"attack_book",8}}) do
  anim=entry[1];local hit=entry[2]+(predicting and 1 or 0)+1
  for _,first in ipairs({false,true}) do
   H.guid=first and 0 or 7
   for _,preview in ipairs({false,true}) do
    H.performed_action=preview
    for n=0,hit-1 do frame=n;assert(not H:IsKeyFrame(),"pre-hit recovery forbidden for "..anim.." frame "..n) end
    frame=hit;assert(H:IsKeyFrame(),"allow recovery after current hit frame for "..anim)
   end
  end
 end
end
H.guid=7;anim="atk_pre";frame=100;assert(not H:IsKeyFrame(),"elapsed previous step cannot cancel windup")
anim="atk";frame=100;attacking=false;assert(not H:IsKeyFrame(),"stale animation without attack tag cannot cancel the next input")
attacking=true;about=true;assert(not H:IsKeyFrame(),"SG abouttoattack always blocks normal recovery")
about=false;H.guid=7;H.last_fa_time=clock;assert(not H:IsKeyFrame(),"retain original continuous attack cadence after hit guard")
print("PASS: real IsKeyFrame checks every swing; old expired-timer/pre-hit and stale-animation empty swings blocked; preview cannot bypass; weapon animations and both prediction modes")
