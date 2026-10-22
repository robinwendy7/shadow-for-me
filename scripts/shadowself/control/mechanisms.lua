-- 本机源码：SGmoonspore / sand_spike / SGsharkboi / SGklaus / SGwagboss_robot。
local A=require("shadowself/control/actions")
local Nav=require("shadowself/control/navigation")
local Mechanisms=Class(function(self,c)
    self.c=c;self.first_seen={};self.hidden={};self.shields={}
    self.last_body=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    -- 接管前已装备的骨甲冷却未知：等满一个完整CD，而非套首次装备CD。
    if self.last_body and self.last_body.prefab=="armorskeleton" then self.bone_ready=GetTime()+(TUNING.ARMOR_SKELETON_COOLDOWN or 5) end
end)
local function anim(e,name) return e.AnimState and e.AnimState:IsCurrentAnimation(name) end
local function frame(e) return e.AnimState:GetCurrentAnimationFrame() or 0 end
local function parent(e) return e.entity and e.entity:GetParent() end
function Mechanisms:Item(name)
    for _,i in ipairs(A.Items(self.c.player)) do if i.prefab==name then return i end end
end
function Mechanisms:Equip(item)
    local p=self.c.player;local eq=item and item.replica and item.replica.equippable
    if not eq then return false end
    if p.replica.inventory:GetEquippedItem(eq:EquipSlot())==item then return true end
    if GetTime()>=(self.next_equip or 0) then
        if A.Self(p,item,ACTIONS.EQUIP) then self.next_equip=GetTime()+.35 end
    end
    return false
end
function Mechanisms:Scan()
    local c=self.c;local p=c.player:GetPosition();local now=GetTime()
    self.zones={};self.missiles=0;self.robot=nil;local seen={}
    local entities=TheSim:FindEntities(p.x,0,p.z,48)
    if c.bosses then
        c.bosses.entities=entities
        for _,zone in ipairs(c.bosses:Zones(entities)) do self.zones[#self.zones+1]=zone end
    end
    if c.plan and c.plan.arena then
        for _,z in ipairs(require("shadowself/control/arena_fire").Zones(c.player,entities)) do self.zones[#self.zones+1]=z end
    end
    for _,e in ipairs(entities) do if e:IsValid() then
        local name=e.prefab or "";seen[e]=true
        if name=="spore_moon" and (anim(e,"rumble") or anim(e,"explode") and frame(e)<4) then
            -- rumble is a loop: use elapsed observation time, not its wrapping frame.
            self.first_seen[e]=self.first_seen[e] or now
            local remaining=26/30-(now-self.first_seen[e])
            local radius=(TUNING.MOONSPORE_ATTACK_RANGE or 3)+c.player:GetPhysicsRadius(0)+.3
            local exit=math.max(0,radius-math.sqrt(p:DistSq(e:GetPosition())))/math.max(1,c:Speed())
            if remaining<=exit+.3 or anim(e,"explode") then self.zones[#self.zones+1]={pos=e:GetPosition(),radius=radius,source=e} end
        elseif name:find("sandspike_",1,true)==1 then
            local pre=anim(e,"short_pre") or anim(e,"med_pre") or anim(e,"tall_pre")
            if not anim(e,"short_pst") and not anim(e,"med_pst") and not anim(e,"tall_pst") then
                local r=name=="sandspike_tall" and .6 or name=="sandspike_med" and .4 or .2
                self.zones[#self.zones+1]={pos=e:GetPosition(),radius=r+.5+c.player:GetPhysicsRadius(0)+.25,source=e}
            end
        elseif name=="sandblock" and not self.hidden[e] then
            self.hidden[e]=e.AnimState.GetMultColour and {e.AnimState:GetMultColour()} or {1,1,1,1}
            e.AnimState:SetMultColour(1,1,1,0) -- 本地视觉；保留碰撞和真实沙堡。
        elseif name=="sharkboi" and (anim(e,"icedive_jump_pre") or anim(e,"icedive_jump") or anim(e,"icedive_dig_pre") or anim(e,"spawn") and frame(e)<20) then
            -- 地下钻出前不可索敌，也必须从机制扫描直接启动避让。
            self.zones[#self.zones+1]={pos=e:GetPosition(),radius=2+c.player:GetPhysicsRadius(0)+.6,source=e}
        elseif name=="wagboss_robot" then self.robot=e
        elseif name=="wagboss_missile" then self.missiles=self.missiles+1
        elseif name:find("shadow_shield",1,true)==1 and (parent(e)==c.player.entity or parent(e)==c.player) and not self.shields[e] then
            self.shields[e]=true;self.bone_ready=now+(TUNING.ARMOR_SKELETON_COOLDOWN or 5);self.bone_consumed=now
        end
        if name=="sharkboi" then
            for _,zone in ipairs(require("shadowself/control/sharkroute").IceZones(c,e)) do self.zones[#self.zones+1]=zone end
        end
        if name~="spore_moon" or not anim(e,"rumble") then self.first_seen[e]=nil end
    end end
    for e in pairs(self.first_seen) do if not seen[e] then self.first_seen[e]=nil end end
    local body=c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    if body~=self.last_body then
        self.last_body=body
        if body and body.prefab=="armorskeleton" then self.bone_ready=now+(TUNING.ARMOR_SKELETON_FIRST_COOLDOWN or 1) end
    end
end
function Mechanisms:Escape()
    local c=self.c;local p=c.player:GetPosition();local danger=false
    for _,z in ipairs(self.zones) do if p:DistSq(z.pos)<z.radius^2 then danger=true;break end end
    if not danger then self.ant_escape=nil;return false end
    local best,score;local original=c.hazards
    c.hazards={};for _,z in ipairs(original or {}) do c.hazards[#c.hazards+1]=z end
    for _,z in ipairs(self.zones) do c.hazards[#c.hazards+1]=z end
    local target=c.h and c.h.ent
    if target and target.prefab=="antlion" and c.bosses then
        c.bosses.routes:RememberAnt()
        local saved=self.ant_escape
        if saved and saved.target==target and p:DistSq(saved.point)>.35^2 and Nav.Safe(c,saved.point,target) then best=saved.point
        else best=c.bosses.routes:AntPoint(target);self.ant_escape={target=target,point=best} end
        c.travel:BeginDodge(c.snapshot);c:Move(best,"蚁狮 · 沿可通行圆周按序躲地刺")
        c.hazards=original;self.escaping=true;return true
    end
    for i=0,23 do
        local a=i*math.pi/12;local q=Vector3(p.x+math.cos(a)*3,0,p.z+math.sin(a)*3)
        local risk=Nav.Risk(c,q)
        if c.actions:SafePoint(q) and (not score or risk<score) then best,score=q,risk end
    end
    if best then best=Nav.Escape(c,best) or best;c.travel:BeginDodge(c.snapshot);c:Move(best,"避开即将爆发的孢子／地刺") end
    c.hazards=original;self.escaping=true;return true
end
function Mechanisms:Missile()
    local c=self.c;local p=c.player;local robot=self.robot or self.missile_robot
    if not robot or not robot:IsValid() then return false end
    local firing=false
    for _,a in ipairs({"atk_missile_pre1","atk_missile_pre2","atk_missile","atk_missile_idle","atk_missile_hit","atk_missile_pst"}) do if anim(robot,a) then firing=true;break end end
    local shell=self:Item("armorsnurtleshell");local staff=self:Item("orangestaff")
    if not self.missile_phase and firing and shell then
        self.missile_robot=robot;self.missile_phase=staff and "teleport" or "equip"
        self.old_body=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
    end
    if not self.missile_phase then return false end
    local now=GetTime()
    if firing or self.missiles>0 then self.quiet_since=nil else self.quiet_since=self.quiet_since or now end
    if self.quiet_since and now-self.quiet_since>.8 then
        if self.old_body and self.old_body:IsValid() then self:Equip(self.old_body)
        elseif shell then A.Self(p,shell,ACTIONS.UNEQUIP) end
        self.missile_phase=nil;self.missile_robot=nil;self.teleported=nil;self.teleport_origin=nil;c.bridge.resume_target=robot;return false
    end
    if self.missile_phase=="teleport" then
        self.teleport_origin=self.teleport_origin or p:GetPosition()
        if self.teleported then
            if p:GetPosition():DistSq(self.teleport_origin)>9 or now-(self.teleport_sent or now)>2 then self.missile_phase="equip";self.teleport_origin=nil end
        elseif self:Equip(staff) and not p.components.playercontroller:IsBusy() then
            local ep=robot:GetPosition();local pos=p:GetPosition();local d=math.max(.1,math.sqrt(pos:DistSq(ep)))
            for _,angle in ipairs({0,math.pi/4,-math.pi/4,math.pi/2,-math.pi/2}) do
                local dx,dz=(pos.x-ep.x)/d,(pos.z-ep.z)/d
                local q=Vector3(pos.x+(dx*math.cos(angle)-dz*math.sin(angle))*12,0,pos.z+(dx*math.sin(angle)+dz*math.cos(angle))*12)
                if c.actions:SafePoint(q) and A.Ground(p,q,ACTIONS.BLINK) then self.teleported=true;self.teleport_sent=now;break end
            end
        end
    elseif self:Equip(shell) then
        -- USEITEM activates the original shell state; do not move/attack out of it.
        if not p:HasTag("shell") and not anim(p,"shell_idle") and now>=(self.next_shell or 0) then
            if A.Self(p,shell,ACTIONS.USEITEM) then self.next_shell=now+.4 end
        end
    end
    c.blocked=true;return true
end
local protection={footballhat=.8,armorwood=.8,armorgrass=.6,armormarble=.95,armorruins=.9,ruinshat=.9,
    armordreadstone=.9,dreadstonehat=.9,voidclothhat=.8,armor_voidcloth=.8,armorskeleton=1,
    armor_sanity=.95,armordragonfly=.7,armorsnurtleshell=.6,slurtlehat=.9,alterguardianhat=.8,armor_bramble=.65}
local function armour_score(item)
    if not item then return -1 end
    local base=protection[item.prefab]
    if not base and item:HasTag("armor") then base=.6 end
    if not base then return nil end
    local ii=item.replica and item.replica.inventoryitem
    local percent=ii and ii.GetPercentUsed and ii:GetPercentUsed() or 1
    return base*100+(percent or 1)*5
end
function Mechanisms:Pickup()
    local c=self.c;local p=c.player;local now=GetTime();local hand=p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and hand:HasTag("weapon") and hand.prefab~="cane" and hand.prefab~="orangestaff" then self.last_weapon=hand end
    if self.pickup and self.pickup:IsValid() and not parent(self.pickup) and not self.pickup:HasTag("INLIMBO") then
        if now<(self.pickup_until or 0) then return true end
        self.pickup=nil
    end
    if self.picked and self.picked:IsValid() and c.gear:Owned(self.picked) then
        local item=self.picked;self.picked=nil
        if item.replica.equippable:EquipSlot()~=EQUIPSLOTS.HANDS then self:Equip(item) else c.gear:Swap("attack",c.snapshot) end
    end
    if now<(self.next_pickup or 0) then return false end
    self.next_pickup=now+.3
    local pos=p:GetPosition();local chosen,score
    for _,item in ipairs(TheSim:FindEntities(pos.x,0,pos.z,8,{"_inventoryitem"},{"INLIMBO"})) do
        local eq=item.replica and item.replica.equippable
        local armour=armour_score(item)
        local current=eq and p.replica.inventory:GetEquippedItem(eq:EquipSlot())
        local protected=eq and c.gear.protected_slots and c.gear.protected_slots[eq:EquipSlot()]
        local upgrade=not protected and armour and armour>(armour_score(current) or 0)+.1
        if eq and not parent(item) and (item==self.last_weapon or upgrade) and not item:HasTag("broken")
            and not (eq.IsRestricted and eq:IsRestricted(p)) and Nav.Safe(c,item:GetPosition()) then
            local value=pos:DistSq(item:GetPosition())+(item==self.last_weapon and -100 or 0)
            if not score or value<score then chosen,score=item,value end
        end
    end
    if chosen and A.Scene(p,chosen,ACTIONS.PICKUP) then
        self.pickup=chosen;self.picked=chosen;self.pickup_until=now+math.sqrt(pos:DistSq(chosen:GetPosition()))/math.max(1,c:Speed())+1
        return true
    end
    return false
end
function Mechanisms:Honey()
 local c=self.c;local p=c.player:GetPosition();local inside=false
 for _,z in ipairs(c.hazards or {}) do if z.honey and p:DistSq(z.pos)<z.radius^2 then inside=true;break end end
 if not inside then return false end
 local q=Nav.Escape(c,Vector3(p.x+4,0,p.z),c.h.ent)
 if q then c.bridge:PauseAttack();c.travel:BeginDodge(c.snapshot);c:Move(q,"蜂后 · 先走出减速蜂蜜，再恢复拉扯或攻击");self.escaping=true;return true end
 return false
end
function Mechanisms:Incoming()
 local c=self.c
 local q=require("shadowself/control/incoming").Point(c,c.bosses and c.bosses.entities or c.enemies)
 if q then c.bridge:PauseAttack();c.travel:BeginDodge(c.snapshot);c:Move(q,"群战 · 优先横移躲侧方冲刺／飞踢");self.incoming=true;return true end
 if self.incoming then c.travel:EndDodge(c.snapshot);self.incoming=nil end
 return false
end
function Mechanisms:Tick()
    self:Scan()
    local retained={}
    for _,z in ipairs(self.c.hazards) do if not z.mechanism then retained[#retained+1]=z end end
    self.c.hazards=retained
    for _,z in ipairs(self.zones) do z.mechanism=true;self.c.hazards[#self.c.hazards+1]=z end
    local queen=self.c.beequeen
    if queen and queen.phase==1 and queen.queen and queen.queen:IsValid() then
        local native=self.c.bridge.OwnsThread and self.c.bridge:OwnsThread()
        if not native or queen.casting_guard or queen.guard_escape then
            if require("shadowself/control/guarddefence").Tick(queen,queen.queen,GetTime()) then return true end
        elseif require("shadowself/control/guardposition").Windup(queen.queen) then
            -- 原生线程已经负责这次闪避，离蜜流程不能抢走它的方向。
            return false
        end
    end
    if self:Incoming() or self:Honey() then return true end
    local primary=self.c.h and self.c.h.ent
    if self.c.bosses then
        local bomb=self.c.bosses:BombPoint()
        if bomb then self.c.bridge:PauseAttack();self.c.travel:BeginDodge(self.c.snapshot);self.c:Move(bomb,"蛤蟆 · 提前带走身上的蘑菇炸弹，持续移动至落地");return true end
        self.c.bosses:MoonHolding()
        if self.c.bosses.routes:Leap(primary) then return false end
    end
    local spinning=primary and primary.prefab=="alterguardian_phase2" and (anim(primary,"attk_spin_pre") or anim(primary,"attk_spin_loop"))
    local line=not spinning and self.c.bosses and self.c.bosses:MoonPair(primary)
    if line then
        self.c.bridge:PauseAttack();self.c.travel:BeginDodge(self.c.snapshot)
        self.c.bosses.moving=true;self.c:Move(line,"天体二 · 锁定最近一对月灵，躲完本对才处理下一对")
        return true
    end
    if self:Missile() then return true end
    if self:Escape() then return true end
    if self.escaping then self.c.travel:EndDodge(self.c.snapshot);self.escaping=nil end
    local target=self.c.h and self.c.h.ent
    if target and target.prefab=="klaus" then
        local bone=self:Item("armorskeleton")
        local observed=self.c.observed[target.GUID]
        if bone and self.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)~=bone
            and not (observed and observed.dodge) and not self.c.player.components.playercontroller:IsBusy() then
            self:Equip(bone);return true
        end
    end
    if self.c.plan and self.c.plan.arena and require("shadowself/control/arena_tools").Recover(self.c,"panflute") then return true end
    return self:Pickup()
end
function Mechanisms:Dodge(target,base)
    local c=self.c;local name=target.prefab;local a=target.AnimState
    if name=="sharkboi" then
        return require("shadowself/control/sharkroute").Dodge(c,target,base)
    elseif name=="klaus" then
        local chomp=anim(target,"attack_chomp");local claws=anim(target,"attack_doubleclaw");local f=frame(target)
        local state=self.klaus_chomp
        if chomp then
            local now=GetTime()
            if not state or state.target~=target or f<(state.frame or 0) then state={target=target,since=now};self.klaus_chomp=state end
            state.frame=f
            local bone=self:Item("armorskeleton")
            local cooldown=bone and bone.components and bone.components.cooldown
            local ready=cooldown and cooldown:IsCharged() or not cooldown and bone and now>=(self.bone_ready or math.huge)
            local fuel=bone and bone.components and bone.components.fueled
            local ii=bone and bone.replica and bone.replica.inventoryitem;local net=ii and ii.classified and ii.classified.percentused
            if fuel and fuel:IsEmpty() or net and net:value()<=0 then ready=false end
            if self.bone_consumed and self.bone_consumed>=state.since then state.used=true;state.armed=nil end
            if not state.used and f<35 and ready and self:Equip(bone) then state.armed=true end
            if state.armed and not state.used and f<=35 then self.tanking_chomp=target;return false end
            self.tanking_chomp=nil
        elseif claws and state and state.target==target then
            self.tanking_chomp=nil
            if f>28 then self.klaus_chomp=nil;return false end
        else
            if state and state.target==target then self.klaus_chomp=nil;self.tanking_chomp=nil end
            return base
        end
        -- 整段扑咬由这里独占：无骨甲径向躲；骨甲抵挡后径向躲二连，绝不返回推挤旧表。
        local radius=(TUNING.KLAUS_HIT_RANGE or 3)*4/3+c.player:GetPhysicsRadius(0)+.5
        local data={atkanim=chomp and "attack_chomp" or "attack_doubleclaw",point="target",dist=radius,update=true,noattack=true,exclusive=true}
        data.fn=function()
            local p=c.player:GetPosition();local q=target:GetPosition();local d=math.sqrt(p:DistSq(q))
            if d>=radius then return p end
            local dx,dz=p.x-q.x,p.z-q.z;if d<.01 then dx,dz,d=1,0,1 end
            return Nav.Select(c,Vector3(q.x+dx/d*radius,0,q.z+dz/d*radius),target)
        end
        return data
    end
    return base
end
function Mechanisms:Stop()
    for e,colour in pairs(self.hidden) do if e:IsValid() then e.AnimState:SetMultColour(unpack(colour)) end end
    self.hidden={}
end
return Mechanisms
