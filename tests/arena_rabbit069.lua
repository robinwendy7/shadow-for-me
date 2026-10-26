local Encounters=require('shadowself/control/encounters')
local function mob(name)
 local e={prefab=name,tags={}}
 function e:IsValid() return true end
 function e:HasTag(t) return self.tags[t] end
 return e
end
local king=mob('rabbitking_aggressive')
local adds={mob('rabbitkingminion_bunnyman'),mob('rabbitkingminion_bunnyman'),mob('rabbitkingminion_bunnyman'),mob('rabbitkingminion_bunnyman')}
local roster={king};for _,e in ipairs(adds) do roster[#roster+1]=e end
local sword={prefab='hambat'};local staff={prefab='staff_tornado'}
local c={plan={arena=true,arena_remaining=function() return roster end},enemies=roster,
 gear={forced_weapon=staff},bridge={allowed=function() return true end}}
local state=Encounters(c)
-- Exercise the actual generic-crowd dispatch, while keeping unrelated tactical handlers inert.
state.Patrol=function() end;state.Walrus=function() end;state.Penguins=function() end;state.Goats=function() end
state.arena_hunts={Tick=function() end}
local calls=0;state.arena_crowd={Tick=function() calls=calls+1;return 'support' end}
local previous={Stop=function() c.gear.forced_weapon=sword;c.arena_wind=nil end}
c.arena_wind=previous
assert(not state:Tick(adds[1]) and calls==0 and c.gear.forced_weapon==sword and not c.arena_wind,
 'minion targeting skips tornado and releases the previous staff ownership for normal weapon selection')
c.enemies=adds
assert(state:RabbitMelee(adds[1]) and not state:Tick(adds[1]) and calls==0,
 'missing king scan still permits ordinary melee against summoned rabbits without tornado')
king.tags.dead=true;roster=adds
assert(not state:Tick(adds[1]) and calls==0,'remaining summoned rabbits also use normal melee')
local unrelated={mob('bat'),mob('bat'),mob('bat'),mob('bat')}
c.enemies=unrelated;roster=unrelated
assert(state:Tick(unrelated[1])=='support' and calls==1,'other arena crowds retain their existing tornado dispatch')
c.plan.arena=false
assert(not state:RabbitMelee(king),'rabbit exception is scoped to arena combat')
print('PASS: arena rabbit king/minions use ordinary melee dispatch; pending wind ownership releases; other crowd tactics unchanged')
