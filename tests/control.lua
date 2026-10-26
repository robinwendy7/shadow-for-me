local R=require("shadowself/control/request")
for _,text in ipairs({"停","停下","等等","停一下，我自己来","取消接管","帮我停止自动战斗","别动","还给我"}) do assert(R.IsStop(text),text) end
for _,text in ipairs({"别停","不停","我怕停电","你喜欢什么"}) do assert(not R.IsStop(text),text) end
for _,case in ipairs({{"帮我砍树","chop"},{"帮我挖矿","mine"},{"帮我挖石头","mine"},
    {"帮我捡木头","pickup"},{"帮我采摘浆果","pick"},{"帮我挖掉树桩","dig"},
    {"帮我拆掉箱子","hammer"},{"帮我制作木板","craft"},{"帮我装备长矛","equip"},
    {"帮我吃肉丸","eat"},{"帮我去10,20","goto"},{"帮我打蜘蛛","fight"},
    {"帮我自动走位","dodge"},{"帮我自动战斗","fight"},{"你能帮我砍树吗","chop"}}) do
    local p=R.Parse(case[1]);assert(p and p.kind==case[2],case[1])
end
assert(not R.Parse("不要帮我砍树"),"negative request does not ask takeover")
assert(not R.Parse("不用帮我打蜘蛛"),"negative combat request")
assert(R.Parse("帮我制作2个木板").kind=="queue","quantity uses imported zom queue")
local one=R.Parse("帮我拆掉箱子");local all=R.Parse("帮我拆掉所有箱子")
assert(not one.all and all.all,"destructive job scope stays one unless all explicit")
-- 确认、过期、演出、停止的状态机；实际动作在单独测试中验证。
local now=100
GetTime=function() return now end
local calls={stops=0,starts=0,work=0,fx=0}
local Actions={Stop=function() calls.stops=calls.stops+1 end}
package.loaded["shadowself/control/actions"]=Actions
package.loaded["shadowself/control/jobs"]=Class(function(self)
    function self:Set(plan) self.plan=plan end
    function self:Cancel() self.plan=nil end
    function self:Tick() calls.work=calls.work+1;return "running" end
    function self:Matches() return true end
    function self:OwnsCombat() return false end
end)
package.loaded["shadowself/control/combat"]=Class(function(self)
    function self:Available() return true end
    function self:Start() calls.starts=calls.starts+1;return true end
    function self:Stop() end
    function self:Running() return true end
end)
package.loaded["shadowself/takeover"]=nil
TUNING={}
local player={dead=false}
function player:IsValid() return true end
function player:HasTag(tag) return tag=="playerghost" and self.dead end
player.AnimState={UsePointFiltering=function() end,OverrideMultColour=function(_,r,g,b,a) player.alpha=a end,IsCurrentAnimation=function() return false end}
player.Transform={GetWorldPosition=function() return 0,0,0 end}
local actor={inst={Transform={GetWorldPosition=function() return 3,0,0 end,SetPosition=function() end},
    AnimState={PlayAnimation=function() end,PushAnimation=function() end},Hide=function() end,Show=function() end}}
function actor:SetRate() end;function actor:SetState() end
local runtime={owner=player,actor=actor,loaded=true,effects={Burst=function() calls.fx=calls.fx+1 end},dialogue={Say=function() end}}
local Control=require("shadowself/takeover")
local c=Control(runtime)
assert(c:HandleText("帮我砍树") and c.pending and not c.phase)
c:Tick();c:Frame(.016)
assert(calls.stops==0 and calls.work==0 and calls.starts==0 and calls.fx==0,"no action before confirmation")
assert(not c:HandleText("我没有同意") and c.pending and not c.phase,"ordinary text is not confirmation")
assert(c:HandleText("同意接管") and c.phase=="diving" and calls.work==0)
c:Tick();assert(calls.work==0 and not c.jobs.plan,"confirmed task waits for visual covering")
now=100.7;c:Frame(.016);assert(c.phase=="hidden" and calls.fx==1)
now=101.1;c:Frame(.016);assert(c.phase=="active" and actor.possessed and player.alpha==.5 and calls.fx==2)
c:Tick();assert(calls.work==1 and c.jobs.plan,"visual completion starts task once")
c:HandleText("停");assert(not c.phase and not actor.possessed and player.alpha==1)
local n=calls.work;c:Tick();c:Frame(.016);assert(calls.work==n,"stopped control never resumes")
local before=calls.stops
c:HandleText("帮我捡木头");now=now+31;c:HandleText("同意")
assert(c.phase=="diving" and not c.pending,"consent remains available until accepted or cancelled");c:Stop(nil,true)
c:HandleText("帮我砍树");c:HandleText("同意");c:HandleText("取消接管")
now=now+2;c:Frame(.016);assert(not c.phase and calls.work==n,"cancel during animation never starts task")
c:HandleText("帮我砍树");c:HandleText("同意");now=now+1;c:Frame(.016);c:Frame(.016)
assert(c.phase=="active");player.dead=true;c:Tick()
assert(not c.phase and player.alpha==1,"death releases possession")
player.dead=false;c.combat.Available=function() return false end
c:HandleText("帮我自动战斗");assert(not c.pending and not c.phase,"missing backend does not fake combat")
-- 指定战斗台词覆盖五句；清敌后继续等待，直到玩家主动停止。
local said={};c.Say=function(_,text) said[text]=true end
runtime.memory={last_user_speech=now};runtime.queue={"hurt"}
c:BeginBattle();for i=1,4 do c:BattleLine() end
local count=0;for _ in pairs(said) do count=count+1 end
assert(count==5 and #runtime.queue==0,"five requested battle lines rotate without repeats and stale hurt queue is cleared")
c.phase="active";c.task={kind="fight"};c.job_started=true;actor.possessed=true;player.alpha=.5
local owned={};c.combat.thread=owned;TUNING.Cheatthread=owned
c.combat.Finished=function() error("persistent combat must not use enemy-clear completion") end
for _,delay in ipairs({0,2,30}) do
    now=now+delay;c:Tick()
    assert(c.phase=="active" and c.battle_active and actor.possessed and player.alpha==.5
        and TUNING.Cheatthread==owned,"enemy-free intervals retain possession and the native combat thread")
end
c:HandleText("停止接管")
assert(not c.phase and not c.battle_active and not actor.possessed and player.alpha==1,"explicit stop still releases possession and music")
TUNING.Cheatthread=nil
-- Consent request is exactly one fixed line, regardless of personality.
c.combat.Available=function() return true end;said={};local speech={}
c.Say=function(_,text) speech[#speech+1]=text end
runtime.queue={{kind="hurt"},{kind="rain"}}
assert(c:OfferCombat() and #speech==1 and speech[1]=="亲爱的我，你又受伤了，需要我帮忙的话点护甲槽上方的接管按钮。")
assert(#runtime.queue==1 and runtime.queue[1].kind=="rain","consent clears stale hurt reminders only")
assert(not c:OfferCombat() and #speech==1,"pending request cannot emit another line")
local Runtime=require("shadowself/runtime")
local r={control={pending={plan={defensive=true}}},events={},memory={},dialogue={thought=nil},queue={}}
r.dialogue.Say=function() error("hurt dialogue cannot interrupt consent") end
Runtime.Emit(r,"hurt");assert(#r.queue==0,"pending defensive consent suppresses normal hurt pool too")

c:Stop(nil,true)
-- HUD combat click is consent, but execution still waits for shadow covering.
c:CombatButton();assert(c.phase=="diving" and c.task.kind=="fight" and not c.job_started)
c:CombatButton();assert(not c.phase,"HUD button also cancels the covering transition")
local savedAdapter=package.loaded["shadowself/control/arena_adapter"]
local arenaSnapshot={arena=true,instance="arena-test",kind="PARTICIPANT"}
package.loaded["shadowself/control/arena_adapter"]=function() return {Snapshot=function() return arenaSnapshot end} end
c:CombatButton();assert(c.phase=="diving" and c.task.kind=="arena","inventory click inside arena starts the full arena job, not bare fight")
now=now+1;c:Frame(.016);c:Frame(.016)
assert(c.phase=="active" and c.jobs.plan.kind=="arena","merged click finishes possession and dispatches the arena job")
c:CombatButton();assert(not c.phase)
assert(c:OfferCombat() and c.pending.plan.kind=="arena","hurt consent and inventory button choose the same arena job")
c:CombatButton();assert(c.phase=="diving" and c.task.kind=="arena")
c:CombatButton()
arenaSnapshot.kind="SPECTATOR"
assert(c:CombatPlan().kind=="fight","spectator HUD cannot start arena automation")
arenaSnapshot=nil
assert(c:CombatPlan().kind=="fight","outside arena retains ordinary combat")
package.loaded["shadowself/control/arena_adapter"]=savedAdapter
-- The merged button must accept the pending arena plan instead of overwriting it with fight.
c:AskPlan({kind="arena",label="单人角斗场循环"},"自动角斗场循环")
local arena_plan=c.pending.plan
c:CombatButton();assert(c.phase=="diving" and c.task==arena_plan and not c.pending,"HUD confirms the requested arena task")
c:CombatButton();assert(not c.phase)
c.pending={plan=arena_plan,until_time=now-1}
c:CombatButton();assert(not c.phase and not c.pending,"expired request cannot become a new fight")
-- 实际桥接模块：确认使用原生走A入口、过滤目标、恢复运行时设置并保留他人线程。
package.loaded["shadowself/control/combat"]=nil
local Bridge=require("shadowself/control/combat")
local function ent(tags)
    return {IsValid=function() return true end,HasTag=function(_,tag) return tags[tag] or false end}
end
local enemy,neutral,other=ent({monster=true}),ent({}),ent({player=true})
local old_get=function(self) self.selected_ents={[enemy]=true,[neutral]=true,[other]=true} end
local started,stopped=0,0
HitAndRun={GetAttackTargets=old_get,IsAttackPre=function() end,DoDodge=function() end,
    StartHitAndRun=function() started=started+1;TUNING.Cheatthread={id=42,SetList=function() end} end,
    StopHitAndRun=function() stopped=stopped+1;TUNING.Cheatthread=nil end}
MOD_util={};POS_util={};ENT_util={};m_options={hitandrun_walkway=4,hitandrun_targetmode=true}
local client={replica={combat={IsAlly=function() return false end}}}
enemy.replica={combat={GetTarget=function() return client end}}
local b=Bridge(client)
assert(b:Start({kind="fight",target=""},function() return true end))
assert(started==1 and HitAndRun.dodgetest==true and m_options.hitandrun_walkway==true)
HitAndRun:GetAttackTargets(20)
assert(HitAndRun.selected_ents[enemy] and not HitAndRun.selected_ents[neutral] and not HitAndRun.selected_ents[other],"default combat filters neutral and players")
neutral.replica={combat={GetTarget=function() end}}
neutral.HasTag=function(_,tag) return tag=="sleeping" end
HitAndRun:GetAttackTargets(20)
assert(HitAndRun.selected_ents[neutral],"sleeping non-allied creatures are attacked without requiring aggro")
-- Sleeping elemental dogs remain excluded even when deliberately prioritised.
neutral.prefab="icehound";b.priority_target=neutral
assert(not b.allowed(neutral),"sleeping ice hound cannot be explicitly targeted")
neutral.prefab="firehound";neutral.HasTag=function() return false end
neutral.AnimState={IsCurrentAnimation=function(_,name) return name=="sleep_loop" end}
assert(not b.allowed(neutral),"sleep animation excludes fire hound before sleep tag arrives")
neutral.AnimState.IsCurrentAnimation=function() return false end
assert(b.allowed(neutral),"awake dog becomes eligible again")
b:Stop()
assert(stopped==1 and HitAndRun.GetAttackTargets==old_get and HitAndRun.dodgetest==nil)
assert(m_options.hitandrun_walkway==4 and m_options.hitandrun_targetmode==true and m_options.hitandrun_dodgetest==nil,"native settings restored including nil")
local external={};TUNING.Cheatthread=external
local foreign=Bridge(client);assert(not foreign:Start({kind="fight",target=""},function() return true end))
foreign:Stop();assert(TUNING.Cheatthread==external,"never kills a thread owned by someone else")
TUNING.Cheatthread=nil
-- 纯走位确实调用3014的DoDodge，并临时关闭其末尾补刀入口。
local old_close=function() return "attack" end
local old_should=function() return true end
HitAndRun.CloseAndAttack=old_close;HitAndRun.ShouldAtkWhenDodging=old_should
HitAndRun.PreTheLoop=function() end;HitAndRun.GetClosestTarget=function() return enemy end
HitAndRun.IsAttackPre=function() return {} end
local dodges=0;HitAndRun.DoDodge=function() dodges=dodges+1 end
local routine=nil
StartThread=function(fn) routine=coroutine.create(fn);return {id=99,SetList=function() end} end
Sleep=function() coroutine.yield() end;FRAMES=1/30
local killed=nil;KillThreadsWithID=function(id) killed=id end
local d=Bridge({components={playercontroller={}},replica={combat={IsAlly=function() return false end},inventory={}}})
enemy.replica.combat.GetTarget=function() return d.player end
assert(d:Start({kind="dodge",target=""},function() return true end))
assert(HitAndRun.CloseAndAttack()==false and HitAndRun.ShouldAtkWhenDodging()==false)
assert(coroutine.resume(routine));assert(dodges==1,"pure dodge uses original DoDodge")
d:Stop();assert(killed==99 and HitAndRun.CloseAndAttack==old_close and HitAndRun.ShouldAtkWhenDodging==old_should,"dodge thread and attack hooks restored")
local restored=false
local fallback=Bridge({IsValid=function() return true end,EnableMovementPrediction=function(_,value) restored=value end})
HitAndRun.StopHitAndRun=function() end;HitAndRun.movementflag=true
assert(fallback:Start({kind="fight",target=""},function() return true end))
fallback:Stop();assert(TUNING.Cheatthread==nil and restored,"exit fallback releases owned thread and prediction")
print("PASS: takeover consent, expiry, cancel, possession, stop/death; native combat bridge ownership/filter/settings")
