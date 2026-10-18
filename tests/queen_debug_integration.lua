-- 在真实走位/监督/扫描回归运行时打开日志，确认埋点本身也能工作。
local Debug=require("shadowself/control/queendebug")
local savedPrint=print;local lines={}
print=function(line) if type(line)=="string" and line:find("[ShadowSelf][QueenDebug]",1,true) then lines[#lines+1]=line end end
Debug.Configure(true)
local ok,why=pcall(assert(loadfile("tests/combat128.lua")))
Debug.Configure(false);print=savedPrint
assert(ok,why)
local text=table.concat(lines,"\n")
for _,event in ipairs({"fight_start","snapshot","dash_start","dash_end","native_pause","native_resume","attack_block","fight_end"}) do
 assert(text:find('event="'..event..'"',1,true),"missing integrated diagnostic event "..event)
end
assert(not text:find('event="logger_error"',1,true),"logger must not fail during real bridge execution")
if write_debug_integration_fixture then write_debug_integration_fixture("OFFLINE INTEGRATION FIXTURE - not live gameplay\n"..text) end
print("PASS: enabled QueenDebug attached to actual native dodge/supervisor/Scan regression emits decisions, movement phases, attack veto and lifecycle without logger errors")
