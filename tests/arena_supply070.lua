local savedWorld,savedSim=TheWorld,TheSim
local actionKey='shadowself/control/actions'
local oldActions=package.loaded[actionKey]
local function entity(name,x)
 local e={prefab=name,GUID=70700+x,pos=Vector3(x,0,0),replica={},components={}}
 function e:IsValid() return true end
 function e:HasTag() return false end
 function e:GetPosition() return self.pos end
 return e
end
local p=entity('wilson',0);p.components.playercontroller={IsBusy=function() return false end}
local fuel=entity('nightmarefuel',3)
local blocked=false
TheWorld={Map={IsPassableAtPoint=function(_,x) return not (blocked and x>1 and x<2) end,
 IsOceanAtPoint=function() return false end}}
TheSim={FindEntities=function() return {} end}
local bag={}
package.loaded[actionKey]={Items=function() return bag end}
-- Load real healing/navigation and the real action-library SafePoint, not permissive path stubs.
local Healing=assert(loadfile('scripts/shadowself/control/arena_healing.lua'))()
local Supply=assert(loadfile('scripts/shadowself/control/arena_supply.lua'))()
local arena={player=p,items={fuel},running=true,wave=10,fire_zones={},healing=Healing(p),bridge={}}
function arena:NearbyEnemies() return {} end
function arena:StopCombat() end
function arena:Say() end
local requests=0;local guard
function arena:Loot(items,_,check)
 assert(items[1]==fuel and check());requests=requests+1;guard=check;return true
end
assert(Supply.Tick(arena,{}) and requests==1 and arena.rest_actions,
 'first wave10 supply tick before combat creates actual navigation context and picks fuel without crash')
local library=arena.rest_actions
blocked=true
assert(not guard() and not Supply.Tick(arena,{}) and requests==1,
 'blocked intermediate terrain cancels queued pickup and prevents a new request')
blocked=false;arena.fire_zones={{pos=fuel.pos,radius=2}}
assert(not Supply.Tick(arena,{}) and requests==1,'active ground danger still blocks fuel pickup')
arena.fire_zones={};arena.healing.pending={}
assert(not Supply.Tick(arena,{}) and requests==1,'existing healing action prevents duplicate pickup')
arena.healing.pending=nil
assert(Supply.Tick(arena,{}) and arena.rest_actions==library,'subsequent ticks reuse the same action library')
arena.wave=11
assert(not guard(),'wave transition still invalidates delayed fuel pickup')
TheWorld,TheSim=savedWorld,savedSim;package.loaded[actionKey]=oldActions
print('PASS: wave9-to10 supply uses real healing/navigation/action library; terrain, danger, pending action and delayed wave guards preserved')
