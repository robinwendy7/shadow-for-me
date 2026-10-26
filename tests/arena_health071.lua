local keys={'astra/persistence/schema','astra/net/mode_hud_state','astra/net/boss_health_state','astra/ui/mode_hud_client'}
local saved={};for _,k in ipairs(keys) do saved[k]=package.loaded[k];package.loaded[k]=assert(loadstring(read_astra_source(k..'.lua')))() end
local oldTime=GetTime;local now=0;GetTime=function() return now end
local R=assert(loadfile('scripts/shadowself/control/arena_late_runtime.lua'))()
local Finish=assert(loadfile('scripts/shadowself/control/arena_stage11_finish.lua'))()
local boss={GUID=134999,prefab='daywalker',pos=Vector3(559,0,615)}
function boss:IsValid() return true end
function boss:HasTag() return false end
function boss:GetPosition() return self.pos end
boss.replica={health={GetCurrent=function() return 100 end}}
local function net(v) return {value=function() return v end} end
local p={astra_player_classified={astra_instance_id=net('health071'),astra_generation=net(25)}}
p.replica={inventory={GetItems=function() return {} end,GetEquips=function() return {} end,GetOverflowContainer=function() end}}
local s={player=p,route='shadow',boss=boss,arena={instance='health071',generation=25,enemies={boss},bridge={}},context={}}
function s:Cleared() return true end
function s:Patrol() return 'hold' end
function s.arena:StopCombat() end
local row={id='server-95742',name='daywalker',prefab='daywalker',current=4800,total=10000,
 x=559,z=615,attackers=1,damage=0,engaged=true,invincible=false}
local function publish(rows)
 now=now+.3
 local model={schema_version=1,visible=true,scene_revision=11,bosses=rows or {row},focus={},alive={}}
 p.astra_player_classified.astra_state_payload=net({schema_version=1,states={{schema_version=1,
 state_id='health071:boss_health',instance_id='health071',generation=25,version=now,value=model}}})
end
publish()
assert(R.Health(s,boss)==4800,'real UI payload exact health survives different server and client GUIDs')
assert(Finish.Pig(s,{boss})=='hold' and not s.health_wait,'real HUD health is accepted; missing bone armor now holds combat separately instead of fabricating health-wait')
row.current=99;publish()
assert(not Finish.Allowed(s,boss) and s.finish,'server exact99HP still stops output for chest finishing, never dummy replica100')
row.current=4800;row.invincible=true;publish()
assert(not R.Health(s,boss) and s.health_reason=='boss_invincible','invincible target does not open an attack window')
row.invincible=false;row.x=600;publish()
assert(not R.Health(s,boss) and s.health_reason=='boss_position_mismatch','distant same-prefab record cannot bind to local target')
row.x=559
local other={};for k,v in pairs(row) do other[k]=v end;other.id='another-server-id'
publish({row,other})
assert(not R.Health(s,boss) and s.health_reason=='ambiguous_boss_records','multiple same-prefab records remain ambiguous')
publish();s.arena.generation=24
assert(not R.Health(s,boss) and s.health_reason=='hud_instance_generation_mismatch','stale generation remains rejected')
s.arena.generation=25;s.arena.instance='other'
assert(not R.Health(s,boss),'another instance cannot supply boss health')
for _,k in ipairs(keys) do package.loaded[k]=saved[k] end
GetTime=oldTime
print('PASS: actual ASTRA health UI protocol with different client/server IDs; exact99HP gate, position, ambiguity, invincibility and instance/generation checks')
