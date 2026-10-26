-- 真正动作模块的预演回调与主机分支；不发送真实网络数据。
package.loaded["shadowself/control/actions"]=nil
local oldTime=GetTime;local now=0;GetTime=function() return now end
local A=require("shadowself/control/actions")
local calls={}
SendRPCToServer=function(...) calls[#calls+1]={...} end
RPC={LeftClick="left",RightClick="right",StopControl="control",StopWalking="stop"}
CONTROL_PRIMARY=1;CONTROL_SECONDARY=2
local wanted={code=7,id="PICKUP"}
local act={action=wanted,rotation=0}
local pc={ismastersim=false,locomotor={}}
function pc:GetPlatformRelativePosition(x,z) return nil,x,z end
function pc:EncodeControlMods() return 0 end
function pc:DoAction(value) self.action=value end
local player={components={playercontroller=pc,playeractionpicker={
    GetLeftClickActions=function() return {act} end,GetRightClickActions=function() return {} end}}}
local target={GetPosition=function() return {x=1,z=2} end}
local allowed=true
assert(A.Scene(player,target,wanted,function() return allowed end))
assert(#calls==0 and pc.action.preview_cb,"client action waits for original preview callback")
pc.action.preview_cb();assert(#calls==1 and calls[1][1]=="left")
allowed=false;pc.action.preview_cb();assert(#calls==1,"revoked ownership blocks stale callback")
pc.ismastersim=true;act.preview_cb=nil
assert(A.Scene(player,target,wanted));assert(#calls==1,"host uses local controller without RPC")
-- Cookpot HARVEST does not depend on the mouse picker selecting it first.
pc.ismastersim=false
local oldbuffer=BufferedAction
local harvest={code=8,id="HARVEST"};ACTIONS={HARVEST=harvest}
BufferedAction=function(p,t,a) return {doer=p,target=t,action=a,rotation=0} end
local done=true
local pot={IsValid=function() return true end,HasTag=function(_,tag) return tag=="donecooking" and done end,GetPosition=target.GetPosition}
assert(not A.Scene(player,pot,harvest),"mouse picker has another preferred action")
local before=#calls
allowed=true;now=now+.5
assert(A.HarvestCooked(player,pot,function() return allowed end))
assert(pc.action.action==harvest and #calls==before,"explicit harvest still waits for native preview")
pc.action.preview_cb();assert(#calls==before+1 and calls[#calls][2]==harvest.code)
done=false;pc.action.preview_cb();assert(#calls==before+1,"empty pot invalidates stale harvest callback")
assert(not A.HarvestCooked(player,pot),"never harvest a pot still cooking or already empty")
done=true;pc.locomotor=nil;now=now+.5
assert(A.HarvestCooked(player,pot));assert(pc.action.non_preview_cb)
pc.action.non_preview_cb();assert(#calls==before+2,"harvest works with prediction disabled")
pc.locomotor={};pc.ismastersim=true
assert(A.HarvestCooked(player,pot) and #calls==before+2,"host uses native buffered harvest without client RPC")
BufferedAction=oldbuffer
pc.ismastersim=false;ACTIONS={WALKTO={code=99}}
function player:GetPosition() return {x=4,z=5} end
function player:ClearBufferedAction() self.cleared=true end
function pc:ClearActionHold() self.hold_cleared=true end
function pc.locomotor:Stop() end;function pc.locomotor:Clear() end
A.Stop(player)
assert(player.cleared and pc.hold_cleared and calls[#calls][1]=="left" and calls[#calls][2]==99,"stop clears queued movement with native click at own feet")
-- 制作完成必须等待背包同步，不能用提交动作或预测动画判定成功。
local inventory_count=0;local builds=0
package.loaded["shadowself/control/actions"]={Count=function() return inventory_count end}
package.loaded["shadowself/control/jobs"]=nil
STRINGS={NAMES={BOARDS="木板"}}
GetValidRecipe=function(name) return name=="boards" and {} or nil end
local maker={components={playercontroller={IsBusy=function() return false end}},replica={builder={
    KnowsRecipe=function() return true end,HasIngredients=function() return true end,
    MakeRecipeFromMenu=function() builds=builds+1 end}}}
local job=require("shadowself/control/jobs")(maker)
job:Set({kind="craft",target="木板"})
assert(job:Tick()=="running" and builds==1)
assert(job:Tick()=="running" and builds==1,"no false completion from client prediction")
inventory_count=1;assert(job:Tick()=="done","completion follows replicated inventory")
job:Cancel();assert(job.plan==nil and job.token==nil)
-- 复活时间轴与真正的100帧/172帧原版动画共用终点。
local owner={time=0,name="amulet_rebirth",length=100/30}
owner.AnimState={IsCurrentAnimation=function(_,name) return name==owner.name end,
    GetCurrentAnimationLength=function() return owner.length end,
    GetCurrentAnimationTime=function() return owner.time end}
local Clock=require("shadowself/rebirthclock")
local clock=Clock(owner,"amulet_rebirth")
owner.time=20/30
assert(math.abs(clock:Pose(clock:Progress())-90/30)<.001,"horizontal lift starts at native frame20, not 2.87 seconds late")
local last=-1
for frame=0,100 do
    owner.time=frame/30;local pose=clock:Pose(clock:Progress())
    assert(pose>=last and pose<=172/30+.0001);last=pose
end
owner.name="idle_loop";assert(clock:Progress()==1,"native animation ending ends local ceremony")
owner.name="wendy_resurrect";owner.length=172/30;owner.time=86/30
local w=Clock(owner,"wendy_resurrect")
assert(math.abs(w:Pose(w:Progress())-86/30)<.001,"original Wendy timeline remains aligned")
print("PASS: native action callbacks, revoked callback, authoritative crafting and synchronized rebirth timelines")

GetTime=oldTime
