local Adapter=require('shadowself/control/arena_adapter')
local record={schema_version=1,state_id='arena072:arena_state',instance_id='arena072',generation=17,
 value={schema_version=1,mode_id='ARENA',wave=6,remaining_objectives=3}}
local payload={schema_version=1,states={record}}
local adapter={player={astra_player_classified={astra_state_payload={value=function() return payload end}}}}
setmetatable(adapter,{__index=Adapter})
assert(adapter:RemainingObjectives('arena072',17,6)==3,'published arena_state supplies the authoritative three remaining objectives')
assert(not adapter:RemainingObjectives('arena072',16,6),'previous generation cannot clear the pack')
assert(not adapter:RemainingObjectives('other',17,6),'other instance cannot clear the pack')
assert(not adapter:RemainingObjectives('arena072',17,5),'other wave cannot clear the pack')
for _,bad in ipairs({-1,2.5,math.huge,'3'}) do
 record.value.remaining_objectives=bad
 assert(not adapter:RemainingObjectives('arena072',17,6),'invalid count cannot authorize melee')
end
record.value.remaining_objectives=0
assert(adapter:RemainingObjectives('arena072',17,6)==0,'zero is an actual completed objective count, not a missing payload')
local oldJson=json
json={decode=function(s) assert(s=='wire072');return payload end}
payload='wire072'
-- The transport and decoder are separate: decoded records remain an ordinary table.
json.decode=function() return {schema_version=1,states={record}} end
assert(adapter:RemainingObjectives('arena072',17,6)==0,'string net payload uses the existing JSON wire format')
json.decode=function() error('malformed') end
assert(not adapter:RemainingObjectives('arena072',17,6),'malformed payload remains unavailable')
json=oldJson
print('PASS: authoritative ASTRA arena objective counter with instance/generation/wave checks, JSON transport and invalid-count rejection')
