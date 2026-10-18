-- 用受限渲染模拟验证本地实体生命周期；没有模拟引擎画面。
local time=100
GetTime=function() return time end
package.loaded["components/skinner"]={}
package.loaded["shadowself/actor"]=nil
package.loaded["shadowself/effects"]=nil
local made={}
local function entity()
    local e={x=0,y=0,z=0,valid=true,shown=true,tags={}}
    e.entity={AddTransform=function() end,AddAnimState=function() end,AddSoundEmitter=function() end,SetCanSleep=function() end}
    e.Transform={SetFourFaced=function() end,SetScale=function(_,x,y,z) e.scale=x end,
        SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end,
        GetWorldPosition=function() return e.x,e.y,e.z end}
    e.hidden_layers={}
    e.SoundEmitter={PlaySound=function(_,sound) e.sound=sound end}
    e.AnimState={}
    for _,key in ipairs({"SetBank","SetBuild","SetSkin","Hide","Show","ClearOverrideBuild","ClearOverrideSymbol","AddOverrideBuild","OverrideSymbol","SetDeltaTimeMultiplier","SetFinalOffset","PushAnimation"}) do e.AnimState[key]=function() end end
    function e.AnimState:UsePointFiltering(value) e.point_filter=value end
    function e.AnimState:Hide(layer) e.hidden_layers[layer]=true end
    function e.AnimState:Show(layer) e.hidden_layers[layer]=nil end
    function e.AnimState:SetMultColour(r,g,b,a) e.tint={r,g,b,a} end
    function e.AnimState:PlayAnimation(name,loop) e.animation=name; e.plays=(e.plays or 0)+1 end
    function e.AnimState:OverrideMultColour(r,g,b,a) e.override_alpha=a end
    function e.AnimState:SetBuild(build) e.build=build;e.build_writes=(e.build_writes or 0)+1 end
    function e.AnimState:SetBank(bank) e.bank=bank end
    function e.AnimState:SetSkin(skin,default) e.skin=skin;e.skin_default=default end
    function e.AnimState:AssignItemSkins() end
    function e.AnimState:SetTime(t) e.anim_time=t end
    function e:AddTag(t) self.tags[t]=true end
    function e:IsValid() return self.valid end
    function e:Remove() self.valid=false end
    function e:Show() self.shown=true end
    function e:Hide() self.shown=false end
    function e:FacePoint() end
    made[#made+1]=e;return e
end
CreateEntity=entity
TheNet={GetClientTableForUser=function() return nil end}
TheWorld={Map={IsPassableAtPoint=function() return true end}}
local owner=entity();owner.prefab="wilson"
function owner:HasTag(tag) return tag=="playerghost" and self.ghost==true end
function owner.AnimState:IsCurrentAnimation(name) return name==owner.animation end
function owner.AnimState:GetCurrentAnimationLength() return 100/30 end
function owner.AnimState:GetCurrentAnimationTime() return time-(owner.native_start or time) end
function owner.AnimState:GetBuild() return owner.current_build or "wilson" end
function owner.AnimState:GetSkinBuild() return owner.current_skin or "" end
local Actor=require("shadowself/actor")
local a=Actor(owner)
assert(a.inst.tint[1]==0 and a.inst.tint[2]==0 and a.inst.tint[3]==0 and a.inst.tint[4]==.5,"native shadow black with 50 percent opacity")
assert(a.inst.tags.FX and a.inst.tags.NOCLICK and not a.inst.entity.AddNetwork)
assert(a.inst.point_filter and a.inst.hidden_layers.HAIR_HAT and a.inst.hidden_layers.HEAD_HAT_NOHELM and a.inst.hidden_layers.HEAD_HAT_HELM,"native point filtering and alternate layers hidden")
local rt={context={},dead=false,effects={bursts={}}}
function rt.effects:Burst(x,y,z,cracks) self.bursts[#self.bursts+1]={x=x,y=y,z=z,cracks=cracks} end
local writes=a.inst.build_writes;a:CopyAppearance();a:CopyAppearance();assert(a.inst.build_writes==writes,"unchanged skin does not rebuild")
-- A stale client-table base skin must never turn the live form back into prefab.
local oldskins,olddata,oldgetter=SetSkinsOnAnim,GetSkinData,GetSkinsDataFromClientTableData
TheNet.GetClientTableForUser=function() return {base_skin="wilson_formal"} end
GetSkinsDataFromClientTableData=function() return "wilson_formal",{} end
GetSkinData=function() return {skins={normal_skin="wilson_formal_build"}} end
SetSkinsOnAnim=function(anim,prefab,skin,clothes,curse,mode,default) anim:SetSkin(skin,default) end
owner.current_build="custom_current_form";owner.current_skin="custom_current_skin"
a:CopyAppearance();assert(a.inst.build=="custom_current_form" and a.inst.skin=="custom_current_skin" and a.inst.skin_default=="custom_current_form","uses current build and current skin build, not prefab or loadout normal_skin")
owner.current_build="weregoose_build";owner.current_skin=""
time=time+.3;a:RefreshAppearance();assert(a.inst.build=="weregoose_build" and a.inst.bank=="weregoose","form follows current build while prefab still wilson")
owner.current_build="wilson";time=time+.3;a:RefreshAppearance();assert(a.inst.bank=="wilson","return to human bank follows current build")
TheNet.GetClientTableForUser=function() return nil end
SetSkinsOnAnim,GetSkinData,GetSkinsDataFromClientTableData=oldskins,olddata,oldgetter
owner.current_build=nil;owner.current_skin=nil
a.inst.Transform:SetPosition(20,0,0)
a:Step(.05,rt);assert(a.inst.x<20 and a.catching,"catch only outside 15")
local plays=a.inst.plays;a:Step(.05,rt);assert(a.inst.plays==plays,"moving animation is not restarted every frame")
local x=a.inst.x;rt.wait=true;a:Step(.05,rt);assert(a.inst.x==x,"wait holds position");rt.wait=false
a.inst.Transform:SetPosition(10,0,0);a.catching=false;a.decide_at=time+100
a:Step(.05,rt);assert(a.inst.x==10 and not a.catching,"within 15 no fixed distance adjustment")
a.inst.Transform:SetPosition(6,0,0);a.catching=true
a:Step(.05,rt);assert(not a.catching,"stop chasing inside 7")
a.goal=nil;a.vx,a.vz=0,0;a.state="follow";a:Step(1/60,rt);assert(a.state=="idle","stop switches animation immediately")
owner.animation="amulet_rebirth";owner.native_start=time
a:BeginCeremony("amulet");local held=a.carried
assert(held and held.inst.animation=="wendy_resurrect","player uses original victim track")
assert(a.inst.animation=="dissipate" and a.ghost,"ghost haunts in place before disappearing")
assert(held.inst.build=="wilson","carried actor snapshots live human build")
assert(owner.override_alpha==0,"native player masked locally")
time=time+.5;a:Step(.016,rt)
assert(not a.inst.shown and a.ceremony.phase=="buried" and a:SpeechTarget()==nil,"buried shadow truly hidden")
assert(#rt.effects.bursts==1 and not rt.effects.bursts[1].cracks,"departure shadow FX once")
time=time+.1;a:Step(.016,rt);assert(#rt.effects.bursts==1,"no repeated departure FX")
time=time+.3;a:Step(.016,rt)
assert(a.inst.shown and a.ghost and #rt.effects.bursts==2,"own ghost returns with FX as player rises")
assert(a.inst.animation=="shadowself_ghost_carry" and a.inst.anim_time==held.inst.anim_time,"ghost and human tracks use same native progress")
assert(held.inst.y==0 and held.inst.x==0,"lift uses animated bone matrices, not body bobbing")
time=time+3;a:Step(.05,rt);assert(not held.inst.valid and not a.ceremony and owner.override_alpha==1,"held actor and mask cleaned")
owner.animation="idle";owner.ghost=true;rt.dead=true
a:BeginCeremony("death");time=time+5;a:Step(.05,rt);assert(a.inst.shown and a.ghost,"death remains visible as a following ghost")
owner.current_build="custom_spirit_form";owner.current_skin="custom_spirit_skin";time=time+.3;a:RefreshAppearance()
assert(a.inst.build=="custom_spirit_form" and a.inst.skin=="custom_spirit_skin","ghost copies current builds without requiring prefab-based ghost name")
owner.ghost=false;rt.dead=false
owner.current_build=nil;owner.current_skin=nil
a:BeginCeremony("revive");time=time+2;a:Step(.05,rt);assert(a.state=="relief","relief after return")
a:BeginCeremony("transition");time=time+2;a:Step(.05,rt);assert(a.inst.scale==1,"transition restores scale")
local Effects=require("shadowself/effects")
local fx=Effects();fx:Burst(0,0,0,true);assert(#fx.items==2,"local effects");assert(fx.items[1].inst.sound=="dontstarve/maxwell/shadowmax_despawn","native local shadow sound")
time=time+4;fx:Step();assert(#fx.items==0,"effects expire")
owner.animation="amulet_rebirth";owner.native_start=time
a:BeginCeremony("amulet");held=a.carried;a:Destroy();fx:Destroy()
assert(not held.inst.valid and not a.inst.valid and owner.override_alpha==1,"cleanup during ceremony restores player")
for _,e in ipairs(made) do if e~=owner then assert(not e.valid,"no leaked local entities") end end
print("PASS: local actor movement, wait, lift, death, return, transition and effects cleanup")
