-- 本轮机制及实际内置DoDodge末尾路径验证，网络/物理仍为离线模拟。
local now=0;GetTime=function() return now end;FRAMES=1/30
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
local guid=0
local function ent(n,x,z)
 guid=guid+1;local e={prefab=n,GUID=guid,pos=Vector3(x or 0,0,z or 0),tags={},valid=true,anim="idle",frame=0,rotation=0,replica={},components={}}
 function e:IsValid() return self.valid end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius or .5 end
 e.Transform={GetRotation=function() return e.rotation end}
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent("wilson",3,0);p.components.playercontroller={IsAnyOfControlsPressed=function() return true end}
p.replica.combat={CanTarget=function() return true end};p.replica.inventory={}
TheWorld={state={}};local entities={};TheSim={FindEntities=function() return entities end}
local c={player=p,enemies={},observed={},hazards={},snapshot={},bridge={},travel={},gear={}}
c.actions={SafePoint=function() return true end,Stop=function() end};c.Latency=function() return .2 end
c.Move=function(self,point) self.moved=point end
local Routes=require("shadowself/control/routes");local boss={c=c};local routes=Routes(boss);boss.routes=routes
-- 疯猪自定义路线退休，原表由native_embedded核对；其它机制继续回归。
local data,point
-- 龙蝇近身普通/暴怒攻击均强制躲避，骨甲状态不参与判断。
local fly=ent("dragonfly");fly.anim="atk";fly.frame=0
p.replica.inventory.GetEquippedItem=function() return {prefab="armorskeleton",components={cooldown={IsCharged=function() return true end}}} end
for _,f in ipairs({0,7,15,18}) do fly.frame=f;data=routes:Dodge(fly,false);assert(data and data.noattack and data.dist>=5.5) end
fly.frame=19;assert(not routes:Dodge(fly,false))
-- 只使用原版明确的撞击屏障标记，不把普通物品或空中落石当柱子。
local Guardian=require("shadowself/control/guardian");local king=ent("minotaur");local pillar=ent("pillar_ruins",6,0);pillar.radius=1;pillar.tags.charge_barrier=true
entities={pillar};local stopped,released=0,0
c.actions.SafePoint=function(_,v) return v:DistSq(pillar.pos)>1.6^2 end
c.actions.Stop=function() stopped=stopped+1 end
boss.Move=function(_,v,label) c.moved=v;c.status=label;return "move",king end
boss.Release=function() released=released+1 end
local mode=Guardian.Tick(boss,king)
assert(mode=="move" and c.moved.z~=0,"approach rear of pillar along its contour, never walk directly through it")
p.pos=Vector3(8.5,0,0);mode=Guardian.Tick(boss,king);assert(mode=="support" and stopped==1,"behind pillar waits for collision instead of attacking unstunned guardian")
king.anim="atk";mode=Guardian.Tick(boss,king);assert(mode=="support" and stopped==1,"aligned running guardian keeps pillar between player and boss")
king.anim="stun_pre";mode=Guardian.Tick(boss,king);assert(mode=="attack" and not boss.guardian.active and released==1,"actual stun opens damage window immediately")
king.anim="idle";pillar.valid=false;now=1
local falling=ent("ruins_cavein_obstacle",6,0);falling.tags.charge_barrier=true;falling.pos.y=4;entities={falling}
assert(not Guardian.Tick(boss,king),"airborne rock is not a usable barrier yet")
falling.pos.y=0;now=2;Guardian.Tick(boss,king);assert(boss.guardian.pillar==falling,"landed cavein barrier can be used")
king.anim="jump_atk_pre";assert(not Guardian.Tick(boss,king),"existing leap dodge takes priority over pillar lure")
-- 原版柱边4码内不发起冲锋，不能躲在柱后永远傻等。
king.anim="idle";king.pos=Vector3(2,0,0);falling.pos=Vector3(6,0,0);now=3
boss.guardian=nil;mode=Guardian.Tick(boss,king)
assert(mode=="move" and boss.guardian.reset and c.status:find("拉离柱脚",1,true),"close pillar first creates charge distance")
king.pos=Vector3(-2,0,0);now=4;Guardian.Tick(boss,king);assert(not boss.guardian.reset,"once enough runway exists, return to pillar bait")
-- 冰锋生成器不联网：即使没有扫描到隧道，也能从动画锁定朝向预测整条生长区。
c.actions.SafePoint=function() return true end;c.enemies={};c.hazards={};p.pos=Vector3(3,0,0)
local shark=ent("sharkboi");shark.anim="ice_summon";shark.frame=0
local Shark=require("shadowself/control/sharkroute");now=5;data=Shark.Dodge(c,shark,false);point=data:fn();assert(point.z~=0,"ice summon turns sideways/back, not running forward along ice rails")
shark.frame=35;now=6;local zones=Shark.IceZones(c,shark)
assert(#zones>=6 and zones[#zones].pos.x>=29,"predict remote ice corridor before waiting for any non-networked FX")
shark.rotation=90;shark.frame=36;local locked=Shark.IceZones(c,shark)
assert(locked[1].pos.x==zones[1].pos.x and locked[1].pos.z==zones[1].pos.z,"after frame35 ice growth remains on locked original heading")
shark.frame=57;assert(Shark.Dodge(c,shark,false),"ice growth cannot release dodge at old frame42")
shark.anim="idle";now=8;assert(#Shark.IceZones(c,shark)==0,"predicted growth expires instead of causing endless running")
-- 实际内置DoDodge完成后，补刀重新选最近目标；战车仍排最后。
local far,near,rook=ent("hound",9,0),ent("hound",2,0),ent("rook",1,0);p.pos=Vector3(0,0,0)
local h={ent=far,pos=far.pos,ppos=p.pos};c.h=h;c.bridge.h=h;c.bridge.player=p;c.bridge.priority_target=nil
c.bridge.allowed=function(e) return e and e:IsValid() end
c.bridge.wrappers={PreTheLoop={old=function() end},IsAttackPre={old=function() return false end}}
h.GetAttackTargets=function(self) self.selected_ents={[far]=true,[near]=true,[rook]=true} end
h.CancelDodgingAtk=function() end;h.ShouldAtkWhenDodging=function() return false end;h.IsAttackPre=function() return false end
local attacked;h.CloseAndAttack=function(_,e) attacked=e end
local sec=require("shadowself/control/secondary")(c);c.secondary=sec
h.shadowself_after_dodge=function(captured) return sec:AfterDodge(captured) end
p.PushEvent=function(_,_,event) p.last_event=event end
local nativefile=read_3014_dodge();local cut=assert(nativefile:find("\n\tlocal initidlelist",1,true))
local env=setmetatable({GLOBAL={DEGREES=math.pi/180},HitAndRun=h,ThePlayer=p,
 FunctionOrValue=function(v,...) return type(v)=="function" and v(...) or v end,
 POS_util={GoToPoint=function() end},distsq=function(a,b) return a:DistSq(b) end,Sleep=function() end},{__index=_G})
local chunk=assert(loadstring(nativefile:sub(1,cut-1).."\nend"));setfenv(chunk,env);chunk()
h:DoDodge({dist=4,point="player",fn=function() return Vector3(4,0,0) end})
assert(attacked==near and h.ent==near and p.last_event.target==near,"actual post-dodge attack and equipment event target nearest non-rook, never captured old victim")
-- 原版聊天和影子聊天均不暂停已接管战斗；菜单仍保持输入阻断。
local oldPlayer,oldFE=ThePlayer,TheFrontEnd;ThePlayer=p
p.HUD={HasInputFocus=function() return true end};local screen=p.HUD
TheFrontEnd={GetActiveScreen=function() return screen end}
p._shadowself={panel={input={editing=true}},takeover={combat={Running=function() return true end}}}
local Input=require("shadowself/control/combatinput")
local Game=assert(loadfile("scripts/shadowself/native/utils/GAME_util.lua"))()
local Keys=assert(loadfile("scripts/shadowself/native/utils/KEY_util.lua"))()
assert(Input.AllowTyping(p) and Game:InGame() and not Keys:MoveKeyDown(),"typing WASD in shadow chat does not pause native combat")
local oldPaused=IsSimPaused;IsSimPaused=function() return false end
local bridge=require("shadowself/control/combat")(p);bridge.native={GAME_util=Game,KEY_util=Keys}
assert(not bridge:ManualAction(),"actual supervisor manual-input gate must continue combat while typing")
IsSimPaused=oldPaused
p._shadowself.panel.input.editing=false;screen={name="ChatInputScreen"}
assert(Game:InGame() and not Keys:MoveKeyDown(),"original server chat keeps owned combat active too")
screen={name="PauseScreen"};assert(not Game:InGame(),"unrelated menu is still blocked")
screen=p.HUD;p._shadowself.panel.input.editing=true;p._shadowself.takeover.combat.Running=function() return false end
assert(not Input.AllowTyping(p) and not Game:InGame(),"typing allowance only applies during owned takeover")
ThePlayer,TheFrontEnd=oldPlayer,oldFE
local mino=read_source("prefabs/minotaur.lua");local pigsrc=read_source("stategraphs/SGdaywalker.lua")
assert(mino:find('other:HasTag("charge_barrier")',1,true) and mino:find('collision_stun',1,true))
assert(pigsrc:find('FrameEvent(26',1,true) and pigsrc:find('DAYWALKER_SLAM_SINKHOLERADIUS',1,true))
assert(read_source("prefabs/sharkboi_icespike.lua"):find('--[[Non-networked entity]]',1,true))
print("PASS: retired custom pig route, dragon dodge regardless bone armor, actual barrier/landed-rock guardian lure and stun gate, predicted non-networked ice corridor, native DoDodge nearest follow-up, owned chat focus/WASD and menu isolation")
