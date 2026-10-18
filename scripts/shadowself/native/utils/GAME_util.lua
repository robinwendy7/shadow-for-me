local GAME_util = {}

function GAME_util:GetGameDelay()
    return TheNet:GetPing() / (1000 * FRAMES)
end

--
function GAME_util:InGame()
    return ThePlayer and ThePlayer.HUD and (not ThePlayer.HUD:HasInputFocus() or require("shadowself/control/combatinput").AllowTyping(ThePlayer))
end

function GAME_util:IsNight()
    return TheWorld and TheWorld.state.isnight
end

function GAME_util:GetDays()
    return TheWorld and TheWorld.state.cycles
end

function GAME_util:AddClientCommand(command_string, params_table, client_command_fn)
    local command_data = {
        name = command_string,
        prettyname = nil,
        desc = nil,
        permission = COMMAND_PERMISSION.USER,
        slash = true,
        usermenu = false,
        servermenu = false,
        params = params_table,
        localfn = client_command_fn
    }
    AddUserCommand(command_data.name, command_data)
end

function GAME_util:AddKeyAndMouseComboFn(funct, mouse, ...)
    local keys = { ... }
    TheInput:AddMouseButtonHandler(function(button, down, x, y)
        if not down then return false end
        if keys then
            for k, v in pairs(keys) do
                if not TheInput:IsKeyDown(v) then
                    return false
                end
            end
        end
        if button == mouse then
            funct()
        end
    end)
end

-- 不迁入来源模组的账号惩罚／批量安装订阅逻辑。
return GAME_util
