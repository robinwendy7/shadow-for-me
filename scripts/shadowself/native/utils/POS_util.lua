local POS_util = {}
--DEGREES
--a, b, c, d分别为ab为极坐标轴，c为旋转角度，d为距离a的距离（其实就是极坐标轴）
function POS_util:CalculateAimPos(a, b, c, d)
	if not a.x then
		a = a:GetPosition()
	end
	if not b.x then
		b = b:GetPosition()
	end
	if b.x == a.x and b.z == a.z then
		b.x = b.x + 0.001
		b.z = b.z + 0.001
	end
	local dx, dz = b.x - a.x, b.z - a.z
	local distance = math.sqrt(dx * dx + dz * dz)
	local cos, sin = dx / distance, dz / distance
	local aimdx = d * (math.cos(c) * cos - math.sin(c) * sin)
	local aimdz = d * (math.sin(c) * cos + math.cos(c) * sin)
	local aimx, aimz = a.x + aimdx, a.z + aimdz
	return Vector3(aimx, 0, aimz)
end

function POS_util:CalculateHeadingPos(target1, rot, dis)
	if not target1 then return end
	local angle = -target1:GetRotation()
	angle = angle * DEGREES
	local cos, sin = math.cos(angle + rot), math.sin(angle + rot)
	local pos = target1:GetPosition()
	local aimx = pos.x + dis * cos
	local aimz = pos.z + dis * sin
	return Vector3(aimx, 0, aimz)
end

function POS_util:CalculateDirect(pos1, pos2)
	local k = (pos2.z - pos1.z) / (pos2.x - pos1.x)
	local x = math.sqrt(1 / (1 + k * k)) * ((pos2.x - pos1.x > 0) and 1 or -1)
	local y = math.sqrt(1 - x * x) * ((pos2.z - pos1.z > 0) and 1 or -1)
	return x, y
end

function POS_util:GoToPoint(x, z)
	local ActiveItem = ThePlayer.replica.inventory:GetActiveItem()
	local playercontroller = ThePlayer.components.playercontroller
	if playercontroller:CanLocomote() then
		local action = BufferedAction(playercontroller.inst, nil, ACTIONS.WALKTO, nil,
			Vector3(x, 0, z))
		playercontroller:DoAction(action)
	else
		local platform, pos_x, pos_z = playercontroller:GetPlatformRelativePosition(x, z)
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pos_x, pos_z, ActiveItem, nil, nil,
			nil, nil, platform, platform ~= nil)
	end
end

return POS_util
