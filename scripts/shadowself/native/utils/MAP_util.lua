local MAP_util = {}
--TheWorld.minimap.MiniMap

function MAP_util:IsMapScreenOpen()
    local active_screen = TheFrontEnd:GetActiveScreen()
    return active_screen ~= nil and active_screen.name == "MapScreen" and active_screen
end

function MAP_util:GetMapScreen()
    local active_screen = TheFrontEnd:GetActiveScreen()
    return active_screen ~= nil and active_screen.name == "MapScreen" and active_screen
end

function MAP_util:GetMiniMap()
    return TheWorld and TheWorld.minimap and TheWorld.minimap.MiniMap
end

function MAP_util:MapPosToWorldPos(x, y)
    local MiniMap = self:GetMiniMap()

    local xx, yy = MiniMap:MapPosToWorldPos(x, y, 0)

    return Vector3(xx, 0, yy)
end

--[[ function WorldPosToScreenPos(self, x, z)
	local screen_width, screen_height = TheSim:GetScreenSize() -- 1920, 1080
	local half_x, half_y = RESOLUTION_X / 2, RESOLUTION_Y / 2 -- 1280/2, 720/2
	local map_x, map_y = TheWorld.minimap.MiniMap:WorldPosToMapPos(x, z, 0) -- Converts world position to map position
	local screen_x = ((map_x * half_x) + half_x) / RESOLUTION_X * screen_width -- Centers map point onto middle of map screen
	local screen_y = ((map_y * half_y) + half_y) / RESOLUTION_Y * screen_height
	return screen_x, screen_y
end ]]
function MAP_util:WorldPosToMapPos(x, z)
    local MiniMap = self:GetMiniMap()

    local xx, yy = MiniMap:WorldPosToMapPos(x, z, 0)

    return xx, yy
end

return MAP_util
