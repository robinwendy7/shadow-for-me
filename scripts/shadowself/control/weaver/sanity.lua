-- 二阶段SAN与一次清鬼手的临时装备。只由原监督协程调用，危险走位始终先处理。
local A=require("shadowself/control/actions")
local O=require("shadowself/control/weaver/observe")
local Food=require("shadowself/control/arena_food")
local D=require("shadowself/control/weaver/debug")
local M={}
local rawfoods={cookedgreen_cap=15,cookedblue_cap=10,cactus_cooked=15,smallmeat_dried=10,meat_dried=15}
local function mask(item) return item and (item.prefab=="purpleamulet" or item.prefab=="skeletonhat") end
local function count(w,name)
    local total=0
    for _,i in ipairs(A.Items(w.c.player)) do if i.prefab==name then
        local stack=i.replica and i.replica.stackable;total=total+(stack and stack:StackSize() or 1)
    end end
    return total
end
local function owned(w,item)
    for _,i in ipairs(A.Items(w.c.player)) do if i==item and i:IsValid() then return true end end
    return false
end
local function wearing(w)
    local inv=w.c.player.replica.inventory
    return mask(inv:GetEquippedItem(EQUIPSLOTS.BODY)) or mask(inv:GetEquippedItem(EQUIPSLOTS.HEAD))
end
M.Wearing=wearing
local function controlleft(w)
    if w.state.anim~="control_pre" then return 0 end
    local anim=w.boss.AnimState
    local length=anim and anim.GetCurrentAnimationLength and anim:GetCurrentAnimationLength()
    if type(length)~="number" or length<=0 then return 0 end
    return length-(w.state.frame or 0)/30
end
function M.ControlDue(w)
    return w.state.controlling and controlleft(w)<=math.max(.4,w.c:Latency()*2+.2) or false
end
function M.HandWindow(w)
    -- 临界点前不再发起新一刀，留出攻击动作结束、摘装备与服务器确认的时间。
    return not w.state.controlling or controlleft(w)>math.max(.4,w.c:Latency()*2+.2)+.65
end
local function choosefood(w)
    local p=w.c.player;local picker=p.components.playeractionpicker
    if not picker or not picker.GetInventoryActions then return nil end
    local best,score
    for _,item in ipairs(A.Items(p)) do if item:IsValid() and Food.Freshness(item)>.5
        and not item:HasTag("spoiledfood") and item.prefab~="mandrake" and item.prefab~="cookedmandrake" and item.prefab~="mandrakesoup" then
        local recipe,base=Food.Recipe(item);local gain=recipe and recipe.sanity or rawfoods[base] or 0
        if type(gain)=="number" and gain>0 then
            local allowed=false
            for _,right in ipairs({true,false}) do for _,act in ipairs(picker:GetInventoryActions(item,right) or {}) do
                if act.action==ACTIONS.EAT then allowed=true end
            end end
            local value=gain/Food.Duration(item)
            if allowed and (not score or value>score) then best,score=item,value end
        end
    end end
    return best
end
function M.NeedsRecovery(w)
    local sanity=O.Sanity(w.c.player)
    return not wearing(w) and sanity and sanity<.6 and choosefood(w)~=nil
end
function M.Feed(w)
    local now=GetTime();local p=w.c.player;local pc=p.components.playercontroller
    local pending=w.sanity_food
    if pending then
        if count(w,pending.name)<pending.count then
            w.sanity_food=nil;w.next_sanity_food=now+.6;D.Emit(w,"sanity_food_confirmed",pending.name)
            return pc:IsBusy()
        elseif now<pending.deadline then return true
        else w.sanity_food=nil;w.next_sanity_food=now+3;D.Emit(w,"sanity_food_timeout");return false end
    end
    local q=w.cycle
    if w.staff_action or q and (q.root_work or q.sent and not q.spent) then return false end
    -- 强制疯狂的网络SAN为0，不能将其当作真实缺SAN而不停进食。
    if w.state.phase<2 or wearing(w) or now<(w.next_sanity_food or 0) then return false end
    local sanity=O.Sanity(p)
    if not sanity or sanity>=.6 or pc:IsBusy() or p:HasTag("attack") then return false end
    local s=w.state
    if w.lure_until or w.rebait or w.cycle and w.cycle.stage=="hands"
        and not (s.channeling or s.summoning or s.controlling) then return false end
    local cast=s.channeling or s.summoning or s.feasting or s.controlling
    local close=p:GetPosition():DistSq(w.boss:GetPosition())<8^2
    local after_melee=s.anim=="attack" and s.frame>32+math.ceil(w.c:Latency()*30)
    if close and not cast and not after_melee then return false end
    local best=choosefood(w)
    if not best then return false end
    if close and not cast and (not s.melee_started or now+Food.Duration(best)+w.c:Latency()+.2
        >=s.melee_started+63/30) then return false end
    w:Hold("安全空档吃回SAN食物",true)
    local before=count(w,best.prefab)
    if A.Self(p,best,ACTIONS.EAT) then
        w.sanity_food={name=best.prefab,count=before,deadline=now+3}
        D.Emit(w,"sanity_food_requested",best.prefab);return true
    end
    w.next_sanity_food=now+2;return false
end
function M.Ready(w)
    local sanity=w.c.player.replica.sanity
    if sanity and sanity.IsInsane then return sanity:IsInsane() end
    return (O.Sanity(w.c.player) or 1)<=.001
end
function M.CanPrepare(w)
    return wearing(w) or M.Ready(w) or w:Item("purpleamulet")~=nil or w:Item("skeletonhat")~=nil
end
function M.Prepare(w)
    local p=w.c.player;local inv=p.replica.inventory;local round=w.sanity_round
    if round then
        if round.restoring then return M.Restore(w) end
        if inv:GetEquippedItem(round.slot)==round.item then w:CancelSupport();return false end
        if not owned(w,round.item) then round.restoring=true;return M.Restore(w) end
        return w:Equip(round.item,round.slot,"本轮固定临时装备，准备清鬼手")
    end
    if not wearing(w) and M.Ready(w) then return false end
    -- 优先梦魇护符；已有同类装备时沿用同一件，不因列表顺序重复切换。
    local item,slot
    for _,s in ipairs({EQUIPSLOTS.HEAD,EQUIPSLOTS.BODY}) do
        local held=inv:GetEquippedItem(s);if mask(held) then item,slot=held,s;break end
    end
    if not item then item=w:Item("purpleamulet");slot=EQUIPSLOTS.BODY end
    if not item then item=w:Item("skeletonhat");slot=EQUIPSLOTS.HEAD end
    if not item then return false end
    local original=inv:GetEquippedItem(slot);if original==item then original=nil end
    w.sanity_round={item=item,slot=slot,original=original}
    D.Emit(w,"sanity_round_begin",item.prefab)
    if inv:GetEquippedItem(slot)==item then return false end
    return w:Equip(item,slot,"临时换装清鬼手，记录原装备")
end
function M.Restore(w)
    local round=w.sanity_round;if not round then return false end
    round.restoring=true
    local p=w.c.player;local inv=p.replica.inventory;local held=inv:GetEquippedItem(round.slot)
    if round.original and not owned(w,round.original) then round.original=nil end
    if held==round.original or held~=round.item and not round.original then
        w:CancelSupport();w.sanity_round=nil;w.next_sanity_food=GetTime()+.5
        D.Emit(w,"sanity_round_restored","inventory_equipment_confirmed");return false
    end
    if round.original then return w:Equip(round.original,round.slot,"清完鬼手／控制前恢复原装备") end
    -- 原槽为空也必须脱下临时物品，不能把强制疯狂装备遗留在身上。
    w:Hold("脱下临时装备，恢复自然SAN",true)
    if not p.components.playercontroller:IsBusy() and GetTime()>=(w.next_equip or 0) then
        A.Self(p,round.item,ACTIONS.UNEQUIP);w.next_equip=GetTime()+.4
    end
    return true
end
return M
