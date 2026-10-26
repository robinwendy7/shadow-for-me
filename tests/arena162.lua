local savedA=package.loaded['shadowself/control/actions'];local savedN=package.loaded['shadowself/control/arena_snails'];local oldTime=GetTime
local now=0;GetTime=function() return now end
local function entity(name,x)
 local e={prefab=name,GUID=x or 1,pos=Vector3(x or 0,0,0),tags={},anim='idle_loop',frame=0,replica={combat={GetAttackRangeWithWeapon=function() return 2 end}}}
 function e:IsValid() return true end;function e:HasTag(k) return self.tags[k] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return a==e.anim end,GetCurrentAnimationFrame=function() return e.frame end}
 return e
end
local p=entity('wilson',0);local busy=false;local equipped=false;local attacks=0;local guard
p.components={playercontroller={IsBusy=function() return busy end}}
package.loaded['shadowself/control/actions']={Stop=function() end,Attack=function(_,target,check) assert(not check or check());attacks=attacks+1;guard=check;return true end}
package.loaded['shadowself/control/arena_snails']=nil
local M=require('shadowself/control/arena_snails');local torch=entity('torch');local hasTorch=true
p.replica.inventory={GetEquippedItem=function() return equipped and torch or nil end}
local c={player=p,enemies={},bridge={allowed=function(e) return not M.Burning(e) end,PauseAttack=function() end},mechanisms={Equip=function(_,item) assert(item==torch);return equipped end}}
local boss={c=c,Item=function() return hasTorch and torch end,Release=function() end,Away=function() return 'move' end,Select=function(_,e) return e end}
for _,name in ipairs({'slurtle','snurtle'}) do
 local snail=entity(name,1);now=now+3;boss.next_snail_fire=nil;c.enemies={}
 equipped=false;local before=attacks
 assert(M.Tick(boss,snail)=='support' and attacks==before,'wait for actual torch equip acknowledgement')
 equipped=true;assert(M.Tick(boss,snail)=='support' and attacks==before+1)
 M.Tick(boss,snail);assert(attacks==before+1,'wait for burning sync rather than duplicate attacks')
 local delayed=guard;snail.pos=Vector3(1.3,0,0);assert(delayed(),'small target movement after contact keeps the real torch-range attack');snail.pos=Vector3(1,0,0);snail.tags.fire=true
 assert(not delayed() and M.Tick(boss,snail)=='move','burning acknowledgement cancels stale attack and exits explosion radius')
 assert(attacks==before+1)
 assert(require('shadowself/control/arena_fire').Zone(snail,p).fire,'fresh ignition immediately creates a burning danger zone')
 now=now+6
 local zone=require('shadowself/control/arena_fire').Zone(snail,p)
 assert(zone and zone.explosive_snail and zone.radius>3,'burning snail explosion joins normal arena hazard escape')
 p.pos=Vector3(8,0,0);local other=entity('slurper',12);c.enemies={snail,other}
 local mode,target=M.Tick(boss,snail);assert(mode=='attack' and target==other,'leave burning snail alone and fight another target')
 c.enemies={snail};assert(M.Tick(boss,snail)=='support','last burning snail waits for actual explosion')
 p.pos=Vector3(0,0,0)
end
hasTorch=false;assert(not M.Tick(boss,entity('snurtle',1)),'missing torch preserves ordinary combat fallback')
package.loaded['shadowself/control/actions']=savedA;package.loaded['shadowself/control/arena_snails']=savedN
-- 执行真实走位入口及实际slurper表项，不以手写伪表代替。
local f=assert(io.open('scripts/shadowself/native/engine/Dodge.lua','r'));local src=f:read('*a');f:close()
local finish=assert(src:find("\n\taddcreature('dragonfly', 'taunt_pre'",1,true))
local first=assert(src:find("\taddcreature('slurper', 'atk'",1,true));local last=assert(src:find("\n\taddcreature('spider_common'",first,true))
local H={GetTargetCanHitRange=function() return 5 end}
local env=setmetatable({HitAndRun=H,GLOBAL={DEGREES=math.pi/180},ThePlayer=p,
 FunctionOrValue=function(v,...) return type(v)=='function' and v(...) or v end,
 GAME_util={GetGameDelay=function() return 0 end},
 ENT_util={GetAnimation=function(_,e) return e.anim end,FnOrNum=function(_,v,...) return type(v)=='function' and v(...) or v end},
 distsq=function(a,b) return a:DistSq(b) end},{__index=_G})
local fn=assert(loadstring(src:sub(1,finish-1)..src:sub(first,last-1)..'\nend'));setfenv(fn,env);fn()
local slurper=entity('slurper',1)
assert(H:RunAwayOverride(slurper),'slurper now has usable native dodge windows')
for _,a in ipairs({'idle_loop','walk_loop','run_loop','headslurpmiss','hit'}) do
 slurper.anim=a;H.idle_ticks=999
 assert(not H:IsAttackPre(slurper,1),'idle/recovery cannot become permanent retreat: '..a)
end
for _,state in ipairs({{'atk',30},{'headslurp',24}}) do
 slurper.anim=state[1]
 for _,frame in ipairs({0,8,20,state[2]}) do slurper.frame=frame;assert(H:IsAttackPre(slurper,1)) end
 slurper.frame=state[2]+1;assert(not H:IsAttackPre(slurper,1),'completed slurper attack releases normal output')
end
assert(read_source('stategraphs/SGslurper.lua'):find('TimeEvent(30*FRAMES',1,true))
local snailSource=read_source('prefabs/slurtle.lua');assert(snailSource:find('explosiverange = 3',1,true) and snailSource:find('SetOnIgniteFn(OnIgniteFn)',1,true))
GetTime=oldTime
print('PASS: actual slurper roll/headslurp windows and idle/output recovery; both snails torch acknowledgement, no repeat after burning, delayed action revoked, explosion escape and other-target handoff')
