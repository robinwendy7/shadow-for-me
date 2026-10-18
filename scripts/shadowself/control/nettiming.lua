-- 侧方冲刺及支持动作的延迟辅助；原生走位沿用GAME_util帧计算。
local M={}
function M.Delay(c)
 if c and c.Latency then return c:Latency() end
 local ping=TheNet and TheNet.GetPing and TheNet:GetPing() or 0
 return math.min(.6,ping/1000+.1)
end
function M.Frames(c) return math.ceil(M.Delay(c)/(FRAMES or 1/30)) end
return M
