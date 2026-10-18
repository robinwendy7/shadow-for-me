local ENT_util = {}

--更加有效的找实体
function ENT_util:FindEntities(target, pos, range, fn)
    pos = target and target:GetPosition() or pos or ThePlayer and ThePlayer:GetPosition()
    local targettable = {}
    for _, ent in pairs(TheSim:FindEntities(pos.x, pos.y, pos.z, range or 10)) do
        if not fn or fn and fn(ent) then
            table.insert(targettable, ent)
        end
    end
    return targettable[1], targettable
end

function ENT_util:CreateEntity(params_table)
    local inst = CreateEntity()
    if not params_table.notaddtransform then
        inst.entity:AddTransform()
        inst.Transform:SetPosition((params_table.pos or Vector3(0, 0, 0)):Get())
    end
    if not params_table.notaddanim then
        inst.entity:AddAnimState()
        inst.AnimState:SetBuild(params_table.build or 'sign_mini')
        inst.AnimState:SetBank(params_table.bank or "sign_mini")
        if params_table.anim then
            inst.AnimState:PlayAnimation(params_table.anim)
        else
            inst.AnimState:PlayAnimation(params_table.anim_play or "idle")
            inst.AnimState:PushAnimation(params_table.anim_push or "idle", true)
        end

        --inst.AnimState:SetMultColour(1.0, 1.0, 1.0, 0.6)
    end
    for k, v in pairs(params_table.tags or {}) do
        inst:AddTag(v)
    end
    if params_table.fn then
        params_table.fn(inst)
    end
    return inst
end

-- 是否有效
function ENT_util:IsValid(ent)
    return ent and ent:IsValid() and ent.Transform and
        not ent:HasTag("INLIMBO")
end

function ENT_util:isOnWater(inst)
    return not inst:GetCurrentPlatform() and not TheWorld.Map:IsVisualGroundAtPoint(inst.Transform:GetWorldPosition())
end

function ENT_util:GetExistTime(ent)
    return ent.spawntime and GetTime() - ent.spawntime
end

function ENT_util:FnOrNum(a, ...)
    if type(a) == "function" then
        return a(...)
    else
        return a
    end
end

-- 获取堆叠数量
function ENT_util:GetStacksize(ent)
    if ent and ent.replica and ent.replica.stackable then
        return ent.replica.stackable:StackSize()
    end
    return 1
end

--获取真实的堆叠数目
function ENT_util:GetRealMaxSize(ent)
    local stackable = ent and ent.replica and ent.replica.stackable
    if stackable then
        local oldhuge = math.huge
        math.huge = false
        local maxsize = stackable:MaxSize()
        math.huge = oldhuge
        return maxsize
    end
    return 1
end

--
function ENT_util:GetMaxSize(ent)
    if ent and ent.replica and ent.replica.stackable then
        return ent.replica.stackable:MaxSize()
    end
    return 1
end

-- 获取耐久
function ENT_util:GetPercent(inst)
    local i = 100
    local classified = type(inst) == "table" and inst.replica and inst.replica.inventoryitem and
        inst.replica.inventoryitem.classified
    if classified then
        if inst:HasOneOfTags({ "fresh", "show_spoilage" }) and classified.perish then
            i = math.floor(classified.perish:value() / 0.62)
        elseif classified.percentused then
            i = classified.percentused:value()
        end
    end
    return i
end

--
function ENT_util:GetItemUnderMouse()
    local target = TheInput:GetHUDEntityUnderMouse()
    --target=target = target.widget ~= nil and target.widget.parent ~= nil and target.widget.parent.item
    if target ~= nil then
        local parent = target.widget and target.widget.parent
        if parent and parent.name == 'ItemTile' then
        else
            parent = parent and parent.parent
        end
        target = parent and parent.item
        return target, false
    else
        target = TheInput:GetWorldEntityUnderMouse()
        return target, true
    end
end

function ENT_util:GetHudUnderMouse()
    return TheInput:GetHUDEntityUnderMouse()
end

-- 获取客户端标签
function ENT_util:GetTags(ent)
    local debugstring = ent and ent:GetDebugString()
    if type(debugstring) == "string" then
        local tags_string = debugstring:match("Tags:(.-)\n")
        return tags_string and tags_string:split(" ") or {}
    end
    return {}
end

function ENT_util:GetAnimation(ent)
    if ent == nil then return end
    if not ent.AnimState then return end
    local a, b, c, d, e, f = ent.AnimState:GetHistoryData()
    return b
end

function ENT_util:CheckAnimation(ent, anim, frame)
    if ent == nil then return end
    local t = type(anim)
    if t == "table" then
        for _, anim_str in ipairs(anim) do
            if (not anim or ent.AnimState:IsCurrentAnimation(anim_str)) and
                (not frame or ent.AnimState:GetCurrentAnimationFrame() < frame) then
                return true
            end
        end
    elseif t == "string" then
        return (not anim or ent.AnimState:IsCurrentAnimation(anim)) and
            (not frame or ent.AnimState:GetCurrentAnimationFrame() < frame)
    elseif t == "function" then
        local get_anim = self:GetAnimation(ent)
        if get_anim then
            return anim(get_anim)
        end
    end
end

local deathanim = { ["corpse"] = true, ["death"] = true, }
function ENT_util:ListenForDeath(ent, fn)
    if not self:IsValid(ent) then
        return
    end
    ent:ListenForEvent("onremove", function()
        local anim = ENT_util:GetAnimation(ent)
        if deathanim[anim] then
            fn(ent)
        end
    end)
end

function ENT_util:GetAngle(target1, target2)
    if not target1 or not target2 then return end
    local pos1 = target1.GetPosition and target1:GetPosition() or target1
    local pos2 = target2.GetPosition and target2:GetPosition() or target2
    local tx, ty, tz = pos1:Get()
    local px, py, pz = pos2:Get()
    if tx == px and tz == pz then
        tx = tx + 0.1
        tz = tz + 0.1
    end
    local heading = -target1:GetRotation()
    local pa = math.atan2(pz - tz, px - tx) / DEGREES
    local result = heading - pa --0 - 360
    result = math.abs(result)
    if result > 180 then
        result = 360 - result
    end
    return result
end

-- 获取攻击目标
function ENT_util:GetCombatTarget(ent)
    return self:IsValid(ent) and ent.replica and ent.replica.combat and ent.replica.combat:GetTarget()
end

function ENT_util:CheckDebugString(ent, ...)
    if ent == nil then return end
    local str = ent.entity
        and ent.entity:GetDebugString()
    for k, v in pairs({ ... }) do
        if type(v) == "table" then
            for key, value in pairs(v) do
                if ENT_util:CheckDebugString(ent, value) then
                    return true
                end
            end
        elseif str and string.find(str, v) then
            return true
        end
    end
end

return ENT_util
