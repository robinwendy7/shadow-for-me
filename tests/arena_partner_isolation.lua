-- Actual Coordinator construction must not load or instantiate solo Boss owners for arena.
local keys={'shadowself/control/coordinator','shadowself/legacy/action_library','shadowself/legacy/combat_equipment',
 'shadowself/legacy/combat_tactics','shadowself/legacy/registry','shadowself/control/travel','shadowself/control/bosses',
 'shadowself/control/encounters','shadowself/control/supplies','shadowself/control/arena_healing',
 'shadowself/control/weaver/controller','shadowself/control/newbosses/controller'}
for _,k in ipairs({'shadowself/control/arena_adapter','astra/ui/lobby_client','astra/ui/mode_hud_client','astra/net/settlement_hud_state'}) do keys[#keys+1]=k end
local saved,preloads={},{};for _,k in ipairs(keys) do saved[k]=package.loaded[k];preloads[k]=package.preload[k] end
local created,stopped,checks=0,0,0
local function owner() created=created+1;return {Stop=function() stopped=stopped+1 end} end
for _,k in ipairs({'shadowself/control/weaver/controller','shadowself/control/newbosses/controller'}) do
 package.loaded[k]=nil;package.preload[k]=function() return owner end
end
for _,k in ipairs({'shadowself/legacy/action_library','shadowself/legacy/combat_equipment','shadowself/legacy/combat_tactics'}) do package.loaded[k]={} end
package.loaded['shadowself/legacy/registry']={ActionLibrary=function() return {Stop=function() end} end,
 CombatEquipment=function() return {Reset=function() end} end,CombatTactics=function() return {Reset=function() end} end}
package.loaded['shadowself/control/travel']=function() return {} end
for _,k in ipairs({'shadowself/control/bosses','shadowself/control/encounters'}) do package.loaded[k]=function() return {Stop=function() end} end end
package.loaded['shadowself/control/supplies']=function() return {Check=function() checks=checks+1 end} end
package.loaded['shadowself/control/arena_healing']=function() return {} end
package.loaded['shadowself/control/coordinator']=nil
local Coordinator=require('shadowself/control/coordinator')
local bridge={player={prefab='wilson'},h={}}
local strategy={};local healing={};local plan={arena=true,arena_strategy=strategy,arena_healing=healing}
local arena=Coordinator(bridge,plan)
assert(arena.plan==plan and arena.plan.arena_strategy==strategy and arena.healing==healing and checks==1)
assert(not arena.weaver and not arena.newbosses and created==0,'arena must have only partner strategy owners')
assert(not package.loaded['shadowself/control/weaver/controller'] and not package.loaded['shadowself/control/newbosses/controller'],'arena must not even load solo controllers')
arena:Stop();assert(stopped==0,'arena shutdown cannot issue a solo movement reset')
local solo=Coordinator(bridge,{kind='fight'})
assert(solo.weaver and solo.newbosses and created==2,'standalone Boss fights retain the existing owners')
solo:Stop();assert(stopped==2,'standalone owners release exactly once')
local title='角斗场'
package.loaded['astra/ui/lobby_client']={New=function() return {Refresh=function() end,IsAvailable=function() return true end,GetState=function() return {} end} end}
package.loaded['astra/ui/mode_hud_client']={New=function() return {Refresh=function() end,
 GetTarget=function() return 'arena-run',1,'PARTICIPANT' end,
 GetModel=function() return {title=title,visible=true,rows={{id='wave',value='1 / 15'}}} end} end}
package.loaded['astra/net/settlement_hud_state']={}
package.loaded['shadowself/control/arena_adapter']=nil
local adapter=require('shadowself/control/arena_adapter')({})
assert(adapter:Snapshot().arena,'partner original arena title stays recognized')
title='场地测试';assert(adapter:Snapshot().arena,'demonstrated renamed title remains compatible')
title='其他模式';assert(not adapter:Snapshot().arena,'unrelated HUD remains rejected')
for _,k in ipairs(keys) do package.loaded[k]=saved[k];package.preload[k]=preloads[k] end
print('PASS: partner arena strategy/healing/supply setup preserved; zero standalone Boss loads, owners or shutdown actions in arena; solo ownership retained')
