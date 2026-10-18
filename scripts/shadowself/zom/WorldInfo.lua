local Config = require("shadowself/zom/Config")

local WorldInfo = {}

function WorldInfo.GetId(G)
    local world = G.TheWorld
    if world == nil then return nil end
    local id = world.worldid
    if (id == nil or Config.WORLD_NAMES[tostring(id)] == nil) and world.net ~= nil then
        local shard = world.net._shardid or world.net._worldid
        if shard ~= nil and shard.value ~= nil then
            local synced = shard:value()
            if synced ~= nil and synced ~= "" then id = synced end
        end
    end
    if id == nil and G.TheShard ~= nil and G.TheShard.GetShardId ~= nil then
        id = G.TheShard:GetShardId()
    end
    return id ~= nil and tostring(id) or nil
end

function WorldInfo.GetName(G)
    local id = WorldInfo.GetId(G)
    if id ~= nil then
        return Config.WORLD_NAMES[id] or (G.TheWorld.worldname or ("世界" .. id)), id
    end
    return nil, nil
end

function WorldInfo.SameWorld(G, sender)
    if sender.entity ~= nil and sender.entity:IsValid()
        and sender.entity.userid == sender.userid then return true end
    -- 同一分片的客户端名单可以确认远处但尚未加载实体的玩家。
    local clients = G.TheNet ~= nil and G.TheNet.GetClientTable ~= nil
        and G.TheNet:GetClientTable() or nil
    for _, client in ipairs(clients or {}) do
        if client.userid == sender.userid then return true end
    end
    return false -- 跨分片聊天无法从 ChatHistory 得到可信的对方世界 ID。
end

return WorldInfo
