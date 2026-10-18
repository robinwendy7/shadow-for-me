local C=require("shadowself/config")
local Appearance=require("shadowself/appearance")
local RebirthClock=require("shadowself/rebirthclock")
-- 只加载皮肤算法，不给任何实体添加 skinner 组件。
require("components/skinner")
local Actor=Class(function(self,owner,frozen)
    self.owner=owner
    self.frozen_appearance=frozen
    self.ghost=owner:HasTag("playerghost") and not frozen or false
    local e=CreateEntity()
    e.entity:AddTransform(); e.entity:AddAnimState()
    e.entity:SetCanSleep(false)
    e.persists=false
    e:AddTag("FX"); e:AddTag("NOCLICK"); e:AddTag("DECOR"); e:AddTag("shadowself_local")
    e.Transform:SetFourFaced()
    e.AnimState:SetBank("wilson")
    e.AnimState:SetBuild(owner.AnimState:GetBuild() or owner.prefab)
    e.AnimState:SetMultColour(0,0,0,.5)
    e.AnimState:UsePointFiltering(true)
    e.AnimState:Hide("ARM_carry"); e.AnimState:Show("ARM_normal")
    e.AnimState:Hide("HAT"); e.AnimState:Hide("HEAD_HAT")
    self.inst=e
    self:CopyAppearance()
    local x,y,z=owner.Transform:GetWorldPosition()
    e.Transform:SetPosition(x+3,y,z)
    self:SetState("idle",0,true)
end)
-- 对齐原版 shadowwaxwell 的点过滤，以及 player_common_extensions 的基础图层。
-- 皮肤刷新后重新清理帽内头发/头部变体，避免半透明重复部件叠成黑块。
function Actor:ApplyHumanLayers()
    local a=self.inst.AnimState
    for _,layer in ipairs({"ARM_carry","HAT","HAIR_HAT","HEAD_HAT","HEAD_HAT_NOHELM","HEAD_HAT_HELM"}) do a:Hide(layer) end
    for _,layer in ipairs({"ARM_normal","HAIR_NOHAT","HAIR","HEAD"}) do a:Show(layer) end
end
function Actor:CopyAppearance()
    if self.ghost then self:SetGhost(true,true);return end
    local a=self.inst.AnimState
    local look=self.frozen_appearance or Appearance.Read(self.owner)
    if self.appearance==look.signature then return end
    self.appearance=look.signature;self.last_human=look
    if self.form_bank~=look.bank then a:SetBank(look.bank);self.form_bank=look.bank;self.state=nil end
    a:SetBuild(look.build)
    if look.base and a.AssignItemSkins then
        local c=look.clothing
        a:AssignItemSkins(self.owner.userid,look.base,c.body or "",c.hand or "",c.legs or "",c.feet or "")
    end
    if SetSkinsOnAnim then
        SetSkinsOnAnim(a,self.owner.prefab,look.skin,look.clothing,nil,look.mode,look.build)
    else a:SetSkin(look.skin,look.build) end
    a:SetMultColour(0,0,0,.5)
    a:UsePointFiltering(true)
    self:ApplyHumanLayers()
end
function Actor:SetGhost(ghost,refresh)
    if self.ghost==ghost and not refresh then return end
    local a=self.inst.AnimState
    if ghost then
        local data=TheNet:GetClientTableForUser(self.owner.userid or "")
        local skin=data and GetSkinData and GetSkinData(data.base_skin or "")
        local build=skin and skin.skins and skin.skins.ghost_skin
        local current=self.owner.AnimState:GetBuild()
        local current_skin=self.owner.AnimState.GetSkinBuild and self.owner.AnimState:GetSkinBuild()
        local copy_current=self.owner:HasTag("playerghost") and not (self.ceremony and self.ceremony.kind=="amulet")
        if copy_current and current and current~="" then build=current end
        local skinbuild=copy_current and current_skin and current_skin~="" and current_skin or build
        build=build or self.ghostbuild or self.owner.ghostbuild or ("ghost_"..self.owner.prefab.."_build")
        skinbuild=skinbuild or build
        if self.ghost and self.ghostbuild==build and self.ghostskin==skinbuild then return end
        a:SetBank("ghost");a:SetBuild(build);a:SetSkin(skinbuild,build);a:SetMultColour(0,0,0,.5)
        self.ghostbuild=build;self.ghostskin=skinbuild;self.form_bank="ghost"
    else
        a:SetBank("wilson");self.ghost=false;self.appearance=nil;self:CopyAppearance()
    end
    self.ghost=ghost;self.state=nil;self:SetRate(1)
    a:PlayAnimation(ghost and "idle" or "idle_loop",true)
end
function Actor:RefreshAppearance()
    if self.ceremony or self.frozen_appearance or GetTime()<(self.next_look or 0) then return end
    self.next_look=GetTime()+.25;self:CopyAppearance()
end
function Actor:SetRate(rate)
    if not self.rate or math.abs(self.rate-rate)>.025 then
        self.inst.AnimState:SetDeltaTimeMultiplier(rate);self.rate=rate
    end
end
function Actor:SpeechTarget()
    if self.possessed then return self.owner end
    if self.speech_hidden or not self.inst:IsValid() then return nil end
    return self.inst
end
function Actor:SetState(state,duration,force)
    if self.ceremony and not force then return end
    if not force and GetTime()<(self.hold or 0) then return end
    if state~=self.state or force then
        local anim=C.animations[state] or C.animations.idle
        local name=anim[1]
        if self.ghost then name=(state=="tense" or state=="mourn") and "angry" or "idle" end
        self.inst.AnimState:PlayAnimation(name,self.ghost or anim[2])
        self.state=state
    end
    self.hold=GetTime()+(duration or 0)
end
function Actor:ClearCeremony()
    if self.carried then self.carried:Destroy(); self.carried=nil end
    if self.front then self.front:Destroy(); self.front=nil end
    if self.masked and self.owner:IsValid() then
        -- OverrideMultColour 为本机渲染覆盖，不更改网络颜色或服务器状态。
        self.owner.AnimState:OverrideMultColour(1,1,1,1)
    end
    self.masked=nil
    self.inst.Transform:SetScale(1,1,1)
    self:SetRate(1)
    self.inst.AnimState:SetFinalOffset(0)
    if self.ceremony and self.ceremony.kind=="amulet" and self.owner:IsValid() then
        local x,y,z=self.inst.Transform:GetWorldPosition()
        local _,ground=self.owner.Transform:GetWorldPosition()
        self.inst.Transform:SetPosition(x,ground,z)
    end
    self.inst:Show();self.speech_hidden=false
    self.ceremony=nil
    if self.owner:IsValid() then self:SetGhost(self.owner:HasTag("playerghost")) end
end
function Actor:BeginCeremony(kind,native)
    self:ClearCeremony()
    self.goal=nil; self.vx,self.vz=0,0
    self.ceremony={kind=kind,start=GetTime()}
    self.inst:Show()
    self:SetRate(1)
    if kind=="amulet" then
        local x,y,z=self.owner.Transform:GetWorldPosition()
        self.ceremony.anchor={x=x,y=y,z=z}
        local dx,dy,dz=self.inst.Transform:GetWorldPosition()
        self.ceremony.depart={x=dx,y=dy,z=dz}
        self.ceremony.clock=RebirthClock(self.owner,native or "amulet_rebirth")
        self.ceremony.phase="haunt"
        self:SetGhost(true)
        self.inst.AnimState:PlayAnimation("dissipate",false)
        self:SetRate(24/math.max(1,self.ceremony.clock.duration*.13*30))
        self.inst.AnimState:SetFinalOffset(-2)
        local frozen=Appearance.Read(self.owner)
        if self.owner:HasTag("playerghost") and frozen.build==self.ghostbuild and self.last_human then frozen=self.last_human end
        self.carried=Actor(self.owner,frozen)
        self.carried.inst.AnimState:PlayAnimation("wendy_resurrect",false)
        self.carried.inst.AnimState:AddOverrideBuild("wendy_resurrect")
        self.carried.inst.AnimState:OverrideSymbol("wormmovefx","mole_build","wormmovefx")
        self.carried.inst.AnimState:SetMultColour(1,1,1,1)
        self.carried.inst.AnimState:UsePointFiltering(false)
        self.carried.inst.AnimState:SetFinalOffset(0)
        self.carried:SetRate(0)
        self.carried.inst.AnimState:SetTime(self.ceremony.clock:Pose(self.ceremony.clock:Progress()))
        self.owner.AnimState:OverrideMultColour(1,1,1,0)
        self.masked=true
    elseif kind=="transition" then self:SetState("idle",0,true)
    elseif kind=="death" then
        self:SetGhost(true);self.ceremony=nil;self:SetState("idle",0,true)
    else self:SetState("follow",0,true) end
end
function Actor:Step(dt,runtime)
    local e=self.inst
    if not e:IsValid() then return end
    if not self.ceremony then self:SetGhost(runtime.dead or self.owner:HasTag("playerghost"));self:RefreshAppearance() end
    if self.ceremony then
        local v=self.ceremony; local t=GetTime()-v.start
        local x,y,z=self.owner.Transform:GetWorldPosition()
        if v.kind=="death" then
            local p=runtime.deathpos or {x=x,y=y,z=z}
            e.Transform:SetPosition(p.x+1,p.y,p.z)
            e:FacePoint(p.x,p.y,p.z)
            if t>4 then e:Hide(); self.speech_hidden=true; self.ceremony=nil end
        elseif v.kind=="transition" then
            e.Transform:SetPosition(x+1,y,z)
            local scale=math.max(.01,1-t*2)
            e.Transform:SetScale(scale,scale,scale)
            if t>1.5 then
                e.Transform:SetScale(1,1,1); self.ceremony=nil; self:SetState("idle",0,true)
            end
        elseif v.kind=="amulet" then
            local anchor=v.anchor
            local progress=v.clock:Progress()
            if (x-anchor.x)^2+(z-anchor.z)^2>1 or progress>=1 then
                self:ClearCeremony();self:SetState("idle",0,true);return
            end
            local pose=v.clock:Pose(progress)
            self.carried.inst.Transform:SetPosition(anchor.x,anchor.y,anchor.z)
            self.carried.inst.AnimState:SetTime(pose)
            if progress<.14 then
                -- 灵魂在原地作祟，不再跳入地下，也不移动到玩家脚下。
                e.Transform:SetPosition(v.depart.x,v.depart.y,v.depart.z)
            else
                if v.phase=="haunt" then
                    runtime.effects:Burst(v.depart.x,v.depart.y,v.depart.z,false)
                    e:Hide();self.speech_hidden=true;v.phase="buried"
                end
                local reveal=v.clock.name=="wendy_resurrect" and 86/172 or .20
                if progress>=reveal then
                    if v.phase=="buried" then
                        runtime.effects:Burst(anchor.x,anchor.y,anchor.z,true)
                        e.AnimState:PlayAnimation("shadowself_ghost_carry",false)
                        self:SetRate(1)
                        e:Show();self.speech_hidden=false;v.phase="carry"
                    end
                    e.Transform:SetPosition(anchor.x,anchor.y,anchor.z)
                    e.AnimState:SetTime(pose)
                end
            end
        else
            e.Transform:SetPosition(x+math.max(1.5,12-t*8),y,z)
            if t>1.3 and not v.relief then self:SetState("relief",0,true); v.relief=true end
            if t>3.5 then self.ceremony=nil; self:SetState("idle",0,true) end
        end
        return
    end
    e:Show();self.speech_hidden=false
    if runtime.wait then
        self.goal=nil; self.vx,self.vz=0,0
        self:SetRate(1); self:SetState("idle"); return
    end
    local px,py,pz=self.owner.Transform:GetWorldPosition()
    local x,y,z=e.Transform:GetWorldPosition()
    local now=GetTime()
    local distance=math.sqrt((px-x)^2+(pz-z)^2)
    local leash=runtime.options and runtime.options.leash or C.leash
    if distance>C.hard_teleport then
        e.Transform:SetPosition(px+4,py,pz); self.goal=nil; self.vx,self.vz=0,0
        return
    end
    -- 滞回：15码外才追赶，7码内停追；不会每帧把距离锁在3码。
    if distance>leash then self.catching=true end
    if self.catching and distance<math.min(C.catch_stop,leash*.5) then self.catching=false; self.goal=nil end
    local danger=now<(runtime.combat_until or 0)
    local observed=self.lastowner and math.sqrt((px-self.lastowner.x)^2+(pz-self.lastowner.z)^2)/dt or 0
    self.lastowner={x=px,z=pz}
    self.owner_speed=(self.owner_speed or 0)*.8+math.min(observed,15)*.2
    local speed=C.walk_speed
    if self.catching then
        self.goal={x=px,z=pz}; speed=math.min(11,math.max(6.5,self.owner_speed*1.12))
    elseif danger and distance<5 then
        local d=math.max(.01,distance)
        self.goal={x=px+(x-px)/d*8,z=pz+(z-pz)/d*8}
    elseif runtime.context.night and runtime.context.firepos then
        local f=runtime.context.firepos
        if not self.goal and (x-f.x)^2+(z-f.z)^2>9 then
            self.goal={x=f.x+2.5,z=f.z}; self.goal_until=now+8
        end
    elseif not self.goal and now>(self.decide_at or 0) then
        self.decide_at=now+4+math.random()*6
        -- 不追着主人的脚跟走，随机在附近短走、停留、张望。
        if math.random()<.65 then
            for attempt=1,8 do
                local angle=math.random()*2*math.pi
                local length=2+math.random()*4
                local gx,gz=x+math.cos(angle)*length,z+math.sin(angle)*length
                if (gx-px)^2+(gz-pz)^2<(leash-2)^2 and TheWorld.Map:IsPassableAtPoint(gx,0,gz) then
                    self.goal={x=gx,z=gz}; self.goal_until=now+6; break
                end
            end
        end
    end
    if self.goal and not self.catching and now>(self.goal_until or 0) then self.goal=nil end
    local vx,vz=0,0
    if self.goal then
        local dx,dz=self.goal.x-x,self.goal.z-z
        local d=math.sqrt(dx*dx+dz*dz)
        if d>.55 then vx,vz=dx/d*speed,dz/d*speed
        else
            self.goal=nil; self.decide_at=now+2+math.random()*5
        end
    end
    -- 速度渐变同时用于起步、制动和转向，避免位置伺服式的抽动。
    local blend=1-math.exp(-dt*6)
    self.vx=(self.vx or 0)+(vx-(self.vx or 0))*blend
    self.vz=(self.vz or 0)+(vz-(self.vz or 0))*blend
    local moving=math.sqrt(self.vx*self.vx+self.vz*self.vz)
    if self.walking then self.walking=moving>.08 else self.walking=moving>.25 end
    if self.walking then
        local nx,nz=x+self.vx*dt,z+self.vz*dt
        if self.ghost or TheWorld.Map:IsPassableAtPoint(nx,0,nz) then
            e.Transform:SetPosition(nx,py,nz); self.stuck=nil
        else
            self.stuck=self.stuck or now
            self.goal=nil; self.decide_at=now+.8
            if self.catching and now-self.stuck>C.stuck_time then
                for i=1,8 do
                    local angle=i*math.pi/4
                    local gx,gz=px+math.cos(angle)*6,pz+math.sin(angle)*6
                    if TheWorld.Map:IsPassableAtPoint(gx,0,gz) then
                        e.Transform:SetPosition(gx,py,gz); self.stuck=nil; self.catching=false; break
                    end
                end
            end
        end
        e:FacePoint(x+self.vx,y,z+self.vz)
        if not self.ceremony then
            self.hold=0
            self:SetState("follow")
            self:SetRate(math.max(.65,math.min(1.35,moving/6)))
        end
    else
        self.vx,self.vz=0,0
        self:SetRate(1)
        -- 跑步刚结束立即切回待机，不等下一次随机行为决策。
        if self.state=="follow" then self:SetState("idle",.4,true) end
        if now>(self.hold or 0) then
            if danger then self:SetState("tense",2)
            elseif runtime.context.night and runtime.context.firepos then
                e:FacePoint(runtime.context.firepos.x,y,runtime.context.firepos.z)
                self:SetState(math.random()<.5 and "sit" or "warm",5)
            elseif now>(self.idle_next or 0) then
                local states={"idle","look","sit"}
                self:SetState(states[math.random(#states)],3+math.random()*3)
                self.idle_next=now+5+math.random()*7
            end
        end
    end
end
function Actor:Destroy()
    self:ClearCeremony()
    if self.inst and self.inst:IsValid() then self.inst:Remove() end
end
return Actor
