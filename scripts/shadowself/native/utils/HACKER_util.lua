local HACKER_util = {}
function HACKER_util:ReadFileStr(path, modname)
    if modname then
        path = "../mods/" .. modname .. "/" .. path
    end
    local file = io.open(path, "r")
    if not file then return end;
    local str = file:read("*a")
    --print(str)
    file:close()
    return str
end

function HACKER_util:WriteStrToFile(str, path, modname)
    if modname then
        path = "mods/" .. modname .. "/" .. path
    end
    RW_util:SaveData(str, path)
end

return HACKER_util
