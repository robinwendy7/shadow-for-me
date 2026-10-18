-- Distance hysteresis for cane travel; equip never gates movement/native combat.
local A=require("shadowself/control/actions")
local Travel=Class(function(self,player,gear)
    self.player=player;self.gear=gear;self.role="attack"
    if not gear then
        require("shadowself/legacy/action_library");require("shadowself/legacy/combat_equipment")
        local R=require("shadowself/legacy/registry")
        self.context={player=player,owner={perception={Inventory=function() return A.Items(player) end}},
            roles={CanRunForm=function() return false end,NaturalWeapon=function() return false end}}
        self.context.actions=R.ActionLibrary(player,{})
        self.gear=R.CombatEquipment(self.context)
    end
end)
-- Native DoDodge emits walk_hands once at entry and fight once at exit.
-- The equip request is retried only if the hit/attack animation initially blocked it;
-- it never waits/yields or takes over native movement.
function Travel:BeginDodge(snapshot)
    if not self.dodging then self.next_dodge_equip=nil end
    self.dodging=true;self.restore_dodge=nil;self.finish_deferred=nil;self.role="move"
    self:UpdateDodge(snapshot)
end
function Travel:EndDodge(snapshot)
    if self.chasing then self.dodging=nil;self.restore_dodge=nil;self.finish_deferred=nil;self.role="move";return end
    if not self.dodging and not self.finish_deferred then return end
    self.dodging=nil;self.finish_deferred=nil;self.restore_dodge=true;self.role="attack"
    self.next_dodge_equip=nil
    -- Explicit phase change, not distance jitter: restoring the weapon need not
    -- inherit the cane request's throttle.
    self.gear.next_request=GetTime()
    self:UpdateDodge(snapshot)
end
function Travel:UpdateDodge(snapshot)
    if not self.dodging and not self.restore_dodge then return end
    local p=self.player;local pc=p.components and p.components.playercontroller;local now=GetTime()
    if p:HasTag("busy") or p:HasTag("attack") or pc and pc.IsBusy and pc:IsBusy() then return end
    if now<(self.next_dodge_equip or 0) then return end
    self.next_dodge_equip=now+.1
    local role=self.dodging and "move" or "attack"
    if role=="attack" and not self.gear:Weapon() then self.restore_dodge=nil;return end
    if self.gear:Swap(role,snapshot or {night=TheWorld and TheWorld.state.isnight}) and role=="attack" then self.restore_dodge=nil end
end
function Travel:Tick(point,reach,imminent,snapshot)
    if self.dodging or self.restore_dodge then self:UpdateDodge(snapshot);return end
    local p=self.player;local now=GetTime();local pc=p.components and p.components.playercontroller
    if imminent or p:HasTag("busy") or p:HasTag("attack") or pc and pc.IsBusy and pc:IsBusy() then return end
    if now<(self.next or 0) then return end
    self.next=now+.2
    local d=math.sqrt(p:GetPosition():DistSq(point))
    if self.chasing then self.role="move"
    elseif reach then
        if self.role=="move" then
            if d<=math.max(4,reach+1.5) then self.role="attack" end
        elseif d>math.max(7,reach+4) then self.role="move" end
    else self.role=d>4 and "move" or "attack" end
    if self.role=="attack" and not self.gear:Weapon() then return end
    self.gear:Swap(self.role,snapshot or {night=TheWorld and TheWorld.state.isnight})
end
function Travel:Reset() if self.context then self.context.actions:Stop() end;self.gear:Reset();self.role="attack";self.next=nil;self.dodging=nil;self.restore_dodge=nil;self.finish_deferred=nil;self.next_dodge_equip=nil end
return Travel
