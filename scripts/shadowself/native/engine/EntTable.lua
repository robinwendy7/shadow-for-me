--这个表定义了怪物的不同属性
local function stopMove()
	--[[if HitAndRun.guid == 0 and ThePlayer:HasTag('moving') then --stop moving
		local now_ppos = ThePlayer:GetPosition()
		POS_util:GoToPoint(now_ppos.x, now_ppos.z)
	end]]
end
local custom_extrafunction_flycreature = function(ent)
	if HitAndRun.guid ~= 0 then return end
	if HitAndRun.p_range > 4 then return end
	if HitAndRun.activeitem then return end
	local canhitrange = HitAndRun.EntTable[ent.prefab].canhitrange or 1.25
	if HitAndRun.distance > (HitAndRun.p_range == 4 and 2 * canhitrange or canhitrange) and not ThePlayer:HasTag('attack') then
		HitAndRun:WalkTo(HitAndRun.ppos, HitAndRun.pos, HitAndRun.distance)
		return true
	else
		stopMove()
	end
end
local custom_extrafunction_runawaycreature = function(ent)
	if HitAndRun.guid ~= 0 then return end
	if HitAndRun.p_range ~= 4 then return end
	local canhitrange = HitAndRun.EntTable[ent.prefab].canhitrange or 1.25
	if HitAndRun.distance > 2 * canhitrange and ENT_util:GetAngle(ent, ThePlayer) > 100
		and (not ent.replica.combat or ent.replica.combat:GetTarget() ~= ThePlayer)
		and not ThePlayer:HasTag('attack')
		and not ent:HasTag('sleeping') then
		HitAndRun:WalkTo(HitAndRun.pos, HitAndRun.ppos, 0.1)
		return true
	else
		stopMove()
	end
end
local custom_extrafunction_shadow = function(ent)
	if MOD_util:GetMOption("hitandrun_shadowdodge", HitAndRun.shadowdodge) and HitAndRun:IsHitingFrame(MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe), ent)
		and ENT_util:CheckDebugString(ent, 'atk') and not HitAndRun:holdLegionShield(HitAndRun.hand) then
		HitAndRun:WalkTo(HitAndRun.pos, HitAndRun.ppos, HitAndRun:GetTargetCanHitRange(ent, ThePlayer) + 0.5 + 0.1)
		HitAndRun.guid = 0
		Sleep(10 * FRAMES)
		HitAndRun:CloseAndAttack(ent)
		return true
	end
end
local customer_extrafunction_spider = function(ent)
	local range = HitAndRun:GetTargetCanHitRange(ThePlayer, ent)
	local anotherspider = FindEntity(ThePlayer, range,
		function(inst)
			local a = HitAndRun.EntTable[inst.prefab]
			return inst ~= ent and a and a.spiderselectfn and a.spiderselectfn(inst)
		end)
	if anotherspider then
		HitAndRun:CloseAndAttack(anotherspider)
		return true
	end
end
HitAndRun.EntTable = {
	["crawlingnightmare"] = { isshadow = true, extrafunction = custom_extrafunction_shadow },
	["crawlinghorror"] = { isshadow = true, extrafunction = custom_extrafunction_shadow },
	["terrorbeak"] = { isshadow = true, extrafunction = custom_extrafunction_shadow },
	["nightmarebeak"] = { isshadow = true, extrafunction = custom_extrafunction_shadow },
	['butterfly'] = {
		extrafunction = custom_extrafunction_flycreature,
	},
	['rabbit'] = { extrafunction = custom_extrafunction_flycreature, },
	["lightflier"] = { extrafunction = custom_extrafunction_flycreature, },
	["moonbutterfly"] = { extrafunction = custom_extrafunction_flycreature, },
	['lightcrab'] = { extrafunction = custom_extrafunction_flycreature, canhitrange = 1, },
	["walrus"] = { extrafunction = custom_extrafunction_runawaycreature },
	["koalefant_summer"] = { extrafunction = custom_extrafunction_runawaycreature },
	["koalefant_winter"] = { extrafunction = custom_extrafunction_runawaycreature },
	['lightninggoat'] = { extrafunction = custom_extrafunction_runawaycreature, canhitrange = 1, },
	['bat'] = { extrafunction = custom_extrafunction_runawaycreature },
	["alterguardian_phase3"] = {
		extrafunction = function(ent)
			--2~3.5   3的时候会跑 最大3.5
			if HitAndRun.p_range == 4 and (HitAndRun.distance >= 3.49 or HitAndRun.distance < 3.05)
				and HitAndRun.final_walkway == 1 then
				local animpos = POS_util:CalculateAimPos(HitAndRun.pos, HitAndRun.ppos, 0, 3.3)
				if distsq(animpos, HitAndRun.ppos) > 3 ^ 2 then
					HitAndRun:WalkTo(HitAndRun.pos, HitAndRun.ppos, 3.3)
				else
					HitAndRun:_PredictWalk(animpos)
				end
				return true
			end
		end
	},
	['spider'] = {
		spiderselectfn = function(inst)
			return inst:HasTag("attack")
		end,
		extrafunction = customer_extrafunction_spider,
	},
	['spiderqueen'] = {
		extrafunction = customer_extrafunction_spider,
	},
}
HitAndRun.EntTable['spider_moon'] = HitAndRun.EntTable['spiderqueen']
HitAndRun.EntTable['spider_warrior'] = HitAndRun.EntTable['spiderqueen']
HitAndRun.EntTable['spider_spitter'] = HitAndRun.EntTable['spiderqueen']
HitAndRun.EntTable['spiderden'] = HitAndRun.EntTable['spiderqueen']
HitAndRun.EntTable['spider_hider'] = HitAndRun.EntTable['spider']
HitAndRun.EntTable['spider_healer'] = HitAndRun.EntTable['spider']
local empty = {}
setmetatable(HitAndRun.EntTable, { __index = function(t, k) return empty end })
