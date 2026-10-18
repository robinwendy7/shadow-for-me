local KEY_util = {}

function KEY_util:MoveKeyDown()
    if require("shadowself/control/combatinput").AllowTyping(ThePlayer) then return false end
    return ThePlayer and ThePlayer.components.playercontroller and
        ThePlayer.components.playercontroller:IsAnyOfControlsPressed(CONTROL_MOVE_UP, CONTROL_MOVE_DOWN,
            CONTROL_MOVE_LEFT, CONTROL_MOVE_RIGHT)
end

function KEY_util:ControlDown(control)
    return TheInput:IsControlPressed(control)
    --return ThePlayer and ThePlayer.components.playercontroller:IsControlPressed(control)
end

function KEY_util:ActionKeyDown()
    return self:ControlDown(CONTROL_ACTION)
end

function KEY_util:AttackKeyDown()
    return self:ControlDown(CONTROL_ATTACK)
end

function KEY_util:ShiftDown()
    return self:ControlDown(CONTROL_FORCE_TRADE)
end

function KEY_util:AltDown()
    return self:ControlDown(CONTROL_FORCE_INSPECT)
end

function KEY_util:CtrlDown()
    return self:ControlDown(CONTROL_FORCE_STACK)
end

return KEY_util
