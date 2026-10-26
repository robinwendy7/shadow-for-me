local savedA=package.loaded['shadowself/control/actions'];local savedTime,oldActions=GetTime,ACTIONS
local now=0;GetTime=function() return now end;ACTIONS={PICKUP={},EQUIP={}}
local bag,requests={},{}
local function entity(name,x)
 local e={prefab=name,GUID=x+65000,pos=Vector3(x,0,0),replica={},components={}}
 function e:IsValid() return true end
 function e:HasTag() return false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 return e
end
local p=entity('wilson',0);p.components.playercontroller={IsBusy=function() return false end}
p.replica.inventory={GetItems=function() return bag end,GetEquippedItem=function() end,GetNumSlots=function() return 15 end,GetOverflowContainer=function() end}
p.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
local A={Items=function() return bag end,Scene=function(_,item,action,guard) requests[#requests+1]={item=item,action=action,guard=guard};return true end,Stop=function() end}
package.loaded['shadowself/control/actions']=A
local Supply=assert(loadfile('scripts/shadowself/control/arena_supply.lua'))()
local Arena=assert(loadfile('scripts/shadowself/control/arena.lua'))()
local Inv=require('shadowself/control/arena_inventory');local Policy=require('shadowself/control/arena_policy')
local fuel=entity('nightmarefuel',2);local safe=true
local arena=setmetatable({player=p,wave=10,running=true,instance='fuel065',generation=1,bridge={},items={fuel},enemies={},fire_zones={},ignored={},healing={Safe=function() return safe end,Path=function() return safe end}},{__index=Arena})
function arena:StopCombat() end
function arena:Say(m) self.message=m end
function arena:NearbyEnemies() return {} end
assert(Supply.Tick(arena,{}) and #requests==1 and requests[1].item==fuel,'wave10 uses existing pickup path for nightmare fuel')
now=.2;assert(Supply.Tick(arena,{}) and #requests==1,'pending fuel pickup waits for actual inventory instead of duplicating requests')
safe=false;assert(not requests[1].guard(),'new real danger cancels delayed fuel pickup')
safe=true;arena.wave=11;assert(not requests[1].guard(),'wave transition invalidates delayed wave10 fuel pickup')
assert(Policy.Keep('nightmarefuel',15) and Inv.Special('nightmarefuel',15) and not Inv.Obsolete(fuel,{fuel},p,15),'fuel remains protected for later rounds')
arena.wave=9;arena.pending_item=nil;assert(not Supply.Tick(arena,{}) and #requests==1,'fuel exception does not change wave9 supply strategy')
local Bird=require('shadowself/control/arena_bird_range');local bird=entity('tallbird',4)
local c={player=p,gear={AttackRange=function() return 20 end},plan={arena=true,arena_wave=function() return 2 end,arena_bird_committed=function(e) return e==bird end}}
assert(Bird.Chase(c,bird) and Bird.Reach(c,bird)==2.3,'bird reach uses the actual held weapon rather than a desired replacement or global inflation')
bird.pos=Vector3(2,0,0);assert(not Bird.Chase(c,bird),'valid close range permits continuous attack')
bird.pos=Vector3(3,0,0);assert(Bird.Chase(c,bird),'moving bird immediately requires pursuit again')
c.plan.arena_wave=function() return 3 end;assert(not Bird.Chase(c,bird),'the correction is restricted to actual wave2')
c.plan.arena=false;c.plan.arena_wave=function() return 2 end;assert(not Bird.Chase(c,bird),'ordinary-world birds retain original behavior')
package.loaded['shadowself/control/actions']=savedA;GetTime,ACTIONS=savedTime,oldActions
print('PASS: wave2 real-range pursuit and moving-target reapproach; wave10 normal pickup ACK/delayed guards and protected later fuel, with ordinary-world/other-wave scope checks')
