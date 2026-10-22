local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local O=Class(function(self,arena) self.arena=arena end)
local clockwork={bishop=true,bishop_nightmare=true,knight=true,knight_nightmare=true,rook=true,rook_nightmare=true}
function O:Reset()
 self.target=nil;self.sent=nil;self.done=nil;self.attempts=0;self.next_try=nil;self.next_move=nil
 self.arena.bridge.priority_target=nil
end
function O:Coverage(roster,range)
 local p=self.arena.player:GetPosition();local x,z=0,0
 for _,e in ipairs(roster) do local q=e:GetPosition();x=x+q.x;z=z+q.z end
 local center=Vector3(x/#roster,0,z/#roster);local candidates={p,center}
 for _,r in ipairs({3,6,9}) do for i=0,15 do
  local a=i*math.pi/8;candidates[#candidates+1]=Vector3(center.x+math.cos(a)*r,0,center.z+math.sin(a)*r)
 end end
 local best,score;local map=TheWorld.Map
 for _,q in ipairs(candidates) do
  local covered=true
  for _,e in ipairs(roster) do if q:DistSq(e:GetPosition())>range^2 then covered=false;break end end
  if covered and map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and require("shadowself/control/arena_fire").Safe(self.arena.player,q,self.arena.fire_zones) then
   local d=p:DistSq(q);if not score or d<score then best,score=q,d end
  end
 end
 return best
end
function O:Tick(enemies)
 local arena=self.arena
 if arena.wave~=3 then return false end
 local p=arena.player;local bishop;local roster={}
 for _,e in ipairs(enemies) do
  if clockwork[e.prefab] then roster[#roster+1]=e end
  if e.prefab=="bishop" or e.prefab=="bishop_nightmare" then bishop=e end
 end
 self.target=bishop;arena.bridge.priority_target=bishop
 if not bishop or self.done then return false end
 local now=GetTime();local pc=p.components.playercontroller
 if self.sent then
  local asleep=#roster>=3
  for _,e in ipairs(roster) do asleep=asleep and Status.Sleeping(e) end
  if asleep and now-self.sent>=1.85 and not pc:IsBusy() then self.done=true;self.sent=nil;return false end
  if now-self.sent<3.5 or pc:IsBusy() then return true end
  self.sent=nil;self.next_try=now+.5
 end
 local flute
 for _,item in ipairs(A.Items(p)) do if item.prefab=="panflute" and item:IsValid() and not item:HasTag("broken") then flute=item;break end end
 if not flute then self.done=true;return false end
 -- 必须等三个实刷发条全部可见，不能只按主教距离吹响。
 if #roster<3 or pc:IsBusy() or now<(self.next_try or 0) then return true end
 local range=(TUNING.PANFLUTE_SLEEPRANGE or 15)-1;local covered=true
 for _,e in ipairs(roster) do if p:GetPosition():DistSq(e:GetPosition())>range^2 then covered=false;break end end
 arena:StopCombat();arena.pending_item=nil
 if not covered then
  local point=self:Coverage(roster,range)
  if point and now>=(self.next_move or 0) then A.Move(p,point);self.next_move=now+.2 end
  return true
 end
 A.Stop(p)
 if A.Self(p,flute,ACTIONS.PLAY) then self.sent=now;self.attempts=(self.attempts or 0)+1
 else self.next_try=now+.5 end
 return true
end
return O
