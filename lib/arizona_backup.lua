-- LIB_VERSION: 1.1
local M = {}

local function dir_of(base, path)
	local p = tostring(path)
	local sep = p:sub(#base + 1, #base + 1)
	if p:sub(1, #base) == base and (sep == '/' or sep == '\\') then
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

local function ensure_dir(dir)
	if not dir or dir == '' then return false end
	if doesDirectoryExist(dir) then return true end
	local parent = dir:match('^(.*)[/\\][^/\\]+$')
	if parent and parent ~= '' and not doesDirectoryExist(parent) then
		ensure_dir(parent)
	end
	pcall(createDirectory, dir)
	return doesDirectoryExist(dir)
end

function M.ensure(base, path)
	return ensure_dir(dir_of(base, path))
end

function M.copy(src, dst)
	local f = io.open(src, 'rb')
	if not f then return false end
	local data = f:read('*a')
	f:close()
	if not data or data == '' then return false end
	local dir = tostring(dst):match('^(.*)[/\\][^/\\]+$')
	if dir and not ensure_dir(dir) then return false end
	local tmp = dst .. '.tmp'
	local o = io.open(tmp, 'wb')
	if not o then return false end
	local ok = o:write(data)
	o:close()
	if not ok then
		pcall(os.remove, tmp)
		return false
	end
	local old = dst .. '.old'
	pcall(os.remove, old)
	if doesFileExist(dst) then
		if not os.rename(dst, old) then
			pcall(os.remove, tmp)
			return false
		end
	end
	if not os.rename(tmp, dst) then
		if doesFileExist(old) then pcall(os.rename, old, dst) end
		pcall(os.remove, tmp)
		return false
	end
	pcall(os.remove, old)
	return true
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
	if inc.network ~= false then
		for _, p in ipairs(cfg.extra_files or {}) do
			if type(p) == 'string' and p ~= '' then add(p) end
		end
	end
	if inc.helper ~= false and cfg.script_path then add(cfg.script_path) end
	return result
end

local function do_backup(cfg, missing_only)
	local inc = cfg.include or {}
	local has_extra = type(cfg.extra_files) == 'table' and #cfg.extra_files > 0
	if inc.settings == false and inc.modules == false and inc.helper == false and (inc.network == false or not has_extra) then return 0 end
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
                local content = f:read('*a') or ''
                local size = #content
                f:close()
                count = count + 1
                bytes = bytes + size
            end
        end
	end
	return count, bytes
end

function M.clear(base, modules, account_dirs)
	local root = base .. '/Backup'
	local function wipe(dir)
		if not doesDirectoryExist(dir) then return end
		local ok, files = pcall(getDirectoryFiles, dir)
		if ok and type(files) == 'table' then
			for _, f in ipairs(files) do
				local p = tostring(f)
				if not p:find('[/\\]') then p = dir .. '/' .. p end
				pcall(os.remove, p)
			end
		end
		pcall(removeDirectory, dir)
	end
	for _, name in ipairs(account_dirs or {}) do
		wipe(root .. '/' .. name)
	end
	wipe(root)
end

function M.bind(ctx)
	ctx = ctx or {}
	local B = {}

	local function st()
		local s = ctx.get_settings and ctx.get_settings() or ctx.settings
		return type(s) == 'table' and s or {}
	end
	local function gen() return st().general or {} end
	local function settings_path() return ctx.settings_path or (ctx.base .. '/Settings.json') end

	function B.enabled(category)
		local g = gen()
		if g.backup_enabled ~= true then return false end
		local inc = g.backup_include
		if category and type(inc) == 'table' and inc[category] == false then return false end
		return true
	end

	function B.file_for(path) return M.file_for(ctx.base, path) end
	function B.guest_for(f)   return M.guest_file_for(ctx.base, f) end
	function B.ensure(path)   return M.ensure(ctx.base, path) end
	function B.copy(s, d)     return M.copy(s, d) end

	function B.module_selected(key)
		local ex = gen().backup_modules
		if type(ex) == 'table' and ex[key] == false then return false end
		return true
	end

	function B.module_list()
		local keys, mods = {}, ctx.modules or {}
		for k, m in pairs(mods) do
			if type(m) == 'table' and type(m.name) == 'string' then keys[#keys + 1] = k end
		end
		table.sort(keys, function(a, b) return tostring(mods[a].name) < tostring(mods[b].name) end)
		return keys
	end

	function B.account_dirs()
		if type(ctx.account_dirs) == 'function' then
			local ok, d, f = pcall(ctx.account_dirs)
			if ok then return d or {}, f or {} end
		end
		return {}, {}
	end

	function B.cfg()
		local dirs = B.account_dirs()
		local exclude = {}
		for k, m in pairs(ctx.modules or {}) do
			if type(m) == 'table' and m.base_file and not B.module_selected(k) then
				exclude[m.base_file] = true
			end
		end
		return {
			base          = ctx.base,
			script_path   = ctx.script_path,
			settings_path = settings_path(),
			modules       = ctx.modules,
			account_dirs  = dirs,
			exclude_files = exclude,
			extra_files   = ctx.extra_files or {},
			include = {
				settings = B.enabled('settings'),
				modules  = B.enabled('modules'),
				helper   = B.enabled('helper'),
				network  = B.enabled('network'),
			},
		}
	end

	function B.invalidate() B._st_at = nil end

	function B.all()     local n = M.backup_all(B.cfg());     B.invalidate(); return n end
	function B.missing() local n = M.backup_missing(B.cfg()); B.invalidate(); return n end

	function B.stats(ttl)
		local now = os.clock()
		if B._st_at and (now - B._st_at) < (ttl or 2.0) then return B._st_n, B._st_b end
		local c = B.cfg()
		c.include = { settings = true, modules = true, helper = true, network = true }
		local n, b = M.stats(c)
		B._st_at, B._st_n, B._st_b = now, n, b
		return n, b
	end

	function B.clear()
		local _, folders = B.account_dirs()
		M.clear(ctx.base, ctx.modules, folders)
		B.invalidate()
	end

	function B.helper()
		if not B.enabled('helper') then return false end
		local src = ctx.script_path
		if not src or not doesFileExist(src) then return false end
		B.ensure(settings_path())
		local ok = M.copy(src, ctx.base .. '/Backup/Arizona Helper.lua.bak')
		if ok then B.invalidate() end
		return ok
	end

	function B.set_enabled(on)
		local g = gen()
		g.backup_enabled = (on == true)
		if on then
			local inc = g.backup_include
			if type(inc) ~= 'table' then inc = {}; g.backup_include = inc end
			if inc.settings == false and inc.modules == false and inc.helper == false and inc.network == false then
				g.backup_include = { settings = true, modules = true, helper = true, network = true }
			end
			B.ensure(settings_path())
			B.helper()
			B.all()
		else
			B.clear()
		end
		B.invalidate()
		return g.backup_enabled
	end

	function B.selection()
		local g = gen()
		local inc, ex = g.backup_include or {}, g.backup_modules or {}
		local mods = {}
		for _, k in ipairs(B.module_list()) do mods[k] = ex[k] ~= false end
		return {
			settings = inc.settings ~= false,
			helper   = inc.helper   ~= false,
			network  = inc.network  ~= false,
			modules  = inc.modules  ~= false,
			mods = mods,
		}
	end

	function B.apply(sel)
		local g = gen()
		sel = sel or {}
		local use_s, use_h = sel.settings == true, sel.helper == true
		local use_n, use_m = sel.network == true, sel.modules == true
		g.backup_include = { settings = use_s, modules = use_m, helper = use_h, network = use_n }
		if use_s or use_m or use_h or use_n then
			local ex = {}
			for k, v in pairs(sel.mods or {}) do if v == false then ex[k] = false end end
			g.backup_modules = next(ex) and ex or nil
			if g.backup_enabled ~= true then
				g.backup_enabled = true
				B.helper(); B.all()
			end
		else
			g.backup_enabled = false
			g.backup_modules = nil
			B.clear()
		end
		B.invalidate()
		return g.backup_enabled
	end

	function B.size_parts(bytes)
		bytes = tonumber(bytes) or 0
		if bytes >= 1048576 then return string.format('%.2f', bytes / 1048576), 'MB' end
		return string.format('%.1f', bytes / 1024), 'KB'
	end

	return B
end

return M
