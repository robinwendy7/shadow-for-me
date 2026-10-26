-- Real four-box completion, crown/seed/staff ACKs and finishing combat authorization.
local oldTime,oldWorld,oldSim,oldNet=GetTime,TheWorld,TheSim,TheNet
local ak,rk='shadowself/control/actions','shadowself/control/arena_late_runtime'
local oldA,oldR=package.loaded[ak],package.loaded[rk]
local now=0;GetTime=function() return now end;TheNet={GetPing=function() return 35 end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
local id=98000
local function ent(name,x,z)
 id=id+1;local e={prefab=name,GUID=id,pos=Vector3(x or 0,0,z or 0),tags={},replica={},components={},anim='idle',frame=0}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return n==e.anim end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent('wilson');p.components.playercontroller={IsBusy=function() return false end}
local crown,seed,staff,cane,bone=ent('alterguardianhat'),ent('lunar_seed'),ent('staff_lunarplant'),ent('cane'),ent('armorskeleton')
bone.components.fueled={GetPercent=function() return .8 end};bone.components.cooldown={GetTimeToCharged=function() return 0 end}
local bag={crown,seed,staff};local equips={[EQUIPSLOTS.BODY]=bone,[EQUIPSLOTS.HANDS]=cane};local commands={};local goal
local hatc={items={},open=false,GetNumSlots=function() return 5 end}
function hatc:GetItems() return self.items end;function hatc:GetItemInSlot(i) return self.items[i] end;function hatc:IsOpenedBy() return self.open end
crown.replica.container=hatc
p.replica.inventory={GetEquippedItem=function(_,slot) return equips[slot] end,GetItems=function() return bag end,
 MoveItemFromCountOfSlot=function(_,slot,target,n) commands[#commands+1]={kind='seed',slot=slot,target=target,count=n} end}
package.loaded[ak]={Items=function() local all={};for _,e in pairs(bag) do all[#all+1]=e end;for _,e in pairs(equips) do all[#all+1]=e end;return all end,
 Self=function(_,e,action) commands[#commands+1]={kind=action,item=e} end,Stop=function() end}
package.loaded[rk]=assert(loadfile('scripts/shadowself/control/arena_late_runtime.lua'))()
local Rewards=assert(loadfile('scripts/shadowself/control/arena_rewards.lua'))()
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
local P=require('shadowself/control/arena_scrappig');local B=require('shadowself/control/boneguard')
local pig=ent('daywalker2',8);local mimic=ent('chest_mimic_revealed',2)
local entities={pig,mimic};TheSim={FindEntities=function() return entities end}
local arena={wave=11,enemies={pig},entities=entities,bridge={},StopCombat=function() end,Say=function() end,
 encounters={Move=function(_,q) goal=q end}}
local context={player=p,enemies={pig},hazards={},actions={SafePoint=function() return true end},plan={arena=true,arena_wave=function() return 11 end,arena_center=function() return Vector3(0,0,0) end}}
local s={player=p,arena=arena,context=context,boss=pig,finish=true,route='lunar',Cleared=function() return true end,hits=999}
context.plan.arena_stage11=s;arena.stage11=s
local reward=Rewards(s,false);s.reward=reward
local boxes={};local open=true
for i=1,4 do local box=ent('chest_mimic',i*3,15);boxes[i]=box;reward.boxes[(i*3)..':15']=box end
reward.visited={['3:15']=true,['6:15']=true,['9:15']=true}
boxes[4].replica.container={IsOpenedBy=function() return open end,IsEmpty=function() return true end,GetItems=function() return {} end,Close=function() open=false end}
-- Three prior mimics can stand nearby idle without blocking the confirmed fourth box.
reward:Tick(boxes);now=.9;reward:Tick(boxes)
assert(reward:BoxesDone() and not reward.retreat and not goal and not open,'fourth confirmed box skips withdrawal and closes normally')
assert(commands[#commands].item==crown and not reward:Ready(),'same completion tick requests actual crown equip, never treats request as success')
equips[EQUIPSLOTS.HEAD]=crown;hatc.open=true;now=1;reward:Tick(entities)
assert(reward.seed_pending and commands[#commands].kind=='seed' and not reward:Ready(),'actual crown equip starts bounded real seed transfer')
now=1.1;reward:Tick(entities);assert(reward.seed_pending and commands[#commands].kind=='seed','unconfirmed seed never authorizes staff output')
hatc.items[1]=seed;bag={crown,staff};now=1.5;reward:Tick(entities)
assert(not reward.seed_pending and commands[#commands].item==staff and not reward:Ready(),'seed destination ACK requests staff but still requires actual hand equip')
equips[EQUIPSLOTS.HANDS]=staff;now=2;assert(reward:Tick(entities) and reward:Ready())
assert(Finish.Pig(s,entities)=='fight' and s.target==pig and s.phase=='staff_finish','confirmed four-box/crown/seed/staff state immediately targets pig despite nearby idle mimics')
assert(Finish.Allowed(s,pig) and not Finish.Allowed(s,mimic),'finisher keeps only the pig as an attack target, without four-hit quota')
mimic.anim='attack';mimic.frame=17;goal=nil
assert(not Finish.Allowed(s,pig) and P.Dodge(s,entities) and goal,'actual mimic bite interrupts staff output even with ready bone shield')
assert(not B.Attack(context,pig),'charged bone shortcut cannot erase finishing dodge ownership')
mimic.anim='idle';equips[EQUIPSLOTS.HANDS]=cane;now=3;goal=nil
assert(Finish.Pig(s,entities)=='hold' and commands[#commands].item==staff and not goal,'ended bite restores staff instead of fleeing idle mimic proximity')
equips[EQUIPSLOTS.HANDS]=staff;now=3.6
assert(Finish.Pig(s,entities)=='fight' and Finish.Allowed(s,pig),'actual re-equip immediately resumes finishing attack')
equips[EQUIPSLOTS.HANDS]=cane;now=60;goal=nil
assert(Finish.Pig(s,entities)=='hold' and commands[#commands].item==staff and not goal,'old reward timeout cannot reintroduce idle-mimic circling during later re-equip')
equips[EQUIPSLOTS.HANDS]=staff;now=60.6;assert(Finish.Pig(s,entities)=='fight')
pig.anim='laser_pre';assert(P.Dodge(s,entities) and not Finish.Allowed(s,pig),'four-box finishing restores cannon avoidance even when shield is ready')
pig.anim='run_pre';assert(P.Dodge(s,entities) and not Finish.Allowed(s,pig),'unarmed pounce windup remains a real finishing threat')
pig.anim='idle';mimic.anim='spawn';mimic.frame=37
assert(P.Dodge(s,entities) and not Finish.Allowed(s,pig),'mimic transformation has a separate late hit, not just bite frame18')
mimic.frame=60;assert(not P.Dodge(s,entities),'completed mimic spawn hit does not cause perpetual proximity circling')
hatc.items={};assert(not reward:Ready() and not Finish.Allowed(s,pig),'missing seed revokes output permission instead of trusting historical completion')
hatc.items[1]=seed;pig.tags.dead=true
assert(Finish.Pig(s,entities)=='hold' and not s.target and not Finish.Allowed(s,pig),'confirmed pig death ends output without attacking reward boxes')
package.loaded[ak],package.loaded[rk]=oldA,oldR;GetTime,TheWorld,TheSim,TheNet=oldTime,oldWorld,oldSim,oldNet
print('PASS: fourth-box immediate crown/seed/staff actual ACKs, idle mimic nonblocking, continuous pig-only finisher, bite/spawn/cannon/pounce avoidance with ready shield, immediate re-equip retaliation, missing-seed revocation and death stop')
