local keys={'shadowself/control/actions','shadowself/control/arena_goats'};local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k] end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),replica={}}
 function e:IsValid() return true end;function e:HasTag() return false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=ent('wilson');local staff=ent('staff_tornado');local cane=ent('cane');local sword=ent('hambat')
local hand=cane;local busy=false;local equips,casts,releases=0,0,0
p.replica.inventory={GetEquippedItem=function() return hand end};p.components={playercontroller={IsBusy=function() return busy end}}
package.loaded['shadowself/control/actions']={Items=function() return {staff,cane,sword} end,Stop=function() end,CastStaff=function(_,item,target,guard)
 assert(hand==staff and item==staff and guard());casts=casts+1;return true end}
package.loaded['shadowself/control/arena_goats']=nil
local c={player=p,bridge={PauseAttack=function() end},gear={forced_weapon=sword},travel={},mechanisms={Equip=function(_,item) assert(item==staff);equips=equips+1 end}}
local owner={c=c,Target=function() end,Release=function() releases=releases+1 end,Move=function() return 'move' end,Away=function() return 'move' end}
local wind=require('shadowself/control/arena_goats')(owner);local goat=ent('lightninggoat',8)
assert(wind:Tick({goat})=='support' and casts==0 and equips==1 and c.gear.forced_weapon==staff,'held cane requires staff equip ack before cast')
now=.1;wind:Tick({goat});assert(casts==0,'requested equip is not actual hand confirmation')
hand=staff;busy=true;now=.2;wind:Tick({goat});assert(casts==0,'equip animation busy cannot count as accepted cast')
busy=false;now=.3;wind:Tick({goat})
assert(casts==1 and releases==0 and c.gear.forced_weapon==staff,'cast cannot call travel release that restores ordinary weapon')
wind:Stop();assert(c.gear.forced_weapon==sword and not c.arena_wind,'leaving wind tactic restores previous forced weapon')
-- 真正右键施法入口：预演时不发RPC，回调再次核对手持，覆盖主机/两种移动预测。
local oldRPC,oldSend=RPC,SendRPCToServer;local rpcCount=0
RPC={RightClick=164};SendRPCToServer=function(...) local args={...};assert(args[1]==164 and args[5]==goat);rpcCount=rpcCount+1 end
local savedSpell=ACTIONS.CASTSPELL;local action=savedSpell or {code=164};ACTIONS.CASTSPELL=action
local pc=p.components.playercontroller
pc.EncodeControlMods=function() return 0 end;pc.GetPlatformRelativePosition=function(_,x,z) return nil,x,z end
pc.DoAction=function(_,act) pc.act=act end
p.components.playeractionpicker={GetUseItemActions=function(_,target,item,right)
 assert(target==goat and item==staff and right);return {{action=action,invobject=staff,target=goat,rotation=0}} end}
local A=assert(loadfile('scripts/shadowself/control/actions.lua'))()
pc.ismastersim=false;pc.locomotor={};hand=cane
assert(not A.CastStaff(p,staff,goat),'wrong held item rejected before any native request')
hand=staff;assert(A.CastStaff(p,staff,goat) and rpcCount==0)
pc.act.preview_cb();assert(rpcCount==1,'rightclick RPC issued only by native preview callback')
hand=cane;pc.act.preview_cb();assert(rpcCount==1,'late gear switch revokes pending spell')
hand=staff;pc.locomotor=nil;assert(A.CastStaff(p,staff,goat));pc.act.non_preview_cb();assert(rpcCount==2)
pc.ismastersim=true;assert(A.CastStaff(p,staff,goat) and rpcCount==2,'host uses normal action without remote RPC')
busy=true;assert(not A.CastStaff(p,staff,goat),'busy controller reports rejection instead of false success')
RPC=oldRPC;SendRPCToServer=oldSend;GetTime=oldTime;ACTIONS.CASTSPELL=savedSpell
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
print('PASS: wind waits for real staff hand/equip/busy acknowledgement; no travel-release weapon cancellation; guarded actual RightClick casts with both prediction modes and host; busy failure is explicit')
