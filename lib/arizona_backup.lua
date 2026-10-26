-- LIB_VERSION: 1.0
local M = {}

local function dir_of(base, path)
	local p = tostring(path)
	if p:sub(1, #base) == base then
		local rest = p:sub(#base + 2)
		local sub = rest:match('^(.+)[/\\][^/\\]+$')
		if sub and sub ~= '' then
			return base .. '/Backup/' .. sub
		end
	end
	return base .. '/Backup'
end

local function name_of(path)
	return tostring(path):match('[^/\\]+$') or 'file'
end

function M.dir_for(base, path)
	return dir_of(base, path)
end

function M.file_for(base, path)
	return dir_of(base, path) .. '/' .. name_of(path) .. '.bak'
end

function M.guest_file_for(base, base_file)
	if not base_file then return '' end
	return base .. '/Backup/' .. base_file .. '.bak'
end

function M.ensure(base, path)
	local dir = dir_of(base, path)
	local parent = dir:match('^(.*)[/\\][^/\\]+$')
	if parent and not doesDirectoryExist(parent) then createDirectory(parent) end
	if not doesDirectoryExist(dir) then createDirectory(dir) end
end

function M.copy(src, dst)
	local f = io.open(src, 'rb')
	if not f then return false end
	local data = f:read('*a')
	f:close()
	if not data or data == '' then return false end
	local o = io.open(dst, 'wb')
	if not o then return false end
	local ok = o:write(data)
	o:close()
	return ok and true or false
end

local function collect(cfg, missing_only, ignore_src)
	local result = {}
	local seen = {}
	local function add(path)
		if seen[path] then return end
		seen[path] = true
		if not ignore_src and not doesFileExist(path) then return end
		local dst = M.file_for(cfg.base, path)
		if missing_only and doesFileExist(dst) then return end
		table.insert(result, { src = path, dst = dst })
	end
	local inc = cfg.include or {}
	if inc.settings ~= false and cfg.settings_path then add(cfg.settings_path) end
	if inc.modules ~= false then
		local excl = cfg.exclude_files or {}
		local function allowed(m)
			if type(m) ~= 'table' then return false end
			if m.base_file and excl[m.base_file] then return false end
			return true
		end
		for _, m in pairs(cfg.modules or {}) do
			if allowed(m) then
				if type(m.path) == 'string' then add(m.path) end
				if m.base_file then add(cfg.base .. '/' .. m.base_file) end
			end
		end
		for _, dir in ipairs(cfg.account_dirs or {}) do
			for _, m in pairs(cfg.modules or {}) do
				if allowed(m) and m.base_file then add(dir .. '/' .. m.base_file) end
			end
		end
	end
	if inc.helper ~= false and cfg.script_path then add(cfg.script_path) end
	return result
end

local function do_backup(cfg, missing_only)
	local inc = cfg.include or {}
	if inc.settings == false and inc.modules == false and inc.helper == false then return 0 end
	M.ensure(cfg.base, cfg.base .. '/Settings.json')
	local n = 0
	for _, item in ipairs(collect(cfg, missing_only)) do
		if M.copy(item.src, item.dst) then n = n + 1 end
	end
	return n
end

function M.backup_all(cfg)
	return do_backup(cfg, false)
end

function M.backup_missing(cfg)
	return do_backup(cfg, true)
end

function M.stats(cfg)
	local count, bytes = 0, 0
	for _, item in ipairs(collect(cfg, false, true)) do
		if doesFileExist(item.dst) then
			local f = io.open(item.dst, 'rb')
			if f then
				local size = f:seek('end') or 0
				f:close()
				count = count + 1
				bytes = bytes + size
			end
		end
	end
	return count, bytes
end

function M.clear(base, modules, account_dirs)
	local function clear_dir(dir)
		if not doesDirectoryExist(dir) then return end
		os.remove(dir .. '/Settings.json.bak')
		os.remove(dir .. '/Arizona Helper.lua.bak')
		for _, m in pairs(modules or {}) do
			if type(m) == 'table' and m.base_file then
				os.remove(dir .. '/' .. m.base_file .. '.bak')
			end
		end
		os.remove(dir)
	end
	for _, dir in ipairs(account_dirs or {}) do
		clear_dir(base .. '/Backup/' .. dir)
	end
	clear_dir(base .. '/Backup')
end

return M
