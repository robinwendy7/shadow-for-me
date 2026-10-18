local ACTIONS_util = {}

function ACTIONS_util:GiveItem()
    --[[   local item, k, con = INV_util:FindInInventory('cave_banana')
    if not INV_util:GetActiveItem() or not PLAYER_util:CanSeeTarget(act.target) then
        SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, k, con, nil)
        SendRPCToServer(RPC.LeftClick, ACTIONS.GIVE.code, act.target:GetPosition().x, act.target:GetPosition().z,
            act.target,
            nil, nil, true)
        SendRPCToServer(RPC.ReturnActiveItem, nil, nil, nil)
    else
        SendRPCToServer(RPC.ControllerUseItemOnSceneFromInvTile, ACTIONS.GIVE.code, item, act.target)
    end ]]
end

function ACTIONS_util:StopWalk()
    local movementprediction = Profile:GetMovementPredictionEnabled()
    SendRPCToServer(RPC.SetMovementPredictionEnabled, not movementprediction)
    SendRPCToServer(RPC.SetMovementPredictionEnabled, movementprediction)
end

return ACTIONS_util
