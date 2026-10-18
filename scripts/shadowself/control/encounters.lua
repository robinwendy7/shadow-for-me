-- 特定生物战术只在获准战斗目标上生效，普通怪仍走原DoDodge。
local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local Encounters=Class(function(self,c) self.c=c;self.allowed={};self.next_flute=0 end)
local function live(e) return e and e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") end
local function distance(a,b) return math.sqrt(a:DistSq(b)) end
local function anim(e,name) return e.AnimState and e.AnimState:IsCurrentAnimation(name) end
local function penguin(e) return e.prefab=="penguin" or e.prefab=="mutated_penguin" end
local function sliding(e) return not e:HasTag("sleeping") and (anim(e,"slide_loop") or anim(e,"slide_bounce")) end
local insulated={rainhat=true,eyebrellahat=true,balloonhat=true,wagpunkhat=true,raincoat=true,armorwagpunk=true}
function Encounters:Target(e)
    self.allowed[e]=true;self.c.bridge.priority_target=e;self.c.target=e
    return e
end
function Encounters:Move(point,label,primary)
    local c=self.c;c.bridge:PauseAttack()
    if c.travel then c.travel:BeginDodge(c.snapshot) end
    c:Move(Nav.Select(c,point,primary),label)
    self.moving=true;return "move"
end
function Encounters:Release()
    if self.moving and self.c.travel then self.c.travel:EndDodge(self.c.snapshot) end
    self.moving=nil
end
function Encounters:Away(e,step,label)
    local p=self.c.player:GetPosition();local ep=e:GetPosition();local d=distance(p,ep)
    local dx,dz=p.x-ep.x,p.z-ep.z;if d<.01 then dx,dz,d=1,0,1 end
    return self:Move(Vector3(p.x+dx/d*step,0,p.z+dz/d*step),label,e)
end
function Encounters:Walrus(target)
    local c=self.c;local walrus=target.prefab=="walrus" and target or self.walrus
    if not live(walrus) then
        walrus=nil
        for _,e in ipairs(c.enemies) do if e.prefab=="walrus" and c.bridge.allowed(e) then walrus=e;break end end
    end
    if not walrus then self.walrus=nil;self.walrus_stage=nil;return end
    if self.walrus~=walrus then self.walrus=walrus;self.walrus_stage="retreat";self.walrus_since=GetTime();self.walrus_outside=nil;self.walrus_calm=nil end
    self.allowed[walrus]=true
    local dog,near
    local wp=walrus:GetPosition();local pos=c.player:GetPosition()
    for _,e in ipairs(c.enemies) do
        if e.prefab=="icehound" and live(e) and e:GetPosition():DistSq(wp)<20^2 then
            local d=pos:DistSq(e:GetPosition());if not near or d<near then dog,near=e,d end
        end
    end
    if dog then
        self.walrus_stage="retreat";self.walrus_since=GetTime();self.walrus_outside=nil;self.walrus_calm=nil;self:Release()
        return "attack",self:Target(dog)
    end
    self:Target(walrus)
    if self.walrus_stage=="retreat" then
        local outside=math.max(TUNING.WALRUS_DART_RANGE or 25,TUNING.WALRUS_LOSETARGET_DIST or 30)+1.5
        if distance(pos,wp)>=outside then self.walrus_outside=true end
        local combat=walrus.replica and walrus.replica.combat
        local opponent=combat and combat.GetTarget and combat:GetTarget()
        local wandering=anim(walrus,"walk_loop") or anim(walrus,"walk_pre") or anim(walrus,"walk_pst")
            or anim(walrus,"idle_loop") or anim(walrus,"idle_happy") or anim(walrus,"idle_angry")
        if self.walrus_outside and opponent==nil and wandering then
            self.walrus_calm=self.walrus_calm or GetTime()
            if GetTime()-self.walrus_calm>=.25 then self.walrus_stage="rush";self:Release()
            else return "support",walrus end
        else
            self.walrus_calm=nil
            return self:Away(walrus,5,"海象 · 持续拉脱仇恨，等它恢复闲庭信步"),walrus
        end
    end
    self:Release();return "attack",walrus
end
function Encounters:Penguins(target)
    local c=self.c;local birds={};local nearest,near
    for _,e in ipairs(c.enemies) do if penguin(e) and live(e) and c.bridge.allowed(e) and sliding(e) then
        birds[#birds+1]=e;local d=distance(c.player:GetPosition(),e:GetPosition())
        if not near or d<near then near,nearest=d,e end
    end end
    if self.bird_wait then
        local sleeping
        for _,e in ipairs(self.bird_targets or {}) do if live(e) and e:HasTag("sleeping") then sleeping=e;break end end
        if sleeping and not c.player.components.playercontroller:IsBusy() then
            self.bird_wait=nil;self:Release();return "attack",self:Target(sleeping)
        end
        if GetTime()<self.bird_wait or c.player.components.playercontroller:IsBusy() then return "support",target end
        self.bird_wait=nil
    end
    if #birds==0 then return end
    local flute
    for _,i in ipairs(A.Items(c.player)) do if i.prefab=="panflute" then flute=i;break end end
    if not flute then return end
    self:Target(nearest)
    local now=GetTime()
    if self.bird_wait then
        if now<self.bird_wait then return "support",nearest end
        self.bird_wait=nil
    end
    if near<9 then return self:Away(nearest,4,"企鹅 · 先拉开滑行冲撞距离"),nearest end
    if near<=(TUNING.PANFLUTE_SLEEPRANGE or 15)-1 and now>=self.next_flute
        and not c.player.components.playercontroller:IsBusy() then
        c.bridge:PauseAttack();self:Release()
        if A.Self(c.player,flute,ACTIONS.PLAY) then
            self.next_flute=now+3;self.bird_wait=now+3;self.bird_targets=birds;return "support",nearest
        end
    end
    -- 不因排箫冷却永久禁攻；仍由专属滑行躲避表处理。
end
function Encounters:Insulate(goats)
    local c=self.c;local choices={};c.gear.protected_slots={}
    for _,i in ipairs(A.Items(c.player)) do
        local eq=i.replica and i.replica.equippable
        local real=i.components and i.components.equippable
        if eq and not i:HasTag("broken") and (insulated[i.prefab] or i:HasTag("insulated") or real and real.IsInsulated and real:IsInsulated())
            and not (eq.IsRestricted and eq:IsRestricted(c.player)) then
            local slot=eq:EquipSlot()
            if slot==EQUIPSLOTS.HEAD or slot==EQUIPSLOTS.BODY then
                local rank=(i:HasTag("armor") or i.prefab=="armorwagpunk" or i.prefab=="wagpunkhat") and 20 or 10
                if c.player.replica.inventory:GetEquippedItem(slot)==i then rank=rank+1 end
                if not choices[slot] or rank>choices[slot].rank or rank==choices[slot].rank and (i.GUID or 0)<(choices[slot].item.GUID or 0) then choices[slot]={item=i,rank=rank} end
            end
        end
    end
    for slot in pairs(choices) do c.gear.protected_slots[slot]=true end
    for _,slot in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
        local choice=choices[slot]
        if choice then
            c.gear.protected_slots[slot]=true
            if c.player.replica.inventory:GetEquippedItem(slot)~=choice.item then
                c.bridge:PauseAttack();c.mechanisms:Equip(choice.item);return true
            end
        end
    end
end
function Encounters:Goats(target)
    if target.prefab~="lightninggoat" then self.goat=nil;self.c.gear.protected_slots=nil;return end
    local c=self.c;local goats={};local charged=false
    for _,e in ipairs(c.enemies) do if e.prefab=="lightninggoat" and live(e) and c.bridge.allowed(e) then
        goats[#goats+1]=e;charged=charged or e:HasTag("charged")
    end end
    if charged and self:Insulate(goats) then return "support",target end
    if #goats<2 then self.goat=nil;self:Release();return end
    local now=GetTime();local pos=c.player:GetPosition();local state=self.goat
    if not state then
        local x,z=0,0;for _,e in ipairs(goats) do local p=e:GetPosition();x=x+p.x;z=z+p.z end
        state={phase=#goats>=3 and "gather" or "bait",since=now,center=Vector3(x/#goats,0,z/#goats)};self.goat=state
    end
    local active=false
    for _,e in ipairs(goats) do if (c.observed[e.GUID] or {}).dodge then active=true;break end end
    if active then state.phase="punish";state.last_attack=now;self:Release() end
    if state.phase=="gather" then
        if now-state.since>2.4 then state.phase="bait";state.since=now
        else
            local center=state.center;local angle=math.atan2(pos.z-center.z,pos.x-center.x)+.4
            return self:Move(Vector3(center.x+math.cos(angle)*7,0,center.z+math.sin(angle)*7),"电羊 · 短时间圆周聚拢",target),target
        end
    end
    if state.phase=="bait" then
        if now-state.since>1.2 then state.phase="punish";self:Release()
        else
            local ep=target:GetPosition();local d=math.max(.01,distance(pos,ep));local edge=(TUNING.LIGHTNING_GOAT_ATTACK_RANGE or 3)+.1
            return self:Move(Vector3(ep.x+(pos.x-ep.x)/d*edge,0,ep.z+(pos.z-ep.z)/d*edge),"电羊 · 贴前缘骗招",target),target
        end
    end
    local best,score
    for _,e in ipairs(goats) do if not (c.observed[e.GUID] or {}).dodge then
        local q=e:GetPosition();local value=pos:DistSq(q)+(e==c.bridge.priority_target and -1 or 0)
        if Nav.Safe(c,q,e) and (not score or value<score) then best,score=e,value end
    end end
    self:Release();return "attack",self:Target(best or target)
end
function Encounters:Tick(target)
    self.c.bridge.priority_target=nil;self.allowed={}
    if target.prefab~="lightninggoat" then self.c.gear.protected_slots=nil end
    if self.walrus and live(self.walrus) then self.allowed[self.walrus]=true end
    local mode,picked=self:Walrus(target)
    if not mode then mode,picked=self:Penguins(target) end
    if not mode then mode,picked=self:Goats(target) end
    if not mode then self:Release() end
    return mode,picked
end
function Encounters:Dodge(target,base)
    if not penguin(target) or target:HasTag("sleeping") then return base end
    local slide=sliding(target);local a=target.AnimState
    local pre=anim(target,"atk_pre") and (a:GetCurrentAnimationFrame() or 0)<15
    if slide or pre then
        self.bird_data=self.bird_data or {}
        local data=self.bird_data[target]
        if not data then
            data={point="target",update=true,angle=0,atkanim=function(e) return require("shadowself/native").Get().ENT_util:GetAnimation(e) end}
            self.bird_data[target]=data
        end
        data.dist=slide and 6 or (TUNING.PENGUIN_ATTACK_DIST or 3)+self.c.player:GetPhysicsRadius(0)+.6
        return data
    end
    return base
end
function Encounters:Stop() self:Release();self.c.gear.protected_slots=nil end
return Encounters
