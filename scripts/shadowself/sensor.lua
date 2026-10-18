local C=require("shadowself/config")
local Sensor=Class(function(self,runtime)
    self.r=runtime; self.previous={}; self.near={}; self.initial=true;self.battles={}
end)
local function percent(owner,name)
    local replica=owner.replica and owner.replica[name]
    return replica and replica:GetPercent() or 1
end
function Sensor:Sample()
    local r=self.r; local p=r.owner; local old=self.previous
    local x,y,z=p.Transform:GetWorldPosition()
    local w=TheWorld.state
    local c={night=w.isnight==true,rain=w.israining==true,snow=w.issnowing==true,
        sanity=percent(p,"sanity"),hunger=percent(p,"hunger"),health=percent(p,"health"),
        tile=TheWorld.Map:GetTileAtPoint(x,0,z),phase=w.phase,season=w.season,
        cave=TheWorld:HasTag("cave"),danger=0,company=0}
    c.low_sanity=c.sanity<.25
    c.phase_index=({day=0,dusk=1,night=2})[c.phase] or 3
    c.season_index=({autumn=0,winter=1,spring=2,summer=3})[c.season] or 0
    local found={}; local building,tree=false,false
    for _,e in ipairs(TheSim:FindEntities(x,y,z,C.radius,nil,{"INLIMBO","FX","NOCLICK","DECOR"})) do
        if e~=p and e:IsValid() then
            local living=e:HasTag("_combat") or e:HasTag("monster") or e:HasTag("animal") or e:HasTag("player")
            if living then found[e.GUID]=e.prefab or "unknown" end
            if e:HasTag("player") then c.company=c.company+1 end
            if e:HasTag("monster") or e:HasTag("hostile") then c.danger=c.danger+1; c.monster=true end
            if e:HasTag("spider") then c.spider=true end
            if e:HasTag("epic") then c.boss=true end
            if e:HasTag("structure") then building=true end
            if e:HasTag("tree") then tree=true end
            if (e:HasTag("campfire") or e:HasTag("fire")) and e.Light and e.Light:IsEnabled() then
                local fx,fy,fz=e.Transform:GetWorldPosition()
                if (fx-x)^2+(fz-z)^2<100 then c.firepos={x=fx,y=fy,z=fz} end
            end
        end
    end
    local playercombat=p.replica and p.replica.combat
    local current=playercombat and playercombat.GetTarget and playercombat:GetTarget()
    for _,e in ipairs(TheSim:FindEntities(x,y,z,15,{"_combat"},{"INLIMBO"})) do
        local combat=e.replica and e.replica.combat
        if e~=p and (current==e or combat and combat.GetTarget and combat:GetTarget()==p) then
            self.battles[e]={time=GetTime(),boss=e:HasTag("epic")}
        end
    end
    for e,entry in pairs(self.battles) do
        local health=e.replica and e.replica.health
        if e:IsValid() and health and health.IsDead and health:IsDead() then
            r:Emit("victory",entry.boss and 80 or 40,entry.boss and "倒下了。你做到了……先看看自己的伤。" or nil)
            self.battles[e]=nil
        elseif not e:IsValid() or GetTime()-entry.time>20 then self.battles[e]=nil end
    end
    r.context=c
    local cycles=w.cycles or 0
    if r.memory.day~=cycles then r.memory.day=cycles; r.memory.died_today=false; r.memory.ate_today=false end
    if c.cave and not r.memory.first_cave then
        r.memory.first_cave=true; r:Emit("cave",75,"原来下面还有黑暗。走吧，我认得你的脚步。")
    end
    if c.boss and not r.memory.first_boss then
        r.memory.first_boss=true; r:Emit("boss",90,"你挑的对手真会长个子。别把自己留在这里。")
    end
    if not self.initial then
        if c.health<old.health-.005 and not r.dead then if r.concern then r.concern:Hit() end;r:Emit("hurt") end
        -- 饱食度上升只是吃东西的代理信号（有治疗/特殊能力的误判可能）。
        if c.hunger>old.hunger+.025 then r.memory.ate_today=true; r:Emit("eat") end
        if c.hunger<.18 and old.hunger>=.18 then r:Emit("hunger") end
        if math.abs(c.sanity-old.sanity)>.05 or c.low_sanity~=old.low_sanity then r:Emit("sanity") end
        if c.phase~=old.phase then r:Emit(c.phase or "day") end
        if c.season~=old.season then r:Emit("season") end
        if c.rain and not old.rain then r:Emit("rain") end
        if c.snow and not old.snow then r:Emit("snow") end
        if c.tile~=old.tile then
            r:Emit("terrain")
            if not r.memory.tiles[tostring(c.tile)] then
                r.memory.tiles[tostring(c.tile)]=true; r:Emit("region")
            end
        end
        if c.monster and not old.monster then r:Emit("monster") end
        if c.firepos and not old.firepos then r:Emit("fire") end
        if c.low_sanity and c.night and c.spider then r:Emit("nightmare") end
        if not old.building and building then r:Emit("building") end
        if not old.tree and tree then r:Emit("tree") end
        local added,removed=false,false
        for id in pairs(found) do if not self.near[id] then added=true; break end end
        for id in pairs(self.near) do if not found[id] then removed=true; break end end
        if added then r:Emit("spawn") end
        if removed then r:Emit("despawn") end
    end
    -- 快速远离已知威胁，用作“逃跑”代理。
    if c.monster and old.x and (x-old.x)^2+(z-old.z)^2>16 then r:Emit("runaway") end
    c.x,c.z=x,z; c.building=building; c.tree=tree
    self.previous=c; self.near=found; self.initial=false
    return c
end
function Sensor:ObserveAction()
    local r=self.r; local p=r.owner
    local anim=nil
    for name in pairs(C.action_anims) do
        if p.AnimState:IsCurrentAnimation(name) then anim=name; break end
    end
    if anim~=self.anim then
        self.anim=anim
        local event=C.action_anims[anim]
        if event and event~="death" then
            if event=="eat" then r.memory.ate_today=true;r.memory.last_eat=GetTime() end
            if event=="hurt" and r.concern then r.concern:Hit() end
            r:Emit(event)
        end
    end
end
return Sensor
