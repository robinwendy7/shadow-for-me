local Recorder=require('scd_recorder')
local now=0;local hp,maxhp=150,150;local tags={};local callbacks={};local pending_saves={};local saves={}
local p={prefab='wilson',GUID=10,replica={},components={},player_classified={}}
function p:IsValid() return true end
function p:HasTag(k) return tags[k] or false end
function p:GetPosition() return {x=0,y=0,z=0} end
function p:ListenForEvent(k,fn) callbacks[k]=fn end
function p:RemoveEventCallback(k,fn) assert(callbacks[k]==fn);callbacks[k]=nil end
p.AnimState={IsCurrentAnimation=function(_,n) return n=='idle' end,GetCurrentAnimationFrame=function() return 2 end}
p.replica.health={GetCurrent=function() return hp end,Max=function() return maxhp end,GetPercent=function() return hp/maxhp end}
p.replica.inventory={GetEquippedItem=function(_,slot) return {prefab=slot=='hands' and 'nightsword' or 'armorwood',replica={inventoryitem={classified={percentused={value=function() return 80 end}}}}} end}
p.components.playercontroller={IsBusy=function() return false end}
local wave=4;local instance='arena-A';local visible=true;local route='普通线';local generation=1
local hud={Refresh=function() end,GetModel=function() return {visible=visible,title='角斗场',rows={{id='wave',value=wave..'/15'},{id='route',value=route}}} end,
    GetTarget=function() return instance,generation,'PARTICIPANT' end}
p._shadowself={control={phase='active',task={kind='arena'},jobs={arena={adapter={hud=hud}}}}}
local foe={prefab='deerclops',GUID=20,replica={combat={}},AnimState={IsCurrentAnimation=function(_,a) return a=='atk' end,GetCurrentAnimationFrame=function() return 17 end}}
function foe:IsValid() return true end;function foe:HasTag() return false end;function foe:GetPosition() return {x=3,y=0,z=0} end
local G={ThePlayer=p,GetTime=function() return now end,print=capture_log,APP_VERSION='756039',
    EQUIPSLOTS={HANDS='hands',HEAD='head',BODY='body'},os={time=function() return 123456 end,date=function() return '2026-10-22 12:00:00' end},
    TheWorld={state={cycles=70,isnight=false}},TheNet={GetPing=function() return 30 end},
    TheSim={FindEntities=function() return {p,foe} end,SetPersistentString=function(_,key,text,encode,fn) saves[#saves+1]={key=key,text=text};pending_saves[#pending_saves+1]=fn end}}
local r=Recorder.New(G,{json={encode=encode_json}})
local function tick(t) now=t;r:Tick() end
local function event(name,data) assert(callbacks[name],name);callbacks[name](p,data) end
tick(0);assert(r.was_alive and r.stage.context.wave==4 and callbacks.attacked)
event('attacked',{});hp=135;event('healthdelta',{oldpercent=1,newpercent=.9});tick(.25)
assert(r.stage.hits==1 and r.stage.loss_events==1 and r.stage.observed_hp_loss==15,'notification + healthdelta + poll must not double-count loss')
assert(r.events[1].attacker==nil and r.events[1].snapshot.nearby[1].prefab=='deerclops','nearest monster cannot become attributed attacker')
hp=140;event('healthdelta',{});assert(r.stage.healed==5)
maxhp=200;event('healthdelta',{});assert(r.stage.observed_hp_loss==15,'max HP changes do not fabricate damage')
wave=5;tick(1);assert(r.stage.hits==0 and #r.stages==2)
event('attacked',{attacker=foe,damage=20});hp=120;event('healthdelta',{});assert(r.life_hits==2 and r.life_hp_loss==35)
assert(r.events[#r.events-1].attacker.prefab=='deerclops')
-- Death event may arrive before the final health delta, ghost tag and world HUD disappear.
event('death');hp=0;event('healthdelta',{});tags.playerghost=true;visible=false;tick(1.1);tick(1.3)
local report=r.last_report
assert(r.deaths==1 and report.context.wave==5 and report.context.source=='astra_hud')
assert(report.stage.hits==1 and report.stage.observed_hp_loss==140 and report.life_hp_loss==155)
assert(report.predeath.gear.HANDS.prefab=='nightsword' and report.death.signal=='death_event')
assert(report.predeath.gear.HANDS.percent==.8,'read the installed inventoryitem classified percent-used value')
assert(report.summary_text:find('第5关',1,true) and report.summary_text:find('客户端观测',1,true))
assert(report.summary_text:find('同步死亡原因：未提供',1,true) and report.summary_text:find('已确认观测',1,true),'summary explains unavailable cause instead of displaying an empty value')
assert(report.analysis and report.analysis.losses[1].attribution.confidence=='unknown' and report.analysis.losses[2].attribution.confidence=='correlated','death report preserves unknown prior loss and correlates only the matching attacker event')
event('death');tick(2);assert(r.deaths==1,'same death signals deduplicate')
assert(#saves==1 and r.save_busy)
r:Export();r:Export();assert(#saves==1,'pending persistence writes must serialize')
pending_saves[1](true);assert(#saves==2);pending_saves[2](true)
-- Revive the same entity; stage and life counters restart, previous report remains exportable.
hp=200;tags.playerghost=nil;visible=true;tick(3)
assert(not r.death_done and r.stage.hits==0 and r.life_hits==0 and r.last_report==report)
event('attacked',{});assert(r.stage.hits==1)
-- A death event followed by a very fast respawn still produces exactly one report.
event('death');tick(3.05);assert(r.deaths==2 and r.stage.hits==0,'quick revival cannot swallow death event')
-- Generation is part of the stage key even when instance and wave are unchanged.
local old=r.stage;generation=2;tick(4);assert(r.stage~=old)
r:MarkStage('测试关卡');assert(r.stage.context.source=='manual');r:MarkStage(nil);assert(r.stage.context.wave==5)
visible=false;tick(5);assert(r.level.source=='last_seen_astra_hud')
tick(16);assert(r.level.source=='unavailable','stale context expires explicitly')
visible=true
for i=1,80 do wave=i;tick(16+i*.25);event('attacked',{}) end
assert(#r.stages==64 and r.life_hits==80,'bounded details cannot truncate life counters')
for i=1,550 do r:Note('case') end
assert(#r.events==500 and #r.samples<=122)
r:Toggle();local hits=r.life_hits;event('attacked',{});assert(r.life_hits==hits and not r.enabled)
r:Toggle();tick(40);assert(r.was_alive)
r:Unbind('test');assert(not r.player and not next(callbacks),'all listener hooks removed')
-- Joining as a ghost is not a new death.
tags.playerghost=true;hp=0;G.ThePlayer=p;tick(41);tick(42);assert(r.deaths==2)
r:Unbind('test')
-- Optional loaded ASTRA HUD path, independent of a running Shadow arena job.
tags.playerghost=nil;hp=150;p._shadowself=nil;visible=true;wave=8
package.loaded['astra/ui/mode_hud_client']={New=function(player) assert(player==p);return hud end}
tick(43);assert(r.level.wave==8 and r.level.source=='astra_hud')
r:Unbind('test');package.loaded['astra/ui/mode_hud_client']=nil
-- One bad snapshot cannot crash a game event callback; three consecutive faults stop capture.
for i=1,3 do r:Safe(function() error('simulated failure') end) end
assert(not r.enabled)
local oldsave=G.TheSim.SetPersistentString;G.TheSim.SetPersistentString=function() error('disk failure') end
r.save_busy=false;r.save_next=nil;r:Save(report);assert(not r.save_busy,'sync storage failures cannot jam the queue')
G.TheSim.SetPersistentString=oldsave
capture_report(report)
local oldmarker=package.loaded.scd_test_build
package.loaded.scd_test_build={commit=string.rep('a',40),manifest_sha256=string.rep('b',64),build_id='test-manifest',mod_directory='shadow-for-me-test',mod_version='0.13.8'}
G.ModManager={mods={{modname='shadow-for-me-test',modinfo={version='0.13.8'}}}}
assert(r.context:Build().status=='verified')
G.ModManager.mods[1].modinfo.version='0.13.7';assert(r.context:Build().status=='unverified','never relabel old loaded version')
G.ModManager.mods[1].modinfo.version='0.13.8';G.ModManager.mods[2]={modname='workshop-3821474072',modinfo={version='0.13.7'}}
assert(r.context:Build().status=='unverified','two enabled project copies are ambiguous')
package.loaded.scd_test_build=oldmarker
print('PASS recorder lifecycle, damage semantics, arena attribution, death deduplication, bounded replay and persistence queue')
