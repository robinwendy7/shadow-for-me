local saved={time=GetTime,world=TheWorld,sim=TheSim}
local nk='shadowself/control/navigation';local oldNav=package.loaded[nk]
package.loaded[nk]={Safe=function() return true end,Select=function(_,q) return q end}
local now=100;GetTime=function() return now end
TheWorld={Map={IsPassableAtPoint=function() return true end,IsOceanAtPoint=function() return false end},Pathfinder={IsClear=function() return true end}}
local function ent(name,x,z,r)
 local e={prefab=name,GUID=math.random(100000),pos=Vector3(x or 0,0,z or 0),radius=r or .5,anim='idle',frame=0,tags={},replica={}}
 function e:IsValid() return not self.removed end;function e:HasTag(t) return self.tags[t] or false end
 function e:GetPosition() return self.pos end;function e:GetPhysicsRadius() return self.radius end
 e.AnimState={IsCurrentAnimation=function(_,a) return e.anim==a end,GetCurrentAnimationFrame=function() return e.frame end}
 e.Transform={GetRotation=function() return 0 end};return e
end
local Shark=assert(loadfile('scripts/shadowself/control/sharkroute.lua'))()
local p,shark=ent('wilson',-2,0),ent('sharkboi')
local c={player=p,plan={arena=true,arena_wave=function() return 7 end}}
for _,v in ipairs({{'atk1',22},{'atk2',10},{'atk3',18}}) do
 now=now+10;local start=now;shark.anim=v[1];shark.frame=0
 assert(Shark.SwipeHold(c,shark))
 shark.frame=v[2]+1;now=start+shark.frame/30
 assert(Shark.SwipeHold(c,shark),'old release frame is still inside doubled window')
 shark.anim=v[1]..'_pst';shark.frame=0
 assert(Shark.SwipeHold(c,shark),'animation transition cannot discard remaining dodge time')
 now=start+v[2]*2/30+.001
 assert(not Shark.SwipeHold(c,shark),'release after exactly twice the original window')
end
shark.anim='atk1';shark.frame=0;assert(Shark.SwipeHold(c,shark))
shark.anim='torpedo_pre';assert(not Shark.SwipeHold(c,shark),'new charge owns its distinct dodge path')
c.plan.arena_wave=function() return 6 end;shark.anim='atk1';assert(not Shark.SwipeHold(c,shark))

-- 真实Guardian入口：两种障碍、绕行、到达后攻击、醒来即交回返柱流程。
local Route=assert(loadfile('scripts/shadowself/control/guardianattack.lua'))()
local routeKey='shadowself/control/guardianattack';local oldRoute=package.loaded[routeKey];package.loaded[routeKey]=Route
local Guardian=assert(loadfile('scripts/shadowself/control/guardian.lua'))()
p.pos=Vector3(0,0,0)
local king=ent('minotaur',8,0);king.anim='stun_loop'
local pillar=ent('pillar_ruins',3,0,1);pillar.tags.charge_barrier=true
local wall=ent('wall_stone',5,-1.6,.6);wall.tags.wall=true
TheSim={FindEntities=function() return {pillar,wall} end}
local goal,moves
c={player=p,plan={arena=true,arena_wave=function() return 9 end},gear={AttackRange=function() return 2 end},
 bridge={PauseAttack=function() end},travel={},enemies={},hazards={},actions={Stop=function() end,SafePoint=function() return true end}}
local boss={c=c,routes={Leap=function() return false end},Release=function() end,
 Move=function(_,q,_,_,verified) assert(verified);goal=q;return 'move' end};c.bosses=boss
local reached=false
for i=1,80 do
 local before=p.pos;local mode=Guardian.Tick(boss,king)
 if mode=='attack' then reached=true;break end
 assert(mode=='move','reachable blocked attack route must make progress: step='..i..' pos='..p.pos.x..','..p.pos.z)
 for _,o in ipairs({pillar,wall}) do
  for j=0,20 do local q=Vector3(before.x+(goal.x-before.x)*j/20,0,before.z+(goal.z-before.z)*j/20)
   assert(q:DistSq(o.pos)>(o.radius+p.radius+.2)^2,'route never clips obstruction')
  end
 end
 p.pos=goal;now=now+.05
end
assert(reached,'clear return route hands approach back to the normal attack distance checks')
king.anim='idle';Guardian.Tick(boss,king);assert(not boss.guardian.attack_path,'wake ends attack-route ownership')
package.loaded[routeKey]=oldRoute

-- 使用真实Inventory及Gear，验证影刀优于铥棒且补捡入口在既有战斗中仍运行。
local ak,ik='shadowself/control/actions','shadowself/control/arena_inventory'
local oldA,oldI=package.loaded[ak],package.loaded[ik]
local bat,sword=ent('ruins_bat'),ent('nightsword',2,0)
for _,e in ipairs({bat,sword}) do e.tags.weapon=true;e.replica.equippable={EquipSlot=function() return EQUIPSLOTS.HANDS end} end
local held=false;sword.replica.inventoryitem={IsHeld=function() return held end}
p.replica.inventory={GetEquippedItem=function(_,slot) return slot==EQUIPSLOTS.HANDS and bat end}
p.components={playercontroller={IsBusy=function() return false end}}
local bag={bat};package.loaded[ak]={Items=function() return bag end,Stop=function() end}
package.loaded[ik]=nil;local Inv=require(ik)
assert(Inv.Want(sword,bag,p,10) and Inv.Physical(sword)>Inv.Physical(bat),'the score does not reject the stronger sword')
local Supply=assert(loadfile('scripts/shadowself/control/arena_supply.lua'))()
local safe=true;local requests=0;local guard
local arena={wave=10,instance='test',generation=1,running=true,player=p,items={sword},rest_actions={},
 bridge={Running=function() return true end},healing={Safe=function() return safe end,Path=function() return safe end}}
function arena:NearbyEnemies() return {} end;function arena:StopCombat() end;function arena:Say() end
function arena:Loot(items,_,check)
 if held then self.pending_item=nil;return false end
 assert(items[1]==sword and check());guard=check;requests=requests+1;return true
end
assert(Supply.WeaponUpgrade(arena) and requests==1,'already-running combat no longer bypasses safe sword pickup')
safe=false;assert(not guard() and not Supply.WeaponUpgrade(arena),'danger invalidates delayed pickup')
safe=true;arena.wave=11;assert(Supply.WeaponUpgrade(arena),'wave11 retries missed wave10 sword')
arena.generation=2;assert(not guard(),'stale-generation request cannot execute')
held=true;bag={bat,sword};arena.pending_item=sword
assert(not Supply.WeaponUpgrade(arena) and not arena.pending_item,'actual inventory receipt releases pending pickup')
local Gear=require('shadowself/legacy/registry').CombatEquipment
local g=Gear({player=p,plan={arena=true,arena_wave=function() return 10 end},owner={perception={Inventory=function() return bag end}},enemies={},h={}})
assert(g:Weapon()==sword,'existing weapon selector equips the stronger sword after receipt')
arena.wave=9;assert(not Supply.WeaponUpgrade(arena),'do not extend new pickup behavior to earlier rounds')
package.loaded[ak],package.loaded[ik]=oldA,oldI
package.loaded[nk]=oldNav;GetTime,TheWorld,TheSim=saved.time,saved.world,saved.sim
print('PASS: doubled shark timing across recovery; real rhino blocked-return detour/output/wake; sword pickup during combat and wave11 retry/guard/receipt/real gear ranking')
