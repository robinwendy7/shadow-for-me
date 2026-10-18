--越权操作
--sssssssssssssssssssuper hack!!!
--[[
CMP_util

用途：
	在不真正 SpawnPrefab 的情况下，尽量读取 prefab 构造函数里写入的组件数据、动画数据和 tag。
	它会用 fake TheWorld / fake Entity / fake component 环境重新执行 prefab 的 fn，
	然后把 inst.components、AnimState 调用记录、AddTag 记录整理成普通 table 返回。

适合：
	1. 客户端侧预读 prefab 的静态数据，比如 finiteuses、equippable、edible、armor 等组件字段。
	2. 读取 prefab 默认动画 bank/build/anim。
	3. 判断 prefab 构造阶段添加过的 tag。

不适合：
	1. 依赖真实世界状态、真实网络变量、真实实体行为的逻辑。
	2. 世界、事件阶段、global、placer 等特殊 prefab。
	3. 需要真实组件完整行为的场景。这里的组件大多是 fake/record 版本。

使用方法：
	-- m_util_basement/modmain.lua 已经把它挂到 GLOBAL.CMP_util。
	local data = CMP_util:GetPrefabData("footballhat")
	if data then
		local animdata = CMP_util:GetAnimData(data)
		local build = animdata and animdata.build
		local absorb = CMP_util:GetCMPData(data, "armor", "absorb_percent")
		local maxuses = CMP_util:CalculateCMPData(data, "finiteuses", "SetMaxUses", 1)
	end

	-- 也可以直接传 prefab 名，函数内部会自动 GetPrefabData 并缓存结果。
	local health = CMP_util:GetCMPData("meatballs", "edible", "healthvalue")
	local uses = CMP_util:CalculateCMPData("axe", "finiteuses", "SetMaxUses", 1)

返回值说明：
	GetPrefabData(prefab) -> data 或 nil
	GetAnimData(data_or_prefab) -> data.AnimState 或 nil
	GetCMPData(data_or_prefab, cmpname, key) -> 组件字段值
	CalculateCMPData(data_or_prefab, cmpname, methodname, index) -> 记录的方法调用参数
	HasTag(data_or_prefab, tag) -> true 或 nil

注意：
	首次读取 prefab 会执行一次 fake prefab fn，结果会缓存。
	如果日志出现 CMP_util_errorload / CMP_util_noinst，通常是 fake 环境缺某个 DST API，
	或者该 prefab 本来就不适合用这种方式分析。
]]
local CMP_util = {}
do
	local function clientprint(str)
		if TUNING.CMP_UTIL_PRINT and TheSim then
			TheSim:LuaPrint(str)
		end
	end
	local meta_list = {}
	local special_table
	local normalmeta = {
		__index = function(t, k)
			return special_table or nil
		end,
	}
	local entity_allown = {
	}
	local entitymeta = {
		__index = function(t, k)
			if EntityScript[k] then
				return special_table
			end
			if entity_allown[k] then
				return special_table
			end
		end,
	}
	local function _set_metatable(t, m)
		t.__mark__ = true
		setmetatable(t, m)
	end
	local function make_tab(t)
		t = t or {}
		_set_metatable(t, normalmeta)
		return t
	end
	local function remember_method(self, methodname, ...)
		if self.method_data then
			self.method_data[methodname] = { ... }
		end
	end
	local function recorded(methodname, fn)
		return function(self, ...)
			remember_method(self, methodname, ...)
			if fn then
				local ret = fn(self, ...)
				if ret ~= nil then
					return ret
				end
			end
			return self
		end
	end
	local function setfield(methodname, fieldname)
		return recorded(methodname, function(self, value)
			self[fieldname] = value
		end)
	end
	local function clamp(n, min, max)
		n = tonumber(n) or tonumber(min) or 0
		min = tonumber(min) or n
		max = tonumber(max) or n
		if n < min then
			return min
		elseif n > max then
			return max
		end
		return n
	end
	local function create_vector(x, y, z)
		return make_tab({
			x = x or 0,
			y = y or 0,
			z = z or 0,
			Get = function(self)
				return self.x, self.y, self.z
			end,
		})
	end
	local cmp_extra_fn = {
		armor = {
			condition = 100,
			maxcondition = 100,
			InitCondition = recorded("InitCondition", function(self, amount, absorb_percent)
				self.condition = amount
				self.maxcondition = amount
				self.absorb_percent = absorb_percent
			end),
			InitIndestructible = recorded("InitIndestructible", function(self, absorb_percent)
				self.absorb_percent = absorb_percent
				self.indestructible = true
			end),
			SetAbsorption = setfield("SetAbsorption", "absorb_percent"),
			SetOnFinished = setfield("SetOnFinished", "onfinished"),
			SetKeepOnFinished = setfield("SetKeepOnFinished", "keeponfinished"),
			SetTags = setfield("SetTags", "tags"),
			SetCondition = recorded("SetCondition", function(self, amount)
				self.condition = math.min(amount, self.maxcondition or amount)
			end),
			SetPercent = recorded("SetPercent", function(self, amount)
				self.condition = (self.maxcondition or 100) * amount
			end),
			GetPercent = function(self)
				return (self.maxcondition or 0) > 0 and (self.condition or 0) / self.maxcondition or 0
			end,
			IsDamaged = function(self)
				return (self.condition or 0) < (self.maxcondition or 0)
			end,
			IsIndestructible = function(self)
				return self.indestructible == true
			end,
		},
		edible = {
			healthvalue = 10,
			hungervalue = 10,
			sanityvalue = 0,
			foodtype = FOODTYPE and FOODTYPE.GENERIC or "GENERIC",
			degrades_with_spoilage = true,
			SetOnEatenFn = setfield("SetOnEatenFn", "oneaten"),
			SetHandleRemoveFn = setfield("SetHandleRemoveFn", "handleremovefn"),
			SetOverrideStackMultiplierFn = setfield("SetOverrideStackMultiplierFn", "overridestackmultiplierfn"),
			SetGetHealthFn = setfield("SetGetHealthFn", "gethealthfn"),
			SetGetSanityFn = setfield("SetGetSanityFn", "getsanityfn"),
			GetHealth = function(self)
				return self.healthvalue
			end,
			GetHunger = function(self)
				return self.hungervalue
			end,
			GetSanity = function(self)
				return self.sanityvalue
			end,
		},
		equippable = {
			isequipped = false,
			equipslot = EQUIPSLOTS and EQUIPSLOTS.HANDS or "hands",
			dapperness = 0,
			insulated = false,
			equippedmoisture = 0,
			maxequippedmoisture = 0,
			SetOnEquip = setfield("SetOnEquip", "onequipfn"),
			SetOnUnequip = setfield("SetOnUnequip", "onunequipfn"),
			SetOnPocket = setfield("SetOnPocket", "onpocketfn"),
			SetOnEquipToModel = setfield("SetOnEquipToModel", "onequiptomodelfn"),
			SetDappernessFn = setfield("SetDappernessFn", "dapperfn"),
			SetPreventUnequipping = setfield("SetPreventUnequipping", "preventunequipping"),
			IsEquipped = function()
				return false
			end,
			IsInsulated = function(self)
				return self.insulated
			end,
		},
		finiteuses = {
			total = 100,
			current = 100,
			consumption = {},
			SetConsumption = recorded("SetConsumption", function(self, action, uses)
				self.consumption[action] = uses
			end),
			ClearAllConsumptions = recorded("ClearAllConsumptions", function(self)
				self.consumption = {}
			end),
			SetMaxUses = recorded("SetMaxUses", function(self, val)
				self.total = val
				self.current = val
			end),
			SetUses = recorded("SetUses", function(self, val)
				self.current = val
			end),
			GetUses = function(self)
				return self.current
			end,
			SetPercent = recorded("SetPercent", function(self, amount)
				self.current = (self.total or 100) * amount
			end),
			GetPercent = function(self)
				return (self.total or 0) > 0 and (self.current or 0) / self.total or 0
			end,
			SetOnFinished = setfield("SetOnFinished", "onfinished"),
			SetDoesNotStartFull = setfield("SetDoesNotStartFull", "doesnotstartfull"),
			SetIgnoreCombatDurabilityLoss = setfield("SetIgnoreCombatDurabilityLoss", "ignorecombatdurabilityloss"),
			SetModifyUseConsumption = setfield("SetModifyUseConsumption", "modifyuseconsumption"),
			IgnoresCombatDurabilityLoss = function(self)
				return self.ignorecombatdurabilityloss
			end,
		},
		freezable = {
			state = "NORMAL",
			resistance = 1,
			coldness = 0,
			wearofftime = 10,
			fxlevel = 1,
			fxdata = {},
			SetResistance = setfield("SetResistance", "resistance"),
			SetDefaultWearOffTime = setfield("SetDefaultWearOffTime", "wearofftime"),
			SetShatterFXLevel = recorded("SetShatterFXLevel", function(self, level, percent)
				self.fxlevel = level
				self.fxpercent = percent
			end),
			AddShatterFX = recorded("AddShatterFX", function(self, prefab, offset, followsymbol)
				table.insert(self.fxdata, {
					prefab = prefab,
					x = offset and offset.x or 0,
					y = offset and offset.y or 0,
					z = offset and offset.z or 0,
					follow = followsymbol,
				})
			end),
			SetRedirectFn = setfield("SetRedirectFn", "redirectfn"),
			SetExtraResist = setfield("SetExtraResist", "extraresist"),
			AddColdness = recorded("AddColdness", function(self, coldness)
				self.coldness = math.max(0, (self.coldness or 0) + (coldness or 0))
			end),
			ResolveResistance = function(self)
				return (self.resistance or 1) + (self.extraresist or 0)
			end,
			IsFrozen = function()
				return false
			end,
			IsThawing = function()
				return false
			end,
		},
		fuel = {
			fuelvalue = 1,
			fueltype = FUELTYPE.BURNABLE or "BURNABLE",
			SetOnTakenFn = setfield("SetOnTakenFn", "ontaken"),
		},
		fueled = {
			consuming = false,
			maxfuel = 0,
			currentfuel = 0,
			rate = 1,
			accepting = false,
			fueltype = FUELTYPE.BURNABLE or "BURNABLE",
			sections = 1,
			SetSectionCallback = setfield("SetSectionCallback", "sectionfn"),
			SetDepletedFn = setfield("SetDepletedFn", "depleted"),
			SetSections = setfield("SetSections", "sections"),
			SetMultiplierFn = setfield("SetMultiplierFn", "multfn"),
			SetCanTakeFuelItemFn = setfield("SetCanTakeFuelItemFn", "cantakefuelitemfn"),
			SetTakeFuelItemFn = setfield("SetTakeFuelItemFn", "ontakefuelitemfn"),
			SetTakeFuelFn = setfield("SetTakeFuelFn", "ontakefuelfn"),
			SetUpdateFn = setfield("SetUpdateFn", "updatefn"),
			InitializeFuelLevel = recorded("InitializeFuelLevel", function(self, fuel)
				if (self.maxfuel or 0) < fuel then
					self.maxfuel = fuel
				end
				self.currentfuel = fuel
			end),
			SetPercent = recorded("SetPercent", function(self, amount)
				self.currentfuel = (self.maxfuel or 0) * amount
			end),
			DoDelta = recorded("DoDelta", function(self, amount)
				self.currentfuel = clamp((self.currentfuel or 0) + amount, 0, self.maxfuel or 0)
			end),
			MakeEmpty = recorded("MakeEmpty", function(self)
				self.currentfuel = 0
			end),
			StartConsuming = recorded("StartConsuming", function(self)
				self.consuming = true
			end),
			StopConsuming = recorded("StopConsuming", function(self)
				self.consuming = false
			end),
			GetPercent = function(self)
				return (self.maxfuel or 0) > 0 and clamp((self.currentfuel or 0) / self.maxfuel, 0, 1) or 0
			end,
			IsEmpty = function(self)
				return (self.currentfuel or 0) <= 0
			end,
			IsFull = function(self)
				return (self.maxfuel or 0) > 0 and (self.currentfuel or 0) >= self.maxfuel
			end,
		},
		forgerepair = {
			SetRepairMaterial = setfield("SetRepairMaterial", "repairmaterial"),
			SetOnRepaired = setfield("SetOnRepaired", "onrepaired"),
		},
		forgerepairable = {
			SetRepairMaterial = setfield("SetRepairMaterial", "repairmaterial"),
			SetRepairable = setfield("SetRepairable", "repairable"),
			SetOnRepaired = setfield("SetOnRepaired", "onrepaired"),
		},
		damagetypebonus = {
			AddBonusCallback = recorded("AddBonusCallback", function(self, fn)
				self.bonuscallbacks = self.bonuscallbacks or {}
				table.insert(self.bonuscallbacks, fn)
			end),
		},
		deployable = {
			SetDeployMode = setfield("SetDeployMode", "mode"),
			SetUseGridPlacer = setfield("SetUseGridPlacer", "usegridplacer"),
		},
		eater = {
			SetOnEatFn = setfield("SetOnEatFn", "oneatfn"),
			SetDiet = recorded("SetDiet", function(self, can_eat, prefer_eat)
				self.caneat = can_eat
				self.prefereat = prefer_eat
			end),
			SetCanEatHorrible = recorded("SetCanEatHorrible", function(self)
				self.caneathorrible = true
			end),
			SetCanEatRaw = recorded("SetCanEatRaw", function(self)
				self.caneatraw = true
			end),
			SetStrongStomach = setfield("SetStrongStomach", "strongstomach"),
			CanEat = function()
				return true
			end,
		},
		floater = {
			SetSize = setfield("SetSize", "size"),
			SetVerticalOffset = setfield("SetVerticalOffset", "verticaloffset"),
			SetScale = setfield("SetScale", "scale"),
			SetBankSwapOnFloat = recorded("SetBankSwapOnFloat", function(self, bank, index, data)
				self.swap_bank = bank
				self.float_index = index
				self.swap_data = data
			end),
			SetSwapData = setfield("SetSwapData", "swap_data"),
			IsFloating = function()
				return false
			end,
			SwitchToDefaultAnim = recorded("SwitchToDefaultAnim"),
		},
		fumaroletool = {
			SetOnBroken = setfield("SetOnBroken", "onbroken"),
			SetOnRepaired = setfield("SetOnRepaired", "onrepaired"),
			SetHeatOnUse = setfield("SetHeatOnUse", "heatonuse"),
			SetOnUpdateTemperatureRange = setfield("SetOnUpdateTemperatureRange", "onupdatetemperature"),
			GetTempRange = function()
				return 1
			end,
		},
		hauntable = {
			SetHauntValue = setfield("SetHauntValue", "hauntvalue"),
			SetOnHauntFn = setfield("SetOnHauntFn", "onhaunt"),
			Panic = recorded("Panic"),
			Haunt = recorded("Haunt"),
		},
		heater = {},
		inspectable = {},
		burnable = {
			SetFXLevel = setfield("SetFXLevel", "fxlevel"),
			SetBurnTime = setfield("SetBurnTime", "burntime"),
			AddBurnFX = recorded("AddBurnFX", function(self, prefab, offset, symbol)
				self.burnfx = self.burnfx or {}
				table.insert(self.burnfx, { prefab = prefab, offset = offset, symbol = symbol })
			end),
			SetOnIgniteFn = setfield("SetOnIgniteFn", "onignite"),
			SetOnExtinguishFn = setfield("SetOnExtinguishFn", "onextinguish"),
			SetOnBurntFn = setfield("SetOnBurntFn", "onburnt"),
			IsBurning = function()
				return false
			end,
		},
		combat = {
			defaultdamage = 0,
			min_attack_period = 0,
			SetDefaultDamage = setfield("SetDefaultDamage", "defaultdamage"),
			SetAttackPeriod = setfield("SetAttackPeriod", "min_attack_period"),
			SetRange = recorded("SetRange", function(self, attack, hit)
				self.attackrange = attack
				self.hitrange = hit or attack
			end),
			SetAreaDamage = recorded("SetAreaDamage", function(self, range, percent)
				self.areahitrange = range
				self.areahitdamagepercent = percent
			end),
			SetRetargetFunction = setfield("SetRetargetFunction", "retargetfn"),
			SetKeepTargetFunction = setfield("SetKeepTargetFunction", "keeptargetfn"),
			DoAreaAttack = recorded("DoAreaAttack"),
			SuggestTarget = recorded("SuggestTarget"),
		},
		container = {
			numslots = 0,
			WidgetSetup = setfield("WidgetSetup", "widgetsetup"),
			GetNumSlots = function(self)
				return self.numslots or 0
			end,
		},
		growable = {
			stage = 0,
			SetStage = recorded("SetStage", function(self, stage)
				if stage > #self.stages then
					stage = #self.stages
				end

				self.stage = stage

				local stagedata = self.stages[stage]

				if stagedata ~= nil and stagedata.fn ~= nil then
					stagedata.fn(self.inst, stage, stagedata)
				end
			end),
			StartGrowing = recorded("StartGrowing"),
			StopGrowing = recorded("StopGrowing"),
		},
		highlightchild = {
			SetOwner = recorded("SetOwner", function(self, owner)
				self.owner = owner
				if owner ~= nil then
					owner.highlightchildren = owner.highlightchildren or {}
					table.insert(owner.highlightchildren, self.inst)
				end
				if self.onchangeownerfn then
					self.onchangeownerfn(self.inst, owner)
				end
			end),
			SetOnChangeOwnerFn = setfield("SetOnChangeOwnerFn", "onchangeownerfn"),
		},
		inventoryitem = {
			SetOnPutInInventoryFn = setfield("SetOnPutInInventoryFn", "onputininventoryfn"),
			SetOnDroppedFn = setfield("SetOnDroppedFn", "ondroppedfn"),
			SetWalkSpeedMult = setfield("SetWalkSpeedMult", "walkspeedmult"),
			SetAttackRange = setfield("SetAttackRange", "attackrange"),
			ChangeImageName = setfield("ChangeImageName", "imagename"),
			EnableTemperature = recorded("EnableTemperature", function(self, enable)
				self.enabletemperature = enable
				local inst = self.inst
				if enable and inst and inst.components and type(inst.AddComponent) == "function" then
					if inst.components.inventoryitemtemperature == nil then
						inst:AddComponent("inventoryitemtemperature")
					end
					if inst.components.inventoryitemmoisture == nil then
						inst:AddComponent("inventoryitemmoisture")
					end
				end
			end),
			SetTemperatureModifier = recorded("SetTemperatureModifier", function(self, key, value)
				self.temperaturemodifiers = self.temperaturemodifiers or {}
				self.temperaturemodifiers[key] = value
			end),
			SetMinTemperature = setfield("SetMinTemperature", "mintemperature"),
			SetMaxTemperature = setfield("SetMaxTemperature", "maxtemperature"),
			SetTemperatureMaxMoisturePenalty = setfield("SetTemperatureMaxMoisturePenalty",
				"temperaturemaxmoisturepenalty"),
			SetNoWetTemperaturePenalty = setfield("SetNoWetTemperaturePenalty", "nowettemperaturepenalty"),
			SetSinks = setfield("SetSinks", "sinks"),
			GetTemperature = function(self)
				return self.temperature or 0
			end,
			IsHeld = function()
				return false
			end,
			OnDropped = recorded("OnDropped"),
			GetContainer = function()
				return nil
			end,
			GetGrandOwner = function()
				return nil
			end,
		},
		inventoryitemtemperature = {
			GetTargetTemperature = function(self)
				return self.targettemperature or 0
			end,
		},
		inventoryitemmoisture = {
			SetExternallyControlled = setfield("SetExternallyControlled", "externallycontrolled"),
			SetOnlyWetWhenSaturated = setfield("SetOnlyWetWhenSaturated", "onlywetwhensaturated"),
			SetOnMoistureDeltaCallback = setfield("SetOnMoistureDeltaCallback", "onmoisturedelta"),
		},
		inventory = {
			maxslots = 0,
			itemslots = {},
			SetNumSlots = setfield("SetNumSlots", "maxslots"),
			NumItems = function()
				return 0
			end,
			GetItems = function(self)
				return self.itemslots or {}
			end,
			GiveItem = recorded("GiveItem"),
		},
		lunarhailbuildup = {
			SetTotalWorkAmount = setfield("SetTotalWorkAmount", "totalworkamount"),
			SetMoonGlassAmount = setfield("SetMoonGlassAmount", "moonglassamount"),
			IsBuildupWorkable = function()
				return false
			end,
		},
		perishable = {
			perishtime = 0,
			perishremainingtime = 0,
			SetPerishTime = recorded("SetPerishTime", function(self, time)
				self.perishtime = time
				self.perishremainingtime = time
			end),
			SetOnPerishFn = setfield("SetOnPerishFn", "onperishfn"),
			SetPercent = recorded("SetPercent", function(self, percent)
				self.perishremainingtime = (self.perishtime or 0) * percent
			end),
			GetPercent = function(self)
				return (self.perishtime or 0) > 0 and (self.perishremainingtime or 0) / self.perishtime or 1
			end,
			StartPerishing = recorded("StartPerishing"),
			StopPerishing = recorded("StopPerishing"),
		},
		repairer = {
			workrepairvalue = 0,
			healthrepairvalue = 0,
			healthrepairpercent = 0,
			perishrepairpercent = 0,
			finiteusesrepairvalue = 0,
		},
		harvestable = {
			produce = 0,
			SetUp = recorded("SetUp", function(self, product, growtime, maxproduce)
				self.product = product
				self.growtime = growtime
				self.maxproduce = maxproduce
				self.produce = 0
			end),
			CanBeHarvested = function(self)
				return (self.produce or 0) > 0
			end,
			StopGrowing = recorded("StopGrowing"),
			StartGrowing = recorded("StartGrowing"),
			SetGrowTime = setfield("SetGrowTime", "growtime"),
			SetOnGrowFn = setfield("SetOnGrowFn", "ongrowfn"),
			SetOnHarvestFn = setfield("SetOnHarvestFn", "onharvestfn"),
		},
		health = {
			maxhealth = 100,
			currenthealth = 100,
			SetMaxHealth = recorded("SetMaxHealth", function(self, amount)
				amount = tonumber(amount) or self.maxhealth or 100
				self.maxhealth = amount
				self.currenthealth = amount
			end),
			SetCurrentHealth = recorded("SetCurrentHealth", function(self, amount)
				self.currenthealth = clamp(amount, 0, self.maxhealth or amount or 100)
			end),
			SetPercent = recorded("SetPercent", function(self, percent)
				percent = tonumber(percent) or 1
				self.currenthealth = (self.maxhealth or 100) * percent
			end),
			DoDelta = recorded("DoDelta", function(self, amount)
				self.currenthealth = clamp((self.currenthealth or self.maxhealth or 100) + (tonumber(amount) or 0), 0,
					self.maxhealth or 100)
			end),
			GetPercent = function(self)
				local maxhealth = tonumber(self.maxhealth) or 0
				return maxhealth > 0 and (tonumber(self.currenthealth) or maxhealth) / maxhealth or 0
			end,
			IsDead = function(self)
				return (tonumber(self.currenthealth) or self.maxhealth or 100) <= 0
			end,
			Kill = recorded("Kill", function(self)
				self.currenthealth = 0
			end),
		},
		lootdropper = {
			DropLoot = recorded("DropLoot"),
			SpawnLootPrefab = recorded("SpawnLootPrefab", function(self, prefab)
				return SpawnPrefab and SpawnPrefab(prefab) or nil
			end),
			SetLoot = setfield("SetLoot", "loot"),
			AddRandomLoot = recorded("AddRandomLoot", function(self, prefab, weight)
				self.randomloot = self.randomloot or {}
				table.insert(self.randomloot, { prefab = prefab, weight = weight })
			end),
		},
		moistureabsorbersource = {
			SetGetDryingRateFn = setfield("SetGetDryingRateFn", "getdryingratefn"),
			SetApplyDryingFn = setfield("SetApplyDryingFn", "applydryingfn"),
		},
		minigame = {
			active = false,
			state = "intro",
			spectator_dist = 20,
			participator_dist = 20,
			watchdist_min = 0,
			watchdist_target = 0,
			watchdist_max = 0,
			SetOnActivatedFn = setfield("SetOnActivatedFn", "activate_fn"),
			SetOnDeactivatedFn = setfield("SetOnDeactivatedFn", "deactivate_fn"),
			IsActive = function(self)
				return self.active == true
			end,
			Activate = recorded("Activate", function(self)
				self.active = true
			end),
			Deactivate = recorded("Deactivate", function(self)
				self.active = false
			end),
			SetIsIntro = recorded("SetIsIntro", function(self)
				self.state = "intro"
			end),
			GetIsIntro = function(self)
				return self.state == "intro"
			end,
			SetIsPlaying = recorded("SetIsPlaying", function(self)
				self.state = "playing"
			end),
			GetIsPlaying = function(self)
				return self.state == "playing"
			end,
			SetIsOutro = recorded("SetIsOutro", function(self)
				self.state = "outro"
			end),
			GetIsOutro = function(self)
				return self.state == "outro"
			end,
			RecordExcitement = recorded("RecordExcitement", function(self)
				self.excitement_time = 0
			end),
			IsExciting = function()
				return false
			end,
		},
		minionspawner = {
			numminions = 0,
			maxminions = 0,
		},
		waterphysics = {},
		prototyper = {
			trees = 0,
		},
		socketable = {
			SetSocketName = setfield("SetSocketName", "socketname"),
			GetSocketName = function(self)
				return self.socketname
			end,
			SetSocketQuality = setfield("SetSocketQuality", "socketquality"),
			GetSocketQuality = function(self)
				return self.socketquality
			end,
		},
		useabletargeteditem = {
			SetOnUseFn = setfield("SetOnUseFn", "onusefn"),
			SetCanSelfTarget = setfield("SetCanSelfTarget", "canselftarget"),
			SetUsingItemDoesNotToggleUseability = setfield("SetUsingItemDoesNotToggleUseability",
				"usingitemdoesnottoggleuseability"),
			SetUseableMounted = setfield("SetUseableMounted", "useablemounted"),
		},
		waxable = {
			SetWaxfn = setfield("SetWaxfn", "waxfn"),
			SetNeedsSpray = recorded("SetNeedsSpray", function(self)
				self.needsspray = true
			end),
		},
		stackable = {
			stacksize = 1,
			maxsize = 40,
			SetMaxSize = setfield("SetMaxSize", "maxsize"),
			SetStackSize = setfield("SetStackSize", "stacksize"),
			StackSize = function(self)
				return self.stacksize
			end,
			MaxSize = function(self)
				return self.maxsize
			end,
			IsStack = function(self)
				return (self.stacksize or 1) > 1
			end,
			Get = function(self)
				return self.inst
			end,
		},
		weapon = {
			damage = 10,
			SetDamage = setfield("SetDamage", "damage"),
			SetRange = recorded("SetRange", function(self, attack, hit)
				self.attackrange = attack
				self.hitrange = hit or attack
			end),
			SetOnAttack = setfield("SetOnAttack", "onattack"),
			SetAttackCallback = setfield("SetAttackCallback", "onattack"),
			SetProjectile = setfield("SetProjectile", "projectile"),
			SetProjectileOffset = setfield("SetProjectileOffset", "projectile_offset"),
			SetOnProjectileLaunch = setfield("SetOnProjectileLaunch", "onprojectilelaunch"),
			SetOnProjectileLaunched = setfield("SetOnProjectileLaunched", "onprojectilelaunched"),
			SetOverrideStimuliFn = setfield("SetOverrideStimuliFn", "overridestimulifn"),
			SetElectric = recorded("SetElectric", function(self, damage_mult, wet_damage_mult)
				self.stimuli = "electric"
				self.electric_damage_mult = damage_mult
				self.electric_wet_damage_mult = wet_damage_mult
			end),
			CanRangedAttack = function(self)
				return self.projectile ~= nil
			end,
		},
		workable = {
			lastworktime = -100,
			SetWorkLeft = recorded("SetWorkLeft", function(self, a)
				self.workleft = a
			end),
			GetWorkLeft = function(self, a)
				return self.workleft or 1
			end,
			SetMaxWork = recorded("SetMaxWork", function(self, a)
				self.maxwork = a
			end),
			workleft = 10
		},
		cyclable = {
			Cyclable = recorded("Cyclable", function(self, a)
				self.num_steps = a
			end),
		},
	}
	local function create_cmp(name)
		if cmp_extra_fn[name] then
			return deepcopy(cmp_extra_fn[name])
		end
		return {
		}
	end

	local function rebuild_special_table()
		special_table = {}
		local specialmeta = {
			__index = function(t, k)
				return special_table
			end,
			__call = function(...)
				return special_table
			end,
			__div = function(rhs)
				return 1 / rhs
			end,
			__add = function(rhs)
				return 1 + rhs
			end,
			__sub = function(rhs)
				return 1 - rhs
			end,
			__mul = function(rhs)
				return 1 * rhs
			end,
			__lt = function(a, b)
				return true
			end,
			__unm = function(rhs)
				return -1
			end,
			__concat = function(rhs)
				return "a"
			end,
		}
		_set_metatable(special_table, specialmeta)
	end
	rebuild_special_table()
	local cmp_baned = {
		owner = true,
	}
	local cmpmeta = {
		__index = function(t, k)
			if cmp_baned[k] then
				return
			end
			local inst = t.inst
			local methodname = k
			local cmp_table = {}
			local specialmeta = {
				__index = function(t, k)
					return special_table
				end,
				__call = function(self, cmp, ...)
					--[[print("cmpmetacall")
					print(self, cmp, ...)]]
					local args = { ... }
					t.method_data[methodname] = args
					local fieldname = string.match(methodname, "^Set(.+)")
					if fieldname and args[1] ~= nil then
						fieldname = string.lower(string.sub(fieldname, 1, 1)) .. string.sub(fieldname, 2)
						t[fieldname] = args[1]
					end
					return special_table
				end,
				__div = function(rhs)
					return 1 / rhs
				end,
				__add = function(rhs)
					return 1 + rhs
				end,
				__sub = function(rhs)
					return 1 - rhs
				end,
				__mul = function(rhs)
					return 1 * rhs
				end,
				__lt = function(a, b)
					return true
				end,
				__unm = function(rhs)
					return -1
				end,
				__concat = function(rhs)
					return "a"
				end,
			}
			_set_metatable(cmp_table, specialmeta)
			return cmp_table
		end,
	}

	local function empty_fn()
	end
	local function has_one_tag(tags_list, tags)
		if type(tags) == "table" then
			for _, tag in pairs(tags) do
				if tags_list[tag] then
					return true
				end
			end
		elseif tags then
			return tags_list[tags] == true
		end
		return false
	end
	local function create_entity()
		local inst
		inst = {
			GUID = 0,
			_cmp_animdata = {},
			components = {},
			AddComponent = function(self, name)
				--self.components
				local cmp = create_cmp(name)
				cmp.inst = self
				cmp.method_data = {}
				_set_metatable(cmp, cmpmeta)
				self.components[name] = cmp
				if name == "inventoryitem" and self.components.inventoryitemmoisture == nil then
					self:AddComponent("inventoryitemmoisture")
				end
				return cmp
			end,
			RemoveComponent = function(self, name)
				self.components[name] = nil
			end,

			--tags_list
			tags_list = {},
			AddTag = function(self, tag)
				self.tags_list[tag] = true
			end,
			RemoveTag = function(self, tag)
				self.tags_list[tag] = nil
			end,
			AddOrRemoveTag = function(self, tag, condition)
				if condition then
					self.tags_list[tag] = true
				else
					self.tags_list[tag] = nil
				end
			end,
			HasTag = function(self, tag)
				return self.tags_list[tag] == true
			end,
			HasOneOfTags = function(self, tags)
				return has_one_tag(self.tags_list, tags)
			end,
			HasAnyTag = function(self, ...)
				return has_one_tag(self.tags_list, { ... })
			end,
			HasAllTags = function(self, tags)
				if type(tags) ~= "table" then
					return self.tags_list[tags] == true
				end
				for _, tag in pairs(tags) do
					if not self.tags_list[tag] then
						return false
					end
				end
				return true
			end,
			SetPrefabNameOverride = function(self, name)
				self.prefabnameoverride = name
			end,
			SetStateGraph = function()
				inst.sg = make_tab({
				})
				return inst.sg
			end,
			IsValid = function()
				return true
			end,
			IsAsleep = function()
				return false
			end,
			GetTimeAlive = function()
				return 10
			end,
			GetDistanceSqToPoint = function(self, x, y, z)
				local dx = (self.Transform.x or 0) - (x or 0)
				local dz = (self.Transform.z or 0) - (z or 0)
				return dx * dx + dz * dz
			end,
			GetPosition = function()
				return create_vector(inst.Transform.x, inst.Transform.y, inst.Transform.z)
			end,
			GetRotation = function()
				return inst.Transform.rotation or 0
			end,

		}
		local entity_list = {
			parent = false,
			SetParent = function(self, parent)
				self.parent = parent
				inst.parent = parent
			end,
			GetParent = function(self)
				return self.parent
			end,
			AddTransform = function()
				inst.Transform = make_tab({
					x = 0,
					y = 0,
					z = 0,
					rotation = 0,
					SetPosition = function(self, x, y, z)
						self.x, self.y, self.z = x or 0, y or 0, z or 0
					end,
					GetWorldPosition = function(self)
						return self.x or 0, self.y or 0, self.z or 0
					end,
					SetRotation = function(self, rot)
						self.rotation = rot or 0
					end,
					GetRotation = function(self)
						return self.rotation or 0
					end,
					SetFourFaced = empty_fn,
					SetSixFaced = empty_fn,
					SetEightFaced = empty_fn,
					SetScale = empty_fn,
				})
				return inst.Transform
			end,
			AddAnimState = function()
				inst.AnimState = make_tab({
					SetBank = function(self, b)
						inst._cmp_animdata.bank = b
					end,
					SetBuild = function(self, b)
						inst._cmp_animdata.build = b
					end,
					PlayAnimation = function(self, a)
						inst._cmp_animdata.anim = a
					end,
					PushAnimation = function(self, a)
						inst._cmp_animdata.anim = a
					end,
					SetBankAndPlayAnimation = function(self, b, a)
						inst._cmp_animdata.anim = a
						inst._cmp_animdata.bank = b
					end,
					GetCurrentAnimationNumFrames = function(...)
						return 1
					end,
					GetCurrentAnimationFrame = function(...)
						return 0
					end,
					GetCurrentAnimationLength = function(...)
						return 1
					end,
					IsCurrentAnimation = function(self, anim)
						return inst._cmp_animdata.anim == anim
					end,
				})
				return inst.AnimState
			end,
			AddSoundEmitter = function()
				inst.SoundEmitter = make_tab({
					PlaySound = empty_fn,
					KillSound = empty_fn,
				})
				return inst.SoundEmitter
			end,
			AddDynamicShadow = function()
				inst.DynamicShadow = make_tab({
					SetSize = empty_fn,
				})
				return inst.DynamicShadow
			end,
			AddMiniMapEntity = function()
				inst.MiniMapEntity = make_tab({
					SetEnabled = empty_fn,
					SetIcon = empty_fn,
				})
				return inst.MiniMapEntity
			end,
			AddLight = function()
				inst.Light = make_tab({
					enabled = false,
					radius = 0,
					intensity = 0,
					falloff = 0,
					Enable = recorded("Enable", function(self, enable)
						self.enabled = enable == true
					end),
					SetRadius = setfield("SetRadius", "radius"),
					GetRadius = function(self)
						return tonumber(self.radius) or 0
					end,
					SetIntensity = setfield("SetIntensity", "intensity"),
					GetIntensity = function(self)
						return tonumber(self.intensity) or 0
					end,
					SetFalloff = setfield("SetFalloff", "falloff"),
					GetFalloff = function(self)
						return tonumber(self.falloff) or 0
					end,
					SetColour = recorded("SetColour", function(self, r, g, b)
						self.r, self.g, self.b = r, g, b
					end),
				})
				return inst.Light
			end,
			AddVFXEffect = function()
				inst.VFXEffect = make_tab({
				})
				return inst.VFXEffect
			end,
			AddMiniMap = function()
				inst.MiniMap = make_tab({
				})
				return inst.MiniMap
			end,
			AddGroundCreepEntity = function()
				inst.GroundCreepEntity = make_tab({
				})
				return inst.GroundCreepEntity
			end,
			AddLightWatcher = function()
				inst.LightWatcher = make_tab({
				})
				return inst.LightWatcher
			end,
			AddLabel = function()
				inst.Label = make_tab({
				})
				return inst.Label
			end,
			AddPhysicsWaker = function()
				inst.PhysicsWaker = make_tab({
				})
				return inst.PhysicsWaker
			end,
			AddFollower = function()
				inst.Follower = make_tab({
					FollowSymbol = empty_fn,
				})
				return inst.Follower
			end,
			AddNetwork = function()
				inst.Network = make_tab({})
				return inst.Network
			end,
			AddPhysics = function()
				inst.Physics = make_tab({
					GetCollisionMask = function()
						return 0
					end,
					GetRadius = function()
						return 0
					end,
				})
				return inst.Physics
			end,
			SetPristine = empty_fn,
			SetCanSleep = empty_fn,
			GetDebugString = function()
				return ""
			end,
			IsVisible = function()
				return true
			end,
		}
		inst.entity = make_tab(entity_list)
		inst.replica = make_tab({
			equippable = make_tab({
				SetEquipSlot = empty_fn,
				SetPreventUnequipping = empty_fn,
			}),
			inventoryitem = make_tab({
				SetWalkSpeedMult = empty_fn,
				SetEquipRestrictedTag = empty_fn,
				SetAttackRange = empty_fn,
			}),
		})
		_set_metatable(inst, entitymeta)
		return inst
	end
	local function create_world()
		local inst = {
			ismastersim = true,
			tags_list = {},
			state = {
				time = 0,
				cycles = 1,
				isnight = false,
				iswinter = false,
				issnowcovered = false,
				moonphase = "full",
				winterlength = 20,
				remainingdaysinseason = 20,
			},
			components = {
				ambientlighting = make_tab({
					GetVisualAmbientValue = function()
						return 0
					end,
				}),
				nutrients_visual_manager = make_tab({
					UpdateVisualAnimState = empty_fn,
					RegisterNutrientsVisual = empty_fn,
					UnregisterNutrientsVisual = empty_fn,
				}),
				sisturnregistry = make_tab({
					Register = empty_fn,
					Unregister = empty_fn,
				}),
			},
			Map = make_tab({
				IsOceanAtPoint = function()
					return false
				end,
				IsVisualGroundAtPoint = function()
					return true
				end,
				IsFarmableSoilAtPoint = function()
					return true
				end,
				GetPlatformAtPoint = function()
					return nil
				end,
			}),
			AddTag = function(self, tag)
				self.tags_list[tag] = true
			end,
			RemoveTag = function(self, tag)
				self.tags_list[tag] = nil
			end,
			HasTag = function(self, tag)
				return self.tags_list[tag] == true
			end,
			CanFlyingCrossBarriers = function()
				return false
			end,
			AddComponent = function(self, name)
				local cmp = self.components[name]
				if cmp == nil then
					cmp = make_tab({})
					self.components[name] = cmp
				end
				return cmp
			end,
			RemoveComponent = function(self, name)
				self.components[name] = nil
			end,
			PushEvent = empty_fn,
			ListenForEvent = empty_fn,
		}
		_set_metatable(inst, normalmeta)
		return inst
	end
	local ez_net = function(...)
		return {
			set = function(self, v)
				self._value = v
			end,
			_value = 0,
			value = function(self)
				return self._value or 0
			end,
			set_local = function(self, v)
				self._value = v
			end,
		}
	end
	local safe_math = {}
	setmetatable(safe_math, {
		__index = function(_, k)
			return math[k]
		end,
	})
	safe_math.random = function(a, b)
		if a == nil then
			return math.random()
		end
		a = tonumber(a)
		if b == nil then
			if not a or a < 1 then
				return 1
			end
			return math.random(a)
		end
		b = tonumber(b)
		if not a and not b then
			return 1
		elseif not a then
			return b
		elseif not b then
			return a
		elseif b < a then
			return a
		end
		return math.random(a, b)
	end
	safe_math.atan2 = function(y, x)
		y = tonumber(y) or 0
		x = tonumber(x) or 1
		if math.atan2 then
			return math.atan2(y, x)
		end
		return math.atan(x ~= 0 and y / x or 0)
	end
	safe_math.cos = function(v)
		return math.cos(tonumber(v) or 0)
	end
	safe_math.sin = function(v)
		return math.sin(tonumber(v) or 0)
	end
	safe_math.sqrt = function(v)
		return math.sqrt(tonumber(v) or 0)
	end
	safe_math.floor = function(v)
		return math.floor(tonumber(v) or 0)
	end
	safe_math.ceil = function(v)
		return math.ceil(tonumber(v) or 0)
	end
	safe_math.clamp = clamp
	safe_math.min = function(a, b, ...)
		a = tonumber(a) or 0
		if b == nil then
			return a
		end
		b = tonumber(b) or 0
		local v = math.min(a, b)
		for i = 1, select("#", ...) do
			local n = tonumber(select(i, ...))
			if n and n < v then
				v = n
			end
		end
		return v
	end
	safe_math.max = function(a, b, ...)
		a = tonumber(a) or 0
		if b == nil then
			return a
		end
		b = tonumber(b) or 0
		local v = math.max(a, b)
		for i = 1, select("#", ...) do
			local n = tonumber(select(i, ...))
			if n and n > v then
				v = n
			end
		end
		return v
	end
	local proxy_table = {
	}
	local proxy_map = {}
	local create_new_proxy_table
	local proxy_index_value
	local function get_table_metacall(tab)
		local meta = type(tab) == "table" and getmetatable(tab) or nil
		return type(meta) == "table" and rawget(meta, "__call") or nil
	end
	local function wrap_proxy_value(value)
		local valuetype = type(value)
		if valuetype == "function" then
			return empty_fn
		elseif valuetype == "table" then
			return create_new_proxy_table(value)
		end
		return value
	end
	function proxy_index_value(tab, k)
		if type(tab) ~= "table" then
			return
		end
		local value = rawget(tab, k)
		if value ~= nil then
			return value
		end
		local watching = rawget(tab, "__watching__")
		if not watching then
			rawset(tab, "__watching__", true)
			local ok, v = pcall(function()
				return tab[k]
			end)
			rawset(tab, "__watching__", watching)
			if ok then
				return v
			end
			return
		else
			return
		end
	end

	function create_new_proxy_table(anothertab)
		if rawget(anothertab, "_ctor") then
			return special_table
		end
		if not proxy_table[anothertab] then
			local new = {}
			proxy_table[anothertab] = new
			proxy_map[new] = anothertab
			local proxymeta = {
				__index = function(t, k)
					return wrap_proxy_value(proxy_index_value(proxy_map[t], k))
				end,
			}
			if get_table_metacall(anothertab) ~= nil then
				proxymeta.__call = function()
					return special_table
				end
			end
			setmetatable(new, proxymeta)

			-- 保留数组长度，但不放入原始子表
			local arraylen = #anothertab
			for i = 1, arraylen do
				local value = rawget(anothertab, i)
				rawset(
					new,
					i,
					value == nil and special_table
					or wrap_proxy_value(value)
				)
			end
			return new
		else
			return proxy_table[anothertab]
		end
	end

	local globalmeta = {
		__index = function(t, k)
			local g_v = rawget(_G, k)
			if g_v ~= nil then
				if type(g_v) == "string" then
					return g_v
				end
				if type(g_v) == "number" then
					return g_v
				end
				if type(g_v) == "boolean" then
					return g_v
				end
				if type(g_v) == "table" then
					return create_new_proxy_table(g_v)
				end
			end

			return special_table
		end,
	}
	local nulltab = {}
	local require_cache = {}
	local function get_proxy_table(t)
		if type(t) == "table" then
			local proxy = proxy_map[t]
			if type(proxy) == "table" then
				return proxy
			end
		end
	end
	local function proxy_next(t, k)
		if type(t) ~= "table" or rawget(t, "__mark__") then
			return
		end
		local proxy = get_proxy_table(t)
		if proxy then
			local nk, nv = next(proxy, k)
			return nk, wrap_proxy_value(nv)
		end
		return next(t, k)
	end
	local function proxy_pairs(t)
		if type(t) ~= "table" or rawget(t, "__mark__") then
			return next, nulltab, nil
		end
		local proxy = get_proxy_table(t)
		if proxy then
			return proxy_next, t, nil
		end
		return pairs(t)
	end
	local function proxy_ipairs_iter(t, i)
		i = i + 1
		local value = rawget(t, i)
		if value ~= nil then
			return i, wrap_proxy_value(value)
		end
	end
	local function proxy_ipairs(t)
		if type(t) ~= "table" or rawget(t, "__mark__") then
			return ipairs(nulltab)
		end
		local proxy = get_proxy_table(t)
		if proxy then
			return proxy_ipairs_iter, proxy, 0
		end
		return ipairs(t)
	end
	local function wrap_proxy_unpack_result(...)
		local count = select("#", ...)
		if count == 0 then
			return
		end
		local values = { ... }
		for index = 1, count do
			values[index] = wrap_proxy_value(values[index])
		end
		return unpack(values, 1, count)
	end
	local function proxy_unpack(t, i, j)
		if type(t) ~= "table" or rawget(t, "__mark__") then
			return unpack(t, i, j)
		end
		local proxy = get_proxy_table(t)
		if proxy then
			return wrap_proxy_unpack_result(unpack(proxy, i, j))
		end
		return unpack(t, i, j)
	end
	local function add_component(inst, name)
		if inst and inst.AddComponent then
			return inst:AddComponent(name)
		end
		local cmp = create_cmp(name)
		cmp.inst = inst
		cmp.method_data = {}
		_set_metatable(cmp, cmpmeta)
		inst.components[name] = cmp
		return cmp
	end
	local function make_burnable(inst, level, time, offset, structure, sym)
		local burnable = add_component(inst, "burnable")
		burnable:SetFXLevel(level)
		burnable:SetBurnTime(time)
		burnable:AddBurnFX("fire", offset or create_vector(0, 0, 0), sym)
		return burnable
	end
	local function make_propagator(inst, flashpoint)
		local propagator = add_component(inst, "propagator")
		propagator.acceptsheat = true
		propagator.flashpoint = flashpoint
		return propagator
	end
	local function make_burnable_character(inst, level, time, sym, offset)
		local burnable = make_burnable(inst, level, time, offset or create_vector(0, 0, 0.1), false, sym)
		burnable.canlight = false
		local propagator = make_propagator(inst, 5)
		propagator.acceptsheat = false
		return burnable, propagator
	end
	local function make_freezable_character(inst, level, resistance, sym, offset)
		local freezable = add_component(inst, "freezable")
		freezable:SetShatterFXLevel(level)
		if resistance then
			freezable:SetResistance(resistance)
		end
		freezable:AddShatterFX("shatter", offset or create_vector(0, 0, 0), sym)
		return freezable
	end
	local function make_deployable_fertilizer_pristine(inst)
		inst:AddTag("deployable")
		inst:AddTag("tile_deploy")
		inst.overridedeployplacername = "gridplacer_farmablesoil"
	end
	local function make_deployable_fertilizer(inst)
		local deployable = add_component(inst, "deployable")
		deployable:SetDeployMode(DEPLOYMODE and DEPLOYMODE.CUSTOM or "custom")
		deployable:SetUseGridPlacer(false)
		deployable.keep_in_inventory_on_deploy = true
		return deployable
	end
	local function make_forge_repairable(inst, material, onbroken, onrepaired)
		local forgerepairable = add_component(inst, "forgerepairable")
		forgerepairable:SetRepairMaterial(material)
		forgerepairable:SetOnRepaired(onrepaired)
		return forgerepairable
	end
	local function ensure_component(inst, name)
		if inst.components[name] == nil then
			return inst:AddComponent(name)
		end
		return inst.components[name]
	end
	local function make_physics(inst, group, rad, height, tag)
		if tag then
			inst:AddTag(tag)
		end
		local phys = inst.entity:AddPhysics()
		phys:SetCollisionGroup(group or 0)
		if height then
			phys:SetCapsule(rad or .5, height)
		elseif rad then
			phys:SetSphere(rad)
		end
		return phys
	end
	local function change_physics(inst, group, rad, height)
		local phys = inst.Physics or inst.entity:AddPhysics()
		phys:SetCollisionGroup(group or 0)
		if rad then
			phys:SetCapsule(rad, height or 1)
		end
		return phys
	end
	local function make_snow_covered_pristine(inst)
		inst:AddTag("SnowCovered")
		inst.AnimState:Hide("snow")
	end
	local function make_lunar_hail_buildup(inst)
		local lunarhailbuildup = ensure_component(inst, "lunarhailbuildup")
		inst.updatelunarhailbuilduptask = inst:DoTaskInTime(0, empty_fn)
		return lunarhailbuildup
	end
	local function remove_lunar_hail_buildup(inst)
		inst:RemoveComponent("lunarhailbuildup")
		if inst.updatelunarhailbuilduptask then
			inst.updatelunarhailbuilduptask:Cancel()
			inst.updatelunarhailbuilduptask = nil
		end
	end
	local function make_snow_covered(inst)
		if not inst:HasTag("SnowCovered") then
			make_snow_covered_pristine(inst)
		end
		inst.AnimState:Hide("snow")
		return make_lunar_hail_buildup(inst)
	end
	local function make_small_perishable_creature_pristine(inst)
		inst:AddTag("show_spoilage")
	end
	local function make_small_perishable_creature(inst, starvetime, oninventory, ondropped, always_perishing)
		make_small_perishable_creature_pristine(inst)
		local perishable = ensure_component(inst, "perishable")
		perishable:SetPerishTime(starvetime)
		if always_perishing then
			perishable:StartPerishing()
		else
			perishable:StopPerishing()
		end
		perishable:SetOnPerishFn(function()
		end)
		local inventoryitem = ensure_component(inst, "inventoryitem")
		inventoryitem:SetOnPutInInventoryFn(oninventory or empty_fn)
		inventoryitem:SetOnDroppedFn(ondropped or empty_fn)
		return perishable
	end
	local function make_feedable_small_livestock_pristine(inst)
		make_small_perishable_creature_pristine(inst)
		inst:AddTag("small_livestock")
	end
	local function make_feedable_small_livestock(inst, starvetime, oninventory, ondropped)
		make_feedable_small_livestock_pristine(inst)
		local eater = ensure_component(inst, "eater")
		eater:SetOnEatFn(function(food)
			if inst.components.perishable then
				inst.components.perishable:SetPercent(1)
			end
		end)
		return make_small_perishable_creature(inst, starvetime, oninventory, ondropped)
	end
	local function make_hauntable(inst, cooldown, haunt_value)
		local hauntable = ensure_component(inst, "hauntable")
		hauntable.cooldown = cooldown
		hauntable:SetHauntValue(haunt_value)
		return hauntable
	end
	local function make_inventory_floatable(inst, size, offset, scale, swap_bank, float_index, swap_data)
		local floater = ensure_component(inst, "floater")
		floater:SetSize(size or "small")
		if offset then
			floater:SetVerticalOffset(offset)
		end
		if scale then
			floater:SetScale(scale)
		end
		if swap_bank then
			floater:SetBankSwapOnFloat(swap_bank, float_index, swap_data)
		elseif swap_data then
			floater:SetSwapData(swap_data)
		end
		return floater
	end
	local function make_fumarole_tool_pristine(inst)
		inst:AddTag("heatrock")
		inst:AddTag("HASHEATER")
		inst:AddTag("inventoryitemtemperature")
		inst:AddTag("show_broken_ui")
	end
	local function make_fumarole_tool(inst, heatonuse, onbroken, onrepaired, onupdatetemperature)
		local inspectable = ensure_component(inst, "inspectable")
		inspectable.getstatus = function()
			return "LUKEWARM"
		end
		local inventoryitem = ensure_component(inst, "inventoryitem")
		inventoryitem:EnableTemperature(true)
		inventoryitem:SetTemperatureModifier("fumaroletool_mod", TUNING and TUNING.FUMAROLETOOL_TEMP_MODIFIER or 0)
		inventoryitem:SetMinTemperature(TUNING and TUNING.FUMAROLETOOL_MINTEMP or 0)
		inventoryitem:SetMaxTemperature(TUNING and TUNING.FUMAROLETOOL_MAXTEMP or 0)
		ensure_component(inst, "inventoryitemtemperature")
		ensure_component(inst, "heater")
		local fumaroletool = ensure_component(inst, "fumaroletool")
		fumaroletool:SetOnBroken(onbroken)
		fumaroletool:SetOnRepaired(onrepaired)
		fumaroletool:SetHeatOnUse(heatonuse)
		fumaroletool:SetOnUpdateTemperatureRange(onupdatetemperature)
		ensure_component(inst, "damagetypebonus"):AddBonusCallback(empty_fn)
		return fumaroletool
	end
	local function make_crafting_material_recycler(inst, data)
		inst._recycle_materials_data_source = data
		inst.onPreBuilt = empty_fn
		inst.OnBuiltFn = empty_fn
	end
	local function make_waxable_plant(inst)
		local waxable = ensure_component(inst, "waxable")
		waxable:SetWaxfn(empty_fn)
		waxable:SetNeedsSpray()
		return waxable
	end
	local function make_item_socketable_client(inst, socketname)
		local socketable = ensure_component(inst, "socketable")
		socketable:SetSocketName(socketname)
		return socketable
	end
	local function make_item_socketable_server(inst)
		ensure_component(inst, "useabletargeteditem")
		return ensure_component(inst, "socketable")
	end
	local function add_to_regrowth_manager(inst)
		inst.OnStartRegrowth = empty_fn
		inst:ListenForEvent("onremove", empty_fn)
		inst:ListenForEvent("despawnedfromhaunt", empty_fn)
	end
	local function remove_from_regrowth_manager(inst)
		inst.OnStartRegrowth = nil
		inst:RemoveEventCallback("onremove", empty_fn)
		inst:RemoveEventCallback("despawnedfromhaunt", empty_fn)
	end
	local require_method_map = {
		["easing"] = true,
		["prefabs/balloons_common"] = true,
		["prefabs/carnivalgame_common"] = true,
		["prefabs/corpses_defs"] = true,
		["prefabs/player_common"] = true,
		["prefabs/pocketwatch_common"] = true,
		["prefabs/ruinsrespawner"] = true,
		["prefabs/boatrace_common"] = true,
		["prefabs/torchfire_common"] = true,
		["prefabs/world_network"] = true,
		["prefabs/waxed_plant_common"] = true,
		["prefabs/lighterfire_common"] = true,
	}
	local global_fake_env
	global_fake_env = {
		TheWorld = create_world(),
		TheSim = make_tab({
			FindEntities = function()
				return {}
			end,
			RegisterPrefab = empty_fn,
			GetTickTime = function()
				return 1 / 30
			end,
			GetTimeScale = function()
				return 1
			end,
		}),
		TheCamera = make_tab({
			GetDownVec = function()
				return create_vector(1, 0, 0)
			end,
		}),
		TheNet = make_tab({
			IsDedicated = function()
				return false
			end,
		}),
		TheFocalPoint = make_tab({
			components = {
				focalpoint = make_tab({
					StartFocusSource = empty_fn,
					StopFocusSource = empty_fn,
				}),
			},
		}),
		ThePlayer = nil,
		AllPlayers = {},
		GetMaxItemSlots = function(...)
			return 1
		end,
		GetGameModeProperty = function()
			return false
		end,
		CreateEntity = function()
			local inst = create_entity()
			inst.prefab = "prefab"
			return inst
		end,
		SpawnPrefab = function(prefab)
			local inst = create_entity()
			_set_metatable(inst, normalmeta)
			inst.prefab = prefab
			inst:AddComponent("highlightchild")
			return inst
		end,
		Asset = function(...)
			return { ... }
		end,
		Prefab = function(name, fn, assets, deps, force_path_search)
			local self = {}
			self.name = string.sub(name, string.find(name, "[^/]*$")) --remove any legacy path on the name
			self.fn = fn
			return self
		end,
		Vector3 = function(x, y, z)
			return create_vector(x, y, z)
		end,
		GetTime = function()
			return 0
		end,
		GetTaskRemaining = function()
			return 0
		end,
		UnitRand = function()
			return 0
		end,
		CreateSphereEmitter = function()
			return function()
				return 0, 0, 0
			end
		end,
		CreateCircleEmitter = function()
			return function()
				return 0, 0, 0
			end
		end,
		Lerp = function(a, b, t)
			a = tonumber(a) or 0
			b = tonumber(b) or a
			t = tonumber(t) or 0
			return a + (b - a) * t
		end,
		GetRandomItem = function(t)
			return type(t) == "table" and t[1] or nil
		end,
		GetRandomMinMax = function(min, max)
			return tonumber(min) or tonumber(max) or 0
		end,
		GetRandomWithVariance = function(base, variance)
			return tonumber(base) or tonumber(variance) or 0
		end,
		GetCombatFxSize = function(ent)
			local radius = ent and rawget(ent, "override_combat_fx_radius") or nil
			local size = ent and rawget(ent, "override_combat_fx_size") or nil
			local height = ent and rawget(ent, "override_combat_fx_height") or nil
			return tonumber(radius) or .5, type(size) == "string" and size or "small",
				type(height) == "string" and height or "low"
		end,
		FunctionOrValue = function(value, ...)
			return type(value) == "function" and value(...) or value
		end,
		Clamp = clamp,
		Remap = function(value, oldmin, oldmax, newmin, newmax)
			value = tonumber(value) or tonumber(oldmin) or 0
			oldmin = tonumber(oldmin) or 0
			oldmax = tonumber(oldmax) or oldmin
			newmin = tonumber(newmin) or 0
			newmax = tonumber(newmax) or newmin
			if oldmax == oldmin then
				return newmin
			end
			return newmin + (value - oldmin) * (newmax - newmin) / (oldmax - oldmin)
		end,
		IsSpecialEventActive = function()
			return false
		end,
		SpringCombatMod = function(value)
			return value
		end,
		print = function(...)
			print(...)
		end,
		ipairs = proxy_ipairs,
		pairs = proxy_pairs,
		net_ushortarray = function(...)
			return {
				set = function()

				end,
				value = function()
					return {}
				end,
				set_local = function()

				end,
			}
		end,
		net_smallbytearray = function(...)
			return {
				set = function()

				end,
				value = function()
					return {}
				end,
				set_local = function()

				end,
			}
		end,
		net_bytearray = function(...)
			return {
				set = function()

				end,
				value = function()
					return {}
				end,
				set_local = function()

				end,
			}
		end,
		net_entity = function(...)
			return {
				set = function()

				end,
				value = function()
					return
				end,
				set_local = function()

				end,
			}
		end,
		net_string = function(...)
			return {
				set = function()

				end,
				value = function()
					return "1"
				end,
				set_local = function()

				end,
			}
		end,
		net_hash = ez_net,
		net_float = ez_net,
		net_uint = ez_net,
		net_int = ez_net,
		net_ushortint = ez_net,
		net_shortint = ez_net,
		net_byte = ez_net,
		net_smallbyte = ez_net,
		net_tinybyte = ez_net,
		net_bool = function(...)
			return {
				_value = false,
				set = function(self, v)
					self._value = v == true
				end,
				value = function(self)
					return self._value == true
				end,
				set_local = function(self, v)
					self._value = v == true
				end,
			}
		end,
		math = safe_math,
		table = table,
		string = string,
		assert = function(value, ...)
			return value, ...
		end,
		bit = bit,
		error = empty_fn,
		getmetatable = getmetatable,
		setmetatable = setmetatable,
		type = type,
		next = proxy_next,
		tonumber = tonumber,
		rawget = rawget,
		rawset = rawset,
		select = select,
		unpack = proxy_unpack,
		tostring = tostring,

		ConcatArrays = ConcatArrays,
		--require
		require = function(path)
			if require_cache[path] then
				return require_cache[path]
			end
			clientprint("require_cache:" .. path)
			if require_method_map[path] then
				local oldresult = require(path)
				local object
				if type(oldresult) == "table" then
					for k, v in pairs(oldresult) do
						if type(v) == "function" then
							object = v
							break
						end
					end
				elseif type(oldresult) == "function" then
					object = oldresult
				end
				if object then
					local function loadthisfile(object)
						local source = debug.getinfo(object, "S").source
						local fn, r = kleiloadlua(source)
						setfenv(fn, global_fake_env)
						local a, b = pcall(fn)
						if a then
							return b
						end
					end
					require_cache[path] = loadthisfile(object)
					return require_cache[path]
				end
			end


			local oldresult = require(path)
			require_cache[path] = wrap_proxy_value(oldresult)
			return require_cache[path]
		end,

		--some fn
		DefaultIgniteFn = empty_fn,
		DefaultBurnFn = empty_fn,
		DefaultBurntFn = empty_fn,
		DefaultExtinguishFn = empty_fn,
		DefaultBurntStructureFn = empty_fn,
		DefaultBurntCorpseFn = empty_fn,
		DefaultExtinguishCorpseFn = empty_fn,
		MakeSmallBurnable = function(inst, time, offset, structure, sym)
			return make_burnable(inst, 2, time or 10, offset, structure, sym)
		end,
		MakeMediumBurnable = function(inst, time, offset, structure, sym)
			return make_burnable(inst, 3, time or 20, offset, structure, sym)
		end,
		MakeLargeBurnable = function(inst, time, offset, structure, sym)
			return make_burnable(inst, 4, time or 30, offset, structure, sym)
		end,
		MakeSmallPropagator = function(inst)
			return make_propagator(inst, 5)
		end,
		MakeMediumPropagator = function(inst)
			return make_propagator(inst, 15)
		end,
		MakeLargePropagator = function(inst)
			return make_propagator(inst, 45)
		end,
		MakeSmallBurnableCharacter = function(inst, sym, offset)
			return make_burnable_character(inst, 1, 6, sym, offset)
		end,
		MakeMediumBurnableCharacter = function(inst, sym, offset)
			return make_burnable_character(inst, 2, 8, sym, offset)
		end,
		MakeLargeBurnableCharacter = function(inst, sym, offset, scale)
			return make_burnable_character(inst, 3, 10, sym, offset)
		end,
		MakeSmallBurnableCorpse = function(inst, time, sym, offset, scale)
			return make_burnable_character(inst, 1, time or 6, sym, offset)
		end,
		MakeMediumBurnableCorpse = function(inst, time, sym, offset, scale)
			return make_burnable_character(inst, 2, time or 8, sym, offset)
		end,
		MakeLargeBurnableCorpse = function(inst, time, sym, offset, scale)
			return make_burnable_character(inst, 3, time or 10, sym, offset)
		end,
		MakeTinyFreezableCharacter = function(inst, sym, offset)
			return make_freezable_character(inst, 1, nil, sym, offset)
		end,
		MakeSmallFreezableCharacter = function(inst, sym, offset)
			return make_freezable_character(inst, 2, nil, sym, offset)
		end,
		MakeMediumFreezableCharacter = function(inst, sym, offset)
			return make_freezable_character(inst, 3, 2, sym, offset)
		end,
		MakeLargeFreezableCharacter = function(inst, sym, offset)
			return make_freezable_character(inst, 4, 3, sym, offset)
		end,
		MakeHugeFreezableCharacter = function(inst, sym, offset)
			return make_freezable_character(inst, 5, 4, sym, offset)
		end,
		MakeInventoryPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.ITEMS or 0, rad or .5)
		end,
		MakeProjectilePhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.ITEMS or 0, rad or .5)
		end,
		MakeCharacterPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.CHARACTERS or 0, rad or .5, 1)
		end,
		MakeFlyingCharacterPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.FLYERS or 0, rad or .5, 1)
		end,
		MakeTinyFlyingCharacterPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.FLYERS or 0, rad or .25, 1)
		end,
		MakeGiantCharacterPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.GIANTS or 0, rad or 1, 1)
		end,
		MakeFlyingGiantCharacterPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.GIANTS or 0, rad or 1, 1)
		end,
		MakeGhostPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.CHARACTERS or 0, rad or .5, 1)
		end,
		MakeTinyGhostPhysics = function(inst, mass, rad)
			return make_physics(inst, COLLISION and COLLISION.CHARACTERS or 0, rad or .25, 1)
		end,
		ChangeToGhostPhysics = function(inst)
			return change_physics(inst, COLLISION and COLLISION.CHARACTERS or 0)
		end,
		ChangeToFlyingCharacterPhysics = function(inst, mass, rad)
			return change_physics(inst, COLLISION and COLLISION.FLYERS or 0, rad)
		end,
		ChangeToCharacterPhysics = function(inst, mass, rad)
			return change_physics(inst, COLLISION and COLLISION.CHARACTERS or 0, rad)
		end,
		ChangeToGiantCharacterPhysics = function(inst, mass, rad)
			return change_physics(inst, COLLISION and COLLISION.GIANTS or 0, rad)
		end,
		ChangeToObstaclePhysics = function(inst, rad, height)
			inst:AddTag("blocker")
			return change_physics(inst, COLLISION and COLLISION.OBSTACLES or 0, rad, height or 2)
		end,
		ChangeToWaterObstaclePhysics = function(inst)
			inst:AddTag("blocker")
			return change_physics(inst, COLLISION and COLLISION.OBSTACLES or 0)
		end,
		ChangeToInventoryItemPhysics = function(inst, mass, rad)
			return change_physics(inst, COLLISION and COLLISION.ITEMS or 0, rad)
		end,
		MakeCollidesWithElectricField = function(inst)
			inst.Physics:CollidesWith(COLLISION and COLLISION.GROUND or 0)
		end,
		ClearCollidesWithElectricField = function(inst)
			inst.Physics:ClearCollidesWith(COLLISION and COLLISION.GROUND or 0)
		end,
		ChangeToInventoryPhysics = function(inst)
			return change_physics(inst, COLLISION and COLLISION.OBSTACLES or 0)
		end,
		MakeObstaclePhysics = function(inst, rad, height)
			return make_physics(inst, COLLISION and COLLISION.OBSTACLES or 0, rad or .5, height or 2, "blocker")
		end,
		MakeWaterObstaclePhysics = function(inst, rad, height, restitution)
			local phys = make_physics(inst, COLLISION and COLLISION.OBSTACLES or 0, rad or .5, height or 2, "blocker")
			ensure_component(inst, "waterphysics").restitution = restitution
			return phys
		end,
		MakeSmallObstaclePhysics = function(inst, rad, height)
			return make_physics(inst, COLLISION and COLLISION.SMALLOBSTACLES or 0, rad or .25, height or 2, "blocker")
		end,
		MakeHeavyObstaclePhysics = function(inst, rad, height)
			return make_physics(inst, COLLISION and COLLISION.OBSTACLES or 0, rad or .5, height or 2, "blocker")
		end,
		MakeSmallHeavyObstaclePhysics = function(inst, rad, height)
			return make_physics(inst, COLLISION and COLLISION.SMALLOBSTACLES or 0, rad or .25, height or 2, "blocker")
		end,
		MakePondPhysics = function(inst, rad, height)
			return make_physics(inst, COLLISION and COLLISION.OBSTACLES or 0, rad or .5, height or 2, "blocker")
		end,
		MakeGolfBallPhysics = function(inst, rad)
			return make_physics(inst, COLLISION and COLLISION.ITEMS or 0, rad or .2)
		end,
		MakeGolfObstaclePhysics = function(inst, rad, golfradoverride)
			inst._golfradoverride = golfradoverride
			return make_physics(inst, COLLISION and COLLISION.SMALLOBSTACLES or 0, rad or .2)
		end,
		RemovePhysicsColliders = function(inst)
			if inst.Physics then
				inst.Physics:ClearCollisionMask()
			end
		end,
		MakeNoGrowInWinter = function(inst)
			if inst.components.pickable then
				inst.components.pickable:WatchWorldState("iswinter", empty_fn)
			end
		end,
		MakeSnowCoveredPristine = make_snow_covered_pristine,
		MakeSnowCovered = make_snow_covered,
		UpdateLunarHailBuildup = empty_fn,
		MakeLunarHailBuildup = make_lunar_hail_buildup,
		RemoveLunarHailBuildup = remove_lunar_hail_buildup,
		SetLunarHailBuildupAmountSmall = function(inst)
			if inst.components.lunarhailbuildup then
				inst.components.lunarhailbuildup:SetTotalWorkAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_TOTAL_WORK_AMOUNT_SMALL or 1)
				inst.components.lunarhailbuildup:SetMoonGlassAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_MOONGLASS_AMOUNT_SMALL or 1)
			end
		end,
		SetLunarHailBuildupAmountMedium = function(inst)
			if inst.components.lunarhailbuildup then
				inst.components.lunarhailbuildup:SetTotalWorkAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_TOTAL_WORK_AMOUNT_MEDIUM or 1)
				inst.components.lunarhailbuildup:SetMoonGlassAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_MOONGLASS_AMOUNT_MEDIUM or 1)
			end
		end,
		SetLunarHailBuildupAmountLarge = function(inst)
			if inst.components.lunarhailbuildup then
				inst.components.lunarhailbuildup:SetTotalWorkAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_TOTAL_WORK_AMOUNT_LARGE or 1)
				inst.components.lunarhailbuildup:SetMoonGlassAmount(TUNING and
					TUNING.LUNARHAIL_BUILDUP_MOONGLASS_AMOUNT_LARGE or 1)
			end
		end,
		MakeSmallPerishableCreaturePristine = make_small_perishable_creature_pristine,
		MakeSmallPerishableCreature = function(inst, starvetime, oninventory, ondropped)
			return make_small_perishable_creature(inst, starvetime, oninventory, ondropped, false)
		end,
		MakeSmallPerishableCreatureAlwaysPerishing = function(inst, starvetime, oninventory, ondropped)
			return make_small_perishable_creature(inst, starvetime, oninventory, ondropped, true)
		end,
		MakeFeedableSmallLivestockPristine = make_feedable_small_livestock_pristine,
		MakeFeedableSmallLivestock = make_feedable_small_livestock,
		MakeFeedablePetPristine = make_feedable_small_livestock_pristine,
		MakeFeedablePet = make_feedable_small_livestock,
		MakeDragonflyBait = empty_fn,
		MaybeMakeDragonflyBait = empty_fn,
		RemoveDragonflyBait = empty_fn,
		MakeDeployableFertilizerPristine = make_deployable_fertilizer_pristine,
		MakeDeployableFertilizer = make_deployable_fertilizer,
		MakeForgeRepairable = make_forge_repairable,
		AddHauntableDropItemOrWork = function(inst)
			local hauntable = make_hauntable(inst)
			hauntable:SetOnHauntFn(empty_fn)
			return hauntable
		end,
		ToggleOffCharacterCollisions = function(inst)
			inst.Physics:ClearCollidesWith(COLLISION and COLLISION.CHARACTERS or 0)
		end,
		ToggleOnCharacterCollisions = function(inst)
			inst.Physics:CollidesWith(COLLISION and COLLISION.CHARACTERS or 0)
		end,
		ToggleOffAllObjectCollisions = function(inst)
			inst.Physics:ClearCollisionMask()
		end,
		ToggleOnAllObjectCollisionsAt = function(inst, x, z)
			inst.Physics:Teleport(x or 0, 0, z or 0)
		end,
		PreventCharacterCollisionsWithPlacedObjects = function(inst)
			inst.Physics:ClearCollidesWith(COLLISION and COLLISION.CHARACTERS or 0)
		end,
		PreventTargetingOnAttacked = function(inst, attacker, tag)
			return attacker and attacker.HasTag and attacker:HasTag(tag) or false
		end,
		AddDefaultRippleSymbols = function(inst, ripple, shadow)
			if ripple then
				inst.AnimState:OverrideSymbol("water_ripple", "swimming_ripple", "water_ripple")
			end
			if shadow then
				inst.AnimState:OverrideSymbol("water_shadow", "swimming_ripple", "water_shadow")
			end
		end,
		MakeInventoryFloatable = make_inventory_floatable,
		MakeItemSocketable_Client = make_item_socketable_client,
		MakeItemSocketable_Server = make_item_socketable_server,
		RemoveFromRegrowthManager = remove_from_regrowth_manager,
		AddToRegrowthManager = add_to_regrowth_manager,
		MakeWaxablePlant = make_waxable_plant,
		MakeCraftingMaterialRecycler = make_crafting_material_recycler,
		IsWithinHermitCrabArea = function()
			return false
		end,
		MakeHermitCrabAreaListener = function(inst, callbackfn)
			if callbackfn then
				callbackfn(inst, false)
			end
		end,
		MakeFumaroleToolPristine = make_fumarole_tool_pristine,
		MakeFumaroleTool = make_fumarole_tool,
		MakeHauntable = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunch = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunchAndSmash = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableWork = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableWorkAndIgnite = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableFreeze = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableIgnite = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunchAndIgnite = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableChangePrefab = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunchOrChangePrefab = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntablePerish = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunchAndPerish = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntablePanic = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntablePanicAndIgnite = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntablePlayAnim = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableGoToState = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableGoToStateWithChanceFunction = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableDropFirstItem = function(inst)
			return make_hauntable(inst)
		end,
		MakeHauntableLaunchAndDropFirstItem = function(inst)
			return make_hauntable(inst)
		end,
		AddHauntableCustomReaction = function(inst)
			return make_hauntable(inst)
		end,
	}
	local function clean_global_env()
		global_fake_env.AllPlayers = {}
	end

	local function get_data(inst)
		if not rawget(inst, "components") then
			return
		end
		setmetatable(inst.components, nil)
		local cmp_savedata = {}
		local entity_animdata = inst._cmp_animdata or {}
		local animdata = {
			build = entity_animdata.build and tostring(entity_animdata.build),
			bank = entity_animdata.bank and tostring(entity_animdata.bank),
			anim = entity_animdata.anim and tostring(entity_animdata.anim),
		}
		for k, v in pairs(inst.components) do
			if type(v) == "table" and rawget(v, "method_data") then
				setmetatable(v, nil)
				cmp_savedata[k] = v.method_data
			end
		end
		cmp_savedata.AnimState = animdata
		return {
			AnimState = animdata,
			animdata = animdata,
			cmp_savedata = cmp_savedata,
			components = inst.components,
			tags_list = inst.tags_list,
		}
	end
	local remember_path = true
	GLOBAL._loading_filename = nil
	local oldloadfile = GLOBAL.loadfile
	function GLOBAL.loadfile(filename, ...)
		if remember_path then
			GLOBAL._loading_filename = filename
		end

		local result = oldloadfile(filename, ...)
		return result
	end

	local constructor = GLOBAL.Prefab._ctor
	GLOBAL.Prefab._ctor = function(self, ...)
		constructor(self, ...)
		if remember_path and GLOBAL._loading_filename then
			self._loading_filename = GLOBAL._loading_filename
		end
	end
	local ban_prefab = {
		world = true,
		forest = true,
		cave = true,
		lavaarena = true,
		quagmire = true,
		global = true,
		quagmire_food = true,
		quagmire_burnt_ingredients = true,
		lavaarena_healblooms = true,
		lavaarena_bloomsleepdebuff = true,
	}
	local ban_prefab_patterns = {
		"^lavaarenastage_",
		"^quagmirestage_",
		"^lavaarena_battlestandard_",
	}
	local function is_ban_prefab(prefab)
		if ban_prefab[prefab] then
			return true
		end
		for _, pattern in ipairs(ban_prefab_patterns) do
			if string.find(prefab, pattern) then
				return true
			end
		end
		return false
	end

	local save_ret = {}
	local working = false
	local function test_prefab_data(prefab)
		if remember_path then
			remember_path = false
			GLOBAL._loading_filename = nil
		end
		if not GLOBAL.Prefabs[prefab] or not GLOBAL.Prefabs[prefab].fn then
			return
		end
		if is_ban_prefab(prefab) then
			return
		end
		if string.find(prefab, "_placer") then
			return
		end
		if not working then
			rebuild_special_table()
			working = true

			local prefabfn = save_ret[prefab]
			if not prefabfn then
				local this = global_fake_env
				clean_global_env()
				_set_metatable(this, globalmeta)
				local source = debug.getinfo(GLOBAL.Prefabs[prefab].fn, "S").source
				local fn, r = kleiloadlua(source)
				if type(fn) ~= "function" then
					clientprint("CMP_util_errorload:prefab[" .. prefab .. "] source[" .. source .. "]")
					return
				end
				setfenv(fn, this)
				pcall(function()
					local ret = { fn() }
					for k, v in pairs(ret) do
						if type(v) == "table" and v.name == prefab and v.fn then
							prefabfn = v.fn
							save_ret[v.name] = v.fn
						end
					end
				end)
			end
			if not prefabfn then
				if GLOBAL.Prefabs[prefab]._loading_filename then
					local this = global_fake_env
					clean_global_env()
					_set_metatable(this, globalmeta)
					local source = GLOBAL.Prefabs[prefab]._loading_filename
					local fn, r = loadfile(source)
					if type(fn) ~= "function" then
						clientprint("CMP_util_errorload:prefab[" .. prefab .. "] source[" .. source .. "]")
						return
					end
					setfenv(fn, this)
					pcall(function()
						local ret = { fn() }
						for k, v in pairs(ret) do
							if type(v) == "table" and v.name == prefab and v.fn then
								prefabfn = v.fn
								save_ret[v.name] = v.fn
							end
						end
					end)
				end
			end
			local inst
			if prefabfn then
				clientprint("CMP_util_try_runing[if game stuck here,try communicate with author【】]:" .. prefab)
				local statue, message = pcall(function()
					inst = prefabfn(global_fake_env.TheSim)
				end)
				if not statue then
					local a = string.format("CMP_util_errorload:prefab[%s] message[%s]", prefab or "",
						message or "")
					clientprint(a)
					--error(message)
				end
			else

			end

			working = false
			if inst and rawget(inst, "components") then
				return get_data(inst)
			else
				local a = string.format("CMP_util_errornoinst:prefab[%s] _loading_filename[%s] source[%s] ", prefab or "",
					GLOBAL.Prefabs[prefab]._loading_filename or "",
					debug.getinfo(GLOBAL.Prefabs[prefab].fn, "S").source or "")
				clientprint(a)
			end
		end
	end
	local remember_list = {}
	function CMP_util:GetPrefabData(prefab)
		if remember_list[prefab] == false then
			return
		elseif remember_list[prefab] then
			return remember_list[prefab]
		else
			local data = test_prefab_data(prefab)
			if data then
				remember_list[prefab] = data
			else
				remember_list[prefab] = false
			end
			return remember_list[prefab]
		end
	end

	function CMP_util:GetAnimData(data)
		if type(data) == "string" then
			data = CMP_util:GetPrefabData(data)
		end
		return data and data.AnimState
	end

	function CMP_util:CalculateCMPData(data, cmpname, methodname, index)
		if type(data) == "string" then
			data = CMP_util:GetPrefabData(data)
		end
		return data and data.cmp_savedata and data.cmp_savedata[cmpname]
			and data.cmp_savedata[cmpname][methodname]
			and data.cmp_savedata[cmpname][methodname][index]
	end

	function CMP_util:GetCMPData(data, cmpname, index)
		if type(data) == "string" then
			data = CMP_util:GetPrefabData(data)
		end
		return data and data.components and data.components[cmpname]
			and data.components[cmpname][index]
	end

	function CMP_util:GetCMP(data, cmpname)
		if type(data) == "string" then
			data = CMP_util:GetPrefabData(data)
		end
		return data and data.components and data.components[cmpname]
	end

	function CMP_util:HasTag(data, tag)
		if type(data) == "string" then
			data = CMP_util:GetPrefabData(data)
		end
		return data and data.tags_list and data.tags_list[tag]
	end
end
return CMP_util
