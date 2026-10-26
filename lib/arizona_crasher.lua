-- LIB_VERSION: 1.0
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
	local chunk = loadstring(c)
	return chunk ~= nil
end
local function restoreHelper()
	local base = getWorkingDirectory()
	local helper = base .. '/Arizona Helper.lua'
	local backup = base .. '/Arizona Helper/Backup/Arizona Helper.lua.bak'
	local fresh = base .. '/Arizona Helper.lua.new'
	local legacy = base .. '/Arizona Helper.lua.bak'
	if fileExists(helper) and validScript(helper) then return end
	local candidates = { backup, fresh, legacy }
	for _, backupPath in ipairs(candidates) do
		if fileExists(backupPath) and validScript(backupPath) then
			local f = io.open(backupPath, 'rb')
			if f then
				local data = f:read('*a')
				f:close()
				if data and data ~= '' then
					if fileExists(helper) then
						local cf = io.open(helper, 'rb')
						if cf then
							local cd = cf:read('*a')
							cf:close()
							if cd and cd ~= '' then
								local co = io.open(helper .. '.corrupt', 'wb')
								if co then co:write(cd); co:close() end
							end
						end
					end
					local o = io.open(helper, 'wb')
					if o then
						o:write(data)
						o:close()
						print('[DEBUG] helper restored from backup')
						return
					end
				end
			end
		end
	end
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
	if script and script.name == 'Arizona&Rodina Helper' and msg and ((msg:find('stack traceback')) or (type == 3 and not msg:find('Script died due to an error'))) then
		local currentTime = os.time()
		if currentTime - lastErrorShown < 5 then
			return
		end
		lastErrorShown = currentTime
		local errorMessage = ('{ffffff}Произошла непредусмотренная ошибка в работе скрипта, из-за чего он был отключён!\n\n' ..
		'{00FF00}Версия скрипта:{ffffff} ' .. script.version .. '\n' ..
		'{00FF00}Время ошибки:{ffffff} ' .. os.date('%H:%M:%S %d.%m.%Y') .. '\n\n' ..
		'Отправьте скриншот этого диалога в {ff9900}тех.поддержку (DS: max_rics){ffffff}.\n\n' ..
		'Детали возникшей ошибки:\n{ff6666}' .. msg .. '{ffffff}\n\n' ..
		'Полный лог работы скрипта: \n{66BB6A}' .. getLog())
		
		sampShowDialog(123123, '{009EFF}Arizona&Rodina Helper [' .. script.version .. ']', errorMessage, 'Закрыть диалог', '', 0)
	end
	end)
end
]==]

function M.install(worked_dir)
	local path = worked_dir .. '/.Arizona Helper Handler.lua'
	local f = io.open(path, 'w')
	if not f then return false end
	f:write(HANDLER)
	f:close()
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
