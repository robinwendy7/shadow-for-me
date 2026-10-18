local savedA=package.loaded["shadowself/control/actions"]
local saved={time=GetTime,vec=Vector3,sim=TheSim,actions=ACTIONS,slots=EQUIPSLOTS}
local now=100;GetTime=function() return now end
Vector3=function(x,y,z) local p={x=x,y=y,z=z};function p:DistSq(v) return (self.x-v.x)^2+(self.z-v.z)^2 end;return p end
ACTIONS={EQUIP={},FISH={},REEL={},OCEAN_FISHING_CATCH={},OCEAN_FISHING_REEL={},OCEAN_FISHING_CAST={},OCEAN_FISHING_STOP={},PLAY={},CASTSPELL={},ATTACK={}}
EQUIPSLOTS={HANDS=1}
local events={};local items={};local entities={};local held
local function event(action,target) events[#events+1]={action=action,target=target} end
local function ent(prefab,x,z)
    local e={prefab=prefab,pos=Vector3(x or 0,0,z or 0),tags={},replica={}}
    function e:IsValid() return true end;function e:HasTag(tag) return self.tags[tag] end
    function e:GetPosition() return self.pos end
    e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end}
    return e
end
local p=ent("wilson");p.replica.inventory={GetEquippedItem=function() return held end}
p.components={playercontroller={IsBusy=function() return false end}}
function p:GetDistanceSqToInst(e) return self.pos:DistSq(e.pos) end
local A={Items=function() return items end,Stop=function() end,
    Self=function(_,item,action) if action==ACTIONS.EQUIP then held=item end;event(action,item);return true end,
    ReelPond=function(_,rod,target,guard) assert(guard());event(ACTIONS.REEL,target);return true end,
    Scene=function(_,target,action,guard) assert(not guard or guard());event(action,target);return true end,
    Ground=function(_,point,action,guard) assert(guard());event(action,point);return true end,
    Attack=function(_,target) event(ACTIONS.ATTACK,target);return true end,
    UseOn=function(_,item,target,action) event(action,target);return true end}
package.loaded["shadowself/control/actions"]=A
TheSim={FindEntities=function() return entities end}
local pond=ent("pond",5,0);pond.tags.fishable=true;entities={pond}
local rod=ent("fishingrod");local active,hooked,caught
rod.replica.fishingrod={GetTarget=function() return active end,HasHookedFish=function() return hooked end,HasCaughtFish=function() return caught end}
items={rod}
package.loaded["shadowself/control/fishing"]=nil
local Fish=require("shadowself/control/fishing")
local f=Fish(p,{mode="pond"});assert(f:Tick()=="running" and held==rod)
now=now+1;f:Tick();assert(events[#events].action==ACTIONS.FISH)
active=pond;local n=#events;now=now+1;f:Tick();assert(#events==n,"no early reel before fish actually hooks")
p.anim="bite_light_loop";hooked=false;now=now+1;f:Tick()
assert(events[#events].action==ACTIONS.REEL,"nibble animation must trigger first hook before HasHookedFish becomes true")
n=#events;now=now+.3;f:Tick();assert(#events==n,"do not send repeated hook requests while waiting for the hook stage")
hooked=true;p.anim="bite_heavy_loop";now=now+.3;f:Tick();assert(#events==n+1 and events[#events].action==ACTIONS.REEL,"hooked fish triggers second reel to collect")
caught=true;n=#events;now=now+.3;f:Tick();assert(#events==n,"caught fish waits for collect animation, never hooks another fish")
p.anim=nil
f:Pause();now=now+1;n=#events;f:Tick();assert(#events==n);f:Resume()
local sea=ent("oceanfishingrod");local target=ent("oceanfishingbobber");local high=true;active=target
sea.replica.oceanfishingrod={GetTarget=function() return active end,IsLineTensionHigh=function() return high end,GetMaxCastDist=function() return 12 end}
held=sea;items={sea};p.tags.fishing_idle=true
local ocean=Fish(p,{mode="sea"});n=#events;ocean:Tick();assert(#events==n,"high tension releases instead of snapping line")
high=false;target.tags.fishinghook=true;now=now+1;n=#events;ocean:Tick();assert(#events==n,"unbitten float is not continuously reeled back to shore")
target.tags.fishinghook=nil;now=now+1;ocean:Tick();assert(events[#events].action==ACTIONS.OCEAN_FISHING_REEL)
target.tags.oceanfishing_catchable=true;now=now+1;ocean:Tick();assert(events[#events].action==ACTIONS.OCEAN_FISHING_CATCH)
active=nil;local fish=ent("oceanfish_small_1",7,0);fish.tags.oceanfish=true;entities={fish};now=now+1;ocean:Tick();assert(events[#events].action==ACTIONS.OCEAN_FISHING_CAST)
ocean:Cancel()
local Request=require("shadowself/control/request")
assert(Request.Parse("帮我钓鱼").mode=="pond" and Request.Parse("帮我海钓").mode=="sea")
assert(Request.Parse("你会钓鱼吗")==nil and Request.Parse("别帮我钓鱼")==nil,"questions and negative requests do not request takeover")
-- Queen strategy uses visible roster/animation, not unsynchronized phase fields.
package.loaded["shadowself/control/beequeen"]=nil
local queen=ent("beequeen",0,0);local bees={}
for i=1,4 do bees[i]=ent("beeguard",i+1,0) end
local c={gear={},actions={SafePoint=function() return true end},hazards={},player=p,enemies={queen,unpack(bees)},h={},bridge={allowed=function(e) return e==queen end,wrappers={PreTheLoop={old=function() end}}}}
function c:Move(point,label) self.moved=point;self.blocked=true end
c.gear.Swap=function(self)
 local item=self.support_hand and self.support_hand.item or self.forced_weapon
 if item and held~=item then A.Self(p,item,ACTIONS.EQUIP) end
 return not item or held==item
end
c.gear.Mobile=function(self) return self.forced_weapon end
local Q=require("shadowself/control/beequeen")(c)
assert(Q:Tick() and Q.allow==bees[1] and c.target==bees[1],"first phase clears initial guard roster, not queen")
c.enemies={queen,bees[1]};items={ent("icestaff")};now=now+1
Q:Tick();assert(c.blocked and c.gear.forced_weapon==items[1],"keep staff ownership while positioning around last guard");p.pos=Vector3(8,0,0)
now=now+.2;Q:Tick();assert(events[#events].action==ACTIONS.ATTACK,"idle queen range no longer delays the shot")
now=now+.8;Q:Tick();assert(events[#events].action==ACTIONS.ATTACK,"ice projectile is fired by ATTACK, not CASTSPELL")
bees[1].tags.frozen=true;Q:Tick();assert(c.target==queen,"frozen last guard leaves queen as solo target")
Q.phase=2;queen.anim=nil;bees[1].tags.frozen=nil;p.pos=Vector3(10,0,0);bees[1].pos=Vector3(15,0,0)
items={ent("panflute")};now=now+5;Q:Tick();assert(Q.late and events[#events].action==ACTIONS.PLAY,"command-stage full coverage starts a flute cycle")
queen.anim="sleep_loop";bees[1].tags.sleeping=true;now=now+1.8;Q:Tick();assert(Q.stage=="strike" and Q.allow==queen and not c.blocked,"confirmed full sleep returns directly to queen solo")
-- 守卫始终未满足旧版 far 条件也必须到时折返；持续战吼不能重置时钟。
local fixed=Q.anchor;bees[1].tags.sleeping=nil;items={};p.pos=Vector3(6,0,0);queen.pos=Vector3(0,0,0)
bees[1].pos=Vector3(4,0,0);queen.anim=nil;Q.was_command=nil;Q:Lure(now);Q:Tick()
local start=Q.lure_since
now=now+7.1;Q:Tick()
assert(Q.stage=="lure","unseparated awake guards keep lure mode rather than cutting back into them")
now=now+10;Q:Tick();assert(Q.stage=="lure","guard separation, not an arbitrary timeout, opens the return")
assert(Q.anchor==fixed,"same queen retains fixed arena center")
-- 每次实际发出的短路线受战场和蜂后距离限制；场外仅允许向内回。
c.enemies={queen};p.pos=Vector3(10,0,0)
Q:Move(Vector3(100,0,0),"test",queen)
assert(c.moved:DistSq(queen.pos)<=18^2 and c.moved:DistSq(Q.anchor)<=40^2,"outbound goal cannot cross either leash limit")
p.pos=Vector3(20,0,0);Q:Move(Vector3(100,0,0),"test",queen)
assert(c.moved.x<20,"starting outside the limit must move inward, not keep chasing an outward goal")
-- 蜂后移动不会拖着战场中心移动，且蜂蜜仍参与沿途筛选。
queen.pos=Vector3(2,0,0);p.pos=Vector3(5,0,0);c.enemies={queen};c.hazards={{pos=Vector3(7,0,0),radius=1}}
Q:Move(Vector3(10,0,0),"test",queen)
assert(require("shadowself/control/navigation").Safe(c,c.moved,queen),"bounded lure retains whole-path honey avoidance")
assert(Q.anchor==fixed and Q.anchor.x==0,"arena does not drift with queen movement")
-- 持续模拟旧版永远达不到 far 的追赶：每一步实际移动都留在战场内。
queen.pos=Vector3(0,0,0);p.pos=Vector3(6,0,0);bees[1].pos=Vector3(4,0,0)
queen.anim=nil;c.enemies={queen,bees[1]};c.hazards={}
local bounded=require("shadowself/control/beequeen")(c);bounded:Anchor(queen);bounded.phase=2;local returned=false
for i=1,80 do
 now=now+.1;bounded:Tick()
 if bounded.stage=="return" then returned=true end
 if c.moved then p.pos=c.moved end
 assert(p.pos:DistSq(bounded.anchor)<=40^2 and p.pos:DistSq(queen.pos)<=18^2,"repeated lure steps never drift out of the arena")
 -- 守卫与蜂后始终相距不足9，重现旧代码无法切回的条件。
 bees[1].pos=Vector3(queen.pos.x+4,0,queen.pos.z)
end
assert(bounded.stage=="lure","unseparated guards cannot trigger a melee return")
-- Queen-specific geometry: straight pull, queen overtakes guards, then punish.
queen.pos=Vector3(0,0,0);queen.anim=nil;p.pos=Vector3(6,0,0);bees[1].pos=Vector3(4,0,0)
bees[1].tags={};c.enemies={queen,bees[1]};c.hazards={};c.observed={};items={}
local queen_cane=false;c.travel={BeginDodge=function() queen_cane=true end,EndDodge=function() queen_cane=false end}
local line=require("shadowself/control/beequeen")(c);line:Anchor(queen);line.phase=2;now=now+1;line:Tick()
assert(queen_cane,"queen straight pull borrows cane")
assert(line.stage=="lure" and c.moved.x>6 and math.abs(c.moved.z)<.001,"queen pulls straight instead of issuing an orbit goal")
assert(not line:Formation(queen,{bees[1]},p.pos),"guard between player and queen is not a successful separation")
queen.pos=Vector3(6,0,0);p.pos=Vector3(10,0,0);bees[1].pos=Vector3(4,0,0);queen.anim=nil
now=now+.3;line:Tick()
assert(not queen_cane,"queen output restores weapon")
assert(line.formed and line.stage=="strike" and c.target==queen and not c.blocked,"queen overtaking guard opens attack without needing nine-unit radial spread")
assert(line:Formation(queen,{bees[1]},p.pos),"player queen guard ordering is recognized")
-- Sleeping guards close to player do not force endless reluring.
bees[1].tags.sleeping=true;bees[1].pos=Vector3(9.5,0,0);line.stage="return";now=now+.1;line:Tick()
assert(line.stage=="strike" and not c.blocked,"slept guards cannot block return-to-output")
bees[1].tags.sleeping=nil;bees[1].pos=Vector3(9.5,0,0);now=now+.1;line:Tick()
assert(line.stage=="lure","awake guard reaching player restarts separation, not generic crowd gathering")
-- Return vector is fixed for the leg, so repeated ticks cannot rotate the goal.
line:Return(now,queen,{bees[1]});local direction=line.return_dir
assert(direction.x<0,"cutback chooses the opposite side of queen from guards")
p.pos=Vector3(10,0,3);assert(line.return_dir==direction,"player moving does not rotate return direction each frame")
-- Opening screech and a five-guard roster are still phase one.
queen.pos=Vector3(0,0,0);queen.anim="screech";p.pos=Vector3(5,0,0)
local five={queen};for i=1,5 do five[#five+1]=ent("beeguard",i+1,0) end
c.enemies=five;c.hazards={};items={}
local first=require("shadowself/control/beequeen")(c);first:Tick()
assert(first.phase==1 and not first.late and c.target.prefab=="beeguard","five guards/opening screech cannot trigger late-phase lure")
queen.replica.health={GetPercent=function() return .74 end};now=now+.2;first:Tick()
assert(first.phase==2 and first.late,"75 percent health ends phase-one leave-one strategy")
queen.replica.health=nil
queen.anim="atk";queen.Transform={GetRotation=function() return 0 end}
queen.AnimState.GetCurrentAnimationFrame=function() return 12 end
function p:GetPhysicsRadius() return .5 end
first:Honey(queen,p.pos,now)
assert(#first.predicted>=1 and first.predicted[1].pos.x==4,"miss honey predicted four units along facing before impact")
package.loaded["shadowself/control/actions"]=savedA
GetTime=saved.time;Vector3=saved.vec;TheSim=saved.sim;ACTIONS=saved.actions;EQUIPSLOTS=saved.slots
print("PASS: rod equip, pond wait/hook/reel, ocean tension/reel/catch/recast, pause/cancel; queen first roster/last freeze/pipe, bounded straight lure, player-queen-guard formation, fixed cutback, command edge, timed return, fixed arena and honey avoidance")
