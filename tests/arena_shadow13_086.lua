local Data=require('shadowself/data/arena_classic')
local P=require('shadowself/control/arena_policy')
local choices=Data.encounters[13].shadow
local expected={['bat_boss_shadow,worm_boss_shadow']=true,
 ['rocky_boss_shadow,worm_boss_shadow']=true,['bat_boss_shadow,rocky_boss_shadow']=true}
assert(#choices==3)
local found={}
for _,choice in ipairs(choices) do
 assert(choice.route=='shadow' and #choice.monsters==2)
 local names={}
 for _,v in ipairs(choice.monsters) do
  assert(v.amount==1 and v.blocking and P.Monster(v.prefab,13))
  names[#names+1]=v.prefab
 end
 table.sort(names);local key=table.concat(names,',')
 assert(expected[key] and not found[key],'each unordered boss pair appears exactly once')
 found[key]=true
end
assert(P.Monster('worm_boss_shadow_dirt',13),'actual SCD shadow worm damage entity must enter the existing bridge')
assert(not P.Monster('worm_boss_shadow_dirt',12) and not P.Monster('worm_boss_shadow_dirt',11))
assert(#Data.encounters[13].default[1].monsters==5 and Data.encounters[13].lunar[1].monsters[1].prefab=='alterguardian_phase1_lunarrift')
local old12={}
for _,v in ipairs(Data.encounters[12].shadow[1].monsters) do old12[v.prefab]=true end
assert(old12.shadowthrall_hands and old12.shadowthrall_wings and old12.shadowthrall_horns and not old12.bat_boss_shadow,'do not move new group into wave12')
-- 暗影蠕虫不复用原版蠕虫的notarget/进食阶段控制，避免套错状态机。
local Encounters=require('shadowself/control/arena_encounters')
local worm={prefab='worm_boss_shadow_dirt',IsValid=function() return true end,HasTag=function(_,tag) return tag=='worm_boss_piece' end}
local calls=0
local s=setmetatable({arena={wave=13,route='shadow'},Worm=function() calls=calls+1;return 'hold' end},Encounters)
assert(s:Tick({worm})==nil and calls==0 and s:Allowed(worm),'shadow worms retain generic selection pending dedicated implementation')
print('PASS: shadow HUD13 three-choose-two pairs, observed dirt permit, unchanged other routes/HUD12, no ordinary worm state-machine reuse')
