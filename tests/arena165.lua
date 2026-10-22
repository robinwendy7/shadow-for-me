local oldTime,oldWorld=GetTime,TheWorld;local now=0;GetTime=function() return now end
local function ent(name,x,z)
 local e={prefab=name,GUID=tostring(x)..':'..tostring(z),pos=Vector3(x,0,z),tags={},rotation=0}
 function e:IsValid() return true end;function e:HasTag(k) return self.tags[k] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 e.AnimState={IsCurrentAnimation=function(_,a) return a==e.anim end}
 e.Transform={GetRotation=function() return e.rotation end}
 e.replica={combat={GetAttackRangeWithWeapon=function() return 2 end}}
 return e
end
local p=ent('wilson',0,0);local a=ent('knight',-2,0);local b=ent('knight_nightmare',2,0)
local s={player=p,c={player=p,Latency=function() return .03 end},actions={SafePoint=function(_,q) return q.x<5 end},hazards={},enemies={a,b},data={[a]={atkanim='atk'},[b]={atkanim='atk'}}}
TheWorld={Map={IsPassableAtPoint=function(_,x) return x<5 end,IsOceanAtPoint=function(_,x) return x>=5 end}}
local M=require('shadowself/control/crowdroute')
local first=M.Choose(s,Vector3(1,0,0),a)
assert(first and math.abs(first.z)>2 and first:DistSq(a.pos)+.00001>=3^2,'left/right simultaneous attacks choose third direction, preserving primary dodge distance')
now=.1;local same=M.Choose(s,Vector3(-.5,0,0),b)
assert(same==first,'switching primary attacker cannot reverse a still-safe short route')
local rook=ent('rook',-6,first.z*.5);rook.anim='atk';s.enemies={a,b,rook};s.data[rook]={atkanim='atk'}
now=.15;local changed=M.Choose(s,Vector3(-.5,0,0),b)
assert(changed and changed~=first and changed.z*first.z<0,'new side charge across committed path immediately invalidates and reverses it when required')
local lane=require('shadowself/control/incoming').Lane(s.c,rook)
local laneInitial=require('shadowself/control/incoming').Risk(lane,p.pos)
for i=1,8 do local q=Vector3(changed.x*i/8,0,changed.z*i/8)
 assert(require('shadowself/control/incoming').Risk(lane,q)<=laneInitial+.01,'replacement route never goes deeper into swept rook lane')
end
assert(require('shadowself/control/incoming').Risk(lane,changed)==0,'replacement ends outside swept rook lane')
s.enemies={a,b};s.data[rook]=nil;s.crowd_commit=nil;a.pos=Vector3(-1.5,0,0);b.pos=Vector3(1.5,0,0)
local escape=M.Choose(s,Vector3(1,0,0),a)
assert(escape and escape:DistSq(p.pos)>1,'overlapping attack circles can escape toward lower combined risk instead of returning current position')
s.crowd_commit=nil;s.hazards={{pos=Vector3(0,0,3),radius=2}}
local dry=M.Choose(s,Vector3(1,0,0),a)
assert(dry and dry.z<0 and dry.x<5,'joint route avoids hazard cloud and coastline while escaping pincer')
-- 躲避收尾若另一只仍在实际攻击，不能先切回主教发起追击。
local knight=ent('knight',1,0);local bishop=ent('bishop',4,0)
local c={player=p,plan={arena=true},h={ent=a},enemies={},hazards={},actions={}}
c.bridge={priority_target=bishop,allowed=function() return true end,wrappers={PreTheLoop={old=function() end}}}
local secondary=require('shadowself/control/secondary')(c)
secondary.Danger=function() return knight end
assert(secondary:AfterDodge(a)==knight and c.h.ent==knight,'remaining attack takes precedence over immediate bishop chase')
secondary.Danger=function() return nil end
assert(secondary:AfterDodge(knight)==bishop,'bishop priority returns once remaining attack ends')
GetTime=oldTime;TheWorld=oldWorld
print('PASS: real joint pincer escape, stable path across primary changes, immediate new rook-lane invalidation, overlapping-circle release, hazard/coast avoidance and safe bishop reentry')
