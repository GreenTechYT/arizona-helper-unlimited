-- LIB_VERSION: 1.0
local M = {}
M.MAX_TIME = 23
M.MAX_WEATHER = 45
M.locked_time = nil
M.locked_weather = nil

local TIME_ADDR, WEATHER_ADDR = 0xB70153, 0xC81320
local loop_on, gen = false, 0
local snap

local function clamp(v, max)
	v = tonumber(v)
	if not v then return nil end
	v = math.floor(v)
	if v < 0 or v > max then return nil end
	return v
end

function M.get_time()
	local ok, v = pcall(readMemory, TIME_ADDR, 1, true)
	return (ok and tonumber(v)) or 0
end

function M.get_weather()
	local ok, v = pcall(readMemory, WEATHER_ADDR, 2, true)
	return (ok and tonumber(v)) or 0
end

function M.set_time(hour)
	hour = clamp(hour, M.MAX_TIME)
	if not hour then return false end
	return (pcall(function()
		local bs = raknetNewBitStream()
		raknetBitStreamWriteInt8(bs, hour)
		raknetEmulRpcReceiveBitStream(29, bs)
		raknetDeleteBitStream(bs)
	end))
end

function M.set_weather(id)
	id = clamp(id, M.MAX_WEATHER)
	if not id then return false end
	return (pcall(forceWeatherNow, id))
end

local function ensure_loop()
	if loop_on then return end
	loop_on = true
	gen = gen + 1
	local my = gen
	lua_thread.create(function()
		while loop_on and gen == my do
			wait(500)
			local t, w = M.locked_time, M.locked_weather
			if not t and not w then break end
			if t and M.get_time() ~= t then M.set_time(t) end
			if w and M.get_weather() ~= w then M.set_weather(w) end
		end
		if gen == my then loop_on = false end
	end)
end

function M.stop()
	loop_on = false
	gen = gen + 1
	M.locked_time, M.locked_weather = nil, nil
end

function M.apply(g)
	g = g or {}
	if g.wt_enable ~= true then M.stop() return end
	local t = (g.wt_lock_time == true) and clamp(g.wt_time or 12, M.MAX_TIME) or nil
	local w = (g.wt_lock_weather == true) and clamp(g.wt_weather or 0, M.MAX_WEATHER) or nil
	M.locked_time, M.locked_weather = t, w
	if t or w then
		ensure_loop()
		if t then M.set_time(t) end
		if w then M.set_weather(w) end
	else
		M.stop()
	end
end

function M.ui(ui, g, imgui)
	if not ui.t then
		ui.t  = imgui.new.int(tonumber(g.wt_time) or 12)
		ui.w  = imgui.new.int(tonumber(g.wt_weather) or 0)
		ui.lt = imgui.new.bool(g.wt_lock_time == true)
		ui.lw = imgui.new.bool(g.wt_lock_weather == true)
	end
	return ui
end

function M.sync(ui, g)
	ui.t[0]  = tonumber(g.wt_time) or 12
	ui.w[0]  = tonumber(g.wt_weather) or 0
	ui.lt[0] = g.wt_lock_time == true
	ui.lw[0] = g.wt_lock_weather == true
	snap = { t = ui.t[0], w = ui.w[0], lt = ui.lt[0], lw = ui.lw[0] }
end

function M.push(ui, g)
	g.wt_time, g.wt_weather = ui.t[0], ui.w[0]
	g.wt_lock_time, g.wt_lock_weather = ui.lt[0], ui.lw[0]
	M.apply(g)
end

function M.revert(ui, g)
	if not snap then return end
	ui.t[0], ui.w[0], ui.lt[0], ui.lw[0] = snap.t, snap.w, snap.lt, snap.lw
	M.push(ui, g)
	snap = nil
end

function M.drop() snap = nil end

return M