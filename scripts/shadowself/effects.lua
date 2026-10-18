-- 只用无 Network 的本地渲染实体；生命周期由运行时统一回收。
local Effects=Class(function(self) self.items={} end)
function Effects:Spawn(bank,build,anim,x,y,z,scale,duration)
    local e=CreateEntity()
    e.entity:AddTransform(); e.entity:AddAnimState(); e.entity:AddSoundEmitter()
    e.persists=false
    e:AddTag("FX"); e:AddTag("NOCLICK"); e:AddTag("DECOR")
    e.Transform:SetPosition(x,y,z); e.Transform:SetScale(scale,scale,scale)
    e.AnimState:SetBank(bank); e.AnimState:SetBuild(build)
    e.AnimState:PlayAnimation(anim,false); e.AnimState:SetMultColour(0,0,0,.5); e.AnimState:UsePointFiltering(true)
    self.items[#self.items+1]={inst=e,expires=GetTime()+duration}
    return e
end
function Effects:Burst(x,y,z,cracks)
    local fx=self:Spawn("statue_ruins_fx","statue_ruins_fx","transform_nightmare",x,y,z,.65,2)
    local focal=TheFocalPoint and TheFocalPoint.SoundEmitter
    local emitter=focal or fx.SoundEmitter
    emitter:PlaySound("dontstarve/maxwell/shadowmax_despawn",nil,1)
    if cracks then self:Spawn("fx_ice_crackleandpop","fx_ice_crackleandpop","crackle",x,y,z,.8,3) end
end
function Effects:Step()
    for i=#self.items,1,-1 do
        local fx=self.items[i]
        if not fx.inst:IsValid() or GetTime()>fx.expires then
            if fx.inst:IsValid() then fx.inst:Remove() end
            table.remove(self.items,i)
        end
    end
end
function Effects:Destroy()
    for _,fx in ipairs(self.items) do if fx.inst:IsValid() then fx.inst:Remove() end end
    self.items={}
end
return Effects
