local oldActions=package.loaded['shadowself/control/actions']
local oldTime=GetTime;local now=0;GetTime=function() return now end
local function ent(name)
 local e={prefab=name,replica={},tags={}}
 function e:IsValid() return true end;function e:HasTag(t) return self.tags[t] end
 return e
end
local p=ent('wilson');local armor=ent('armorskeleton');local bag={}
p.components={playercontroller={IsBusy=function() return false end}}
p.replica.inventory={}
local arena={player=p,running=true,wave=10,instance='078'}
local realActions=assert(loadfile('scripts/shadowself/control/actions.lua'))()
package.loaded['shadowself/control/actions']={Items=function() return bag end}
-- 实际公共移动入口：第11关开始切杖，继续走，不因装备网络往返站住。
local cane=ent('cane');bag={cane};local hand=armor;local events={}
local mocked=package.loaded['shadowself/control/actions']
mocked.Self=function(_,item,action) assert(item==cane and action==ACTIONS.EQUIP);events[#events+1]='equip';return true end
p.replica.inventory.GetEquippedItem=function() return hand end
p.components.playercontroller.locomotor={GoToPoint=function(_,point) events[#events+1]='walk' end}
p._shadowself_arena_move_owner=arena;arena.wave=10
realActions.Move(p,Vector3(1,0,0));assert(#events==1 and events[1]=='walk','earlier waves keep movement equipment policy')
arena.wave=11;events={};now=now+.1;realActions.Move(p,Vector3(2,0,0))
assert(events[1]=='equip' and events[2]=='walk','late movement requests cane then immediately continues walking')
now=now+.1;realActions.Move(p,Vector3(3,0,0));assert(#events==3 and events[3]=='walk','pending cane equip is throttled without blocking the next movement')
arena.running=false;now=3;events={};realActions.Move(p,Vector3(4,0,0));assert(#events==1 and events[1]=='walk','stopping arena disables late movement equipment hook')
p._shadowself_arena_move_owner=nil
package.loaded['shadowself/control/actions']=oldActions;GetTime=oldTime
print('PASS: late movement still equips cane without blocking travel and releases on arena stop')
