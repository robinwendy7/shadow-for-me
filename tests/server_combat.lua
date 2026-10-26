-- 本次服务器反馈的离线回归；不宣称真实引擎和网络验证。
local savedA=package.loaded["shadowself/control/actions"]
local now=0;GetTime=function() return now end;FRAMES=1/30
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(q) return (self.x-q.x)^2+(self.z-q.z)^2 end;return p end
EQUIPSLOTS={HANDS="hands",BODY="body"};ACTIONS={PLAY={}}
TUNING={WHIP_RANGE=2,ELECTRIC_DAMAGE_MULT=1.5,ELECTRIC_WET_DAMAGE_MULT=1,PANFLUTE_SLEEPRANGE=15}
local guid=0
local function ent(name,x,z)
 guid=guid+1;local e={prefab=name,GUID=guid,pos=Vector3(x or 0,0,z or 0),tags={},anim="idle",frame=0,components={},replica={},valid=true}
 function e:IsValid() return self.valid end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 function e:GetIsWet() return self.tags.wet or false end
 e.Transform={GetRotation=function() return e.rotation or 0 end}
 e.AnimState={IsCurrentAnimation=function(_,n) return e.anim==n end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=ent("wilson",3,0);local held;local busy=false;local items={};local entities={};local plays,stops=0,0
p.replica.inventory={GetEquippedItem=function() return held end}
p.components.playercontroller={IsBusy=function() return busy end}
TheWorld={state={}};TheSim={FindEntities=function() return entities end}
local c={player=p,target=nil,enemies={},hazards={},observed={},snapshot={},h={selected_ents={}},owner={perception={Inventory=function() return items end}}}
c.actions={SafePoint=function() return true end,Stop=function() stops=stops+1 end}
c.bridge={player=p,h=c.h,allowed=function() return true end,PauseAttack=function() end,wrappers={PreTheLoop={old=function() end}}}
c.travel={BeginDodge=function(self) self.dodging=true end};c.Latency=function() return .2 end
c.Move=function(self,v,label) self.moved=v;self.status=label end
package.loaded["shadowself/control/actions"]={Items=function() return items end,Self=function(_,item,action) assert(action==ACTIONS.PLAY);plays=plays+1;busy=true;p.anim="flute";return true end}
require("shadowself/legacy/combat_equipment");local Registry=require("shadowself/legacy/registry")
local function weapon(name,damage)
 local e=ent(name);e.tags.weapon=true
 e.replica.equippable={EquipSlot=function() return "hands" end}
 e.replica.inventoryitem={GetWalkSpeedMult=function() return 1 end,AttackRange=function() return 0 end}
 if damage then e.components.weapon={damage=damage} end
 return e
end
local sword,whip,star=weapon("nightsword"),weapon("whip"),weapon("nightstick")
c.gear=Registry.CombatEquipment(c);local gear=c.gear
local hound=ent("hound");c.target=hound;c.enemies={hound};items={sword,star}
hound.tags.wet=true;assert(gear:Weapon()==star,"wet target without electric buff selects morningstar")
p._shadowself_combat_buffs={electric_until=100};assert(gear:Weapon()==sword,"active electric buff excludes redundant morningstar")
p._shadowself_combat_buffs=nil;hound.tags.wet=nil
items={weapon("spear"),star};assert(gear:Weapon().prefab=="spear","dry target never selects stronger morningstar over ordinary spear")
c.enemies={hound,ent("hound"),ent("hound"),ent("hound"),ent("hound")};items={sword,star}
assert(gear:Weapon()==sword,"five dry mobs never force morningstar")
items={sword,whip,star};assert(gear:Weapon()==whip,"ordinary mob crowd still uses whip")
c.plan={arena=true,arena_no_whip=function() return true end}
assert(gear:Weapon()==sword,"arena trap guards prohibit whip despite crowd range bonus")
gear.forced_weapon=whip;assert(gear:Weapon()==sword,"forced whip cannot bypass trap prohibition");gear.forced_weapon=nil
c.plan.arena_no_whip=function() return false end
assert(gear:Weapon()==whip,"whip available again when trap guards removed")
c.enemies={hound};c.plan.arena_whip=function() return true end
assert(gear:Weapon()==whip,'fish/frog wave temporarily selects whip even below the generic crowd threshold')
c.plan.arena_no_whip=function() return true end
assert(gear:Weapon()==sword,'distance guard overrides temporary whip preference inside trap boundary')
c.plan.arena_whip=nil
c.plan=nil
local bat=weapon('ruins_bat');items={sword,bat};c.plan={arena=true,arena_wave=function() return 8 end}
assert(gear:Weapon()==bat,'eighth-wave combat uses the owned ruins bat over higher raw damage alternatives')
c.plan=nil;items={sword,whip,star}
local boss=ent("antlion");boss.tags.epic=true;c.target=boss
assert(gear:Weapon()==sword,"boss target ignores crowd range preference")
c.target=hound;c.enemies={hound,ent("sandspike_tall"),ent("sandspike_med"),ent("sandspike_short"),ent("sandblock"),ent("crabking_icewall")}
assert(gear:Weapon()==sword,"sand spikes and breakable walls are not crowd creatures")
local huge=weapon("test_high_damage",200);items={huge,sword,star};boss.tags.wet=true;c.target=boss
assert(gear:Weapon()==huge,"wet boss still chooses highest calculated damage rather than fixed morningstar bonus")
local Policy=require("shadowself/control/targetpolicy")
local rook,knight,bishop=ent("rook",2,0),ent("knight",4,0),ent("bishop",6,0)
c.h.selected_ents={[rook]=true,[knight]=true,[bishop]=true}
assert(Policy.Other(c.bridge,rook)==knight,"rook deprioritized even when nearer")
c.h.selected_ents={[rook]=true};assert(not Policy.Other(c.bridge,rook),"last remaining rook becomes attackable")
local remnants={rook,knight,bishop}
c.bridge.plan={arena=true,arena_wave=function() return 3 end,arena_remaining=function() return remnants end}
c.h.selected_ents={[rook]=true,[knight]=true,[bishop]=true}
assert(not Policy.ClockworkRook(c.bridge),'living bishop prevents the rook endgame')
remnants={rook,knight};assert(Policy.Nearest(c.bridge)==rook and not Policy.Other(c.bridge,rook),'wave3 endgame chooses rook even with a nearer knight')
rook.tags.dead=true;assert(Policy.Nearest(c.bridge)==knight,'rook death releases the final knight')
rook.tags.dead=nil;c.bridge.plan.arena_wave=function() return 2 end
assert(Policy.Nearest(c.bridge)==knight,'other waves retain rook-last policy')
c.bridge.plan=nil
-- 真实Secondary.Wrap必须处理exclusive专用走位，检查其他发条近身圈及冲撞扫掠线。
local primary=ent("bishop",0,0);primary.anim="atk2_loop";p.pos=Vector3(4,0,0)
knight.pos=Vector3(2,0,4);knight.anim="idle"
local data={atkanim="atk2_loop",exclusive=true,fn=function() return Vector3(0,0,4) end}
entities={primary,knight};c.enemies=entities;c.bridge.wrappers.IsAttackPre={old=function(_,e) if e==primary then return data end end}
local secondary=require("shadowself/control/secondary")(c);c.secondary=secondary
local wrapped=secondary:Wrap(primary,data)
assert(wrapped~=data and wrapped.exclusive,"exclusive route is wrapped without stripping its own semantics")
local goal=wrapped:fn();local Nav=require("shadowself/control/navigation")
assert(Nav.Safe(secondary,goal,primary) and goal:DistSq(knight.pos)>=3.2^2,"bishop dodge must avoid idle adjacent knight's attack range")
rook.pos=Vector3(-5,0,4);rook.anim="atk";rook.rotation=0;entities={primary,rook};now=1;secondary.next_scan=nil
c.bridge.wrappers.IsAttackPre.old=function(_,e) return e==primary and data or {atkanim="atk"} end
secondary:Scan();assert(secondary:LaneBlocked(Vector3(0,0,4),primary),"rook's distant swept lane blocks intended landing")
goal=secondary:Point(Vector3(0,0,4),primary);assert(not secondary:LaneBlocked(goal,primary),"alternate landing avoids the charging rook lane")
-- 主教状态必须按实体保留，多只主教同时出招不能互相重置蓄力计时。
entities={};c.enemies={};local routes=require("shadowself/control/routes")({c=c,entities={}})
p.pos=Vector3(3,0,0);primary.anim="atk2_pre";primary.frame=0;bishop.anim="atk2_pre";bishop.frame=0
now=2;assert(routes:Bishop(primary,false));assert(routes:Bishop(bishop,false));now=2.3
local bd=routes:Bishop(primary,false);assert(bd and bd.fn,"server latency starts bishop sidestep before old0.4-second delay")
local bp=bd:fn();assert(math.abs(bp:DistSq(primary.pos)-9)<.001,"bishop retains close same-radius sidestep")
routes:Bishop(bishop,false);assert(routes.bishops[primary] and routes.bishops[bishop],"bishop plans survive off-target scans")
-- 大霜鲨扫击更贴近；地下钻出保持圆形伤害间距。
local Shark=require("shadowself/control/sharkroute");local shark=ent("sharkboi",0,0)
shark.anim="atk1";shark.frame=0;c.enemies={shark};p.pos=Vector3(3,0,0)
local sd=Shark.Dodge(c,shark,false);local sp=sd:fn()
assert(sp:DistSq(shark.pos)<=2.5^2+.001 and sp.z~=0,"swipe close orbit avoids old oversized radius")
for _,name in ipairs({"spawn","icedive_jump_pre","icedive_jump","icedive_dig_pre"}) do
 shark.anim=name;sd=Shark.Dodge(c,shark,false);sp=sd:fn()
 assert(sd.noattack and sp:DistSq(shark.pos)>3.5^2,"emerge/landing is a circular damage exit: "..name)
end
-- 蚁狮脱困后仍被刺堆挡住回身通道：保持移动，真正净空后才恢复攻击。
local ant=ent("antlion",0,0);p.pos=Vector3(6,0,0);c.enemies={ant};c.gear=gear
c.hazards={};c.mechanisms={zones={{pos=Vector3(4,0,0),radius=1.1}}}
local ar=require("shadowself/control/routes")({c=c});ar.ant_clearing=true;ar.ant_exit=Vector3(6,0,3)
ar.boss.Move=function(_,q) assert(q:DistSq(p.pos)>0);return 'move',ant end
local mode=ar:AntRecover(ant);assert(mode=='move' and not ar.ant_clearing and not ar.ant_exit,"blocked return corridor continues circular avoidance before resuming attacks")
c.mechanisms=nil;c.hazards={};assert(not ar:AntRecover(ant) and not ar.ant_clearing,"safe return corridor immediately restores normal combat")
-- 帝王蟹实际状态流程：飞蟹落地 -> 正常PLAY -> 确认入睡 -> 普攻破冰 -> 本体。
local king=ent("crabking",0,0);king.tags.epic=true;king.tags.icewall=true;king.tags.notarget=true
local mob=ent("crabking_mob",5,0);mob.anim="boat_jump_loop"
local wall=ent("crabking_icewall",2,0);local flute=ent("panflute")
entities={king,mob,wall};items={flute,sword};c.enemies={king,mob};p.pos=Vector3(3,0,0);busy=false;c.gear=gear;c.h.ent=king
package.loaded["shadowself/control/crabking"]=nil
local Crab=require("shadowself/control/crabking");local crab=Crab(c);c.crabking=crab;now=10
mode=crab:Tick(king);assert(mode=="support" and plays==0 and not crab:Allowed(mob),"wait rather than hit minion or waste flute in flight")
now=11.2;mode=crab:Tick(king);assert(mode=="support" and plays==0)
mob.anim="idle";now=11.5;mode=crab:Tick(king)
assert(mode=="support" and plays==1 and gear.action_hold and crab.pending,"landed awake crab submits one PLAY and locks concurrent swaps")
now=12;crab:Tick(king);assert(plays==1,"no duplicate flute while pending")
mob.anim="sleep_loop";busy=false;p.anim="idle";now=12.6
mode=crab:Tick(king);assert(mode=="attack" and c.h.ent==wall and crab:Allowed(wall) and not crab:Allowed(mob) and not gear.action_hold,"only confirmed sleep unlocks ice-wall attacks")
king.tags.notarget=nil;now=12.7;mode=crab:Tick(king)
assert(mode=='attack' and c.h.ent==king and king.tags.icewall and wall.valid and not crab:Allowed(wall),'first actual targetability update returns to king even while ice tag and walls remain')
mob.anim='idle';now=12.8;mode=crab:Tick(king)
assert(mode=='attack' and c.h.ent==king and plays==1,'king output window cannot regress to re-fluting awakened minions')
wall.valid=false;king.tags.icewall=nil;king.tags.notarget=nil;now=13;mode=crab:Tick(king)
assert(mode=="attack" and c.h.ent==king and not crab:Allowed(wall),"ice stage ends back on king only")
king.tags.icewall=true;king.tags.notarget=true;wall.valid=true;mob.anim="idle";now=15;crab:Tick(king);now=16.2;crab:Tick(king)
assert(plays==2,"new ice phase requires a fresh sleep cycle")
busy=false;now=19.3;crab:Tick(king);now=20;crab:Tick(king);assert(plays==3,"sleep resistance/failed effect retries PLAY instead of assuming success")
-- 走位中断吹奏后立即释放装备锁，不会阻止拿手杖；之前的赶路换装要能确认。
crab:Interrupt();assert(not crab.pending and not gear.action_hold)
busy=false;p.anim="idle";now=21;gear.pending={item=sword,untiltime=now+1};held=sword
crab:Tick(king);assert(not gear.pending and crab.pending and plays==4,"acknowledged travel equip cannot deadlock crab PLAY")
local Co=require("shadowself/control/coordinator");c.next_move=now+1;c.crabking=crab
Co.Move(c,Vector3(5,0,0),"escape incoming")
assert(not crab.pending and not gear.action_hold,"actual movement entry cancels crab PLAY lock immediately")
-- 主目标地下不可被索敌时，Mechanisms.Scan也能识别钻出圈。
local mechanisms=require("shadowself/control/mechanisms")(c);c.bosses=nil;shark.anim="icedive_jump_pre";shark.frame=20;entities={shark};p.pos=Vector3(1,0,0)
mechanisms:Scan();assert(#mechanisms.zones==1 and mechanisms.zones[1].source==shark,"untargetable late emerge remains an active ground hazard")
-- 对照本机原版源码：地标半径/伤害持续、扫击弧度和地下起跳伤害、破冰动作与空中不可睡。
local bs=read_source("stategraphs/SGbishop.lua");local fx=read_source("prefabs/bishop_charge.lua")
assert(bs:find('SetTimeout(1)',1,true) and fx:find('local RADIUS = 2.5 - 0.5',1,true) and fx:find('18 * FRAMES',1,true))
local ss=read_source("stategraphs/SGsharkboi.lua")
assert(ss:find('local SWIPE_ARC = 240',1,true) and ss:find('DoAOEAttackAndDig(inst, 0, 2',1,true))
local ks=read_source("prefabs/crabking_icewall.lua")
assert(ks:find('AddComponent("combat")',1,true) and not ks:find('AddComponent("workable")',1,true),"ice wall is attacked, not mined")
assert(read_source("stategraphs/SGcrabking_mob.lua"):find('"nosleep"',1,true))
package.loaded["shadowself/control/actions"]=savedA
print("PASS: wet/electric and boss/crowd weapon policy; sandspike exclusion; rook last with retained swept danger; exclusive-route group guards; per-bishop timing; close shark vs emerge; antlion safe reentry; crab landing/sleep confirmation/retry/icewall/body lifecycle; source checks")
