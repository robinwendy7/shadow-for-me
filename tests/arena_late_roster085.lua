-- 第14关真实日志中的两种双子召唤物必须进入扫描、许可和近处危险检查。
local Policy=require('shadowself/control/arena_policy')
local Arena=require('shadowself/control/arena')
local oldSim,oldTime=TheSim,GetTime
GetTime=function() return 1 end
local function point(x,z)
 local p={x=x,y=0,z=z}
 function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end
 return p
end
local function entity(name,x)
 local e={prefab=name,pos=point(x,0),tags={},replica={combat={}}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 return e
end
local p=entity('wilson',0)
local eye=entity('eyeofterror_mini',2)
local grounded=entity('eyeofterror_mini_grounded',3)
local dead=entity('eyeofterror_mini',4);dead.tags.dead=true
local ally=entity('eyeofterror_mini_ally',1)
local roster={eye,grounded,dead,ally}
TheSim={FindEntities=function() return roster end}
local active,starts,plan=false,0
local a=setmetatable({player=p,wave=14,entities={},opening={},
 bridge={Running=function() return active end,Start=function(_,v) active=true;starts=starts+1;plan=v;return true end},
 encounters={Allowed=function() return true end}},Arena)
local enemies,items=a:Entities()
assert(#enemies==2 and #items==0 and enemies[1]==eye and enemies[2]==grounded)
assert(#a:NearbyEnemies(24)==2,'rest/healing may not ignore live twin soldiers')
assert(a:Combat() and plan.arena_contains(eye) and plan.arena_contains(grounded))
assert(not plan.arena_contains(ally),'do not adopt player-friendly mini eyes')
assert(a:Combat() and starts==1,'reuse existing combat bridge, no extra soldier loop')
for wave=1,15 do
 assert(Policy.Monster(eye.prefab,wave)==(wave==14),'late soldier permit must be wave scoped')
 assert(Policy.Monster('klaus',wave)==Policy.monsters.klaus,'preserve existing boss permits')
end
a.wave=4
assert(#a:Entities()==0 and #a:NearbyEnemies(24)==0 and not plan.arena_contains(eye))

-- 蜂后仍走现有 NativePulse 专属调度，不因为补齐名单另造战斗循环。
local Coordinator=require('shadowself/control/coordinator')
local queen=entity('beequeen',3);local calls,scans=0,0
local c=setmetatable({h={ent=queen},plan={arena=true},
 beequeen={Tick=function() calls=calls+1;return true end},
 Scan=function() scans=scans+1 end},Coordinator)
c:NativePulse()
assert(calls==1 and scans==1 and c.special_active and c.queen_active)
TheSim,GetTime=oldSim,oldTime
print('PASS: twin soldier scan/permit/rest integration, wave scope, single bridge and existing queen dispatcher')
