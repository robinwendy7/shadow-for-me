local oldTime,oldWorld=GetTime,TheWorld
local oldActions=package.loaded['shadowself/control/actions']
local oldOpening=package.loaded['shadowself/control/arena_opening']
local now=0;GetTime=function() return now end
local function entity(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),tags={}}
 function e:IsValid() return not self.removed end
 function e:GetPosition() return self.pos end
 function e:HasTag(tag) return self.tags[tag] or false end
 return e
end
local p=entity('wilson');local busy=false;local animation='idle'
p.components={playercontroller={IsBusy=function() return busy end}}
p.AnimState={IsCurrentAnimation=function(_,name) return name==animation end}
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local Fire=require('shadowself/control/arena_fire')
local flame=entity('houndfire');local zones=Fire.Zones(p,{flame})
assert(#zones==1 and zones[1].radius>3,'houndfire has damaging zone with player margin')
local escape=Fire.Escape(p,zones);assert(escape and Fire.Safe(p,escape,zones),'standing in ground fire escapes fully outside')
p.pos=Vector3(-6,0,0)
assert(not Fire.Safe(p,Vector3(6,0,0),zones),'route cannot cross fire to loot on opposite side')
assert(Fire.Safe(p,Vector3(-6,0,4),zones),'safe nearby route remains available')
local fx=entity('fire');local torch=entity('torch');fx.entity={GetParent=function() return torch end}
assert(not Fire.Zone(fx,p),'held torch and controlled campfire not treated as damaging ground fire')
local burning=entity('evergreen');fx.entity.GetParent=function() return burning end
assert(Fire.Zone(fx,p),'burning scenery fire remains dangerous')
flame.removed=true;assert(#Fire.Zones(p,{flame})==0,'expired fire removed immediately')
p.pos=Vector3(0,0,0)
local flute=entity('panflute');local items={flute};local plays=0;local stops=0
local moved
package.loaded['shadowself/control/actions']={Items=function() return items end,Stop=function() stops=stops+1 end,
 Move=function(_,q) moved=q end,
 Self=function(_,item,action) assert(item==flute and action==ACTIONS.PLAY);plays=plays+1;return true end}
package.loaded['shadowself/control/arena_opening']=nil
local arena={player=p,wave=3,bridge={},StopCombat=function() stops=stops+1 end}
local opening=require('shadowself/control/arena_opening')(arena);opening:Reset()
assert(not opening:Tick({}) and plays==0,'wait for actual monster spawn rather than wave number alone')
local bishop=entity('bishop',6,0);local knight=entity('knight',2,0);local rook=entity('rook',-4,0)
assert(opening:Tick({knight,bishop,rook}) and plays==1 and arena.bridge.priority_target==bishop,'spawn starts single flute and bishop priority')
now=.4;opening:Tick({knight,bishop,rook});assert(plays==1,'pending play does not resend')
bishop.tags.sleeping=true;knight.tags.sleeping=true;rook.tags.sleeping=true;busy=true;now=1.1
assert(opening:Tick({knight,bishop,rook}),'sleep acknowledgement must not cancel remaining instrument action')
now=2;busy=false;assert(not opening:Tick({knight,bishop,rook}) and opening.done)
assert(opening.rhythm and opening.rhythm.target==bishop,'ordinary and shadow clockworks share the requested bishop rhythm')
now=3;assert(not opening:Tick({knight,bishop,rook}) and plays==1,'only one successful opener in this wave')
assert(not opening:Tick({knight}) and not arena.bridge.priority_target,'bishop death releases ordinary target selection')
arena.wave=2;opening:Reset();assert(not opening:Tick({bishop}) and plays==1,'other waves do not play opener')
arena.wave=3;items={};assert(not opening:Tick({bishop}) and opening.done,'missing flute does not stall combat forever')
items={flute};opening:Reset();now=10
local sb=entity('bishop_nightmare',6,0);local sk=entity('knight_nightmare',2,0);local sr=entity('rook_nightmare',-4,0)
assert(opening:Tick({sb,sk,sr}) and not opening.rhythm,'sending PLAY alone cannot enable the strike budget')
now=12;sb.tags.sleeping=true;sk.tags.sleeping=true
assert(opening:Tick({sb,sk,sr}) and not opening.rhythm,'two sleeping enemies are insufficient')
sr.tags.sleeping=true;assert(not opening:Tick({sb,sk,sr}) and opening.rhythm.target==sb,'all three sleep confirmations arm the shadow bishop opening')
opening:Reset();assert(not opening.rhythm,'new wave clears the completed-swing budget')
knight.tags.sleeping=nil;rook.tags.sleeping=nil
-- 执行真实Secondary路径：骑士临时接管躲避后，恢复主教而不是原样返回骑士。
local c={player=p,plan={arena=true},h={ent=knight,selected_ents={[knight]=true,[bishop]=true}},enemies={},hazards={}}
c.bridge={priority_target=bishop,allowed=function(e) return e:IsValid() and not e:HasTag('dead') end,
 wrappers={PreTheLoop={old=function() end}}}
local secondary=require('shadowself/control/secondary')(c)
secondary.Scan=function() end;secondary.Danger=function() return nil end
assert(secondary:AfterDodge(knight)==bishop and c.h.ent==bishop,'knight dodge followup returns bishop, not captured knight')
c.h.ent=knight;secondary.data={};secondary:Pulse()
assert(c.h.ent==bishop,'idle native inner loop retargets bishop without waiting for knight death')
c.h.ent=knight;secondary.data={[knight]={atkanim='atk'}};secondary:Pulse()
assert(c.h.ent==knight,'active knight windup retains native dodge target')
assert(not secondary:BeforeAttack(false) and c.h.ent==knight,'cannot strike knight or interrupt its active dodge to chase bishop')
secondary.data={};assert(not secondary:BeforeAttack(false) and c.h.ent==bishop,'ordinary attack redirected to bishop before off-target hit')
c.h.ent=knight;c.plan.arena=false;assert(not secondary:Preferred(),'ordinary fights retain nearest-target behavior')
c.plan.arena=true;bishop.tags.dead=true;assert(not secondary:Preferred(),'dead bishop releases focus')
-- 最新战术：催眠后主教未死时，侧方新攻击不再抢占。
bishop.tags.dead=nil;c.h.ent=bishop;secondary.data={[knight]={atkanim='atk'}};secondary.enemies={knight,bishop}
c.plan.arena_clockwork={target=bishop,Live=function() return not bishop.tags.dead end}
assert(not secondary:Danger(bishop) and secondary:BeforeAttack(false) and c.h.ent==bishop,'living bishop suppresses off-target attack takeover')
bishop.tags.dead=true;assert(not secondary:Focus(),'bishop confirmed death restores other threat processing')
-- 第一关：靠近骗首攻，第13帧之后且已拉开才恢复攻击。
arena.wave=1;items={entity('spear')};items[1].tags.weapon=true;opening:Reset()
local pig=entity('pigman',4,0);local piganim='idle';local pigframe=0
pig.replica={combat={GetAttackRangeWithWeapon=function() return 3 end}}
pig.AnimState={IsCurrentAnimation=function(_,n) return n==piganim end,GetCurrentAnimationFrame=function() return pigframe end}
now=30;p.pos=Vector3(0,0,0)
assert(opening:Tick({pig}) and moved:DistSq(pig.pos)<3^2,'approach into the first attack trigger')
p.pos=moved;piganim='atk';pigframe=1;now=31
assert(opening:Tick({pig}) and moved:DistSq(pig.pos)>=4^2,'first attack causes immediate disengage')
p.pos=moved;pigframe=12;assert(opening:Tick({pig}),'no attack before first damage frame')
pigframe=13;assert(not opening:Tick({pig}) and opening.done,'confirmed first attack unlocks normal combat')
-- 第二关：覆盖三种高脚鸟，仅一次PLAY，幼年→青年→成年。
arena.wave=2;opening:Reset();items={flute};p.pos=Vector3(0,0,0);now=40
local small,teen,tall=entity('smallbird',1),entity('teenbird',3),entity('tallbird',5)
local before=plays
assert(opening:Tick({tall,teen,small}) and plays==before+1 and opening.target==small)
small.tags.sleeping=true;teen.tags.sleeping=true;now=42
assert(opening:Tick({tall,teen,small}),'all three must actually sleep before attack')
tall.tags.sleeping=true;assert(not opening:Tick({tall,teen,small}) and plays==before+1)
small.tags.dead=true;opening:Tick({tall,teen,small});assert(opening.target==teen)
teen.tags.dead=true;opening:Tick({tall,teen,small});assert(opening.target==tall and plays==before+1)
opening:Reset();now=50;small.tags.dead=nil;teen.tags.dead=nil
opening:Tick({tall,teen,small});now=54;small.tags.sleeping=nil;opening:Tick({tall,teen,small})
assert(opening.done and plays==before+2,'failed control does not dispatch another flute in this opening')
print('PASS: bishop focus survives native inner loop, knight dodge followup and off-target attack attempts; active dodge and non-arena targeting preserved')
package.loaded['shadowself/control/actions']=oldActions;package.loaded['shadowself/control/arena_opening']=oldOpening
GetTime=oldTime;TheWorld=oldWorld
print('PASS: arena groundfire escape/crossing/controlled-fire exclusion; wave3 actual spawn, one acknowledged flute, no animation interruption, bishop focus and fallback')
