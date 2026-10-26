local saved={world=TheWorld,sim=TheSim,time=GetTime,net=TheNet}
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end}}
local function entity(name,x,z,r)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),radius=r or .5,frame=0,rotation=0,anim='idle',tags={},replica={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius end
 e.AnimState={IsCurrentAnimation=function(_,n) return n==e.anim end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return e.rotation end};return e
end
local p=entity('wilson',1.6);local shark=entity('sharkboi',0,0,1)
local c={player=p,enemies={shark},hazards={},actions={SafePoint=function() return true end}}
local R=require('shadowself/control/sharkroute')
local function move(q,speed)
 local dx,dz=q.x-p.pos.x,q.z-p.pos.z;local d=math.sqrt(dx*dx+dz*dz)
 if d>0 then local step=math.min(d,speed/30);p.pos=Vector3(p.pos.x+dx/d*step,0,p.pos.z+dz/d*step) end
end
for _,speed in ipairs({6,7.5}) do for _,delay in ipairs({2,4}) do
 c.shark_swipe=nil;c.shark_attack_window=nil;c.shark_recovery=nil
 p.pos=Vector3(1.6,0,0);shark.anim='atk1';shark.rotation=0
 for f=0,40 do
  shark.frame=f
  local data=R.Dodge(c,shark,false)
  if data and f>=delay then move(data:fn(),speed) end
  if f==16 then assert(not ((p.pos.x-2)^2+p.pos.z^2<4^2 and p.pos.x>.25),'actual swipe damage clearance at speed '..speed..' delay '..delay) end
 end
 assert(R.Rear(c,shark) and not R.Dodge(c,shark,false),'orbit continues past the hit frame until the actual rear is reached')
end end
for _,speed in ipairs({6,7.5}) do for _,delay in ipairs({2,4}) do
 c.shark_torpedo=nil;c.shark_recovery=nil;c.shark_attack_window=nil
 shark.anim='torpedo_pre';shark.rotation=0;p.pos=Vector3(1.6,0,0)
 for f=0,30 do
  shark.frame=f;local data=R.Dodge(c,shark,false)
  if data and f>=delay then move(data:fn(),speed) end
  -- SGsharkboi torpedo_pre follows target at at most two degrees per update.
  local wanted=-math.atan2(p.pos.z,p.pos.x)*180/math.pi
  local delta=(wanted-shark.rotation+180)%360-180
  if math.abs(delta)<90 then shark.rotation=shark.rotation+math.max(-2,math.min(2,delta/2)) end
 end
 local rot=shark.rotation*math.pi/180
 local along=p.pos.x*math.cos(rot)-p.pos.z*math.sin(rot)
 local side=math.abs(p.pos.x*math.sin(rot)+p.pos.z*math.cos(rot))
 assert(p.pos:DistSq(shark.pos)>=3^2,'torpedo jump actual 2.5 plus player radius clearance')
 assert(side>=3.5 or along<=-3.5,'torpedo sliding actual three-unit radius plus player clearance')
 shark.anim='torpedo_loop';R.Dodge(c,shark,false)
 shark.anim='torpedo_pst';assert(R.Committed(c,shark) and not R.Dodge(c,shark,{}),'after sliding keep attacking without extra movement')
 shark.anim='atk1';shark.frame=0;shark.rotation=-math.atan2(p.pos.z,p.pos.x)*180/math.pi
 assert(not R.Committed(c,shark) and R.Dodge(c,shark,false),'the next real attack immediately restores dodge priority')
end end
-- Return from the opposite shore must take the outer brick ring, never cross open water.
local Return=require('shadowself/control/arena_return');local goal=Vector3(20,0,0)
TheWorld.Map.IsOceanAtPoint=function(_,x,_,z) return math.abs(x)<18 and math.abs(z)<18 end
TheWorld.Map.IsPassableAtPoint=function(_,x,_,z) return not (math.abs(x)<18 and math.abs(z)<18) end
TheWorld.Map.GetTileAtPoint=function() return 0 end
p.pos=Vector3(-20,0,0)
assert(not Return.Clear(p.pos,goal),'straight home route crosses the water and must be rejected')
for i=1,12 do
 local q=Return.Point(p,goal,Vector3(0,0,0))
 assert(q and Return.Clear(p.pos,q),'each actual return leg remains on verified land')
 p.pos=q;if p.pos:DistSq(goal)<.01 then break end
end
assert(p.pos:DistSq(goal)<.01,'perimeter route reaches the original entry shore')
-- Torch strikes require actual contact, not the former normal weapon range.
local oldA=package.loaded['shadowself/control/actions'];local oldSnails=package.loaded['shadowself/control/arena_snails']
local oldNav=package.loaded['shadowself/control/navigation'];local strikes=0;local moveGoal
package.loaded['shadowself/control/actions']={Stop=function() end,Attack=function(_,_,guard) assert(guard());strikes=strikes+1;return true end}
package.loaded['shadowself/control/navigation']={Safe=function() return true end}
package.loaded['shadowself/control/arena_snails']=nil
local Snails=require('shadowself/control/arena_snails');local snail=entity('snurtle',2);local torch=entity('torch')
p.pos=Vector3(0,0,0);p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetEquippedItem=function() return torch end}
local sc={player=p,enemies={snail},bridge={PauseAttack=function() end,allowed=function() return true end},mechanisms={Equip=function() return true end}}
p.replica.combat={GetAttackRangeWithWeapon=function() return 2 end};sc.Move=function(_,q) moveGoal=q end
local sb={c=sc,Item=function() return torch end,Release=function() end,Move=function(_,q) moveGoal=q;return 'move' end}
assert(Snails.Tick(sb,snail)=='move' and strikes==0,'old torch range cannot trigger an early strike')
p.pos=moveGoal;assert(Snails.Tick(sb,snail)=='support' and strikes==1,'closest contact position permits the normal torch attack')
package.loaded['shadowself/control/actions']=oldA;package.loaded['shadowself/control/arena_snails']=oldSnails
package.loaded['shadowself/control/navigation']=oldNav
TheWorld,TheSim,GetTime,TheNet=saved.world,saved.sim,saved.time,saved.net
print('PASS: shark rear completion and actual swipe/turning-torpedo geometry at tested speed and delay; post-slide output releases on next windup')
