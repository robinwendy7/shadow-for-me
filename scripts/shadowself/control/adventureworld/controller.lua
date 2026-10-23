-- 冒险总流程：记录 -> 测向 -> 开表/赶路 -> 实体确认 -> 既有战斗 -> 下一轮。
-- 不另起移动或施法协程；战斗期间仅由Combat/Coordinator(含Maxwell)下发动作。
local A=require("shadowself/control/actions")
local C=require("shadowself/control/adventureworld/config")
local R=require("shadowself/control/adventureworld/registry")
local Locator=require("shadowself/control/adventureworld/locator")
local Watch=require("shadowself/control/adventureworld/watch")
local Adventure=Class(function(self,p,plan,report)
    self.player=p;self.plan=plan;self.report=report or function() end;self.running=true
    self.bridge=require("shadowself/control/combat")(p)
    self.travel=require("shadowself/control/travel")(p)
    self.phase="select";self.probed={};self.cursor=0;self.retries=0;self.started=GetTime()
end)
function Adventure:Say(key,message)
    if self.notice~=key then self.notice=key;self.report(message) end
end
function Adventure:OwnsCombat() return self.bridge:Running() end
function Adventure:Cancel()
    self.running=false;self.locator=nil
    if self.watch then self.watch:Cancel();self.watch=nil end
    self.bridge:Stop();self.travel:Reset();A.Stop(self.player)
end
function Adventure:Scan()
    if GetTime()<(self.next_scan or 0) then return self.entities end
    local p=self.player:GetPosition()
    self.entities=TheSim:FindEntities(p.x,0,p.z,C.scan_radius,nil,{"INLIMBO","FX","DECOR","playerghost"})
    self.next_scan=GetTime()+C.scan_interval;R.Observe(self.entities);return self.entities
end
function Adventure:Matches(e)
    local grade=R.Grade(e)
    if not grade or R.Dead(e) or self.plan.grade and grade~=self.plan.grade then return false end
    if self.plan.boss then return e.prefab==self.plan.boss or e:GetBasicDisplayName()==self.plan.boss end
    return true
end
function Adventure:Nearest(entities)
    local target,best
    for _,e in ipairs(entities) do if self:Matches(e) then local d=self.player:GetDistanceSqToInst(e)
        if not best or d<best then target,best=e,d end
    end end
    return target
end
function Adventure:Move(point)
    local p=self.player;local now=GetTime()
    if p.components.playercontroller:IsBusy() then return end
    if not TheWorld.Map:IsPassableAtPoint(point.x,0,point.z) then self.blocked=true;return end
    self.travel:Tick(point)
    if now>=(self.next_move or 0) then A.Move(p,point);self.next_move=now+C.movement_interval end
    local pos=p:GetPosition()
    if not self.progress_point or pos:DistSq(self.progress_point)>2^2 then self.progress_point=pos;self.progress_at=now end
    if now-(self.progress_at or now)>C.stalled_timeout then self.blocked=true end
end
function Adventure:StartFight(target)
    self.locator=nil;if self.watch then self.watch:Cancel();self.watch=nil end
    A.Stop(self.player);self.travel:Reset();self.target=target
    self.fight_started=GetTime();self.target_grade=R.Grade(target)
    self.target_name=target:GetBasicDisplayName() or target.prefab;self.phase="fight"
    local plan={kind="fight",coordinated=true,target="",adventure=true,
        adventure_contains=function(e) return self:Matches(e) end}
    local ok,why=self.bridge:Start(plan,function() return false end)
    if not ok then return "failed",why end
    self:Say("fight:"..target.GUID,"找到"..self.target_name.."了，接入战斗。麦斯威尔会沿用暗影秘典禁锢。")
    return "running"
end
function Adventure:Grade()
    local now=GetTime()
    if self.plan.grade then
        if now>=(self.probed[self.plan.grade] or 0) then return self.plan.grade end
        return
    end
    -- 公告里有存活Boss的等级优先；没有公告仍允许探测，不能把未知当作不存在。
    for offset=1,4 do local i=(self.cursor+offset-1)%4+1
        if R.Available(i) and Locator.CanGrade(self.player,i) and now>=(self.probed[i] or 0) then self.cursor=i;return i end end
    for offset=1,4 do local i=(self.cursor+offset-1)%4+1
        if Locator.CanGrade(self.player,i) and now>=(self.probed[i] or 0) then self.cursor=i;return i end end
end
function Adventure:Tick()
    if not self.running then return "done" end
    local p=self.player;local now=GetTime();local entities=self:Scan()
    if not R.InWorld(entities) then
        if now-self.started<5 then return "running" end
        return "failed","当前不是已识别的冒险世界（zom约定分片7），未投币。其他部署请调整冒险配置。"
    end
    if self.phase=="fight" then
        local target=self.target
        local killed=R.Dead(target) or R.WasKilled(self.target_grade,self.target_name,self.fight_started)
        if killed then
            self.bridge:Stop();self.target=nil;self.phase="select";self.retries=0;self.probed={}
            self:Say("won:"..now,"这一个结束了，继续找下一个。")
        elseif target and not target:IsValid() then
            self.bridge:Stop();self.target=nil;self.phase="select"
            self.probed[self.target_grade]=now+5
            self:Say("lost","目标离开了加载范围，重新测向；暂不判定击杀。")
        elseif not self.bridge:Running() then return "failed","冒险战斗进程已停止，请重新接管。"
        end
        return "running"
    end
    -- 开洞/过洞期间禁止目标扫描抢走动作。转换前遇袭则取消工作，先交给战斗。
    if self.watch and self.watch.phase~="portal" and self.watch.phase~="jump" then
        for _,e in ipairs(entities) do
            local ec=e.replica and e.replica.combat
            if ec and ec.GetTarget and ec:GetTarget()==p and not R.Dead(e) and p:GetDistanceSqToInst(e)<14^2 then
                self.watch:Cancel();self.watch=nil;self.phase="select";break
            end
        end
    end
    if self.watch then
        local state,why=self.watch:Tick(function(point) self:Move(point) end)
        if state=="failed" then return "failed",why end
        if state=="done" then
            self.watch:Cancel();self.watch=nil;self.phase="relocate";self.phase_before="relocate";self.locator=Locator(p,self.grade)
            self.progress_point=nil;self.progress_at=now;self.next_scan=0
            self:Say("arrived","已穿过时空洞，重新投币确认 Boss 的实际方向。")
        end
        return "running"
    end
    local visible=self:Nearest(entities)
    if visible and not self.defending and p:GetDistanceSqToInst(visible)<=18^2 then return self:StartFight(visible) end
    -- 非战斗工作遇袭，让同一Combat实例防卫，结束后重新测量，不恢复过期箭头。
    local threatened=false
    for _,e in ipairs(entities) do local ec=e.replica and e.replica.combat
        if ec and ec.GetTarget and ec:GetTarget()==p and not R.Dead(e) and p:GetDistanceSqToInst(e)<14^2 then threatened=true;break end end
    if threatened or self.defending then
        if not self.defending then
            self.locator=nil;A.Stop(p);self.travel:Reset()
            local ok,why=self.bridge:Start({kind="fight",target="",coordinated=true,defensive=true},function() return false end)
            if not ok then return "failed",why end
            self.defending=true
        end
        if threatened then self.clear_since=nil else self.clear_since=self.clear_since or now end
        if self.clear_since and now-self.clear_since>1.5 then
            self.bridge:Stop();self.defending=nil;self.clear_since=nil;self.phase="select"
        elseif not self.bridge:Running() then
            return "failed","冒险途中防卫进程已停止，操作交回。"
        end
        return "running"
    end
    if self.blocked then return "failed","前往 Boss 的路不通或长时间没有前进，请检查表的板块对应及地形。" end
    if visible then self.destination=visible:GetPosition();self.grade=R.Grade(visible);self.phase="travel";self.locator=nil end
    if self.locator then
        local state,result=self.locator:Tick(function(point) self:Move(point) end)
        if state=="done" then
            self.destination=Vector3(result.x,0,result.z);self.locator=nil;self.phase="travel"
            self.progress_point=nil;self.progress_at=now
            self:Say("located:"..now,C.grades[self.grade].." Boss 预计在"..result.sector.."号板块，正在前往。")
            if p:HasTag("pocketwatchcaster") and self.phase_before~="relocate"
                and p:GetDistanceSqToPoint(self.destination:Get())>C.watch_distance^2 then
                self.watch=Watch(p,result.sector);self.phase="watch";A.Stop(p)
            end
            self.phase_before=nil
        elseif state=="empty" then
            A.Stop(p)
            self.probed[self.grade]=now+C.probe_interval;self.locator=nil;self.phase="select"
            self:Say("empty:"..self.grade,"暂时没测到"..C.grades[self.grade].." Boss，稍后再查。")
        elseif state=="failed" then
            A.Stop(p)
            self.retries=self.retries+1;self.locator=nil;self.phase="select";self.probed[self.grade]=now+5
            if self.retries>=3 then return "failed",result end
            self:Say("retry:"..self.retries,result)
        end
        return "running"
    end
    if self.phase=="travel" then
        if p:GetDistanceSqToPoint(self.destination:Get())<12^2 then
            self.retries=self.retries+1
            if self.retries>3 then return "failed","到达测向区域仍没有看到 Boss，暂停以避免原地反复。" end
            self.phase_before="relocate";self.locator=Locator(p,self.grade)
        else self:Move(self.destination) end
        return "running"
    end
    self.grade=self:Grade()
    if not self.grade then self:Say("waiting","等待下一次探测；请保留可用猪鼻铸币，主物品栏留一个空格拆币。")
    else
        self.locator=Locator(p,self.grade);self.phase="locate"
        self:Say("probe:"..self.grade,"先用猪鼻铸币找"..C.grades[self.grade].." Boss。")
    end
    return "running"
end
return Adventure
