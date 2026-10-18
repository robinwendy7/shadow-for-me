-- Real action bridge: direct native RPCs, not mocked batch implementation.
local previous=package.loaded["shadowself/control/actions"]
local saved_rpc,saved_send=RPC,SendRPCToServer
package.loaded["shadowself/control/actions"]=nil
local Actions=require("shadowself/control/actions")
RPC={MoveInvItemFromCountOfSlot="inventory",MoveItemFromCountOfSlot="container"}
local target={replica={container={IsOpenedBy=function() return true end}},IsValid=function() return true end}
local source={open=true,calls=0}
function source:IsOpenedBy() return self.open end
function source:MoveItemFromCountOfSlot(slot,dest,count) assert(dest==target and count==1);self.calls=self.calls+1 end
local inst={IsValid=function() return true end}
local p={components={playercontroller={ismastersim=false}}}
local calls={}
SendRPCToServer=function(...) calls[#calls+1]={...} end
local steps={{inventory=true,source=source,slot=2}}
for i=1,3 do steps[#steps+1]={source=source,inst=inst,slot=7} end
assert(Actions.TransferBatch(p,target,steps,function() return true end))
assert(#calls==4 and source.calls==0,"remote mode submits four native RPCs without classified preview")
assert(calls[1][1]=="inventory" and calls[1][2]==2 and calls[1][3]==target and calls[1][4]==1)
for i=2,4 do assert(calls[i][1]=="container" and calls[i][2]==7 and calls[i][3]==inst and calls[i][4]==target and calls[i][5]==1) end
p.components.playercontroller.ismastersim=true
assert(Actions.TransferBatch(p,target,steps) and source.calls==4 and #calls==4,"host uses native replica/component path without remote RPC")
source.open=false;assert(not Actions.TransferBatch(p,target,steps) and source.calls==4,"closed source rejects whole batch before any inventory move")
source.open=true;assert(not Actions.TransferBatch(p,target,steps,function() return false end) and source.calls==4,"revoked guard rejects batch")
steps[5]=steps[1];assert(not Actions.TransferBatch(p,target,steps),"hard cap matches four cooker slots")
if read_source then
    local src=read_source("networkclientrpc.lua")
    assert(src:find("MoveInvItemFromCountOfSlot = function(player, slot, destcontainer, count)",1,true))
    assert(src:find("MoveItemFromCountOfSlot = function(player, slot, srccontainer, destcontainer, count)",1,true))
end
package.loaded["shadowself/control/actions"]=previous;RPC=saved_rpc;SendRPCToServer=saved_send
print("PASS: real batch bridge sends four exact native RPCs in one call; host path, closed source, revoked guard and four-slot cap")
