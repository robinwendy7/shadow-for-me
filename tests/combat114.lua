-- 基于可见动画、装备同步和库存消耗的场景回归；非游戏实测。
local oldA=package.loaded["shadowself/control/actions"]
local oldEnc=package.loaded["shadowself/control/encounters"];local oldSup=package.loaded["shadowself/control/supplies"]
local now=0;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=1000
local function entity(name,x,z)
 guid=guid+1;local e={GUID=guid,prefab=name,pos=Vector3(x or 0,0,z or 0),tags={aggro=true},frame=0,replica={}}
 function e:IsValid() return true end;function e:HasTag(k) return self.tags[k] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end,GetHistoryData=function() return nil,e.anim end}
 e.replica.combat={GetAttackRangeWithWeapon=function() return 3 end};return e
end
local p=entity("wilson",0,0);local slots={};local items={};local busy=false;local eaten,played,pauses=0,0,0
p.tags={};p.replica.inventory={GetEquippedItem=function(_,slot) return slots[slot] end}
p.components={playercontroller={IsBusy=function() return busy end}}
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"};ACTIONS={EQUIP={},EAT={},PLAY={}}
TUNING={WALRUS_DART_RANGE=25,WALRUS_LOSETARGET_DIST=30,PANFLUTE_SLEEPRANGE=15,LIGHTNING_GOAT_ATTACK_RANGE=3,BUFF_ELECTRICATTACK_DURATION=300,BUFF_ATTACK_DURATION=240}
TheNet={GetPing=function() return 0 end}
local A={Items=function() return items end,Self=function(_,item,action)
 if action==ACTIONS.EQUIP then slots[item.replica.equippable:EquipSlot()]=item
 elseif action==ACTIONS.EAT then eaten=eaten+1
 elseif action==ACTIONS.PLAY then played=played+1 end
 return true
end}
package.loaded["shadowself/control/actions"]=A;package.loaded["shadowself/control/encounters"]=nil;package.loaded["shadowself/control/supplies"]=nil
local bridge={PauseAttack=function() pauses=pauses+1 end,allowed=function(e) return e.tags.aggro end}
local c={player=p,bridge=bridge,enemies={},observed={},hazards={},gear={},snapshot={},actions={SafePoint=function() return true end},
 travel={BeginDodge=function() end,EndDodge=function() end},Move=function(self,point,label) self.moved=point;self.label=label end}
c.mechanisms={Equip=function(_,item) if slots[item.replica.equippable:EquipSlot()]==item then return true end;A.Self(p,item,ACTIONS.EQUIP);return false end}
local Enc=require("shadowself/control/encounters");local e=Enc(c);c.encounters=e
local walrus=entity("walrus",10,0);local dog=entity("icehound",2,0)
c.enemies={walrus,dog};local mode,target=e:Tick(walrus)
assert(mode=="attack" and target==dog and bridge.priority_target==dog,"ice dogs are killed before walrus manoeuvre")
-- 复现服务器第二关：威胁列表仍含陷阱冰狗，但攻击过滤拒绝它。
dog.tags.aggro=false;dog.anim="sleep_loop";dog.tags.sleeping=true
for i=1,12 do
 mode,target=e:Tick(walrus)
 assert(mode=="move" and target==walrus and bridge.priority_target==walrus and not e.allowed[dog],"sleeping forbidden ice dog cannot pin walrus tactics or suppress movement")
end
dog.tags.aggro=true;dog.tags.sleeping=nil;dog.anim="run_loop"
mode,target=e:Tick(walrus)
assert(mode=="attack" and target==dog,"awakened permitted ice dog resumes priority")
dog.tags.isdead=true;c.enemies={walrus};now=1;mode,target=e:Tick(walrus)
assert(mode=="move" and c.moved.x<0 and pauses>0,"walrus retreat physically stops attacks before moving outside darts")
p.pos=Vector3(42,0,0);now=2;walrus.anim="idle_happy";mode=e:Tick(walrus)
assert(mode=="support","distance alone waits for observed calm state")
now=2.3;mode,target=e:Tick(walrus)
assert(mode=="attack" and target==walrus and e.walrus_stage=="rush","confirmed target loss and ordinary wandering resume pursuit")
walrus.tags.isdead=true
local bird=entity("penguin",2,0);bird.anim="slide_loop";c.enemies={bird};p.pos=Vector3(0,0,0)
local flute=entity("panflute");items={flute};now=3;mode=e:Tick(bird)
assert(mode=="move" and played==0,"retreat before playing at close sliding penguins")
p.pos=Vector3(12,0,0);now=4;mode=e:Tick(bird)
assert(mode=="support" and played==1,"play once at safe distance inside flute range")
bird.anim="atk_pre";now=4.2;mode=e:Tick(bird)
assert(mode=="support","animation change alone is not a successful sleep acknowledgement")
bird.tags.sleeping=true;now=4.3;mode,target=e:Tick(bird)
assert(mode=="attack" and target==bird and played==1,"observed sleep resumes attacks without replaying flute")
bird.tags.sleeping=nil;bird.frame=10;assert(e:Dodge(bird,false),"actual atk_pre is dodged before frame-15 hit")
bird.frame=15;assert(not e:Dodge(bird,false));bird.prefab="mutated_penguin";bird.anim="slide_bounce"
assert(e:Dodge(bird,false).dist==6,"lunar penguins share slide avoidance")
local function equipment(name,slot)
 local i=entity(name);i.replica.equippable={EquipSlot=function() return slot end,IsRestricted=function() return false end};return i
end
local hat=equipment("rainhat",EQUIPSLOTS.HEAD);local coat=equipment("raincoat",EQUIPSLOTS.BODY);items={hat,coat}
local goats={entity("lightninggoat",3,0),entity("lightninggoat",6,1),entity("lightninggoat",8,-1)}
for _,goat in ipairs(goats) do goat.tags.charged=true end
c.enemies=goats;c.observed={};p.pos=Vector3(0,0,0);now=10
mode=e:Tick(goats[1]);assert(mode=="support" and slots.head==hat,"equip insulating head before attacking charged goats")
mode=e:Tick(goats[1]);assert(mode=="support" and slots.body==coat,"equip insulating clothing too")
mode=e:Tick(goats[1]);assert(mode=="move" and e.goat.phase=="gather" and c.gear.protected_slots.head and c.gear.protected_slots.body,"goat-only circle gathers with insulation protected from armour swaps")
now=12.5;mode=e:Tick(goats[1]);assert(mode=="move" and e.goat.phase=="bait","circle has a finite duration and then baits attacks")
c.observed[goats[1].GUID]={dodge={}};now=12.6;mode=e:Tick(goats[1])
assert(mode=="attack" and e.goat.phase=="punish","real windup ends gathering and returns control to native dodge and punish")
c.observed={};now=15;mode,target=e:Tick(goats[1]);assert(mode=="attack" and target,"recovery windows are attacked rather than restarting circles forever")
-- Supplies: real count decrease, independent timers, safe handoff and failure timeout.
c.enemies={};c.observed={};c.travel.dodging=false;bridge.chasing=false
local function food(name,count) local f=entity(name);f.count=count;f.replica.stackable={StackSize=function() return f.count end};return f end
local chili=food("voltgoatjelly_spice_chili",2);local plain=food("voltgoatjelly",2);items={plain,chili};now=20
local Supply=require("shadowself/control/supplies");local supply=Supply(c)
assert(supply:Tick() and supply.pending.name==chili.prefab and eaten==1 and not supply.state.electric_until,"prefer chili but do not grant buffs on request alone")
chili.count=1;now=20.1;supply:Tick()
assert(supply.state.electric_until==320.1 and supply.state.attack_until==260.1,"confirmed consumption starts source-accurate separate durations")
now=100;assert(not supply:Tick() and eaten==1,"active buffs do not waste food")
now=261;assert(supply:Tick() and eaten==2,"expired chili attack buff is refreshed even while electric buff remains")
chili.count=0;items={plain};now=261.1;supply:Tick()
now=562;assert(supply:Tick() and supply.pending.name==plain.prefab and eaten==3,"base jelly also replenishes expired electric buff")
plain.count=1;now=562.1;supply:Tick()
now=900;busy=true;p.tags.attack=true
assert(supply:Tick() and not supply.pending,"stop scheduling swings and let current attack finish before eating")
busy=false;p.tags.attack=nil;assert(supply:Tick() and eaten==4)
now=901;assert(not supply:Tick(),"unacknowledged rejected food does not stall combat for entire timeout")
now=904;assert(not supply:Tick() and not supply.pending,"failed consumption never invents a buff or loops requests")
assert(read_source("components/playercontroller.lua"):find('self.ismastersim and self:IsEnabled() and self.handler == nil',1,true),"host action gate matches installed game")
assert(read_source("stategraphs/SGwalrus.lua"):find('EventHandler("newcombattarget"',1,true))
assert(read_source("stategraphs/SGpenguin.lua"):find('TimeEvent(15*FRAMES',1,true))
assert(read_source("prefabs/lightninggoat.lua"):find('inventory:IsInsulated()',1,true))
package.loaded["shadowself/control/actions"]=oldA;package.loaded["shadowself/control/encounters"]=oldEnc;package.loaded["shadowself/control/supplies"]=oldSup
print("PASS: walrus dogs/retreat/rush, sliding penguin sleep confirmation, charged-goat insulation/circle/bait/punish, confirmed jelly/chili refresh and non-blocking failed food")
