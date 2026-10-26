local oldTime,oldSim,oldWorld=GetTime,TheSim,TheWorld
local now=0;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
local function ent(name,x,z)
 local e={prefab=name,pos=Vector3(x or 0,0,z or 0),replica={},tags={}}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return .5 end
 return e
end
local p=ent('wilson');p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={GetEquippedItem=function() end,GetNumSlots=function() return 15 end,GetItemInSlot=function() end}
local entities={};TheSim={FindEntities=function() return entities end}
local key='shadowself/control/actions';local oldA=package.loaded[key];local sent={};local goal;local moves=0
package.loaded[key]={Items=function() return {} end,Stop=function() end,
 Scene=function(_,box,action,guard) assert(action==ACTIONS.RUMMAGE);sent[#sent+1]={box=box,guard=guard};return true end}
local Rewards=assert(loadfile('scripts/shadowself/control/arena_rewards.lua'))()
local Route=require('shadowself/control/arena_reward_route')
local arena={player=p,running=true,wave=11,instance='route093',generation=1,bridge={},StopCombat=function() end,Say=function() end,
 encounters={FindCenter=function() return Vector3(0,0,0) end,Move=function(_,q) goal=q;moves=moves+1 end}}
local stage={player=p,arena=arena,context={player=p,enemies={},hazards={},actions={SafePoint=function() return true end},
 plan={arena=true,arena_center=function() return Vector3(0,0,0) end}}};arena.stage11=stage
local boxes={}
for _,v in ipairs({{-15,-15},{15,-15},{15,15},{-15,15}}) do
 local box=ent('chest_mimic',v[1],v[2]);box.open=false
 box.replica.container={IsOpenedBy=function() return box.open end,Close=function() box.open=false end,GetItems=function() return {} end,IsEmpty=function() return true end}
 boxes[#boxes+1]=box
end
local pig=ent('daywalker',5);entities={pig};for _,box in ipairs(boxes) do entities[#entities+1]=box end
local reward=Rewards(stage,false)
assert(not reward:Tick(entities) and reward.reward_route.patrol and #sent==0 and moves>0,'six-unit live monster starts perimeter ownership rather than opening any box')
now=3;reward:Tick(entities);assert(reward.reward_route.elapsed==0,'stationary time does not become seven seconds of patrol')
p.pos=Vector3(18,0,-18);now=3.1;reward:Tick(entities)
for i=1,13 do now=now+.5;p.pos=goal;reward:Tick(entities);assert(#sent==0,'patrol cannot end before seven observed moving seconds') end
now=now+.5;p.pos=goal
local farthest,dist
for _,box in ipairs(boxes) do local d=p.pos:DistSq(box.pos);if not dist or d>dist then farthest,dist=box,d end end
reward:Tick(entities)
assert(#sent==1 and sent[1].box==farthest and reward.opened==farthest,'after patrol real RUMMAGE dispatch selects farthest unvisited box')
local stale=sent[1].guard
assert(stale(),'clear delayed opening retains matching wave/generation/route ownership')
pig.pos=Vector3(p.pos.x+5,0,p.pos.z)
assert(not stale() and reward.reward_route.patrol,'new monster arriving before dispatch cancels preview and starts another patrol')
assert(#sent==1,'cancellation cannot send a second opening action')
reward:Stop();assert(not stale() and not reward.reward_route,'stop releases patrol and invalidates all delayed opening requests')
local body=ent('worm_boss_segment',p.pos.x,p.pos.z)
local tail=ent('worm_boss_tail',p.pos.x,p.pos.z);local dirt=ent('worm_boss_dirt',p.pos.x,p.pos.z)
assert(not Route.Near(reward,{body,tail,dirt}),'body, tail and dirt never count as the six-unit monster trigger')
local head=ent('worm_boss_head',p.pos.x+6,p.pos.z)
assert(Route.Near(reward,{head}),'visible worm head at exactly six counts');head.tags.dead=true
assert(not Route.Near(reward,{head}),'confirmed dead head cannot trigger another patrol')
p.pos=Vector3(-10,0,0);local target=boxes[1];target.pos=Vector3(10,0,0);body.pos=Vector3(0,0,0)
local fresh=Rewards(stage,true)
assert(Route.Segment(fresh,{body},target) and Route.Before(fresh,{body},target) and fresh.reward_route.patrol,'body scrape intersecting approach cancels the attempt even without a counted monster')
body.pos=Vector3(0,0,15)
assert(not Route.Segment(fresh,{body},target),'distant body does not falsely veto a clear approach')
fresh:Stop();fresh.opened=target;target.open=true;body.pos=Vector3(9,0,0);fresh.pending={kind='unconfirmed_transfer'}
Route.Begin(fresh,'test')
assert(not target.open and fresh.pending and fresh.reward_route.patrol,'aborting an opened dangerous box closes it while retaining outstanding inventory confirmation')
fresh:Stop();arena.healing={Safe=function() return false end,Path=function() return true end}
local unsafe=Rewards(stage,false);unsafe:Tick({target})
assert(unsafe.reward_route and unsafe.reward_route.patrol,'existing path-safety failure joins the same outer patrol instead of the old lunar junk-pile patrol')
package.loaded[key]=oldA;GetTime,TheSim,TheWorld=oldTime,oldSim,oldWorld
print('PASS: actual reward entry six-unit gate, movement-only seven-second patrol, farthest-box RUMMAGE, late threat guard, stop release, worm head/body distinction and independent body scrape cancellation')
