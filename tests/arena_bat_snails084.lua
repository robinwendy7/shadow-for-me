local saved={time=GetTime,world=TheWorld,sim=TheSim}
local keys={'actions','navigation','arena_bats','arena_snails'};local modules={}
for _,n in ipairs(keys) do local k='shadowself/control/'..n;modules[k]=package.loaded[k];package.loaded[k]=nil end
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local function ent(n,x,z)
 local e={prefab=n,GUID=math.random(1000),pos=Vector3(x or 0,0,z or 0),tags={},replica={},anim='idle',frame=0}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local p=ent('wilson',1);local torch=ent('torch');local helmet=ent('footballhat')
helmet.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HEAD end}
local king=ent('bat_boss');king.held=true;king.tags.INLIMBO=true
king.replica.inventoryitem={IsHeld=function() return king.held end}
local head=king;local busy=false;local drops,equips,attacks,moves,stops=0,0,0,0,0;local moveGoal;local bag={helmet}
p.components={playercontroller={IsBusy=function() return busy end}}
p.replica={inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HEAD and head or slot==EQUIPSLOTS.HANDS and torch end,
 DropItemFromInvTile=function(_,e,single) assert(e==king and single==false);drops=drops+1 end},combat={GetAttackRangeWithWeapon=function() return 2 end}}
package.loaded['shadowself/control/actions']={Items=function() return bag end,Self=function(_,e,a) assert(e==helmet and a==ACTIONS.EQUIP);equips=equips+1;return true end,
 Stop=function() stops=stops+1 end,Attack=function(_,e,g) assert(g());attacks=attacks+1;return true end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end,Select=function(_,q) return q end}
local B=require('shadowself/control/arena_bats');local Snails=require('shadowself/control/arena_snails')
local c={player=p,enemies={},plan={arena=true,arena_wave=function() return 6 end,arena_entities=function() return {king} end},
 bridge={PauseAttack=function() end,allowed=function(e) return e:IsValid() end},h={guid=5,shadowself_dodging=true},gear={pending={},protected_slots={}},
 travel={EndDodge=function() end},mechanisms={Equip=function() return true end}}
assert(B.Detach(c) and drops==1 and not c.gear.pending and not c.h.shadowself_dodging)
local Arena=assert(loadfile('scripts/shadowself/control/arena.lua'))();local arena={player=p,wave=6,bridge={coordinator=c}}
assert(Arena.BatAttached(arena),'an attached last boss keeps the existing supervisor alive even with no ground enemies')
now=.1;assert(B.Detach(c) and drops==1,'drop request cannot masquerade as confirmation')
head=nil;assert(Arena.BatAttached(arena));now=.4;assert(B.Detach(c) and drops==2 and equips==0,'head empty but entity held is not ground confirmation')
king.held=false;king.tags.INLIMBO=nil;now=.5;assert(B.Detach(c) and equips==1,'restore actual helmet before resuming combat')
head=helmet;now=.6;assert(not B.Detach(c) and c.bridge.priority_target==king)
assert(not Arena.BatAttached(arena),'ground/head confirmation releases the special lifecycle hold')
local boss={c=c,Release=function() end,Select=function(_,e) c.bridge.priority_target=e;return e end}
assert(B.Tick(boss,ent('bat'))=='attack' and c.bridge.priority_target==king,'kill summoning boss with normal weapons before bat cleanup')
king.anim='hair_attack';king.frame=1
local d=B.Dodge(c,king,nil);assert(d and d.noattack and d:fn():DistSq(king.pos)>=4.8^2-.01)
king.anim='hair_attack_fail';king.frame=4;assert(B.Dodge(c,king,nil),'failure slide still permits attaching before frame5')
king.frame=6;assert(not B.Dodge(c,king,{}),'after attachment ends resume output')
king.anim='atk';king.frame=9;assert(B.Dodge(c,king,nil));king.frame=12;assert(not B.Dodge(c,king,{}))
c.plan.arena_wave=function() return 2 end;assert(not B.Active(c),'other bat groups keep their original strategy')
-- 火把动作在目标稍微移动时完整执行，真实新攻击仍可立即中断。
local snail=ent('snurtle');c.plan.arena_wave=function() return 6 end;c.enemies={snail};c.gear={AttackRange=function() return 2 end}
c.Move=function(_,q) moves=moves+1;moveGoal=q end
boss.Item=function() return torch end;boss.Move=function(_,q) moves=moves+1;moveGoal=q;return 'move' end
boss.Away=function(_,e,r) moves=moves+1;moveGoal=Vector3(e.pos.x+r,0,e.pos.z);return 'move' end
p.pos=Vector3(1,0,0);now=10;head=helmet
assert(Snails.Tick(boss,snail)=='support' and attacks==1)
local beforeMove,beforeStop=moves,stops;snail.pos=Vector3(-.35,0,0);now=10.3
assert(Snails.Tick(boss,snail)=='support' and moves==beforeMove and stops==beforeStop and attacks==1,'slight drift cannot replace an in-progress strike with follow or STOP')
now=11.3;assert(Snails.Tick(boss,snail)=='move' and moves==beforeMove+1,'unconfirmed expired strike can reapproach')
p.pos=moveGoal;now=11.5;assert(Snails.Tick(boss,snail)=='support' and attacks==2)
snail.prefab='slurtle';snail.anim='atk';snail.frame=1;busy=true;now=11.6
assert(Snails.Tick(boss,snail)=='move' and not boss.snail_strike and attacks==2,'actual bite windup interrupts even the torch commitment and busy state')
p.pos=moveGoal;busy=false;snail.frame=8;assert(Snails.Tick(boss,snail)=='support' and attacks==2,'outside hit range wait for actual impact before reapproach')
snail.frame=12;now=12;assert(Snails.Tick(boss,snail)=='move')
p.pos=moveGoal;now=12.2;assert(Snails.Tick(boss,snail)=='support' and attacks==3,'completed bite dodge permits immediate torch counterattack')
local side=ent('slurtle',p.pos.x,2);side.anim='atk';side.frame=2;c.enemies={snail,side};snail.prefab='snurtle';snail.anim='idle';now=12.3
assert(Snails.Tick(boss,snail)=='move' and not boss.snail_strike and attacks==3,'side slurtle attack also interrupts torch instead of tunnelling on current target')
c.enemies={snail}
for _,name in ipairs({'slurtle','snurtle'}) do
 snail.prefab=name;snail.tags.fire=true;snail._shadowself_snail_fire={requested=now}
 local zone=require('shadowself/control/arena_fire').Zone(snail,p)
 assert(zone and zone.fire and not zone.explosive_snail,'both species create immediate burning danger')
 assert(Snails.Remaining(snail)>2);now=now+6
 assert(require('shadowself/control/arena_fire').Zone(snail,p).explosive_snail,'later explosion remains a danger')
 snail.tags.fire=nil
end
-- 当前服务器第六关新增配置与准确prefab，不扩散到其余新暗影关卡。
local actual=assert(loadstring(read_astra_source('astra/modes/arena/encounters.lua')))().WAVES_1_2[6].default[5]
local data=require('shadowself/data/arena_classic').encounters[6].default[5]
local function equal(a,b) if type(a)~='table' then assert(a==b);return end;for k,v in pairs(a) do equal(v,b[k]) end;for k in pairs(b) do assert(a[k]~=nil) end end
equal(actual,data);assert(require('shadowself/control/arena_policy').monsters.bat_boss)
local src=read_source('prefabs/bat_boss.lua');assert(src:find('DoPeriodicTask(0.6, DoChomp',1,true) and src:find('EQUIPSLOTS.HEAD',1,true))
assert(read_source('stategraphs/SGslurtle.lua'):find('FrameEvent(9',1,true))
for k,v in pairs(modules) do package.loaded[k]=v end
GetTime,TheWorld,TheSim=saved.time,saved.world,saved.sim
print('PASS: actual wave6 bat boss config/head parasite, detach/drop/equip ACKs, normal melee boss priority, chomp and lunge windows; snail strike drift commitment, urgent bite preemption and immediate burning/explosion avoidance')
