-- 延迟预算用于提前决策，不修改实际怪物帧或人物移速。
local M={}
function M.Delay(c)
 if c and c.Latency then return c:Latency() end
 local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
 return math.min(.6,ping/1000+.1)
end
function M.Frames(c) return math.ceil(M.Delay(c)/(FRAMES or 1/30)) end
function M.Speed(c) return math.max(1,math.min(6,c.Speed and c:Speed() or 6)) end
function M.Remote() return TheWorld and TheWorld.ismastersim==false end
return M
