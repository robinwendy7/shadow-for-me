local saved={actions=package.loaded['shadowself/control/actions'],encounters=package.loaded['shadowself/control/arena_encounters'],time=GetTime,net=TheNet,world=TheWorld}
local now,ping=0,34;GetTime=function() return now end;TheNet={GetPing=function() return ping end}
TheWorld={Map={IsOceanAtPoint=function() return true end,IsPassableAtPoint=function() return true end}}
local function ent(name,x)
 local e={prefab=name,pos=Vector3(x or 0,0,0),tags={},replica={}}
 function e:IsValid() return not self.removed end
 function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end
 return e
end
local p=ent('wilson',20);local kit=ent('boat_item');local boat=ent('boat',12)
local count=1;local can=true;local busy=false;local buffered;local bag={kit}
kit.replica.stackable={StackSize=function() return count end}
kit.replica.inventoryitem={CanDeploy=function() return can end}
function p:GetCurrentPlatform() end
function p:GetBufferedAction() return buffered end
p.components={playercontroller={IsBusy=function() return busy end}}
local requests,moves=0,0
package.loaded['shadowself/control/actions']={Items=function() return bag end,Deploy=function() requests=requests+1;return true end,Move=function() moves=moves+1 end}
package.loaded['shadowself/control/arena_encounters']=nil
local E=require('shadowself/control/arena_encounters')
local arena={wave=8,player=p,items={},StopCombat=function() end,Say=function() end}
local point=Vector3(12,0,0)
local function start()
 local s=E(arena);s.center=Vector3(0,0,0);s:DeployBoat(kit,point);return s
end
local s=start();assert(requests==1 and s.deploy.deadline==6)
now=.2;s:Crab({});assert(requests==1,'first failed or unacknowledged request is not spammed every tick')
now=.76;s:Crab({});assert(requests==2 and s.deploy.deadline==6,'idle client with unchanged owned boat kit retries without a six-second blind wait')
now=.8;s:Crab({boat});assert(moves==1 and not s.deploy and requests==2,'real replicated boat immediately preempts retries and starts boarding')
-- 消耗一份可堆叠船套或整个船套消失，都不能触发第二次部署。
now=10;count=3;s=start();local before=requests;count=2;now=11;s:Crab({})
assert(requests==before and s.deploy,'stack consumption waits for boat acknowledgement instead of deploying another boat')
now=17;s:Crab({});assert(requests==before and s.deploy,'consumed kit remains protected even past old timeout')
now=20;count=1;s=start();bag={};before=requests;now=21;s:Crab({})
assert(requests==before and s.deploy,'fully consumed boat kit cannot be retried using another kit')
bag={kit};now=30;s=start();before=requests
busy=true;now=31;s:Crab({});assert(requests==before,'busy deployment action is not overwritten')
busy=false;p.tags.moving=true;now=32;s:Crab({});assert(requests==before,'walking toward deployment remains uninterrupted')
p.tags.moving=nil
local oldDeploy=ACTIONS.DEPLOY;ACTIONS.DEPLOY=oldDeploy or {}
buffered={action=ACTIONS.DEPLOY};now=33;s:Crab({});assert(requests==before,'buffered deploy is not duplicated despite a clear busy tag')
buffered=nil;now=33.1;s:Crab({});assert(requests==before+1 and s.deploy.deadline==36,'idle retry keeps the original bounded confirmation window')
now=34;s:Crab({});assert(requests==before+2 and s.deploy.attempts==3)
now=35;s:Crab({});assert(requests==before+2,'at most three requests are sent in one deployment confirmation window')
now=36.1;s:Crab({});assert(not s.deploy,'unconsumed failed attempt eventually returns to normal placement search')
ACTIONS.DEPLOY=oldDeploy
-- 地形变化后的旧点不能重复发送；高延迟要给已发请求足够的确认时间。
now=40;s=start();before=requests;can=false;now=41;s:Crab({})
assert(requests==before and not s.deploy,'invalidated water point is replanned rather than retried blindly')
can=true;ping=1200;now=50;s=start();before=requests
now=51;s:Crab({});assert(requests==before,'high RTT extends acknowledgement time instead of using the low-ping retry interval')
now=51.61;s:Crab({});assert(requests==before+1)
package.loaded['shadowself/control/actions']=saved.actions;package.loaded['shadowself/control/arena_encounters']=saved.encounters
GetTime,TheNet,TheWorld=saved.time,saved.net,saved.world
print('PASS: deploy retry replaces observed six-second blind wait; actual boat preempts retry, consumed/stacked kit and busy/moving/buffered actions are protected, retry count and invalid-point/high-RTT handling')
