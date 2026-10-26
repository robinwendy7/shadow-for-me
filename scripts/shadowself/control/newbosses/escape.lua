-- 暗影憎恶黑液脱离：正常装备/BLINK动作，确认位移才释放控制权。
local A=require("shadowself/control/actions")
local G=require("shadowself/control/newbosses/geometry")
local Shrouden=require("shadowself/control/newbosses/shrouden")
local M={}
local function usable(item)
    return item and item:IsValid() and not item:HasTag("nomagiccast")
        and (item.prefab=="orangestaff" or item.HasActionComponent and item:HasActionComponent("blinkstaff"))
end
local function staff(player,chosen)
    local held=player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if usable(held) then return held end
    local found
    for _,item in ipairs(A.Items(player)) do
        if usable(item) then
            if item==chosen then return item end
            found=found or item
        end
    end
    return found
end
local function landing(owner)
    local c=owner.c;local p=c.player:GetPosition();local best,score
    -- 瞬移不要求中间路径可走，但落点必须离开黑液、攻击区及实体碰撞体。
    for _,length in ipairs({8,10,12,14}) do for i=0,23 do
        local angle=i*math.pi/12;local q=Vector3(p.x+length*math.cos(angle),0,p.z+length*math.sin(angle))
        if c.actions:SafePoint(q) and owner:Risk(q,.5)==0 then
            local clear=true
            for _,e in ipairs(owner.bodies) do
                if q:DistSq(e:GetPosition())<(e:GetPhysicsRadius(0)+c.player:GetPhysicsRadius(.5)+.4)^2 then clear=false;break end
            end
            if clear then for _,h in ipairs(c.hazards or {}) do if q:DistSq(h.pos)<(h.radius+.25)^2 then clear=false;break end end end
            if clear then
                local value=length+(8-require("shadowself/control/navigation").Clearance(c,q))*3
                if not score or value<score then best,score=q,value end
            end
        end
    end end
    return best
end
function M.Clear(owner,cooldown)
    local s=owner.gel_escape
    if s and owner.c.gear.action_hold==s then owner.c.gear.action_hold=nil end
    owner.gel_escape=nil
    if cooldown then owner.next_blink=GetTime()+cooldown end
end
function M.Tick(owner)
    local c=owner.c;local p=c.player;local now=GetTime();local s=owner.gel_escape
    if s and c.gear.action_hold~=s then M.Clear(owner,1);return false end
    if not s then
        if now<(owner.next_blink or 0) or c.gear.action_hold or not Shrouden.Contact(owner) then return false end
        local item=staff(p);if not item or not ACTIONS.BLINK then return false end
        local point=landing(owner);if not point then return false end
        s={item=item,point=point,started=now};owner.gel_escape=s;c.gear.action_hold=s
        -- 撤销之前排队的追击/出刀；从这里到位移确认，不再发移动和手杖请求。
        c.bridge:PauseAttack();A.Stop(p);c.gear.pending=nil
    end
    owner.holding=true;c.blocked=true;c.special_active=true
    c.bridge:PauseAttack();c.status="暗影憎恶 · 瞬移脱离黑液"
    if s.sent then
        local pos=p:GetPosition()
        if pos:DistSq(s.before)>4^2 and pos:DistSq(s.point)<2.5^2 then
            M.Clear(owner,1);owner.point=nil;return true
        end
        if now-s.sent>1.6 then M.Clear(owner,1);return false end
        return true
    end
    if staff(p,s.item)~=s.item or now-s.started>2 then M.Clear(owner,1);return false end
    local pc=p.components.playercontroller
    if pc:IsBusy() then return true end
    if p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)~=s.item then
        if now>=(s.next_equip or 0) then
            if A.Self(p,s.item,ACTIONS.EQUIP) then s.next_equip=now+.35
            else M.Clear(owner,1);return false end
        end
        return true
    end
    -- 装备期间Boss可能移动，真正施法前重新评估落点。
    s.point=landing(owner)
    if not s.point then M.Clear(owner,1);return false end
    local function guard()
        return owner.gel_escape==s and s.item:IsValid()
            and p.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)==s.item
    end
    if A.Ground(p,s.point,ACTIONS.BLINK,guard) then s.sent=now;s.before=p:GetPosition();return true end
    M.Clear(owner,1);return false
end
return M
