local saved={actions=package.loaded['shadowself/control/actions'],encounters=package.loaded['shadowself/control/arena_encounters'],time=GetTime,net=TheNet}
local now=0;GetTime=function() return now end;TheNet={GetPing=function() return 50 end}
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={},components={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 function e:GetPhysicsRadius() return 4 end
 return e
end
local boat=ent('boat',15);local p=ent('wilson',15);local oar=ent('oar_driftwood');local basic=ent('oar');basic.tags.oar=true
local bat=ent('ruins_bat');local sword=ent('nightsword');local inventory={basic,oar};local lastEquip
local hand=oar;local platform=boat;local animation='idle';local frame=0;local busy=false
function p:GetCurrentPlatform() return platform end
p.replica.inventory={GetEquippedItem=function() return hand end}
p.AnimState={IsCurrentAnimation=function(_,name) return animation==name end,GetCurrentAnimationFrame=function() return frame end}
p.components.playercontroller={IsBusy=function() return busy end}
local moves,requests,attempts,equips=0,0,0,0;local reject=false;local lastpoint,lastaction,lastguard
package.loaded['shadowself/control/actions']={Stop=function() end,Items=function() return inventory end,
 Move=function(_,q) moves=moves+1;lastpoint=q end,Self=function(_,item) assert(item==oar or item==bat or item==sword);lastEquip=item;equips=equips+1;return true end,
 Ground=function(_,point,action,guard)
  assert(guard());attempts=attempts+1
  if reject then return false end
  requests=requests+1;lastpoint=point;lastaction=action;lastguard=guard;return true
 end}
package.loaded['shadowself/control/arena_encounters']=nil
local E=require('shadowself/control/arena_encounters')
local arena={wave=8,player=p,items={},bridge={Running=function() return false end},StopCombat=function() end,Say=function() end,Loot=function() return false end}
local s=E(arena);local goal=Vector3(0,0,0)
assert(s:Row(boat,goal)=='hold' and requests==1 and moves==0,'confirmed boat and paddle row immediately from boat centre without walking to the rim')
assert(lastaction==ACTIONS.ROW and lastpoint.x<boat.pos.x-4,'mouse row uses a real outside point in the centre direction')
now=.04;s:Row(boat,goal);assert(requests==1,'unacknowledged stroke does not resend every tick')
p.tags.is_rowing=true;animation='row_pre';frame=0;now=.05;s:Row(boat,goal)
assert(requests==1 and not s.row_pending,'observed new rowing state acknowledges request but does not chain inside fail window')
frame=8;now=.2;s:Row(boat,goal);assert(requests==1,'row_pre cannot be interrupted by a premature second stroke')
animation='row_medium';frame=3;now=.27;s:Row(boat,goal);assert(requests==1,'medium frame three still causes ROW_FAIL and must be skipped')
frame=4;now=.3;s:Row(boat,goal)
assert(requests==2 and moves==0,'legal second stroke starts at medium frame four instead of waiting fixed 0.9 seconds')
frame=5;now=.31;s:Row(boat,goal);assert(requests==2,'old stroke animation does not acknowledge an in-flight second request')
animation='row_pre';frame=0;now=.35;s:Row(boat,goal)
assert(not s.row_pending and requests==2,'animation restart acknowledges the next stroke')
animation='row_medium_off';frame=4;now=.6;s:Row(boat,goal);assert(requests==3,'off-hand animation uses the same legal rapid rowing window')
local delayed=lastguard
s.second_phase=true;assert(not delayed(),'queued paddle is cancelled when ice combat starts')
s.second_phase=nil;s.retreat=true;assert(not delayed(),'queued paddle cannot run during walking-only return')
s.retreat=nil;s.row_count=6;assert(not delayed(),'six completed strokes cancel a late queued seventh paddle');s.row_count=0
p.pos=Vector3(15,0,0);platform=nil;assert(not delayed(),'losing the actual platform cancels stale row')
platform=boat
-- 网络没有同步划桨状态时，只做有界确认重试，不把请求成功当作动作已发生。
s:Reset();p.tags.is_rowing=nil;animation='idle';frame=0;now=1
local before=requests;s:Row(boat,goal);now=1.29;s:Row(boat,goal);assert(requests==before+1)
now=1.31;s:Row(boat,goal);assert(requests==before+2,'missing animation acknowledgement retries after a short bounded delay')
-- 原版动作列表暂时拒绝时，不再追加0.9秒空等。
s:Reset();now=2;reject=true;before=attempts;s:Row(boat,goal)
assert(not s.row_pending and attempts==before+1)
now=2.05;s:Row(boat,goal);assert(attempts==before+1)
reject=false;now=2.11;s:Row(boat,goal);assert(attempts==before+2 and s.row_pending,'rejected action is retried promptly once it becomes legal')
-- 船桨优先选真实可用漂流木桨；装备确认一到就衔接，不空等装备重试计时。
s:Reset();now=3;hand=nil;before=requests;s:Row(boat,goal)
assert(equips==1 and requests==before,'unconfirmed hand slot cannot row')
hand=oar;now=3.05;s:Row(boat,goal);assert(requests==before+1,'real equip acknowledgement immediately enables rowing')
-- 手柄的原版方向来自船沿站位，保留它的走位需求。
s:Reset();now=4;p.components.playercontroller.isclientcontrollerattached=true
before=requests;s:Row(boat,goal);assert(moves==1 and requests==before,'controller rowing still moves to the forward edge')
p.pos=lastpoint
local oldController=ACTIONS.ROW_CONTROLLER;ACTIONS.ROW_CONTROLLER=oldController or {}
now=4.1;s:Row(boat,goal)
assert(requests==before+1 and lastaction==ACTIONS.ROW_CONTROLLER,'controller uses actual controller row action after reaching rim')
ACTIONS.ROW_CONTROLLER=oldController
busy=true;s:Reset();before=requests;now=5;s:Row(boat,goal);assert(requests==before,'busy game action is never overwritten by rowing')
-- 六次只按实际动作帧计数；请求和准备动画不能冒充完成。
s:Reset();p.components.playercontroller.isclientcontrollerattached=nil;busy=false;p.pos=Vector3(15,0,0)
platform=boat;hand=oar;animation='idle';frame=0;p.tags.is_rowing=nil;inventory={basic,oar,bat};now=10
local rowBefore=requests;local rests=0
arena.Rest=function(_,near,full,waiting) assert(full and waiting);rests=rests+1 end
s:Row(boat,goal)
for i=1,6 do
 p.tags.is_rowing=true;animation='row_pre';frame=0;now=now+.05;s:Row(boat,goal)
 assert((s.row_count or 0)==i-1,'row preparation acknowledgement is not a completed stroke')
 frame=8;now=now+.05;s:Row(boat,goal)
 assert(s.row_count==i,'actual eighth-frame stroke counts once')
 if i<6 then animation='row_medium';frame=4;now=now+.3;s:Row(boat,goal) end
end
assert(requests==rowBefore+6 and lastEquip==bat and rests==0,'sixth real stroke stops rowing and requests actual ruins bat before recovery')
assert(not lastguard(),'delayed seventh request is rejected after the six-stroke cap')
hand=bat;now=now+.7;s:Row(boat,goal)
assert(requests==rowBefore+6 and rests==1,'confirmed bat keeps hand ownership and waiting starts full-status recovery')
s.center=goal;now=now+.7;s:Crab({boat})
assert(requests==rowBefore+6 and rests==2,'even if boat remains outside centre range there is no seventh stroke')
-- 第八关没有铥棒时，已有影刀直接换装，不被岸上的铥棒拾取挡住。
inventory={oar,sword};hand=oar;arena.items={bat};now=now+.7
local priorEquips=equips;local priorRests=rests
s:Row(boat,goal)
assert(lastEquip==sword and equips==priorEquips+1 and rests==priorRests,'six-stroke wait requests carried nightsword and waits for hand acknowledgement')
now=now+.1;s:Row(boat,goal)
assert(equips==priorEquips+1 and rests==priorRests,'unconfirmed nightsword neither repeats equip nor advances to recovery')
hand=sword;now=now+.1;s:Row(boat,goal)
assert(rests==priorRests+1 and requests==rowBefore+6,'real nightsword acknowledgement completes the handoff without another row')
inventory={oar,sword,bat};hand=oar;now=now+.7
assert(not s:CrabWeapon() and lastEquip==bat,'carried ruins bat retains priority when both weapons are available')
s:Reset();assert(not s.row_count and not s.row_stroke,'new arena opening resets stroke count')
package.loaded['shadowself/control/actions']=saved.actions;package.loaded['shadowself/control/arena_encounters']=saved.encounters
GetTime,TheNet=saved.time,saved.net
print('PASS: immediate mouse rowing after confirmed boarding/equip, legal medium-frame chaining, no row-fail interruption, in-flight ack/rejection retries, controller rim path and stale phase/platform/arrival guards')
