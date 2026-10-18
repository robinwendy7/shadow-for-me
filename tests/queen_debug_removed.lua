local D=require("shadowself/control/queendebug")
local old=print;local count=0;print=function() count=count+1 end
local c={};D.Configure(true)
for _,name in ipairs({"Start","Event","Change","Throttle","Block","Performed","Equip","Move","Hit","Sample","End"}) do D[name](c) end
assert(not D.enabled and not c._queen_debug and count==0,"retired queen debug must do no logging or tracking")
print=old;print("PASS: queen debug disabled permanently; all legacy calls are no-ops")
