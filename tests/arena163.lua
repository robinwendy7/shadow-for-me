local keys={'shadowself/control/actions','shadowself/control/arena_tools','shadowself/control/arena_hunts','shadowself/control/arena_goats','shadowself/control/navigation','shadowself/control/arena_pirates'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end;function e:HasTag(k) return self.tags[k] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.replica.inventoryitem={IsHeld=function() return e.held end,classified={percentused={value=function() return e.percent or 100 end}}}
 return e
end
local bag,ground={},{};local hand;local plays,attacks,picks,drops=0,0,0,0;local picked,castTargets
local p=ent('wilson',0);p.components.playercontroller={IsBusy=function() return false end}
p.replica.inventory={GetItems=function() return bag end,GetNumSlots=function() return 15 end,GetEquippedItem=function() return hand end,DropItemFromInvTile=function(_,item) drops=drops+1 end}
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Self=function(_,item,action) assert(action==ACTIONS.PLAY);plays=plays+1;return true end,
 Attack=function(_,target,guard) assert(not guard or guard());attacks=attacks+1;return true end,
 Scene=function(_,item,action,guard) assert(action==ACTIONS.PICKUP and (not guard or guard()));picks=picks+1;picked=item;return true end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end}
package.loaded['shadowself/control/arena_goats']=function(owner,label) assert(label=='火药猴');return {Tick=function(_,targets) castTargets=targets;return 'support',targets[1] end} end
package.loaded['shadowself/control/arena_tools']=nil;package.loaded['shadowself/control/arena_hunts']=nil
local Tools=require('shadowself/control/arena_tools')
local c={player=p,plan={arena=true,arena_ground=function() return ground end},enemies={},snapshot={},bridge={allowed=function(e) return not e.tags.sleeping end,PauseAttack=function() end}}
local sword=ent('nightsword');c.gear={Weapon=function() return sword end,Swap=function() end};c.mechanisms={Equip=function() return true end}
local owner={c=c,Target=function(_,e) return e end,Release=function() end,Move=function() return 'move' end}
local Hunts=require('shadowself/control/arena_hunts');local hunts=Hunts(owner)
local little=ent('little_walrus',7);local walrus=ent('walrus',10);local flute=ent('panflute');bag={flute}
c.enemies={little,walrus};local mode,target=hunts:Tick(little)
assert(mode=='attack' and target==walrus and plays==0,'little walrus is left until last')
c.enemies={little};assert(not hunts:Tick(little),'short chase allowed before spending flute')
now=3.1;assert(hunts:Tick(little)=='support' and plays==1,'last fleeing little walrus gets flute after failed chase')
now=3.2;hunts:Tick(little);assert(plays==1,'no duplicate pending flute action')
little.tags.sleeping=true;mode,target=hunts:Tick(little);assert(mode=='attack' and target==little,'sleeping acknowledgement releases attack immediately')
local empty=ent('panflute');empty.percent=0;local spare=ent('panflute',4)
assert(not Tools.Usable(empty) and Tools.Usable(spare))
bag={empty};ground={spare};now=5
assert(Tools.Recover(c,'panflute') and drops==1 and picks==0,'spent flute removed before replacement pickup')
bag={};now=6;assert(Tools.Recover(c,'panflute') and picked==spare and picks==1,'unowned ground flute replenishes after exhaustion')
spare.held=true;bag={spare};assert(not Tools.Recover(c,'panflute') and picks==1,'authoritative inventory ownership prevents duplicate pickup')
local captain=ent('prime_mate',1);local monkey=ent('powder_monkey',5)
package.loaded['shadowself/control/arena_pirates']=function(owner) return {Tick=function(_,entities) assert(entities[1]==captain and entities[2]==monkey);return 'move',monkey end} end
c.enemies={captain,monkey};local mode,target=hunts:Tick(captain)
assert(mode=='move' and target==monkey and attacks==0,'pirates use the dedicated wave policy without the old torch opener')
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end;GetTime=oldTime
print('PASS: last fleeing little walrus flute/ack; spent flute replacement and pickup ownership; pirates delegate to the dedicated wave policy')
