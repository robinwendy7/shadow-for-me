--读写库函数
local RW_util = {}
function RW_util:ReadFilmText(path)
	local file = io.open(path, "a+") -- 打开文件，以只读模式打开

	if not file then file = io.open(path, "w") end
	if not file then return end
	local text = file:read("*a")
	file:close() -- 关闭文件
	return text
end

function RW_util:WriteFileText(path, str)
	local file = io.open(path, "w")
	if file then
		file:write(str)
		file:close()
	else
		print("Error opening file")
	end
end

function RW_util:LoadStringFn(path, env, errorpatch, skipprint)
	local text = self:ReadFilmText(path)
	if text then
		local result, message
		local a = loadstring(text)
		if not a then
			print("语法错误！")
			return
		end
		--[[ print(text) ]]
		setfenv(a, env)

		result, message = xpcall(a, function(msg)
			print(msg)
			StackTraceToLog()
			local debug = debugstack()
			print(debug)
			print(msg)

			--[[  if errorpatch then
                self:WriteFileText(errorpatch, msg .. "\n" .. debug .. "\n" .. msg)
            end ]]

			return ""
		end)
		if skipprint then

		else
			if result then
				print("运行成功")
			elseif not result then
				print("运行失败")
			end
		end

		return message
	end
end

function RW_util:ChangeFilmLine(file_path, line_number, new_content)
	-- 打开文件以读取模式
	local file = io.open(file_path, "r")
	if file then
		-- 读取文件的所有行
		local lines = {}
		for line in file:lines() do
			table.insert(lines, line)
		end

		-- 关闭文件
		file:close()

		-- 修改指定行的内容
		if line_number <= #lines then
			lines[line_number] = new_content
		else
			print("行号超出文件行数")
		end

		-- 打开文件以写入模式
		file = io.open(file_path, "w")

		if file then
			-- 写入修改后的内容
			for _, line in ipairs(lines) do
				file:write(line .. "\n")
			end

			-- 关闭文件
			file:close()
		else
			print("无法打开文件")
		end
	else
		print("无法打开文件")
	end
end

--"mod_config_data/HappyPredictCheating"
function RW_util:SaveData(data, filepath)
	if type(data) ~= "table" then
		return SavePersistentString(filepath, data)
	end
	local str = json.encode(data)
	local insz, outsz = SavePersistentString(filepath, str)
end

function RW_util:LoadData(filepath)
	local data
	TheSim:GetPersistentString(filepath, function(load_success, str)
		if load_success then
			if string.len(str) > 0 then
				data = json.decode(str) or {}
			end
		end
	end)
	return data or {}
end

function RW_util:SaveStr(str, filepath)
	local insz, outsz = SavePersistentString(filepath, str)
end

function RW_util:LoadStr(filepath)
	return TheSim:GetPersistentString(filepath)
end

return RW_util
