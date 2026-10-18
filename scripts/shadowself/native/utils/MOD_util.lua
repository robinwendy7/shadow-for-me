local MOD_util = {}
function MOD_util:Require(path)
	package.loaded[path] = nil
	return require(path)
end

function MOD_util:MakeRunOnceFn(fnid, fn)
	if not rawget(GLOBAL, "mmdx_fnids") then
		GLOBAL.global("mmdx_fnids")
		GLOBAL.mmdx_fnids = {}
	end
	if not GLOBAL.mmdx_fnids[fnid] then
		GLOBAL.mmdx_fnids[fnid] = true
		fn()
	end
end

--
function MOD_util:StartThread(threadstring, fn)
	TUNING[threadstring] = StartThread(fn, threadstring)
end

function MOD_util:StopThread(threadstring, stopstring, extrafn)
	if TUNING[threadstring] then
		if stopstring then
			PLAYER_util:Say(stopstring)
		end
		KillThreadsWithID(TUNING[threadstring].id)
		TUNING[threadstring]:SetList(nil)
		TUNING[threadstring] = nil
		if extrafn then
			extrafn()
		end
	end
end

function MOD_util:Ismmdx()
	return TheSim:GetUsersName() == "1127781833@steam"
end

function MOD_util:AuthorMode()
	return false and self:Ismmdx()
end

MOD_util.AuthorPrint = MOD_util:AuthorMode() and function(...)
	print(GetTime(), 'AuthorMode:', ...)
end or function(...)

end
function MOD_util:HookFn(env, key, prefn, afterfn, not_runoldfn, returnparams)
	local oldfn = env[key]
	env[key] = function(...)
		local preresult
		if prefn then
			preresult = { prefn(...) }
		end
		local oldresult
		if not not_runoldfn and oldfn then
			oldresult = { oldfn(...) }
		end
		local afterresult
		if afterfn then
			afterresult = { afterfn(...) }
		end
		return not returnparams and oldresult and unpack(oldresult)
			or returnparams and returnparams.pre and preresult and unpack(preresult)
			or returnparams and returnparams.after and afterresult and unpack(afterresult)
			or oldresult and unpack(oldresult)
	end
end

function MOD_util:HookUserdataFunction(userdata, name, prefn, afterfn)
	local idx = getmetatable(userdata).__index;
	if idx and idx[name] then
		local oldfn = idx[name];
		idx[name] = function(...)
			if prefn then
				local preresult = prefn(...)
				if preresult ~= nil then
					return preresult
				end
			end
			local oldresult = { oldfn(...) }
			if afterfn then
				local afterresult = afterfn(...)
				if afterresult ~= nil then
					return afterresult
				end
			end
			return unpack(oldresult)
		end
	end
end

local hasbeingchecked = {}
function MOD_util:CheckMod(name)
	local result = false
	if hasbeingchecked[name] ~= nil then
		result = hasbeingchecked[name]
	else
		for k, v in pairs(ModManager.mods) do
			local modname = v.modinfo.name
			if type(name) == "string" then
				if modname == name or modname and string.find and string.find(modname, name) or KnownModIndex:IsModEnabledAny(name) then
					result = true
					break
				end
			elseif type(name) == "table" then
				for _, checkname in pairs(name) do
					if modname == checkname or modname and string.find and string.find and string.find(modname, checkname) or KnownModIndex:IsModEnabledAny(checkname) then
						result = true
						break
					end
				end
			end
		end
		hasbeingchecked[name] = result
	end
	return result
end

function MOD_util:AddUserCommand(command_string, params_table, client_command_fn, paramsoptional)
	local command_data = {
		menusort = 1,
		name = command_string,
		prettyname = nil,
		desc = nil,
		emote = true,
		permission = COMMAND_PERMISSION.USER,
		slash = true,
		usermenu = false,
		servermenu = false,
		params = params_table,
		paramsoptional = paramsoptional,
		localfn = client_command_fn
	}
	AddUserCommand(command_data.name, command_data)
end

--弃用 你不应该再使用这个接口 更换CMP_util里面的接口
function MOD_util:MasterDo(fn, ...) --越权执行某个函数
	local IsMasterSim = TheWorld.ismastersim
	TheWorld.ismastersim = true
	GLOBAL.MOD_SRC_LOCK = true
	local a, b = pcall(fn, ...)
	if not a then
		MOD_util.fallfn = fn
		print("MOD_util:MasterDo<crash>:", a, b)
	end
	TheWorld.ismastersim = IsMasterSim
	GLOBAL.MOD_SRC_LOCK = false
end

function MOD_util:Weak_Master_Do(fn, ...)
	local IsMasterSim = TheWorld.ismastersim
	TheWorld.ismastersim = true
	local a, b = pcall(fn, ...)
	if not a then
		MOD_util.fallfn = fn
		print("MOD_util:Master_Do<crash>:", a, b)
	end
	TheWorld.ismastersim = IsMasterSim
end

--弃用 你不应该再使用这个接口 更换CMP_util里面的接口
function MOD_util:Master_Do(fn, ...) --越权执行某个函数
	local IsMasterSim = TheWorld.ismastersim
	TheWorld.ismastersim = true
	GLOBAL.MOD_SRC_LOCK = true
	local a, b = pcall(fn, ...)
	if not a then
		MOD_util.fallfn = fn
		print("MOD_util:Master_Do<crash>:", a, b)
	end
	TheWorld.ismastersim = IsMasterSim
	GLOBAL.MOD_SRC_LOCK = false
end

--ScanMap 0.0869
function MOD_util:Estimatefunction(fn, repeattime, ...)
	local a = os.clock()
	local ticks = 0
	repeat
		ticks = ticks + 1
		fn(...)
		if not repeattime or ticks >= repeattime then
			break
		end
	until false
	local b = os.clock()
	print(b - a)
	return b - a
end

function MOD_util:Estimatefunction1(fn, ...)
	local starttime = os.clock()
	local num = 0
	repeat
		num = num + 1
		fn(...)
		if os.clock() - starttime > 0.1 then
			break
		end
	until false
	print(num)
	return num
end

function MOD_util:DoTaskInTime(time, fn)
	self.mmdx_instance = self.mmdx_instance or CreateEntity("mmdx_instance")
	return self.mmdx_instance:DoTaskInTime(time, fn)
end

--DoStaticPeriodicTask
function MOD_util:DoStaticPeriodicTask(time, fn, initialdelay, ...)
	self.mmdx_instance = self.mmdx_instance or CreateEntity("mmdx_instance")
	return self.mmdx_instance:DoStaticPeriodicTask(time, fn, initialdelay, ...)
end

function MOD_util:DoStaticTaskInTime(time, fn)
	self.mmdx_instance = self.mmdx_instance or CreateEntity("mmdx_instance")
	return self.mmdx_instance:DoStaticTaskInTime(time, fn)
end

function MOD_util:DoPeriodicTask(time, fn, initialdelay, ...)
	self.mmdx_instance = self.mmdx_instance or CreateEntity("mmdx_instance")
	self.mmdx_instance:DoPeriodicTask(time, fn, initialdelay, ...)
end

function MOD_util:repeatsleepuntil(fun, max)
	local ticks = 0
	repeat
		ticks = ticks + 1
		if ticks > max or fun(ticks) then
			break
		end
		Sleep(0)
	until false
end

function MOD_util:TraceBackLine(final)
	final = final or 20
	for i = 1, final do
		local info = debug.getinfo(i)
		if info then
			print(string.format("@%s%s in %s", info.source,
				info.currentline ~= nil and (":" .. info.currentline) or "",
				info.name or "?"))
		end
	end
end

function MOD_util:GetFnParams(fun)
	local params = {}
	local hook = function(...)
		local info = debug.getinfo(3)
		if info.name ~= 'pcall' then return end

		for i = 1, math.huge do
			local name, value = debug.getlocal(2, i)
			if name == '(*temporary)' or not name then
				debug.sethook()
				error('')
				return
			end
			params[i] = name
		end
	end

	debug.sethook(hook, "c")
	pcall(fun)
	debug.sethook(nil)
	return params
end

--获取local函数
local ismmdx = TheSim:GetUsersName() == "1127781833@steam"
local function GetUpvalueHelper(entry_fn, entry_name)
	local i = 1
	while true do
		local name, value = debug.getupvalue(entry_fn, i)
		if name and ismmdx then
			print(name, value)
		end
		if name == entry_name then
			return value, i
		elseif name == nil then
			return
		end
		i = i + 1
	end
end
local function GetUpvalueHelper_deekseek(entry_fn, entry_name, fn, path, depth, fn_filter_fn)
	local i = 1
	local tab = {}
	while true do
		local name, value = debug.getupvalue(entry_fn, i)
		if name and ismmdx then
			print(name, value)
		end
		if name == entry_name and (not fn_filter_fn or fn_filter_fn(value)) then
			return value, i
		elseif name == nil then
			break
		elseif type(value) == "function" then
			tab[value] = true
		end
		i = i + 1
	end
	for value, v in pairs(tab) do
		local fn1, ii, prv = MOD_util:GetUpvalue_deekseek(value, path, depth + 1, fn_filter_fn)
		if fn1 then
			return fn1, ii, prv
		end
	end
end


function MOD_util:GetUpvalue(fn, path) --fn是要总函数，path是要改的本地函数
	local prv, i = nil, nil
	for var in path:gmatch("[^%.]+") do
		prv = fn
		fn, i = GetUpvalueHelper(fn, var)
		if not fn then break end
	end
	return fn, i, prv --返回那个本地函数和所在行
end

function MOD_util:SetUpvalue(start_fn, path, new_fn) --start_fn是要总函数，path是要改的本地函数，new_fn是修改后的
	local fn, fn_i, scope_fn = self:GetUpvalue(start_fn, path)
	if not fn_i then
		print("Didn't find " .. path .. " from", start_fn)
		return
	end
	debug.setupvalue(scope_fn, fn_i, new_fn)
end

function MOD_util:GetUpvalue_deekseek(fn, path, depth, fn_filter_fn) --fn是要总函数，path是要改的本地函数
	depth = depth or 0                                               --最多四层
	if depth >= 8 then return end
	local prv, i = nil, nil
	local prv2
	for var in path:gmatch("[^%.]+") do
		prv         = fn
		fn, i, prv2 = GetUpvalueHelper_deekseek(fn, var, fn, path, depth, fn_filter_fn)
		if not fn then break end
	end
	return fn, i, prv2 or prv --返回那个本地函数和所在行
end

function MOD_util:SetUpvalue_deekseek(start_fn, path, new_fn, fn_filter_fn) --start_fn是要总函数，path是要改的本地函数，new_fn是修改后的
	local fn, fn_i, scope_fn = self:GetUpvalue_deekseek(start_fn, path, 0, fn_filter_fn)
	if not fn_i then
		print("Didn't find " .. path .. " from", start_fn)
		return
	end
	debug.setupvalue(scope_fn, fn_i, new_fn)
end

--获取预制物定义的文件名字
function MOD_util:GetPrefabFile(prefab)
	return debug.getinfo(GLOBAL.Prefabs[prefab].fn, "S").source
end

function MOD_util:GuessFnName(fn)
	local a = fn
	local function checktab(tab, kk, v)
		if type(v) == "table" then
			for k, v in pairs(v) do
				if v == a then
					--print(k, v)
					return tab .. "." .. kk .. "." .. k
				end
			end
		elseif v == a then
			return tab .. "." .. k
		end
	end
	for k, v in pairs(GLOBAL) do
		local c = checktab("GLOBAL", k, v)
		if c then
			return c
		end
	end
end

--获取事件的回调函数
function MOD_util:GetEventCallback(inst, event, patch, souce)
	souce = souce or inst
	local listeners = souce.event_listeners[event]
	local listener_fns = listeners and listeners[inst] or {}
	for k, v in pairs(listener_fns) do
		--patch such as scripts/xxx/xxx.lua
		--or ../mods/workshop-xxxx/scripts/xxx/xxx.lua
		--[[if TheSim:GetUsersName() == "1127781833@steam" then
			print(debug.getinfo(v, "S").source, v)
		end]]
		if debug.getinfo(v, "S").source == patch then
			return v
		end
	end
end

--修改事件的回调函数
function MOD_util:SetEventCallback(inst, event, patch, fn, souce)
	souce = souce or inst
	do
		local listeners = souce.event_listeners[event]
		local listener_fns = listeners and listeners[inst] or {}
		for k, v in pairs(listener_fns) do
			if debug.getinfo(v, "S").source == patch then
				listener_fns[k] = fn
				break
			end
		end
	end
	do
		local listeners = inst.event_listening[event]
		local listener_fns = listeners and listeners[souce] or {}
		for k, v in pairs(listener_fns) do
			if debug.getinfo(v, "S").source == patch then
				listener_fns[k] = fn
				break
			end
		end
	end
end

--获取定时器的回调函数
function MOD_util:GetTaskCallback(inst, patch)
	local pendingtasks = inst.pendingtasks
	for k, v in pairs(pendingtasks or {}) do
		--patch such as scripts/xxx/xxx.lua
		--or ../mods/workshop-xxxx/scripts/xxx/xxx.lua
		if debug.getinfo(k.fn, "S").source == patch then
			return k.fn, k
		end
	end
end

--修改定时器的回调函数
function MOD_util:SetTaskCallback(inst, patch, fn, getfnfn)
	local pendingtasks = inst.pendingtasks
	for k, v in pairs(pendingtasks or {}) do
		--patch such as scripts/xxx/xxx.lua
		--or ../mods/workshop-xxxx/scripts/xxx/xxx.lua
		if debug.getinfo(k.fn, "S").source == patch then
			if getfnfn then
				k.fn = getfnfn(k.fn)
			else
				k.fn = fn
			end
			return
		end
	end
end

--判断是不是空表
function MOD_util:IsEmpty(t)
	return not next(t)
end

--crash
function MOD_util:DoCrash()
	local inst = CreateEntity()
	inst.entity:AddTransform()
	inst.entity:SetParent(inst.entity)
end

--写单子的时候用 如何固定时间没结尾款就崩
function MOD_util:CheckReallyTime(finaltime)
	--finaltime example 20250323 y+m+d
	if finaltime < tonumber(os.date("%Y%m%d")) then
		MOD_util:DoCrash()
	end
end

-- 内置库接口校验，不执行来源Mod的账号/作者/名称检查。
function MOD_util:CheckUtilsVersion() end
function MOD_util:GetUtilsVersion() return 1.3 end
function MOD_util:returntrue(a)
	return a
end

--判空
function MOD_util:EnsureTable(t, s)
	if type(t) ~= "table" then return end
	if type(s) ~= "string" then return end
	local result = t
	s = s:split(".")
	for index, value in ipairs(s or {}) do
		if type(result) == "table" then
			result = result[value]
		else
			result = nil
			break
		end
	end
	return result
end

function MOD_util:InsertTable(destTable, srcTable)
	if srcTable and type(srcTable) == 'table' and next(srcTable) then
		for _, value in pairs(srcTable) do
			table.insert(destTable, value)
		end
	end
end

do
	local status, settingscreen = pcall(require, "screens/settingsscreen")
	--获取设置
	function MOD_util:GetMOption(key, default)
		if rawget(_G, "m_options") and m_options[key] ~= nil then
			return m_options[key]
		else
			return default
		end
	end

	--修改设置 自带判空
	function MOD_util:ChangeMOption(key, v)
		if not rawget(_G, "m_options") then return end
		m_options[key] = v
	end

	--添加按键，可以在游戏内更改设置
	function MOD_util:AddKeyDownHandler(optionkey, defaultkey, fn)
		if not fn then
			fn = defaultkey
			defaultkey = nil
		end
		local f = getfenv(2)
		local modname = rawget(f, "modname")
		if not TheInput.m_regard_mouse_as_key then
			local mousehandler = TheInput:AddMouseButtonHandler(function(button, down, x, y)
				if TheInput.m_regard_mouse_as_key then
					return
				end
				if down and MOD_util:GetMOption(optionkey, defaultkey) == button then
					fn(button, down, x, y)
				end
			end)
			mousehandler.modname = modname
		end
		local handler = TheInput:AddKeyHandler(function(key, down)
			if down and MOD_util:GetMOption(optionkey, defaultkey) == key then
				fn(key, down)
			end
		end)
		handler.modname = modname
		print(handler.modname)
	end

	function MOD_util:AddKeyUpHandler(optionkey, defaultkey, fn)
		if not fn then
			fn = defaultkey
			defaultkey = nil
		end
		local f = getfenv(2)
		local modname = rawget(f, "modname")
		if not TheInput.m_regard_mouse_as_key then
			local mousehandler = TheInput:AddMouseButtonHandler(function(button, down, x, y)
				if TheInput.m_regard_mouse_as_key then
					return
				end
				if not down and MOD_util:GetMOption(optionkey, defaultkey) == button then
					fn(button, down, x, y)
				end
			end)
			mousehandler.modname = modname
		end
		local handler = TheInput:AddKeyHandler(function(key, down)
			if not down and MOD_util:GetMOption(optionkey, defaultkey) == key then
				fn(key, down)
			end
		end)
		handler.modname = modname
	end

	--模组添加设置
	function MOD_util:CanAddSetting()
		--print(status, settingscreen, "1screens/settingsscreen")
		return status, settingscreen
	end

	function MOD_util:CreatePage(pagename, pagedata, forcecreate)
		if not MOD_util:CanAddSetting() then
			return
		end
		settingscreen:CreatePage(pagename, pagedata, forcecreate)
	end

	--
	function MOD_util:StandardPage(pagename, buttonname, order, pagetitle)
		if not MOD_util:CanAddSetting() then
			return
		end
		settingscreen:StandardPage(pagename, buttonname, order, pagetitle)
	end

	function MOD_util:AddEnableDisableOption(pagename, key, default, description, hover)
		if not MOD_util:CanAddSetting() then
			return
		end
		if default == nil then
			default = true
		end
		settingscreen:AddEnableDisableOption(pagename, key, default, description, hover)
	end

	function MOD_util:AddKeyBinds(pagename, key, default, description, hover)
		if not MOD_util:CanAddSetting() then
			return
		end
		if default == nil then
			default = true
		end
		settingscreen:AddKeyBinds(pagename, key, default, description, hover)
	end

	function MOD_util:AddOption(pagename, key, options, default, description, hover)
		if not MOD_util:CanAddSetting() then
			return
		end
		if default == nil then
			default = true
		end
		settingscreen:AddOption(pagename, key, options, default, description, hover)
	end

	function MOD_util:AddPageParam(pagename, key, option)
		if not MOD_util:CanAddSetting() then
			return
		end
		option = option or {}
		option.key = key
		settingscreen:SetPageParam(pagename, option)
	end

	--SettingsScreen:SetPageParam(pagename, option, buttonname, order, pagetitle)

	function MOD_util:GetKeyFromConfig(name)
		local f = getfenv(2)
		local a = GLOBAL.GetModConfigData(name, rawget(f, "modname"))
		return a and rawget(GLOBAL, a)
	end
end
do --监听一个表的某一个key的值的变化
	local function default__newindex(t, k, v)
		local p = rawget(t, "_")[k]
		if p == nil then
			rawset(t, k, v)
		else
			local old = p[1]
			p[1] = v
			p[2](t, v, old)
		end
	end
	local function default__index(t, k)
		local p = rawget(t, "_")[k]
		if p ~= nil then
			return p[1]
		end
		return getmetatable(t)[k]
	end
	function MOD_util:ListenforTableKey(tt, kk, callback)
		local tab = tt
		local key = kk
		local metatable = getmetatable(tab)

		if not metatable then
			setmetatable(tab, { __newindex = default__newindex, })
			metatable = getmetatable(tab)
		end
		metatable.__index = metatable.__index or default__index
		metatable.__newindex = metatable.__newindex or default__newindex -- use the default __newindex
		tab._ = tab._ or {}
		tab._[key] = { nil, callback }
	end
end
--addclickfunction
if false then
	do
		--这个直接复制到对应的位置执行就行
		--执行时机是加载模组的时候
		local registerlist = {}
		local oldLoadPrefabFile = GLOBAL.LoadPrefabFile
		function GLOBAL.LoadPrefabFile(filename, async_batch_validation, search_asset_first_path, ...)
			if registerlist[filename] then
				assert(not async_batch_validation or not search_asset_first_path,
					"search_asset_first_path and async_batch_validation cannot both be defined")
				local fn = registerlist[filename]
				assert(fn, "Could not load file ")
				assert(type(fn) == "function", "Prefab file doesn't return a callable chunk: " .. filename)
				setfenv(fn, GLOBAL)
				local ret = { fn() }
				if ret then
					for i, val in ipairs(ret) do
						if type(val) == "table" and val.is_a and val:is_a(GLOBAL.Prefab) then
							val.search_asset_first_path = search_asset_first_path
							if async_batch_validation then
								RegisterPrefabsImpl(val, function(prefab, asset)
									TheSim:AddBatchVerifyFileExists(asset.file)
								end)
							else
								RegisterSinglePrefab(val)
							end
							GLOBAL.PREFABDEFINITIONS[val.name] = val
						end
					end
				end

				return ret
			end
			return oldLoadPrefabFile(filename, async_batch_validation, search_asset_first_path, ...)
		end

		function MOD_util:RegisterModPrefab(prefab_path, prefabfn)
			registerlist["prefabs/" .. prefab_path] = prefabfn
			table.insert(PrefabFiles, prefab_path)
		end
	end
end

return MOD_util
