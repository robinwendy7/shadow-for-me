local oldTime,oldWorld=GetTime,TheWorld
local modules={};for _,n in ipairs({"actions","arena_tools","arena_spiders","arena_opening"}) do
 local key="shadowself/control/"..n;modules[key]=package.loaded[key];package.loaded[key]=nil
end
local now,busy,plays,moves=0,false,0,0
GetTime=function() return now end
local blocked=false
TheWorld={Map={IsPassableAtPoint=function() return not blocked end,IsOceanAtPoint=function() return false end},
 Pathfinder={IsClear=function() return not blocked end}}
local function entity(n,x,z)
 local e={prefab=n,pos=Vector3(x or 0,0,z or 0),tags={},replica={combat={}}}
 function e:IsValid() return not self.invalid end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 return e
end
local p=entity('wilson');p.components={playercontroller={IsBusy=function() return busy end}}
local flute=entity('panflute');local bag={flute};local moved
package.loaded['shadowself/control/actions']={Items=function() return bag end,Stop=function() end,
 Move=function(_,q) moves=moves+1;moved=q end,Self=function(_,item,action)
 assert(item==flute and action==ACTIONS.PLAY);plays=plays+1;return true end}
local arena={player=p,wave=2,running=true,bridge={},StopCombat=function() end,fire_zones={}}
local Opening=require('shadowself/control/arena_opening');local o=Opening(arena);arena.opening=o
local spider,bat,hider,spitter=entity('spider',2),entity('bat',4),entity('spider_hider',5),entity('spider_spitter',6)
local enemies={spider,bat};arena.enemies=enemies;arena.entities={spider,bat}
assert(not o:Tick(enemies) and plays==0,'no special spider: preserve existing fight')
arena.entities={spider,bat,entity('spider_dropper')};assert(not o:Tick(enemies),'dangling spider is not cave spider')
arena.entities={spider,bat,hider};assert(o:Tick(enemies) and plays==1,'one cave spider is sufficient, even absent from wave roster')
assert(not o.spiders:Allowed(spider) and not o.spiders:Allowed(bat),'no attacks before acknowledgement')
spider.tags.sleeping=true;bat.tags.sleeping=true;now=2
assert(o:Tick(enemies) and not o.spiders.ready,'special spider must sleep as well')
now=4;assert(o:Tick(enemies) and not o.spiders.ready,'timeout cannot authorize attacks')
now=5;assert(o:Tick(enemies) and plays==2,'unconfirmed control retries')
hider.tags.sleeping=true;busy=true;now=7
assert(o:Tick(enemies),'do not interrupt remaining play animation')
busy=false;assert(not o:Tick(enemies) and o.spiders.ready)
assert(o.spiders:Allowed(spider) and o.spiders:Allowed(bat))
assert(not o.spiders:Allowed(hider) and not o.spiders:Allowed(spitter) and not o.spiders:Allowed(entity('spider_warrior')))
spider.tags.dead=true;bat.tags.dead=true
assert(not o:Tick({}) and not o.spiders:Allowed(hider),'no fallback attack against protected spiders')
-- 喷吐蜘蛛独立触发；覆盖包含陷阱及未列入波次名单的子代。
o:Reset();spider.tags.dead=nil;bat.tags.dead=nil;spider.tags.sleeping=nil;bat.tags.sleeping=nil
p.pos=Vector3(-20,0,0);spider.pos=Vector3(-3,0,0);bat.pos=Vector3(3,0,0);spitter.pos=Vector3(9,0,0)
local dog=entity('icehound',11);dog.tags.sleeping=true
arena.entities={spider,bat,spitter,dog};now=10;local count=plays
assert(o:Tick(enemies) and moves>0 and plays==count)
for _,e in ipairs(arena.entities) do assert(moved:DistSq(e.pos)<=((TUNING.PANFLUTE_SLEEPRANGE or 15)-1)^2) end
p.pos=moved;now=11;assert(o:Tick(enemies) and plays==count+1)
spider.tags.sleeping=true;bat.tags.sleeping=true;spitter.tags.sleeping=true;spitter.invalid=true;now=13
assert(o:Tick(enemies) and not o.spiders.ready,'unloaded creature is not death/sleep acknowledgement')
spitter.invalid=nil;assert(not o:Tick(enemies) and o.spiders.ready)
-- 无箫和不可达覆盖点均不得绕过控制，地面拾取也受停止/换关保护。
o:Reset();bag={};arena.items={flute};local guard
arena.Loot=function(_,items,cleared,g) assert(not cleared);guard=g;return true end
assert(o:Tick(enemies) and guard and guard());arena.running=false;assert(not guard());arena.running=true
bag={flute};arena.items={};o:Reset();blocked=true;p.pos=Vector3(-20,0,0);now=20;local before=moves
assert(o:Tick(enemies) and moves==before,'blocked path must not issue movement through walls')
blocked=false;o:Reset();bag={};assert(o:Tick(enemies) and not o.spiders:Allowed(spider),'missing flute never opens attack gate')
arena.wave=3;assert(not o.spiders:Active() and o.spiders:Allowed(hider),'scope excludes other waves')
-- 确认实际源码，不依靠中文猜测。
local hole=read_source('prefabs/spiderhole.lua');assert(hole:find('childname = "spider_hider"',1,true) and hole:find('SetRareChild("spider_spitter"',1,true))
local waves=assert(loadstring(read_astra_source('astra/modes/arena/encounters.lua')))().WAVES_1_2
local set=waves[2].default[4];assert(set.monsters[1].prefab=='bat' and set.monsters[1].amount==5)
assert(set.monsters[2].prefab=='spider' and set.monsters[2].amount==2)
local function source(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local bridge=source('scripts/shadowself/control/combat.lua')
assert(bridge:find('not plan.arena_spider_control(e)',1,true) and bridge:find('not c.plan.arena_spider_control(victim)',1,true),'selection and actual attack both guarded')
assert(source('scripts/shadowself/control/encounters.lua'):find('arena_spider_scene()',1,true),'generic wind bypasses controlled spider scene')
for key,value in pairs(modules) do package.loaded[key]=value end
GetTime,TheWorld=oldTime,oldWorld
print('PASS: wave2 exact spider/bat prefabs, full live roster coverage, real sleep acknowledgement, failed/missing flute gate, blocked route, reset and native attack/wind integration')
