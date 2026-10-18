local PLAYER_util = {}
local PlayerController = require "components/playercontroller"

-- 不覆盖原版 RemoteDirectWalking。
function PLAYER_util:BanDirectWalking(time, delaytime)
	if PLAYER_util.task_banwalk then
		PLAYER_util.task_banwalk:Cancel()
	end

	if delaytime then
		ThePlayer:DoTaskInTime(delaytime, function()
			PLAYER_util.bandirectwalk = true
			PLAYER_util.task_banwalk = ThePlayer:DoTaskInTime(time, function()
				PLAYER_util.bandirectwalk = false
				PLAYER_util.task_banwalk = nil
			end)
		end)
	else
		PLAYER_util.bandirectwalk = true
		PLAYER_util.task_banwalk = ThePlayer:DoTaskInTime(time, function()
			PLAYER_util.bandirectwalk = false
			PLAYER_util.task_banwalk = nil
		end)
	end
end

local ex_fns = require "prefabs/player_common_extensions"
function PLAYER_util:EnableMovementPrediction(tellserver, stopmove)
	local inst = ThePlayer
	if inst.components.locomotor == nil then
		local isghost =
			(inst.player_classified ~= nil and inst.player_classified.isghostmode:value()) or
			(inst.player_classified == nil and inst:HasTag("playerghost"))
		inst.Physics:Stop()
		inst:AddComponent("embarker")
		inst.components.embarker.embark_speed = TUNING.WILSON_RUN_SPEED
		inst:AddComponent("locomotor") -- locomotor must be constructed before the stategraph
		if isghost then
			ex_fns.ConfigureGhostLocomotor(inst)
			inst.components.locomotor.pathcaps = { player = true, ignorecreep = true, allowocean = true }
		else
			ex_fns.ConfigurePlayerLocomotor(inst)
		end

		inst.components.locomotor.pathcaps = { player = true, ignorecreep = false }

		if inst.player_classified and inst.player_classified.isstrafing:value() then
			inst.components.locomotor:SetStrafing(true)
		end
		if inst.components.playercontroller ~= nil then
			inst.components.playercontroller.locomotor = inst.components.locomotor
		end
		inst:SetStateGraph(isghost and "SGwilsonghost_client" or "SGwilson_client")
		inst.entity:EnableMovementPrediction(true)
		inst.components.locomotor.is_prediction_enabled = true
		if tellserver then
			SendRPCToServer(RPC.SetMovementPredictionEnabled, true)
		end
		if stopmove then
			SendRPCToServer(RPC.PredictWalking, ThePlayer:GetPosition().x, ThePlayer:GetPosition().z)
		end
		return true
	end
end

function PLAYER_util:DisableMovementPrediction(tellserver)
	local inst = ThePlayer
	if inst.components.locomotor ~= nil then
		inst.entity:EnableMovementPrediction(false)
		inst:ClearBufferedAction()
		inst:ClearStateGraph()
		if inst.components.playercontroller ~= nil then
			inst.components.playercontroller.locomotor = nil
		end
		inst:RemoveComponent("locomotor")
		inst:RemoveComponent("embarker")
		inst.Physics:Stop()
		if tellserver then
			SendRPCToServer(RPC.SetMovementPredictionEnabled, false)
		end
	end
end

function PLAYER_util:Say(str, Response)
	if not Response and ThePlayer and ThePlayer.components.talker then
		ThePlayer.components.talker:Say(str)
	else
		ChatHistory:SendCommandResponse(str)
	end
end

function PLAYER_util:IsBusy()
	return ThePlayer and ThePlayer.components.playercontroller and
		ThePlayer.components.playercontroller:IsDoingOrWorking()
end

function PLAYER_util:IsHoldingItem(item, all)
	return item
		and item:IsValid() and ThePlayer and ThePlayer.replica.inventory and
		ThePlayer.replica.inventory:IsHolding(item, all)
end

function PLAYER_util:CalculateAimPos(a, b, c, d)
	if not a.x then
		a = a:GetPosition()
	end
	if not b.x then
		b = b:GetPosition()
	end
	if b.x == a.x then
		b.x = b.x + 0.1
	end
	if b.z == a.z then
		b.z = b.z + 0.1
	end
	local dx, dz = b.x - a.x, b.z - a.z
	local distance = math.sqrt(dx * dx + dz * dz)
	local cos, sin = dx / distance, dz / distance
	local aimdx = d * (math.cos(c) * cos - math.sin(c) * sin)
	local aimdz = d * (math.sin(c) * cos + math.cos(c) * sin)
	local aimx, aimz = a.x + aimdx, a.z + aimdz
	return Vector3(aimx, 0, aimz)
end

function PLAYER_util:ChangeFacing(pos, target)
	if target then
		local animpos = PLAYER_util:CalculateAimPos(ThePlayer:GetPosition(), target:GetPosition(), 0, 0.001)
		SendRPCToServer(RPC.PredictWalking, animpos.x, animpos.z)
		return
	end
	local animpos = PLAYER_util:CalculateAimPos(ThePlayer:GetPosition(), pos or TheInput:GetWorldPosition(), 0, 0.001)
	SendRPCToServer(RPC.PredictWalking, animpos.x, animpos.z)
end

function PLAYER_util:CancelCraft()
	local inventory = ThePlayer.replica.inventory
	local hand = inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
	local items = inventory:GetItems()
	if hand or next(items) then
		SendRPCToServer(RPC.InspectItemFromInvTile, hand or items[next(items)])
	end
end

function PLAYER_util:TryCraft(cancel)
	if not ThePlayer then return end
	if not ThePlayer.replica.builder then return end
	if ThePlayer.replica.inventory and not ThePlayer.replica.inventory:IsOpenedBy(ThePlayer) then return end
	for recname, rec in pairs(AllRecipes) do
		if IsRecipeValid(recname) and rec.placer == nil and ThePlayer.replica.builder:KnowsRecipe(recname) and
			ThePlayer.replica.builder:HasIngredients(recname) then
			if rec.sg_state == nil then
				SendRPCToServer(RPC.MakeRecipeFromMenu, rec.rpc_id)
				if cancel then
					self:CancelCraft()
				end
				return rec
			end
		end
	end
end

--ThePlayer.components.talker.widget.text.string
function PLAYER_util:GetSayingString()
	local talker = ThePlayer and ThePlayer.components and ThePlayer.components.talker
	local widget = talker and
		talker.widget
	local text = widget and widget.text
	return text and text.string
end

function PLAYER_util:CanSeeTarget(ent)
	if not ent then return end
	if ThePlayer.prefab == 'wathom' then return true end
	return TheSim:GetLightAtPoint(ent:GetPosition().x, 0, ent:GetPosition().z) > TUNING.DARK_CUTOFF
		or ThePlayer.components.playervision.nightvision
end

--停止走路
function PLAYER_util:StopWalk()
	local movementprediction = Profile:GetMovementPredictionEnabled()
	SendRPCToServer(RPC.SetMovementPredictionEnabled, not movementprediction)
	SendRPCToServer(RPC.SetMovementPredictionEnabled, movementprediction)
end

return PLAYER_util
