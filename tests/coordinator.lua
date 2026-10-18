-- 使用合并的原 AI Player Pack/Choose；3014方法用可计数桩。
package.loaded["shadowself/control/actions"]=nil;package.loaded["shadowself/control/coordinator"]=nil
local Co=require("shadowself/control/coordinator")
local now=1000;GetTime=function() return now end
local moves=0;POS_util={GoToPoint=function() moves=moves+1 end}
local function pos(x,z)
    local v={x=x,y=0,z=z};function v:DistSq(o) return (self.x-o.x)^2+(self.z-o.z)^2 end
    function v:Get() return self.x,self.y,self.z end;return v
end
Vector3=function(x,y,z) return pos(x,z) end
local player={replica={},components={}}
function player:GetPosition() return pos(0,0) end
function player:HasTag() return false end
function player:IsValid() return true end
function player:GetPhysicsRadius() return .5 end
function player:ClearBufferedAction() end
player.replica.inventory={GetItems=function() return {} end,GetEquips=function() return {} end,GetEquippedItem=function() end,GetOverflowContainer=function() end}
player.replica.combat={GetAttackRangeWithWeapon=function() return 2 end}
player.components.playercontroller={ismastersim=true,IsEnabled=function() return true end,IsBusy=function() return false end}
player.components.playeractionpicker={GetSceneActions=function(_,e) return {{action=ACTIONS.ATTACK,rotation=0}} end}
local enemies={}
for i,point in ipairs({pos(5,0),pos(5,8),pos(11,0),pos(11,8)}) do
    local e={GUID=900+i,prefab="spider",replica={combat={GetAttackRangeWithWeapon=function() return 2 end}}}
    function e:GetPosition() return point end;function e:HasTag() return false end
    function e:IsValid() return true end;function e:GetPhysicsRadius() return .5 end
    enemies[i]=e
end
TheWorld={state={isnight=false},Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
TheSim={FindEntities=function() return enemies end}
local bridge={player=player,allowed=function() return true end,wrappers={PreTheLoop={old=function() end}}}
bridge.h={ent=enemies[1],GetSpeed=function() return 6 end,IsAttackPre=function() return nil end}
local c=Co(bridge,{kind="fight"});c.gear.Swap=function() return true end
c:Pulse();assert(c.tactics.pack and c.tactics.pack.stage=="gather" and moves>0,"original Pack spreads then orbits a dispersed group")
local native=0
bridge.h.DoDodge=function() native=native+1 end
bridge.h.IsAttackPre=function(_,e) if e==enemies[2] then return {dist=8} end end
now=now+.2;c:Pulse()
assert(c.h.ent~=enemies[2],"a distant off-target windup does not steal a reachable attack window")
enemies[2].GetPosition=function() return pos(1,0) end
now=now+.2;c:Pulse()
assert(c.h.ent==enemies[2],"an off-target windup becomes the native dodge target")
assert(c.tactics.pack.stage=="evade","original Pack enters evade on observed windup")
enemies[2].GetPosition=function() return pos(5,8) end
now=now+.2;bridge.h.IsAttackPre=function() end;c:Pulse()
assert(c.tactics.pack.stage=="punish","original Pack returns to attacks after windup")
assert(c:PermitAttack(),"safe group recovery returns attack permission")
c:Stop()
-- 音效在镜头焦点发出，脱离特效的地下坐标与距离。
local sound,volume
TheFocalPoint={SoundEmitter={PlaySound=function(_,s,_,v) sound=s;volume=v end}}
package.loaded["shadowself/effects"]=nil
local Effects=require("shadowself/effects")
local fx=Effects();fx.Spawn=function() return {SoundEmitter={PlaySound=function() error("positional emitter should not be used") end}} end
fx:Burst(100,-10,100,false)
assert(sound=="dontstarve/maxwell/shadowmax_despawn" and volume==1,"shadow sound uses focal emitter at full volume")
TheFocalPoint=nil
print("PASS: original AI group gather/evade/punish, off-target danger and focal shadow sound")


-- 确认协调器钩子只门控3014原动作，不调用旧 AI 攻击循环。
local Bridge=require("shadowself/control/combat")
local attacks,dodges,stops=0,0,0
local pre=function() end
local attack=function() attacks=attacks+1 end
local dodge=function() dodges=dodges+1 end
local walk=function() end
HitAndRun={WalkTo=walk,GetAttackTargets=function() end,IsAttackPre=function() end,PreTheLoop=pre,
    OnKeyFrame=attack,OnNormalFrame=attack,CloseAndAttack=attack,ShouldAtkWhenDodging=function() return true end,
    DoDodge=dodge,StartHitAndRun=function() TUNING.Cheatthread={id=888,SetList=function() end} end,
    StopHitAndRun=function() stops=stops+1;TUNING.Cheatthread=nil end}
MOD_util={};ENT_util={};TUNING.Cheatthread=nil
player.replica.combat.IsAlly=function() return false end
local observer,observer_cancelled
player.DoPeriodicTask=function(_,interval,fn)
 assert(interval==FRAMES);observer=fn
 return {Cancel=function() observer_cancelled=true end}
end
local equip_callback,equip_removed
player.ListenForEvent=function(_,name,fn) if name=="EquipItem" then equip_callback=fn end end
player.RemoveEventCallback=function(_,name,fn) if name=="EquipItem" then assert(fn==equip_callback);equip_removed=true end end
local original_move=POS_util.GoToPoint
local bridge2=Bridge(player)
assert(bridge2:Start({kind="fight",coordinated=true,target="spider"},function() return true end))
assert(HitAndRun.WalkTo==walk,"native WalkTo remains untouched during possession")
local scan=TheSim.FindEntities
local ambient={};TheSim.FindEntities=function() return {ambient} end
local allowed=bridge2.allowed;bridge2.allowed=function(e) return e==enemies[1] end
assert(not bridge2:Finished());now=now+1.1;assert(bridge2:Finished(),"ambient mobs do not hold combat possession open")
now=now+.3;TheSim.FindEntities=function() return {enemies[1]} end
assert(not bridge2:Finished(),"a new aggressor resets the clear timer")
TheSim.FindEntities=scan;bridge2.allowed=allowed
assert(not observer,"ordinary combat has no auxiliary hit/equipment observer")
local roles={};bridge2.coordinator.gear.Swap=function(_,role) roles[#roles+1]=role;return true end
bridge2.coordinator.gear.Weapon=function() return nil end
bridge2.coordinator.Scan=function() error("ordinary fight must not use custom threat scanning") end
bridge2.coordinator.PermitAttack=function() error("ordinary native attack cannot enter custom gate") end
local rawmove=original_move
assert(HitAndRun.DoDodge==dodge and HitAndRun.WalkTo==walk and POS_util.GoToPoint==rawmove,"native dodge/movement function identities remain intact")
HitAndRun.ent=enemies[1]
for i=1,60 do
 bridge2.coordinator.blocked=true -- even an old stale flag cannot block ordinary attacks
 HitAndRun:PreTheLoop();HitAndRun:OnKeyFrame();HitAndRun:OnNormalFrame();HitAndRun:DoDodge({})
end
assert(attacks==120 and dodges==60 and #roles==0,"ordinary native loop is never held by shadow gates or travel equipment")
assert(POS_util.GoToPoint==rawmove,"no global position filter installed")
assert(equip_callback,"owned native dodge EquipItem listener installed")
bridge2.coordinator.gear.Weapon=function() return {} end
equip_callback(player,{type="walk_hands"});assert(roles[#roles]=="move","actual bridge event enters cane role")
bridge2.coordinator.secondary.pending=enemies[1]
equip_callback(player,{type="fight"});assert(bridge2.coordinator.travel.finish_deferred and roles[#roles]=="move","continuous other threat does not switch back and forth between adjacent dodges")
HitAndRun:CloseAndAttack();assert(roles[#roles]=="attack","cleared secondary pending restores weapon through the original follow-up")
local n=#roles;equip_callback(player,{type="fight"});assert(#roles==n,"ordinary fight event does not spam equips")
equip_callback(player,{type="walk_hands"});bridge2.coordinator.beequeen={travelling=true}
equip_callback(player,{type="fight"});assert(bridge2.coordinator.travel.dodging and roles[#roles]=="move","queen lure retains cane across incidental native dodges")
bridge2.coordinator.beequeen=nil;bridge2.coordinator.travel:EndDodge();assert(roles[#roles]=="attack","queen output can explicitly restore weapon")
local oldangle=ENT_util.GetAngle;ENT_util.GetAngle=function() return 180 end
for _,prefab in ipairs({"rook","rook_nightmare"}) do
    local foe={prefab=prefab,AnimState={IsCurrentAnimation=function(_,a) return a==(prefab=="daywalker" and "run_loop" or "atk") end},Transform={GetRotation=function() return 0 end}}
    foe.GetPosition=function() local p=player:GetPosition();return Vector3(p.x-1,0,p.z) end;foe.GetPhysicsRadius=function() return .5 end
    local data=HitAndRun:IsAttackPre(foe)
    assert(data and data.point=="player" and data.angle==math.pi/2 and data.dist==4,"charge overrides are lateral, never linear 8-unit retreat")
    assert(data.breakdodgefn(foe),"when charge has passed, return to the native attack process")
end
ENT_util.GetAngle=oldangle
bridge2:Stop();assert(equip_removed,"owned EquipItem listener removed on Stop");player.ListenForEvent=nil;player.RemoveEventCallback=nil;player.DoPeriodicTask=nil;assert(stops==1 and HitAndRun.PreTheLoop==pre and HitAndRun.OnKeyFrame==attack and HitAndRun.DoDodge==dodge,"stop restores native hooks")
-- 任务防卫暂停不重复发送已经发出的制作请求。
package.loaded["shadowself/control/jobs"]=nil
local Jobs=require("shadowself/control/jobs")
local job=Jobs(player);job:Set({kind="craft",target="木板"})
local defending=true
job.guard={Tick=function() return defending and "running" or "idle" end,OwnsCombat=function() return defending end,Cancel=function() end}
local beforetoken=job.token;job.sent=now;job.before=0
assert(job:Tick()=="running" and job.token~=beforetoken and job:OwnsCombat(),"guard revokes pending work callback and owns thread")
defending=false
local requested=0;AllRecipes.boards={name="boards"};GetValidRecipe=function() return AllRecipes.boards end
player.replica.builder={KnowsRecipe=function() return true end,HasIngredients=function() return true end,MakeRecipeFromMenu=function() requested=requested+1 end}
assert(job:Tick()=="running" and requested==0 and job.sent~=nil,"resume preserves sent consumptive task instead of duplicating it")
job:Cancel()
print("PASS: native combat hooks restored; work defense invalidates callbacks and preserves craft request")
