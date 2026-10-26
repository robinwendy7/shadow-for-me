-- Read-only adapters. Never invoke arena Prepare/Send/Tick or combat controls.
local M={}
local function call(obj,name,...)
    if not obj or type(obj[name])~="function" then return nil end
    local ok,a,b,c=pcall(obj[name],obj,...)
    if ok then return a,b,c end
end
M.Call=call
local animations={"atk2_pre","atk2_loop","atk2_pst","atk_skid","atk_collide","paw_loop","dropkick_pre","dropkick_loop","short_pre","med_pre","tall_pre","short_pst","med_pst","tall_pst","short","med","tall","cast_pre","cast","rumble","explode","row_pre","row_loop","row_pst","hit_spike","eat_pre","eat","quick_eat_pre","quick_eat","atk","atk_pre","attack","attack_pre","ground_pound","hopatk","hopatk_loop","atk1","atk2","atk1a","charge","run_pre","run_loop","hit","death","idle","idle_loop","sleep_loop","taunt","disarm","frozen","jump","chomp","bite"}
function M.Entity(e,p)
    if not e or call(e,"IsValid")==false then return nil end
    local v=call(e,"GetPosition");local q=p and call(p,"GetPosition")
    local a=e.AnimState;local anim
    if a then for _,name in ipairs(animations) do if call(a,"IsCurrentAnimation",name) then anim=name;break end end end
    return {prefab=e.prefab or "unknown",guid=e.GUID,
        distance=v and q and math.sqrt((v.x-q.x)^2+(v.z-q.z)^2) or nil,
        x=v and v.x,z=v and v.z,animation=anim or "unidentified",frame=call(a,"GetCurrentAnimationFrame"),
        rotation=call(e.Transform,"GetRotation"),dead=call(e.replica and e.replica.health,"IsDead") or call(e,"HasTag","isdead") or call(e,"HasTag","dead") or false,
        hp_percent=call(e.replica and e.replica.health,"GetPercent")}
end
function M.New(G)
    local C={G=G}
    function C:Build()
        local result={status="unverified",observed={}}
        for _,mod in ipairs(G.ModManager and G.ModManager.mods or {}) do
            local info=mod.modinfo or call(G.ModIndex,"GetModInfo",mod.modname)
            if mod.modname=="workshop-3821474072" or (mod.modname or ""):find("shadow-for-me",1,true) then
                result.observed[#result.observed+1]={directory=mod.modname,version=info and info.version}
            end
        end
        local ok,marker=pcall(require,"scd_test_build")
        if ok and type(marker)=="table" and type(marker.commit)=="string" and #marker.commit==40
            and marker.commit:match("^[0-9a-f]+$") and marker.build_id
            and type(marker.manifest_sha256)=="string" and #marker.manifest_sha256==64 and marker.manifest_sha256:match("^[0-9a-f]+$")
            and #result.observed==1 and result.observed[1].directory==marker.mod_directory
            and result.observed[1].version==marker.mod_version then
            result.status="verified";result.commit=marker.commit;result.mod_version=marker.mod_version
            result.build_id=marker.build_id;result.manifest_sha256=marker.manifest_sha256
            result.evidence="tester_verified_install_manifest_and_loaded_mod_metadata"
        end
        return result
    end
    function C:Level(p)
        local r=p._shadowself;local control=r and r.control
        local arena=control and control.jobs and control.jobs.arena
        local adapter=arena and arena.adapter
        local hud=adapter and adapter.hud
        -- Already-loaded ASTRA module is optional; no dependency on a particular load order.
        if not hud then
            local H=package.loaded["astra/ui/mode_hud_client"]
            if H and H.New and self.hud_player~=p then
                local ok,value=pcall(H.New,p)
                if ok then self.hud=value;self.hud_player=p end
            end
            hud=self.hud_player==p and self.hud or nil
        end
        if hud then
            call(hud,"Refresh")
            local model=call(hud,"GetModel")
            local id,generation,kind=call(hud,"GetTarget")
            if model and model.visible~=false and kind=="PARTICIPANT" and id
                and (model.mode_id=="ARENA" or (model.title or ""):find("角斗场",1,true)) then
                local result={instance=tostring(id),generation=generation,source="astra_hud",title=model.title}
                for _,row in ipairs(model.rows or {}) do
                    if row.id=="wave" then result.wave=tonumber(tostring(row.value or ""):match("^(%d+)"));result.wave_label=tostring(row.value or "") end
                    if row.id=="route" then result.route=tostring(row.value or "") end
                end
                if result.wave then return result end
            end
        end
        return {source="unavailable",wave_label="未识别关卡（可用 MarkStage 手动标记）"}
    end
    function C:Snapshot(p,scan)
        local r=p._shadowself;local c=r and r.control
        local arena=c and c.jobs and c.jobs.arena
        local bridge=arena and arena.bridge or c and c.combat
        local co=bridge and bridge.coordinator
        local inv=p.replica and p.replica.inventory;local pos=call(p,"GetPosition")
        local h=p.replica and p.replica.health
        local state=G.TheWorld and G.TheWorld.state or {}
        local result={character=p.prefab,hp=call(h,"GetCurrent"),max_hp=call(h,"Max"),health_percent=call(h,"GetPercent"),
            x=pos and pos.x,z=pos and pos.z,ping_ms=call(G.TheNet,"GetPing"),
            ghost=call(p,"HasTag","playerghost") or false,corpse=call(p,"HasTag","corpse") or false,
            dead=call(p,"HasTag","isdead") or false,busy=call(p.components and p.components.playercontroller,"IsBusy"),
            frozen=call(p,"HasTag","frozen"),burning=call(h,"IsTakingFireDamage"),
            hunger_percent=call(p.replica and p.replica.hunger,"GetPercent"),sanity_percent=call(p.replica and p.replica.sanity,"GetPercent"),
            day=state.cycles and state.cycles+1,season=state.season,night=state.isnight,
            takeover_phase=c and c.phase or "stopped",task=c and c.task and c.task.kind,
            arena_status=arena and arena.message,combat_status=co and co.status,
            run_speed=call(p.components and p.components.locomotor,"GetRunSpeed"),
            platform=M.Entity(call(p,"GetCurrentPlatform"),p),
            target=M.Entity(co and co.target or bridge and bridge.h and bridge.h.ent,p),
            player=M.Entity(p),gear={}}
        for _,name in ipairs({"HANDS","HEAD","BODY"}) do
            local slot=G.EQUIPSLOTS and G.EQUIPSLOTS[name]
            local item=slot and call(inv,"GetEquippedItem",slot)
            local ii=item and item.replica and item.replica.inventoryitem
            local raw=ii and ii.classified and call(ii.classified.percentused,"value")
            result.gear[name]=item and {prefab=item.prefab,guid=item.GUID,percent=type(raw)=="number" and raw<=100 and raw/100 or nil} or {prefab="empty"}
        end
        if scan and pos then
            local enemies={}
            for _,e in ipairs(call(G.TheSim,"FindEntities",pos.x,0,pos.z,20,nil,{"INLIMBO","FX","DECOR","playerghost","isdead","dead"}) or {}) do
                if e~=p and not call(e,"HasTag","player") and e.replica and e.replica.combat then enemies[#enemies+1]=M.Entity(e,p) end
            end
            table.sort(enemies,function(a,b) return (a.distance or 999)<(b.distance or 999) end)
            result.nearby={};for i=1,math.min(12,#enemies) do result.nearby[i]=enemies[i] end
            result.nearby_total=#enemies
        end
        return result
    end
    return C
end
return M
