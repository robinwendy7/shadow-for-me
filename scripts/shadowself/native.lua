-- 3014走A/走位和37503函数库独立运行，不发布全局同名接口。
local M={}
function M.Get() return M.context or _G end
function M.Init(root)
    if M.context then return M.context end
    local g=_G
    local tuning=setmetatable({},{__index=function(_,k) if k~="Cheatthread" then return g.TUNING[k] end end})
    local env=setmetatable({TUNING=tuning,m_options={},MODROOT=root},{__index=function(_,key) return rawget(g,key) end})
    -- CMP utility records prefab constructors; isolate its class table too.
    if g.Prefab then
        local prefab={};for k,v in pairs(g.Prefab) do prefab[k]=v end
        env.Prefab=setmetatable(prefab,getmetatable(g.Prefab))
    end
    env.GLOBAL=env;env._G=env;env.env=env
    env.BufferedAction=function(...)
        local act=g.BufferedAction(...);act._shadowself_native=true;return act
    end
    env.GetModConfigData=function() return nil end
    local function load(path)
        local fn=assert(kleiloadlua(root.."scripts/shadowself/native/"..path..".lua"))
        setfenv(fn,env);return fn()
    end
    env.modimport=function(path) return load("engine/"..path:match("([^/]+)$")) end
    for _,name in ipairs({"RW","ENT","MOD","GAME","INV","PLAYER","POS","KEY","EQUIP","HUD","MAP","HACKER","ACTIONS","CMP"}) do
        env[name.."_util"]=load("utils/"..name.."_util")
    end
    env.MOD_util.fixrpc=function() end
    env.MOD_util.Ismmdx=function() return false end
    env.MOD_util.GetMOption=function(_,key,default) local v=env.m_options[key];if v~=nil then return v end;return default end
    env.RW_util.LoadData=function() return {} end
    env.MOD_util.AddKeyDownHandler=function() end;env.MOD_util.AddKeyUpHandler=function() end
    -- Only this private engine dispatches normal RPC handlers for a local host.
    -- No NetworkProxy override and no custom/server-side Mod RPC registration.
    local rpc_handlers
    env.SendRPCToServer=function(code,...)
        if g.TheWorld and g.TheWorld.ismastersim then
            rpc_handlers=rpc_handlers or env.MOD_util:GetUpvalue_deekseek(g.HandleRPC,"RPC_HANDLERS")
            local fn=rpc_handlers and rpc_handlers[code]
            if fn and g.ThePlayer then
                local pc=g.ThePlayer.components and g.ThePlayer.components.playercontroller
                local handler=pc and pc.handler
                local native_rpc=pc and pc._shadowself_native_rpc
                -- 原版OnRemoteLeftClick/Attack仅处理无本机handler的远程输入。
                -- 只在此同步调用期间暂借入口，返回或报错均恢复本机输入。
                if pc then pc.handler=nil;pc._shadowself_native_rpc=true end
                local result={pcall(fn,g.ThePlayer,...)}
                if pc then pc.handler=handler;pc._shadowself_native_rpc=native_rpc end
                if not result[1] then error(result[2],0) end
                return unpack(result,2)
            end
            return
        end
        return g.SendRPCToServer(code,...)
    end
    load("engine/HitAndRun")
    env.HitAndRun.movementswitch=false;env.HitAndRun.dodgetest=true
    M.context=env;return env
end
return M
