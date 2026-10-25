local A=require('scd_analysis')
assert(not A.Cause('') and not A.Cause('  ') and A.Cause('fire')=='fire','blank synchronized cause is unavailable')
local ctx={instance='test',generation=1,wave=8}
local loss={event='hp_loss',time=10,context=ctx,hp_before=95,hp_after=0,observed_loss=95,
 snapshot={hunger_percent=.95,nearby={{prefab='crabking_claw',distance=2,animation='atk',frame=24},{prefab='sandspike_tall',distance=.2,animation='tall_pre'}}}}
local unknown=A.Loss(loss,{})
assert(unknown.confidence=='unknown' and #unknown.attacker_candidates==0 and #unknown.nearby_attacking==1 and #unknown.nearby_hazards==1,'nearby attack and hazard never fabricate an attacker')
local attack={event='attacked',time=10.1,context=ctx,attacker={prefab='knight',guid=3}}
local related=A.Loss(loss,{attack})
assert(related.confidence=='correlated' and related.attacker_candidates[1].entity.prefab=='knight','late attacker notification can correlate but cannot become confirmed damage')
attack.context={instance='test',generation=2,wave=8}
assert(A.Loss(loss,{attack}).confidence=='unknown','no cross-generation attribution')
attack.context=ctx;attack.time=9
assert(A.Loss(loss,{attack}).confidence=='unknown','old attack does not bleed into later damage')
loss.cause='fire';loss.overtime=true;loss.snapshot.hunger_percent=0;loss.snapshot.burning=true
local explicit=A.Loss(loss,{})
assert(explicit.confidence=='reported' and explicit.reported_cause=='fire' and #explicit.environment_clues==3,'retain explicit cause while preserving competing environment observations')
loss.cause=nil
assert(A.Loss(loss,{}).confidence=='unknown','zero hunger and fire flags alone are clues, not confirmed cause')
local function sample(t,hp,body,percent)
 return {time=t,hp=hp,hunger_percent=.95,gear={BODY={prefab=body,percent=percent},HEAD={prefab='empty'},HANDS={prefab='cane'}}}
end
local report={death={at=10},recent_events={loss},recent_samples={sample(8,100,'armorwood',.1),sample(9,95,'empty')},death_cause=''}
local result=A.Report(report)
assert(#result.equipment_transitions==1 and result.equipment_transitions[1].previous.percent==.1,'report records live armor-to-empty transition with preceding durability')
assert(result.losses[1].net_loss==95 and result.losses[1].attribution.confidence=='unknown','large net drop remains aggregate evidence')
assert(#result.unknowns>0 and result.facts[1]:find('BODY'),'blank cause remains explicitly unknown')
report.recent_samples={sample(8,100,'armorwood',.1),sample(10,0,'empty')}
assert(#A.Report(report).equipment_transitions==0,'death auto-unequip must not be mistaken for predeath armor exhaustion')
local C=require('scd_context')
local e={prefab='rook',replica={health={GetPercent=function() return 1 end,IsDead=function() return true end}},
 IsValid=function() return true end,GetPosition=function() return {x=0,z=0} end,
 AnimState={IsCurrentAnimation=function(_,a) return a=='atk_skid' end,GetCurrentAnimationFrame=function() return 4 end}}
local entity=C.Entity(e)
assert(entity.animation=='atk_skid' and entity.dead and entity.hp_percent==1,'capture recovery and death state even when hp_percent is stale')
print('PASS attribution uncertainty, late notification correlation, stage boundary, environment ambiguity, armor transitions and stale health-percent death state')
