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
        -- 威胁扫描含睡眠陷阱狗；选为攻击目标前仍须遵守战斗层许可。
        if e.prefab=="icehound" and live(e) and c.bridge.allowed(e) and e:GetPosition():DistSq(wp)<20^2 then
            local d=pos:DistSq(e:GetPosition());if not near or d<near then dog,near=e,d end
        end
    end
    if dog then
        self.walrus_stage="retreat";self.walrus_since=GetTime();self.walrus_outside=nil;self.walrus_calm=nil;self:Release()
        return "attack",self:Target(dog)
    end
    self:Target(walrus)
    -- 角斗场强制仇恨且有场地边界：清醒冰狗优先，其后直接近身压制海象。
    if c.plan and c.plan.arena then self:Release();return "attack",walrus end
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
    local tools=require("shadowself/control/arena_tools")
    for _,i in ipairs(A.Items(c.player)) do if i.prefab=="panflute" and tools.Usable(i) then flute=i;break end end
    if not flute then
        if c.plan and c.plan.arena and tools.Recover(c,"panflute") then return "support",nearest end
        return
    end
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
    if c.plan and c.plan.arena then
        self.arena_goats=self.arena_goats or require("shadowself/control/arena_goats")(self)
        local mode,picked=self.arena_goats:Tick(goats)
        if mode then return mode,picked end
    end
    if c.arena_goat_melee and c.plan and c.plan.arena_wave and c.plan.arena_wave()==6 then
        local straw
        for _,item in ipairs(A.Items(c.player)) do
            local eq=item.replica and item.replica.equippable
            if item.prefab=="strawhat" and item:IsValid() and not item:HasTag("broken") and eq
                and eq:EquipSlot()==EQUIPSLOTS.HEAD and not (eq.IsRestricted and eq:IsRestricted(c.player)) then straw=item;break end
        end
        if straw then
            c.gear.protected_slots={[EQUIPSLOTS.HEAD]=true}
            if c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)~=straw then
                c.bridge:PauseAttack();c.mechanisms:Equip(straw);return "support",target
            end
        elseif charged and self:Insulate(goats) then return "support",target end
        local best,near;local pos=c.player:GetPosition()
        for _,e in ipairs(goats) do local d=pos:DistSq(e:GetPosition());if not near or d<near then best,near=e,d end end
        self:Release();return "attack",self:Target(best or target)
    end
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
-- 兔王及召唤物沿用正常武器/走位；选中小兔人时也不能落入通用旋风清群。
function Encounters:RabbitMelee(target)
    local plan=self.c.plan
    if not plan or not plan.arena then return false end
    local function rabbit(e)
        return live(e) and (e.prefab=="rabbitking_aggressive" or e.prefab=="rabbitkingminion_bunnyman")
    end
    if rabbit(target) then return true end
    for _,list in ipairs({self.c.enemies or {},plan.arena_remaining and plan.arena_remaining() or {}}) do
        for _,e in ipairs(list) do if rabbit(e) then return true end end
    end
    return false
end
function Encounters:Tick(target)
    local patrol_mode,patrol_target=self:Patrol(target)
    if patrol_mode then return patrol_mode,patrol_target end
    local hunt=self.c.plan and self.c.plan.arena_walrus
    if hunt and hunt.active and hunt.target then self:Release();return "attack",self:Target(hunt.target) end
    local whip=self.c.plan and self.c.plan.arena_whip_state
    if whip and whip.active and require("shadowself/control/arena_tools").Recover(self.c,"whip",function(item)
        return whip.active and whip:CanPickup(self.c.player,item)
    end) then
        if whip.moving then self.c.travel:EndDodge(self.c.snapshot);whip.moving=nil end
        return "support",target
    end
    if whip and whip:Evade(self.c) then return "move",target end
    if whip and whip.active and not whip:CanAttack(self.c.player) then return "support",target end
    local previous_wind=self.c.arena_wind;self.c.arena_wind=nil
    self.c.bridge.priority_target=self.c.plan and self.c.plan.arena_priority and self.c.plan.arena_priority() or nil;self.allowed={}
    if target.prefab~="lightninggoat" then self.c.gear.protected_slots=nil end
    if self.walrus and live(self.walrus) then self.allowed[self.walrus]=true end
    local mode,picked
    if self.c.plan and self.c.plan.arena then
        self.arena_hunts=self.arena_hunts or require("shadowself/control/arena_hunts")(self)
        mode,picked=self.arena_hunts:Tick(target)
    end
    if not mode then mode,picked=self:Walrus(target) end
    if not mode then mode,picked=self:Penguins(target) end
    if not mode then mode,picked=self:Goats(target) end
    if not mode and self.c.plan and self.c.plan.arena and not self.c.plan.arena_stage11 and not self:RabbitMelee(target)
     and not require("shadowself/control/arena_bats").Active(self.c)
     and not (self.c.plan.arena_spider_scene and self.c.plan.arena_spider_scene())
     and not (whip and whip.active and self.c.plan.arena_wave and self.c.plan.arena_wave()==2) then
        local crowd={};local policy=require("shadowself/control/targetpolicy")
        for _,e in ipairs(self.c.enemies) do
            if live(e) and policy.Creature(e) and not policy.Boss(e) and self.c.bridge.allowed(e) then crowd[#crowd+1]=e end
        end
        if #crowd>=4 and not policy.Boss(target) then
            self.arena_crowd=self.arena_crowd or require("shadowself/control/arena_goats")(self,"群怪")
            mode,picked=self.arena_crowd:Tick(crowd)
        end
    end
    if previous_wind and previous_wind~=self.c.arena_wind then previous_wind:Stop() end
    if not mode then self:Release() end
    return mode,picked
end
function Encounters:Patrol(target)
 local Rabbit=require("shadowself/control/arena_rabbit")
 if self.rabbit or Rabbit.Required(self.c) then
  self.rabbit=self.rabbit or Rabbit(self)
  local mode,picked=self.rabbit:Tick();if mode then return mode,picked end
 end
 local mode,picked=self:Salamanders();if mode then return mode,picked end
 mode,picked=require("shadowself/control/arena_swamp").Tick(self);if mode then return mode,picked end
 local c=self.c;local wave=c.plan and c.plan.arena and c.plan.arena_wave and c.plan.arena_wave()
 if wave==5 then
  self.arena_hunts=self.arena_hunts or require("shadowself/control/arena_hunts")(self)
  return self.arena_hunts:Pirates(c.plan.arena_remaining and c.plan.arena_remaining() or c.enemies)
 elseif wave==6 then
  for _,e in ipairs(c.enemies) do if e.prefab=="lightninggoat" and live(e) then return self:Goats(e) end end
 end
end
function Encounters:Salamanders()
 local policy=require("shadowself/control/arena_salamanders")
 if not self.salamanders and not policy.Required(self.c) then return end
 self.salamanders=self.salamanders or policy(self)
 return self.salamanders:Tick()
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
function Encounters:Stop() if self.rabbit then self.rabbit:Stop() end;if self.c.arena_wind then self.c.arena_wind:Stop() end;self:Release();self.c.gear.protected_slots=nil end
return Encounters
