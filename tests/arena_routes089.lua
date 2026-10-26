local oldTime,oldWorld,oldSim=GetTime,TheWorld,TheSim
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
TheSim={FindEntities=function() return {} end}
local function ent(name,x,z)
 local e={prefab=name,GUID=89000,pos=Vector3(x or 0,0,z or 0),anim='idle',frame=0,replica={},components={}}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=ent('wilson',3);local bishop=ent('bishop');local knight=ent('knight',3,1.5);knight.GUID=89001
local body
p.replica.inventory={GetEquippedItem=function(_,slot) if slot==EQUIPSLOTS.BODY then return body end end}
p.components.playercontroller={IsBusy=function() return false end}
local stops=0;local c={player=p,enemies={bishop,knight},hazards={},observed={},h={ent=bishop},
 actions={SafePoint=function() return true end,Stop=function() stops=stops+1 end},gear={AttackRange=function() return 2 end},
 bridge={PauseAttack=function() end,allowed=function() return true end},travel={BeginDodge=function() end,EndDodge=function() end}}
c.plan={arena=true,arena_wave=function() return 3 end,arena_remaining=function() return c.enemies end,
 arena_clockwork={target=bishop,Live=function() return true end}};c.bridge.plan=c.plan
function c:Move(q) self.moved=q end
local Boss=require('shadowself/control/bosses');local b=Boss(c);c.bosses=b
bishop.anim='atk2_pre';local data=b.routes:Bishop(bishop,nil);local q=data:fn()
assert(q and q.z<0,'bishop priority still routes around the knight body instead of walking into its occupied side')
for i=0,20 do
 local v=Vector3(p.pos.x+(q.x-p.pos.x)*i/20,0,p.pos.z+(q.z-p.pos.z)*i/20)
 assert(v:DistSq(knight.pos)>1.1^2,'complete dodge segment clears combined body radii')
end
local rook=ent('rook');rook.anim='atk';knight.pos=Vector3(0,0,-15);c.enemies={rook,knight};c.plan.arena_clockwork=nil
c.h.ent=rook;p.pos=Vector3(0,0,4);local state={}
local Follow=require('shadowself/control/arena_rook')
now=1;assert(Follow(c,rook,state,true))
now=1.4;q=Follow(c,rook,state,true);assert(state.wall_wait and q:DistSq(p.pos)==0,'stationary charging rook allows a stable safe-side wait')
b.rooks[rook]=state
assert(b:Rook(rook)=='support' and b:Rook(rook)=='support' and stops==1,'wall wait stops once and does not repeatedly issue short movement legs')
knight.pos=Vector3(0,0,4.5);knight.anim='atk'
q=Follow(c,rook,state,true);assert(not state.wall_wait,'new nearby knight danger immediately releases wall wait')
knight.pos=Vector3(0,0,-15);rook.pos=Vector3(1,0,0);now=1.5
q=Follow(c,rook,state,true);assert(not state.wall_wait,'real resumed charge motion restores following')
local Windows=require('shadowself/control/arena_attackwindows')
local slurper=ent('slurper');slurper.anim='atk';p.pos=Vector3(2,0,0);c.enemies={slurper};c.plan.arena_wave=function() return 5 end
data=Windows.Dodge(c,slurper,false);q=data:fn()
assert(data.noattack and data.update and q.z>=3.2,'rolling slurper uses lateral separation and refreshes movement')
slurper.frame=31;assert(Windows.Block(c,slurper) and not data.breakdodgefn(),'damage frame passing alone cannot end the moving attack state')
slurper.anim='idle';assert(not Windows.Block(c,slurper) and data.breakdodgefn())
slurper.anim='headslurp';slurper.frame=24;assert(Windows.Block(c,slurper),'head pounce has its own complete state window')
local calls=0;b.snailpack={Tick=function() calls=calls+1;return 'move' end}
assert(b:Tick(slurper)=='attack' and calls==0,'an active pounce preempts the pack perimeter move through the real Boss entry')
local dragon=ent('dragonfly');dragon.anim='atk';dragon.frame=16;c.enemies={dragon};c.plan.arena_wave=function() return 10 end
assert(b:Tick(dragon)=='attack' and Windows.Block(c,dragon),'swipe preempts return-to-center and remains blocked after old frame15 cutoff')
data=Windows.Dodge(c,dragon,{dist=8});assert(data.dist==8 and data.noattack,'existing longer enraged escape distance is preserved')
dragon.anim='idle';assert(not Windows.Block(c,dragon))
c.plan.arena_wave=function() return 4 end;slurper.anim='atk';assert(Windows.Block(c,slurper),'slurper windup safety applies to other arena waves too')
c.plan.arena=false;assert(not Windows.Block(c,slurper),'ordinary world remains unchanged');c.plan.arena=true
-- Inward approach blocked by the pig must still find a tangent leg around the SAME junk center.
local J=require('shadowself/control/arena_junkroute');local pig=ent('daywalker2',3.5,0);pig.GUID=89002
p.pos=Vector3(8,0,0);local s={player=p,boss=pig,junk_radius=3.6,context={hazards={}}}
q=J.Point(s,Vector3(0,0,0));assert(q and q.z~=0,'blocked inward approach takes a tangential center-anchored leg')
p.pos=Vector3(4.4,0,0);pig.pos=Vector3(4.4,0,4);pig.anim='atk_object';now=2
q=J.Point(s,Vector3(0,0,0));assert(q and q:DistSq(pig.pos)>p.pos:DistSq(pig.pos),'active 4.5-radius swing chooses the direction increasing separation')
assert(q:DistSq(Vector3(0,0,0))<6^2,'escape remains around the central junk rather than arena perimeter')
-- Carried food with no safe eating window cannot suppress a charged bone-shield counterattack forever.
body=ent('armorskeleton');body.replica.inventoryitem={classified={percentused={value=function() return 50 end}}}
body.components.cooldown={GetTimeToCharged=function() return 0 end}
c.plan.arena_wave=function() return 11 end;c.enemies={pig}
local Stage=assert(loadfile('scripts/shadowself/control/arena_stage11.lua'))()
local cancelled,ticks=0,0
local a={enemies={pig},bridge={},encounters={},StopCombat=function() end,
 healing={Health=function() return 50,150 end,Safe=function() return false end,Tick=function() end}}
local stage=setmetatable({player=p,context=c,arena=a,boss=pig,route='lunar',recovering=true,food={
 Available=function() return true end,CancelPickup=function() cancelled=cancelled+1 end,Tick=function() ticks=ticks+1 end},
 Cleared=function() return true end},{__index=Stage})
assert(not stage:Recovery() and not stage.recovering and cancelled==1 and ticks==0,'charged armor plus unsafe food yields back to boss combat')
body.components.cooldown.GetTimeToCharged=function() return 2 end
assert(stage:Recovery() and ticks==1,'uncharged armor retains actual recovery processing')
local rk='shadowself/control/arena_late_runtime';local oldR=package.loaded[rk];local resets=0
package.loaded[rk]={Live=function(e) return e~=nil end,Health=function() return 500 end,Equip=function() return true end,
 Hits=function() return 4 end,ResetHits=function() resets=resets+1 end,Phase=function(v,phase) v.phase=phase end}
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
body.components.cooldown.GetTimeToCharged=function() return 0 end
stage.phase='pig_orbit';stage.orbit_until=now+6
assert(Finish.Pig(stage,{pig})=='fight' and stage.target==pig and not stage.orbit_until and resets==1,
 'verified charged bone shield immediately re-enters counterattack even during old orbit hold')
package.loaded[rk]=oldR;GetTime,TheWorld,TheSim=oldTime,oldWorld,oldSim
print('PASS: bishop body-safe dodge, stationary wall-charge hold and danger release, rolling/pouncing slurper state and dispatch priority, dragonfly full swipe, tangential junk approach and swing separation, charged-pig counterattack over unsafe-food recovery')
