local M={}
function M.Late(c)
 local s=c and c.plan and c.plan.arena_doc_late
 return s and s:Active() and s or nil
end
function M.Continuous(c,e)
 local s=M.Late(c)
 if s then return s:Hold(e) or false end
 return require("shadowself/control/arena_doc_early").Continuous(c,e)
end
function M.Defensive(c,e)
 local s=M.Late(c);return s and s:Defensive(e) or false
end
function M.Allowed(c,e)
 if not require("shadowself/control/arena_doc_early").Allowed(c,e) then return false end
 local s=M.Late(c)
 if s and not s:Allowed(e) then return false end
 return not require("shadowself/control/arena_doc_boss").Block(c,e)
end
function M.Protect(c)
 require("shadowself/control/arena_doc_early").Protect(c)
 local s=M.Late(c);if s and s.Protect then s:Protect(c) end
end
function M.Commit(c,e)
 if not M.Continuous(c,e) then return false end
 if c.secondary then c.secondary.pending=nil end
 c.bridge.chasing=nil;c.travel.chasing=nil
 c.travel:EndDodge(c.snapshot);c.travel.role="attack"
 c.h.shadowself_dodging=nil;c.blocked=false;c.special_active=false;c.queen_active=false
 M.Protect(c);c.gear:Swap("attack",c.snapshot)
 return true
end
return M
