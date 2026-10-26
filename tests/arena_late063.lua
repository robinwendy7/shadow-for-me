local lateCache={};for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do lateCache[k]=package.loaded["shadowself/control/"..k];package.loaded["shadowself/control/"..k]=nil end
-- Scope: only Stage11. Actual Healing.Tick verifies interrupted/acknowledged eating.
local oldA=package.loaded['shadowself/control/actions']
local oldNav=package.loaded['shadowself/control/navigation']
local oldStageFood=package.loaded['shadowself/control/arena_stage11_food'];package.loaded['shadowself/control/arena_stage11_food']=nil
local oldTime,oldWorld,oldNet=GetTime,TheWorld,TheNet
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheNet={GetPing=function() return 30 end}
local id=63000
local function ent(name,slot)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(0,0,0),tags={},components={},replica={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 e.AnimState={IsCurrentAnimation=function(_,name) return name==e.anim end}
 if slot then e.replica.equippable={EquipSlot=function() return slot end} end
 return e
end
local hp=6;local equipped;local bag={};local commands={};local moves=0;local safe=false;local stack=5
local p=ent('wilson');p.components.playercontroller={IsBusy=function() return false end}
p.replica.health={GetCurrent=function() return hp end,Max=function() return 150 end}
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HEAD and equipped end}
local A={Items=function() return bag end,Self=function(_,item,action) commands[#commands+1]={item=item,action=action};return true end}
package.loaded['shadowself/control/actions']=A
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end,Radius=function() return 3 end,Escape=function(_,q) return q end}
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage11.lua'))()
local Healing=assert(loadfile('scripts/shadowself/control/arena_healing.lua'))()
local hat=ent('wathgrithr_improvedhat',EQUIPSLOTS.HEAD)
local backup=ent('slurtlehat',EQUIPSLOTS.HEAD)
local chili=ent('fruitmedley');chili.components.edible={GetHealth=function() return 20 end}
chili.replica.stackable={StackSize=function() return stack end,IsFull=function() return false end}
local fish={};for i=1,4 do fish[i]=ent('mermguard_shadow');fish[i].pos=Vector3(i+4,0,0) end
local arena={player=p,wave=11,items={},ignored={},enemies=fish,bridge={}}
function arena:StopCombat() self.stopped=(self.stopped or 0)+1 end
function arena:Say(msg) self.message=msg end
function arena:Loot(items) self.looted=items;return true end
arena.encounters={FindCenter=function() return Vector3(0,0,0) end,
 Move=function(_,q) moves=moves+1;return 'hold' end}
local function start()
 local h=Healing(p);h.Safe=function() return safe end;arena.healing=h
 local s=Stage(arena);s.buffs={Ready=function() return true end,Check=function() end};s.prepared=true;s.hat=hat;s.opening_equipped=true
 commands={};moves=0;bag={hat,chili};equipped=hat;p.anim=nil;return s,h
end
local s,h=start()
assert(s:Tick(fish)=='hold' and s.recovering and #commands==0 and moves==1,'6 HP enters single-owner perimeter recovery instead of competing with incoming attacks')
assert(not s:Allowed(fish[1]),'captured attack entries remain closed during recovery')
safe=true;now=.3;s:Tick(fish)
assert(h.pending and #commands==1 and commands[1].action==ACTIONS.EAT,'safe window dispatches actual Healing.Tick EAT')
now=.4;p.anim='eat';s:Tick(fish);p.anim=nil;now=1.6;hp=26;s:Tick(fish)
assert(not h.pending and s.recovering and not s:Allowed(fish[1]),'infinite food healing is acknowledged but 26 HP does not immediately reenter melee')
for i=1,5 do
 now=now+1;s:Tick(fish);assert(h.pending,'recovery must issue the next actual meal')
 now=now+.1;p.anim='eat';s:Tick(fish);p.anim=nil
 now=now+1.2;hp=hp+20;s:Tick(fish)
end
now=now+.6
assert(hp==126 and s:Tick(fish)=='fight' and not s.recovering and s:Allowed(fish[1]),'melee resumes only after actual healing crosses 75 percent')
-- Threatened eating yields to movement and cannot infer success from unrelated HP recovery.
hp=6;safe=true;s,h=start();now=30;s:Tick(fish);now=30.1;p.anim='eat';s:Tick(fish)
p.anim=nil;safe=false;now=30.2;s:Tick(fish)
assert(h.pending and h.pending.interrupted and moves>0 and not s:Allowed(fish[1]))
hp=26;now=31.5;s:Tick(fish);assert(h.pending,'interrupted animation plus recovery is not an EAT acknowledgement')
stack=4;now=31.6;s:Tick(fish);assert(not h.pending,'late inventory consumption still resolves the interrupted request')
-- Initial Valkyrie hat stays mandatory; later real breakage can use valid backup armor.
hp=150;safe=true;stack=5;s,h=start();s.opening_equipped=nil;bag={backup,chili};equipped=backup;now=40
assert(s:Tick(fish)=='hold' and not s.opening_equipped and not arena.looted,'backup alone cannot skip the requested opening Valkyrie hat')
s.opening_equipped=true;bag={hat,backup,chili};hat.tags.broken=true;equipped=nil;commands={};now=41
assert(s:Tick(fish)=='hold' and commands[1].item==backup and commands[1].action==ACTIONS.EQUIP and not s:Allowed(fish[1]),'after actual opening, broken head armor requests usable backup and waits for equip ACK')
equipped=backup;now=41.5
assert(s:Tick(fish)=='fight' and s.hat==backup and s:Allowed(fish[1]),'confirmed backup head slot restores fish-first melee without waiting forever for a destroyed unique hat')
equipped=nil;bag={hat,chili};arena.items={hat,backup};arena.looted=nil;now=42
assert(s:Tick(fish)=='hold' and arena.looted[1]==backup,'broken ground Valkyrie hat is excluded; usable permitted ground backup is collected')
backup.tags.broken=true;equipped=backup
assert(not s:Allowed(fish[1]),'real broken/zero-condition head armor immediately closes melee before the next arena scan')
hat.tags.broken=nil;backup.tags.broken=nil;hp=6;safe=true;now=50;s,h=start();s:Tick(fish)
assert(h.pending)
local crack=ent('worm_boss_dirt_ground_fx');local all={crack};for _,e in ipairs(fish) do all[#all+1]=e end
now=50.1;s:Tick(all)
assert(h.pending.interrupted and moves>0 and not s:Allowed(fish[1]),'real emergence warning interrupts recovery eating before it owns movement')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/navigation']=oldNav
package.loaded['shadowself/control/arena_stage11_food']=oldStageFood
GetTime,TheWorld,TheNet=oldTime,oldWorld,oldNet
for k,v in pairs(lateCache) do package.loaded["shadowself/control/"..k]=v end
for _,k in ipairs({"arena_late_runtime","arena_stage11_finish","arena_rewards"}) do if lateCache[k]==nil then package.loaded["shadowself/control/"..k]=nil end end
print('PASS: stage11 six-HP recovery priority, real repeated infinite-food healing to75 percent, interrupted/late eating acknowledgement, mandatory opening hat and acknowledged backup after breakage')
