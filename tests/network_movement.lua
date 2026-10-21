-- 联机实际移动入口回归：原版DoAction busy拒绝之前必须发出合法预测会话。
local oldPlayer,oldRPC,oldActions,oldBuffered=ThePlayer,RPC,ACTIONS,BufferedAction
local calls={};local busy=true;local attempted=0;local platform={}
local pc={ismastersim=false,locomotor={}}
function pc:CanLocomote() return true end;function pc:IsBusy() return busy end
function pc:GetPlatformRelativePosition(x,z) return platform,x-10,z-20 end
function pc:EncodeControlMods() return 0 end
function pc:DoAction(act) attempted=attempted+1;if self:IsBusy() then return end;if act.preview_cb then act.preview_cb() end end
ThePlayer={components={playercontroller=pc},GetPosition=function() return Vector3(0,0,0) end}
RPC={PredictWalking=101,StopWalking=102,LeftClick=103};ACTIONS={WALKTO={code=1},ATTACK={code=2}}
BufferedAction=function() return {} end
local H={};local pos={CalculateAimPos=function(_,a,b,angle,d) return Vector3(a.x+math.cos(angle)*d,0,a.z+math.sin(angle)*d) end}
local env=setmetatable({HitAndRun=H,POS_util=pos,ThePlayer=ThePlayer,RPC=RPC,ACTIONS=ACTIONS,BufferedAction=BufferedAction,SendRPCToServer=function(...) calls[#calls+1]={...} end},{__index=_G})
local src=assert(io.open("scripts/shadowself/native/engine/HitAndRun.lua","r")):read("*a")
local a=assert(src:find("do --走向和攻击函数",1,true));local z=assert(src:find("\ndo --功能性函数",a,true))
local f=assert(loadstring(src:sub(a,z-1)));setfenv(f,env);f()
local F=assert(loadfile("scripts/shadowself/native/utils/POS_util.lua"));setfenv(F,env);local P=F()
P:GoToPoint(12,24)
assert(attempted==0 and #calls==1,"busy attack cannot swallow the move before it reaches the server")
local msg=calls[1];assert(msg[1]==101 and msg[2]==2 and msg[3]==4 and msg[4]==false and msg[5]==true and msg[6]==platform and msg[7]==true,"correct platform-relative PredictWalking with isstart=true")
H:StopPredictWalk();assert(calls[2][1]==101 and calls[2][9]==true and calls[3][1]==102 and not H.shadowself_predicting,"prediction is explicitly stopped before attacks/cleanup")
-- Ordinary recovery must retain the original input sequence, not emergency prediction.
busy=false;ThePlayer.replica={inventory={GetActiveItem=function() end}}
H.PC=pc;H.ppos=Vector3(0,0,0);H.pos=Vector3(1,0,0)
H:WalkTo(Vector3(0,0,0),Vector3(1,0,0),-.3)
assert(attempted==1 and #calls==3,"ordinary locomotor recovery uses original DoAction only")
H:_PredictWalk(Vector3(-.3,0,0))
assert(#calls==6 and calls[4][1]==101 and calls[4][2]==-.3 and calls[5][1]==103 and calls[6][1]==101,
    "original PredictWalking / LeftClick WALKTO / PredictWalking order")
assert(not H.shadowself_predicting,"ordinary recovery must not start emergency prediction sessions")
H:PredictWalk(Vector3(0,0,0),Vector3(1,0,0),{GetPosition=function() return Vector3(1,0,0) end})
assert(attempted==2 and #calls==6,"at reach boundary restore original local recovery instead of extra outward .15 step")
local actual=read_source("components/playercontroller.lua")
assert(actual:find('elseif self:IsBusy() then',1,true) and actual:find('if isstart then',1,true) and actual:find('RestartPredictMoveTimer()',1,true))
ThePlayer,RPC,ACTIONS,BufferedAction=oldPlayer,oldRPC,oldActions,oldBuffered
print("PASS: emergency movement remains busy-safe; ordinary recovery restores original action sequence and boundary behavior")
