MOD_util:CheckUtilsVersion(1.3)
--https://steamcommunity.com/sharedfiles/filedetails/?id=3014188454
MOD_util.fixrpc()
local ismmdx = MOD_util:Ismmdx()
local print = ismmdx and GLOBAL.print or function(...)
end
local testing = ismmdx and true
HitAndRun = {
	delay = ismmdx and 11 or GetModConfigData('hitandrun_delay') or 11,
	keyframe = ismmdx and 0 or GetModConfigData('hitandrun_keyframe') or 0,
	hitandrun_saveswitch = GetModConfigData("savedata_1"),
	walkway = ismmdx and 1 or GetModConfigData("walkway") or 1,
	walktime = GetModConfigData("walktime") or 0, --行走打断后的睡眠时间(控制人物走多远)
	shadowdodge = ismmdx and true or GetModConfigData("ceshi1") or false,
	dodgetest = GetModConfigData("ceshi2") or false,
	dt_runaway = GetModConfigData("dt_runaway") ~= false,
	targetmode = GetModConfigData("targetmode"),
	mousekey = ismmdx and MOUSEBUTTON_MIDDLE or GetModConfigData('mousekey') and MOUSEBUTTON_RIGHT or MOUSEBUTTON_MIDDLE,
	ctrl_key = ismmdx and KEY_LCTRL or MOD_util:GetKeyFromConfig("controlkey_1") or KEY_LCTRL,
	alt_key = ismmdx and KEY_LALT or MOD_util:GetKeyFromConfig("controlkey_2") or KEY_LALT,
	isadmin = TheNet:GetIsServerAdmin(),
	isserver = TheNet:GetIsServer(),
	highttarget_open = ismmdx and true or GetModConfigData("highttarget_open") or false,
	movementswitch = GetModConfigData("movementswitch") or false,
	priority_undermouse = ismmdx and true or GetModConfigData("priority_undermouse") or false,

	switchcut = GetModConfigData("switchcut") or false,
	force_suit_formod = GetModConfigData("force_suit_formod") or false,

	hitandrun_repeat_attack = GetModConfigData("hitandrun_repeat_attack") ~= false,
	allfirst = false,
	--
	testingmode = true,
}
HitAndRun.defaultstartkey = MOD_util:GetKeyFromConfig("Attack_key") or KEY_R
if ismmdx or true then
	GLOBAL.HitAndRun = HitAndRun
end
--初始化读取
HitAndRun.AutoAttackMonsterBlackList = RW_util:LoadData("AutoAttackMonsterBlackList") or {}
HitAndRun.SwitchItems = MOD_util:GetMOption("hitandrun_saveswitch", HitAndRun.hitandrun_saveswitch) and
	RW_util:LoadData("SwitchItems") or {}

modimport("HitAndRun/EntTable")
modimport("HitAndRun/PlayerAnim")
modimport("HitAndRun/SpecialEnt")
--选择范围内满足的目标
function HitAndRun:GetAttackTargets(range)
	local ppos = ThePlayer:GetPosition()
	local entity = TheSim:FindEntities(ppos.x, 0, ppos.z, range or 20, { "_combat" }) --第五个参数是不选的标签
	if entity then
		for key, value in ipairs(entity) do
			--如果按着ctrl_key就不管黑名单
			if HitAndRun.combat and
				(TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key))
					or not HitAndRun.AutoAttackMonsterBlackList[value.prefab])
				and not HitAndRun.combat:IsAlly(value) then
				HitAndRun.selected_ents[value] = true
			end
			--带着骨盔不会打影怪 除非按着CTRL
			if not TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) and ThePlayer:HasTag("shadowdominance") and HitAndRun.EntTable[value.prefab].isshadow then
				HitAndRun.selected_ents[value] = nil
			end
		end
	end
end

do --双切a部分
	--人物正在进行双切A
	function HitAndRun:DoubleSwitching()
		local activeitem = INV_util:GetActiveItem()
		return INV_util:GetHandsEquip()
			and activeitem and activeitem:HasTag('weapon')
	end

	--拿着枕头
	function HitAndRun:HoldingPillow()
		local hand = INV_util:GetHandsEquip()
		return hand and hand.prefab == 'handpillow_steelwool'
	end

	--人物超级双切，不拿在鼠标上的那种
	function HitAndRun:CanNoMouseDoubleSwitch()
		if HitAndRun.super_switch_prefab then
			local prefab = HitAndRun.super_switch_prefab
			if not HitAndRun.inv:GetActiveItem() and prefab and HitAndRun.inv:GetEquippedItem(EQUIPSLOTS.HANDS) and INV_util:FindInInventory(prefab) then
				return prefab
			end
		end
	end

	function HitAndRun:DoNoMouseDoubleSwitch()

	end
end
function HitAndRun:CanHitTarget(target, doer)
	local attacker = doer or ThePlayer
	local combat = attacker and attacker.replica
		and attacker.replica.combat
	if not combat then return end
	local weapon = combat:GetWeapon()
	if combat:CanExtinguishTarget(target, weapon) or
		combat:CanLightTarget(target, weapon) or
		(target.replica.combat ~= nil and target.replica.combat:CanBeAttacked(attacker)) then
		local range = HitAndRun:GetTargetCanHitRange(attacker, target) --0.5+2
		local offset = 0.10                                      --越小越近
		range = math.max(range + offset, 0)
		return distsq(target:GetPosition(), attacker:GetPosition()) <= range ^ 2
	end
end

--获取距离玩家最近选取的表的目标
function HitAndRun:GetClosestTarget()
	local mindistsq, target
	local player_pos = ThePlayer:GetPosition()
	--优先鼠标下的敌人
	if MOD_util:GetMOption("hitandrun_priority_undermouse", HitAndRun.priority_undermouse) then
		local undermouse = TheInput:GetWorldEntityUnderMouse()
		undermouse = undermouse and ENT_util:IsValid(undermouse) and HitAndRun.selected_ents[undermouse] and undermouse
		if undermouse then return undermouse end
	end
	--优先特殊的
	for ent, v in pairs(HitAndRun.selected_ents) do
		if ENT_util:IsValid(ent) and HitAndRun.SpecialEnt[ent.prefab] and HitAndRun.combat:CanTarget(ent) and HitAndRun:CanHitTarget(ent) then
			return ent
		end
	end
	--然后上个目标
	local lasttarget = HitAndRun.combat.classified.lastcombattarget:value()
	if not TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) and lasttarget then
		if HitAndRun.selected_ents[lasttarget] and ENT_util:IsValid(lasttarget) and HitAndRun.combat:CanTarget(lasttarget) and HitAndRun:CanHitTarget(lasttarget) then
			return lasttarget
		end
	end
	--最后距离最近的
	for ent, v in pairs(HitAndRun.selected_ents) do
		if ENT_util:IsValid(ent) and HitAndRun.combat:CanTarget(ent) then
			local curdistsq = player_pos:DistSq(ent:GetPosition())
			if not mindistsq or curdistsq < mindistsq then
				mindistsq = curdistsq
				target = ent
			end
		else
			HitAndRun.selected_ents[ent] = nil
		end
	end
	return target
end

do --走向和攻击函数
	local function doPredictwalk(x, z)
		SendRPCToServer(RPC.PredictWalking, x, z)
	end
    -- 仅紧急躲避使用完整预测会话；普通走A使用下方3014原版入口。
    local function emergencywalk(x,z)
        local pc=ThePlayer.components.playercontroller
        local platform,rx,rz=pc:GetPlatformRelativePosition(x,z)
        if RPC.PredictWalking then
            SendRPCToServer(RPC.PredictWalking,rx,rz,false,not HitAndRun.shadowself_predicting,platform,platform~=nil,nil,false)
            HitAndRun.shadowself_predicting=true
        end
        if not pc.IsBusy or not pc:IsBusy() then
            if pc:CanLocomote() then
                local action=BufferedAction(pc.inst,nil,ACTIONS.WALKTO,nil,Vector3(x,0,z))
                if not pc.ismastersim then
                    local function send() SendRPCToServer(RPC.LeftClick,ACTIONS.WALKTO.code,rx,rz,nil,true,pc:EncodeControlMods(),nil,nil,platform,platform~=nil) end
                    if pc.locomotor then action.preview_cb=send else action.non_preview_cb=send end
                end
                pc:DoAction(action)
            else
                SendRPCToServer(RPC.LeftClick,ACTIONS.WALKTO.code,rx,rz,nil,true,pc:EncodeControlMods(),nil,nil,platform,platform~=nil)
            end
        end
    end
    function HitAndRun:StopPredictWalk()
        if self.shadowself_predicting then
            if RPC.PredictWalking then SendRPCToServer(RPC.PredictWalking,nil,nil,nil,nil,nil,nil,nil,true) end
            if RPC.StopWalking then SendRPCToServer(RPC.StopWalking) end
            self.shadowself_predicting=nil
        end
    end
    function HitAndRun:DoPredictWalk(x,z) return emergencywalk(x,z) end


	function HitAndRun:_PredictWalk(pos)
		local animpos = pos
		local x, z = animpos.x, animpos.z
		doPredictwalk(x, z)
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, x, z)
		doPredictwalk(x, z)
	end

	--原地走位打断后摇
	function HitAndRun:PredictWalk(ppos, mpos, target)
		if HitAndRun.PC:CanLocomote() and not HitAndRun.PC.ismastersim then
			local animpos = POS_util:CalculateAimPos(ppos, mpos, 0, 0.5)
			local action = BufferedAction(HitAndRun.PC.inst, nil, ACTIONS.WALKTO, nil, animpos)
			HitAndRun.PC:DoAction(action)
		else
			if HitAndRun.isserver then
                local animpos=POS_util:CalculateAimPos(ThePlayer:GetPosition(),target:GetPosition(),0,.01)
                HitAndRun.PC:DoAction(BufferedAction(HitAndRun.PC.inst,nil,ACTIONS.WALKTO,nil,animpos))
			else
				HitAndRun:_PredictWalk(ThePlayer:GetPosition())
				--[[local animpos = POS_util:CalculateAimPos(ThePlayer:GetPosition(), target:GetPosition(), 0,
				 0.00001)
				SendRPCToServer(, animpos.x, animpos.z)]]
			end
		end
	end

	--攻击
	function HitAndRun:CloseAndAttack(target, force_force)
		if not target or not ThePlayer then return end
        HitAndRun:StopPredictWalk()
		local pos = target:GetPosition()
		local noforce = true
		if force_force then
			noforce = false
		end
		if ThePlayer:HasTag("weregoose") then
			SendRPCToServer(RPC.ControllerAttackButton, target, true, noforce)
		elseif ThePlayer.components.playercontroller:CanLocomote() and not ThePlayer.components.playercontroller.ismastersim then
			local act = BufferedAction(ThePlayer.components.playercontroller.inst, target, ACTIONS.ATTACK)
			if act ~= nil then
				act.preview_cb = function()
					SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, true, 10,
						nil, nil)
				end
				ThePlayer.components.playercontroller:DoAction(act)
			end
		else
			local activeitem = INV_util:GetActiveItem()
			local blowdart = HitAndRun.cannomouseatk
			if activeitem or blowdart then
				if blowdart or HitAndRun:DoubleSwitching() then
					SendRPCToServer(RPC.AttackButton, target, true, false)
				else
					SendRPCToServer(RPC.AttackButton, target, true, noforce)
				end
			else
				--SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, true, 10, true)

				SendRPCToServer(RPC.LeftClick, ACTIONS.ATTACK.code, pos.x, pos.z, target, nil, 10, noforce) --连打
			end
		end
	end

	--走向某个点
	function HitAndRun:WalkTo(startpos, stoppos, walkdistance, checkrange, rangecheck_ent, trydodging)
		local pmdistance = math.sqrt((startpos.x - stoppos.x) * (startpos.x - stoppos.x) +
			(startpos.z - stoppos.z) * (startpos.z - stoppos.z))
		local dx, dz = stoppos.x - startpos.x, stoppos.z - startpos.z
		if dx == 0 and dz == 0 then dx, dz = 1, 1 end
		if pmdistance == 0 then pmdistance = 0.1 end
		local fx, fz = startpos.x + walkdistance * dx / pmdistance, startpos.z + walkdistance * dz / pmdistance
		if checkrange then
			if distsq(HitAndRun.pos.x, HitAndRun.pos.z, fx, fz) > checkrange * checkrange then
				if trydodging and rangecheck_ent then
					return HitAndRun:PredictWalk(HitAndRun.ppos, rangecheck_ent:GetPosition(), rangecheck_ent)
				else
					return HitAndRun:WalkTo(startpos, HitAndRun.pos or stoppos, math.abs(walkdistance))
				end
			end
		end
		local x, z = fx, fz
		local ActiveItem = ThePlayer.replica.inventory:GetActiveItem()
		local playercontroller = ThePlayer.components.playercontroller
		if playercontroller:CanLocomote() then
			local action = BufferedAction(playercontroller.inst, nil, ACTIONS.WALKTO, nil,
				Vector3(x, 0, z))
			playercontroller:DoAction(action)
		else
			local platform, pos_x, pos_z = playercontroller:GetPlatformRelativePosition(x, z)
			SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pos_x, pos_z, ActiveItem, nil, nil,
				nil, nil, platform, platform ~= nil)
		end
	end

	function HitAndRun:PredictWalkTo(startpos, stoppos, walkdistance, checkrange, rangecheck_ent, trydodging)
		local pmdistance = math.sqrt((startpos.x - stoppos.x) * (startpos.x - stoppos.x) +
			(startpos.z - stoppos.z) * (startpos.z - stoppos.z))
		local dx, dz = stoppos.x - startpos.x, stoppos.z - startpos.z
		if dx == 0 and dz == 0 then dx, dz = 1, 1 end
		if pmdistance == 0 then pmdistance = 0.1 end
		local fx, fz = startpos.x + walkdistance * dx / pmdistance, startpos.z + walkdistance * dz / pmdistance
		if checkrange then
			if distsq(HitAndRun.pos.x, HitAndRun.pos.z, fx, fz) > checkrange * checkrange then
				if trydodging and rangecheck_ent then
					return HitAndRun:PredictWalk(HitAndRun.ppos, rangecheck_ent:GetPosition(), rangecheck_ent)
				else
					return HitAndRun:PredictWalkTo(startpos, HitAndRun.pos or stoppos, math.abs(walkdistance))
				end
			end
		end
		local x, z = fx, fz
		HitAndRun:_PredictWalk(Vector3(x, 0, z))
	end
end
do --功能性函数
	function HitAndRun:holdLegionShield(hand)
		return TUNING.Shieldthread and hand and hand:HasTag('canshieldatk')
	end

	--判断人物打中了吗
	function HitAndRun:IsHitingFrame(number, target, checkmod)
		local anim = ENT_util:GetAnimation(ThePlayer)
		local pin = TheNet:GetPing()
		local shadowcreaturedelay = pin ~= 0 and HitAndRun.combat:GetAttackRangeWithWeapon() == 4 and
			not HitAndRun.PC:CanLocomote()
			and HitAndRun.EntTable[target.prefab].isshadow and -math.floor(pin / (1000 * FRAMES) + 0.5) or 0

		local v = anim and HitAndRun.PlayerAnim[anim]
		local ismastersim = TheWorld.ismastersim
		if v and (ThePlayer.AnimState:GetCurrentAnimationFrame() or 0) >= (ENT_util:FnOrNum(v.anim, target) or 0) + shadowcreaturedelay + (number or 0)
			+ (ismastersim and 1 or 0) then
			if v.require_attack_tag then
				if not ThePlayer:HasTag("attack") then
					return false
				end
			end
			if not v.cancelfn or not v.cancelfn() then
				if v.extrafunction then
					v.extrafunction()
				end
				return true
			end
		elseif not v and checkmod then --我没记录过的anim？
			if string.find(ThePlayer.entity:GetDebugString(), "../mods/") then
				if HitAndRun.performed_action then
					HitAndRun.performed_action = false
					return true
				end
			end
		end
	end

	local lastupdatetime = -100
	function HitAndRun:UpdateMyPing()
		if GetTime() - lastupdatetime > 10 then
			lastupdatetime = GetTime()
			HitAndRun.ping = TheNet:GetPing()
		end
		return HitAndRun.ping or TheNet:GetPing()
	end
end
do --走A部分的函数
	local function IsAcceleratedAttack()
		local period = HitAndRun.combat and HitAndRun.combat:MinAttackPeriod()
		local normal_period = TUNING.WILSON_ATTACK_PERIOD or 12 * FRAMES
		return period ~= nil and period > 0 and period < normal_period
	end

	--循环开始前获得需要用的参数
	function HitAndRun:PreTheLoop()
		HitAndRun.p_range = HitAndRun.combat:GetAttackRangeWithWeapon()
		HitAndRun.activeitem, HitAndRun.hand = HitAndRun.inv:GetActiveItem(),
			HitAndRun.inv:GetEquippedItem(EQUIPSLOTS.HANDS)
		HitAndRun.pos, HitAndRun.ppos = HitAndRun.ent:GetPosition(), ThePlayer:GetPosition()
		HitAndRun.distance = math.sqrt((HitAndRun.ppos.x - HitAndRun.pos.x) ^ 2 +
			(HitAndRun.ppos.z - HitAndRun.pos.z) ^ 2)
		HitAndRun.canhit = HitAndRun:CanHitTarget(HitAndRun.ent)
	end

	--判断关键时机来执行打断攻击
	--第一刀判断+步进判断
	function HitAndRun:IsKeyFrame()
        if ThePlayer.sg and ThePlayer.sg.HasStateTag and ThePlayer.sg:HasStateTag("abouttoattack") then return false end
		local allfirst = MOD_util:GetMOption("hitandrun_allfirst", HitAndRun.allfirst)
		if HitAndRun.guid == 0 or allfirst then
			if HitAndRun.cannomouseatk then
				if HitAndRun.atktag_tick and HitAndRun.atktag_tick >= (5 + (TheWorld.ismastersim and 2 or 0)) then
					return true
				end
			elseif HitAndRun:DoubleSwitching() then
				if not HitAndRun:HoldingPillow() then
					if HitAndRun.atktag_tick and HitAndRun.atktag_tick >= (5 + (TheWorld.ismastersim and 2 or 0)) then
						return true
					end
				else
					return HitAndRun:IsHitingFrame(
						MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe) +
						(HitAndRun.PC:CanLocomote() and 1 or 0),
						HitAndRun.ent, true)
				end
			end
			if HitAndRun.performed_action then
				local ishitframe = HitAndRun:IsHitingFrame(-2,
					HitAndRun.ent, true)
				HitAndRun.performed_action = false
				return ishitframe
			end

			if HitAndRun:IsHitingFrame(
					MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe) + (HitAndRun.PC:CanLocomote() and 1 or 0) + 1,
					HitAndRun.ent, true) then
				return true
			end
		else
			return HitAndRun.guid == HitAndRun.ent.GUID
				and GetTime() - HitAndRun.last_fa_time > (
					(MOD_util:GetMOption("hitandrun_delay", HitAndRun.delay) + 1)) * FRAMES
		end
	end

	--执行打断攻击的操作
	function HitAndRun:OnKeyFrame()
		local cannomouseatk = HitAndRun.cannomouseatk
		local walktime = MOD_util:GetMOption("hitandrun_walktime", HitAndRun.walktime)
		if HitAndRun.activeitem and HitAndRun.hand or cannomouseatk then
			if cannomouseatk == "slingshot" and HitAndRun.hand.prefab ~= 'handpillow_steelwool' then
				local a, b, c = INV_util:FindInInventory(cannomouseatk)
				if a then
					SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c)
				end
				SendRPCToServer(RPC.SwapEquipWithActiveItem)
				SendRPCToServer(RPC.PutAllOfActiveItemInSlot, b, c)
				HitAndRun.banatk = true
				HitAndRun.atktag_tick = -10
				ThePlayer:DoTaskInTime(5 * FRAMES, function()
					SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c)
					SendRPCToServer(RPC.SwapEquipWithActiveItem)
					SendRPCToServer(RPC.EquipActiveItem, nil, nil, nil)
					SendRPCToServer(RPC.PutAllOfActiveItemInSlot, b, c)
					HitAndRun.banatk = nil
					HitAndRun.atktag_tick = 0
					HitAndRun:CloseAndAttack(HitAndRun.ent)
				end)
				HitAndRun.last_fa_time, HitAndRun.guid =
					GetTime(),
					HitAndRun.ent.GUID
				if TheWorld.ismastersim then
					HitAndRun.guid = 0
				end
			elseif cannomouseatk then
				local a, b, c = INV_util:FindInInventory(cannomouseatk)
				if a then
					SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c)
				end
				SendRPCToServer(RPC.SwapEquipWithActiveItem)
				SendRPCToServer(RPC.PutAllOfActiveItemInSlot, b, c)
				HitAndRun.banatk = true
				HitAndRun.atktag_tick = -10
				ThePlayer:DoTaskInTime(2 * FRAMES, function()
					SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c)
					SendRPCToServer(RPC.SwapEquipWithActiveItem)
					SendRPCToServer(RPC.EquipActiveItem, nil, nil, nil)
					SendRPCToServer(RPC.PutAllOfActiveItemInSlot, b, c)
					HitAndRun.banatk = nil
					HitAndRun.atktag_tick = 0
					HitAndRun:CloseAndAttack(HitAndRun.ent)
				end)
				HitAndRun.last_fa_time, HitAndRun.guid =
					GetTime() -
					(ThePlayer.fastattack and 4 or 3) * FRAMES, --FRAMES
					(HitAndRun.ent.GUID)         --3.75攻速4.2
			elseif HitAndRun:HoldingPillow() and HitAndRun.activeitem.prefab == HitAndRun.hand.prefab then
				SendRPCToServer(RPC.SwapEquipWithActiveItem)
				HitAndRun.last_fa_time, HitAndRun.guid =
					GetTime() - (ThePlayer.fastattack and 5 or 4) * FRAMES, (HitAndRun.ent.GUID)
			elseif HitAndRun:HoldingPillow() and HitAndRun.activeitem:HasTag('weapon') then
				if HitAndRun.activeitem:HasTag('blowdart') then
					local stacknum = ENT_util:GetStacksize(HitAndRun.activeitem)
					if stacknum and stacknum < 5 then
						local a, b, c = INV_util:FindInInventory(HitAndRun.activeitem.prefab)
						if a then
							SendRPCToServer(RPC.ReturnActiveItem, nil, nil, nil)
							SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c, nil)
						end
					end
				end
				SendRPCToServer(RPC.SwapEquipWithActiveItem)
				ThePlayer:DoTaskInTime(2 * FRAMES or 0, function()
					SendRPCToServer(RPC.SwapEquipWithActiveItem)
				end)
				HitAndRun.last_fa_time, HitAndRun.guid =
					GetTime() - (ThePlayer.fastattack and 5 or 4) * FRAMES + FRAMES,
					HitAndRun.ent.GUID --3.75攻速4.2
			elseif HitAndRun.activeitem:HasTag('weapon') then
				if HitAndRun.activeitem:HasTag('blowdart') then
					local stacknum = ENT_util:GetStacksize(HitAndRun.activeitem)
					if stacknum and stacknum < 5 then
						local a, b, c = INV_util:FindInInventory(HitAndRun.activeitem.prefab)
						if a then
							SendRPCToServer(RPC.ReturnActiveItem, nil, nil, nil)
							SendRPCToServer(RPC.TakeActiveItemFromAllOfSlot, b, c, nil)
						end
					end
				end
				SendRPCToServer(RPC.SwapEquipWithActiveItem)
				HitAndRun.banatk = true
				ThePlayer:DoTaskInTime(5 * FRAMES or 0,
					function()
						HitAndRun.banatk = nil
						SendRPCToServer(RPC.SwapEquipWithActiveItem)
						HitAndRun:CloseAndAttack(HitAndRun.ent)
					end)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID --2.5攻速
				if TheWorld.ismastersim then
					HitAndRun.guid = 0
				end
			else
				HitAndRun:PredictWalk(HitAndRun.ppos, TheInput:GetWorldPosition(), HitAndRun.ent)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			end
		else
			local run_dist = HitAndRun:GetSpeed() * FRAMES * .5
			--print(run_dist)
			--[[ local x, y = POS_util:CalculateDirect(ThePlayer:GetPosition(), TheInput:GetWorldPosition())
SendRPCToServer(RPC.DirectWalking, x, y)
player:DoTaskInTime(0, function()
	SendRPCToServer(RPC.StopWalking)
end) ]]
			local walkrange = walktime >= 2 and 3 or 0.3
			walkrange = math.max(run_dist + 0.1, walkrange)
			local cancelitem
			if MOD_util:GetMOption("hitandrun_switchcut", HitAndRun.switchcut) and next(HitAndRun.SwitchItems) then
				cancelitem = INV_util:FindInInv(nil, nil, nil, function(inst)
					return HitAndRun.SwitchItems[inst.prefab]
				end, { equips = true, })
			end
			--runaway_override
			local walkway = MOD_util:GetMOption("hitandrun_walkway", HitAndRun.walkway)
			if MOD_util:GetMOption("hitandrun_dodgetest", HitAndRun.dodgetest)
				and MOD_util:GetMOption("hitandrun_dt_runaway", HitAndRun.dt_runaway) then
				walkway = HitAndRun:RunAwayOverride(HitAndRun.ent) or walkway
			end
			HitAndRun.final_walkway = walkway
			local oops
			if not ThePlayer:HasTag("attack") then
				--出错了 可能是卡住了
				oops = true
			end

			if ThePlayer:HasTag("weremoose") and ThePlayer:HasTag("weremoosecombo") then
				if ENT_util:GetAnimation(ThePlayer) == "moose_slam" then
					HitAndRun:PredictWalk(HitAndRun.ppos, TheInput:GetWorldPosition(), HitAndRun.ent)
					HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
					HitAndRun.performed_action = false
					HitAndRun:BenPerformed(0.1)
				else
					SendRPCToServer(RPC.ControllerAttackButton, nil, true, true)
					HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
					for i = 1, 5 do
						ThePlayer:DoTaskInTime(i * FRAMES, function()
							HitAndRun:CloseAndAttack(HitAndRun.ent)
							SendRPCToServer(RPC.ControllerAttackButton, nil, true, true)
						end)
					end
				end
			elseif walkway == "rapid_runaway" then
				HitAndRun:PredictWalkTo(HitAndRun.ppos, HitAndRun.pos, -walkrange,
					HitAndRun.p_range + HitAndRun.ent:GetPhysicsRadius(0) - HitAndRun.rangeoffset,
					HitAndRun.ent, true)
				HitAndRun.skip_attack_num = 1 --为了远离
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			elseif walkway == true then
				HitAndRun:PredictWalkTo(HitAndRun.ppos, HitAndRun.pos, -walkrange,
					HitAndRun.p_range + HitAndRun.ent:GetPhysicsRadius(0) - HitAndRun.rangeoffset,
					HitAndRun.ent, true)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			elseif cancelitem and cancelitem:HasTag('_equippable') then
				if cancelitem:HasTag('_equippable') then
					SendRPCToServer(RPC.ControllerUseItemOnSelfFromInvTile, ACTIONS.EQUIP.code,
						cancelitem)
				else
					HitAndRun.inv:InspectItemFromInvTile(cancelitem)
				end
				HitAndRun:CloseAndAttack(HitAndRun.ent)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			elseif HitAndRun:HoldingPillow() then
				oops = false
				SendRPCToServer(RPC.TakeActiveItemFromEquipSlot, EQUIP_util:ToID('hands'))
				SendRPCToServer(RPC.EquipActiveItem, nil, nil, nil)
				HitAndRun.last_fa_time, HitAndRun.guid =
					GetTime() - (ThePlayer.fastattack and 5 or 4) * FRAMES, HitAndRun.ent.GUID
				HitAndRun:CloseAndAttack(HitAndRun.ent)
			elseif walkway == 1 then --原地
				if 1 then
					HitAndRun:PredictWalk(HitAndRun.ppos, TheInput:GetWorldPosition(), HitAndRun.ent)
					HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
				elseif HitAndRun.hand and not ThePlayer.sg then
					SendRPCToServer(RPC.ControllerUseItemOnSelfFromInvTile, ACTIONS.UNEQUIP.code,
						HitAndRun.hand)
					SendRPCToServer(RPC.ControllerUseItemOnSelfFromInvTile, ACTIONS.EQUIP.code,
						HitAndRun.hand)
					HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
					HitAndRun:CloseAndAttack(HitAndRun.ent)
				else
					HitAndRun:PredictWalk(HitAndRun.ppos, TheInput:GetWorldPosition(), HitAndRun.ent)
					HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
				end
			elseif walkway == 2 then --向着鼠标
				HitAndRun:DealTheBadRemoteAuthor()
				HitAndRun:WalkTo(HitAndRun.ppos, TheInput:GetWorldPosition(), walkrange,
					HitAndRun.p_range + HitAndRun.ent:GetPhysicsRadius(0) - HitAndRun.rangeoffset)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			elseif walkway == 3 then --远离目标
				HitAndRun:WalkTo(HitAndRun.ppos, HitAndRun.pos, -walkrange,
					HitAndRun.p_range + HitAndRun.ent:GetPhysicsRadius(0) - HitAndRun.rangeoffset)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			else --if walkway == 4 then--向着目标
				HitAndRun:WalkTo(HitAndRun.ppos, HitAndRun.pos, walkrange)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), HitAndRun.ent.GUID
			end
			if oops then
				print("oops??")
				HitAndRun:WalkTo(HitAndRun.ppos, HitAndRun.ppos, 0)
				HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), 0
			end
		end
		--触发点击切装备模组
		if HitAndRun.hand and HitAndRun.hand:HasTag('weapon') then
		else
			ThePlayer:PushEvent("EquipItem", { type = 'fight', target = HitAndRun.ent })
		end

		if walktime >= 2 then
			Sleep((walktime - 1) * FRAMES)
		end
	end

	--无特殊情况一直执行攻击指令
	function HitAndRun:OnNormalFrame()
		if HitAndRun.skip_attack_num and HitAndRun.skip_attack_num > 0 then
			HitAndRun.skip_attack_num = HitAndRun.skip_attack_num - 1
		elseif not HitAndRun.banatk then
			HitAndRun:CloseAndAttack(HitAndRun.ent)
		end
	end
end
--[[HitAndRun.resetguidanims = {
	["pickup"] = true,    --busy
	["hit"] = true,       --busy
	["distress_pst"] = true, --busy
	["toolpunch"] = function()
	end,
	["build_pre"] = true,     --busy
	["pocketwatch_warp"] = true, --busy
	["jumpout"] = true,       --busy
}]]
HitAndRun.defaultcolor = { x = 255, y = 89, z = 64 }
do --高亮函数
	function HitAndRun:GetHightlighColor()
		return MOD_util:GetMOption("hightcolor_x", HitAndRun.defaultcolor.x) / 255,
			MOD_util:GetMOption("hightcolor_y", HitAndRun.defaultcolor.y) / 255,
			MOD_util:GetMOption("hightcolor_z", HitAndRun.defaultcolor.z) / 255
	end

	function HitAndRun:IsHightTargetFnOpen()
		return MOD_util:GetMOption("highttarget_open", HitAndRun.highttarget_open)
	end

	function HitAndRun:HightLightTarget(ent)
		if HitAndRun:IsHightTargetFnOpen() and ent then
			if ent and not ent.components.highlight then
				ent:AddComponent("highlight")
			end
			local highlight = ent.components.highlight
			highlight.highlight_add_colour_red = nil
			highlight.highlight_add_colour_green = nil
			highlight.highlight_add_colour_blue = nil
			local x, y, z = HitAndRun:GetHightlighColor()
			highlight:SetAddColour({ x = x, y = y, z = z })
			highlight.highlit = true

			HitAndRun._highting_target = ent
		end
	end

	function HitAndRun:UnHightLightTarget(ent)
		ent = ent or HitAndRun._highting_target
		if ent and ent:IsValid() and ent.components.highlight then
			ent.components.highlight:UnHighlight()

			HitAndRun._highting_target = nil
		end
	end
end
do --记录玩家处于攻击状态的时间
	-- 攻击计时由接管监督协程更新，不注册永久玩家组件定时器。
	function HitAndRun:RegisterListener()
		if not ThePlayer then return end
		if not ThePlayer.shadowself_native_listener then
			ThePlayer.shadowself_native_listener = true
			ThePlayer:ListenForEvent("performaction", function(inst, data)
				if HitAndRun.ent then
					if not ThePlayer.shadowself_ban_performed_action then
						local act=data and (data.action or data)
                        if act and act.action==ACTIONS.ATTACK and ThePlayer:HasTag("attack") then
                            -- 只有攻击的performaction可确认命中，WALKTO不能把下一刀提前取消。
							HitAndRun.performed_action = true
						else
							--print("performed_action2")
							HitAndRun.performed_action = false
						end
					end
				else
					HitAndRun.performed_action = false
				end
			end)
		end
		ThePlayer.shadowself_ban_performed_action = nil --cancel ban_performed_action
		HitAndRun.performed_action = false
	end

	function HitAndRun:BenPerformed(time)
		if ThePlayer.shadowself_ban_performed_action then
			ThePlayer.shadowself_ban_performed_action:Cancel()
		end
		ThePlayer.shadowself_ban_performed_action = ThePlayer:DoTaskInTime(time or 0.1, function()
			ThePlayer.shadowself_ban_performed_action = nil
		end)
	end
end
-- 内置版本不修改原版控制器，不执行服务器远程代码。
function HitAndRun:DealMovementPredicting() end
function HitAndRun:DealTheBadRemoteAuthor() end
function HitAndRun:ShoudSkipThread()
	return KEY_util:MoveKeyDown() or TUNING.AUTODODGER_RUNING_AWAYING
end

--开始线程
function HitAndRun:StartHitAndRun(key, down)
	if not GAME_util:InGame() or TUNING.Cheatthread then return end
	HitAndRun.selected_ents = {}
	HitAndRun:GetAttackTargets(20)
	TUNING.Cheatthread = StartThread(function()
        if not ThePlayer or not ThePlayer:IsValid() or not ThePlayer.components or not ThePlayer.components.playercontroller then return end
		--注册监听
		HitAndRun:RegisterListener()
		--自动开关延迟补偿
		if MOD_util:GetMOption("hitandrun_movementswitch", HitAndRun.movementswitch) or ThePlayer:HasTag("weremoose") then
			HitAndRun.movementflag = false
			if ThePlayer.sg then
				ThePlayer:EnableMovementPrediction(false)
				HitAndRun.movementflag = true
			end
		end

		--init
		HitAndRun.PC, HitAndRun.combat = ThePlayer.components.playercontroller, ThePlayer.replica.combat
		HitAndRun.inv = ThePlayer.replica.inventory
		HitAndRun.cannomouseatk = HitAndRun:CanNoMouseDoubleSwitch()
		HitAndRun.rangeoffset = (not TheWorld.ismastersim and HitAndRun.PC:CanLocomote() and 0.5 or 0.1)
		local owner = ThePlayer
		while TUNING.Cheatthread do
            if ThePlayer~=owner or not owner:IsValid() or not owner.components.playercontroller then return end
			--如果按下移动键就一直睡眠到没有按下移动键
			if HitAndRun:ShoudSkipThread() then --TUNING.AUTODODGER_RUNING_AWAYING
				repeat
					Sleep(0)
				until not HitAndRun:ShoudSkipThread()
			end
			HitAndRun:GetAttackTargets(5)
			local ent
			--走自己的索敌逻辑或者克雷的索敌逻辑
			if MOD_util:GetMOption("hitandrun_targetmode", HitAndRun.targetmode) then
				local retarget = HitAndRun.combat:GetTarget()
				ent = HitAndRun.PC:GetAttackTarget(
					TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)), retarget,
					retarget ~= nil)
			else
				ent = HitAndRun:GetClosestTarget()
			end
			if not ent then HitAndRun:GetAttackTargets(10) end
			if ent then
				do
					HitAndRun:DealMovementPredicting(1)
				end
				ThePlayer:PushEvent("EquipItem", { type = 'fight', target = ent })
			end
			HitAndRun:UnHightLightTarget()
			HitAndRun:HightLightTarget(ent)

			HitAndRun.guid, HitAndRun.idle_ticks, HitAndRun.last_fa_time = 0, nil, GetTime()
			HitAndRun.performed_action = false
			HitAndRun.ent = ent
			--这里是在切换目标的时候让下一刀为第一刀，否则会罚站
			local alwayscantarget = HitAndRun:AlwaysCanTarget(HitAndRun.ent)
			while ENT_util:IsValid(HitAndRun.ent) and not HitAndRun.ent:HasTag("isdead") and (alwayscantarget or HitAndRun.combat:CanTarget(HitAndRun.ent)) and not HitAndRun:ShoudSkipThread() do
                if ThePlayer~=owner or not owner:IsValid() or not owner.components.playercontroller then return end
				HitAndRun:PreTheLoop()
				local dodgetab = MOD_util:GetMOption("hitandrun_dodgetest", HitAndRun.dodgetest) and
					HitAndRun:IsAttackPre(HitAndRun.ent, 1)
				local not_keyframe = false
				if ThePlayer:HasTag("busy") and not ThePlayer:HasTag("attack") then
					--print("busy or attack")
					if HitAndRun:DoubleSwitching() or HitAndRun.cannomouseatk or HitAndRun:HoldingPillow() then
					else
						not_keyframe = true
						HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), 0
					end
				elseif not HitAndRun.canhit then
					--如果目标是暗影生物并且瞬移走了 尝试切换目标
					--print("not canhitk")
					if not HitAndRun.canhit and HitAndRun.guid ~= 0 and HitAndRun.EntTable[HitAndRun.ent.prefab].isshadow then
						local new = HitAndRun:GetClosestTarget()
						if new and HitAndRun.EntTable[new.prefab].isshadow then
							HitAndRun.ent = new
							not_keyframe = true
							HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), 0
						end
					elseif HitAndRun:DoubleSwitching() or HitAndRun.cannomouseatk then --如果正在双切a则无视canhit
					else
						not_keyframe = true
						HitAndRun.last_fa_time, HitAndRun.guid = GetTime(), 0
					end
				end
				if HitAndRun.EntTable[HitAndRun.ent.prefab].extrafunction and HitAndRun.EntTable[HitAndRun.ent.prefab].extrafunction(HitAndRun.ent) then
					--成功执行额外函数，这次while循环将不再执行其他分支
				elseif dodgetab and
					not HitAndRun:holdLegionShield(HitAndRun.hand) then --尝试躲避目标的攻击
					HitAndRun:DoDodge(dodgetab)
				elseif not not_keyframe and HitAndRun:IsKeyFrame() then --判断关键时机来执行打断攻击
					HitAndRun:OnKeyFrame()
				else
					HitAndRun:OnNormalFrame() --否则一直执行攻击
				end
				Sleep(FRAMES)
			end
			HitAndRun.ent = nil
			Sleep(FRAMES)
		end
	end, "shadowself_native_attack")
end

--停止线程
function HitAndRun:StopHitAndRun()
    HitAndRun:StopPredictWalk();HitAndRun.shadowself_dodging=nil
	if GAME_util:InGame() and TUNING.Cheatthread then
		--ThePlayer:EnableMovementPrediction(true)
		KillThreadsWithID(TUNING.Cheatthread.id) --挂起线程 让线程不动
		TUNING.Cheatthread:SetList(nil)    --把线程的参数抹除
		TUNING.Cheatthread = nil           --让线程死去
		if HitAndRun.movementflag then
			ThePlayer:EnableMovementPrediction(true)
		end
		if HitAndRun._highting_target then
			HitAndRun:UnHightLightTarget(HitAndRun._highting_target)
			HitAndRun._highting_target = nil
		end
		HitAndRun:DealMovementPredicting(false)

		HitAndRun.cannomouseatk = false

		if MOD_util:GetMOption("hitandrun_repeat_attack", HitAndRun.hitandrun_repeat_attack) then

		else
			SendRPCToServer(RPC.StopControl, CONTROL_PRIMARY)
		end
	end
end

function HitAndRun:GetTargetCanHitRange(ent, target)
	return (ent.replica.combat and ent.replica.combat:GetAttackRangeWithWeapon() or 2) +
		target:GetPhysicsRadius(0)
end

do --按键注册
	--用按键开始线程
	MOD_util:AddKeyDownHandler("hitandrun_startkey", HitAndRun.defaultstartkey, HitAndRun.StartHitAndRun)
	MOD_util:AddKeyUpHandler("hitandrun_startkey", HitAndRun.defaultstartkey, HitAndRun.StopHitAndRun)
	--左右键设置参数
	MOD_util:AddKeyDownHandler("hitandrun_add", KEY_RIGHT, function()
		if not GAME_util:InGame() then return end
		if TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) then
			HitAndRun.keyframe = MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe) + 1
			PLAYER_util:Say("增加第一刀补偿： " .. HitAndRun.keyframe)

			MOD_util:ChangeMOption("hitandrun_keyframe", HitAndRun.keyframe)
		elseif TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_alt_key", HitAndRun.alt_key)) then
			HitAndRun.walktime = MOD_util:GetMOption("hitandrun_walktime", HitAndRun.walktime) + 1
			PLAYER_util:Say("增加移动时间： " .. HitAndRun.walktime .. "帧")

			MOD_util:ChangeMOption("hitandrun_walktime", HitAndRun.walktime)
		else
			HitAndRun.delay = MOD_util:GetMOption("hitandrun_delay", HitAndRun.delay) + 1
			PLAYER_util:Say("增加攻击间隔： " .. HitAndRun.delay .. "帧")

			MOD_util:ChangeMOption("hitandrun_delay", HitAndRun.delay)
		end
	end)
	MOD_util:AddKeyDownHandler("hitandrun_reduce", KEY_LEFT, function()
		if not GAME_util:InGame() then return end
		if TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) then
			HitAndRun.keyframe = MOD_util:GetMOption("hitandrun_keyframe", HitAndRun.keyframe) - 1
			PLAYER_util:Say("减小第一刀补偿： " .. HitAndRun.keyframe)

			MOD_util:ChangeMOption("hitandrun_keyframe", HitAndRun.keyframe)
		elseif TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_alt_key", HitAndRun.alt_key)) then
			HitAndRun.walktime = MOD_util:GetMOption("hitandrun_walktime", HitAndRun.walktime) - 1
			PLAYER_util:Say("减小移动时间： " .. HitAndRun.walktime .. "帧")

			MOD_util:ChangeMOption("hitandrun_walktime", HitAndRun.walktime)
		else
			HitAndRun.delay = MOD_util:GetMOption("hitandrun_delay", HitAndRun.delay) - 1
			PLAYER_util:Say("减小攻击间隔： " .. HitAndRun.delay .. "帧")

			MOD_util:ChangeMOption("hitandrun_delay", HitAndRun.delay)
		end
	end)
	MOD_util:AddKeyUpHandler("hitandrun_up", KEY_UP, function()
		if not GAME_util:InGame() then return end
		if TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) then
			HitAndRun.priority_undermouse = not MOD_util:GetMOption("hitandrun_priority_undermouse",
				HitAndRun.priority_undermouse)
			PLAYER_util:Say("优先攻击鼠标下的目标： " .. (HitAndRun.priority_undermouse and "是" or "否"))
			MOD_util:ChangeMOption("hitandrun_priority_undermouse", HitAndRun.priority_undermouse)
		elseif TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_alt_key", HitAndRun.alt_key)) then
			HitAndRun.highttarget_open = not MOD_util:GetMOption("highttarget_open", HitAndRun.highttarget_open)
			PLAYER_util:Say("高亮目标： " .. (HitAndRun.highttarget_open and "是" or "否"))
			MOD_util:ChangeMOption("highttarget_open", HitAndRun.highttarget_open)
		elseif TheInput:IsControlPressed(CONTROL_FORCE_TRADE) then
			HitAndRun.allfirst = not MOD_util:GetMOption("hitandrun_allfirst", HitAndRun.allfirst)
			PLAYER_util:Say("全部第一刀：" .. (HitAndRun.allfirst and "开启" or "关闭"))
			MOD_util:ChangeMOption("hitandrun_allfirst", HitAndRun.allfirst)
		else
			HitAndRun.walkway = MOD_util:GetMOption("hitandrun_walkway", HitAndRun.walkway) + 1
			if HitAndRun.walkway == 5 then
				HitAndRun.walkway = 1
			end
			local str = HitAndRun.walkway == 1 and '原地模式'
				or HitAndRun.walkway == 2 and '跟随鼠标' or
				HitAndRun.walkway == 3 and '保持距离' or
				HitAndRun.walkway == 4 and '向着敌人' or 'error'
			PLAYER_util:Say("走A模式：" .. str)

			MOD_util:ChangeMOption("hitandrun_walkway", HitAndRun.walkway)
		end
	end)
	MOD_util:AddKeyUpHandler("hitandrun_down", KEY_DOWN, function()
		if not GAME_util:InGame() then return end
		if TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) then
			if HitAndRun.super_switch_prefab then
				HitAndRun.super_switch_prefab = nil
				PLAYER_util:Say("超级双切:" .. (HitAndRun.super_switch_prefab and "开启" or "关闭"))
			else
				local item = ThePlayer.replica.inventory:GetActiveItem()
				HitAndRun.super_switch_prefab = item and item.prefab
				if HitAndRun.super_switch_prefab then
					SendRPCToServer(RPC.ReturnActiveItem)
					PLAYER_util:Say("超级双切:" .. (HitAndRun.super_switch_prefab and "开启" or "关闭"))
					ChatHistory:SendCommandResponse("超级双切介绍:" ..
						"会使用鼠标的物品和手部物品双切且无需拿在鼠标上" ..
						"\n再次按下该键可关闭该功能。")
				else
					PLAYER_util:Say("超级双切:请在鼠标上拿装备")
				end
			end
		elseif TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_alt_key", HitAndRun.alt_key)) then
			HitAndRun.targetmode = not MOD_util:GetMOption("hitandrun_targetmode", HitAndRun.targetmode)
			if HitAndRun.targetmode then
				PLAYER_util:Say("官方索敌")
			else
				PLAYER_util:Say("黑名单索敌")
			end
			MOD_util:ChangeMOption("hitandrun_targetmode", HitAndRun.targetmode)
		elseif TheInput:IsControlPressed(CONTROL_FORCE_TRADE) then
			HitAndRun.shadowdodge = not MOD_util:GetMOption("hitandrun_shadowdodge", HitAndRun.shadowdodge)
			PLAYER_util:Say("暗影躲避：" .. (HitAndRun.shadowdodge and "开启" or "关闭"))
			MOD_util:ChangeMOption("hitandrun_shadowdodge", HitAndRun.shadowdodge)
		else
			HitAndRun.dodgetest = not MOD_util:GetMOption("hitandrun_dodgetest", HitAndRun.dodgetest)
			PLAYER_util:Say("自动躲避：" .. (HitAndRun.dodgetest and "开启" or "关闭"))
			MOD_util:ChangeMOption("hitandrun_dodgetest", HitAndRun.dodgetest)
		end
	end)
	--中键设置
	local function Set_oneMonster_AutoAttack()
		local item = ENT_util:GetItemUnderMouse()
		if not item or not TheNet:GetPVPEnabled() and item:HasTag("player") then
			return
		end
		if not item.prefab then return end --byd有些东西没prefab
		local name = item:GetDisplayName() or "MISSNAME"
		if item.replica.combat then
			if HitAndRun.AutoAttackMonsterBlackList[item.prefab] then
				HitAndRun.AutoAttackMonsterBlackList[item.prefab] = nil
				PLAYER_util:Say(name .. "  " .. item.prefab .. "  " .. "已移除 自动攻击列表黑名单")
			else
				HitAndRun.AutoAttackMonsterBlackList[item.prefab] = item.prefab
				PLAYER_util:Say(name .. "  " .. item.prefab .. "  " .. "已经加入自动攻击队列黑名单")
			end
			RW_util:SaveData(HitAndRun.AutoAttackMonsterBlackList or {}, 'AutoAttackMonsterBlackList')
		else
			print(name .. "  " .. item.prefab .. "  " .. "不是个战斗单位 没有 combat 标签")
		end
	end
	local function WriteHitAndRunPrefabToFile()
		local item = ENT_util:GetItemUnderMouse()
		if not item --[[ or not item:HasTag('_equippable') ]] then
			return
		end
		local name = item:GetDisplayName() or "MISSNAME"

		if HitAndRun.SwitchItems[item.prefab] then
			HitAndRun.SwitchItems[item.prefab] = nil
			print("走A道具 " .. "  " .. item.prefab .. "  " .. name .. "已从列表删除")
			PLAYER_util:Say("走A道具 " .. "  " .. item.prefab .. "  " .. name .. "已从列表删除")
		else
			HitAndRun.SwitchItems[item.prefab] = item.prefab
			PLAYER_util:Say("走A道具 " .. "  " .. item.prefab .. "  " .. name .. "已经加入列表")
			print("走A道具 " .. "  " .. item.prefab .. "  " .. name .. "已经加入列表")
		end
		if MOD_util:GetMOption("hitandrun_saveswitch", HitAndRun.hitandrun_saveswitch) then
			RW_util:SaveData(HitAndRun.SwitchItems or {}, 'SwitchItems')
		end
	end
	MOD_util:AddKeyDownHandler("hitandrun_mousekey", HitAndRun.mousekey, function()
		if TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_alt_key", HitAndRun.alt_key)) then
			if not MOD_util:GetMOption("hitandrun_targetmode", HitAndRun.targetmode) then
				Set_oneMonster_AutoAttack()
			end
		end
		if MOD_util:GetMOption("hitandrun_switchcut", HitAndRun.switchcut)
			and TheInput:IsKeyDown(MOD_util:GetMOption("hitandrun_ctrl_key", HitAndRun.ctrl_key)) then
			WriteHitAndRunPrefabToFile()
		end
	end)
end
modimport("HitAndRun/Dodge")

--------------------模组设置界面-------------------
-- 不注册来源Mod的设置界面。
