-- 仅在战斗接管运行；食物消耗被库存确认后才开始计算buff时间。
local A=require("shadowself/control/actions")
local Supplies=Class(function(self,c)
    self.c=c;self.player=c.player
    self.state=self.player._shadowself_combat_buffs or {}
    self.player._shadowself_combat_buffs=self.state
end)
local function jelly(item) return item.prefab=="voltgoatjelly" or item.prefab=="voltgoatjelly_spice_chili" end
function Supplies:Count(name)
    local count=0
    for _,i in ipairs(A.Items(self.player)) do if i.prefab==name then
        local stack=i.replica and i.replica.stackable
        count=count+(stack and stack:StackSize() or 1)
    end end
    return count
end
function Supplies:Active(name,untiltime)
    local d=self.player.components and self.player.components.debuffable
    if d and d.HasDebuff then return d:HasDebuff(name) end
    return GetTime()<(untiltime or 0)
end
-- 睡眠不排除：这里判断的是闪电连锁会不会波及守卫，而不是守卫是否有威胁。
function Supplies:QueenBlocksChili()
    local c=self.c;local q=c.beequeen;local queen
    for _,e in ipairs(c.enemies or {}) do
        if e.prefab=="beequeen" and e:IsValid() and not e:HasTag("isdead") and not e:HasTag("dead") then queen=e;break end
    end
    if not queen and c.queen_active and q then queen=q.queen end
    if not queen or not queen:IsValid() or queen:HasTag("isdead") or queen:HasTag("dead") then return false end
    -- 一阶段维持禁用；下崽尚未结束时不能把尚未同步完整的名单当成安全距离。
    if not q or q.queen~=queen or (q.phase or 1)<2 or q.spawn_wait
        or queen.AnimState and queen.AnimState:IsCurrentAnimation("spawn") then return true end
    local qp=queen:GetPosition()
    local function near(e)
        if e.prefab~="beeguard" or not e:IsValid() or e:HasTag("isdead") or e:HasTag("dead") or e:HasTag("INLIMBO") then return false end
        local health=e.replica and e.replica.health
        return not (health and health.IsDead and health:IsDead()) and qp:DistSq(e:GetPosition())<=10^2
    end
    for _,e in ipairs(q.debug_bees or {}) do if near(e) then return true end end
    for e in pairs(q.roster or {}) do if near(e) then return true end end
    for _,e in ipairs(c.enemies or {}) do if near(e) then return true end end
    return false
end
function Supplies:Tick()
    local now=GetTime();local state=self.state;local pc=self.player.components.playercontroller
    local pending=self.pending
    if pending then
        if self:Count(pending.name)<pending.count then
            state.electric_until=now+(TUNING.BUFF_ELECTRICATTACK_DURATION or 300)
            if pending.name=="voltgoatjelly_spice_chili" then state.attack_until=now+(TUNING.BUFF_ATTACK_DURATION or 240) end
            self.pending=nil;return pc:IsBusy()
        elseif now<pending.deadline then return pc:IsBusy() or now<(pending.grace or pending.deadline)
        else self.pending=nil;self.next_try=now+3;return false end
    end
    if now<(self.next_try or 0) or self.c.travel and self.c.travel.dodging or self.c.bridge.chasing then return false end
    for _,e in ipairs(self.c.enemies or {}) do
        if (self.c.observed[e.GUID] or {}).dodge then
            local range=require("shadowself/control/navigation").Radius(e)
            if self.player:GetPosition():DistSq(e:GetPosition())<(range+1)^2 then return false end
        end
    end
    local electric=self:Active("buff_electricattack",state.electric_until)
    -- 二阶段起，蜂后与所有守卫相隔超过10码才恢复普通补吃/续buff流程。
    local block_chili=self:QueenBlocksChili()
    local preferred
    for _,i in ipairs(A.Items(self.player)) do if jelly(i) and i:IsValid() and not (block_chili and i.prefab=="voltgoatjelly_spice_chili") then
        if not preferred or i.prefab=="voltgoatjelly_spice_chili" then preferred=i end
    end end
    if not preferred then return false end
    local refresh_chili=preferred.prefab=="voltgoatjelly_spice_chili" and state.attack_until
        and not self:Active("buff_attack",state.attack_until)
    if electric and not refresh_chili then return false end
    if pc:IsBusy() or self.player:HasTag("attack") then
        -- 停掉下一轮攻击调度，让已开始的一刀自然结束，给进食留下空档。
        self.c.bridge:PauseAttack();return true
    end
    local count=self:Count(preferred.prefab)
    if A.Self(self.player,preferred,ACTIONS.EAT) then
        local latency=TheNet and TheNet.GetPing and TheNet:GetPing()/1000 or 0
        self.pending={name=preferred.prefab,count=count,deadline=now+math.max(3,latency*2+1.5),grace=now+.5+latency*2};self.next_try=now+1;return true
    end
    self.next_try=now+3;return false
end
return Supplies
