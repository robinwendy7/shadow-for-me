-- Actual recovery/controller code; only the game transport and spatial result are simulated.
local keys={'actions','navigation','arena_tools','arena_inventory','arena_disarm'};local saved={}
for _,k in ipairs(keys) do saved[k]=package.loaded['shadowself/control/'..k];package.loaded['shadowself/control/'..k]=nil end
local oldTime,oldActions=GetTime,ACTIONS;local now=0;GetTime=function() return now end;ACTIONS={PICKUP={}}
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),replica={},tags={},components={}}
 function e:IsValid() return true end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={IsHeld=function() return e.held end}
 return e
end
local p=ent('wilson');local goose=ent('moose',-3);local cane=ent('cane',1);local sword=ent('nightsword')
local anim,frame='honk',20
goose.AnimState={IsCurrentAnimation=function(_,n) return n==anim end,GetCurrentAnimationFrame=function() return frame end,GetCurrentAnimationLength=function() return 2 end}
local bag={sword};local hand;local busy=false;local phase=4;local ground={cane};local requests,equips=0,0;local guard;local path=true
p.components.playercontroller={IsBusy=function() return busy end}
p.replica.inventory={GetItems=function() return bag end,GetNumSlots=function() return 15 end,GetEquippedItem=function() return hand end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Self=function() error('recovering the lost cane cannot equip another cane first') end,
 Scene=function(_,item,action,g) assert(item==cane and action==ACTIONS.PICKUP);requests=requests+1;guard=g;return true end}
package.loaded['shadowself/control/navigation']={Safe=function(_,q,exclude) return path and exclude==goose end,Escape=function() end}
package.loaded['shadowself/control/arena_inventory']={Weapon=function(e) return e==sword end,Physical=function() return 68 end}
local Tools=require('shadowself/control/arena_tools');local D=require('shadowself/control/arena_disarm');local Moose=require('shadowself/control/arena_moose')
local c={player=p,enemies={goose},h={shadowself_dodging=true},snapshot={},
 plan={arena=true,arena_wave=function() return phase end,arena_ground=function() return ground end},
 travel={BeginDodge=function() end},bridge={PauseAttack=function() end},
 mechanisms={Equip=function(_,item) assert(item==sword);equips=equips+1;return hand==sword end}}
assert(Moose.PickupSafe(c,cane),'actual post-disarm honk window permits a short pickup despite the idle proximity circle')
assert(D.Tick(c) and requests==1 and c.disarm_item==cane,'missing cane is recovered even though a stronger combat weapon is already carried')
assert(guard(cane),'guard remains valid inside the observed safe window')
now=.1;D.Tick(c);assert(requests==1,'in-flight recovery does not spam pickup')
anim='atk';frame=5;assert(not guard(cane) and not Moose.PickupSafe(c,cane),'new actual windup cancels the delayed pickup')
anim='honk';frame=20;path=false;assert(not guard(cane),'other threats or blocked terrain cannot be waived by the goose window');path=true
phase=5;assert(not guard(cane),'the recovery request cannot leak into another wave');phase=4
-- Inventory receipt does not equip the cane as the combat weapon or infer an equip success.
cane.held=true;bag={sword,cane};ground={};hand=nil;c.h.shadowself_dodging=nil
assert(D.Tick(c) and equips==1 and c.disarm_item==cane,'cane receipt requests the carried combat weapon and waits for actual hand acknowledgement')
hand=sword;assert(not D.Tick(c) and c.disarm_item==nil,'actual weapon acknowledgement releases recovery')
local before=requests;assert(not D.Tick(c) and requests==before,'an already owned cane is not repeatedly recovered')
-- Near the end of the safe animation, insufficient completion time must not start a pickup.
cane.held=false;bag={sword};ground={cane};frame=59
assert(not Moose.PickupSafe(c,cane),'insufficient post-disarm window cannot be called safe')
for _,k in ipairs(keys) do package.loaded['shadowself/control/'..k]=saved[k] end
GetTime,ACTIONS=oldTime,oldActions
print('PASS: actual goose cane recovery despite carried weapon, short post-disarm window, delayed windup/path/wave cancellation, request throttle, combat weapon equip ACK and no duplicate recovery')
