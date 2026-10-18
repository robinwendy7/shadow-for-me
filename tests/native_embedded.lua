-- Execute the migrated engine itself with no Workshop globals installed.
Vector3=Vector3 or function(x,y,z) return {x=x,y=y,z=z} end
local Native=require("shadowself/native")
local saved={};for _,key in ipairs({"TheNet","TheSim","TheInput","TUNING","kleiloadlua","HitAndRun","POS_util","MOD_util","ENT_util","GLOBAL","DEGREES","FRAMES","Prefab","FUELTYPE","TheWorld","ThePlayer","HandleRPC","SendRPCToServer","global","__STRICT","RPC","ACTIONS","BufferedAction"}) do saved[key]=rawget(_G,key) end
Prefab={_ctor=function() end};FUELTYPE={BURNABLE="BURNABLE"};TUNING=setmetatable({FRUITDRAGON={HIT_RANGE=3,ATTACK_RANGE=2}},{__index=function(_,k) if k~="Cheatthread" and k~="FORGE" and k~="Shieldthread" then return 6 end end});HitAndRun=nil;POS_util=nil;MOD_util=nil;ENT_util=nil;GLOBAL=_G;DEGREES=math.pi/180;FRAMES=1/30
TheNet={GetIsServerAdmin=function() return false end,GetIsServer=function() return false end,GetPing=function() return 0 end}
TheSim={GetScreenSize=function() return 1920,1080 end,GetUsersName=function() return "local-test" end,FindEntities=function() return {} end}
TheInput={IsKeyDown=function() return false end,IsControlPressed=function() return false end}
kleiloadlua=function(path) return assert(loadfile(path)) end
local pc={RemoteDirectWalking=function() end}
local dependencies={
 ["components/playercontroller"]=pc,["prefabs/player_common_extensions"]={},
 ["equipslotutil"]={ToID=function(v) return v end},
 ["widgets/imagebutton"]={},["widgets/uianim"]={},["widgets/uianimbutton"]={}}
local original={};for name,value in pairs(dependencies) do original[name]=package.loaded[name];package.loaded[name]=value end
-- Load this installed game's actual strict.lua, then dispatch a host attack RPC.
local previous_mt=getmetatable(_G)
local RPC_HANDLERS={}
local input_handler={};local controller={handler=input_handler,ismastersim=true,inst={}}
controller.CanLocomote=function() return true end
controller.IsEnabled=function() return true end
controller.EncodeControlMods=function() return 0 end
controller.GetPlatformRelativePosition=function(_,x,z) return nil,x,z end
local moves=0
controller.DoAction=function(_,action) assert(action._shadowself_native);moves=moves+1;if action.preview_cb then action.preview_cb() end end
RPC={LeftClick=99,PredictWalking=100}
ACTIONS={ATTACK={code=11},WALKTO={code=12}}
BufferedAction=function(doer,target,action,item,pos) return {doer=doer,target=target,action=action,pos=pos} end
TheWorld={ismastersim=true};ThePlayer={components={playercontroller=controller},HasTag=function() return false end,
 replica={inventory={GetActiveItem=function() end}}};HandleRPC=function(code) return RPC_HANDLERS[code] end
local remote_calls=0;SendRPCToServer=function() remote_calls=remote_calls+1 end
local n=Native.Init("./")
assert(loadstring(read_source("strict.lua")))()
local host_calls,resolutions=0,0
local resolver=n.MOD_util.GetUpvalue_deekseek
RPC_HANDLERS[99]=function(player,action)
    -- 与当前原版OnRemoteLeftClick相同的本地主机handler门槛。
    assert(player.components.playercontroller._shadowself_native_rpc,"host RPC action carries native ownership into playercontroller")
    if player.components.playercontroller.handler==nil and (action=="attack" or action==ACTIONS.ATTACK.code) then host_calls=host_calls+1 end
end
n.MOD_util.GetUpvalue_deekseek=function(object,fn,key)
    assert(fn==HandleRPC and key=="RPC_HANDLERS");resolutions=resolutions+1
    return resolver(object,fn,key)
end
n.SendRPCToServer(99,"attack");n.SendRPCToServer(99,"attack")
assert(controller.handler==input_handler and not controller._shadowself_native_rpc,"host action dispatch restores local input handler and ownership")
assert(host_calls==2 and resolutions==1,"strict host RPC dispatch resolves and caches handlers once")
local foe={GetPosition=function() return Vector3(2,0,0) end}
n.HitAndRun.ent=foe;n.HitAndRun:OnNormalFrame()
assert(host_calls==3 and controller.handler==input_handler,"actual native OnNormalFrame -> CloseAndAttack reaches enabled host attack handler")
n.HitAndRun:PredictWalk(Vector3(0,0,0),Vector3(1,0,0),foe)
assert(moves==1,"host recovery uses one native WALKTO action instead of rejected PredictWalking RPC")
local old_handler=RPC_HANDLERS[99];RPC_HANDLERS[99]=function() error("injected RPC failure") end
local ok=pcall(n.SendRPCToServer,99,"attack")
assert(not ok and controller.handler==input_handler and not controller._shadowself_native_rpc,"RPC failure also restores local input")
RPC_HANDLERS[99]=old_handler
TheWorld.ismastersim=false;n.SendRPCToServer(99,"attack")
assert(remote_calls==1 and host_calls==3,"remote clients use normal engine RPC sender")
assert(n.missing_private_cache==nil,"optional private fields cannot fall through strict game globals")
assert(n.HitAndRun and n.HitAndRun.DoDodge and n.HitAndRun.StartHitAndRun,"embedded engine loads without subscribed mods")
assert(not rawget(_G,"HitAndRun") and not rawget(_G,"POS_util") and not TUNING.Cheatthread,"embedded objects never overwrite Workshop/global objects")
assert(n.TUNING~=TUNING and n.POS_util.CalculateAimPos and n.EQUIP_util.ToID)
assert(n.HitAndRun.targetanimtable.deerclops and n.HitAndRun.targetanimtable.klaus,"original monster dodge tables are present")
local pig_expected={atk_slam_pre={10,30,2,false,90},atk_slam={0,10,2,false,90},run_pre={0,30,4,false,80},run_loop={0,30,8,true,0},atk3={0,12,5,true,80}}
local pig_count=0
for _,entry in pairs(n.HitAndRun.targetanimtable.daywalker) do
 local v=assert(pig_expected[entry.atkanim]);pig_count=pig_count+1
 assert(entry.atk_start_frame==v[1] and entry.atk_stop_frame==v[2] and entry.dist==v[3] and entry.update==v[4] and math.abs(entry.angle-v[5]*math.pi/180)<.001,"daywalker uses original 3014 animation/frame/angle/range")
end
assert(pig_count==5)
local oldanim=n.ENT_util.GetAnimation;n.ENT_util.GetAnimation=function(_,e) return e.anim end
local pig={prefab="daywalker",anim="run_pre",HasTag=function() return false end,AnimState={GetCurrentAnimationFrame=function() return 0 end}}
assert(n.HitAndRun:IsAttackPre(pig),"visible pounce windup must not wait for delayed replicated attack tag")
n.HitAndRun.shadowself_latency_frames=function() return 5 end;pig.anim="atk_slam_pre";pig.AnimState.GetCurrentAnimationFrame=function() return 5 end
assert(n.HitAndRun:IsAttackPre(pig),"native frame10 prep starts five observed frames earlier under network budget")
n.HitAndRun.shadowself_latency_frames=nil;n.ENT_util.GetAnimation=oldanim
for _,entry in pairs(n.HitAndRun.targetanimtable.alterguardian_phase2) do
 if entry.atkanim=="attk_chop" then assert(entry.dist==nil,"native 40-unit summon retreat removed") end
end
local p=Vector3(0,0,0);local q=Vector3(1,0,0);local v=n.POS_util:CalculateAimPos(p,q,math.pi/2,4)
assert(math.abs(v.x)<.001 and math.abs(v.z-4)<.001,"migrated geometry helper executes")
Native.context=nil
setmetatable(_G,previous_mt)
for name in pairs(dependencies) do package.loaded[name]=original[name] end
for _,key in ipairs({"TheNet","TheSim","TheInput","TUNING","kleiloadlua","HitAndRun","POS_util","MOD_util","ENT_util","GLOBAL","DEGREES","FRAMES","Prefab","FUELTYPE","TheWorld","ThePlayer","HandleRPC","SendRPCToServer","global","__STRICT","RPC","ACTIONS","BufferedAction"}) do rawset(_G,key,saved[key]) end
print("PASS: actual embedded engine and all support modules initialise under actual strict.lua, cached host RPC dispatch, remote RPC fallback and no external mod globals")
