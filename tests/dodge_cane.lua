-- Actual installed 3014 DoDodge + travel event lifecycle, simulated equipment.
local saved={time=GetTime,vec=Vector3,world=TheWorld}
local now=10;GetTime=function() return now end
Vector3=function(x,y,z) local q={x=x,y=y,z=z};function q:DistSq(v) return (self.x-v.x)^2+(self.z-v.z)^2 end;return q end
TheWorld={state={isnight=false}}
local busy=true;local hand="weapon";local equips={};local moves=0;local frames=0;local attacks=0
local p={pos=Vector3(0,0,0),components={playercontroller={IsBusy=function() return busy end}}}
function p:IsValid() return true end
function p:GetPosition() return self.pos end
function p:HasTag(tag) return tag=="busy" and busy end
local gear={Weapon=function() return {} end,Swap=function(_,role)
 local wanted=role=="move" and "cane" or "weapon"
 if hand~=wanted then hand=wanted;equips[#equips+1]=wanted end
 return true
end}
local Travel=require("shadowself/control/travel");local travel=Travel(p,gear)
function p:PushEvent(name,data)
 assert(name=="EquipItem")
 if data.type=="walk_hands" then travel:BeginDodge()
 elseif data.type=="fight" then travel:EndDodge() end
end
local foe={anim="atk",GetPosition=function() return Vector3(3,0,0) end}
local data={point="target",dist=6,fn=function() return Vector3(-3,0,0) end}
local h={ent=foe,pos=foe:GetPosition(),ppos=p.pos,
 ShouldAtkWhenDodging=function() return false end,CancelDodgingAtk=function() end,
 CloseAndAttack=function() assert(hand=="weapon");attacks=attacks+1 end}
h.IsAttackPre=function() travel:UpdateDodge();return foe.anim=="atk" and data or nil end
local env=setmetatable({GLOBAL={DEGREES=math.pi/180},HitAndRun=h,ThePlayer=p,FRAMES=1/30,
 FunctionOrValue=function(v,...) return type(v)=="function" and v(...) or v end,
 distsq=function(a,b) return a:DistSq(b) end,
 POS_util={GoToPoint=function() moves=moves+1 end},
 Sleep=function()
  frames=frames+1;now=now+1/30
  if frames==2 then busy=false end
  if frames==8 then foe.anim="idle" end
 end},{__index=_G})
local raw=read_3014_dodge();local cut=assert(raw:find("\n\tlocal initidlelist",1,true))
local chunk=assert(loadstring(raw:sub(1,cut-1).."\nend"));setfenv(chunk,env);chunk()
h:DoDodge(data)
assert(moves==8 and attacks==1,"equip retries never stop any of the native dodge frames")
assert(#equips==2 and equips[1]=="cane" and equips[2]=="weapon","exactly one cane entry and one weapon restoration")
assert(not travel.dodging and not travel.restore_dodge)
local count=#equips;p:PushEvent("EquipItem",{type="fight"});assert(#equips==count,"ordinary fight events never repeatedly switch hands")
GetTime,Vector3,TheWorld=saved.time,saved.vec,saved.world
print("PASS: real 3014 dodge events equip cane after initial busy, preserve all 8 movement frames, restore weapon once before follow-up")
