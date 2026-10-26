-- 第二关蛛蝠组：只按实际prefab触发；PLAY请求不是催眠确认。
local A=require("shadowself/control/actions")
local Status=require("shadowself/control/status")
local Tools=require("shadowself/control/arena_tools")
local Policy=require("shadowself/control/arena_policy")
local S=Class(function(self,opening) self.opening=opening;self.arena=opening.arena;self.roster={} end)
local special={spider_hider=true,spider_spitter=true}
local victims={spider=true,bat=true}
local function dead(e)
 local h=e.replica and e.replica.health
 return e:HasTag("dead") or e:HasTag("isdead") or h and h.IsDead and h:IsDead()
end
function S:Active()
 if self.arena.wave~=2 then return false end
 if self.active then return true end
 local spider,bat,extra=false,false,false
 for _,e in ipairs(self.arena.entities or self.arena.enemies or {}) do
  if e:IsValid() and not dead(e) then
   spider=spider or e.prefab=="spider";bat=bat or e.prefab=="bat";extra=extra or special[e.prefab]
  end
 end
 self.active=spider and bat and extra or false
 return self.active
end
function S:Allowed(e)
 return not self:Active() or self.ready and e~=nil and victims[e.prefab]==true or false
end
function S:Phase(phase)
 if self.phase==phase then return end
 self.phase=phase
 print("[ShadowSelf][spider_control] "..phase)
 if self.arena.Say then self.arena:Say("第二关蛛蝠 · "..phase) end
end
function S:Path(q)
 local p=self.arena.player:GetPosition();local map=TheWorld.Map
 local steps=math.max(2,math.ceil(math.sqrt(p:DistSq(q))/.5))
 for i=1,steps do
  local v=Vector3(p.x+(q.x-p.x)*i/steps,0,p.z+(q.z-p.z)*i/steps)
  if not map:IsPassableAtPoint(v.x,0,v.z) or map:IsOceanAtPoint(v.x,0,v.z)
   or map.IsPointNearHole and map:IsPointNearHole(v) then return false end
 end
 return not TheWorld.Pathfinder or TheWorld.Pathfinder:IsClear(p.x,0,p.z,q.x,0,q.z,{ignorecreep=true,ignorewalls=false})
end
function S:Tick(enemies)
 if not self:Active() then return false,false end
 if self.ready then return true,false end
 local arena=self.arena;local p=arena.player;local now=GetTime();local pc=p.components.playercontroller
 arena:StopCombat()
 -- 使用全部实体，包含未列入波次名单的蜘蛛巢子代和睡眠陷阱狗。
 local seen={};for _,e in ipairs(self.roster) do seen[e]=true end
 for _,list in ipairs({enemies or {},arena.entities or {}}) do for _,e in ipairs(list) do
  if e:IsValid() and not dead(e) and e.replica and e.replica.combat
   and (Policy.monsters[e.prefab] or special[e.prefab] or e:HasTag("astra_arena_monster")) and not seen[e] then
   self.roster[#self.roster+1]=e;seen[e]=true
  end
 end end
 local roster={};local asleep=true
 for _,e in ipairs(self.roster) do if not dead(e) then
  -- 卸载不等于死亡，不能把脱离扫描当作全体催眠成功。
  if not e:IsValid() then self:Phase("等待已记录怪物重新可见");return true,true end
  roster[#roster+1]=e;asleep=asleep and Status.Sleeping(e)
 end end
 if self.sent then
  if #roster>0 and asleep and now-self.sent>=1.85 and not pc:IsBusy() then
   self.ready=true;self.sent=nil;self:Phase("已确认全体催眠，仅攻击spider与bat");return true,false
  end
  if now-self.sent<3.5 or pc:IsBusy() then return true,true end
  self.sent=nil;self.next_try=now+.5;self:Phase("催眠未全部确认，重新校验覆盖")
 end
 local flute=Tools.Owned({player=p},"panflute")
 if not flute then
  for _,item in ipairs(arena.items or {}) do if item.prefab=="panflute" and Tools.Usable(item) then
   arena:Loot({item},false,function() return arena.running and arena.wave==2 and not self.ready and self.opening.spiders==self end)
   self:Phase("补捡可用排箫");return true,true
  end end
  self:Phase("缺少可用排箫，等待补给，不提前攻击");return true,true
 end
 if pc:IsBusy() or now<(self.next_try or 0) or #roster==0 then return true,true end
 arena.pending_item=nil
 local range=(TUNING.PANFLUTE_SLEEPRANGE or 15)-1
 local covered=true
 for _,e in ipairs(roster) do if p:GetPosition():DistSq(e:GetPosition())>range^2 then covered=false;break end end
 if not covered then
  local q=self.opening:Coverage(roster,range,function(v) return self:Path(v) end)
  if not q then self:Phase("暂无可覆盖全体的安全位置");return true,true end
  self:Phase("移动至全体怪物催眠覆盖点")
  if now>=(self.next_move or 0) then A.Move(p,q);self.next_move=now+.2 end
  return true,true
 end
 A.Stop(p)
 if A.Self(p,flute,ACTIONS.PLAY) then self.sent=now;self:Phase("已请求排箫，等待全体睡眠确认")
 else self.next_try=now+.5;self:Phase("排箫动作未接受") end
 return true,true
end
return S
