local saved={time=GetTime,sim=TheSim,start=StartThread,sleep=Sleep,kill=KillThreadsWithID,mods=rawget(_G,'ModManager')}
local ak,bk='shadowself/control/actions','shadowself/control/arena_bone_maintenance'
local oldA,oldB=package.loaded[ak],package.loaded[bk];package.loaded[bk]=nil
local now=0;GetTime=function() return now end;TheSim={FindEntities=function() return {} end}
local function item(name,id,value)
 local e={prefab=name,GUID=id,value=value,tags={},replica={}}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] or false end
 e.replica.inventoryitem={classified={percentused={value=function() return math.floor(e.value*100+.001) end}}}
 return e
end
local p=item('wilson',1,1);p.entity={};function p:GetPosition() return Vector3(0,0,0) end
local armor,other,fuel=item('armorskeleton',2,.25),item('armorskeleton',3,.9),item('nightmarefuel',4,1)
fuel.tags.INLIMBO=true -- 真实库存中的燃料带此标签，仍必须被枚举和使用。
local bag={armor,fuel};local body=armor;local busy=false;local active
p.components={playercontroller={IsBusy=function() return busy end}}
p.replica.inventory={GetEquippedItem=function() return body end,GetActiveItem=function() return active end}
local calls,equips,starts,kills=0,0,0,0;local valid;local sent
package.loaded[ak]={Items=function() return bag end,RefuelArmor=function(_,f,a,guard)
 assert(f==fuel and a==body and guard());calls=calls+1;valid=guard;return true end,
 Self=function(_,e,act) assert(act==ACTIONS.EQUIP);equips=equips+1;sent=e;return true end}
StartThread=function(fn) starts=starts+1;local co=coroutine.create(fn);assert(coroutine.resume(co));return {co=co,id=starts,SetList=function() end} end
Sleep=function(dt) assert(dt==.2);coroutine.yield() end
KillThreadsWithID=function() kills=kills+1 end
ModManager={GetMod=function() end}
local B=require('shadowself/control/arena_bone_maintenance')
local arena={player=p,running=true,wave=10,instance='test',generation=1,bridge={Running=function() return false end}}
p._shadowself_arena_move_owner=arena
B.Sync(arena);assert(starts==0,'waves1-10 do not run this maintenance thread')
arena.wave=11;B.Sync(arena);assert(starts==1 and calls==1 and B.Busy(p),'<=25 requests one fuel in its own thread')
local s=arena.bone_maintenance;B.Sync(arena);assert(starts==1,'only one thread per arena')
now=.2;B.Tick(arena);assert(calls==1,'request accepted is not acknowledgement and cannot duplicate')
armor.value=.5;now=.4;B.Tick(arena);assert(not B.Busy(p) and calls==1,'actual durability increase acknowledges one fuel')
armor.value=.25;now=1;busy=true;B.Tick(arena);assert(calls==1,'server rejects busy inventory actions, so defer rather than interrupt')
busy=false;active=fuel;B.Tick(arena);assert(calls==1,'manual active item keeps ownership')
active=nil;p.tags.attack=true;B.Tick(arena);assert(calls==1,'do not cancel an existing attack')
p.tags.attack=nil;p.tags.moving=true;B.Tick(arena);assert(calls==2,'patrol movement alone cannot starve maintenance forever')
busy=true;assert(valid(),'own predicted short-action busy state must not cancel its delayed RPC')
busy=false;p.tags.moving=nil
armor.value=.5;now=1.3;B.Tick(arena);armor.value=0;now=2;B.Tick(arena);assert(calls==3)
armor.value=.25;now=2.3;B.Tick(arena);now=3;B.Tick(arena)
assert(calls==3,'0-to25 repair counts as one use, no loop to80 at same threshold')
-- 外部Mod存在时禁止本线程发出补燃料或切甲动作；取甲认可当前装备。
ModManager.GetMod=function(_,n) assert(n=='workshop-2129374112');return {} end
armor.value=.1;now=4;B.Tick(arena);assert(calls==3 and not B.Busy(p))
bag={other,armor,fuel};B.Tick(arena);assert(B.Select(p,other)==armor,'internal by-name equip does not fight external bone rotation')
body=other;assert(B.Select(p,armor)==other)
-- 外部离开后冷却/耐久排序，切换请求必须等待装备确认。
ModManager.GetMod=function() end;body=armor;now=10;B.Tick(arena)
assert(equips==1 and sent==other and B.Busy(p));now=10.2;B.Tick(arena);assert(equips==1)
body=other;now=10.4;B.Tick(arena);assert(not B.Busy(p))
-- 开关关闭只关闭加燃料；不会靠不存在的数值修复或重复空请求。
p._shadowself={options={bone_refuel=-1}};bag={other,fuel};other.value=.1;now=11;B.Tick(arena);assert(calls==3)
p._shadowself.options.bone_refuel=25;other.value=2.55;now=12;B.Tick(arena);assert(calls==3,'255 is unknown durability')
other.value=.2;bag={other};now=13;B.Tick(arena);assert(calls==3,'missing fuel makes no request')
bag={other,fuel};B.Tick(arena);assert(calls==4 and valid());local stale=valid
bag={other};assert(not valid(),'delayed repair cannot use dropped fuel');bag={other,fuel}
ModManager.GetMod=function() return {} end;assert(not valid(),'external owner invalidates an in-flight preview immediately');ModManager.GetMod=function() end
arena.generation=2;assert(not valid(),'generation changes invalidate the previous repair');arena.generation=1
B.Stop(arena);assert(kills==1 and not stale() and not B.Busy(p),'stop kills own thread and invalidates delayed actions immediately')
B.Sync(arena);local count=starts;arena.wave=10;B.Sync(arena);assert(not arena.bone_maintenance and kills==2 and starts==count)
-- 真实原版动作封装，预演/非预演与停止后回调保护。
local realA=assert(loadfile('scripts/shadowself/control/actions.lua'))()
local oldRPC,oldSend,oldFuel,oldWet=RPC,SendRPCToServer,ACTIONS.ADDFUEL,ACTIONS.ADDWETFUEL
ACTIONS.ADDFUEL={code=8301};ACTIONS.ADDWETFUEL={code=8302};RPC={ControllerUseItemOnItemFromInvTile=8303}
local allow=true;local preview;local sends=0
SendRPCToServer=function(r,code,a,f) assert(r==8303 and code==8301 and a==other and f==fuel);sends=sends+1 end
p.components.playeractionpicker={GetUseItemActions=function() return {{action=ACTIONS.ADDFUEL}} end}
p.components.playercontroller.CanLocomote=function() return true end
p.components.playercontroller.locomotor={PreviewAction=function(_,a) preview=a.preview_cb end}
assert(realA.RefuelArmor(p,fuel,other,function() return allow end) and sends==0)
allow=false;preview();assert(sends==0);allow=true
now=now+.5;assert(realA.RefuelArmor(p,fuel,other,function() return allow end));preview();assert(sends==1)
now=now+.5;p.components.playercontroller.locomotor=nil;assert(realA.RefuelArmor(p,fuel,other,function() return true end) and sends==2)
RPC,SendRPCToServer,ACTIONS.ADDFUEL,ACTIONS.ADDWETFUEL=oldRPC,oldSend,oldFuel,oldWet
package.loaded[ak],package.loaded[bk]=oldA,oldB
GetTime,TheSim,StartThread,Sleep,KillThreadsWithID,ModManager=saved.time,saved.sim,saved.start,saved.sleep,saved.kill,saved.mods
print('PASS: dedicated single bone thread, <=25 single fuel and real ACK, 0-to25 no loop, busy/manual/attack ownership, external-Mod delegation, cooldown-based armor rotation and immediate stop/network preview cancellation')
