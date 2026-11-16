-- LIB_VERSION: 1.1
local M = {}
M.enabled            = false
M.loop_started       = false
M.generation         = 0
M._error_logged      = false
M.notify_func        = nil
M.TICK_MS            = 33
M.CACHE_TTL          = 0.25
M.CACHE_MOVE_SQ      = 225
M.DOOR_DIST_SQ       = 6.25
M.BARRIER_FOOT       = 5
M.BARRIER_CAR        = 12
M.DOOR_COOLDOWN      = 250
M.BARRIER_COOLDOWN   = 700
M.HEADING_TOL        = 3
M.NOTIFY_COOLDOWN    = 5000
M.last_no_key_notify = 0
M.last_trigger       = 0
M.cached_targets     = {}
M.last_cache_update  = 0

local os_clock = os.clock
local sync_mem = nil
local cache_px, cache_py, cache_pz = 0, 0, 0
local obj_cd = {}

local DOOR_MODELS = {
    [1495] = true, [3089] = true, [1561] = true, [19938] = true,
    [1557] = true, [1808] = true, [19857] = true, [19302] = true,
    [2634] = true, [19303] = true
}

local BARRIER_MODELS = {
    [968] = true, [975] = true, [1374] = true, [19912] = true,
    [988] = true, [19313] = true, [11327] = true, [980] = true
}

local function isMonetLoader()
    return MONET_VERSION ~= nil
end

local function isValidHeading(h, tol)
    tol = tonumber(tol) or 3
    local function near(target)
        local d = math.abs((h - target + 180) % 360 - 180)
        return d <= tol
    end
    return near(0) or near(90) or near(180) or near(270)
end

local function sendKeyForCar()
    setGameKeyState(18, 255)
end

local function sendClickKeySync()
    if not sync_mem then sync_mem = allocateMemory(68) end
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    sampStorePlayerOnfootData(myId, sync_mem)
    setStructElement(sync_mem, 36, 1, getCurrentCharWeapon(PLAYER_PED) + 192, true)
    sampSendOnfootData(sync_mem)
end

local function sendOpenPacket(inCar)
    if isMonetLoader() then
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt8(bs, 220)
        raknetBitStreamWriteInt8(bs, 63)
        raknetBitStreamWriteInt8(bs, 8)
        raknetBitStreamWriteInt32(bs, 7)
        raknetBitStreamWriteInt32(bs, -1)
        raknetBitStreamWriteInt32(bs, 0)
        raknetBitStreamWriteString(bs, "")
        raknetSendBitStreamEx(bs, 1, 7, 1)
        raknetDeleteBitStream(bs)
    else
        if inCar == nil then inCar = isCharInAnyCar(PLAYER_PED) end
        if inCar then sendKeyForCar() else sendClickKeySync() end
    end
end

local function update_object_cache(px, py, pz)
    local getAllObjects, doesObjectExist, getObjectModel, getObjectCoordinates = getAllObjects, doesObjectExist, getObjectModel, getObjectCoordinates
    local targets, n, seen = {}, 0, {}
    for _, h in ipairs(getAllObjects()) do
        if doesObjectExist(h) then
            local model = getObjectModel(h)
            local kind = DOOR_MODELS[model] and 1 or (BARRIER_MODELS[model] and 2 or 0)
            if kind ~= 0 then
                local ok, x, y, z = getObjectCoordinates(h)
                if ok then
                    n = n + 1
                    targets[n] = { h = h, m = model, k = kind, x = x, y = y, z = z }
                    seen[h] = true
                end
            end
        end
    end
    for h in pairs(obj_cd) do
        if not seen[h] then obj_cd[h] = nil end
    end
    M.cached_targets = targets
    M.last_cache_update = os_clock()
    cache_px, cache_py, cache_pz = px, py, pz
end

function M.check()
    if not M.enabled then return end
    if not isMonetLoader() then
        if sampIsChatInputActive() or sampIsDialogActive()
            or isSampfuncsConsoleActive() or sampIsCursorActive() then
            return
        end
    end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local t = os_clock()
    if t - M.last_cache_update >= M.CACHE_TTL then
        update_object_cache(px, py, pz)
    else
        local mx, my, mz = px - cache_px, py - cache_py, pz - cache_pz
        if mx * mx + my * my + mz * mz >= M.CACHE_MOVE_SQ then
            update_object_cache(px, py, pz)
        end
    end
    local list = M.cached_targets
    local n = #list
    if n == 0 then return end
    local now = t * 1000
    local inCar = isCharInAnyCar(PLAYER_PED)
    local bDist = inCar and M.BARRIER_CAR or M.BARRIER_FOOT
    local bDistSq = bDist * bDist
    local doesObjectExist, getObjectModel, getObjectHeading = doesObjectExist, getObjectModel, getObjectHeading
    local best_door, best_door_d2
    local best_bar,  best_bar_d2
    local stale = false
    for i = 1, n do
        local o = list[i]
        local lim = (o.k == 1) and M.DOOR_DIST_SQ or bDistSq
        local dx, dy, dz = o.x - px, o.y - py, o.z - pz
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 <= lim then
            if not doesObjectExist(o.h) or getObjectModel(o.h) ~= o.m then
                stale = true
            else
                local cd = (o.k == 1) and M.DOOR_COOLDOWN or M.BARRIER_COOLDOWN
                if now - (obj_cd[o.h] or 0) >= cd then
                    if o.k == 1 then
                        if isValidHeading(getObjectHeading(o.h), M.HEADING_TOL) then
                            if not best_door_d2 or d2 < best_door_d2 then
                                best_door, best_door_d2 = o, d2
                            end
                        end
                    elseif not best_bar_d2 or d2 < best_bar_d2 then
                        best_bar, best_bar_d2 = o, d2
                    end
                end
            end
        end
    end
    if stale then update_object_cache(px, py, pz) end
    local target = best_door or best_bar
    if target then
        sendOpenPacket(inCar)
        obj_cd[target.h] = now
        M.last_trigger = now
    end
end

function M.handleNoKeyMessage(text)
    if type(text) ~= 'string' then return false end
    if not text:find('нет ключей', 1, true) then return false end
    local now = os_clock() * 1000
    if now - M.last_no_key_notify < M.NOTIFY_COOLDOWN then return false end
    M.last_no_key_notify = now
    return true
end

function M.start_loop()
    if M.loop_started then return end
    M.loop_started = true
    M._error_logged = false
    M.generation = M.generation + 1
    local gen = M.generation
    M.last_cache_update = 0
    obj_cd = {}
    lua_thread.create(function()
        while M.enabled and M.loop_started and M.generation == gen do
            wait(M.TICK_MS)
            local ok, err = pcall(M.check)
            if not ok and not M._error_logged then
                M._error_logged = true
                print('[AutoDoor] Ошибка в check(): ' .. tostring(err))
            end
        end
        M.loop_started = false
    end)
end

function M.stop_loop()
    M.loop_started = false
    M.cached_targets = {}
    obj_cd = {}
end

function M.set_enabled(value)
    M.enabled = value == true
    if M.enabled then M.start_loop() else M.stop_loop() end
end

function M.init(settings, notify_func)
    M.enabled = settings.general.auto_door == true
    M.notify_func = notify_func
    if M.enabled then M.start_loop() end
    return M
end

return M