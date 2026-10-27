local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local O=Class(function(self,arena) self.arena=arena end)
local clockwork={bishop=true,bishop_nightmare=true,knight=true,knight_nightmare=true,rook=true,rook_nightmare=true}
local birds={smallbird=1,teenbird=2,tallbird=3}
local function live(e)
 local h=e.replica and e.replica.health
 return e:IsValid() and not e:HasTag("dead") and not e:HasTag("isdead") and not (h and h.IsDead and h:IsDead())
end
function O:Reset()
 self.target=nil;self.sent=nil;self.done=nil;self.rhythm=nil;self.bait=nil;self.attempts=0;self.next_try=nil;self.next_move=nil
 self.hunt=nil;self.spiders=nil;self.clockwork_bishop=nil;self.clockwork_bishop_dead=nil
 self.arena.bridge.priority_target=nil
end
function O:Cleanup(e)
 if self.arena.wave~=3 or not e or not live(e) or not ({rook=true,rook_nightmare=true,knight=true,knight_nightmare=true})[e.prefab] then return false end
 local b=self.clockwork_bishop;local h=b and b.replica and b.replica.health
 if b and b:IsValid() and (b:HasTag("dead") or b:HasTag("isdead") or h and h.IsDead and h:IsDead()) then self.clockwork_bishop_dead=true end
 if not self.clockwork_bishop_dead then return false end
 for _,other in ipairs(self.arena.enemies or {}) do
  if live(other) and not ({rook=true,rook_nightmare=true,knight=true,knight_nightmare=true})[other.prefab] then return false end
 end
 return true
end
function O:Bait(enemies)
 if self.done then return false end
 local arena=self.arena;local target
 for _,e in ipairs(enemies) do if live(e) and (e.prefab=="pigman" or e.prefab=="bunnyman") then target=e;break end end
 if not target then return false end
 -- 先让原拾取/换装流程拿到开局补给，再开始骗首攻。
 local armed=false
 for _,item in ipairs(A.Items(arena.player)) do if item:HasTag("weapon") then armed=true;break end end
 if not armed or arena.equip_due then return false end
 local p=arena.player:GetPosition();local ep=target:GetPosition()
 self.bait=self.bait or {target=target};local b=self.bait
 local atk=target.AnimState and target.AnimState:IsCurrentAnimation("atk")
 local frame=atk and target.AnimState:GetCurrentAnimationFrame() or 0
 if atk then b.seen=true end
 if b.seen and (not atk or frame>=13) and p:DistSq(ep)>=4^2 then self.done=true;return false end
 arena:StopCombat();arena.pending_item=nil
 local dx,dz=p.x-ep.x,p.z-ep.z;local d=math.sqrt(dx*dx+dz*dz)
 if d<.01 then dx,dz,d=1,0,1 end
 local combat=target.replica and target.replica.combat
 local range=combat and combat.GetAttackRangeWithWeapon and combat:GetAttackRangeWithWeapon() or 3
 local radius=b.seen and 4.5 or math.max(1.5,range-.2)
 local q=Vector3(ep.x+dx/d*radius,0,ep.z+dz/d*radius)
 if GetTime()>=(self.next_move or 0) and require("shadowself/control/arena_fire").Safe(arena.player,q,arena.fire_zones) then
  A.Move(arena.player,q);self.next_move=GetTime()+.1
 end
 return true
end
function O:SpiderScene()
 self.spiders=self.spiders or require("shadowself/control/arena_spiders")(self)
 return self.spiders
end
function O:Coverage(roster,range,valid)
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
  if covered and (not valid or valid(q)) and map:IsPassableAtPoint(q.x,0,q.z) and not map:IsOceanAtPoint(q.x,0,q.z)
   and require("shadowself/control/arena_fire").Safe(self.arena.player,q,self.arena.fire_zones) then
   local d=p:DistSq(q);if not score or d<score then best,score=q,d end
  end
 end
 return best
end
function O:Tick(enemies)
 local arena=self.arena
 if arena.wave==1 then return self:Bait(enemies) end
 if arena.wave~=3 and arena.wave~=2 then return false end
 if arena.wave==2 then
  self.hunt=self.hunt or require("shadowself/control/arena_walrus")(arena)
  local handled,hold=self.hunt:Tick(enemies,arena.entities)
  if handled then self.target=self.hunt.target;return hold end
  local spiders=self:SpiderScene()
  local active,waiting=spiders:Tick(enemies)
  if active then self.target=nil;arena.bridge.priority_target=nil;return waiting end
 end
 local birdwave=arena.wave==2
 local p=arena.player;local bishop;local roster={}
 for _,e in ipairs(enemies) do
  if live(e) then
   if birdwave and birds[e.prefab] or not birdwave and clockwork[e.prefab] then roster[#roster+1]=e end
   if birdwave then
    if birds[e.prefab] and (not bishop or birds[e.prefab]<birds[bishop.prefab]) then bishop=e end
   elseif e.prefab=="bishop" or e.prefab=="bishop_nightmare" then bishop=e end
  end
 end
 if not birdwave and bishop then self.clockwork_bishop=bishop end
 self.target=bishop;arena.bridge.priority_target=bishop
 if not bishop or self.done then return false end
 local now=GetTime();local pc=p.components.playercontroller
 if self.sent then
  local asleep=#roster>=3
  for _,e in ipairs(roster) do asleep=asleep and Status.Sleeping(e) end
  if asleep and now-self.sent>=1.85 and not pc:IsBusy() then
   self.done=true;self.sent=nil
   if not birdwave then self.rhythm=require("shadowself/control/arena_clockwork")(bishop) end
   return false
  end
  if now-self.sent<3.5 or pc:IsBusy() then return true end
  self.sent=nil;self.next_try=now+.5
  if birdwave then self.done=true;return false end -- 本关只提交一次PLAY，失败后交回正常战斗。
 end
 local flute
 for _,item in ipairs(A.Items(p)) do if item.prefab=="panflute" and require("shadowself/control/arena_tools").Usable(item) then flute=item;break end end
 if not flute then
  if birdwave then
   -- 第二关排箫本关才落地，不能在首次背包扫描为空时永久跳过开局。
   for _,item in ipairs(arena.items or {}) do if item.prefab=="panflute" and require("shadowself/control/arena_tools").Usable(item) then
    arena:StopCombat();arena:Loot({item});return true
   end end
  else self.done=true end
  return false
 end
 -- 必须等三个实刷发条全部可见，不能只按主教距离吹响。
 if #roster<3 or pc:IsBusy() or now<(self.next_try or 0) then return true end
 if birdwave then
  local present={};for _,e in ipairs(roster) do present[e.prefab]=true end
  if not (present.smallbird and present.teenbird and present.tallbird) then return true end
 end
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
