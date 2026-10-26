-- 合并回归：真实游戏 Class、动作选择器与旧 AI 模块；网络为模拟。
local checks=0
local function check(value,message)
    checks=checks+1
    assert(value,message)
end
assert(loadstring(read_source("class.lua")))()
local now=0
function GetTime() return now end
local Vector={}
Vector.__index=Vector
function Vector:DistSq(p) return (self.x-p.x)^2+(self.y-p.y)^2+(self.z-p.z)^2 end
function Vector:Get() return self.x,self.y,self.z end
function Vector:is_a(t) return t==Vector3 end
function Vector3(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},Vector) end
EntityScript={}
EQUIPSLOTS={HANDS="hands",HEAD="head",BODY="body"}
FOODTYPE={MEAT="meat",GOODIES="goodies",VEGGIE="veggie"}
FOODGROUP={}
TUNING={CALORIES_MED=25}
CONTROL_FORCE_STACK=101; CONTROL_FORCE_TRADE=102
CONTROL_MOVE_UP=103; CONTROL_MOVE_DOWN=104; CONTROL_MOVE_LEFT=105; CONTROL_MOVE_RIGHT=106
CONTROL_ATTACK=107; CONTROL_ACTION=108
KEY_F8=1008
ANCHOR_LEFT=0; ANCHOR_TOP=1; ANCHOR_MIDDLE=2; SCALEMODE_PROPORTIONAL=1; BODYTEXTFONT="testfont"
ACTIONS={}
for i,name in ipairs({"WALKTO","LOOKAT","CHOP","MINE","DIG","PICK","PICKUP","EAT","HEAL","FERTILIZE","CAST_POCKETWATCH","EQUIP","UNEQUIP","COOK","ADDFUEL","TURNON","TURNOFF","ATTACK","RUMMAGE","DEPLOY","STORE","SMOTHER","SLEEPIN","JUMPIN","ACTIVATE","READ","SING"}) do ACTIONS[name]={code=i,priority=1,id=name,instant=false} end
RPC={LeftClick="left",RightClick="right",StopAllControls="stopall",StopWalking="stopwalk",UseItemFromInvTile="inventory",ControllerUseItemOnSceneFromInvTile="useitem"}
local rpc_log={}
function SendRPCToServer(...) rpc_log[#rpc_log+1]={...} end
local deferred={}
local guid=1
local function entity(prefab,tags,point)
    guid=guid+1
    local e={prefab=prefab,GUID=guid,tags=tags or {},point=point or Vector3(0,0,0),replica={},components={},valid=true,offered={}}
    function e:IsValid() return self.valid end
    function e:HasTag(tag) return self.tags[tag]==true end
    function e:HasAnyTag(...) for _,tag in ipairs({...}) do if self:HasTag(tag) then return true end end return false end
    function e:GetPosition() return self.point end
    function e:GetDistanceSqToInst(other) return self.point:DistSq(other.point) end
    function e:GetCurrentPlatform() return self.platform end
    function e:is_a(t) return t==EntityScript end
    function e:CollectActions(context,doer,a,b,c)
        local list=context=="USEITEM" and b or a
        for _,name in ipairs(self.offered[context] or {}) do list[#list+1]=ACTIONS[name] end
    end
    function e:DoTaskInTime(delay,fn) local task={time=now+delay,fn=function() fn(self) end}; function task:Cancel() self.cancelled=true end; deferred[#deferred+1]=task; return task end
    function e:DoPeriodicTask(delay,fn) local task={fn=fn}; function task:Cancel() self.cancelled=true end; return task end
    function e:ListenForEvent(name,fn) self[name]=fn end
    function e:ClearBufferedAction() self.buffer=nil end
    return e
end
function BufferedAction(doer,target,action,item,point)
    local act={doer=doer,target=target,action=action,invobject=item,pos=point,rotation=0,options={}}
    function act:GetActionPoint() return self.pos end
    return act
end
local world_entities={}
local light=.8
local passable=function() return true end
local ocean=function() return false end
TheWorld=entity("forest",{})
TheWorld.meta={session_identifier="session01"}
TheWorld.state={isnight=false,isdusk=false,israining=false,cycles=5,time=.5}
TheWorld.Map={IsPassableAtPoint=function(_,x,y,z) return passable(x,z) end,IsOceanAtPoint=function(_,x,y,z) return ocean(x,z) end}
local saved={}
local load_callback=nil
TheSim={
    GetLightAtPoint=function() return light end,
    FindEntities=function(_,x,y,z,r,required,excluded)
        local result={}
        for _,e in ipairs(world_entities) do
            local omit=false
            for _,tag in ipairs(excluded or {}) do if e:HasTag(tag) then omit=true end end
            if e.valid and not omit and e.point:DistSq(Vector3(x,y,z))<=r*r then result[#result+1]=e end
        end
        return result
    end,
    GetPersistentString=function(_,key,cb) if load_callback=="defer" then load_callback=cb else cb(saved[key]~=nil,saved[key] or "") end end,
    SetPersistentString=function(_,key,text,encode,cb) saved[key]=text; cb(true) end,
}
TheNet={GetServerName=function() return "测试服" end,IsDedicated=function() return false end,GetIsServerPaused=function() return false end}
local screen={name="HUD"}
TheFrontEnd={GetActiveScreen=function() return screen end}
function IsPaused() return false end
package.preload.json=function() return assert(loadstring(read_source("json.lua")))() end
package.preload.cooking=function() return {recipes={cookpot={meatballs={hunger=62.5,health=3,sanity=5,foodtype=FOODTYPE.MEAT},dragonpie={hunger=75,health=40,sanity=5,foodtype=FOODTYPE.VEGGIE}}}} end
package.preload.usercommands=function() return {RunTextUserCommand=function() end} end
local picker_class=assert(loadstring(read_source("components/playeractionpicker.lua")))()
local function vitals(percent)
    return {percent=percent,GetPercent=function(self) return self.percent end,Max=function() return 150 end,IsDead=function() return false end}
end
local function item(prefab,actions,tags,n)
    local e=entity(prefab,tags)
    -- These fixture prefabs carry native pristine weapon tags in the game.
    if prefab=="spear" or prefab=="axe" or prefab=="pocketwatch_weapon" then e.tags.weapon=true end
    e.offered.INVENTORY=actions or {}
    e.n=n or 1
    e.replica.stackable={StackSize=function() return e.n end}
    return e
end
local function player(prefab)
    local p=entity(prefab or "wilson",{idle=true,player=true})
    local inv={items={},equips={},active=nil,slots=15}
    function inv:GetItems() return self.items end
    function inv:GetEquips() return self.equips end
    function inv:GetEquippedItem(slot) return self.equips[slot] end
    function inv:GetNumSlots() return self.slots end
    function inv:GetOverflowContainer() return self.overflow end
    function inv:GetActiveItem() return self.active end
    function inv:TakeActiveItemFromAllOfSlot(slot) self.take_requested=slot end
    function inv:ReturnActiveItem() self.return_requested=true end
    function inv:MoveItemFromAllOfSlot(slot,target) self.transfer={slot,target} end
    function inv:DropItemFromInvTile(obj,single) self.drop_requested={obj,single} end
    p.replica={inventory=inv,health=vitals(.9),hunger=vitals(.8),sanity=vitals(.8)}
    p.player_classified={currenttemperature=20,moisture={value=function() return 0 end}}
    p.HUD={IsMapScreenOpen=function() return false end,IsControllerInventoryOpen=function() return false end}
    p.userid="player01"
    local pc={inst=p,ismastersim=false,remote_controls={},busy=false,enabled=true}
    function pc:IsControlPressed() return false end
    function pc:IsBusy() return self.busy end
    function pc:IsEnabled() return self.enabled end
    function pc:EncodeControlMods() return 0 end
    function pc:GetPlatformRelativePosition(x,z) return nil,x,z end
    function pc:DoAction(act)
        self.last_action=act; p.buffer=act
        if self.ismastersim then self.host_executed=act
        elseif self.delay_preview then self.late_action=act
        elseif self.locomotor then if act.preview_cb then act.preview_cb() end
        elseif act.non_preview_cb then act.non_preview_cb() end
    end
    function pc:RemoteUseItemFromInvTile(act,obj)
        self.last_action=act
        local send=function() SendRPCToServer(RPC.UseItemFromInvTile,act.action.code,obj,0,act.action.mod_name) end
        if self.delay_preview then act.preview_cb=send else send() end
    end
    function pc:RemoteControllerUseItemOnSceneFromInvTile(act,obj) self.last_action=act; SendRPCToServer(RPC.ControllerUseItemOnSceneFromInvTile,act.action.code,obj,act.target,act.action.mod_name) end
    p.components.playercontroller=pc
    p.components.playeractionpicker=picker_class(p)
    return p
end
AllRecipes={torch={name="torch",product="torch"},axe={name="axe",product="axe"},campfire={name="campfire",product="campfire",placer="campfire_placer"}}
local function builder(p)
    local b={known=true,ingredients=true,buffered=false}
    function b:KnowsRecipe() return self.known end
    function b:CanLearn() return true end
    function b:HasIngredients() return self.ingredients end
    function b:IsBuildBuffered() return self.buffered end
    function b:IsBusy() return false end
    function b:CanBuildAtPoint() return true end
    function b:MakeRecipeFromMenu(recipe) self.request=recipe end
    function b:MakeRecipeAtPoint(recipe,point) self.request=recipe; self.point=point end
    p.replica.builder=b
    return b
end

for key in pairs(package.loaded) do
    if key:find("shadowself/legacy/",1,true) or key=="shadowself/control/autonomy" then package.loaded[key]=nil end
end
package.loaded.cooking=nil;package.loaded.json=nil
local Autonomy=require("shadowself/control/autonomy")
local p=player();ThePlayer=p;builder(p)
local berry=item("berries",{"EAT"},nil,3)
p.replica.inventory.items[1]=berry;p.replica.hunger.percent=.1
local reports={};local auto=Autonomy(p,function(s) reports[#reports+1]=s end)
check(#rpc_log==0,"constructing autonomous runner sends no inputs")
check(auto.controller.model.ready,"namespaced memory loads")
auto:Tick()
check(auto.controller.active and auto.controller.pending.name=="EAT","hungry AI decides to eat before work")
now=now+2;auto:Tick()
check(#rpc_log>0 and p.components.playercontroller.last_action.action==ACTIONS.EAT,"decision reaches real action picker and native inventory route")
check(auto.controller.pending~=nil,"request alone does not complete eating")
berry.n=2;now=now+.5;auto:Tick()
check(auto.controller.pending==nil,"server inventory decrease confirms eating")
check(#reports>0,"decision summary reaches shadow local dialogue callback")
auto:Cancel();local previous=#rpc_log
check(not auto.controller.active and auto.controller.removed,"cancel disables imported controller")
-- 已停止实例即使误调 Tick 也不能重新执行。
auto:Tick();check(#rpc_log==previous,"removed controller cannot send again")
local registry=require("shadowself/legacy/registry")
check(not _G.AIPLAYER,"import does not create old global registry")
check(auto.controller.model.key:find("shadowself_ai_v1_",1,true)==1,"old AI save is untouched")
print("PASS: Lua 5.1 native Class/picker, imported AI initialization, hunger decision, server confirmation and cancellation: "..checks)

local Queue=require("shadowself/zom/ActionQueue")
local pc=p.components.playercontroller
p.Transform={GetWorldPosition=function() return 0,0,0 end}
local tree=entity("evergreen",{CHOP_workable=true},Vector3(3,0,0));world_entities={tree}
local action=BufferedAction(p,tree,ACTIONS.CHOP)
pc.locomotor={Stop=function() end};pc.delay_preview=true
p.components.playeractionpicker={GetLeftClickActions=function() return {action} end,GetRightClickActions=function() return {} end}
local q=Queue.new(_G,function() end,function() end,function() end,function() return false end)
q:Set({{kind="chop",text="树"}},p,p)
q:Update(p,now);check(pc.late_action==action,"imported queue creates real scene action callback")
local n=#rpc_log;q:Cancel(p);action.preview_cb()
check(#rpc_log==n,"cancelled imported queue rejects delayed click RPC")
print("PASS: imported queue native scene callback invalidated on cancel")

-- 同一个自动托管实例：感知威胁后启动3014，低血停线程交回生存层。
package.loaded["shadowself/control/autonomy"]=nil
local NativeAuto=require("shadowself/control/autonomy")
local spear=item("spear",{"EQUIP"})
spear.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end,IsRestricted=function() return false end}
spear.replica.inventoryitem={GetWalkSpeedMult=function() return 1 end}
p.replica.inventory.items={spear};p.replica.inventory.equips.hands=spear
p.replica.hunger.percent=.8;p.replica.health.percent=.9
p.replica.combat={IsAlly=function() return false end,GetAttackRangeWithWeapon=function() return 2 end}
local monster=entity("spider",{hostile=true,monster=true},Vector3(2,0,0))
monster.replica.combat={GetTarget=function() return p end};world_entities={monster}
local starts,ends=0,0
HitAndRun={GetAttackTargets=function(h) h.selected_ents={[monster]=true} end,
    IsAttackPre=function() return nil end,DoDodge=function() end,
    StartHitAndRun=function() starts=starts+1;TUNING.Cheatthread={id=702,SetList=function() end} end,
    StopHitAndRun=function() ends=ends+1;TUNING.Cheatthread=nil end}
MOD_util={};POS_util={GoToPoint=function() end};ENT_util={};TUNING.Cheatthread=nil
local a=NativeAuto(p,function() end);a:Tick()
check(starts==1 and a:OwnsCombat(),"autonomous takeover actually starts 3014 thread")
local pending=a.controller.pending;a:Tick()
check(starts==1 and a.controller.pending==pending,"survival action loop does not compete with native combat")
p.replica.health.percent=.2;a.controller.perception.next_scan=0;now=now+.5;a:Tick()
check(ends==0 and a:OwnsCombat(),"low health alone does not release combat or force retreat")
a:Cancel();check(not TUNING.Cheatthread,"cancel releases all owned native combat")
print("PASS: autonomous 3014 entry, exclusive thread control, no health-threshold retreat and cancel")

-- 实际 CombatEquipment：先借手杖，服务器同步前不能视为已切；战斗换回原武器。
p.components.playeractionpicker=picker_class(p)
local cane=item("cane",{"EQUIP"},{weapon=true})
cane.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end,IsRestricted=function() return false end}
cane.replica.inventoryitem={GetWalkSpeedMult=function() return 1.25 end}
p.replica.inventory.items={spear,cane};p.replica.inventory.equips.hands=spear
local gear=registry.CombatEquipment({player=p,owner=a.controller,actions=a.controller.actions,
    roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end}})
check(not gear:Swap("move",{night=false}) and gear.pending.item==cane,"travel requests faster cane")
check(p.replica.inventory.equips.hands==spear and not gear:Swap("move",{}),"pending equip does not count as synchronized hand")
p.replica.inventory.equips.hands=cane;now=now+.3
check(gear:Swap("move",{}),"travel continues after authoritative cane equip")
check(not gear:Swap("attack",{}) and gear.pending.item==spear,"combat restores remembered weapon")
p.replica.inventory.equips.hands=spear;now=now+.3
check(gear:Swap("attack",{}),"attack allowed after authoritative weapon equip")
-- 开局空手/只有手杖，之后获得武器：同一次接管必须重新选武器。
gear:Reset();p.replica.inventory.items={};p.replica.inventory.equips.hands=nil
check(gear:Weapon()==nil,"initial empty inventory has no cached weapon")
p.replica.inventory.items={cane};p.replica.inventory.equips.hands=cane
check(gear:Weapon()==cane,"cane only is a temporary fallback")
p.replica.inventory.items={cane,spear}
check(gear:Weapon()==spear,"newly acquired weapon replaces cached travel cane")
now=now+.3;check(not gear:Swap("attack",{}) and gear.pending.item==spear,"new weapon equip requested before attack")
check(not gear:Swap("attack",{}) and p.replica.inventory.equips.hands==cane,"waits for actual hand synchronization")
p.replica.inventory.equips.hands=spear;now=now+.3
check(gear:Swap("attack",{}),"attack resumes with newly received weapon")
p.replica.inventory.items={cane};p.replica.inventory.equips.hands=cane
check(gear:Weapon()==cane,"lost weapon is discarded rather than reused from cache")
p.replica.inventory.items={cane,spear};check(gear:Weapon()==spear,"another inventory change is detected without restarting takeover")
local torch=item("torch",{"EQUIP"},{light=true})
torch.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end}
torch.replica.inventoryitem={GetWalkSpeedMult=function() return 1 end}
p.replica.inventory.items={torch,cane};p.replica.inventory.equips.hands=torch;light=.01
check(gear:Mobile({night=true})==torch,"darkness preserves sole hand light instead of cane")
print("PASS: real AI Player travel gear, synchronized weapon restoration and darkness light")

-- Real ActionLibrary/Equipment busy rejection must not become a 3-second item ban.
local saved_busy=pc.IsBusy;local busy=true;pc.IsBusy=function() return busy end;now=now+1
p.replica.inventory.items={cane,spear};p.replica.inventory.equips.hands=cane
gear:Reset();local rpc_before=#rpc_log
check(not gear:Swap("attack",{}) and not gear.pending and not gear.failed[spear],"hit busy does not create equip timeout or weapon failure cooldown")
check(#rpc_log==rpc_before,"busy equip does not stop controls or send another request")
busy=false;now=now+.033
check(not gear:Swap("attack",{}) and gear.pending and gear.pending.item==spear,"first recovered frame requests weapon without waiting 1.2/3 seconds")
p.replica.inventory.equips.hands=spear;now=now+.033
check(gear:Swap("attack",{}),"confirmed hand resumes combat on next frame")
-- Busy can begin between the initial controller check and Execute.
gear:Reset();p.replica.inventory.equips.hands=cane;now=now+.5
local execute=gear.combat.actions.Execute
gear.combat.actions.Execute=function() return false,"角色忙碌" end
check(not gear:Swap("attack",{}) and not gear.failed[spear],"late native busy rejection is transient too")
gear.combat.actions.Execute=execute
check(not gear:Swap("attack",{}) and gear.pending.item==spear,"retry after native busy rejection is immediate")
-- The currently held weapon is usable even if an obsolete travel request was pending.
p.replica.inventory.equips.hands=spear;gear.pending={item=cane,role="move",untiltime=now+1.2}
check(gear:Swap("attack",{}) and not gear.pending,"stale cane acknowledgement never blocks an already held combat weapon")
pc.IsBusy=saved_busy
print("PASS: real equipment busy/late busy never blacklists; first recovered frame retries; stale travel acknowledgement releases")

-- Real native inventory equip acknowledgement during dodge, not a distance chase.
now=now+.5 -- Independent dodge transaction after the prior equip test's rate window.
local Travel=require("shadowself/control/travel");local dodge=Travel(p,gear)
p.replica.inventory.items={spear,cane};p.replica.inventory.equips.hands=spear;gear:Reset()
dodge:BeginDodge({night=false})
check(gear.pending and gear.pending.item==cane,"dodge event requests real cane equip immediately")
p.replica.inventory.equips.hands=cane;now=now+.11;dodge:UpdateDodge({night=false})
check(not gear.pending and dodge.dodging,"acknowledged cane stays held throughout dodge")
dodge:Tick(p:GetPosition(),2,true,{night=false})
check(dodge.role=="move","near target/imminent attack does not override a real dodge's cane role")
dodge:EndDodge({night=false})
check(gear.pending and gear.pending.item==spear,"native dodge exit requests real weapon equip")
p.replica.inventory.equips.hands=spear;now=now+.11;dodge:UpdateDodge({night=false})
check(not dodge.restore_dodge and not gear.pending,"confirmed weapon completes restoration without stale wait")
print("PASS: actual equipment/inventory cane acknowledgement, hold while dodging near target, native exit weapon acknowledgement")
