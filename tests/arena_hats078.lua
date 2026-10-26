local oldA=package.loaded['shadowself/control/actions'];local oldTime=GetTime
local now=0;GetTime=function() return now end
local bag,head,requests={},nil,{}
local function hat(id,percent)
 local e={prefab='wathgrithr_improvedhat',GUID=id,components={armor={GetPercent=function() return percent end}},replica={equippable={EquipSlot=function() return EQUIPSLOTS.HEAD end}}}
 function e:IsValid() return true end;function e:HasTag() return false end
 return e
end
local worn,spare,extra=hat(7801,1),hat(7802,.8),hat(7803,.9)
local p={components={playercontroller={IsBusy=function() return false end}},replica={inventory={}}}
p.replica.inventory.GetEquippedItem=function() return head end
p.replica.inventory.DropItemFromInvTile=function(_,item) requests[#requests+1]={kind='drop',item=item} end
package.loaded['shadowself/control/actions']={Items=function() return bag end,
 Self=function(_,item) requests[#requests+1]={kind='equip',item=item};return true end}
local Arena=assert(loadfile('scripts/shadowself/control/arena.lua'))()
local H=require('shadowself/control/arena_stage11_hats')
local arena=setmetatable({player=p,wave=11,ignored={},items={spare,extra}}, {__index=Arena})
function arena:StopCombat() end;function arena:Say() end
function arena:Loot(items)
 for _,e in ipairs(items) do if self:Want(e,bag) then requests[#requests+1]={kind='pick',item=e};return true end end
 return false
end
local s={arena=arena,player=p,route='lunar'};arena.stage11=s;bag={worn};head=worn
assert(not arena:Want(spare,bag),'ordinary duplicate/value filter rejects worse spare')
assert(H.Tick(s) and requests[1].kind=='pick' and requests[1].item==extra,'lunar opening overrides duplicate filter and picks best remaining ground helmet')
bag={worn,extra};assert(H.Tick(s) and requests[2].item==spare,'owned acknowledgement advances to another helmet, never loops on stale ground scan')
bag={worn,extra,spare};assert(not H.Tick(s),'all actual helmets in inventory releases opening pickup')
s.route='default';now=1
assert(H.Tick(s) and requests[#requests].kind=='drop' and requests[#requests].item~=worn,'normal route drops spare and preserves worn helmet')
bag={worn,spare};now=1.6;assert(H.Tick(s) and requests[#requests].item==spare)
bag={worn};now=2.2;assert(not H.Tick(s) and arena.ignored[spare.GUID]==math.huge and arena.ignored[extra.GUID]==math.huge,'normal route ignores dropped helmets for this wave')
head=nil;bag={worn};now=3;assert(H.Tick(s) and requests[#requests].kind=='equip','normal route waits for actual worn helmet before dropping spares')
head=worn;arena.wave=12;local before=#requests
assert(not H.Tick(s) and #requests==before and not arena.collect_stage11_hats,'helmet collection/drop policy is strictly wave11')
GetTime=oldTime;package.loaded['shadowself/control/actions']=oldA
print('PASS: wave11 lunar/shadow all spare Valkyrie helmets, actual ownership advancement; normal route keeps worn one, drops extras, suppresses re-pick and leaves other waves unchanged')
