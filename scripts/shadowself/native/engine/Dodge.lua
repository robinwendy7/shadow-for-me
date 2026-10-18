do --关于躲避的函数
	local DEGREES = GLOBAL.DEGREES
	local BASE_PLAYER_SPEED = 6
	local SPEED_CACHE_TIME = 1
	local AIM_REACHED_DIST_SQ = 0.1 * 0.1
	local IDLE_DODGE_FALLBACK_TICKS = 90

	local always_can_target_prefabs = {
		wagboss_robot = true,
	}
	function HitAndRun:AlwaysCanTarget(ent)
		if not ent then return end
		return always_can_target_prefabs[ent.prefab]
	end

	local function reset_idle_ticks()
		HitAndRun.idle_ticks = 0
	end

	local function get_replica_combat(ent)
		return ent ~= nil and ent.replica ~= nil and ent.replica.combat or nil
	end

	local function get_attack_range(ent)
		local combat = get_replica_combat(ent)
		return combat ~= nil and combat:GetAttackRangeWithWeapon() or 0
	end

	local function get_dodge_distance(ent, dodgetab)
		local dist = FunctionOrValue(dodgetab.dist, ent)
		if dist then
			return dist
		end
		local combatdist = FunctionOrValue(dodgetab.combatdist, ent) or get_attack_range(ent)
		return (combatdist * (dodgetab.combat_scale or 1) +
				ThePlayer:GetPhysicsRadius(0) + (dodgetab.calculate_offset or 0.4) + 0.1) +
			(dodgetab.extradist or 0) +
			(FunctionOrValue(dodgetab.combat_offset, ent) or 0)
	end

	local function get_dodge_points(ent, dodgetab, locked_ent_pos, locked_player_pos, player_pos)
		local update = dodgetab.update ~= false
		local ent_pos = update and ent:GetPosition() or locked_ent_pos
		local player_anchor = update and player_pos or locked_player_pos
		local point = FunctionOrValue(dodgetab.point, ent) or "target"
		if point == "target" then
			return ent_pos, player_anchor
		end
		return player_anchor, ent_pos
	end

	local function get_dodge_aim_pos(ent, dodgetab, locked_ent_pos, locked_player_pos, player_pos)
		local start_pos, end_pos = get_dodge_points(ent, dodgetab, locked_ent_pos, locked_player_pos, player_pos)
		local angle = FunctionOrValue(dodgetab.angle, ent) or 0
		local dist = get_dodge_distance(ent, dodgetab)
		return dodgetab.fn and dodgetab:fn(start_pos, end_pos, angle, dist)
			or POS_util:CalculateAimPos(start_pos, end_pos, angle, dist)
	end

	local function stop_player_if_moving()
		if ThePlayer:HasTag("moving") then
			local pos = ThePlayer:GetPosition()
			POS_util:GoToPoint(pos.x, pos.z)
		end
	end

	local function has_usable_dodge_data(prefab)
		local entries = HitAndRun.targetanimtable ~= nil and HitAndRun.targetanimtable[prefab] or nil
		if entries == nil then
			return false
		end
		for _, data in pairs(entries) do
			if not data.noused then
				return true
			end
		end
		return false
	end

	function HitAndRun:DoDodge(dodgetab)
        local owner=ThePlayer
		local ent = HitAndRun.ent
		if ent == nil or dodgetab == nil then return end

		HitAndRun.guid = 0
        HitAndRun.shadowself_dodging=ent
		local locked_ent_pos, locked_player_pos = HitAndRun.pos, HitAndRun.ppos
		ThePlayer:PushEvent("EquipItem", { type = "walk_hands" })

		while true do
            if ThePlayer~=owner or not owner:IsValid() or not owner.components.playercontroller then HitAndRun.shadowself_dodging=nil;return end
			if dodgetab.breakdodgefn and dodgetab.breakdodgefn(ent) then
				reset_idle_ticks()
				break
			end

			local player_pos = ThePlayer:GetPosition()
			local aim_pos = get_dodge_aim_pos(ent, dodgetab, locked_ent_pos, locked_player_pos, player_pos)
			if aim_pos == nil then
				break
			end

			if distsq(player_pos, aim_pos) < AIM_REACHED_DIST_SQ and HitAndRun:ShouldAtkWhenDodging(ent, dodgetab) then
				HitAndRun:AtkWhenDodging(ent)
			else
				POS_util:GoToPoint(aim_pos.x, aim_pos.z)
			end

			Sleep(FRAMES)

            if ThePlayer~=owner or not owner:IsValid() or not owner.components.playercontroller then HitAndRun.shadowself_dodging=nil;return end
			local next_dodge = HitAndRun:IsAttackPre(ent, 1, dodgetab)
			if not next_dodge and (not dodgetab.avoid_break or not dodgetab.avoid_break(ent)) then
				break
			elseif next_dodge and dodgetab ~= next_dodge then
				if not dodgetab.legacypos then
					locked_ent_pos, locked_player_pos = ent:GetPosition(), player_pos
				end
				dodgetab = next_dodge
			end
		end

        HitAndRun.shadowself_dodging=nil
		stop_player_if_moving()
		HitAndRun:CancelDodgingAtk(ent)
        local follow=HitAndRun.shadowself_after_dodge and HitAndRun.shadowself_after_dodge(ent) or ent
		ThePlayer:PushEvent("EquipItem", { type = "fight", target = follow })
		HitAndRun:CloseAndAttack(follow)
	end

	local initidlelist = {
		tallbird = 50,
	}
	local function get_initial_idle_ticks(target)
		return initidlelist[target.prefab]
	end

	local function get_attack_frame_window(data, target)
		local stop_frame = ENT_util:FnOrNum(data.atk_stop_frame, target) or 1000
		local start_frame = ENT_util:FnOrNum(data.atk_start_frame, target) or 0
		if data.atk_frame_calculate then
			start_frame = math.min(ENT_util:FnOrNum(data.atk_frame_calculate, target, data.atk_start_frame,
				stop_frame, nil, data), stop_frame)
		end
        if HitAndRun.shadowself_latency_frames then start_frame=math.max(0,start_frame-HitAndRun.shadowself_latency_frames()) end
		return start_frame, stop_frame
	end

	local function is_same_checked_anim(checktab, target, atkanim)
		return checktab ~= nil and ENT_util:FnOrNum(checktab.atkanim, target) == atkanim
	end
	--判断生物是否要攻击
	function HitAndRun:IsAttackPre(target, updateticks, checktab)
		--checktab是已经进入躲避循环了，进入躲避循环之前的那次目标动作表
		if not target then return end
		local entries = HitAndRun.targetanimtable[target.prefab]
		HitAndRun.idle_ticks = (HitAndRun.idle_ticks or get_initial_idle_ticks(target) or 0) + (updateticks or 1)
		if entries == nil then
			return false
		end
		local targetanim = ENT_util:GetAnimation(target)
		local targetframe = target.AnimState:GetCurrentAnimationFrame() or 0
		for _, data in pairs(entries) do
			local atkanim = ENT_util:FnOrNum(data.atkanim, target)
			local idledodge_tick = ENT_util:FnOrNum(data.idledodge, target)
			local atk_start_frame, atk_stop_frame = get_attack_frame_window(data, target)
			local same_checked_anim = is_same_checked_anim(checktab, target, atkanim)
			if same_checked_anim then
				if targetframe <= atk_stop_frame and targetanim == atkanim then
					reset_idle_ticks()
					return data
				end
			elseif targetframe >= atk_start_frame and targetframe <=
				atk_stop_frame and targetanim == atkanim then
				--checkatktag
				if data.checkatktag and not target:HasTag("attack") and not (target.prefab=="daywalker" and targetanim=="run_pre") then
					return
				end
				if data.breakdodgefn and data.breakdodgefn(target) then
					return
				end
				reset_idle_ticks()
				return data
			end
			--check idle_ticks
			if same_checked_anim and HitAndRun.idle_ticks >= IDLE_DODGE_FALLBACK_TICKS then
				--print("why i write this?")
				return data
			elseif data.resetidle and data.resetidle(target) then
				reset_idle_ticks()
			elseif target:HasTag('fire') then --目标着火了
				reset_idle_ticks()
			elseif idledodge_tick and idledodge_tick <= HitAndRun.idle_ticks then
				return data
			end
		end
		return false
	end

	local attack_while_dodging_prefabs = {
	}
	function HitAndRun:ShouldAtkWhenDodging(ent, dodgetab)
		if ent ~= nil and ent.prefab and attack_while_dodging_prefabs[ent.prefab] then
			return true
		end
		if HitAndRun.combat ~= nil and HitAndRun.combat:GetAttackRangeWithWeapon() >= 4 then
			return true
		end
		return HitAndRun:CanHitTarget(ent, ThePlayer)
	end

	function HitAndRun:AtkWhenDodging(ent)
		local keyframe = MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe) +
			(HitAndRun.PC:CanLocomote() and 1 or 0)
		if HitAndRun:IsHitingFrame(keyframe, ent, true) then
			HitAndRun:PredictWalk(HitAndRun.ppos, TheInput:GetWorldPosition(), ent)
		else
			HitAndRun:CloseAndAttack(ent, true)
		end
	end

	function HitAndRun:CancelDodgingAtk(ent)

	end

	local run_away_banlist = {
	}
	local run_away_overrides = {
		--[[ dragonfly = "rapid_runaway", ]]
		alterguardian_phase3 = function(target)
			return HitAndRun.p_range == 4 and 1
		end,
		spider_spitter = 4,
	}
	function HitAndRun:RunAwayOverride(target)
		--alterguardian_phase3 = true,
		if target == nil then return false end
		if run_away_banlist[target.prefab] then
			return false
		end
		if run_away_overrides[target.prefab] then
			return FunctionOrValue(run_away_overrides[target.prefab], target)
		end
		return has_usable_dodge_data(target.prefab)
	end

	function HitAndRun:GetSpeed()
		if not HitAndRun.last_get_speed_time or GetTime() - HitAndRun.last_get_speed_time > SPEED_CACHE_TIME then
			HitAndRun.last_get_speed_time = GetTime()
			local inst = ThePlayer
			local mult = inst.player_classified ~= nil and inst.player_classified.externalspeedmultiplier:value() or 1
			local inventory = inst.replica ~= nil and inst.replica.inventory or nil
			if inventory ~= nil then
				local rider = inst.replica.rider
				if rider ~= nil and rider:IsRiding() then
					local saddle = rider:GetSaddle()
					local inventoryitem = saddle ~= nil and saddle.replica ~= nil and saddle.replica.inventoryitem or nil
					if inventoryitem ~= nil then
						mult = mult * inventoryitem:GetWalkSpeedMult()
					end
				else
					local is_mighty = inst:HasTag("mightiness_mighty")
					for _, item in pairs(inventory:GetEquips() or {}) do
						local inventoryitem = item.replica ~= nil and item.replica.inventoryitem or nil
						if inventoryitem ~= nil then
							local item_speed_mult = inventoryitem:GetWalkSpeedMult()
							if is_mighty and item_speed_mult < 1 then
								item_speed_mult = 1
							end
							mult = mult * item_speed_mult
						end
					end
				end
			end
			HitAndRun.speed = mult * BASE_PLAYER_SPEED
		end
		return HitAndRun.speed or BASE_PLAYER_SPEED
	end

	local special_mod_anim_mult = 4 / 3 --一些模组打包的动画是40帧 而克雷只用

	local function get_calculate_distance(ent, notdelay)
		local distance = math.sqrt(distsq(ent:GetPosition(), ThePlayer:GetPosition()))
		return notdelay and distance or math.max(distance - 0.7, 0)
	end

	local function get_calculate_max_range(ent, data)
		local dist = FunctionOrValue(data.dist, ent)
		if dist then
			return dist
		end
		return HitAndRun:GetTargetCanHitRange(ent, ThePlayer) * (data.combat_scale or 1) +
			(data.calculate_offset or 0.4) + 0.1 +
			(data.extradist or 0) +
			(FunctionOrValue(data.combat_offset, ent) or 0)
	end

	local function calculate(ent, a, b, notdelay, v, ...)
		v = v or {}
		local distance = get_calculate_distance(ent, notdelay)
		local max = get_calculate_max_range(ent, v)
		local gamedelay = notdelay and 0 or GAME_util:GetGameDelay()
		local animmult = v.mod_anim and special_mod_anim_mult or 1
		-- print(gamedelay * 6)
		local speed = HitAndRun:GetSpeed()
		if not speed then
			local result = (v._b or b) - 30 * animmult * (max - distance) / (6 - 1) - math.ceil(gamedelay)
			return result
		else
			local result = (v._b or b) - 30 * animmult * (max - distance) / math.clamp(speed - 1, 5, 10) -
				math.ceil(gamedelay)
			return result
		end
	end
	local walk_start_framge = 5
	local safeadvance = 2
	HitAndRun.targetanimtable = {
	}

	local function addcreature(prefab, atkanim, atk_frame_calculate, atk_start_frame, atk_stop_frame, dodgeaimpos, data)
		data = data or {}
		if not HitAndRun.targetanimtable[prefab] then HitAndRun.targetanimtable[prefab] = {} end
		table.insert(HitAndRun.targetanimtable[prefab], {
			atkanim = atkanim,
			atk_frame_calculate = atk_frame_calculate,
			atk_start_frame = atk_start_frame,
			atk_stop_frame = atk_stop_frame,
		})
		if dodgeaimpos then
			for k, v in pairs(dodgeaimpos) do
				HitAndRun.targetanimtable[prefab][#HitAndRun.targetanimtable[prefab]][k] = v
			end
		end

		for k, v in pairs(data) do
			HitAndRun.targetanimtable[prefab][#HitAndRun.targetanimtable[prefab]][k] = v
		end
	end
	local function addcreaturedata(prefab, data)
		data = data or {}
		if not HitAndRun.targetanimtable[prefab] then HitAndRun.targetanimtable[prefab] = {} end
		table.insert(HitAndRun.targetanimtable[prefab], {})

		for k, v in pairs(data) do
			HitAndRun.targetanimtable[prefab][#HitAndRun.targetanimtable[prefab]][k] = v
		end
	end
	local function copy(a, b)
		HitAndRun.targetanimtable[a] = HitAndRun.targetanimtable[b]
	end
	local function makeNoUsed(prefab)
		addcreature(prefab, 'run_loop', calculate, -1, -1, nil, { noused = true })
	end
	addcreature('tallbird', 'atk_pre', calculate, 0, 12, nil, {
		idledodge = function(ent)
			local distance = math.sqrt(distsq(ent:GetPosition(), ThePlayer:GetPosition()))
			local min = ent:GetPhysicsRadius(0) + ThePlayer:GetPhysicsRadius(0)
			return distance - min < 1 and (HitAndRun.PC:CanLocomote() and 52 or 44) or 2000
		end,
	})
	addcreature('tallbird', 'atk', nil, 0, 2)
	addcreature('krampus', 'atk_pre', nil, 0, 18)
	addcreature('krampus', 'atk', nil, 0, 3)

	addcreature('rocky', 'atk', calculate, 0, 20)
	addcreature('minotaur', 'bite', calculate, 0, 16, nil, { combat_offset = 1 }) --jump_atk_pre: 24/44
	addcreature('minotaur', 'jump_atk_loop', nil, 0, 20,
		{ point = "target", update = false, angle = 180 * DEGREES, dist = 2 })
	addcreature('tentacle', 'hit', nil, 0, 20)
	addcreature('tentacle', 'atk_loop', nil, 0, 30)

	addcreature('deerclops', 'atk', nil, (16 - 2) or 10, 33 + 3 - 1, {
		point = "player",
		update = false,
		angle = -80 * DEGREES,
		dist = 6,
	})
	addcreature("bearger", 'atk', nil, 0 or (10 - 3), 32, {
		point = "target", update = false, angle = 90 * DEGREES, dist = 2.1 }, {
		breakdodgefn = function(ent)
			return ENT_util:GetAngle(ent, ThePlayer) > 70
		end,
	})
	addcreature("bearger", 'ground_pound', nil, 0, (20 + 0.6 / FRAMES) or 20, {
		point = "target", update = true, angle = 0 * DEGREES, dist = 1 + 2 * 3 })
	addcreature("mutatedbearger", 'ground_pound', nil, 0, (20 + 0.6 / FRAMES) or 20, {
		point = "target", update = true, angle = 0 * DEGREES, dist = 1 + 2 * 3 })
	addcreature("mutatedbearger", 'atk1', nil, 0, 32,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 60
			end,
		})
	addcreature("mutatedbearger", 'atk2', nil, 0, 32,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 60
			end,
		})
	addcreature("mutatedbearger", 'atk1a', nil, 0, 32,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 60
			end,
		})
	addcreature("mutatedbearger", 'butt_pre_L', nil, 0, 32,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) < 120
			end,
		})
	addcreature("mutatedbearger", 'butt_pre_R', nil, 0, 32,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) < 120
			end,
		})
	--[[ addcreature("mutatedbearger", 'butt_pre_L', nil, 0, 100,
    { point = "target", update = true, angle = 0, dist = 20 })
addcreature("mutatedbearger", 'butt_pre_R', nil, 0, 100,
    { point = "target", update = true, angle = 0, dist = 20 }) ]]
	addcreature("mutatedbearger", 'butt_pst', nil, 0, (2 + 0.6 / FRAMES - 10), --20
		{ point = "target", update = true, angle = 0, dist = 1 + 2 * 3 })
	addcreature("mutatedbearger", 'butt', nil, 0, 10,                       --butt 8f
		{ point = "target", update = true, angle = 0, dist = 1 + 2 * 3 })

	addcreature('dragonfly', 'atk', function(ent)
		local distance = math.sqrt(distsq(ent:GetPosition(), ThePlayer:GetPosition()))
		local min = ent:GetPhysicsRadius(0) + ThePlayer:GetPhysicsRadius(0)
		if ent.AnimState:GetBuild() == "dragonfly_fire_build" then return 17 end
		--print(distance - min < 1.4 and 17 or 0)
		return distance - min < 1.4 and 17 or 0
	end, 0, 15, nil, {
		idledodge = function(ent)
			if ent.AnimState:GetBuild() == "dragonfly_fire_build" then
				return 1000000
			end
			--if build == "dragonfly_fire_build" then return 1000000 end
			local distance = math.sqrt(distsq(ent:GetPosition(), ThePlayer:GetPosition()))
			local min = ent:GetPhysicsRadius(0) + ThePlayer:GetPhysicsRadius(0)
			if distance - min < 1.4 then
				return calculate(ent, 95, 120, true, HitAndRun.targetanimtable.dragonfly[1]) --112
				--4 he 3
			end
			return 1000000
		end,
		breakdodgefn = function(ent)
			if ENT_util:CheckDebugString(ent, 'sleep_loop', 'hit_ground', 'vomit', 'hit_large') then
				return true
			end
		end,
		combat_offset = function(dragon)
			return dragon.AnimState:GetBuild() == "dragonfly_fire_build" and 2 or 1
		end,

	})
	addcreature('dragonfly', 'taunt_pre', calculate, 0, 18 + 2, {
		point = "target", update = true, angle = 0 * DEGREES, dist = 1.5 + 2 * 2 + 1 })
	addcreature('dragonfly', 'taunt', nil, 0, 20 + 0.6 / FRAMES, {
		point = "target", update = true, angle = 0 * DEGREES, dist = 1.5 + 2 * 2 + 1 })
	addcreature("klaus", 'attack_doubleclaw', nil, 0, 26, nil, { combat_scale = 4 / 3 })
	addcreature("klaus", 'attack_chomp', nil, 10 - walk_start_framge, 25 - walk_start_framge, {
		point = "target",
		update = true,
		angle = 0 * DEGREES,
		dist = 0
	})
	addcreature("klaus", 'attack_chomp', nil, 26 - walk_start_framge, 49 or 35, nil, { combat_scale = 4 / 3 })
	addcreature("leif", 'atk', calculate, 0, 25)     --24
	addcreature("leif_sparse", 'atk', calculate, 0, 25) --SetRange(3)
	addcreature('stalker', 'attack', calculate, 0, 32,
		{ point = "target", update = true, angle = 0, extradist = 1.4 })
	addcreature('stalker', 'spikes', calculate, 0, 51,
		{ point = "target", update = true, angle = 0, extradist = 1.4 })
	addcreature('stalker', 'attack1', calculate, 0, 25,
		{ point = "target", update = true, angle = 0, extradist = 1.4 })
	copy('stalker_atrium', 'stalker')
	copy('stalker_forest', 'stalker')

	--kura添加
	addcreature('knight_nightmare', 'atk', calculate, 0, 17, nil, {
		combat_offset = 0.25,
	}) --发条骑士
	addcreature('knight', 'atk', calculate, 0, 17, nil, {
		combat_offset = 0.25,
	})                                          --地上发条骑士
	addcreature('pigman', 'atk', calculate, 0, 13) --猪人
	addcreature('pigman', 'idle_angry', nil, 0, 20)
	addcreature('pigman', 'counter_atk', nil, 0, 9 * special_mod_anim_mult, { mod_anim = true, })
	copy('pigguard', 'pigman')
	addcreature('moonpig', 'were_atk_pre', calculate, 0, 10) --疯猪
	addcreature('moonpig', 'were_atk', nil, 0, 2)
	addcreature('merm', 'atk', calculate, 0, 13)          --鱼人
	addcreature('mermguard', 'atk', calculate, 0, 13)     --鱼人守卫
	addcreature('bunnyman', 'atk', calculate, 0, 13)      --兔人
	addcreature('rabbitkingminion_bunnyman', 'atk', nil, 0, 13)
	addcreature('lordfruitfly', 'atk', calculate, 0, 8)   --果蝇王
	addcreature('koalefant_summer', 'atk', calculate, 0, 10) --红考拉象
	addcreature('koalefant_winter', 'atk', calculate, 0, 10) --蓝考拉象


	--接下来是我加了
	addcreature('moose', 'atk', calculate, 0, 20)
	addcreature('moose', 'hopatk', nil, 30, 42,
		{ update = false, angle = 90 * DEGREES, dist = 2 })
	addcreature('moose', 'hopatk_loop', nil, 0, 42)
	addcreature('malbatross', 'atk', calculate, 0, 29)
	addcreature('fused_shadeling', 'attack', calculate, 0, 14)
	addcreature('frog', 'atk', nil, 0, 8)
	addcreature('frog', 'atk_pre', calculate, 0, 22) --18
	addcreature('lunarfrog', 'atk', nil, 0, 8)
	addcreature('lunarfrog', 'atk_pre', calculate, 0, 22)
	addcreature('worm', 'atk', calculate, 0, 25)
	addcreature('yots_worm', 'atk', calculate, 0, 25)
	addcreature('spiderqueen', 'atk', calculate, 0, 28)
	addcreature('fruitdragon', 'attack', calculate, 0, 22, nil,
		{ combat_offset = TUNING.FRUITDRAGON.HIT_RANGE - TUNING.FRUITDRAGON.ATTACK_RANGE })
	copy('wormwood_fruitdragon', 'fruitdragon')
	addcreature('catcoon', 'atk', nil, 0, 16)
	copy('ticoon', 'catcoon')
	addcreature('daywalker', 'atk_slam_pre', nil, 10, 30,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 })
	addcreature('daywalker', 'atk_slam', nil, 0, 10,
		{ point = "target", update = false, angle = 90 * DEGREES, dist = 2 })
	addcreature('daywalker', 'run_pre', nil, 0, 30,
		{ update = false, angle = 80 * DEGREES, dist = 4, }, { checkatktag = true })
	addcreature('daywalker', 'run_loop', nil, 0, 30,
		{ update = true, angle = 0 * DEGREES, dist = 8, }, {})
	addcreature('daywalker', 'atk3', nil, 0, 12,
		{ point = "target", update = true, angle = 80 * DEGREES, dist = 5, })
	addcreature('chest_mimic_revealed', 'attack', nil, 0, 18)
	addcreature('fruitfly', 'atk', nil, 0, 8)
	addcreature('merm_shadow', 'atk', calculate, 0, 13)
	addcreature('merm_lunar', 'atk', calculate, 0, 13)
	addcreature('shadowthrall_horns', 'slap', nil, 0, 42)
	addcreature('shadowthrall_horns', 'jump', nil, 0, 30,
		{ point = "target", update = false, angle = 180 * DEGREES, dist = 2 })
	addcreature('shadowthrall_wings', 'cast', nil, 23, 100,
		{ point = "target", update = false, angle = 120 * DEGREES, dist = 2 })
	addcreature('eyeplant', 'atk', calculate, 0, 14)
	addcreature('hound_common', 'atk_pre', calculate, 0, 16)
	addcreature('hound_common', 'atk', nil, 0, 2)
	copy('hound', 'hound_common')
	copy('firehound', 'hound_common')
	copy('icehound', 'hound_common')
	copy('moonhound', 'hound_common')
	copy('clayhound', 'hound_common')
	copy('mutatedhound', 'hound_common')
	copy('hedgehound', 'hound_common')
	copy('warglet', 'hound_common')
	addcreature('otter', 'bite', calculate, 0, 15)
	addcreature('molebat', 'attack', calculate, 0, 10)
	addcreature('eyeofterror_mini', 'atk_pre', calculate, 0, 14,
		{ point = "target", update = true, })
	addcreature('eyeofterror_mini', 'atk', nil, 0, 4,
		{ point = "target", update = true, })
	-- addcreature('warg', 'atk', nil, 0, 11)
	-- copy('claywarg', 'warg')
	-- copy('gingerbreadwarg', 'warg')
	-- copy('mutatedwarg', 'warg')
	--addcreature('player_hosted', 'punch', nil, 0, 6)
	addcreature('crabking_claw', 'atk', nil, 0, 24)
	addcreature('ruinsnightmare', 'atk_walk_pre', nil, 0, 16)
	addcreature('ruinsnightmare', 'atk_pre', nil, 0, 16)
	addcreature('ruinsnightmare', 'atk', nil, 0, 10)
	addcreature('slurtle', 'atk', nil, 0, 10)

	-- addcreature('prime_mate', 'atk', nil, 0, 9)
	-- addcreature('prime_mate', 'atk_weapon', nil, 0, 9)
	addcreature('shark', 'attack', nil, 0, 26)
	addcreature('powder_monkey', 'unequipped_atk', nil, 0, 14)
	addcreature('powder_monkey', 'atk', nil, 0, 14)
	addcreature('oceanhorror', 'atk_pre', calculate, 0, 17)
	addcreature('oceanhorror', 'atk', nil, 0, 17 - 10)
	addcreature('spat', 'snot_pre', nil, 0, 27 + 4,
		{ point = "target", update = true, angle = 180 * DEGREES, dist = 2 })
	addcreature('spat', 'snot', nil, 0, 30,
		{ point = "target", update = true, angle = 180 * DEGREES, dist = 2 })
	addcreature('crabking_mob', 'atk1', calculate, 0, 18)
	copy('crabking_mob_knight', 'crabking_mob')
	addcreature('deer', 'atk', calculate, 0, 12)
	copy('deer_red', 'deer')
	copy('deer_blue', 'deer')
	addcreature('daywalker2', 'atk_object', nil, 0, 16,
		{ point = "target", update = true, angle = 0 * DEGREES, dist = 7 }) --1, 4.5
	-- addcreature('daywalker2', 'laser_pre', calculate, 0, 36 + 5,
	--     { point = "target", update = true, angle = 0 * DEGREES, dist = 11 })
	-- addcreature('daywalker2', 'laser_pst', nil, 0, 5 + 5,
	--     { point = "target", update = true, angle = 0 * DEGREES, dist = 11 })
	addcreature('archive_centipede', 'atk', calculate, 0, 9)
	addcreature('archive_centipede', 'atk_aoe', calculate, 0, 25,
		{ point = "target", update = true, angle = 0 * DEGREES, extradist = 1 })
	addcreature('squid', 'attack', nil, 0, 26)
	addcreature('snurtle', 'atk', calculate, 0, 10)
	addcreature('bat', 'atk', calculate, 0, 11)
	addcreature('smallbird', 'atk', calculate, 0, 12)
	addcreature('mermguard_lunar', 'atk', calculate, 0, 13)
	addcreature('mermguard_shadow', 'atk', calculate, 0, 13)
	addcreature('beeguard', 'atk', calculate, 0, 13)
	makeNoUsed('beequeen')
	makeNoUsed('crabking')
	makeNoUsed('sharkboi')
	makeNoUsed('rook')
	makeNoUsed('sandspike')
	makeNoUsed('bird_mutant')
	makeNoUsed('bird_mutant_spitter')
	makeNoUsed('prime_mate')
	addcreature('penguin', 'atk', calculate, 0, 8)
	copy('mutated_penguin', 'penguin')
	local alterguardian_phase1_dodge1 = {
		point = "target",
		update = true,
		angle = 0,
		dist = TUNING
			.ALTERGUARDIAN_PHASE1_AOERANGE + 0.7
	}
	addcreature('alterguardian_phase1', 'tantrum_pre', calculate, 0, 26, alterguardian_phase1_dodge1)
	addcreature('alterguardian_phase1', 'tantrum_loop', nil, 0, 20, alterguardian_phase1_dodge1)
	addcreature('alterguardian_phase1', 'tantrum_pst', nil, 0, 8, alterguardian_phase1_dodge1)
	addcreature('alterguardian_phase1', 'roll_pre', nil, 20, 51,
		{ point = "target", update = true, angle = -90 * DEGREES, dist = 4 })
	addcreature('alterguardian_phase1', 'roll_loop', nil, 0, 100,
		{
			point = "player",
			update = true,
			angle = function(target)
				if ENT_util:GetAngle(target, ThePlayer) > 90 then
					return 0 * DEGREES
				end
				return 90 * DEGREES
			end,
			dist = function(target)
				if ENT_util:GetAngle(target, ThePlayer) > 90 then
					return math.sqrt(distsq(target:GetPosition(), ThePlayer:GetPosition())) - 10
				end
				return 4
			end,
		})
	addcreature('alterguardian_phase1', 'roll_pst', nil, 0, 18, alterguardian_phase1_dodge1)
	copy('alterguardian_phase1_lunarrift', 'alterguardian_phase1')
	local a_p_2_1, a_p_2_2 = 18, 4.5
	addcreature('alterguardian_phase2', 'attk_spin_pre', nil, 0, 38,
		{ point = "target", update = true, angle = 0 * DEGREES, dist = 20 })
	addcreature('alterguardian_phase2', 'attk_spin_loop', nil, 0, 100,
		{ point = "target", update = true, angle = 0 * DEGREES, dist = 20 })
	addcreature('alterguardian_phase2', 'attk_spin_pst', nil, 0, 10,
		{ point = "target", update = true, angle = 0 * DEGREES, dist = 6 })
	addcreature('alterguardian_phase2', 'attk_stab_pre', calculate, 0, 28, nil, { combat_offset = a_p_2_2 - a_p_2_1 })
	-- Summon/projectile movement is owned by the gap route, never a 40-unit retreat.
	addcreature('alterguardian_phase2', 'attk_chop', calculate, 0, 23, nil, { combat_offset = a_p_2_2 - a_p_2_1 })

	addcreature('alterguardian_phase3', 'attk_stab2_pre', nil, 0, 100, nil, { combat_offset = 7 })
	addcreature('alterguardian_phase3', 'attk_stab2_loop', nil, 0, 100, nil, { combat_offset = 7 }) --20
	addcreature('alterguardian_phase3', 'attk_stab', calculate, 0, 45, nil,
		{
			combat_offset = 2 - 14,
			calculate_offset = 1,
			breakdodgefn = function(ent)
				return HitAndRun.p_range == 4 and HitAndRun.distance > 3
			end,
			_b = 29,
		})
	local SECOND_BLAST_TIME = 28
	addcreature('alterguardian_phase3', 'attk_beam', nil, 0, 21,
		{
			point = "target",
			update = true,
			angle = 0 * DEGREES,
			dist = 10,
		})
	addcreature('alterguardian_phase3', 'attk_beam', nil, 21, 35 + SECOND_BLAST_TIME,
		{
			point = "player",
			update = false,
			angle = 90 * DEGREES,
			dist = 2,
		})
	addcreature('alterguardian_phase3', 'attk_swipe', nil, 0, 21,
		{
			point = "target",
			update = true,
			angle = 0 * DEGREES,
			dist = 10,
		})
	addcreature('alterguardian_phase3', 'attk_swipe', nil, 21, 37 + SECOND_BLAST_TIME,
		{
			point = "player",
			update = false,
			angle = 0 * DEGREES,
			dist = -2,
		})

	addcreature('alterguardian_phase4_lunarrift', 'dash_pre', nil, 0, 100,
		{
			point = "target",
			update = true,
			angle = 0 * DEGREES,
			dist = 12,
		})
	addcreature('alterguardian_phase4_lunarrift', 'dash_loop', nil, 0, 100,
		{
			point = "player",
			update = true,
			angle = 135 * DEGREES,
			dist = 4,
		}, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 145
			end,
		})
	addcreature('alterguardian_phase4_lunarrift', 'slam', calculate, 0, 44, nil, { combat_offset = 4 })
	addcreature('alterguardian_phase4_lunarrift', 'slam', nil, 44, 77, nil, { combat_offset = 4 })

	addcreature('wagboss_robot', 'atk_squish', calculate, 0, 27, nil, {})
	addcreature('wagboss_robot', 'atk_squish', nil, 27, 30, nil, {})
	addcreature('wagboss_robot', 'taunt2_loop', calculate, 0, 25, nil, {})
	addcreature('wagboss_robot', 'taunt2_loop', nil, 25, 32, nil, {})
	--atk_leap
	addcreature('wagboss_robot', 'atk_leap_pre', nil, 55, 62, nil, { update = false, dist = -8, legacypos = true }) --0 62
	addcreature('wagboss_robot', 'atk_leap', nil, 0, 100, nil, { update = false, dist = -8, legacypos = true })
	addcreature('wagboss_robot', 'atk_leap_pst', nil, 0, 7, nil, { update = false, dist = -8 })                  --0 60
	--atk_missile
	addcreature('wagboss_robot', 'atk_missile_pre1', nil, 0, 100, nil, {
		dist = 20,
	})
	addcreature('wagboss_robot', 'atk_missile_pre2', nil, 0, 100, nil, { dist = 20 })
	addcreature('wagboss_robot', 'atk_missile_hit', nil, 0, 100, nil, { dist = 20 })
	addcreature('wagboss_robot', 'atk_missile_idle', nil, 0, 100, nil, { dist = 20 })
	addcreature('wagboss_robot', 'atk_missile', nil, 0, 100, nil, { dist = 20 })
	addcreature('wagboss_robot', 'atk_missile_pst', nil, 0, 100, nil, {
		avoid_break = function(target)
			return FindEntity(target, 20, function(ent)
				return ent.prefab == "wagboss_missile"
			end)
		end,
		dist = 20
	})
	--atk_signal_loop atk_signal_pre
	addcreature('wagboss_robot', 'atk_signal_pre', nil, 0, 100, nil, { angle = 40 * DEGREES, dist = 20 })
	addcreature('wagboss_robot', 'atk_signal_loop', nil, 0, 100, nil, { angle = 40 * DEGREES, dist = 20 })
	--
	addcreature('eyeofterror', 'charge_pre', nil, 0, 25,
		{
			point = "target",
			update = true,
			angle = 0 * DEGREES,
			dist = 8,
		})
	addcreature('eyeofterror', 'charge_pre', nil, 25, 33,
		{
			point = "player",
			update = false,
			angle = 90 * DEGREES,
			dist = 4,
		})
	addcreature('eyeofterror', 'charge_loop', nil, 0, 100,
		{
			point = "player",
			update = true,
			angle = 90 * DEGREES,
			dist = 4,
		}, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 100
			end,
		})
	addcreature('eyeofterror', 'charge_pst', nil, 0, 100,
		{
			point = "target",
			update = false,
			angle = -45 * DEGREES,
			dist = 8,
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 100
			end,
		})
	addcreature('eyeofterror', 'chomp', calculate, 0, 25)
	copy('twinofterror1', 'eyeofterror')
	copy('twinofterror2', 'eyeofterror')

	--
	addcreature('shadowthrall_hands', 'run_loop', nil, 0, 100,
		{ update = false, angle = 80 * DEGREES, dist = 4, }, {
			breakdodgefn = function(ent)
				return ENT_util:GetAngle(ent, ThePlayer) > 100
			end,
		})
	addcreature('shadowthrall_hands', 'run_pre', nil, 0, 100,
		{ update = false, angle = 80 * DEGREES, dist = 4, })
	addcreature('mosquito', 'atk', calculate, 0, 15)
	addcreature('bee', 'atk', calculate, 0, 15)
	copy('killerbee', 'bee')
	addcreature('grassgator', 'atk', calculate, 0, 10)
	addcreature('babybeefalo', 'atk', calculate, 0, 10)
	addcreature('spider_water', 'atk', calculate, 0, 16)
	makeNoUsed('walrus')
	makeNoUsed('monkey')
	makeNoUsed('gestalt_guard_evolved')
	addcreature('perd', 'atk', calculate, 0, 20)
	makeNoUsed('lavae')
	makeNoUsed('lavae_pet')
	makeNoUsed('bishop_nightmare')
	makeNoUsed('bishop')
	makeNoUsed('mutatedwarg')
	makeNoUsed('warg')
	makeNoUsed('rook_nightmare')
	makeNoUsed('slurper')
	addcreature('spider_common', 'atk', calculate, 0, 25)
	addcreature('spider_common', 'warrior_atk', nil, 0, 19, { angle = 120 * DEGREES, update = false })
	addcreature('spider_moon', 'atk', calculate, 0, 25, nil, { combat_offset = -3 })
	addcreature('spider_moon', 'warrior_atk', nil, 0, 19, { angle = 120 * DEGREES, update = false })
	addcreature('spider_spitter', 'atk', calculate, 0, 25, nil, { combat_offset = -2 })
	--addcreature('spider_spitter', 'spit', nil, 0, 21 or 33, nil, { dist = 8, })
	--addcreature('spider_spitter', 'spit', nil, 21, 33, nil, { point = "player", dist = 4, })
	copy('spider_dropper', 'spider_moon')
	copy('spider_warrior', 'spider_moon')
	copy('spider_hider', 'spider_common')
	copy('spider_healer', 'spider_common')

	makeNoUsed('crawlinghorror')
	makeNoUsed('lunar_grazer')
	makeNoUsed('terrorbeak')
	makeNoUsed('mutateddeerclops')
	addcreature('shadowthrall_mouth', 'bite_pre', nil, 0, 100)
	addcreature('shadowthrall_mouth', 'bite_loop', nil, 0, 100)
	addcreature('shadowthrall_mouth', 'land', nil, 0, 100)
	addcreature('shadowthrall_mouth', 'leap', nil, 0, 100)
	addcreature('toadstool', 'attack_pound_pre', calculate, 0, 45, nil, { combatdist = 7.5 })
	addcreature('toadstool', 'attack_pound_loop', nil, 0, 45, nil, { combatdist = 7.5 })
	copy('toadstool_dark', 'toadstool')
	addcreature('shadow_knight', 'atk_pre', nil, 0, 100, nil,
		{ combat_scale = 2 })
	addcreature('shadow_knight', 'atk', nil, 0, 3, nil,
		{ combat_scale = 2 })
	addcreature('shadow_knight', 'atk_plus', nil, 0, 5, nil,
		{ combat_scale = 2 })


	addcreature('beefalo', 'atk', calculate, 0, 10, nil, { calculate_offset = 0.3 })
	addcreature('lightninggoat', 'atk', calculate, 0, 12, nil, { calculate_offset = 0.2 })

	addcreature('lavae', 'atk_pre', nil, 0, 15,
		{ point = "player", update = false, angle = 90 * DEGREES, })
	addcreature('lavae', 'atk', nil, 0, 6)

	--
	addcreature('buzzard', 'atk', calculate, 0, 15)
	addcreature('mutatedbuzzard_gestalt', 'atk', calculate, 0, 15, nil, { combat_offset = -8 })
	addcreature('mutatedbuzzard_gestalt', 'atk_flame_pre', nil, 0, 100)
	addcreature('mutatedbuzzard_gestalt', 'atk_flame_loop', nil, 0, 100)
	--[[addcreature('mutatedbuzzard_gestalt', 'atk_flame_pst', nil, 0, 100)]]
	--atk_flame_pre atk_flame_loop atk_flame_pst
	addcreature('bernie_big', 'atk', calculate, 0, 23, { extradist = 0.25 })
	do --棱镜
		copy('siving_foenix', 'buzzard')
		copy('siving_moenix', 'buzzard')
		--[[  addcreature('elecarmet', 'attack1', calculate, 0, 12, nil, {
        idledodge = function(ent)
            return (HitAndRun.PC:CanLocomote() and 70 or 80) 
        end,
    })
    addcreature('elecarmet', 'attack2', nil, 0, 3)
    addcreature('elecarmet', 'attack3', calculate, 0, 7)
    addcreature('elecarmet', 'attack4', nil, 0, 24)

    addcreature('elecarmet', 'taunt', calculate, 0, 13) ]]
	end
	do --勋章
		addcreature('medal_naughty_krampus', 'atk_pre', nil, 0, 18)
		addcreature('medal_rage_krampus', 'atk_pre', calculate, 0, 18)
		addcreature('medal_rage_krampus', 'atk', nil, 0, 3 - safeadvance)
	end
	do --永不妥协
		addcreature('alpha_lightninggoat', 'atk', calculate, 0, 12)
		addcreature('alpha_lightninggoat', 'lightcharge_atk_loop', nil, 0, 100)
		addcreature('alpha_lightninggoat', 'stompy', nil, 0, 100, { dist = 6 + 2 })
		addcreature('alpha_lightninggoat', 'stompy_loop', nil, 0, 100, { dist = 6 + 2 })

		addcreature('ancient_trepidation', 'attack', calculate, 0, 12 / 12 * 16)
		addcreature('ancient_trepidation', 'attack', nil, 12 / 12 * 16, 25 / 12 * 16)

		addcreature('ancient_trepidation_arm', 'atk_pre', calculate, 0, 24 * special_mod_anim_mult, nil,
			{ mod_anim = true })
		addcreature('ancient_trepidation_arm', 'atk_loop', nil, 0, 7 * special_mod_anim_mult, nil, { mod_anim = true })

		addcreature('bight', 'atk', calculate, 0, math.ceil(26 * special_mod_anim_mult), nil, { mod_anim = true })

		addcreature('creepingfear', 'atk_pre', calculate, 0, math.ceil(16 * special_mod_anim_mult), nil,
			{ extradist = 1, mod_anim = true })
		addcreature('creepingfear', 'atk', nil, 0, math.ceil(4 * special_mod_anim_mult), nil,
			{ extradist = 1, mod_anim = true })
		copy('eyeofterror_mini_ally', 'eyeofterror')
		addcreature('hoodedwidow', 'atk', calculate, 0, 28 * special_mod_anim_mult, nil, { mod_anim = true })
		addcreature('hoodedwidow', 'leap', nil, 0, 20 * special_mod_anim_mult,
			{ update = false, angle = 0, dist = 0 }, { mod_anim = true }) -- range  5
		addcreature('hoodedwidow', 'shoot_pre', nil, 0, 47 * special_mod_anim_mult,
			{ dist = 15 + 5 }, { mod_anim = true })
		addcreature('hoodedwidow', 'shoot_loop', nil, 0, 32,
			{ dist = 15 + 5 })
		addcreature('hoodedwidow', 'shoot_pst', nil, 0, 16,
			{ dist = 15 + 5 })

		addcreature('knook', 'atk_pre', calculate, 0, 36 + 7 * special_mod_anim_mult,
			{}, { mod_anim = true })
		addcreature('knook', 'atk', nil, 0, 7 * special_mod_anim_mult,
			{}, { mod_anim = true })
		addcreature('knook', 'bigjump', nil, 0, 15 * special_mod_anim_mult,
			{}, { mod_anim = true })

		copy('lavae2', 'lavae')

		addcreature('lureplague_rat', 'atk', calculate, 0, 7 * special_mod_anim_mult,
			{}, { mod_anim = true })

		addcreature('mock_dragonfly', 'taunt_pre', nil, 0, 18 + 2, {
			point = "target", update = true, angle = 0 * DEGREES })
		addcreature('mock_dragonfly', 'taunt', nil, 0, 20 + 0.6 / FRAMES, {
			point = "target", update = true, angle = 0 * DEGREES })
		copy('mothergoose', 'moose')

		addcreature('pied_rat', 'atk', calculate, 0, 18 * special_mod_anim_mult,
			{ dist = 5 }, { mod_anim = true })
		copy('pigking_pigguard', 'pigman')

		addcreature('rneskeleton', 'atk_pre', calculate, 0, 10)
		addcreature('rneskeleton', 'atk', nil, 0, 4)

		addcreature('roship', 'atk', nil, 10, 100,
			{
				avoid_break = function(target)
					return FindEntity(ThePlayer, 10, function(ent)
						return ent.prefab == "roship_projectile"
					end)
				end,
				angle = 120 * DEGREES,
				dist = 10,
				update = false,
			})

		addcreature('um_scorpion', 'tail', calculate, 0, 20 * special_mod_anim_mult,
			{}, { mod_anim = true })
		addcreature('um_scorpion', 'atk', calculate, 0, 19 * special_mod_anim_mult,
			{
				angle = function(ent)
					return ent.replica.combat:GetAttackRangeWithWeapon() >= 10 and 120 * DEGREES or 0
				end,
				update = false,
			}, { mod_anim = true })
		copy('shockworm', 'worm')
		copy('viperworm', 'worm')
		addcreature('vampirebat', 'atk', calculate, 0, 14)

		addcreature('snapdragon', 'atk_pre', calculate, 0, 15, { mod_anim = true })
		addcreature('snapdragon', 'atk', nil, 0, 3)

		addcreature('snapperturtle', 'atk', calculate, 0, 10, { mod_anim = true })
		addcreature('snapperturtlebaby', 'atk', calculate, 0, 10, { mod_anim = true })

		addcreature('snowmong', 'action', calculate, 0, 10, { mod_anim = true })
		copy('spider_trapdoor', 'spider_common')

		addcreature('stumpling', 'attack', calculate, 0, 26 * special_mod_anim_mult,
			{ extradist = 2, mod_anim = true, _b = 10 })

		addcreature('swilson', 'atk', calculate, 0, 17, { mod_anim = true, _b = 13 })
		copy('lightninghound', 'hound_common')
		copy('glacialhound', 'hound_common')
		copy('sporehound', 'hound_common')
		copy('rnehound', 'hound_common')
		addcreature('magmahound', 'atk_pre', calculate, 0, 16)
		addcreature('magmahound', 'atk_magma', nil, 0, 2)
	end
	do
		addcreature('bishop', 'atk2_pre', nil, 0, 100, nil, {
			point = "player", update = true, angle = 90 * DEGREES, dist = 4
		})
		addcreature('bishop', 'atk2_loop', nil, 0, 100, nil, {
			point = "player", update = true, angle = 90 * DEGREES, dist = 4
		})
		addcreature('bishop', 'atk2_pst', nil, 0, 8, nil, {
			point = "player", update = true, angle = 90 * DEGREES, dist = 4
		})
		copy('bishop_nightmare', 'bishop')

		addcreature('cave_vent_mite', 'atk', calculate, 0, 20)
	end
	do --一些接口和debug工具
		function GLOBAL.HitAndRun_AddCreature(prefab, atkanim, atk_frame_calculate, atk_start_frame, atk_stop_frame,
											  dodgeaimpos,
											  data, ...)
			addcreature(prefab, atkanim, atk_frame_calculate, atk_start_frame, atk_stop_frame, dodgeaimpos, data, ...)
		end

		local str = ""
		function GLOBAL.HitAndRun_CalculateAtkAnim(prefab, line)
			if TheWorld and TheWorld.ismastersim then
				local a, b = pcall(function()
					local target = SpawnPrefab(prefab)
					target:DoTaskInTime(0, function()
						if target.components.combat then
							target.components.combat:SetTarget(ThePlayer)
						end
						--[[ target:PushEvent("doattack", { target = target }) ]]
					end)
					if ThePlayer then
						local x, y, z = ThePlayer.Transform:GetWorldPosition()
						target.Transform:SetPosition(x, y, z)
					end
					if target.components.combat then
						target.components.combat.DoAttack = function()
							print("分析目标攻击动画为:")
							local a, b, c, d, e, f = target.AnimState:GetHistoryData()
							print(prefab, b, c)
							local extradist = target.components.combat.attackrange - target.components.combat
								.attackrange
							if extradist ~= 0 then
								str = str ..
									string.format(
										" addcreaturedata('%s', { atkanim = '%s',  atk_stop_frame = %d , extradist = %d})\n",
										prefab, b, c, extradist)
							else
								str = str ..
									string.format(
										" addcreaturedata('%s', { atkanim = '%s',  atk_stop_frame = %d })\n",
										prefab, b, c)
							end
							if line then
								target:Remove()
							end
						end
					end
					target.persists = false
					target:DoTaskInTime(10, target.Remove)
				end
				)
				print(a, b)
			end
		end

		local HitAndRun_CalculateAtkAnim = GLOBAL.HitAndRun_CalculateAtkAnim
		function GLOBAL.HitAndRun_CalculateAllAtkAnim()
			for k, v in pairs(GLOBAL.Prefabs) do
				HitAndRun_CalculateAtkAnim(k, true)
			end
			TheWorld:DoTaskInTime(10, function()
				print("输出所有结果:\n")
				print(str)
				RW_util:SaveData(str, "HitAndRun_atkanim")
				str = ""
			end)
		end

		function GLOBAL.HitAndRun_CalculateScrapBookAtkAnim()
			local dataset = require("screens/redux/scrapbookdata")
			for prefab, v in pairs(GLOBAL.Prefabs) do
				if not HitAndRun.targetanimtable[prefab] and dataset[prefab] and dataset[prefab].health then
					HitAndRun_CalculateAtkAnim(prefab, true)
				end
			end
			TheWorld:DoTaskInTime(10, function()
				print("输出所有结果:\n")
				print(str)
				RW_util:SaveData(str, "HitAndRun_atkanim")
				str = ""
			end)
		end

		function GLOBAL.HitAndRun_CalculateAllModAtkAnim(modname)
			local mod = ModManager:GetMod(modname)
			for k, v in pairs(mod.Prefabs) do
				HitAndRun_CalculateAtkAnim(k, true)
			end
			TheWorld:DoTaskInTime(10, function()
				print("输出所有结果:\n")
				print(str)
				RW_util:SaveData(str, "HitAndRun_atkanim")
				str = ""
			end)
		end
	end
end
