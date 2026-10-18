local savedA=package.loaded["shadowself/control/actions"]
local savedN=require("shadowself/native").context
local now=0;GetTime=function() return now end;FRAMES=1/30
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"};ACTIONS={ATTACK={},EQUIP={},PICKUP={},CHOP={},PLAY={}}
TUNING={TOADSTOOL_SPOREBOMB_TIMER=3.5,TOADSTOOL_SPORECLOUD_RADIUS=3.5,TENTACLE_STOPATTACK_DIST=4}
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=0
local function entity(name,x,z)
 guid=guid+1;local e={prefab=name,GUID=guid,pos=Vector3(x or 0,0,z or 0),frame=0,tags={},replica={},components={},entity={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};e.entity.GetParent=function() return e.parent end;return e
end
local p=entity("wilson",2,0);local held={};local items={};local commands={};local entities={}
p.replica.inventory={GetEquippedItem=function(_,slot) return held[slot] end,DropItemFromInvTile=function(_,item) commands[#commands+1]={drop=item} end}
p.replica.combat={};p.components.playercontroller={IsBusy=function() return false end}
ThePlayer=p;TheWorld={state={}};TheSim={FindEntities=function() return entities end}
local A={Items=function() return items end,Self=function(_,item,action) held.hands=item;commands[#commands+1]={item=item,action=action};return true end,
 Attack=function(_,target) commands[#commands+1]={target=target,action=ACTIONS.ATTACK};return true end,
 Scene=function(_,target,action) commands[#commands+1]={target=target,action=action};return true end}
package.loaded["shadowself/control/actions"]=A
require("shadowself/native").context={ENT_util={GetAnimation=function(_,e) return e.anim end}}
local pauses=0;local stop=0
local c={player=p,enemies={},observed={},hazards={},snapshot={},gear={},h={IsHitingFrame=function() return p.frame>=8 end},
 bridge={PauseAttack=function() pauses=pauses+1 end,allowed=function() return true end},
 actions={SafePoint=function() return true end,Stop=function() stop=stop+1 end},
 travel={BeginDodge=function() end,EndDodge=function() end},Move=function(self,q,label) self.moved=q;self.status=label end}
c.mechanisms={Equip=function(_,item) held.hands=item;return true end}
package.loaded["shadowself/control/bosses"]=nil
local Boss=require("shadowself/control/bosses");local b=Boss(c);c.bosses=b
c.Latency=function() return .1 end;c.Speed=function() return 6 end



local Debug=require("shadowself/control/queendebug")
local savedPrint=print;local lines={};print=function(line) lines[#lines+1]=line end
local queen=entity("beequeen");queen.anim="command2"
local guard=entity("beeguard",6,0);guard.build="bee_guard_puffy_build";guard.anim="run_loop";guard.AnimState.GetBuild=function() return guard.build end
c.h.ent=queen;c.hazards={};c.enemies={guard};c.bridge.OwnsThread=function() return true end
local health=1;p.replica.health={GetPercent=function() return health end}
local q={c=c,queen=queen,phase=3,stage="dash_pull",dash_cycle={mode="pull"},debug_bees={guard}}
c.beequeen=q;now=100
Debug.Configure(true);Debug.Start(c,queen);Debug.Sample(q)
local function count(event)
 local n=0;for _,line in ipairs(lines) do if line:find('event="'..event..'"',1,true) then n=n+1 end end;return n
end
assert(count("fight_start")==1 and count("decision")==1 and count("guards")==1 and count("snapshot")==1 and count("logger_error")==0)
local size=#lines;for i=1,40 do now=100+i*.01;Debug.Sample(q) end
assert(#lines==size,"unchanged per-frame sampling must not flood client log")
now=100.7;health=.8;Debug.Sample(q);assert(count("hurt")==1,"health drop is captured before two-second heartbeat")
Debug.Performed(c,{action=ACTIONS.ATTACK,target=queen})
Debug.Performed(c,{action={action=ACTIONS.ATTACK,target=queen}})
assert(count("attack_performed")==2,"host execution-event shapes are distinguished from dispatch attempts")
local helditem=entity("icestaff");Debug.Equip(c,"request",helditem,"attack")
Debug.Equip(c,"ack",helditem,"attack",{latency=.3})
assert(count("equip_request")==1 and count("equip_ack")==1)
Debug.Block(c,"select",guard);Debug.Block(c,"CloseAndAttack",guard);Debug.Block(c,"CloseAndAttack",guard)
assert(count("attack_block")==1,"identical blocked attacks are throttled; select veto is counted without per-bee spam")
now=100.8;Debug.Move(c,Vector3(15,0,0),"蜂后 · 测试路线")
local prior=q.stage;local priorpos=p.pos;now=102.1;Debug.Sample(q)
assert(q.stage==prior and p.pos==priorpos,"logger cannot alter AI phase or player position")
local joined=table.concat(lines,"\n")
assert(joined:find('stalled=true',1,true) and joined:find('queen_in_scan=false',1,true),"snapshot explains no movement and retained off-scan queen")
guard.build="bee_guard_build";guard.anim="walk_loop";now=102.4;Debug.Sample(q);assert(count("guards")==2)
local before=#lines;for i=1,100 do Debug.Event(c,"spam_test",{index=i}) end
assert(#lines-before<=24 and c._queen_debug.dropped>0,"event burst has a hard print budget")
Debug.End(c,"test_done");assert(count("fight_end")==1 and not c._queen_debug)
Debug.Configure(false);size=#lines;Debug.Start(c,queen);Debug.Event(c,"disabled_test",{});Debug.Sample(q)
assert(#lines==size and not c._queen_debug,"disabled logging produces no combat entries")
if write_debug_fixture then write_debug_fixture("OFFLINE TEST FIXTURE - not live gameplay\nLoading mod: Cry for me (offline fixture) Version:0.12.18\n"..table.concat(lines,"\n")) end
print=savedPrint;package.loaded["shadowself/control/actions"]=savedA;require("shadowself/native").context=savedN
print("PASS: QueenDebug lifecycle, .2s read-only sampling/2s heartbeat, health/equip/veto records, no per-frame flood, print budget, explicit disable and offline fixture")
