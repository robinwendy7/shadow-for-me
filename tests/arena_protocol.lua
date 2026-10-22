local savedTime=GetTime;local now=0;GetTime=function() return now end
local function net(v) return {value=function() return v end} end
local state={revision=1,lobby_state="LOBBY",preparation={selection={},ready={}},userid="test"}
local sent={};local private={}
local env=setmetatable({ThePlayer=nil,TheWorld=nil,TheNet=nil,TheFocalPoint=nil,
 GetModRPC=function(namespace,name) assert(namespace=="ASTRA" and name=="lobby_request");return 71 end,
 SendModRPCToServer=function(...) sent[#sent+1]={...} end},{__index=_G})
env.require=function(name)
 if private[name] then return private[name] end
 local fn=assert(loadstring(read_astra_source(name..".lua"),name));setfenv(fn,env)
 local result=fn();private[name]=result;return result
end
local function loadmodule(name) return env.require(name) end
local player={userid="test",astra_player_classified={astra_lobby_state_revision=net(1),astra_lobby_state_payload=net(state),
 astra_lobby_catalog_revision=net(1),astra_lobby_catalog_payload=net({modes={}}),astra_lobby_roster_revision=net(1),astra_lobby_roster_payload=net({players={}})}}
env.ThePlayer=player
local client=loadmodule("astra/ui/lobby_client").New(player);client:Refresh(true)
assert(client:IsAvailable(),'actual server lobby client recognizes authoritative classified channels')
local ok,id=client:Send("QUEUE_JOIN",{mode_id="ARENA",mode_version=1,variant_id="ARENA_CLASSIC_SOLO",direct_start=true})
assert(ok and id and #sent==1 and sent[1][1]==71 and sent[1][3]=="QUEUE_JOIN",'real ASTRA client -> real RPC encoder')
local hasvariant,hasdirect=false,false
for _,v in pairs(sent[1]) do if v=="ARENA_CLASSIC_SOLO" then hasvariant=true end;if v==true then hasdirect=true end end
assert(hasvariant and hasdirect and client:IsActionPending("QUEUE_JOIN"),'single variant and direct-start travel through actual sender')
-- Isolated adapter with asynchronous server acknowledgements.
local oldL,oldH=package.loaded['astra/ui/lobby_client'],package.loaded['astra/ui/mode_hud_client']
local c={pending={},requests={},Refresh=function() end,IsAvailable=function() return true end,GetState=function() return state end,
 GetLastResponse=function() return state.last_response end,IsActionPending=function(self,a) return self.pending[a] end,
 Send=function(self,a,f) self.requests[#self.requests+1]={a=a,f=f};self.pending[a]=true;return true,'r'..#self.requests end}
package.loaded['astra/ui/lobby_client']={New=function() return c end}
package.loaded['astra/ui/mode_hud_client']={New=function() return {Refresh=function() end,GetModel=function() end,GetTarget=function() end} end}
local oldSet=package.loaded['astra/net/settlement_hud_state'];package.loaded['astra/net/settlement_hud_state']={}
local Adapter=require('shadowself/control/arena_adapter');local adapter=Adapter(player)
adapter.hud.GetModel=function() return {title='角斗场',status={text='波次间休整'},rows={{id='wave',value='2 / 15'}}} end
assert(adapter:Snapshot().intermission==true,'server HUD intermission recognized')
adapter.hud.GetModel=function() return {title='角斗场',status={text='战斗中'},rows={{id='wave',value='2 / 15'}}} end
assert(adapter:Snapshot().intermission==false,'active combat is not a waiting period')
adapter:Prepare({state=state});assert(c.requests[1].a=='LOBBY_CONFIGURE')
now=2;adapter:Prepare({state=state});assert(#c.requests==1,'pending configure cannot cause repeated starts')
c.pending={};state.preparation.selection={mode_id='ARENA',variant_id='ARENA_CLASSIC_SOLO'}
adapter:Prepare({state=state});assert(c.requests[2].a=='LOBBY_READY' and c.requests[2].f.ready==true)
now=4;c.pending={};state.preparation.ready.test=true;state.preparation.all_ready=false
adapter:Prepare({state=state});assert(#c.requests==2,'readiness alone is insufficient before server all_ready')
state.preparation.all_ready=true;state.party={party_id='p',revision=7,leader_userid='test',members={{userid='test'}},state='OPEN'}
adapter:Prepare({state=state});assert(c.requests[3].a=='QUEUE_JOIN' and c.requests[3].f.party_revision==7 and c.requests[3].f.direct_start)
state.party.members[2]={userid='other'};now=6
local status=adapter:Prepare({state=state});assert(status=='failed' and #c.requests==3,'do not split or take over a multiplayer party')
state.party.members[2]=nil;state.ticket={};state.party.state='QUEUED';adapter:Cancel()
assert(c.requests[4].a=='QUEUE_CANCEL','cancel only own queued ticket')
package.loaded['astra/ui/lobby_client'],package.loaded['astra/ui/mode_hud_client'],package.loaded['astra/net/settlement_hud_state']=oldL,oldH,oldSet
GetTime=savedTime
print('PASS: actual ASTRA client/RPC encoder, solo variant/direct start, version fields, pending acknowledgement, server readiness and party/cancel boundaries')
