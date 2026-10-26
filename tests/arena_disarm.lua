local keys={'shadowself/control/actions','shadowself/control/arena_inventory','shadowself/control/arena_tools','shadowself/control/navigation','shadowself/control/arena_disarm'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k] end
local bag={};local ground={};local hand;local recover=true;local calls=0;local equips=0;local guard
local function ent(name,damage)
 local e={prefab=name,damage=damage,replica={inventoryitem={IsHeld=function() return false end}}}
 function e:IsValid() return true end;function e:HasTag(t) return self.dead and t=='dead' end
 return e
end
local torch=ent('torch',17);local sword=ent('nightsword',68);local spear=ent('spear',34);local moose=ent('moose')
package.loaded[keys[1]]={Items=function() return bag end}
package.loaded[keys[2]]={Weapon=function(e) return e==sword or e==spear end,Physical=function(e) return e.damage end}
package.loaded[keys[3]]={Usable=function() return true end,Recover=function(_,name,permit) calls=calls+1;assert(name=='nightsword');guard=permit;return recover end}
package.loaded[keys[4]]={Escape=function() return Vector3(8,0,0) end}
package.loaded[keys[5]]=nil
local D=require(keys[5]);local wave=4;local pauses=0;local moves=0
local c={plan={arena=true,arena_wave=function() return wave end,arena_ground=function() return ground end},enemies={moose},h={},
 player={replica={inventory={GetEquippedItem=function() return hand end}},GetPosition=function() return Vector3(0,0,0) end,components={playercontroller={IsBusy=function() return false end}}},
 bridge={PauseAttack=function() pauses=pauses+1 end},travel={BeginDodge=function() end},snapshot={}}
function c:Move() moves=moves+1 end
c.mechanisms={Equip=function(_,item) equips=equips+1;assert(item==sword);return hand==sword end}
bag={torch};ground={sword};hand=torch
assert(D.Tick(c) and c.disarm_item==sword and calls==1,'running arena combat actively recovers the real dropped weapon instead of selecting torch')
assert(guard(sword));wave=5;assert(not guard(sword),'late pickup cannot cross the moose wave boundary')
wave=4;bag={torch,sword};assert(D.Tick(c) and equips==1 and c.disarm_item==sword,'inventory pickup acknowledgement does not imply hand-slot acknowledgement')
hand=sword;assert(not D.Tick(c) and not c.disarm_item,'resume normal combat only after weapon is actually equipped')
bag={torch};hand=torch;recover=false;assert(D.Tick(c) and moves==1,'unsafe recovery first clears danger instead of attacking with torch')
c.h.shadowself_dodging=true;local before=calls;assert(not D.Tick(c) and calls==before,'in-progress dodge is never overwritten by recovery')
c.h.shadowself_dodging=nil;moose.dead=true;assert(not D.Tick(c),'confirmed moose death restores normal looting')
moose.dead=nil;wave=5;assert(not D.Tick(c),'other encounters retain their existing tool tactics')
-- 熊大共用缴械恢复，但成功回包或函数返回true都不代表实际手持攻击武器。
wave=4;moose.prefab='bearger';bag={torch,sword};ground={};hand=torch;recover=true
c.mechanisms.Equip=function(_,item) assert(item==sword);equips=equips+1;return true end
assert(D.Tick(c) and hand==torch,'bearger waits for actual attack-weapon hand ACK despite equip returning true')
hand=sword;assert(not D.Tick(c),'bearger resumes after actual sword is held')
hand=torch;c.h.shadowself_dodging=true
local equipBefore=equips;assert(not D.Tick(c) and equips==equipBefore,'bearger evasion is not interrupted to replace movement gear')
c.h.shadowself_dodging=nil;bag={torch};ground={sword}
bag={torch,sword};ground={};c.travel.chasing=true
assert(not D.Tick(c) and equips==equipBefore,'pursuit keeps movement equipment until it actually returns to an attack window')
c.travel.chasing=nil;bag={torch};ground={sword}
assert(D.Tick(c) and c.disarm_item==sword,'bearger recovers dropped combat weapon instead of attacking with torch')
bag={torch,sword};assert(D.Tick(c) and c.disarm_item==sword,'bearger pickup confirmation still waits for real hand slot')
hand=sword;assert(not D.Tick(c) and not c.disarm_item,'bearger pickup/equip transaction releases only on actual weapon confirmation')
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
print('PASS: moose dropped-weapon recovery during active combat, delayed pickup guard, real equip acknowledgement, danger retreat and unrelated-stage isolation')
