local INV_util = {}
local function isneed(v, prefabs, tags, nottags, fn)
    --[[ print((not prefabs or type(prefabs) == 'string' and v.prefab == prefabs
            or type(prefabs) == 'table' and table.contains(prefabs, v.prefab)),
        (not tags or type(tags) == 'string' and v:HasTag(tags) or type(tags) == 'table' and v:HasOneOfTags(tags)),
        (not nottags or type(nottags) == 'string' and not v:HasTag(nottags) or type(nottags) == 'table'
            and not v:HasOneOfTags(nottags)), (not fn or fn(v))) ]]
    if (not prefabs or type(prefabs) == 'string' and v.prefab == prefabs
            or type(prefabs) == 'table' and table.contains(prefabs, v.prefab))
        and (not tags or type(tags) == 'string' and v:HasTag(tags) or type(tags) == 'table' and v:HasOneOfTags(tags))
        and (not nottags or type(nottags) == 'string' and not v:HasTag(nottags) or type(nottags) == 'table'
            and not v:HasOneOfTags(nottags))
        and (not fn or fn(v)) then
        return true
    end
end
function INV_util:FindInInv(prefabs, tags, nottags, fn, notsearchtab) --如果都是nil会返回一个身上的物品
    if not ThePlayer then return end
    if not notsearchtab or not notsearchtab.equips then
        for k, v in pairs(ThePlayer.replica.inventory:GetEquips()) do
            if isneed(v, prefabs, tags, nottags, fn) then
                return v, k, nil
            end
        end
    end
    if not notsearchtab or not notsearchtab.items then
        for k, v in pairs(ThePlayer.replica.inventory:GetItems()) do
            if isneed(v, prefabs, tags, nottags, fn) then
                return v, k, nil
            end
        end
    end
    if not notsearchtab or not notsearchtab.items then
        --[[  local active = ThePlayer.replica.inventory:GetActiveItem()
        if isneed(active, prefabs, tags, nottags, fn) then
            return active
        end ]]
    end
    if not notsearchtab or not notsearchtab.container then
        for k, v in pairs(ThePlayer.replica.inventory:GetOpenContainers() or {}) do
            if k and k.replica and k.replica.container then --如果是空表不知道k是不是nil??以防万一还是判定空
                for kkk, vvv in pairs(k.replica.container:GetItems()) do
                    if isneed(vvv, prefabs, tags, nottags, fn) then
                        return vvv, kkk, k
                    end
                end
            end
        end --Inventory:GetOverflowContainer()
    elseif not notsearchtab or not notsearchtab.backpack then
        local backpack = ThePlayer.replica.inventory:GetOverflowContainer()
        if backpack then
            for kkk, vvv in pairs(backpack:GetItems()) do
                if isneed(vvv, prefabs, tags, nottags, fn) then
                    return vvv, kkk, backpack.inst
                end
            end
        end
    end
end

function INV_util:FindInInventory(prefab, tags, fn) --如果都是nil会返回一个身上的物品
    if not ThePlayer then return end
    for k, v in pairs(ThePlayer.replica.inventory:GetItems()) do
        if isneed(v, prefab, tags, nil, fn) then
            return v, k, nil
        end
    end
    for k, v in pairs(ThePlayer.replica.inventory:GetOpenContainers() or {}) do
        if k and k.replica and k.replica.container then
            for kkk, vvv in pairs(k.replica.container:GetItems()) do
                if isneed(vvv, prefab, tags, nil, fn) then
                    return vvv, kkk, k
                end
            end
        end
    end
end

function INV_util:FindInCon(con, prefabs, tags, nottags, fn)
    if not con or not con.replica.container then return end
    for k, v in pairs(con.replica.container:GetItems()) do
        if isneed(v, prefabs, tags, nottags, fn) then
            return v, k
        end
    end
end

function INV_util:FindEmptySlot(con, excludepos, excludecon)
    if not con or con == ThePlayer then
        local inventory = ThePlayer.replica.inventory
        if inventory:IsFull() then
            local backpack = inventory:GetOverflowContainer()
            if backpack and not backpack:IsFull() then
                for i = 1, backpack:GetNumSlots() do
                    if not backpack:GetItemInSlot(i)
                        and (i ~= excludepos or backpack.inst ~= excludecon) then
                        return i, backpack.inst
                    end
                end
            end
        else
            for i = 1, inventory:GetNumSlots() do
                if not inventory:GetItemInSlot(i)
                    and (i ~= excludepos or nil ~= excludecon) then
                    return i
                end
            end
            local backpack = inventory:GetOverflowContainer()
            if backpack and not backpack:IsFull() then
                for i = 1, backpack:GetNumSlots() do
                    if not backpack:GetItemInSlot(i)
                        and (i ~= excludepos or backpack.inst ~= excludecon) then
                        return i, backpack.inst
                    end
                end
            end
        end
    else
        local backpack = con.replica.container
        if not backpack then return end
        for i = 1, backpack:GetNumSlots() do
            if not backpack:GetItemInSlot(i)
                and (i ~= excludepos or backpack.inst ~= excludecon) then
                return i, backpack.inst
            end
        end
    end
end

function INV_util:CountPrefab(prefabs, tags, nottags, fn, notsearchtab)
    local num = 0
    if not notsearchtab or not notsearchtab.equips then
        for k, v in pairs(ThePlayer.replica.inventory:GetEquips()) do
            if isneed(v, prefabs, tags, nottags, fn) then
                num = num + (v.replica.stackable and v.replica.stackable:StackSize() or 1)
            end
        end
    end
    if not notsearchtab or not notsearchtab.items then
        for k, v in pairs(ThePlayer.replica.inventory:GetItems()) do
            if isneed(v, prefabs, tags, nottags, fn) then
                num = num + (v.replica.stackable and v.replica.stackable:StackSize() or 1)
            end
        end
    end
    if not notsearchtab or not notsearchtab.items then
        local v = ThePlayer.replica.inventory:GetActiveItem()
        if v and isneed(v, prefabs, tags, nottags, fn) then
            num = num + (v.replica.stackable and v.replica.stackable:StackSize() or 1)
        end
    end
    if not notsearchtab or not notsearchtab.container then
        for k, v in pairs(ThePlayer.replica.inventory:GetOpenContainers() or {}) do
            if k and k.replica and k.replica.container then --如果是空表不知道k是不是nil??以防万一还是判定空
                for kkk, vvv in pairs(k.replica.container:GetItems()) do
                    num = num + (vvv.replica.stackable and vvv.replica.stackable:StackSize() or 1)
                end
            end
        end
    end
    return num
end

function INV_util:HasInv()
    return ThePlayer
        and ThePlayer.replica.inventory
end

function INV_util:GetActiveItem()
    return self:HasInv()
        and ThePlayer.replica.inventory:GetActiveItem()
end

function INV_util:GetHandsEquip()
    return self:HasInv() and EQUIPSLOTS.HANDS
        and ThePlayer.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
end --GetEquippedItem(EQUIPSLOTS.HEAD)

function INV_util:GetHeadEquip()
    return self:HasInv() and EQUIPSLOTS.HEAD
        and ThePlayer.replica.inventory:GetEquippedItem(EQUIPSLOTS.HEAD)
end

function INV_util:GetBodyEquip()
    return self:HasInv() and EQUIPSLOTS.BODY
        and ThePlayer.replica.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
end

function INV_util:GetBackEquip()
    return self:HasInv() and EQUIPSLOTS.BACK
        and ThePlayer.replica.inventory:GetEquippedItem(EQUIPSLOTS.BACK)
end

function INV_util:GetEquip(slot)
    return self:HasInv() and slot
        and ThePlayer.replica.inventory:GetEquippedItem(slot)
end

function INV_util:UseAtoB(a, b, action) --把a加到b 用action动作
    if b == nil or a == nil then return end

    local actions = action or a:GetIsWet() and ACTIONS.ADDWETFUEL or
        ACTIONS.ADDFUEL

    local playercontroller = ThePlayer.components.playercontroller
    local act = BufferedAction(ThePlayer, b, actions, a)
    local function cb()
        SendRPCToServer(RPC.ControllerUseItemOnItemFromInvTile,
            actions.code, b, a, actions.mod_name)
    end
    if ThePlayer.components.locomotor then
        act.preview_cb = cb
    else
        cb()
    end
    playercontroller:DoAction(act)
end

return INV_util
