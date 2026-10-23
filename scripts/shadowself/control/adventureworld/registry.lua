-- 只记录本次世界的已加载实体和实际收到的公告，不将未知视为死亡。
local M={}
local C=require("shadowself/control/adventureworld/config")
function M.Reset(world) M.world=world;M.alive={{},{},{},{}};M.deaths={};M.seen={};M.dead_ids={} end
local function ensure() if M.world~=TheWorld or not M.alive then M.Reset(TheWorld) end end
function M.Grade(e)
    if not e or not e:IsValid() or not e:HasTag("adventure_boss") then return end
    for i=1,4 do if e:HasTag("level"..i) then return i end end
end
function M.InWorld(entities)
    local w=TheWorld;if not w then return false end
    local id=w.worldid
    if w.net then
        local field=w.net._shardid or w.net._worldid
        if field and field.value then local value=field:value();if value and value~="" then id=value end end
        local name=w.net._worldname
        if name and name.value and (name:value() or ""):find("冒险",1,true) then return true end
    end
    if id and C.world_ids[tostring(id)] then return true end
    for _,e in ipairs(entities or {}) do if M.Grade(e) then return true end end
    return false
end
function M.Dead(e)
    return e and e:IsValid() and (e:HasTag("dead") or e:HasTag("isdead")
        or e:HasTag("corpse") or e.replica and e.replica.health and e.replica.health:IsDead()
        or e.AnimState and e.AnimState:IsCurrentAnimation("death")) or false
end
function M.OnAnnouncement(message)
    ensure();if type(message)~="string" then return end
    for i,label in ipairs(C.grades) do
        local name=message:match("冒险世界的"..label.."级(.-)已刷新")
        if name and name~="" then
            M.alive[i][name]=GetTime();M.deaths[i..":"..name]=nil
            if name=="墨荒三相" then
                for _,prefab in ipairs({"SHADOWTHRALL_HORNS","SHADOWTHRALL_WINGS","SHADOWTHRALL_HANDS"}) do
                    local n=STRINGS and STRINGS.NAMES and STRINGS.NAMES[prefab] or prefab
                    M.deaths[i..":"..n]=nil
                end
            end
            return
        end
        name=message:match("冒险世界的"..label.."级(.-)被.+击杀")
        if name and name~="" then
            M.alive[i][name]=nil;M.deaths[i..":"..name]=GetTime()
            -- 墨荒三相公告是整组刷新、成员逐个死亡。
            local all=true
            for _,prefab in ipairs({"SHADOWTHRALL_HORNS","SHADOWTHRALL_WINGS","SHADOWTHRALL_HANDS"}) do
                local n=STRINGS and STRINGS.NAMES and STRINGS.NAMES[prefab] or prefab
                if not M.deaths[i..":"..n] then all=false end
            end
            if all then M.alive[i]["墨荒三相"]=nil end
            return
        end
    end
end
function M.Observe(entities)
    ensure()
    for _,e in ipairs(entities) do
        local grade=M.Grade(e)
        if grade then
            local name=e:GetBasicDisplayName() or e.prefab
            if M.Dead(e) then
                if not M.dead_ids[e.GUID] then
                    M.seen[e.GUID]=nil;M.alive[grade][name]=nil;M.deaths[grade..":"..name]=GetTime()
                    M.dead_ids[e.GUID]=true
                end
            else
                M.dead_ids[e.GUID]=nil
                M.alive[grade][name]=GetTime()
                local p=e:GetPosition();M.seen[e.GUID]={entity=e,grade=grade,name=name,x=p.x,z=p.z,time=GetTime()}
            end
        end
    end
end
function M.WasKilled(grade,name,since)
    ensure();return (M.deaths[grade..":"..name] or -math.huge)>=since
end
function M.Available(grade) ensure();return next(M.alive[grade])~=nil end
function M.Report()
    ensure();local lines={}
    for i,label in ipairs(C.grades) do
        local names={};for name in pairs(M.alive[i]) do names[#names+1]=name end;table.sort(names)
        if #names>0 then lines[#lines+1]=label.."："..table.concat(names,"、") end
    end
    return #lines>0 and table.concat(lines,"；") or "本次在线还没有 Boss 存活公告；上线前的刷新情况未知，可以用猪鼻铸币探测。"
end
function M.Install(G)
    ensure();local history=G.ChatHistory
    if not history or history._shadowself_adventure_announcement then return end
    local old=history.OnAnnouncement;if not old then return end
    history._shadowself_adventure_announcement=true
    history.OnAnnouncement=function(self,message,...)
        M.OnAnnouncement(message);return old(self,message,...)
    end
end
return M
