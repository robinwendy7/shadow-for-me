-- 第三关怪物实刷后单次开场催眠；主教优先只改变攻击目标，不替代原生躲避。
local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local O=Class(function(self,arena) self.arena=arena end)
function O:Reset() self.sent=nil;self.done=nil;self.attempts=0;self.played=nil;self.next_try=nil;self.arena.bridge.priority_target=nil end
function O:Tick(enemies)
 local arena=self.arena
 if arena.wave~=3 then return false end
 local p=arena.player;local bishop,distance
 for _,e in ipairs(enemies) do
  if e.prefab=="bishop" or e.prefab=="bishop_nightmare" then
   local d=p:GetPosition():DistSq(e:GetPosition())
   if not distance or d<distance then bishop,distance=e,d end
  end
 end
 arena.bridge.priority_target=bishop
 if not bishop or self.done then return false end
 local now=GetTime();local pc=p.components.playercontroller
 if self.sent then
  local a=p.AnimState
  if a and a:IsCurrentAnimation("flute") then self.played=true end
  if Status.Sleeping(bishop) or self.played and now-self.sent>=1.8 then
   if now-self.sent<1.85 or pc:IsBusy() then return true end
   self.done=true;self.sent=nil
   return false
  end
  if now-self.sent<3.5 then return true end
  self.sent=nil;self.next_try=now+.5
  if self.attempts>=2 then self.done=true;return false end
 end
 local flute
 for _,item in ipairs(A.Items(p)) do if item.prefab=="panflute" and item:IsValid() and not item:HasTag("broken") then flute=item;break end end
 if not flute then self.done=true;return false end
 if pc:IsBusy() or now<(self.next_try or 0) then return true end
 local range=TUNING.PANFLUTE_SLEEPRANGE or 15
 if distance>(range-1)^2 then
  -- 暂用原生追击接近主教，下次脉冲在催眠范围内再开场，不能朝陷阱/火焰盲走。
  return false
 end
 arena:StopCombat();A.Stop(p);arena.pending_item=nil
 if A.Self(p,flute,ACTIONS.PLAY) then self.sent=now;self.attempts=(self.attempts or 0)+1
 else self.next_try=now+.5;self.attempts=(self.attempts or 0)+1;if self.attempts>=2 then self.done=true end end
 return not self.done
end
return O
