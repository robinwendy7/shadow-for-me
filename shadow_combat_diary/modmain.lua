local G=GLOBAL
if G.TheNet:IsDedicated() then return end
local recorder=require("scd_recorder").New(G,{
    enabled=GetModConfigData("auto_record")~=false,
    interval=GetModConfigData("sample_interval") or .25,
})
G.SHADOW_COMBAT_DIARY=recorder
AddSimPostInit(function()
    if not G.TheWorld then return end
    G.TheWorld:DoPeriodicTask(recorder.interval,function() recorder:Safe(recorder.Tick) end)
    G.TheWorld:ListenForEvent("onremove",function() recorder:Safe(recorder.Unbind,"world_removed") end)
end)
if GetModConfigData("show_buttons")~=false then
    AddClassPostConstruct("widgets/controls",function(self)
        local Button=require("widgets/textbutton")
        local root=self.topright_root or self
        local toggle=root:AddChild(Button("scd_toggle"));toggle:SetPosition(-205,-240);toggle:SetTextSize(22)
        toggle:SetOnClick(function() recorder:Safe(recorder.Toggle) end)
        local export=root:AddChild(Button("scd_export"));export:SetPosition(-205,-270);export:SetTextSize(22)
        export:SetText("反馈：写入日志");export:SetOnClick(function() recorder:Safe(recorder.Export) end)
        self.inst:DoPeriodicTask(.5,function()
            toggle:SetText("战斗日志："..(recorder.enabled and "记录中" or "已暂停").." / 死亡 "..recorder.deaths)
        end)
    end)
end
