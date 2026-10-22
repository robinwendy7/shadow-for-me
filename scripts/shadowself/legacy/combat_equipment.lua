local AIPLAYER=require("shadowself/legacy/registry")
local Debug=require("shadowself/control/queendebug")
-- Public replica attributes, original EQUIP actions, and observed hand-slot
-- changes. A pending equip never counts as extra movement speed or a weapon.
local function read(o,name,fallback,...)
    if o and type(o[name])=="function" then local ok,v=pcall(o[name],o,...);if ok and v~=nil then return v end end
    return fallback
end
local E={}
function E.Usable(player,item)
    if not item or not item:IsValid() or item:HasTag("broken") then return false end
    local replica=item.replica or {};local eq=replica.equippable;local ii=replica.inventoryitem
    if not eq then
        local inv=player.replica and player.replica.inventory
        if not inv or inv:GetEquippedItem(EQUIPSLOTS.HANDS)~=item then return false end
    end
    if read(eq,"EquipSlot",EQUIPSLOTS.HANDS)~=EQUIPSLOTS.HANDS then return false end
    if read(eq,"IsRestricted",false,player) then return false end
    local tag=read(ii,"GetEquipRestrictedTag",nil)
    return not tag or player:HasTag(tag)
end
function E.Melee(player,item)
    return E.Usable(player,item) and item:HasTag("weapon") and not item:HasTag("rangedweapon")
        and not (item:HasTag("projectile") and not item:HasTag("complexprojectile"))
end
function E.Weapon(player,item)
    if E.Melee(player,item) then return true end
    -- Do not infer ammunition from an ATTACK preview: an empty slingshot
    -- still offers ATTACK and is rejected only on the server at fire time.
    return E.Usable(player,item) and item:HasTag("slingshot") and item:HasTag("ammoloaded")
end
function E.Mult(item)
    local v=read(item and item.replica and item.replica.inventoryitem,"GetWalkSpeedMult",1)
    return type(v)=="number" and v==v and v>0 and v<=3 and v or 1
end
local Gear=Class(function(self,combat)self.combat=combat;self.player=combat.player;self.failed={};self.next_request=0 end)
function Gear:Items()
    local out={};local found={}
    local items=self.combat.owner.perception:Inventory()
    for _,item in ipairs(items or {}) do
        if item:IsValid() and not found[item] then found[item]=true;out[#out+1]=item end
    end
    local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if hand and hand:IsValid() and not found[hand] then out[#out+1]=hand end
    table.sort(out,function(a,b)return a.GUID<b.GUID end);return out,hand
end
function Gear:Owned(item)
    for _,v in ipairs(self:Items()) do if v==item then return true end end
    return false
end
local DAMAGE={ruins_bat=59.5,nightsword=68,glasscutter=68,voidcloth_scythe=38,shadow_battleaxe=38,
    sword_lunarplant=38,pickaxe_lunarplant=32.5,shovel_lunarplant=17.2,spear_wathgrithr_lightning_charged=59.5,
    tentaclespike=51,spear=34,spear_wathgrithr=42.5,spear_wathgrithr_lightning=59.5,
    hambat=59.5,whip=27.2,nightstick=43.35,cane=17,orangestaff=10,batbat=42.5,
    trident=51,boomerang=27.2,icestaff=0,firestaff=0,torch=17,pickaxe=27,axe=27}
function Gear:Damage(item)
    local w=item.components and item.components.weapon
    local damage=w and type(w.damage)=="number" and w.damage or DAMAGE[item.prefab] or 34
    if item.prefab=="hambat" then
        local percent=read(item.replica and item.replica.inventoryitem,"GetPerishPercent",1)
        if self.combat and self.combat.plan and self.combat.plan.arena then
            local perish=item.components and item.components.perishable
            local ii=item.replica and item.replica.inventoryitem
            local net=ii and ii.classified and ii.classified.perish
            if perish and perish.GetPercent then percent=perish:GetPercent()
            elseif net and net:value()~=63 then percent=net:value()/62 end
        end
        damage=damage*(.5+.5*percent)
    end
    return damage
end
function Gear:Weapon()
    local plan=self.combat and self.combat.plan
    local no_whip=plan and plan.arena and plan.arena_no_whip and plan.arena_no_whip()
    if self.forced_weapon and not (no_whip and self.forced_weapon.prefab=="whip") and self:Owned(self.forced_weapon) and E.Usable(self.player,self.forced_weapon) then return self.forced_weapon end
    local items,hand=self:Items();local best,bestscore
    local policy=require("shadowself/control/targetpolicy")
    local damage=require("shadowself/control/weapon_damage")
    local target=self.combat.target or self.combat.h and self.combat.h.ent
    local count=0
    for _,e in ipairs(self.combat.enemies or {}) do if policy.Creature(e) then count=count+1 end end
    local boss=policy.Boss(target)
    local electric=damage.Electric(self.player)
    local wet=target and (target.GetIsWet and target:GetIsWet() or target:HasTag("wet"))
    for _,item in ipairs(items) do if E.Weapon(self.player,item) and not (no_whip and item.prefab=="whip") then
        local travel=E.Mult(item)>=1.2 or item.prefab=="cane" or item.prefab=="orangestaff"
        local score=damage.Score(self.player,item,self:Damage(item),target)+(item==hand and .1 or 0)-(travel and 1000 or 0)
        if item.prefab=="nightstick" and electric then score=score-10000 end
        -- 潮湿且无闪电增益，晨星按要求优先；不再因群怪数量给晨星加分。
        if item.prefab=="nightstick" and wet and not electric and not boss then score=score+5000 end
        -- Boss只按实际伤害选择。普通群怪才借猫尾鞭的攻击距离。
        if count>4 and not boss and (not target or policy.Creature(target)) and not travel and item.prefab=="whip" then
            local range=math.max(read(item.replica.inventoryitem,"AttackRange",0),TUNING.WHIP_RANGE or 2)
            score=score+3000+range*100
        end
        if not bestscore or score>bestscore then best,bestscore=item,score end
    end end
    self.weapon=best;return best
end
function Gear:Mobile(snapshot)
    local _,hand=self:Items();local best=hand;local mult=E.Mult(hand)
    -- Keep a sole held light in darkness; equipment changes must not remove
    -- the only visible source while dodging.
    if snapshot and snapshot.night and hand and hand:HasTag("light") then
        local point=self.player:GetPosition()
        if not (self.player.Light and self.player.Light:IsEnabled()) and TheSim:GetLightAtPoint(point.x,0,point.z)<.25 then return hand end
    end
    for _,item in ipairs(self:Items()) do
        local speed=E.Mult(item)
        if E.Usable(self.player,item) and speed>mult+.01 and GetTime()>=(self.failed[item] or 0)
            and (item==hand or self.combat.actions:FindAction("EQUIP",nil,item)) then best=item;mult=speed end
    end
    return best
end
function Gear:AttackRange()
    local combat=self.player.replica.combat
    local current=read(combat,"GetAttackRangeWithWeapon",2)
    local weapon=self:Weapon()
    local hand=self.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if weapon==hand then return current end
    local own=read(combat,"GetWeaponAttackRange",nil)
    local extra=read(weapon and weapon.replica.inventoryitem,"AttackRange",nil)
    if type(own)=="number" and type(extra)=="number" then return math.max(0,current-own+extra) end
    local held=read(hand and hand.replica.inventoryitem,"AttackRange",0)
    return math.max(1.5,current-held+(type(extra)=="number" and extra or 0))
end
function Gear:Swap(role,snapshot)
    if self.action_hold then return false end -- 二阶段吹奏拥有操作权，禁止并发换装。
    if self.combat.roles:CanRunForm() then return true end
    if self.combat.roles:NaturalWeapon() and not self:Weapon() then return true end
    local now=GetTime();local inv=self.player.replica.inventory;local hand=inv:GetEquippedItem(EQUIPSLOTS.HANDS)
    self:Weapon() -- Remember the actual combat weapon before borrowing a cane.
    local pc=self.player.components and self.player.components.playercontroller
    local busy=pc and pc.IsBusy and pc:IsBusy()
    local support=self.support_hand
    if support and (not self:Owned(support.item) or not E.Usable(self.player,support.item)) then self.support_hand=nil;support=nil end
    local pending=self.pending
    if pending and pending.role and pending.role~=role and not support then
        -- A cancelled travel equip cannot hold up returning to combat (or vice versa).
        Debug.Equip(self.combat,"cancel_role",pending.item,role)
        self.pending=nil;pending=nil;self.next_request=now
    end
    if pending then
        if hand==pending.item then Debug.Equip(self.combat,"ack",pending.item,role,{latency=pending.senttime and now-pending.senttime or -1});self.pending=nil
        elseif busy then return false -- transient hit/busy is not a rejected item
        elseif now<pending.untiltime and pending.item:IsValid() and self:Owned(pending.item) then return false
        else
            Debug.Equip(self.combat,"timeout",pending.item,role)
            self.failed[pending.item]=now+3;self.pending=nil
            self.combat.actions:Stop();self.combat.last_action_kind=nil;self.combat.last_point=nil
        end
    end
    -- 蜂后一阶段专属手持所有权：native move/fight 只能协助当前阶段，不能另选一件。
    local wanted=support and support.item or (role=="move" and self:Mobile(snapshot) or self:Weapon())
    if not wanted then return false end
    if hand==wanted then return true end
    if busy then return false end -- do not Stop or blacklist an item while hit-stunned
    if now<self.next_request or now<(self.failed[wanted] or 0) then return false end
    local act=self.combat.actions:FindAction("EQUIP",nil,wanted)
    if not act then self.failed[wanted]=now+3;return false end
    -- Cancel a stale attack before issuing EQUIP, never afterwards: doing so
    -- would invalidate the native inventory preview callback itself.
    if self.combat.last_action_kind=="attack" or role=="attack" and self.combat.last_action_kind=="move" then
        self.combat.actions:Stop();self.combat.last_action_kind=nil;self.combat.issued_attack=nil
    end
    local sent,reason=self.combat.actions:Execute(act)
    if sent then
        self.pending={item=wanted,role=role,untiltime=now+1.2,senttime=now};self.next_request=now+.25
        Debug.Equip(self.combat,"request",wanted,role)
        if role=="move" then self.mobile=wanted end
    elseif reason~="角色忙碌" then Debug.Equip(self.combat,"rejected",wanted,role,{reason=reason or "unknown"});self.failed[wanted]=now+3 end
    return false
end
function Gear:Reset()self.action_hold=nil;self.support_hand=nil;self.weapon=nil;self.mobile=nil;self.pending=nil;self.failed={};self.next_request=0 end
AIPLAYER.Equipment=E
AIPLAYER.CombatEquipment=Gear

return true
