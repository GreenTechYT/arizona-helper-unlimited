-- LIB_VERSION: 1.3
local M = {}

local HANDLER = [==[
-- DONT SEND ME THIS FILE, THIS IS NOT AN ERROR, BUT A SCRIPT TO DISPLAY THE ERROR IN DIALOG
-- НЕ ОТПРАВЛЯЙТЕ МНЕ ЭТОТ ФАЙЛ, ЭТО НЕ ОШИБКА, ЭТО СКРИПТ ДЛЯ ВЫВОДА ОШИБКИ ВАМ В ДИАЛОГЕ
local lastErrorShown = 0
local function fileExists(path)
	local f = io.open(path, 'r')
	if f then
		f:close()
		return true
	end
	return false
end
local function validScript(path)
	local f = io.open(path, 'r')
	if not f then return false end
	local c = f:read('*a') or ''
	f:close()
	if c == '' then return false end
	local chunk = (loadstring or load)(c)
	return chunk ~= nil
end
local function scriptVersion(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local head = f:read(8192) or ''
	f:close()
	local v = head:match("script_version%s*%(%s*[\"']([%d%.]+)[\"']%s*%)")
	if not v then return nil end
	local t = {}
	for c in v:gmatch('%d+') do t[#t + 1] = tonumber(c) end
	return t
end
local function verCmp(a, b)
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x < y then return -1 end
		if x > y then return 1 end
	end
	return 0
end
local function restoreHelper()
	local base = getWorkingDirectory()
	local helper = base .. '/Arizona Helper.lua'
	local backup = base .. '/Arizona Helper/Backup/Arizona Helper.lua.bak'
	local fresh = base .. '/Arizona Helper.lua.new'
	local legacy = base .. '/Arizona Helper.lua.bak'
	if fileExists(helper) and validScript(helper) then return end
	local candidates = { backup, fresh, legacy }
	local best, bestVer = nil, nil
	for _, backupPath in ipairs(candidates) do
		if fileExists(backupPath) and validScript(backupPath) then
			local v = scriptVersion(backupPath)
			if v and (bestVer == nil or verCmp(v, bestVer) > 0) then
				best, bestVer = backupPath, v
			elseif not v and best == nil then
				best = backupPath
			end
		end
	end
	if not best then return end
	local f = io.open(best, 'rb')
	if not f then return end
	local data = f:read('*a')
	f:close()
	if not data or data == '' then return end
	if fileExists(helper) then
		local cf = io.open(helper, 'rb')
		if cf then
			local cd = cf:read('*a')
			cf:close()
			if cd and cd ~= '' then
				local corruptDir = base .. '/Arizona Helper/Backup'
				if not doesDirectoryExist(corruptDir) then createDirectory(corruptDir) end
				local co = io.open(corruptDir .. '/Arizona Helper.lua.corrupt', 'wb')
				if co then co:write(cd); co:close() end
			end
		end
	end
	local tmp_helper = helper .. '.tmp'
	local old_helper = helper .. '.old'
	local o = io.open(tmp_helper, 'wb')
	if not o then return end
	o:write(data)
	o:close()
	pcall(os.remove, old_helper)
	local had_helper = fileExists(helper)
	if had_helper and not os.rename(helper, old_helper) then
		pcall(os.remove, tmp_helper)
		return
	end
	if not os.rename(tmp_helper, helper) then
		if had_helper and not fileExists(helper) and doesFileExist(old_helper) then
			os.rename(old_helper, helper)
		end
		pcall(os.remove, tmp_helper)
		return
	end
	pcall(os.remove, old_helper)
	print('Хелпер восстановлен из резервной копии: ' .. best)
	pcall(function()
		lua_thread.create(function()
			wait(5000)
			sampShowDialog(123124,
				'{009EFF}Arizona Helper',
				'{ffffff}Файл хелпера был повреждён или отсутствовал.\n' ..
				'Он автоматически восстановлен из резервной копии.\n\n' ..
				'Нажмите {00FF00}CTRL + R{ffffff} для перезагрузки скриптов.',
				'Понятно', '', 0)
		end)
	end)
end
restoreHelper()
function getLog()
	local worked_dir = getWorkingDirectory():gsub('\\','/')
	local IS_MOBILE = MONET_VERSION ~= nil
	local log_path = worked_dir .. (IS_MOBILE and '/logs/monetloader.log' or '/moonloader.log')
	if not fileExists(log_path) then return 'Файл логов не найден:\n- ' .. log_path end
	local file = io.open(log_path, 'r')
	if not file then
		return 'Не удалось открыть файл логов:\n- ' .. log_path
	end
	local lines = {}
	local max_lines = 10000
	for line in file:lines() do
		table.insert(lines, line)
		if #lines > max_lines then
			table.remove(lines, 1)
		end
	end
	file:close()
	local start_index = 1
	for i = #lines, 1, -1 do
		if lines[i]:find('Инициализация скрипта', 1, true) then
			start_index = i
			break
		end
	end
	local result = {}
	for i = start_index, #lines do
		local line = lines[i]
		if line:find('Arizona&Rodina Helper', 1, true) then
			if not (line:find('Script died') or line:find('%.lua%:') or line:find('Loaded successfully')) then
				local clean = line:match('Arizona&Rodina Helper%: (.+)')
				if clean then
					table.insert(result, clean)
				end
			end
		end
	end
	if #result == 0 then return 'Строки с Arizona&Rodina Helper не найдены.' end
	local logText = table.concat(result, '\n')
	if #logText > 2000 then logText = logText:sub(1, 2000) .. '\n... (лог обрезан)' end
	return logText
end
function onSystemMessage(msg, type, script)
	pcall(function()
	if script and script.name == 'Arizona&Rodina Helper' and msg and (msg:find('stack traceback') or msg:find('Script died due to an error')) then
		local currentTime = os.time()
		if currentTime - lastErrorShown < 5 then
			return
		end
		lastErrorShown = currentTime
		local short_msg = tostring(msg):sub(1, 1200)
		local short_log = tostring(getLog() or ''):sub(-2500)
		local errorMessage = ('{ffffff}Произошла непредусмотренная ошибка в работе скрипта, из-за чего он был отключён!\n\n' ..
		'{00FF00}Версия скрипта:{ffffff} ' .. tostring(script.version) .. '\n' ..
		'{00FF00}Время ошибки:{ffffff} ' .. os.date('%H:%M:%S %d.%m.%Y') .. '\n\n' ..
		'Отправьте скриншот этого диалога в {ff9900}тех.поддержку (DS: max_rics){ffffff}.\n\n' ..
		'Детали возникшей ошибки:\n{ff6666}' .. short_msg .. '{ffffff}\n\n' ..
		'Последние строки лога: \n{66BB6A}' .. short_log)
		
		sampShowDialog(123123, '{009EFF}Arizona&Rodina Helper [' .. script.version .. ']', errorMessage, 'Закрыть диалог', '', 0)
	end
	end)
end
]==]

function M.install(worked_dir)
	local path = worked_dir .. '/.Arizona Helper Handler.lua'
	local tmp = path .. '.tmp'
	local f = io.open(tmp, 'w')
	if not f then return false end
	f:write(HANDLER)
	f:close()
	local old_path = path .. '.old'
	os.remove(old_path)
	if doesFileExist(path) then
		if not os.rename(path, old_path) then
			os.remove(tmp)
			return false
		end
	end
	if not os.rename(tmp, path) then
		os.remove(tmp)
		if doesFileExist(old_path) then os.rename(old_path, path) end
		return false
	end
	local check = io.open(path, 'r')
	if not check then
		os.remove(path)
		if doesFileExist(old_path) then os.rename(old_path, path) end
		return false
	end
	local src = check:read('*a') or ''
	check:close()
	if src == '' or (loadstring or load)(src) == nil then
		os.remove(path)
		if doesFileExist(old_path) then os.rename(old_path, path) end
		return false
	end
	os.remove(old_path)
	local old = {
		'Crash Info.lua',
		'Error Handler.lua',
		'Errors Handler.lua',
		'Crash Informer.lua',
		'CrashInfo.lua',
		'ErrorHandler.lua'
	}
	for _, name in ipairs(old) do
		os.remove(worked_dir .. '/' .. name)
		os.remove(worked_dir .. '/.Arizona Helper ' .. name)
	end
	return true
end

return M
