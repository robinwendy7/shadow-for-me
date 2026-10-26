local oldTime,oldWorld,oldSim=GetTime,TheWorld,TheSim
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),anim='idle',frame=0,replica={},components={},tags={}}
 function e:IsValid() return not self.removed end;function e:HasTag(n) return self.tags[n] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.Transform={GetRotation=function() return 0 end};e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent('wilson');p.replica.inventory={GetEquippedItem=function() end}
local spore=ent('spore_moon');local objects={spore};TheSim={FindEntities=function() return objects end}
local ak='shadowself/control/actions';local oldA=package.loaded[ak];local moves=0;local goal
package.loaded[ak]={Items=function() return {} end,Move=function(_,q) goal=q;moves=moves+1 end}
local Residual=assert(loadfile('scripts/shadowself/control/arena_residual.lua'))()
local arena={player=p,enemies={},wave=6,StopCombat=function() end,Say=function() end}
assert(Residual.Tick(arena) and moves==1 and goal:DistSq(spore.pos)>4^2,'idle residual moonspore after clear triggers a real safe exit before supplies')
spore.removed=true;now=.2;objects={};assert(not Residual.Tick(arena),'invalid/destroyed spore no longer blocks rest')
arena.enemies={ent('hound')};objects={spore};assert(not Residual.Tick(arena),'residual monitor does not replace live combat')
package.loaded[ak]=oldA
local Guard=require('shadowself/control/boneguard');local W=require('shadowself/control/arena_attackwindows')
local bone=ent('armorskeleton');bone.components.fueled={GetPercent=function() return .5 end};local cooldown=0
bone.components.cooldown={GetTimeToCharged=function() return cooldown end}
p.replica.inventory.GetEquippedItem=function() return bone end
local swapped;local c={player=p,plan={arena=true,arena_wave=function() return 10 end},secondary={pending={}},
 bridge={chasing=true},travel={dodging=true,chasing=true,EndDodge=function(self) self.dodging=nil;self.restore_dodge=nil end},
 gear={Swap=function(_,role) swapped=role end},snapshot={}}
local dragon=ent('dragonfly');dragon.anim='atk';dragon.frame=14
assert(Guard.Attack(c,dragon) and not c.travel.dodging and not c.travel.chasing and not c.bridge.chasing and not c.secondary.pending and swapped=='attack',
 'charged armor clears stale cane dodge state before weapon restoration')
cooldown=5;dragon.frame=15
assert(not Guard.Ready(c) and W.Committed(c,dragon) and not W.Block(c,dragon),'observed shield-backed swipe continues retaliation after its single damage frame')
dragon.frame=0;assert(W.Block(c,dragon) and not W.Committed(c,dragon),'next attack frame reset restores avoidance while shield is cooling')
dragon.frame=22;assert(W.Committed(c,dragon),'unshielded swipe ends after damage plus latency margin, without waiting for full animation idle')
local native=require('shadowself/native');local oldNative=native.context
local entry={atkanim='windup',atk_start_frame=12,atk_stop_frame=20}
native.context={HitAndRun={targetanimtable={daywalker={entry}}},ENT_util={GetAnimation=function(_,e) return e.anim end,
 FnOrNum=function(_,v) return v end}}
c.plan.arena_wave=function() return 11 end;local pig=ent('daywalker');pig.anim='windup';pig.frame=6
assert(Guard.Early(c,pig,nil)==entry,'cooling bone armor starts existing windup dodge before its former start threshold')
pig.anim='idle';assert(not Guard.Early(c,pig,nil),'ordinary idle is not fabricated into a new attack')
native.context=oldNative
local Policy=require('shadowself/control/arena_policy')
assert(Policy.Monster('lunar_grazer',12) and Policy.Monster('lunar_grazer',13) and not Policy.Monster('lunar_grazer',11),'logged grazers reach the existing lunar handling only in the two observed waves')
local bag={};local slots={ent('nightsword'),ent('staff_lunarplant'),ent('alterguardianhat'),ent('lunar_seed')};local takes={}
p.replica.inventory.GetNumSlots=function() return 15 end;p.replica.inventory.GetItemInSlot=function() end
package.loaded[ak]={Items=function() return bag end,Stop=function() end}
local Rewards=assert(loadfile('scripts/shadowself/control/arena_rewards.lua'))()
local box=ent('chest_mimic');local opened=true
box.replica.container={IsOpenedBy=function() return opened end,GetItems=function() return slots end,GetItemInSlot=function(_,i) return slots[i] end,
 MoveItemFromAllOfSlot=function(_,i) takes[#takes+1]=slots[i];bag[#bag+1]=slots[i];slots[i]=nil end,Close=function() opened=false end}
local rewardMoves=0;local state={player=p,context=c,arena={running=true,wave=11,bridge={},StopCombat=function() end,Say=function() end,
 encounters={Move=function() rewardMoves=rewardMoves+1 end}}}
local reward=Rewards(state,false)
for i=1,9 do now=now+.2;reward:Tick({box}) end
assert(#takes==3 and slots[1].prefab=='nightsword' and reward.visited['0:0'],'all routes take exactly staff/crown/seed and leave other items inside')
local mimic=ent('chest_mimic_revealed');reward.boxes={a=box,b=box,c=box,d=box};box.removed=true;reward.visited={};objects={}
now=now+1;reward:Tick({mimic})
assert(not state.failed and rewardMoves>0,'transformed reward boxes keep avoidance alive instead of stopping takeover beside attackers')
package.loaded[ak]=oldA
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
local mite=ent('cave_vent_mite',5);local segment=ent('worm_boss_segment');local wormState={player=p,route='default',seen={[mite]=false},context=c,
 arena={wave=11,bridge={},encounters={Move=function() end},StopCombat=function() end,Say=function() end},Cleared=function() return false end}
assert(Finish.Worm(wormState,{mite,segment})=='hold' and not wormState.target,'worm body danger preempts mite melee even with charged armor')
assert(Finish.Worm(wormState,{mite})=='fight' and wormState.target==mite and not wormState.reward,'clear space resumes ordinary mite melee without patrol or opening chests')
GetTime,TheWorld,TheSim=oldTime,oldWorld,oldSim
print('PASS: post-clear spore monitoring and disappearance, live-combat boundary, charged-bone stale-cane release, guarded swipe counterattack and next-windup dodge, early known-entry margin, logged late grazer scan')
