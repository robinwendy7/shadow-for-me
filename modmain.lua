-- 入口仅绑定本机 HUD。无 prefab 注册，无服务器钩子，无 RPC。
local G = GLOBAL
if G.TheNet:IsDedicated() then return end
local BossDebug=require("shadowself/control/newbosses/debug")
BossDebug.Configure(GetModConfigData("newboss_debug")~=false)
local WeaverDebug=require("shadowself/control/weaver/debug")
WeaverDebug.Configure(GetModConfigData("weaver_debug")~=false)
local QueenDebug=require("shadowself/control/queendebug")
G.print("[ShadowSelf] "..QueenDebug.VERSION.." loaded: embedded combat")
require("shadowself/native").Init(MODROOT)
local options = {
    bone_refuel = GetModConfigData("bone_refuel") or 25,
    speech_color = GetModConfigData("speech_color") or "red",
    speech_voice = GetModConfigData("speech_voice") ~= false,
    leash = GetModConfigData("leash") or 15,
    frequency = GetModConfigData("frequency") or 25,
    battle_music = GetModConfigData("battle_music") == true,
    ceremony = GetModConfigData("ceremony") ~= false,
}
Assets = {
    Asset("SOUNDPACKAGE", "sound/shadowself_battle.fev"),
    Asset("SOUND", "sound/shadowself_battle.fsb"),
    Asset("ANIM", "anim/shadowself_ghost_carry.zip"),
    Asset("ANIM", "anim/player_ghost_withhat.zip"),
    Asset("ANIM", "anim/ghost_wilson_build.zip"),
    Asset("ANIM", "anim/player_idles.zip"),
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_jump.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_actions_eat.zip"),
    Asset("ANIM", "anim/player_emotes.zip"),
    Asset("ANIM", "anim/player_emotes_sit.zip"),
    Asset("ANIM", "anim/wendy_resurrect.zip"),
    Asset("ANIM", "anim/statue_ruins_fx.zip"),
    Asset("ANIM", "anim/fx_ice_crackleandpop.zip"),
    Asset("ANIM", "anim/mole_build.zip"),
}
local function BindShadow(controls,owner)
    owner = owner or controls.owner
    require("shadowself/control/adventureworld/registry").Install(G)
    if owner == nil or owner ~= G.ThePlayer or owner._shadowself ~= nil then return end
    require("shadowself/bombs").Bind(owner)
    local handoff=require("shadowself/handoff")
    if handoff.runtime and handoff.runtime.owner~=owner then handoff.runtime:Destroy() end
    local Runtime = require("shadowself/runtime")
    local Panel = require("widgets/shadowselfpanel")
    local runtime = Runtime(owner, options)
    owner._shadowself = runtime
    handoff.runtime=runtime
    local panel = controls:AddChild(Panel(runtime, options))
    runtime.panel = panel
    local CombatButton=require("widgets/shadowselfcombatbutton")
    if controls.inv then runtime.combat_button=controls.inv:AddChild(CombatButton(runtime,controls.inv)) end
    local Speech = require("widgets/shadowselfspeech")
    runtime.speech = owner.HUD:AddChild(Speech(runtime))
    runtime.speech:SetHUD(owner.HUD.inst)
    local Consent = require("widgets/shadowselfconsent")
    runtime.consent = owner.HUD:AddChild(Consent(runtime))
    local PersonalityPicker = require("widgets/shadowselfpersonality")
    runtime.personality_picker = owner.HUD:AddChild(PersonalityPicker(runtime))
    runtime:Start()
    controls.inst:ListenForEvent("onremove", function() runtime:Destroy() end)
end
AddClassPostConstruct("widgets/controls",function(controls)
    BindShadow(controls)
    -- Seamless Wonkey changes can reuse controls; rebind to the new local entity.
    controls.inst:DoPeriodicTask(.2,function()
        local p=G.ThePlayer
        if p and p.HUD and p.HUD.controls==controls and p.components and p.components.playercontroller and not p._shadowself then
            BindShadow(controls,p)
        end
    end)
end)

-- Timestamp replicated bombs at creation, including bombs attached before takeover.
AddPrefabPostInit("sporebomb",function(inst) require("shadowself/bombs").Track(inst) end)
