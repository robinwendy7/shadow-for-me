-- 仅限制本Mod发起的动作，不替换全局RPC，不排队重放过期的目标/坐标。
local M={}
local states=setmetatable({},{__mode="k"})
local limits={move={.1,.25},attack={.15,.15},item={.1,.4},scene={.1,.25}}
local function state(player)
 local now=GetTime();local s=states[player]
 if not s or now<s.now then s={now=now,serial=0};states[player]=s end
 s.now=now;return s,now
end
local function host(player)
 local pc=player.components and player.components.playercontroller
 return pc and pc.ismastersim
end
function M.Take(player,lane,key,point)
 if host(player) then return true end -- 本地主机没有这条网络RPC。
 local s,now=state(player);local last=s[lane];local interval=limits[lane]
 local same=last and last.key==key
 if point and same then same=last.x and (point.x-last.x)^2+(point.z-last.z)^2<.25^2 end
 if last and now-last.time+1e-7<(same and interval[2] or interval[1]) then return false end
 s[lane]={time=now,key=key,x=point and point.x,z=point and point.z}
 if lane=="attack" and s.move then s.move.key={} end -- 反打后允许重新提交同落点，仍守100ms间隔。
 s.serial=s.serial+1
 return true
end
function M.Move(player,point)
 local platform=player.GetCurrentPlatform and player:GetCurrentPlatform()
 return M.Take(player,"move",platform,point)
end
function M.Attack(player,target) return M.Take(player,"attack",target) end
function M.Action(player,action,target,item,point)
 if not action then return false end
 local definitions=rawget(_G,"ACTIONS")
 if (action.id=="WALKTO" or definitions and action==definitions.WALKTO) and point then return M.Move(player,point) end
 if action.id=="ATTACK" or definitions and action==definitions.ATTACK then return M.Attack(player,target) end
 local key=tostring(action.code)..":"..tostring(target)..":"..tostring(item)
 return M.Take(player,target and "scene" or "item",key)
end
function M.Stop(player)
 if host(player) then return true end
 local s,now=state(player)
 -- 新操作后的首次停手立即通过；无新操作的重复Stop每200ms至多一组。
 if s.stop and s.stop.serial==s.serial and now-s.stop.time<.2 then return false end
 s.stop={time=now,serial=s.serial}
 if s.move then s.move.key={} end -- 停止后需重发移动，但不能用Stop绕过最短间隔。
 return true
end
return M
