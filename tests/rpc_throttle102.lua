local old={time=GetTime,player=ThePlayer,rpc=RPC,actions=ACTIONS,send=SendRPCToServer,buffer=BufferedAction}
local now=0;GetTime=function() return now end
local calls={};SendRPCToServer=function(...) calls[#calls+1]={...} end
local originalSender=SendRPCToServer
RPC={LeftClick=1,RightClick=2,StopControl=3,StopWalking=4,PredictWalking=5,
 MoveInvItemFromCountOfSlot=6,MoveItemFromCountOfSlot=7}
ACTIONS={WALKTO={id='WALKTO',code=10},ATTACK={id='ATTACK',code=11},EQUIP={id='EQUIP',code=12},PICKUP={id='PICKUP',code=13}}
local pc={ismastersim=false,IsBusy=function() return false end,CanLocomote=function() return false end,
 GetPlatformRelativePosition=function(_,x,z) return nil,x,z end,EncodeControlMods=function() return 0 end}
local p={components={playercontroller=pc,playeractionpicker={}},replica={inventory={GetActiveItem=function() end,GetEquippedItem=function() end}},
 GetPosition=function() return Vector3(0,0,0) end,HasTag=function() return false end,IsValid=function() return true end}
pc.inst=p
BufferedAction=function(_,target,action,item,pos) return {target=target,action=action,invobject=item,pos=pos,rotation=0} end
pc.DoAction=function(_,a) pc.last=a;if a.non_preview_cb then a.non_preview_cb() end end
local A=assert(loadfile('scripts/shadowself/control/actions.lua'))()
-- Actual wire sends at 60Hz; no global RPC replacement.
for frame=0,119 do now=frame/60;A.Move(p,Vector3(frame,0,0)) end
assert(#calls==20,'changing movement goals at 60Hz generate only ten ordinary movement RPCs per second')
calls={};now=0
for frame=0,119 do now=frame/60;A.Move(p,Vector3(30,0,0)) end
assert(#calls==8,'the same movement goal refreshes at most four times per second')
local target={IsValid=function() return true end,GetPosition=function() return Vector3(2,0,0) end}
calls={};now=0
for frame=0,119 do now=frame/60;A.Attack(p,target) end
assert(#calls==14,'direct attack requests are limited before DoAction and network preview')
calls={};now=0
for frame=0,119 do now=frame/60;A.Stop(p) end
assert(#calls<=40 and #calls%4==0,'duplicate stops are coalesced while each accepted cancellation keeps its complete four-RPC bundle')
-- A new action can be cancelled immediately, but Stop cannot reset the movement budget.
calls={};now=10;assert(A.Move(p,Vector3(1,0,0))~=false);A.Stop(p)
local after=#calls;assert(after==5)
assert(A.Move(p,Vector3(2,0,0))==false);A.Stop(p);assert(#calls==after)
now=10.1;assert(A.Move(p,Vector3(2,0,0))~=false);A.Stop(p)
assert(#calls==after+5,'new admitted movement receives immediate cancellation even inside the old stop window')
-- Preview callbacks are one-shot, and revocation still wins over any quota.
calls={};now=20;local allowed=true
p.components.playeractionpicker.GetLeftClickActions=function() return {{action=ACTIONS.PICKUP,rotation=0}} end
p.components.playeractionpicker.GetRightClickActions=function() return {} end
pc.DoAction=function(_,a) pc.last=a end
assert(A.Scene(p,target,ACTIONS.PICKUP,function() return allowed end))
pc.last.non_preview_cb();pc.last.non_preview_cb();assert(#calls==1,'a duplicate preview cannot send the same scene action twice')
now=20.01;assert(not A.Scene(p,target,ACTIONS.PICKUP),'caller receives a real transient rejection rather than fictitious success')
now=20.3;allowed=false;assert(not A.Scene(p,target,ACTIONS.PICKUP,function() return allowed end) and #calls==1)
-- Inventory transfers reserve the whole logical batch; never drop its second packet.
local box={IsValid=function() return true end,replica={container={IsOpenedBy=function() return true end}}}
local steps={{inventory=true,slot=1},{inventory=true,slot=2}}
calls={};now=30;assert(A.TransferBatch(p,box,steps))
assert(not A.TransferBatch(p,box,steps) and #calls==2,'all-or-nothing repeat batch admission')
now=30.4;assert(A.TransferBatch(p,box,steps) and #calls==4)
-- Run the actual migrated engine's movement/attack entry points.
local src=assert(io.open('scripts/shadowself/native/engine/HitAndRun.lua')):read('*a')
local start=assert(src:find('do --走向和攻击函数',1,true));local finish=assert(src:find('\ndo --功能性函数',start,true))
local H={};local env=setmetatable({HitAndRun=H,ThePlayer=p,INV_util={GetActiveItem=function() end},
 SendRPCToServer=SendRPCToServer},{__index=_G})
local f=assert(loadstring(src:sub(start,finish-1)));setfenv(f,env);f()
pc.IsBusy=function() return true end;calls={};now=0
for frame=0,119 do now=frame/60;H:DoPredictWalk(frame,0) end
assert(#calls==20 and calls[1][1]==RPC.PredictWalking and calls[1][5]==true,
 'busy-safe native dodge is rate limited without losing prediction-session start')
H:StopPredictWalk();assert(calls[#calls-1][9]==true and calls[#calls][1]==RPC.StopWalking,'prediction session end is never partially dropped')
pc.IsBusy=function() return false end;calls={};now=0
for frame=0,119 do now=frame/60;H:CloseAndAttack(target) end
assert(#calls==14,'native attack and direct attack share the same player admission limiter')
assert(SendRPCToServer==originalSender,'manual inputs and other mods retain their original global sender')
GetTime,ThePlayer,RPC,ACTIONS,SendRPCToServer,BufferedAction=old.time,old.player,old.rpc,old.actions,old.send,old.buffer
print('PASS: 60Hz real RPC load reduced, duplicate goals/stops/callbacks coalesced, immediate cancellation, no Stop quota bypass, atomic transfers/prediction and shared native attack limit')
