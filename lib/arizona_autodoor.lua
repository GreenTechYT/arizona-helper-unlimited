-- LIB_VERSION: 1.0
local M = {}
M.enabled = false
M.last_trigger = 0
M.TRIGGER_COOLDOWN = 750
M.NOTIFY_COOLDOWN = 5000
M.last_no_key_notify = 0
M.generation = 0
M.loop_started = false
M._error_logged = false
M.notify_func = nil
M.cached_targets = {}
M.last_cache_update = 0
local sync_mem = nil
local last_px, last_py, last_pz = 0, 0, 0

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

local function isValidHeading(heading)
    return (heading > 179 and heading < 181) or
           (heading > 89 and heading < 91) or
           (heading > -1 and heading < 1) or
           (heading > 269 and heading < 271)
end

local function sendKeyForCar()
    setGameKeyState(18, 255)
end

local function sendClickKeySync()
    if not sync_mem then sync_mem = allocateMemory(68) end
    local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    sampStorePlayerOnfootData(myId, sync_mem)
    local weaponId = getCurrentCharWeapon(PLAYER_PED)
    setStructElement(sync_mem, 36, 1, weaponId + 192, true)
    sampSendOnfootData(sync_mem)
end

local function sendOpenPacket()
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
        if isCharInAnyCar(PLAYER_PED) then
            sendKeyForCar()
        else
            sendClickKeySync()
        end
    end
end

local function update_object_cache()
    local targets = {}
    for _, hObj in ipairs(getAllObjects()) do
        if doesObjectExist(hObj) then
            local model = getObjectModel(hObj)
            if DOOR_MODELS[model] or BARRIER_MODELS[model] then
                local res, ox, oy, oz = getObjectCoordinates(hObj)
                if res then
                    table.insert(targets, { h = hObj, m = model, x = ox, y = oy, z = oz })
                end
            end
        end
    end
    M.cached_targets = targets
    M.last_cache_update = os.clock()
end

function M.check()
    if not M.enabled then return end
    local now = os.clock() * 1000
    if now - M.last_trigger < M.TRIGGER_COOLDOWN then return end
    if not isMonetLoader() then
        if sampIsChatInputActive() or sampIsDialogActive() or 
           isSampfuncsConsoleActive() or sampIsCursorActive() then
            return
        end
    end
    local px, py, pz = getCharCoordinates(PLAYER_PED)
    local dx, dy, dz = px - last_px, py - last_py, pz - last_pz
    if (dx*dx + dy*dy + dz*dz) < 0.1 then return end
    last_px, last_py, last_pz = px, py, pz
    if os.clock() - M.last_cache_update > 3.0 or #M.cached_targets == 0 then
        update_object_cache()
    end
    local inCar = isCharInAnyCar(PLAYER_PED)
    local maxDist = inCar and 8 or 5
    local maxDistSq = maxDist * maxDist
    for _, obj in ipairs(M.cached_targets) do
        if doesObjectExist(obj.h) then
            local ox, oy, oz = obj.x, obj.y, obj.z
            local distSq = (ox - px)^2 + (oy - py)^2 + (oz - pz)^2      
            if distSq <= maxDistSq then
                if DOOR_MODELS[obj.m] then
                    if distSq <= 4.0 and isValidHeading(getObjectHeading(obj.h)) then
                        sendOpenPacket()
                        M.last_trigger = now
                        return
                    end
                elseif BARRIER_MODELS[obj.m] then
                    sendOpenPacket()
                    M.last_trigger = now
                    return
                end
            end
        end
    end
end

function M.handleNoKeyMessage(text)
    local now = os.clock() * 1000
    if now - M.last_no_key_notify < M.NOTIFY_COOLDOWN then return false end
    if text:find("У вас нет ключей от данного шлагбаума", 1, true) or
       text:find("У вас нет ключей от этого шлагбаума!", 1, true) or
       text:find("У вас нет ключей от этой двери!", 1, true) or
       text:find("У вас нет ключей от данной двери", 1, true) then
        M.last_no_key_notify = now
        return true
    end
    return false
end

function M.set_enabled(value)
    M.enabled = value == true
    if M.enabled then
        M.start_loop()
    else
        M.stop_loop()
    end
end

function M.start_loop()
    if M.loop_started then return end
    M.loop_started = true
    M.generation = M.generation + 1
    local gen = M.generation
    M.last_cache_update = 0 
    lua_thread.create(function()
        while M.enabled and M.loop_started and M.generation == gen do
            wait(33) 
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
end

function M.init(settings, notify_func)
    M.enabled = settings.general.auto_door == true
    M.notify_func = notify_func
    if M.enabled then
        M.start_loop()
    end
    return M
end

return M