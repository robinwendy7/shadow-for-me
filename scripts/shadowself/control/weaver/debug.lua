local M={enabled=true,version="0.13.103-merge"}
function M.Configure(value) M.enabled=value~=false end
local function safe(v) return tostring(v):gsub("[\r\n\t ]","_"):sub(1,200) end
function M.Emit(w,event,detail)
    if not M.enabled then return end
    local t=GetTime();local second=math.floor(t)
    if w.logsecond~=second then w.logsecond=second;w.logcount=0 end
    if (w.logcount or 0)>=8 and event~="hurt" and event~="snare_caught" and event~="round_stage" and event~="cycle_bait_reserved"
        and event~="slow_tick" and event~="ranged_pending" and event~="ranged_complete" and event~="route_blocked" then return end
    w.logcount=(w.logcount or 0)+1
    local s=w.state or {};local p=w.c.player:GetPosition();local boss=w.boss
    local d=boss and boss:IsValid() and math.sqrt(p:DistSq(boss:GetPosition())) or -1
    local held=w.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    local gem=held and held._gem and held._gem.value and held._gem:value() or "none"
    local point=w.point
    print(string.format("[ShadowSelf][WeaverDebug] v=%s t=%.2f event=%s phase=%s anim=%s frame=%s distance=%.2f mode=%s target=%s shield=%s hands=%s ghosts=%d minions=%d pos=%.2f,%.2f goal=%s predict=%s cages=%d gem=%s detail=%s",
        M.version,t,event,tostring(s.phase or 0),s.anim or "?",tostring(s.frame or 0),d,w.mode or "?",
        w.focus and (w.focus.prefab..":"..tostring(w.focus.GUID)) or "none",tostring(s.shield),
        (w.c.player.replica.inventory:GetEquippedItem(EQUIPSLOTS.HANDS) or {}).prefab or "none",
        #(w.channelers or {}),#(w.minions or {}),p.x,p.z,
        point and string.format("%.2f,%.2f",point.x,point.z) or "none",tostring(w.c.h.shadowself_predicting),#(w.cages or {}),gem,safe(detail or "")))
end
function M.Sample(w,elapsed)
    local now=GetTime();w.lastcost=elapsed;w.tick_peak_ms=math.max(w.tick_peak_ms or 0,elapsed*1000)
    if elapsed>=.02 and now>=(w.nextslow or 0)then
        w.nextslow=now+.5
        M.Emit(w,"slow_tick",string.format("cost_ms=%.2f paths=%d grid_fallbacks=%d route=%s",elapsed*1000,w.route_paths or 0,w.route_grid_fallbacks or 0,
            w.retreat and w.retreat.mode or w.corner_dodge and "melee" or "none"))
    end
    local health=w.c.player.replica.health
    local hp=health and health.GetPercent and health:GetPercent()
    if hp and w.hp and hp<w.hp-.0001 then
        local near,d;local p=w.c.player:GetPosition()
        for _,e in ipairs(w.entities or {}) do if e.prefab=="fossilspike2" and e:IsValid() then
            local n=p:DistSq(e:GetPosition());if not d or n<d then near,d=e,n end
        end end
        local extra=""
        if near then
            local a=near.AnimState;local name=near.AnimState:IsCurrentAnimation("appear") and "appear" or "other"
            extra=string.format(" spike=%s:%s:%d distance=%.2f",tostring(near.GUID),name,a:GetCurrentAnimationFrame() or 0,math.sqrt(d))
        end
        M.Emit(w,"hurt","previous="..(w.previous or "unknown")..extra)
    end
    w.hp=hp
    if now>=(w.nextsample or 0) then
        w.nextsample=now+2
        local s=w.state
        local plan=w.phase1 or {}
        local goal=plan.goal or plan.anchor;local bp=w.boss:GetPosition();local p=w.c.player:GetPosition()
        M.Emit(w,"sample",string.format("paths=%d peak_ms=%.2f obs=%d flight=%.2f cycle=%s feeding=%d round=%s p1=%s bone=%d spike=%d side=%.2f boss_side=%.2f boss_center=%.2f san=%.3f speed=%.2f tick_ms=%.2f snare_est=%.2f exit=%.1f enough=%s unknown=%s cycle=%s feeding=%d ghost_window=%.2f fences=%d",
            w.route_paths or 0,w.tick_peak_ms or 0,#(w.obstacles or {}),w.staff_action and math.max(0,(w.staff_action.until_time or now)-now) or 0,
            w.cycle and w.cycle.stage or "none",w.cycle and w.cycle.feeding or 0,w.cycle and w.cycle.round or "first_recovery",
            plan.stage or "none",plan.snares or 0,plan.spikes or 0,
            goal and math.sqrt(p:DistSq(goal)) or -1,goal and math.sqrt(bp:DistSq(goal)) or -1,w.center and math.sqrt(bp:DistSq(w.center)) or -1,
            require("shadowself/control/weaver/observe").Sanity(w.c.player) or -1,w.c:Speed(),elapsed*1000,
            s and s.ready.snare and require("shadowself/control/weaver/observe").ReadyIn(s,"snare",now) or -1,
            w.escape_reach or -1,tostring(w.escape_enough),tostring(not (s and s.ready.snare)),
            w.cycle and w.cycle.stage or "none",w.cycle and w.cycle.feeding or 0,
            w.cycle and w.cycle.deadline and math.max(0,w.cycle.deadline-now) or 0,#(w.fences or {})))
        w.tick_peak_ms=0
    end
    w.previous=(w.mode or "?")..":"..(w.state.anim or "?")..":"..tostring(w.state.frame)
end
return M
