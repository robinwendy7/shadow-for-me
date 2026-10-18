-- 蜂后调试已移除。保留空接口供历史调用点使用，不采样、不计数、不打印。
local M={VERSION="0.12.21",enabled=false}
local function noop() end
for _,name in ipairs({"Configure","Start","Event","Change","Throttle","Block","Performed","Equip","Move","Hit","Sample"}) do M[name]=noop end
function M.End(c) if c then c._queen_debug=nil end end
function M.Entity(e) return e and tostring(e.prefab or "?") or "none" end
function M.Point() return "" end
return M
