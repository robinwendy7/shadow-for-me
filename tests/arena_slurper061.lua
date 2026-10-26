local oldTime=GetTime;local now=0;GetTime=function() return now end
local S=require('shadowself/control/arena_slurper')
local item={prefab='slurper',replica={},held=true,tags={INLIMBO=true}}
function item:IsValid() return true end;function item:HasTag(t) return self.tags[t] end
item.replica.inventoryitem={IsHeld=function() return item.held end}
local head=item;local busy=true;local drops,pauses,ends=0,0,0
local p={replica={inventory={GetEquippedItem=function(_,slot) if slot==EQUIPSLOTS.HEAD then return head end end,
 DropItemFromInvTile=function(_,e,single) assert(e==item and single==false);drops=drops+1 end}},
 components={playercontroller={IsBusy=function() return busy end}}}
p.GetPosition=function() return Vector3(0,0,0) end
item.GetPosition=function() return Vector3(1,0,0) end
local c={plan={arena=true,arena_wave=function() return 6 end},player=p,gear={pending={},protected_slots={[EQUIPSLOTS.HEAD]=true}},
 bridge={PauseAttack=function() pauses=pauses+1 end},h={guid=99,shadowself_dodging=item},
 travel={EndDodge=function() ends=ends+1 end},arena_snailpack={active=true,phase='bait'}}
assert(S.Tick(c) and drops==0 and not c.h.shadowself_dodging and not c.gear.pending,'attachment cancels stale battle/dodge/equip state but waits through busy')
busy=false;now=.1;assert(S.Tick(c) and drops==1)
now=.2;assert(S.Tick(c) and drops==1,'drop request cannot be mistaken for head-slot confirmation or spammed')
head=nil;now=.3;assert(S.Tick(c) and not c.bridge.priority_target,'head cleared but slurper still held is not a valid ground attack target')
item.held=false;item.tags.INLIMBO=nil;now=.7
assert(not S.Tick(c) and not c.slurper_detach and c.bridge.priority_target==item and c.bridge.resume_target==item)
assert(c.arena_snailpack.phase=='bait' and c.arena_snailpack.target==item and ends==1,'actual detachment re-enters existing locked melee instead of repeating opening bait')
assert(not c.gear.protected_slots[EQUIPSLOTS.HEAD] and not S.Tick(c),'head armour and normal combat regain control without another detach loop')
GetTime=oldTime
print('PASS: actual head attachment, busy/drop throttle, head and ground acknowledgement, stale equipment/dodge release and existing melee resumption')
