local oldTime,oldSim,oldMods=GetTime,TheSim,rawget(_G,'ModManager')
local now=0;GetTime=function() return now end
local fx={};TheSim={FindEntities=function() return fx end}
local function item(name,slot,value)
 local e={prefab=name,GUID=88000+(slot==EQUIPSLOTS.HEAD and 1 or 2),tags={},value=value or 1,replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return Vector3(0,0,0) end
 e.replica.inventoryitem={classified={percentused={value=function() return math.floor(e.value*100+.001) end}}}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local p=item('wilson');p.entity={};local body,head;local busy=false
p.components.playercontroller={IsBusy=function() return busy end}
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.BODY and body or slot==EQUIPSLOTS.HEAD and head end}
local c={player=p,plan={arena=true}}
local Guard=assert(loadfile('scripts/shadowself/control/boneguard.lua'))()
body=item('armorskeleton',EQUIPSLOTS.BODY,.5)
assert(not Guard.Ready(c),'first sight is not a synchronized cooldown ACK')
now=6;assert(Guard.Ready(c),'full observed cooldown allows shield-backed attacks')
body.value=.45;assert(not Guard.Ready(c),'actual durability loss revokes monster-dodge suppression')
now=12;assert(Guard.Ready(c))
fx={{prefab='shadow_shield1',entity={GetParent=function() return p.entity end}}};now=12.1
assert(not Guard.Ready(c),'own shield FX restarts cooldown even without a percent update')
now=18;assert(Guard.Ready(c),'same FX must not restart cooldown every frame')
c.plan.arena=false;assert(not Guard.Ready(c));c.plan.arena=true
body.value=2.55;assert(not Guard.Ready(c),'unknown net255 is never a charged shield')
body.value=.5;body.components.cooldown={GetTimeToCharged=function() return 2 end}
assert(not Guard.Ready(c));body.components.cooldown.GetTimeToCharged=function() return 0 end
assert(Guard.Ready(c),'real synchronized component takes precedence when present')
fx={}
local Inv=require('shadowself/control/arena_inventory')
body=nil;local football=item('footballhat',EQUIPSLOTS.HEAD,.8)
local cutter=item('cookiecutterhat',EQUIPSLOTS.HEAD,1)
local ruins=item('ruinshat',EQUIPSLOTS.HEAD,.5)
local rain=item('rainhat',EQUIPSLOTS.HEAD,1)
local bag={football,cutter,ruins,rain}
assert(Inv.HelmetFallback(p,bag,1)==ruins and Inv.HelmetFallback(p,bag,8)==ruins,'absorption wins over legacy category score')
ruins.value=0;assert(Inv.HelmetFallback(p,bag,4)==football,'broken or exhausted helmet cannot be a fallback')
assert(not Inv.HelmetFallback(p,bag,9),'wave9+ is unchanged')
body=item('backpack',EQUIPSLOTS.BODY);assert(not Inv.HelmetFallback(p,bag,4),'occupied body slot retains original rules')
body=nil;bag[#bag+1]=item('armorgrass',EQUIPSLOTS.BODY)
assert(not Inv.HelmetFallback(p,bag,4),'carried usable armor retains normal armor equip flow')
-- Real bishop phase exit clears the stale movement owners, without ending its firing state early.
local rhythm=assert(loadfile('scripts/shadowself/control/arena_clockwork.lua'))()
local bishop=item('bishop_nightmare');local anim='atk2_pst'
bishop.AnimState={IsCurrentAnimation=function(_,a) return a==anim end}
local ended=0;c.secondary={pending={}};c.bridge={chasing=true};c.h={};c.travel={chasing=true,EndDodge=function(self) assert(not self.chasing);ended=ended+1 end}
local r=rhythm(bishop);assert(r:Block(c) and not r:AfterDodge(c) and ended==0,'real emission state still blocks attack')
anim='idle';assert(r:AfterDodge(c)==bishop and ended==1 and not c.secondary.pending and not c.bridge.chasing and c.h.ent==bishop,
 'state exit immediately restores bishop ownership without another generic dodge target selection')
anim='atk2_pre';assert(not r:Block(c),'no second bishop evade after first completed volley')
-- External bone Mod gets the first request window; a stalled owner cannot starve repairs forever.
local ak='shadowself/control/actions';local oldA=package.loaded[ak]
body=item('armorskeleton',EQUIPSLOTS.BODY,0);body.components.cooldown=nil
local fuel=item('nightmarefuel');bag={body,fuel};local calls=0
package.loaded[ak]={Items=function() return bag end,Self=function() return true end,
 RefuelArmor=function(_,f,a,valid) assert(f==fuel and a==body and valid());calls=calls+1;return true end}
local B=assert(loadfile('scripts/shadowself/control/arena_bone_maintenance.lua'))()
ModManager={GetMod=function() return {} end}
local arena={running=true,player=p,wave=11,generation=1,instance='088',bridge={Running=function() return true end,coordinator={special_active=true}},
 bone_maintenance={active=true,bones={},serviced={},shields={}}}
p._shadowself_arena_move_owner=arena
now=30;B.Tick(arena);assert(calls==0,'external handler retains first chance')
now=32.6;p.tags.attack=true;B.Tick(arena)
assert(calls==0 and B.Busy(p),'reserve a brief gap for maintenance without canceling the current swing')
p.tags.attack=nil;B.Tick(arena);assert(calls==1 and B.Busy(p),'stalled external owner uses the normal guarded fuel operation')
body.value=.25;now=32.8;B.Tick(arena)
assert(not B.Busy(p) and arena.bone_maintenance.serviced[body]==.25,'ACK is processed before external grace resets')
now=36;B.Tick(arena);assert(calls==1,'0-to25 confirmed repair cannot loop at the same threshold')
body.value=.2;now=37;B.Tick(arena);arena.bone_maintenance.external_request=39
now=40;B.Tick(arena);assert(calls==1,'external request event defers fallback rather than echoing another fuel RPC')
now=42;B.Tick(arena);assert(calls==2)
-- Opened chest contents are handled in the real 2.5s transformation window, with actual inventory ACKs.
local requests=0;local slots={};local open=true
p.replica.inventory.GetNumSlots=function() return 15 end;p.replica.inventory.GetItemInSlot=function() end
package.loaded[ak]={Items=function() return bag end,Stop=function() end,Scene=function() return true end}
local Rewards=assert(loadfile('scripts/shadowself/control/arena_rewards.lua'))()
local box=item('chest_mimic');local seed=item('lunar_seed');slots[1]=seed;bag={}
box.replica.container={IsOpenedBy=function() return open end,GetItems=function() return slots end,
 GetItemInSlot=function(_,slot) return slots[slot] end,IsEmpty=function() return next(slots)==nil end,
 MoveItemFromAllOfSlot=function(_,slot) assert(slot==1);requests=requests+1 end,Close=function() open=false end}
local s={player=p,context=c,arena={running=true,wave=11,bridge={},StopCombat=function() end,Say=function() end,
 healing={Safe=function() return false end,Path=function() return false end}}}
local rewards=Rewards(s,false);rewards.next_request=1000;now=50
assert(not rewards:Tick({box}) and requests==1 and rewards.pending,'confirmed open bypasses stale rummage throttle and approach-only safety')
now=50.1;rewards:Tick({box});assert(requests==1 and rewards.pending and not next(rewards.visited),'request acceptance never marks chest done')
bag={seed};slots={};now=50.5;rewards:Tick({box})
assert(not rewards.pending and not next(rewards.visited) and open,'inventory ACK starts content grace instead of immediately closing chest')
-- A late replica item must still be taken during the extended grace.
local late=item('staff_lunarplant');slots[1]=late;now=51;rewards:Tick({box})
assert(requests==2 and rewards.pending and not next(rewards.visited),'late reward during grace is requested rather than missed')
bag={seed,late};slots={};now=51.3;rewards:Tick({box})
now=52;rewards:Tick({box});assert(not next(rewards.visited),'each successful transfer restarts full grace')
now=52.2;rewards:Tick({box})
assert(rewards.visited['0:0'] and not open,'stable contents after actual ACK complete chest')
open=true;bag={};local empty=Rewards(s,false);now=60;empty:Tick({box})
assert(not next(empty.visited),'empty chest needs stable confirmed-empty state')
now=60.4;empty:Tick({box});assert(not next(empty.visited),'empty replica waits longer than former .35s')
now=60.9;empty:Tick({box});assert(empty.visited['0:0'],'confirmed empty chest does not stall the four-box flow forever')
package.loaded[ak]=oldA;p._shadowself_arena_move_owner=nil
GetTime,TheSim,ModManager=oldTime,oldSim,oldMods
print('PASS: observed bone shield and cooldown ownership, external repair grace/fallback/ACK, no repeated zero-to25 repair, early-wave strongest helmet, bishop immediate attack ownership, chest first-take/transfer/empty ACK')
