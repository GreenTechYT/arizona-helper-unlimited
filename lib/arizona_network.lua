-- LIB_VERSION: 1.1
local M = {}
M.version = '1.1'
M.ctx = nil
M.base_url = ''
M.default_url = 'https://my-helper-api.greentechyt-helper.workers.dev'
M.enabled = false
M.server = 1
M.nick = ''
M.hwid = ''
M.users = {}
M.crown_users = {}
M.admin_users = {}
M.all_users = {}
M.show_users = false
M.chat_open = false
M.network_thread_started = false
M.disabled = false
M.messages = {}
M.system_messages = {}
M.last_system_id = 0
M.session_started_at = os.time()
M.last_id = 0
M.max_messages = 200
M.online = false
M.polling = false
M.running = false
M.started = false
M.last_error = ''
M.auto_scroll = true
M.window = nil
M.input = nil
M.admin_panel = nil
M.admin_panel_want_open = false
M.admin_confirm = nil
M.admin_mute_buf = nil
M.admin_lobby = nil
M.server_pick_open = false
M.server_pick_buf = nil
M.banned_users = {}
M.mute_until = {}
M.ban_until = {}
M.my_ban_until = 0
M.my_mute_until = 0
M.my_banned = false
M.session = ''
M.user_servers = {}
M.user_devices = {}
M.user_fractions = {}
M.online_any = {}
M.last_heartbeat_at = 0
M.last_cleared_at = ''
M.last_fetch_users = 0
M.last_fetch_crowns = 0
M.last_poll = 0
M.last_group_mention_at = 0
M.MENTION_COOLDOWN = 120
M.last_send_at = 0
M.SEND_COOLDOWN = 2
M.SYNC_INTERVAL = 30
M.HEARTBEAT_INTERVAL = 90
M.USERS_INTERVAL = 180
M.CROWNS_INTERVAL = 180
M.backoff_until = 0
M.backoff_sec = 30
M.show_avatars = true
M.chat_crowns = true
M.input_gen = 0
M.notices = {}
M.MAX_INPUT_LINES = 2
M.network_tasks = {}

local admin_ok, admin_mod = pcall(require, 'arizona_admin')
M.admin = admin_ok and admin_mod or nil
local dkjson_ok, dkjson = pcall(require, 'dkjson')
local ffi_ok, ffi = pcall(require, 'ffi')
if ffi_ok then
    pcall(ffi.cdef, [[
        int __stdcall GetVolumeInformationA(const char* root, char* volume, unsigned long volume_size, unsigned long* serial, unsigned long* max_component, unsigned long* flags, char* fs, unsigned long fs_size);
    ]])
end

local function ctx() return M.ctx or {} end
local function config_path() return tostring(ctx().config_dir or '') .. '/HelperNetwork.json' end

local EMOJIS_ICONS = { 'FACE_SMILE', 'FACE_GRIN', 'FACE_LAUGH', 'FACE_MEH', 'FACE_FROWN',  'THUMBS_UP', 'THUMBS_DOWN', 'HEART', 'FIRE',
    'ROCKET', 'STAR', 'SKULL', 'GHOST', 'LIGHTBULB', 'BOMB', 'TROPHY', 'GIFT', 'CROWN'
}
local MENTION_MODES = { 'police', 'fbi', 'hospital', 'smi', 'army', 'prison', 'gov', 'mafia', 'ghetto', 'judge' }
local SERVER_ERRORS = {
    unauthorized = 'сессия устарела (обновляю автоматически)',
    rate_limit = 'слишком много запросов, подождите',
    storage_unavailable = 'хранилище временно недоступно',
    database_unavailable = 'база данных временно недоступна',
    message_too_long = 'сообщение слишком длинное',
    too_many_messages = 'слишком много сообщений, подождите',
    muted = 'вы заглушены',
    banned = 'вы заблокированы в чате',
    cooldown = 'кулдаун: подождите немного',
    flood = 'флуд-защита: подождите немного',
    too_fast = 'слишком быстро: подождите немного',
    spam = 'расценено как спам: подождите немного',
    slow_down = 'слишком часто: сбавьте темп',
}
local function one_line(t)
    local s = tostring(t):gsub('[\r\n]+', '. '):gsub('%.%s*%.', '.'):gsub('%s+', ' ')
    return s:gsub('^%s+', ''):gsub('%s+$', '')
end
local function is_utf8_string(text)
    local i, length = 1, #text
    while i <= length do
        local c = text:byte(i)
        if c < 0x80 then i = i + 1
        elseif c >= 0xC2 and c <= 0xDF then
            if i + 1 > length or text:byte(i + 1) < 0x80 or text:byte(i + 1) > 0xBF then return false end
            i = i + 2
        elseif c >= 0xE0 and c <= 0xEF then
            if i + 2 > length or text:byte(i + 1) < 0x80 or text:byte(i + 1) > 0xBF or text:byte(i + 2) < 0x80 or text:byte(i + 2) > 0xBF then return false end
            i = i + 3
        elseif c >= 0xF0 and c <= 0xF4 then
            if i + 3 > length then return false end
            i = i + 4
        else return false end
    end
    return true
end
local su8
local function trim(text) return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function utf8_cut(s, n) s = tostring(s) if #s <= n then return s end local cut = s:sub(1, n) return cut:gsub('[\128-\191]+$', '') end
function M.to_utf8(text)
    local value = tostring(text or '')
    if value == '' or is_utf8_string(value) then return value end
    return su8(value)
end
local function ru_system_text(t)
    local low = tostring(t):lower()
    for k, v in pairs(SERVER_ERRORS) do
        if low:find(k, 1, true) then 
            local result = v
            if not is_utf8_string(result) then
                result = su8(result)
            end
            return result 
        end
    end
    local original = tostring(t)
    if not is_utf8_string(original) then
        return su8(original)
    end
    return original
end
local function notice(text, kind)
    local final_text = M.to_utf8(tostring(text))
    M.notices = M.notices or {}
    local now = os.time()
    for _, n in ipairs(M.notices) do
        if n.text == final_text then
            n.until_ts = now + 6
            return
        end
    end
    table.insert(M.notices, { text = final_text, kind = kind or 'warn', until_ts = now + 6 })
    while #M.notices > 3 do table.remove(M.notices, 1) end
end

local REACT_ICONS = { 'HEART', 'THUMBS_UP', 'THUMBS_DOWN', 'FACE_LAUGH', 'FIRE', 'STAR' }
local AVATAR_ICONS = { 'FACE_SMILE', 'FACE_GRIN', 'STAR', 'CROWN', 'HEART', 'FIRE', 'ROCKET', 'SKULL', 'GHOST', 'TROPHY' }
M.user_avatars = M.user_avatars or {}
local AVATAR_ICON_SET = {}
for _, k in ipairs(AVATAR_ICONS) do AVATAR_ICON_SET[k] = true end

local function clamp255(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > 255 then v = 255 end
    return math.floor(v + 0.5)
end

local function norm_color3(v)
    if type(v) == 'table' then
        if v[1] == nil then return nil end
        return { clamp255(v[1]), clamp255(v[2]), clamp255(v[3]) }
    end
    local r, g, b = tostring(v or ''):match('^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$')
    if not r then return nil end
    return { clamp255(r), clamp255(g), clamp255(b) }
end

local function norm_avatar(mode, icon, bg, fg, outline)
    local m = (tostring(mode or '') == 'icon') and 'icon' or 'letters'
    local ic = tostring(icon or '')
    if not AVATAR_ICON_SET[ic] then ic = 'FACE_SMILE' end
    local o = tonumber(outline) or 0
    o = math.max(0, math.min(3, math.floor(o)))
    return m, ic, norm_color3(bg), norm_color3(fg), o
end

local function avatar_sig_of(mode, icon, bg, fg, outline)
    return table.concat({
        tostring(mode), tostring(icon),
        bg and table.concat(bg, ',') or '',
        fg and table.concat(fg, ',') or '',
        tostring(outline)
    }, '|')
end

function M.my_avatar()
    return norm_avatar(M.avatar_mode, M.avatar_icon, M.avatar_bg, M.avatar_fg, M.avatar_outline)
end

local function store_user_avatar(nick, item)
    if type(nick) ~= 'string' or nick == '' or type(item) ~= 'table' then return end
    if item.avatar_mode == nil and item.avatar_icon == nil and item.avatar_bg == nil then return end
    local m, ic, bg, fg, o = norm_avatar(item.avatar_mode, item.avatar_icon, item.avatar_bg, item.avatar_fg, item.avatar_outline)
    M.user_avatars[nick] = { mode = m, icon = ic, bg = bg, fg = fg, outline = o }
end

local function resolve_other_avatar(sender, message)
    local has_msg = type(message) == 'table' and (
        message.avatar_mode ~= nil or message.avatar_icon ~= nil or
        (message.avatar_bg ~= nil and message.avatar_bg ~= '')
    )
    if has_msg then
        return norm_avatar(message.avatar_mode, message.avatar_icon, message.avatar_bg, message.avatar_fg, message.avatar_outline)
    end
    local ua = M.user_avatars[sender]
    if ua then return ua.mode, ua.icon, ua.bg, ua.fg, ua.outline end
    return 'letters', 'FACE_SMILE', nil, nil, 0
end

local function draw_glyph_outlined(imgui, dl, x, y, txt, col_u32, outline)
    if outline and outline > 0 then
        local oc = imgui.GetColorU32Vec4(imgui.ImVec4(0, 0, 0, 0.85))
        for ox = -outline, outline do
            for oy = -outline, outline do
                if ox ~= 0 or oy ~= 0 then dl:AddText(imgui.ImVec2(x + ox, y + oy), oc, txt) end
            end
        end
    end
    dl:AddText(imgui.ImVec2(x, y), col_u32, txt)
end

local http
function M.apply_reactions(map)
    if type(map) ~= 'table' then return end
    M.msg_reactions = M.msg_reactions or {}
    for mid, icons in pairs(map) do
        if type(icons) ~= 'table' then
            M.msg_reactions[tonumber(mid) or mid] = nil
        else
            local out = {}
        for icon, data in pairs(icons) do
            if type(data) == 'table' then
                out[icon] = { n = tonumber(data.n or data.count) or 0, mine = data.mine == true or data.mine == 1 }
            elseif type(data) == 'number' then
                out[icon] = { n = data, mine = false }
            end
        end
        M.msg_reactions[tonumber(mid) or mid] = out
        end
    end
end

function M.toggle_reaction(id, icon, server)
    local mid = tonumber(id) or 0
    if mid <= 0 or not M.enabled then return end
    local srv = tonumber(server) or tonumber(M.get_server()) or 1
    http('POST', '/messages/reactions', { message_id = mid, server = srv, icon = tostring(icon or '') }, function(data)
        if type(data) == 'table' and data.ok == true then
            M.apply_reactions({ [mid] = data.reactions })
        elseif type(data) == 'table' and data.error then
            notice('Не удалось поставить реакцию: ' .. (SERVER_ERRORS[tostring(data.error)] or ru_system_text(data.error)), 'err')
        end
    end, function(err) M.last_error = tostring(err or '') end, M.session_headers(), true)
end

function M.report_message(msg)
    if type(msg) ~= 'table' then return end
    local payload = {
    kind = 'message', message_id = tonumber(msg.id) or 0, server = tonumber(msg.server) or tonumber(M.get_server()) or 1,
    sender = tostring(msg.sender or ''), text = tostring(msg.text or ''),
    problem = 'Жалоба на сообщение в мессенджере', actions = '',
    version = ctx().version or '1.8.0', channel = (ctx().settings and ctx().settings.general and ctx().settings.general.beta_tester) and 'beta' or 'stable'
    }
    M.send_report(payload, function(ok)
    if ok then notice('Жалоба отправлена модератору', 'ok') else notice('Не удалось отправить жалобу', 'err') end
    end)
end

function M.send_report(payload, callback)
    if type(payload) ~= 'table' then return false end
    payload.kind = payload.kind == 'message' and 'message' or 'support'
    payload.server = tonumber(payload.server) or tonumber(M.get_home_server()) or 1
    payload.version = payload.version or ctx().version or '1.8.0'
    payload.channel = payload.channel or ((ctx().settings and ctx().settings.general and ctx().settings.general.beta_tester) and 'beta' or 'stable')
    http('POST', '/reports', payload, function(data)
    local ok = type(data) == 'table' and data.ok == true
    if type(callback) == 'function' then pcall(callback, ok, data) end
    end, function(err)
    M.last_error = tostring(err or '')
    if type(callback) == 'function' then pcall(callback, false, { error = tostring(err or '') }) end
    end, M.session_headers(), true)
    return true
end

function M.fetch_reports(callback)
    if not M.enabled then return false end
    http('GET', '/reports?mine=1', nil, function(data)
    if type(callback) == 'function' then pcall(callback, type(data) == 'table' and data.reports or {}) end
    end, function(err) M.last_error = tostring(err or '') end, M.session_headers())
    return true
end

function M.fetch_admin_reports(callback)
    http('GET', '/admin/reports', nil, function(data)
    if type(callback) == 'function' then pcall(callback, type(data) == 'table' and data.reports or {}) end
    end, function(err) M.last_error = tostring(err or '') end, M.session_headers())
    return true
end

function M.set_report_status(id, status, callback)
    http('POST', '/admin/reports/status', { id = tonumber(id) or 0, status = tostring(status or 'new') }, function(data)
    if type(callback) == 'function' then pcall(callback, type(data) == 'table' and data.ok == true, data) end
    end, function(err) M.last_error = tostring(err or '') end, M.session_headers(), true)
end

function M.set_pin(id, pinned)
    local mid = tonumber(id) or 0
    if mid <= 0 then return false end
    local srv = tonumber(M.get_server()) or 1
    for _, m in ipairs(M.messages) do if m.id == mid then srv = tonumber(m.server) or srv; break end end
    http('POST', '/messages/pin', { message_id = mid, server = srv, pinned = pinned ~= false }, function(data)
    if type(data) == 'table' and data.ok == true then
    if data.pinned then
        M.pinned = { id = data.pinned.id, sender = data.pinned.sender, text = M.to_utf8(tostring(data.pinned.text or '')), timestamp = data.pinned.timestamp, server = srv }
        else M.pinned = nil end
    else
        notice('Не удалось изменить закрепление', 'err')
    end
    end, function(err) M.last_error = tostring(err or '') end, M.session_headers(), true)
    return true
end
M.pinned = nil
M.avatar_mode = M.avatar_mode or 'letters'
M.avatar_icon = M.avatar_icon or 'FACE_SMILE'
M.avatar_outline = M.avatar_outline or 1

local SU8_CACHE = {}
su8 = function(v)
    if type(v) ~= 'string' then
        if v == nil then return '' end
        v = tostring(v)
    end
    if v == '' then return '' end
    if not v:find('[\128-\255]') then return v end
    if #v <= 128 then
        local c = SU8_CACHE[v]
        if c then return c end
        local u8 = ctx().u8
        if not u8 then return v end
        local ok, r = pcall(u8, v)
        local res = (ok and r) or v
        if #SU8_CACHE < 2048 then SU8_CACHE[v] = res end
        return res
    end
    local u8 = ctx().u8
    if not u8 then return v end
    local ok, r = pcall(u8, v)
    return (ok and r) or v
end

local function to_cp1251(t)
    local u8 = ctx().u8
    if not u8 or not u8.decode then return t end
    local ok, r = pcall(u8.decode, u8, t)
    return (ok and type(r) == 'string' and r ~= '') and r or t
end
local function to_clip(t)
    local clean = tostring(t)
        :gsub('[\238\239][\128-\191][\128-\191]', '')
        :gsub('[\240-\244][\128-\191][\128-\191][\128-\191]', '')
    return to_cp1251(clean)
end

local ignore = {[')']=true,['))']=true,['(']=true,['((']=true,['q']=true,['<3']=true}
local function apply_rp_format(msg)
    if type(msg) ~= 'string' or msg == '' or ignore[msg] then return msg end
    local s = ctx().settings
    if not (s and s.general and s.general.rp_chat == true) or type(string.rupper) ~= 'function' then return msg end
    local u8 = ctx().u8
    local cp = msg
    if u8 then
        local ok, dec = pcall(u8.decode, u8, msg)
        if ok and type(dec) == 'string' and dec ~= '' then cp = dec else u8 = nil end
    end
    cp = cp:sub(1, 1):rupper() .. cp:sub(2)
    if not cp:match('[.!?]$') then cp = cp .. '.' end
    return (u8 and su8(cp)) or cp
end

local function insert_to_input(utf8_text)
    if not M.input then M.input = imgui.new.char[4096]('') end
    local current = ffi.string(M.input, 4096):match("^[^%z]*") or ""
    local addition = (current ~= '' and not current:match('%s$') and ' ' or '') .. utf8_text .. ' '
    local new_text = utf8_cut(current .. addition, 4000)
    ffi.fill(M.input, 4096, 0)
    ffi.copy(M.input, new_text)
    M.input_gen = (M.input_gen or 0) + 1
end

local function decode_json(text)
    if not text or text == '' then return nil end
    if type(ctx().decodeJson) == 'function' then
        local ok, data = pcall(ctx().decodeJson, text)
        if ok and type(data) == 'table' then return data end
    end
    if dkjson_ok and dkjson and type(dkjson.decode) == 'function' then
        local ok, data = pcall(dkjson.decode, text)
        if ok and type(data) == 'table' then return data end
    end
    return nil
end

local function utf8_deep(value, seen)
    if type(value) == 'string' then return M.to_utf8(value) end
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        local key = type(k) == 'string' and M.to_utf8(k) or k
        out[key] = utf8_deep(v, seen)
    end
    return out
end

local function encode_json(data, pretty)
    data = utf8_deep(data)
    if pretty and dkjson_ok and dkjson and type(dkjson.encode) == 'function' then
        local ok, text = pcall(dkjson.encode, data, { indent = true })
        if ok and type(text) == 'string' then return text end
    end
    if type(ctx().encodeJson) == 'function' then
        local ok, text = pcall(ctx().encodeJson, data)
        if ok and type(text) == 'string' then return text end
    end
    if dkjson_ok and dkjson and type(dkjson.encode) == 'function' then
        local ok, text = pcall(dkjson.encode, data)
        if ok and type(text) == 'string' then return text end
    end
    return ''
end

local function read_config()
    local path = config_path()
    if path == '/HelperNetwork.json' or not doesFileExist(path) then return {} end
    local file = io.open(path, 'r')
    if not file then return {} end
    local text = file:read('*a')
    file:close()
    return decode_json(text) or {}
end

function M.save_config(force)
    if M.ctx == nil then return end
    local m, i, b, f, o = M.my_avatar()
    local sig = avatar_sig_of(m, i, b, f, o)
    if M._avatar_sig ~= nil and M._avatar_sig ~= sig then M._avatar_dirty = true end
    M._avatar_sig = sig

    local now = os.time()
    if not force and M._cfg_last_write and now - M._cfg_last_write < 2 then return end
    M._cfg_last_write = now

    local data = {
        server = M.server, hwid = M.hwid,
        chat_crowns = M.chat_crowns ~= false, last_id = M.last_id or 0,
        last_system_id = M.last_system_id or 0, hide_system = M.hide_system == true,
        show_avatars = M.show_avatars ~= false, last_cleared_at = M.last_cleared_at or '',
        avatar_mode = m, avatar_icon = i, avatar_outline = o, avatar_bg = b, avatar_fg = f
    }
    local path = config_path()
    if path == '/HelperNetwork.json' then return end
    local file = io.open(path, 'w')
    if not file then return end
    file:write(encode_json(data, true))
    file:close()
end

local function make_hwid()
    if IS_MOBILE then
        local mobile_ok, android_id = pcall(function()
            local envu = require('android.jnienv-util')
            envu.LooperPrepare()
            local activity = require('android.jni-raw').activity
            local resolver = envu.CallObjectMethod(activity, 'getContentResolver', '()Landroid/content/ContentResolver;')
            local setting = envu.GetStaticObjectField('android/provider/Settings$Secure', 'ANDROID_ID', 'Ljava/lang/String;')
            local value = envu.CallStaticObjectMethod('android/provider/Settings$Secure', 'getString', '(Landroid/content/ContentResolver;Ljava/lang/String;)Ljava/lang/String;', resolver, setting)
            return envu.FromJString(value)
        end)
        if mobile_ok and android_id and tostring(android_id) ~= '' then return 'AH-MOBILE-' .. tostring(android_id) end
    end
    local serial = ''
    if ffi_ok then
        pcall(function()
            local value = ffi.new('unsigned long[1]')
            if ffi.C.GetVolumeInformationA('C:\\', nil, 0, value, nil, nil, nil, 0) ~= 0 then
                serial = string.format('%08X', tonumber(value[0]) or 0)
            end
        end)
    end
    local name = ''
    pcall(function()
        if type(getComputerName) == 'function' then name = tostring(getComputerName() or '') end
    end)
    name = name:gsub('[^%w]', ''):sub(1, 24)
    if serial == '' then serial = 'UNKNOWN' end
    if name == '' then name = 'PC' end
    return 'AH-' .. serial .. '-' .. name
end

function M.get_server()
    if M.admin_lobby then
        if tostring(M.admin_lobby) == '00' then return '900' end
        return M.admin_lobby
    end
    if not isSampAvailable() then
        local srv = tonumber(M.server) or 1
        return srv < 10 and string.format('0%d', srv) or tostring(srv)
    end
    local ok, value = pcall(function() return getServerNumber() end)
    if ok and type(value) == 'string' and value ~= '' and value ~= '00' then return value end
    local srv = tonumber(M.server) or 1
    return srv < 10 and string.format('0%d', srv) or tostring(srv)
end

function M.get_home_server()
    if not isSampAvailable() then
        local srv = tonumber(M.server) or 1
        return srv < 10 and string.format('0%d', srv) or tostring(srv)
    end
    local ok, value = pcall(function() return getServerNumber() end)
    if ok and type(value) == 'string' and value ~= '' and value ~= '00' then return value end
    local srv = tonumber(M.server) or 1
    return srv < 10 and string.format('0%d', srv) or tostring(srv)
end

local function norm_server(value)
    local n = tonumber(value)
    if not n or n < 1 then return '' end
    return n < 10 and string.format('0%d', n) or tostring(n)
end

local function server_tag_for(nick, srv_override)
    local is_admin = M.admin_users[nick] == true or (nick ~= '' and nick == M.get_nick() and M.is_admin())
    if is_admin then return '' end

    local srv = srv_override or ((nick ~= '' and nick == M.get_nick()) and M.get_home_server() or (M.user_servers[nick] or ''))
    if srv == '' then return '' end
    local view = tostring(M.get_server())
    if view == '900' then 
        if srv == '900' then return '' end
        return ' [' .. srv .. ']' 
    end
    if srv == view then return '' end    
    return ' [' .. srv .. ']'
end

function M.get_nick()
    if not isSampAvailable() or not sampIsLocalPlayerSpawned() then return M.nick end
    local ok, nick = pcall(function()
        local id = select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))
        if id and id >= 0 then return sampGetPlayerNickname(id) or '' end
        return ''
    end)
    if ok and type(nick) == 'string' and nick ~= '' then return nick end
    return M.nick
end

local function sync_http(method, path, body, extra_headers)
    local result = nil
    local done = false
    local headers = { ['Content-Type'] = 'application/json' }
    if type(extra_headers) == 'table' then for k, v in pairs(extra_headers) do headers[k] = v end end
    local args = { timeout = 8, headers = headers }
    if body ~= nil then args.data = encode_json(body) end
    
    local ok_call = pcall(ctx().asyncHttpRequest, method, M.base_url .. path, args, function(response)
        result = { type = 'ok', response = response }
        done = true
    end, function(err)
        result = { type = 'err', err = err }
        done = true
    end)
    
    if not ok_call then
        return { type = 'err', err = 'pcall_failed' }
    end
    
    local timeout = os.time() + 12
    while not done and M.running and os.time() < timeout do
        wait(0)
    end
    
    if not done then
        return { type = 'err', err = 'timeout' }
    end
    
    if result.type == 'ok' then
        local data = decode_json(result.response and result.response.text or '')
        result.data = data
    end
    return result
end

http = function(method, path, body, on_ok, on_error, extra_headers, priority)
    if not M.enabled or M.base_url == '' then return false end
    if #M.network_tasks >= 64 then
        for i = #M.network_tasks, 1, -1 do
            if not M.network_tasks[i].priority then table.remove(M.network_tasks, i); break end
        end
    end    
    table.insert(M.network_tasks, {
        method = method, path = path, body = body,
        on_ok = on_ok, on_error = on_error, headers = extra_headers,
        priority = priority
    })
    return true
end

local function parse_iso_time(value)
    local year, month, day, hour, minute, second = tostring(value or ''):match('(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
    if not year then year, month, day, hour, minute, second = tostring(value or ''):match('(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)') end
    if not year then return 0 end
    local stamp = os.time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = tonumber(hour), min = tonumber(minute), sec = tonumber(second) })
    local offset = os.time() - os.time(os.date("!*t"))
    return stamp + offset
end

function M.format_remaining(seconds)
    local value = math.max(0, math.floor(tonumber(seconds) or 0))
    local str
    if value >= 86400 then str = math.floor(value / 86400) .. ' д ' .. math.floor((value % 86400) / 3600) .. ' ч'
    elseif value >= 3600 then str = math.floor(value / 3600) .. ' ч ' .. math.floor((value % 3600) / 60) .. ' мин'
    else str = math.floor(value / 60) .. ' мин ' .. (value % 60) .. ' сек' end
    return tostring(ctx().u8 and ctx().u8(str) or str)
end

function M.fetch_users()
    if not M.enabled then return end
    if os.time() - M.last_fetch_users < 5 then return end
    M.last_fetch_users = os.time()
    
    http('GET', '/users?server=' .. tostring(M.get_server()), nil, function(data)
        if type(data) ~= 'table' then return end
        M.users, M.crown_users, M.admin_users = {}, {}, {}
        for _, item in ipairs(data.users or {}) do
            local nick = type(item) == 'table' and item.nick or item
            if type(nick) == 'string' then
                local online = type(item) == 'table' and (item.online == 1 or item.online == true) or false
                local since = type(item) == 'table' and tostring(item.first_seen or '') or ''
                local is_admin_user = type(item) == 'table' and (item.admin == 1 or item.admin == true) or false
                local user_srv = norm_server(type(item) == 'table' and (item.home or item.server) or nil)
                if user_srv ~= '' then M.user_servers[nick] = user_srv end
                local user_dev = type(item) == 'table' and tostring(item.device or '') or ''
                local user_frac = M.to_utf8(type(item) == 'table' and tostring(item.fraction_tag or item.mode or '') or '')
                if user_dev ~= '' then M.user_devices[nick] = user_dev end
                if user_frac ~= '' then M.user_fractions[nick] = user_frac end
                store_user_avatar(nick, item)
                M.crown_users[nick] = true
                local banned_flag = type(item) == 'table' and (item.banned == 1 or item.banned == true) or false
                local mute_until = type(item) == 'table' and tostring(item.mute_until or '') or ''
                local ban_until = type(item) == 'table' and tostring(item.ban_until or '') or ''
                if banned_flag then M.banned_users[nick] = true else M.banned_users[nick] = nil end
                M.mute_until[nick] = mute_until ~= '' and parse_iso_time(mute_until) or 0
                M.ban_until[nick] = ban_until ~= '' and parse_iso_time(ban_until) or 0
                if is_admin_user then M.admin_users[nick] = true end
                if online then
                    M.users[nick] = true
                    local found = false
                    for _, u in ipairs(M.all_users) do
                        if u.nick == nick then
                            u.online, u.admin, u.server, u.device, u.fraction = true, is_admin_user, user_srv, user_dev, user_frac
                            found = true; break
                        end
                    end
                    if not found then
                        table.insert(M.all_users, { nick = nick, first_seen = since, last_seen = type(item) == 'table' and tostring(item.last_seen or '') or '', online = true, admin = is_admin_user, server = user_srv, device = user_dev, fraction = user_frac })
                    end 
                end
            end
        end
        M._users_rev = (M._users_rev or 0) + 1
        if ctx().module and ctx().module.HelperUsers then ctx().module.HelperUsers.list = M.users end
    end, function(err) M.last_error = tostring(err or '') end)
end

function M.fetch_crowns()
    if not M.enabled then return end
    if os.time() - M.last_fetch_crowns < 5 then return end
    M.last_fetch_crowns = os.time()
    
    http('GET', '/crowns?server=' .. tostring(M.get_server()), nil, function(data)
        if type(data) ~= 'table' then return end
        local crowns, admins = {}, {}
        for _, item in ipairs(data.users or {}) do
            local nick = type(item) == 'table' and item.nick or nil
            if type(nick) == 'string' then
                crowns[nick] = true
                store_user_avatar(nick, item)
                if item.admin == 1 or item.admin == true then admins[nick] = true end
                if item.banned == 1 or item.banned == true then M.banned_users[nick] = true else M.banned_users[nick] = nil end
                M.mute_until[nick] = item.mute_until and parse_iso_time(item.mute_until) or 0
                M.ban_until[nick] = item.ban_until and parse_iso_time(item.ban_until) or 0
                local cs = norm_server(item.home or item.server)
                if cs ~= '' then M.user_servers[nick] = cs end
                if item.device and tostring(item.device) ~= '' then M.user_devices[nick] = tostring(item.device) end
                local frac_tag = M.to_utf8(tostring(item.fraction_tag or item.mode or ''))
                if frac_tag ~= '' then M.user_fractions[nick] = frac_tag end
            end
        end
        M.crown_users, M.admin_users = crowns, admins
        M._users_rev = (M._users_rev or 0) + 1
    end, function(err) M.last_error = tostring(err or '') end)
end

function M.fetch_user_directory(silent)
    if not M.enabled then return false end
    http('GET', '/users?server=' .. tostring(M.get_server()), nil, function(data)
        if type(data) ~= 'table' then return end
        M.all_users, M.online_any = {}, {}
        for _, item in ipairs(data.users or {}) do
            if type(item) == 'table' and type(item.nick) == 'string' then
                store_user_avatar(item.nick, item)
                local is_admin_user = (item.admin == 1 or item.admin == true)
                local is_online = (item.online == 1 or item.online == true)
                local user_srv = norm_server(item.home or item.server)
                if user_srv ~= '' then M.user_servers[item.nick] = user_srv end
                local user_dev = tostring(item.device or '')
                local user_frac = M.to_utf8(tostring(item.fraction_tag or item.mode or ''))
                if user_dev ~= '' then M.user_devices[item.nick] = user_dev end
                if user_frac ~= '' then M.user_fractions[item.nick] = user_frac end
                if is_online then M.online_any[item.nick] = true end
                table.insert(M.all_users, { nick = item.nick, first_seen = tostring(item.first_seen or ''), last_seen = tostring(item.last_seen or ''), online = is_online, admin = is_admin_user, server = user_srv, device = user_dev, fraction = user_frac })
                if is_admin_user then M.admin_users[item.nick] = true end
            end
        end
        M._users_rev = (M._users_rev or 0) + 1
        if not silent then M.show_users = true end
    end, function(err)
        M.last_error = tostring(err or '')
    end)
    return true
end

function M.add_system(data)
    if type(data) ~= 'table' then return end
    local nick = M.get_nick()
    local target = tostring(data.target or '')
    local admin = tostring(data.admin or '')
    if nick == '' or not (target == nick or admin == nick) then return end
    local id = tonumber(data.id) or 0
    if id > 0 and id <= M.last_system_id then return end
    local ts = tostring(data.created_at or data.timestamp or '')
    local event_epoch = parse_iso_time(ts)
    if event_epoch > 0 and event_epoch < (M.session_started_at or 0) - 5 then
        if id > M.last_system_id then M.last_system_id = id end
        return
    end
    if ts == '' then ts = os.date('!%Y-%m-%d %H:%M:%SZ') end
    local recent_status = parse_iso_time(ts) > os.time() - 10
    if target == nick and recent_status then
        local status_text = M.to_utf8(tostring(data.text or ''))
        if data.banned ~= nil then
            M.my_banned = (data.banned == true) or (tonumber(data.banned) == 1)
            M.my_ban_until = data.ban_until and parse_iso_time(data.ban_until) or 0
            if M.my_banned then M.messages = {}; M.system_messages = {} end
        end
        if data.mute_until ~= nil then M.my_mute_until = parse_iso_time(data.mute_until) end
        if status_text:find(M.to_utf8('Блокировка снята'), 1, true) then
            M.my_banned = false; M.my_ban_until = 0; M.messages = {}; M.system_messages = {}; M.last_id = 0; M.last_system_id = 0
            M.poll(true)
        end
        if status_text:find(M.to_utf8('Мут снят'), 1, true) then M.my_mute_until = 0; M.print('Мут снят.') end
    end
    local raw_text = tostring(data.text or '')
    local text_utf8 = M.to_utf8(raw_text)
    table.insert(M.system_messages, { id = id, text = one_line(ru_system_text(text_utf8)), admin = admin, target = target, timestamp = ts })
    if id > M.last_system_id then M.last_system_id = id end
    while #M.system_messages > 100 do table.remove(M.system_messages, 1) end
end

function M.news_likes(key, callback)
    if not M.enabled or M.hwid == '' then return end
    http('POST', '/news/likes', { key = key, hwid = M.hwid }, function(data)
        if type(callback) == 'function' then pcall(callback, data) end
    end, function(err) M.last_error = tostring(err or '') end)
end

function M.vote_news(key, vote, callback)
    if not M.enabled or M.hwid == '' then return end
    http('POST', '/news/like', { key = key, hwid = M.hwid, vote = vote or 'none' }, function(data)
        if type(callback) == 'function' then pcall(callback, data) end
    end, function(err) M.last_error = tostring(err or '') end)
end

function M.current_account()
    local path = tostring(ctx().config_dir or '') .. '/Accounts.json'
    if path == '/Accounts.json' or not doesFileExist(path) then return nil end
    local f = io.open(path, 'r')
    if not f then return nil end
    local data = decode_json(f:read('*a') or '')
    f:close()
    if type(data) ~= 'table' or type(data.list) ~= 'table' then return nil end
    local cur = tostring(data.current or '')
    for _, a in ipairs(data.list) do
        if type(a) == 'table' and tostring(a.name or '') == cur then return a end
    end
    return nil
end

function M.fraction_mode()
    if type(ctx().get_fraction_mode) == 'function' then
        local ok, m = pcall(ctx().get_fraction_mode)
        if ok and type(m) == 'string' and m ~= '' then return m end
    end
    if type(_G.get_fraction_mode) == 'function' then
        local ok, m = pcall(_G.get_fraction_mode)
        if ok and type(m) == 'string' and m ~= '' then return m end
    end
    local sm = ctx().settings and ctx().settings.general and ctx().settings.general.fraction_mode
    if type(sm) == 'string' and sm ~= '' and sm ~= 'none' then return sm end
    local acc = M.current_account()
    if acc and type(acc.fraction_mode) == 'string' and acc.fraction_mode ~= '' and acc.fraction_mode ~= 'none' then 
        return acc.fraction_mode 
    end
    return 'none'
end

function M.player_data()
    if type(ctx().get_player_data) == 'function' then
        local ok, d = pcall(ctx().get_player_data)
        if ok and type(d) == 'table' then return d end
    end
    local m1 = ctx().modules and ctx().modules.player and ctx().modules.player.data
    if type(m1) == 'table' then return m1 end
    local m2 = ctx().module and ctx().module.player and ctx().module.player.data
    if type(m2) == 'table' then return m2 end
    return {}
end

function M.heartbeat()
    if not M.enabled then return end
    local nick = M.get_nick()
    if nick == '' then return end
    M.nick = nick
    M.last_heartbeat_at = os.time()
    local pdata = M.player_data()
    local heartbeat_priority = M.pending_initial_sync == true
    http('POST', '/heartbeat', {
        nick = nick,
        hwid = M.hwid,
        avatar_mode = (function() local m, i, b, f, o = M.my_avatar()
            M._av_m, M._av_i, M._av_b, M._av_f, M._av_o = m, i, b, f, o return m end)(),
        avatar_icon = M._av_i,
        avatar_bg = M._av_b and table.concat(M._av_b, ',') or '',
        avatar_fg = M._av_f and table.concat(M._av_f, ',') or '',
        avatar_outline = M._av_o,
        server = M.get_home_server(),
        home = M.get_home_server(),
        lobby = M.get_server(),
        version = ctx().version or '1.8.0',
        mode = M.fraction_mode(),
        fraction = M.to_utf8(tostring(pdata.fraction or '')),
        fraction_tag = M.to_utf8(tostring(pdata.fraction_tag or '')),
        device = IS_MOBILE and 'MOBILE' or 'PC',
    }, function(data)
        if type(data) == 'table' and data.error == 'rate_limit' then return end
        M.online = data and data.ok == true or false
        if M.online then
            M.session = tostring(data.session or M.session)
        if M.pending_initial_sync and M.chat_open then
            M.pending_initial_sync = false
            M.poll(true)
        end
            local was_banned = M.my_banned
            local was_mute_until = M.my_mute_until
            M.my_banned = (data.banned == true) or (tonumber(data.banned) == 1)
            M.my_ban_until = data.ban_until and parse_iso_time(data.ban_until) or 0
            M.my_mute_until = data.mute_until and parse_iso_time(data.mute_until) or 0
            if was_banned and not M.my_banned then M.print('Блокировка чата снята.') end
            if was_mute_until > os.time() and M.my_mute_until <= os.time() then M.print('Мут снят.') end
            if was_banned and not M.my_banned then M.messages = {}; M.system_messages = {}; M.poll(true) end
            if M.my_banned then M.messages = {}; M.system_messages = {} end
        end
    end, function(err) M.online = false; M.last_error = tostring(err or '') end, nil, heartbeat_priority)
end

function M.session_headers()
    if M.session == '' then return nil end
    return { ['X-Session'] = M.session }
end

local function add_message(message)
    if M.my_banned or type(message) ~= 'table' then return end
    local id = tonumber(message.id) or 0
    if id > 0 and id <= M.last_id then return end
    local item = { id = id, server = tonumber(message.server) or 1, sender = tostring(message.sender or ''), text = M.to_utf8(tostring(message.text or '')), timestamp = tostring(message.timestamp or ''), home = norm_server(message.home), avatar_mode = message.avatar_mode ~= nil and tostring(message.avatar_mode) or nil, avatar_icon = message.avatar_icon ~= nil and tostring(message.avatar_icon) or nil, avatar_bg = message.avatar_bg ~= nil and tostring(message.avatar_bg) or nil, avatar_fg = message.avatar_fg ~= nil and tostring(message.avatar_fg) or nil, avatar_outline = message.avatar_outline ~= nil and tonumber(message.avatar_outline) or nil }
    if item.text == '' then return end
    table.insert(M.messages, item)
    local my_nick = M.get_nick()
    local notifications = (ctx().settings and ctx().settings.notifications) or {}
    local my_mode = M.fraction_mode()
    local is_cross_server = (tostring(M.get_server()) == '900')
    local is_mentioned = false
    local mention_type = 'user'
    local my_nick_u8 = M.to_utf8(my_nick)
    if my_nick ~= '' and item.sender ~= my_nick and item.text:find('@' .. my_nick_u8 .. '%f[%W]') then
        is_mentioned = true
    elseif item.sender ~= my_nick and not is_cross_server and my_mode ~= 'none' then
        if item.text:find('@' .. my_mode .. '%f[%W]') then
            is_mentioned = true
            mention_type = 'mode'
        end
    end
    item.mention_type = mention_type
    item.is_mentioned = is_mentioned
    local ts_epoch = parse_iso_time(item.timestamp)
    local age = os.time() - ts_epoch
    local fresh = (ts_epoch == 0) or (age >= 0 and age <= 60)
    local general = (ctx().settings or {}).general or {}
    if general.ping ~= false and notifications.messenger_mention ~= false and is_mentioned and fresh then
        local MOD = ctx().module or {}
        MOD.PingNotify = MOD.PingNotify or {}
        local short_utf8 = item.text:gsub('{%x%x%x%x%x%x}', ''):sub(1, 90)
        local key = 'ping|' .. item.sender .. '|' .. short_utf8
        if not MOD.PingNotify[key] then
            MOD.PingNotify[key] = os.time()
            if type(ctx().play_sound) == 'function' then pcall(ctx().play_sound) end
            local prefix_text = (mention_type == 'mode') and ('[' .. my_mode .. '] ') or ''
            local line_cp = prefix_text .. 'Вас упомянул ' .. item.sender .. ': ' .. to_cp1251(short_utf8)
            if type(ctx().notify) == 'function' then
                pcall(ctx().notify, 'messenger', '[' .. tostring(ctx().chat_prefix or 'Arizona Helper') .. '] {ffffff}' .. line_cp, ctx().message_color or 40703)
            end
            if type(sampAddChatMessage) == 'function' then
                pcall(sampAddChatMessage, '[' .. tostring(ctx().chat_prefix or 'Arizona Helper') .. ' | Messenger] {ffffff}' .. line_cp, ctx().message_color or 40703)
            end
        end
        local now = os.time()
        for k, v in pairs(MOD.PingNotify) do
            if now - v > 300 then MOD.PingNotify[k] = nil end
        end
        M.auto_scroll = true
    end
    
    if id > M.last_id then M.last_id = id end
    while #M.messages > M.max_messages do table.remove(M.messages, 1) end
    M.auto_scroll = true
end

function M.clear_history()
    if M.admin and type(M.admin.clear_history) == 'function' then M.admin.clear_history(M) end
end

function M.remove_message(id)
    local target = tonumber(id) or 0
    if target <= 0 then return end
    for i = 1, #M.messages do
        if M.messages[i].id == target then
            M.messages[i].text = "Сообщение удалено"
            M.messages[i].deleted = true
            M.messages[i].sender = ""
            break
        end
    end
end

function M.ingest(list)
    if type(list) ~= 'table' then return end
    for _, message in ipairs(list) do add_message(message) end
end

function M.poll(force)
    if not M.enabled or M.my_banned then return end
    if M.polling and not force then return end
    if not force and os.time() < (M.backoff_until or 0) then return end
    if not force and os.time() - M.last_poll < M.SYNC_INTERVAL then return end
    M.last_poll = os.time()
    M.polling = true
    local view_server = tonumber(M.get_server()) or 1
    M._poll_queued = http('GET', '/sync?server=' .. tostring(view_server)
        .. '&after_id=' .. tostring(M.last_id)
        .. '&system_after=' .. tostring(M.last_system_id), nil, function(data)
        M.polling = false
        if type(data) == 'table' and data.error == 'rate_limit' then M.rate_backoff() end
        if type(data) == 'table' and data.error == 'unauthorized' then
            M.session = ''
            M.pending_initial_sync = M.chat_open
            M.heartbeat()
            return
        end
        if type(data) ~= 'table' then return end

        local server_cleared = data.cleared_at or ""
        local cleared_epoch = parse_iso_time(server_cleared)
        local last_cleared_epoch = parse_iso_time(M.last_cleared_at or "")
        if server_cleared ~= "" and cleared_epoch > 0 and cleared_epoch > last_cleared_epoch then
            M.messages = {}
            M.system_messages = {}
            M.last_id = 0
            M.last_system_id = 0
            M.auto_scroll = true
            M.last_cleared_at = server_cleared
            M.add_system({
                id = 0,
                text = "История чата очищена администратором",
                admin = "Система",
                target = "",
                timestamp = server_cleared
            })
            M.save_config()
        end

        M.ingest(data.messages)
        M.apply_reactions(data.reactions)
        for _, event in ipairs(data.events or {}) do M.add_system(event) end

        if data.pinned ~= nil then
            if type(data.pinned) == 'table' then
                M.pinned = {
                    id = data.pinned.id,
                    sender = data.pinned.sender,
                    text = M.to_utf8(tostring(data.pinned.text or '')),
                    timestamp = data.pinned.timestamp,
                    server = view_server
                }
            else
                M.pinned = nil
            end
        end
    end, function(err)
        M.polling = false
        M.last_error = tostring(err or '')
    end, M.session_headers(), force)
    if not M._poll_queued then M.polling = false end
end


function M.rate_backoff()
    local now = os.time()
    M.backoff_sec = math.min(300, math.max(30, (M.backoff_sec or 30) * 2))
    M.backoff_until = now + M.backoff_sec
    M.last_poll = now + M.backoff_sec
    M.last_fetch_users = now + M.backoff_sec
end


local function restore_input(text)
    if not M.input then return end
    local cur = ffi.string(M.input, 4096):match("^[^%z]*") or ""
    if cur ~= '' then return end
    ffi.fill(M.input, 4096, 0)
    ffi.copy(M.input, utf8_cut(text, 4000))
    M.input_gen = (M.input_gen or 0) + 1
end

function M.send(text)
    local raw_in = trim(text)
    local message = apply_rp_format(raw_in)
    if message == '' then return false end
    if #message > 2000 then message = utf8_cut(message, 2000) end
    local nick = M.get_nick()
    if nick == '' then return false end
    
    if M.my_ban_until > os.time() then
        notice('У вас блокировка чата: осталось ' .. math.ceil((M.my_ban_until - os.time()) / 60) .. ' мин', 'err')
        return false
    elseif M.my_mute_until > os.time() then
        notice('У вас мут: осталось ' .. math.ceil((M.my_mute_until - os.time()) / 60) .. ' мин', 'err')
        return false
    end
    if not M.enabled then M.print('Мессенджер отключен (сбор данных выключен в настройках).'); return false end

    local flood_left = M.SEND_COOLDOWN - (os.time() - (M.last_send_at or 0))
    if flood_left > 0 then
        notice('Защита от флуда: следующее сообщение через ' .. flood_left .. ' сек.')
        return false
    end

    local has_group_mention = false
    local my_admin = M.is_admin()
    local is_cross_server = (tostring(M.get_server()) == '900')

    if not my_admin and not is_cross_server then
        for _, mode in ipairs(MENTION_MODES) do
            if message:find('@' .. mode .. '%f[%W]') then
                has_group_mention = true
                break
            end
        end
        if has_group_mention then
            local elapsed = os.time() - (M.last_group_mention_at or 0)
            if elapsed < M.MENTION_COOLDOWN then
                local remaining = M.MENTION_COOLDOWN - elapsed
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                notice(string.format('Групповое упоминание: подождите %d:%02d', mins, secs))
                return false
            end
            M.last_group_mention_at = os.time()
        end
    elseif not my_admin and is_cross_server then
        for _, mode in ipairs(MENTION_MODES) do
            if message:find('@' .. mode .. '%f[%W]') then
                notice('Групповые упоминания запрещены в межпроектном чате', 'err')
                return false
            end
        end
    end
    
    M.last_send_at = os.time()
    local function attempt(n)
        http('POST', '/messages', { nick = nick, hwid = M.hwid, server = M.get_server(), home = M.get_home_server(), device = IS_MOBILE and 'MOBILE' or 'PC', text = message }, function(data)
            if type(data) == 'table' and type(data.message) == 'table' then
                add_message(data.message)
            elseif type(data) == 'table' and data.error == 'unauthorized' and n < 2 then
                M.heartbeat()
                table.insert(M.network_tasks, { due_at = os.time() + 2, action = function() attempt(n + 1) end })
            elseif type(data) == 'table' and (data.error == 'storage_unavailable' or data.error == 'database_unavailable') and n < 3 then
                table.insert(M.network_tasks, { due_at = os.time() + 3, action = function() attempt(n + 1) end })
            elseif type(data) == 'table' and (data.error == 'rate_limit' or data.error == 'too_many_messages' or data.error == 'flood' or data.error == 'too_fast') and n < 3 then
                M.rate_backoff()
                table.insert(M.network_tasks, { due_at = os.time() + 3, action = function() attempt(n + 1) end })
            elseif type(data) == 'table' and data.error then
                local err_msg = SERVER_ERRORS[tostring(data.error)]
                if err_msg then err_msg = su8(err_msg) else err_msg = ru_system_text(data.error) end
                notice(su8('Сервер отклонил сообщение: ') .. M.to_utf8(err_msg), 'err')
                restore_input(raw_in)
            end
        end, function(err) M.last_error = tostring(err or '') end, M.session_headers(), true)
    end
    attempt(1)
    return true
end

function M.start_network_thread()
    if M.network_thread_started then return end
    M.network_thread_started = true
    lua_thread.create(function()
        while M.running do
            local now = os.time()
            local idx = nil
            for i, t in ipairs(M.network_tasks) do
                if (t.due_at or 0) <= now then
                    if t.priority then idx = i; break end
                    if not idx then idx = i end
                end
            end
            if idx then
                local task = table.remove(M.network_tasks, idx)
                if type(task.action) == 'function' then
                    pcall(task.action)
                else
                    local result = sync_http(task.method, task.path, task.body, task.headers)
                    if result.type == 'ok' then
                        if type(task.on_ok) == 'function' then pcall(task.on_ok, result.data, result.response) end
                    else
                        if type(task.on_error) == 'function' then pcall(task.on_error, result.err) end
                    end
                end
            else
                wait(50)
            end
        end
    end)
end

function M.start_loop()
    if M.loop_started then return end
    M.loop_started = true
    M.start_network_thread()

    lua_thread.create(function()
        local last_heartbeat = 0
        local last_sync = os.time()
        local last_save = 0
        local last_users = 0
        local last_crowns = 0

        while M.running do
            wait(1000)
            local now = os.time()
            if M._avatar_dirty and now - (M.last_avatar_heartbeat or 0) >= 2 then
                M._avatar_dirty = false
                M.last_avatar_heartbeat = now
                M.heartbeat()
            end
            if M.chat_open then
                if now - last_save >= 30 then
                    M.save_config()
                    last_save = now
                end
                if now - last_sync >= M.SYNC_INTERVAL then
                    M.poll()
                    last_sync = now
                end
                if now - last_users >= M.USERS_INTERVAL then
                    M.fetch_user_directory(true)
                    M.fetch_users()
                    last_users = now
                end

            end
            if now - last_crowns >= M.CROWNS_INTERVAL then
                M.fetch_crowns()
                last_crowns = now
                end

            if now - last_heartbeat >= M.HEARTBEAT_INTERVAL then
                M.heartbeat()
                last_heartbeat = now
            end
        end
    end)
end


function M.start()
    if M.started or not M.enabled then return end
    M.started = true; M.running = true; M.session_started_at = os.time(); M.system_messages = {}; M.start_loop()
end

function M.set_disabled(value)
    M.disabled = value == true
    if M.disabled then M.stop()
    else
        M.enabled = M.base_url ~= ''
        if M.hwid == '' then M.hwid = make_hwid(); M.save_config() end
        M.start()
    end
end

function M.stop()
    M.running, M.started, M.loop_started, M.chat_open, M.network_thread_started = false, false, false, false, false
    M.users, M.all_users, M.messages, M.system_messages, M.online_any = {}, {}, {}, {}, {}
    M.network_tasks = {}
    M.polling, M.pending_initial_sync = false, false
    M.msg_reactions, M.pinned = {}, nil
    M._users_rev = (M._users_rev or 0) + 1
    M.save_config(true)
end

function M.admin_request(method, path, body, headers, on_ok, on_error)
    table.insert(M.network_tasks, { method = method, path = path, body = body, on_ok = on_ok, on_error = on_error, headers = headers, priority = true })
    return true
end

function M.is_admin_sender(nick)
    local value = tostring(nick or '')
    return M.admin_users[value] == true or (value ~= '' and value == M.get_nick() and M.is_admin())
end

function M.is_admin() return M.admin and type(M.admin.is_admin) == 'function' and M.admin.is_admin(M.hwid) end
function M.delete_message(id) if M.admin and type(M.admin.delete) == 'function' then return M.admin.delete(M, id) end end
function M.mute_user(nick, minutes) if M.admin and type(M.admin.mute) == 'function' then return M.admin.mute(M, nick, minutes) end end
function M.ban_user(nick, seconds) if M.admin and type(M.admin.ban) == 'function' then return M.admin.ban(M, nick, seconds) end end
function M.grant_admin(nick) if M.admin and type(M.admin.grant) == 'function' then return M.admin.grant(M, nick) end end
function M.unmute_user(nick) if M.admin and type(M.admin.unmute) == 'function' then return M.admin.unmute(M, nick) end end
function M.unban_user(nick) if M.admin and type(M.admin.unban) == 'function' then return M.admin.unban(M, nick) end end
function M.revoke_admin(nick) if M.admin and type(M.admin.revoke) == 'function' then return M.admin.revoke(M, nick) end end

function M.is_user(nick)
    if type(nick) ~= 'string' then return false end
    local clean = nick:gsub('^%s+', ''):gsub('%s+$', '')
    return M.crown_users[clean] == true or M.users[clean] == true or M.admin_users[clean] == true
end

local crown_set_cache, crown_set_rev = nil, -1
local function get_crown_set()
    local rev = M._users_rev or 0
    if crown_set_cache and crown_set_rev == rev then return crown_set_cache end
    local gold = M.chat_nick_color or '{FFD700}'
    local set = {}
    for nick in pairs(M.crown_users) do
        if type(nick) == 'string' and nick ~= '' then
            set[nick] = (M.admin_users[nick] == true) and '{FF4444}' or gold
        end
    end
    for nick in pairs(M.users) do
        if type(nick) == 'string' and nick ~= '' and set[nick] == nil then
            set[nick] = (M.admin_users[nick] == true) and '{FF4444}' or gold
        end
    end
    crown_set_cache, crown_set_rev = set, rev
    return set
end

local function chat_color_to_hex(color)
    local n = tonumber(color)
    if not n then return '{FFFFFF}' end
    n = math.floor(n)
    if n < 0 then n = n + 4294967296 end
    return string.format('{%06X}', math.floor(n / 256) % 16777216)
end

function M.decorate_chat(text, color)
    if not M.chat_crowns or type(text) ~= 'string' or text == '' then return text end
    local set = get_crown_set()
    if next(set) == nil then return text end

    local base = chat_color_to_hex(color)
    local out, pos, cur = {}, 1, base
    while true do
        local s, e, code = text:find('({%x+})', pos)
        local stop = s and (s - 1) or #text
        local seg = text:sub(pos, stop)
        if seg ~= '' then
            local restore = cur
            seg = seg:gsub('[%w_]+', function(tok)
                local c = set[tok]
                if c then return c .. tok .. restore end
                return nil
            end)
            out[#out + 1] = seg
        end
        if not s then break end
        out[#out + 1] = code
        cur = code
        pos = e + 1
    end
    return table.concat(out)
end

function M.toggle()
    if M.disabled then return end
    if not M.window then return end
    M.window[0] = not M.window[0]
    M.chat_open = M.window[0] == true
    if M.chat_open then
        M.start_loop()
        if M.session == '' then
            M.pending_initial_sync = true
            M.heartbeat()
        else
            M.poll(true)
        end
        M.fetch_users()
        M.fetch_crowns()
    else
        M.pending_initial_sync = false
    end
end
local function message_time(timestamp)
    local key = tostring(timestamp or '')
    M._time_cache = M._time_cache or {}
    local cached = M._time_cache[key]
    if cached then return cached end

    local result = ''
    local epoch = parse_iso_time(timestamp)
    if epoch ~= 0 then
        if os.date('%d.%m.%Y', epoch) == os.date('%d.%m.%Y') then
            result = os.date('%H:%M', epoch)
        else
            result = os.date('%d.%m %H:%M', epoch)
        end
    else
        local hours, minutes = key:match('[T ](%d%d):(%d%d)')
        if hours and minutes then result = hours .. ':' .. minutes end
    end

    M._time_cache[key] = result
    M._time_cache_n = (M._time_cache_n or 0) + 1
    if M._time_cache_n > 1000 then
        M._time_cache = {}
        M._time_cache_n = 0
    end
    return result
end


local function since_text(value)
    local epoch = parse_iso_time(value)
    if epoch ~= 0 then return os.date('%d.%m.%Y', epoch) end
    local year, month, day = tostring(value or ''):match('(%d%d%d%d)%-(%d%d)%-(%d%d)')
    if day then return day .. '.' .. month .. '.' .. year end
    return ''
end

function M.load_users() M.show_users = true; M.fetch_user_directory() end

function M.insert_mention(nick)
    if not M.input then M.input = imgui.new.char[4096]('') end
    local current = ffi.string(M.input, 4096):match("^[^%z]*") or ""
    local addition = (current ~= '' and not current:match('%s$') and ' ' or '') .. '@' .. M.to_utf8(nick) .. ' '
    local text = utf8_cut(current .. addition, 4000)
    ffi.fill(M.input, 4096, 0)
    ffi.copy(M.input, text)
    M.input_gen = (M.input_gen or 0) + 1
end

local function draw_text_strikethrough(imgui, text, color)
    local pos = imgui.GetCursorScreenPos()
    imgui.TextColored(color, "%s", text)
    local size = imgui.CalcTextSize(text)
    imgui.GetWindowDrawList():AddLine(imgui.ImVec2(pos.x, pos.y + size.y * 0.5), imgui.ImVec2(pos.x + size.x, pos.y + size.y * 0.5), imgui.GetColorU32Vec4(color))
end

function M.draw(player)
    local c = ctx()
    if M.disabled then if M.window then M.window[0] = false end; return end
    if not M.input or not M.window or not c.imgui then return end
    local imgui = c.imgui
    local fa = c.fa or {}
    local u8 = c.u8
    local function T(s) return (u8 and u8(s)) or s end
    local dpi = (c.settings and c.settings.ui and c.settings.ui.dpi) or 1.0
    local st = imgui.GetStyle()
    local light = ((c.settings or {}).ui or {}).theme == 2

    local server_name = ''
    local active_server = tostring(M.get_server())
    local active_label = (M.admin_lobby == '00') and 'Межпроектный' or active_server
    if M.admin_lobby == '00' then
        server_name = 'Межпроектный'
    elseif isSampAvailable() then
        pcall(function() server_name = getServerName(active_server) or '' end)
        if server_name == '' and not M.admin_lobby then pcall(function() server_name = server_name_safe() or '' end) end
    end
    local helper_online = 0
    for _, user in ipairs(M.all_users or {}) do if user.online then helper_online = helper_online + 1 end end
    local header_server = (M.admin_lobby == '00') and active_label or (server_name ~= '' and (server_name .. ' [' .. active_label .. ']') or active_label)

    local green  = light and imgui.ImVec4(0.02, 0.45, 0.18, 1) or imgui.ImVec4(0.35, 0.85, 0.45, 1)
    local red    = light and imgui.ImVec4(0.72, 0.08, 0.08, 1) or imgui.ImVec4(0.90, 0.35, 0.35, 1)
    local yellow = light and imgui.ImVec4(0.62, 0.42, 0.00, 1) or imgui.ImVec4(1.00, 0.85, 0.30, 1)
    local gold   = light and imgui.ImVec4(0.62, 0.42, 0.00, 1) or imgui.ImVec4(1.00, 0.78, 0.20, 1)
    local muted  = light and imgui.ImVec4(0.45, 0.45, 0.48, 1) or imgui.ImVec4(0.60, 0.62, 0.66, 1)
    local accent = green
    local hdr_bg   = light and imgui.ImVec4(0.02, 0.45, 0.18, 0.07) or imgui.ImVec4(0.35, 0.85, 0.45, 0.08)
    local line_col = light and imgui.ImVec4(0, 0, 0, 0.18) or imgui.ImVec4(1, 1, 1, 0.14)
    local panel    = light and imgui.ImVec4(0.94, 0.95, 0.96, 1) or imgui.ImVec4(0.12, 0.13, 0.15, 1)
    local input_bg = light and imgui.ImVec4(0.99, 0.99, 0.99, 1) or imgui.ImVec4(0.09, 0.10, 0.12, 1)
    local btn_bg     = light and imgui.ImVec4(0, 0, 0, 0.06) or imgui.ImVec4(1, 1, 1, 0.08)
    local btn_hover  = light and imgui.ImVec4(0, 0, 0, 0.12) or imgui.ImVec4(1, 1, 1, 0.16)
    local btn_active = light and imgui.ImVec4(0, 0, 0, 0.18) or imgui.ImVec4(1, 1, 1, 0.22)

    local win_w, win_h = 780 * dpi, 520 * dpi
    local users_w, send_w = 220 * dpi, 110 * dpi
    local frame_h = imgui.GetTextLineHeight() + st.FramePadding.y * 2
    local header_h = frame_h + 8 * dpi

    imgui.SetNextWindowSize(imgui.ImVec2(win_w, win_h), imgui.Cond.Always)
    imgui.Begin((fa.COMMENTS or '') .. T(' Arizona Helper Messenger'), M.window, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
    if isKeyJustPressed(27) and not IS_MOBILE and not sampIsChatInputActive() and not sampIsDialogActive() then
        local any_popup_open = imgui.IsPopupOpen('##ahm_server_pick') or imgui.IsPopupOpen('##msg_ctx') or imgui.IsPopupOpen('##emoji_popup') or imgui.IsPopupOpen('##mention_popup') or (M.admin_panel ~= nil)
        if not any_popup_open then M.window[0] = false M.chat_open = false imgui.End() return end
    end
    local dl = imgui.GetWindowDrawList()
    local wp, ws = imgui.GetWindowPos(), imgui.GetWindowSize()
    local region_w = imgui.GetWindowContentRegionMax().x - imgui.GetWindowContentRegionMin().x

    local hp = imgui.GetCursorScreenPos()
    pcall(function()
        dl:AddRectFilled(imgui.ImVec2(wp.x, hp.y - 2 * dpi), imgui.ImVec2(wp.x + ws.x, hp.y + header_h), imgui.GetColorU32Vec4(hdr_bg))
    end)
    imgui.AlignTextToFramePadding()
    if M.online then
        imgui.TextColored(green, (fa.CIRCLE_CHECK or '') .. T(' В сети'))
    else
        imgui.TextColored(red, (fa.CIRCLE_XMARK or fa.CIRCLE or '') .. T(' Не в сети'))
    end
    imgui.SameLine(0, 8 * dpi); imgui.TextColored(muted, '|')
    imgui.SameLine(0, 8 * dpi); imgui.Text((fa.SERVER or '') .. ' ' .. T(header_server))
    imgui.SameLine(0, 8 * dpi); imgui.TextColored(muted, '|')
    imgui.SameLine(0, 8 * dpi); imgui.Text((fa.USERS or '') .. ' ' .. tostring(helper_online))
    if M.my_banned then
        imgui.SameLine(0, 8 * dpi)
        local ban_text = (fa.BAN or '') .. ' ' .. T('Блокировка')
        if M.my_ban_until >= 9999999999 then ban_text = ban_text .. T(' (навсегда)')
        elseif M.my_ban_until > 0 then ban_text = ban_text .. ' (' .. M.format_remaining(M.my_ban_until - os.time()) .. ')' end
        imgui.TextColored(red, ban_text)
    elseif M.my_mute_until > os.time() then
        imgui.SameLine(0, 8 * dpi)
        imgui.TextColored(yellow, (fa.CLOCK or '') .. ' ' .. T('Мут: ') .. M.format_remaining(M.my_mute_until - os.time()))
    end

    local gear_w = 26 * dpi
    local list_btn_w = math.min(170 * dpi, region_w * 0.3)
    imgui.SameLine(0, 0)
    imgui.SetCursorPosX(imgui.GetWindowContentRegionMax().x - list_btn_w - gear_w - 6 * dpi)
    imgui.PushStyleColor(imgui.Col.Button, btn_bg)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, btn_hover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, btn_active)
    if imgui.Button((fa.USERS or '') .. T(' Список пользователей') .. '##ahm_users', imgui.ImVec2(list_btn_w, frame_h)) then
        if M.show_users then M.show_users = false else M.load_users() end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(T('Пользователи Arizona Helper онлайн')) end
    imgui.SameLine(0, 6 * dpi)
    if imgui.Button((fa.GEAR or 'S') .. '##ahm_server_pick', imgui.ImVec2(gear_w, frame_h)) then
        M.server_pick_open = true
        if M.is_admin() then
            local cur_num = (M.admin_lobby == '00') and '00' or tostring(M.get_server())
            local servers_list = {}
            if M.ctx and type(M.ctx.get_servers) == 'function' then
                local ok_l, list = pcall(M.ctx.get_servers)
                if ok_l and type(list) == 'table' then servers_list = list end
            end
            if not M.server_pick_combo_idx then M.server_pick_combo_idx = imgui.new.int(0) end
            for i, s in ipairs(servers_list) do if tostring(s.number) == cur_num then M.server_pick_combo_idx[0] = i - 1; break end end
        end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(T('Настройки подключения')) end
    imgui.PopStyleColor(3)
    pcall(function()
        dl:AddLine(imgui.ImVec2(wp.x, hp.y + header_h), imgui.ImVec2(wp.x + ws.x, hp.y + header_h), imgui.GetColorU32Vec4(line_col), 1)
    end)
    imgui.SetCursorPosY(hp.y - wp.y + header_h + 6 * dpi)

    if M.server_pick_open then M.server_pick_open = false; imgui.OpenPopup('##ahm_server_pick') end
    imgui.SetNextWindowPos(imgui.ImVec2(wp.x + ws.x * 0.5, wp.y + ws.y * 0.40), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    if imgui.BeginPopup('##ahm_server_pick') then
        local pdl = imgui.GetWindowDrawList()
        local pw = 320 * dpi
        local row_h = frame_h
        local function section(icon, title)
            imgui.Spacing()
            imgui.TextColored(muted, (icon ~= '' and (icon .. ' ') or '') .. title:upper())
            pcall(function()
                local mx = imgui.GetItemRectMax()
                local mn = imgui.GetItemRectMin()
                pdl:AddLine(imgui.ImVec2(mx.x + 6 * dpi, (mn.y + mx.y) * 0.5), imgui.ImVec2(mx.x + 6 * dpi + (pw - (mx.x - mn.x) - 6 * dpi), (mn.y + mx.y) * 0.5), imgui.GetColorU32Vec4(line_col), 1)
            end)
        end
        local function row_label(icon, label)
            imgui.AlignTextToFramePadding()
            imgui.Text((icon ~= '' and (icon .. ' ') or '') .. label)
        end
        local function right_x(w)
            imgui.SameLine(0, 0)
            imgui.SetCursorPosX(pw - w)
        end
        imgui.TextColored(yellow, (fa.GEAR or '') .. T(' Настройки мессенджера'))
        imgui.Separator()
        section(fa.GLOBE or '', T('Сервер'))
        row_label(fa.SERVER or '', T('Текущий:'))
        imgui.SameLine()
        imgui.TextColored(green, T(active_server .. (header_server ~= '' and (' (' .. header_server .. ')') or '')))
        if M.is_admin() then
            local servers_list = {}
            if M.ctx and type(M.ctx.get_servers) == 'function' then
                local ok_l, list = pcall(M.ctx.get_servers)
                if ok_l and type(list) == 'table' then servers_list = list end
            end
            if #servers_list > 0 then
                if not M.server_combo_strings or (M.server_combo_count or 0) ~= #servers_list then
                    M.server_combo_strings = {}
                    for i, s in ipairs(servers_list) do
                        M.server_combo_strings[i] = T(tostring(s.name or '?') .. ' [' .. tostring(s.number or '?') .. ']')
                    end
                    M.server_combo_items = imgui.new['const char*'][#servers_list](M.server_combo_strings)
                    M.server_combo_count = #servers_list
                    if not M.server_pick_combo_idx then M.server_pick_combo_idx = imgui.new.int(0) end
                end
                row_label(fa.RIGHT_LEFT or fa.GLOBE or '', T('Лобби:'))
                right_x(pw * 0.60)
                imgui.PushItemWidth(pw * 0.60)
                imgui.Combo('##ahm_server_combo', M.server_pick_combo_idx, M.server_combo_items, #servers_list)
                imgui.PopItemWidth()
                local selected = servers_list[M.server_pick_combo_idx[0] + 1]
                local bw2 = (pw - st.ItemSpacing.x) / 2
                if imgui.Button((fa.FOLDER_OPEN or '') .. ' ' .. T('Подключить'), imgui.ImVec2(bw2, row_h)) then
                    if selected then M.set_server(selected.number) end
                    imgui.CloseCurrentPopup()
                end
                imgui.SameLine()
                if imgui.Button((fa.ARROW_LEFT or fa.ROTATE_LEFT or '') .. ' ' .. T('Назад'), imgui.ImVec2(bw2, row_h)) then
                    if M.admin_lobby then M.return_home() end
                    imgui.CloseCurrentPopup()
                end
            end
        else
            if M.admin_lobby ~= '00' then
                if imgui.Button((fa.GLOBE or '') .. ' ' .. T('В межпроектный'), imgui.ImVec2(pw, row_h)) then M.set_server('00'); imgui.CloseCurrentPopup() end
            else
                if imgui.Button((fa.ROTATE_LEFT or '') .. ' ' .. T('На свой сервер'), imgui.ImVec2(pw, row_h)) then M.return_home(); imgui.CloseCurrentPopup() end
            end
        end
        section(fa.CLOCK_ROTATE_LEFT or fa.DOWNLOAD or '', T('История'))
        if not M.hide_system_cb then M.hide_system_cb = imgui.new.bool(M.hide_system or false) end
        row_label(fa.BELL_SLASH or fa.EYE_SLASH or '', T('Скрывать системные'))
        right_x(row_h)
        if imgui.Checkbox('##hide_sys', M.hide_system_cb) then M.hide_system = M.hide_system_cb[0]; M.save_config() end
        if M.is_admin() then
            local bw3 = (pw - st.ItemSpacing.x) / 2
            if imgui.Button((fa.TRASH_CAN or '') .. ' ' .. T('Очистить'), imgui.ImVec2(bw3, row_h)) then M.clear_history(); imgui.CloseCurrentPopup() end
            imgui.SameLine()
            if imgui.Button((fa.DOWNLOAD or '') .. ' ' .. T('Загрузить всё'), imgui.ImVec2(bw3, row_h)) then
                if M.admin and type(M.admin.load_history) == 'function' then M.admin.load_history(M) end
                imgui.CloseCurrentPopup()
            end
        end
        section(fa.PALETTE or '', T('Внешний вид'))
        if not M.chat_crowns_cb then M.chat_crowns_cb = imgui.new.bool(M.chat_crowns ~= false) end
        M.chat_crowns_cb[0] = (M.chat_crowns ~= false)
        row_label(fa.PALETTE or fa.CROWN or '', T('Золотые ники в чате'))
        right_x(row_h)
        if imgui.Checkbox('##chat_crowns', M.chat_crowns_cb) then
            M.chat_crowns = M.chat_crowns_cb[0]
            M.save_config(true)
        end
        if imgui.IsItemHovered() then imgui.SetTooltip(T('Помечает ники пользователей хелпера в игровом чате')) end
        if not M.show_avatars_cb then M.show_avatars_cb = imgui.new.bool(M.show_avatars ~= false) end
        row_label(fa.COMMENTS or '', T('Пузыри и аватары'))
        right_x(row_h)
        if imgui.Checkbox('##av_on', M.show_avatars_cb) then M.show_avatars = M.show_avatars_cb[0]; M.save_config() end
        if M.show_avatars ~= false then
            if not M.avatar_mode_buf then M.avatar_mode_buf = imgui.new.int(0) end
            if not M.avatar_mode_strings then M.avatar_mode_strings = { T('Буквы'), T('Иконка') } end
            if not M.avatar_mode_items then M.avatar_mode_items = imgui.new['const char*'][2](M.avatar_mode_strings) end
            M.avatar_mode_buf[0] = (M.avatar_mode == 'icon') and 1 or 0
            row_label(fa.USER or '', T('Свой аватар'))
            right_x(pw * 0.45)
            imgui.PushItemWidth(pw * 0.45)
            if imgui.Combo('##avmode', M.avatar_mode_buf, M.avatar_mode_items, 2) then
                M.avatar_mode = (M.avatar_mode_buf[0] == 1) and 'icon' or 'letters'
                M.save_config()
            end
            imgui.PopItemWidth()
            if M.avatar_mode == 'icon' then
                local g0 = imgui.GetCursorScreenPos()
                local cell = 26 * dpi
                local gapx = 2 * dpi
                local grid_w = 5 * cell + 4 * gapx
                local grid_h = 2 * cell + gapx
                for i, key in ipairs(AVATAR_ICONS) do
                    if (i - 1) % 5 ~= 0 then imgui.SameLine(0, gapx) end
                    local sel = (M.avatar_icon == key)
                    if sel then imgui.PushStyleColor(imgui.Col.Button, accent) end
                    if imgui.Button((fa[key] or '?') .. '##av_' .. key, imgui.ImVec2(cell, cell)) then
                        M.avatar_icon = key
                        M.save_config()
                    end
                    if sel then imgui.PopStyleColor() end
                end
                local pv_d = grid_h
                local free_w = pw - grid_w
                local pv_x = g0.x + grid_w + math.max(6 * dpi, (free_w - pv_d) * 0.5)
                local pv_y = g0.y
                local pv_bg = M.avatar_bg and imgui.ImVec4(M.avatar_bg[1] / 255, M.avatar_bg[2] / 255, M.avatar_bg[3] / 255, 1) or accent
                local pv_fg = M.avatar_fg and imgui.ImVec4(M.avatar_fg[1] / 255, M.avatar_fg[2] / 255, M.avatar_fg[3] / 255, 1) or imgui.ImVec4(1, 1, 1, 1)
                local pv_g = fa[M.avatar_icon or ''] or '?'
                pcall(function()
                    pdl:AddCircleFilled(imgui.ImVec2(pv_x + pv_d * 0.5, pv_y + pv_d * 0.5), pv_d * 0.5, imgui.GetColorU32Vec4(pv_bg), 24)
                end)
                local pv_gw = imgui.CalcTextSize(pv_g).x
                draw_glyph_outlined(imgui, pdl, pv_x + pv_d * 0.5 - pv_gw * 0.5, pv_y + pv_d * 0.5 - imgui.GetTextLineHeight() * 0.5, pv_g, imgui.GetColorU32Vec4(pv_fg), math.min(tonumber(M.avatar_outline) or 0, 2))
                local cap = T('Пример: так ваш аватар выглядит в чате')
                imgui.SetCursorScreenPos(imgui.ImVec2(g0.x + (pw - imgui.CalcTextSize(cap).x) * 0.5, g0.y + math.max(grid_h, pv_d) + 4 * dpi))
                imgui.TextColored(muted, cap)
            end
            M.avatar_bg_buf = M.avatar_bg_buf or imgui.new.float[3](M.avatar_bg and M.avatar_bg[1] / 255 or 0.13, M.avatar_bg and M.avatar_bg[2] / 255 or 0.38, M.avatar_bg and M.avatar_bg[3] / 255 or 0.22)
            M.avatar_fg_buf = M.avatar_fg_buf or imgui.new.float[3](M.avatar_fg and M.avatar_fg[1] / 255 or 1, M.avatar_fg and M.avatar_fg[2] / 255 or 1, M.avatar_fg and M.avatar_fg[3] / 255 or 1)
            row_label(fa.FILL_DRIP or '', T('Фон аватара'))
            right_x(row_h)
            if imgui.ColorEdit3('##avbg', M.avatar_bg_buf, imgui.ColorEditFlags.NoInputs) then
                M.avatar_bg = { math.floor(M.avatar_bg_buf[0] * 255 + 0.5), math.floor(M.avatar_bg_buf[1] * 255 + 0.5), math.floor(M.avatar_bg_buf[2] * 255 + 0.5) }
                M.save_config()
            end
            row_label(fa.FONT or '', T('Цвет символа'))
            right_x(row_h)
            if imgui.ColorEdit3('##avfg', M.avatar_fg_buf, imgui.ColorEditFlags.NoInputs) then
                M.avatar_fg = { math.floor(M.avatar_fg_buf[0] * 255 + 0.5), math.floor(M.avatar_fg_buf[1] * 255 + 0.5), math.floor(M.avatar_fg_buf[2] * 255 + 0.5) }
                M.save_config()
            end
            if not M.avatar_outline_buf then M.avatar_outline_buf = imgui.new.int(M.avatar_outline or 1) end
            row_label(fa.PEN or '', T('Обводка символа'))
            right_x(pw * 0.45)
            imgui.PushItemWidth(pw * 0.45)
            if imgui.SliderInt('##avol', M.avatar_outline_buf, 0, 3) then
                M.avatar_outline = M.avatar_outline_buf[0]
                M.save_config()
            end
            imgui.PopItemWidth()
        end
        imgui.EndPopup()
    end

    local input_line_h = imgui.GetTextLineHeight() + st.FramePadding.y * 2
    local current_text = ffi.string(M.input, 4096):match("^[^%z]*") or ""
    local nl = 1
    for _ in current_text:gmatch("\n") do nl = nl + 1 end
    local vis_lines = math.min(nl, M.MAX_INPUT_LINES or 2)
    local dynamic_input_h = math.min(input_line_h + (vis_lines - 1) * imgui.GetTextLineHeight(), ws.y * 0.35)
    local btn_size = dynamic_input_h
    local input_w = region_w - send_w - btn_size * 2 - st.ItemSpacing.x * 3
    local body_h = math.max(120 * dpi, imgui.GetContentRegionAvail().y - dynamic_input_h - st.ItemSpacing.y * 2)
    local hist_w = M.show_users and (region_w - users_w - st.ItemSpacing.x) or region_w

    if M.pinned then
        local pin_h = frame_h + 2 * dpi
        body_h = body_h - pin_h - st.ItemSpacing.y
        imgui.PushStyleColor(imgui.Col.ChildBg, light and imgui.ImVec4(0.98, 0.96, 0.86, 1) or imgui.ImVec4(0.16, 0.15, 0.10, 1))
        if imgui.BeginChild('##pinned_bar', imgui.ImVec2(region_w, pin_h), true, imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse) then
            imgui.AlignTextToFramePadding()
            imgui.TextColored(yellow, (fa.THUMBTACK or fa.STAR or '') .. T(' Закреплено:'))
            imgui.SameLine(0, 4 * dpi)
            local ptxt = M.to_utf8(M.pinned.sender) .. ': ' .. M.pinned.text
            if #ptxt > 90 then ptxt = ptxt:sub(1, 90):gsub('[\128-\191]+$', '') .. '...' end
            imgui.Text(ptxt)
            if M.is_admin() then
                local un_s = frame_h - 2 * dpi
                imgui.SameLine(0, 0)
                imgui.SetCursorPosX(imgui.GetWindowContentRegionMax().x - un_s)
                if imgui.Button((fa.CIRCLE_XMARK or 'X') .. '##unpin', imgui.ImVec2(un_s, un_s)) then
                    M.set_pin(M.pinned.id, false)
                    M.pinned = nil
                end
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()
    end

    imgui.PushStyleColor(imgui.Col.ChildBg, panel)
    if imgui.BeginChild('##messenger_history', imgui.ImVec2(hist_w, body_h), true) then
        local dl_child = imgui.GetWindowDrawList()
        M.hover_msg_id = nil
        local cmin, cmax = imgui.GetWindowContentRegionMin().x, imgui.GetWindowContentRegionMax().x
        local cw = cmax - cmin
        if M.my_banned then
            local avail = imgui.GetContentRegionAvail()
            imgui.SetCursorPosY(imgui.GetCursorPosY() + avail.y * 0.35)
            local text1 = (fa.BAN or '') .. ' ' .. T('Вы не можете читать сообщения')
            local text2 = T('Доступ к истории мессенджера закрыт администратором.')
            if M.my_ban_until >= 9999999999 then text2 = text2 .. '\n' .. T('Блокировка: навсегда')
            elseif M.my_ban_until > 0 then text2 = text2 .. '\n' .. T('Осталось: ') .. M.format_remaining(M.my_ban_until - os.time()) end
            imgui.SetCursorPosX(cmin + (cw - imgui.CalcTextSize(text1).x) * 0.5); imgui.TextColored(red, text1)
            imgui.SetCursorPosX(cmin + (cw - imgui.CalcTextSize(text2).x) * 0.5); imgui.TextColored(muted, text2)
        else
            local my_nick = M.get_nick()
            local timeline = {}
            for _, m in ipairs(M.messages) do m.is_system = false; timeline[#timeline + 1] = m end
            if not M.hide_system then for _, s in ipairs(M.system_messages) do s.is_system = true; timeline[#timeline + 1] = s end end
            table.sort(timeline, function(a, b)
                if a.timestamp and b.timestamp and a.timestamp ~= '' and b.timestamp ~= '' then
                    if a.timestamp == b.timestamp then return (a.id or 0) < (b.id or 0) end
                    return a.timestamp < b.timestamp
                end
                return (a.id or 0) < (b.id or 0)
            end)

            if #timeline == 0 then
                local hint = T('Сообщений пока нет - напишите первым!')
                imgui.SetCursorPosY(imgui.GetCursorPosY() + body_h * 0.35)
                imgui.SetCursorPosX(cmin + (cw - imgui.CalcTextSize(hint).x) * 0.5)
                imgui.TextColored(muted, hint)
            end

            local line_h = imgui.GetTextLineHeight()
            local pad = 8 * dpi
            local av_d = 26 * dpi
            local av_gap = 6 * dpi
            local max_bubble_w = cw * 0.72
            local max_inner_w = max_bubble_w - pad * 2
            local rounding = 12 * dpi
            local bubble_in_col   = light and imgui.ImVec4(0.87, 0.89, 0.92, 1) or imgui.ImVec4(0.17, 0.18, 0.22, 1)
            local bubble_out_col  = light and imgui.ImVec4(0.72, 0.90, 0.78, 1) or imgui.ImVec4(0.13, 0.38, 0.22, 1)
            local bubble_ment_col = light and imgui.ImVec4(0.98, 0.93, 0.75, 1) or imgui.ImVec4(0.40, 0.33, 0.10, 1)
            local text_on_in  = light and imgui.ImVec4(0.10, 0.10, 0.12, 1) or imgui.ImVec4(0.92, 0.93, 0.95, 1)
            local text_on_out = light and imgui.ImVec4(0.05, 0.20, 0.10, 1) or imgui.ImVec4(0.93, 0.98, 0.93, 1)
            local warn_icon = fa.TRIANGLE_EXCLAMATION or fa.CIRCLE_EXCLAMATION or '!'

            local function wrap_pixels(text, max_w)
                local cache = M._wrap_cache or {}
                local key = tostring(text) .. '|' .. tostring(math.floor(max_w))
                local cached = cache[key]
                if cached then return cached end
                local out = {}
                for raw_line in tostring(text):gmatch('[^\n]+') do
                    local cur = ''
                    for word in raw_line:gmatch('%S+') do
                        local test = (cur == '') and word or (cur .. ' ' .. word)
                        if imgui.CalcTextSize(test).x <= max_w then
                            cur = test
                        else
                            if cur ~= '' then out[#out + 1] = cur end
                            while #word > 1 and imgui.CalcTextSize(word).x > max_w do
                                local cut = #word
                                while cut > 1 and imgui.CalcTextSize(word:sub(1, cut)).x > max_w do cut = cut - 1 end
                                out[#out + 1] = word:sub(1, cut)
                                word = word:sub(cut + 1)
                            end
                            cur = word
                        end
                    end
                    out[#out + 1] = cur
                end
                if #out == 0 then out[1] = '' end
                cache[key] = out
                M._wrap_cache_n = (M._wrap_cache_n or 0) + 1
                if M._wrap_cache_n > 800 then
                    cache = {}
                    M._wrap_cache_n = 0
                end
                M._wrap_cache = cache
                return out
            end

            local function initials_of(nick)
                M._initials_cache = M._initials_cache or {}
                local initials_key = tostring(nick or '')
                local cached = M._initials_cache[initials_key]
                if cached then return cached end
                local clean = tostring(nick or ''):gsub('{%x%x%x%x%x%x}', '')
                local first = clean:match('^[%a%d_]+') or clean
                first = first:sub(1, 2)
                if type(string.rupper) == 'function' then first = first:rupper() else first = first:upper() end
                local result = M.to_utf8(first)
                if M._initials_cache then M._initials_cache[initials_key] = result end
                return result
            end

            for _, message in ipairs(timeline) do
                if message.deleted or message.is_system then
                    local txt = message.deleted and ((fa.TRASH_CAN or '') .. ' ' .. T('Сообщение удалено'))
                        or (warn_icon .. ' ' .. message.text)
                    imgui.SetCursorPosX(cmin + (cw - imgui.CalcTextSize(txt).x) * 0.5)
                    imgui.TextColored(muted, txt)
                    imgui.Spacing()
                else
                    local sender = tostring(message.sender or '')
                    local is_mine = (sender == my_nick and my_nick ~= '')
                    local any_mention = message.is_mentioned == true
                    local time = message_time(message.timestamp)
                    local is_sender_admin = M.admin_users[sender] == true or (is_mine and M.is_admin())
                    local is_banned = M.banned_users[sender] == true
                    local sender_col = is_sender_admin and gold or (is_banned and red or (((M.users[sender] or M.online_any[sender]) and green) or muted))
                    local server_tag = server_tag_for(sender, (message.home ~= '' and message.home) or nil)
                    local name_line = (is_sender_admin and ((fa.STAR or '') .. ' ') or '') .. M.to_utf8(sender) .. server_tag
                    local time_w = (time ~= '') and imgui.CalcTextSize(time).x or 0
                    local reacts = (M.msg_reactions or {})[message.id]
                    local react_keys = {}
                    if reacts then
                        for k, v in pairs(reacts) do if v.n > 0 then react_keys[#react_keys + 1] = k end end
                        table.sort(react_keys)
                    end
                    local has_reacts = #react_keys > 0

                    if M.show_avatars ~= false then
                        local body_lines = wrap_pixels(message.text, max_inner_w)
                        local show_name = not is_mine
                        local inner_w = time_w
                        if show_name then inner_w = math.max(inner_w, imgui.CalcTextSize(name_line).x) end
                        for _, ln in ipairs(body_lines) do inner_w = math.max(inner_w, imgui.CalcTextSize(ln).x) end
                        local bubble_w = math.min(max_bubble_w, inner_w + pad * 2)
                        local total_lines = #body_lines + (show_name and 1 or 0) + ((time ~= '') and 1 or 0)
                        local bubble_h = total_lines * line_h + pad * 2
                        local cwp = imgui.GetWindowPos()
                        local y0 = imgui.GetCursorScreenPos().y
                        local bx, ax
                        if is_mine then
                            bx = cmax - av_d - av_gap - bubble_w
                            ax = cmax - av_d * 0.5
                        else
                            bx = cmin + av_d + av_gap
                            ax = cmin + av_d * 0.5
                        end
                        local av_bg, av_fg, av_glyph, av_out
                        if is_mine then
                            local mm, mi, mb, mf, mo = M.my_avatar()
                            av_bg = mb and imgui.ImVec4(mb[1] / 255, mb[2] / 255, mb[3] / 255, 1) or accent
                            av_fg = mf and imgui.ImVec4(mf[1] / 255, mf[2] / 255, mf[3] / 255, 1) or imgui.ImVec4(1, 1, 1, 1)
                            av_glyph = (mm == 'icon' and (fa[mi] or nil)) or initials_of(sender)
                            av_out = mo
                        else
                            local am, ai, ab, af, ao = resolve_other_avatar(sender, message)
                            av_bg = ab and imgui.ImVec4(ab[1] / 255, ab[2] / 255, ab[3] / 255, 1) or sender_col
                            av_fg = af and imgui.ImVec4(af[1] / 255, af[2] / 255, af[3] / 255, 1) or imgui.ImVec4(1, 1, 1, 1)
                            av_glyph = (am == 'icon' and (fa[ai] or nil)) or initials_of(sender)
                            av_out = ao
                        end
                        local av_cx = cwp.x + ax
                        local av_cy = y0 + bubble_h * 0.5
                        pcall(function()
                            dl_child:AddCircleFilled(imgui.ImVec2(av_cx, av_cy), av_d * 0.5, imgui.GetColorU32Vec4(av_bg), 20)
                        end)
                        local gw = imgui.CalcTextSize(av_glyph).x
                        draw_glyph_outlined(imgui, dl_child, av_cx - gw * 0.5, av_cy - line_h * 0.5, av_glyph, imgui.GetColorU32Vec4(av_fg), av_out)
                        if is_mine then
                            imgui.SetCursorScreenPos(imgui.ImVec2(cwp.x + ax - av_d * 0.5, y0 + bubble_h * 0.5 - av_d * 0.5))
                            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.10))
                            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.18))
                            if imgui.Button('##self_av_' .. tostring(message.id), imgui.ImVec2(av_d, av_d)) then
                                if M.is_admin() then
                                    M.admin_panel = { id = message.id, sender = sender, text = message.text, time = time }
                                    M.admin_confirm = nil
                                    M.admin_panel_want_open = true
                                end
                            end
                            imgui.PopStyleColor(3)
                        end
                        pcall(function()
                            dl_child:AddRectFilled(imgui.ImVec2(cwp.x + bx, y0), imgui.ImVec2(cwp.x + bx + bubble_w, y0 + bubble_h),
                                imgui.GetColorU32Vec4(any_mention and bubble_ment_col or (is_mine and bubble_out_col or bubble_in_col)), rounding)
                        end)
                        local ty = y0 + pad
                        if show_name then
                            imgui.SetCursorScreenPos(imgui.ImVec2(cwp.x + bx + pad, ty))
                            if is_banned then
                                draw_text_strikethrough(imgui, name_line, sender_col)
                            else
                                imgui.TextColored(sender_col, name_line)
                            end
                            if imgui.IsItemClicked() and M.is_admin() then
                                M.admin_panel = { id = message.id, sender = sender, text = message.text, time = time }
                                M.admin_confirm = nil
                                M.admin_panel_want_open = true
                            end
                            ty = ty + line_h
                        end
                        local tcol = is_mine and text_on_out or text_on_in
                        for _, ln in ipairs(body_lines) do
                            imgui.SetCursorScreenPos(imgui.ImVec2(cwp.x + bx + pad, ty))
                            imgui.TextColored(tcol, ln)
                            ty = ty + line_h
                        end
                        if time ~= '' then
                            local time_x = cwp.x + bx + bubble_w - pad - time_w
                            imgui.SetCursorScreenPos(imgui.ImVec2(time_x, ty))
                            imgui.TextColored(is_mine and text_on_out or muted, time)
                        end
                        if imgui.IsItemHovered() then M.hover_msg_id = message.id end
                        if has_reacts then
                            local pills = {}
                            local total_w = 0
                            for _, rk in ipairs(react_keys) do
                                local rv = reacts[rk]
                                local label = (fa[rk] or '?') .. ' ' .. tostring(rv.n)
                                local pill_w = imgui.CalcTextSize(label).x + 12 * dpi
                                pills[#pills + 1] = { rk = rk, rv = rv, label = label, w = pill_w }
                                total_w = total_w + pill_w + 4 * dpi
                            end
                            total_w = total_w - 4 * dpi
                            local pill_h = line_h + 2 * dpi
                            local ry = y0 + bubble_h + 1 * dpi
                            local rx = is_mine and (cwp.x + bx + bubble_w - total_w) or (cwp.x + bx)
                            for _, p in ipairs(pills) do
                                imgui.SetCursorScreenPos(imgui.ImVec2(rx, ry))
                                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.10))
                                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.16))
                                if imgui.Button('##react_' .. tostring(message.id) .. '_' .. p.rk, imgui.ImVec2(p.w, pill_h)) then
                                    M.toggle_reaction(message.id, p.rk, message.server)
                                end
                                imgui.PopStyleColor(3)
                                pcall(function()
                                    dl_child:AddRectFilled(imgui.ImVec2(rx, ry), imgui.ImVec2(rx + p.w, ry + pill_h),
                                        p.rv.mine and imgui.GetColorU32Vec4(accent) or imgui.GetColorU32Vec4(light and imgui.ImVec4(0, 0, 0, 0.10) or imgui.ImVec4(1, 1, 1, 0.10)), pill_h * 0.5)
                                    dl_child:AddText(imgui.ImVec2(rx + 6 * dpi, ry + (pill_h - line_h) * 0.5),
                                        imgui.GetColorU32Vec4(p.rv.mine and imgui.ImVec4(1, 1, 1, 1) or (is_mine and text_on_out or text_on_in)), p.label)
                                end)
                                rx = rx + p.w + 4 * dpi
                            end
                        end
                        local row_extra = has_reacts and (line_h + 4 * dpi) or 0
                        imgui.SetCursorScreenPos(imgui.ImVec2(cwp.x + cmin, y0 + bubble_h + row_extra + 6 * dpi))
                    else
                        if is_banned then
                            draw_text_strikethrough(imgui, name_line, sender_col)
                        else
                            imgui.TextColored(sender_col, name_line)
                        end
                        if imgui.IsItemClicked() and M.is_admin() then
                            M.admin_panel = { id = message.id, sender = sender, text = message.text, time = time }
                            M.admin_confirm = nil
                            M.admin_panel_want_open = true
                        end
                        imgui.PushTextWrapPos(cmax - time_w - 2 * st.ItemSpacing.x)
                        if any_mention then imgui.PushStyleColor(imgui.Col.Text, yellow) end
                        imgui.TextWrapped("%s", message.text)
                        if imgui.IsItemHovered() then M.hover_msg_id = message.id end
                        if any_mention then imgui.PopStyleColor() end
                        imgui.PopTextWrapPos()
                        if time ~= '' then
                            local tx = cmax - time_w
                            if tx > imgui.GetCursorPosX() then imgui.SameLine() end
                            imgui.SetCursorPosX(tx)
                            imgui.TextColored(muted, time)
                        end
                        if has_reacts then
                            for i, rk in ipairs(react_keys) do
                                local rv = reacts[rk]
                                if i > 1 then imgui.SameLine(0, 4 * dpi) end
                                if rv.mine then
                                    imgui.PushStyleColor(imgui.Col.Button, accent)
                                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
                                end
                                if imgui.SmallButton((fa[rk] or '?') .. ' ' .. rv.n .. '##cr_' .. tostring(message.id) .. '_' .. rk) then
                                    M.toggle_reaction(message.id, rk, message.server)
                                end
                                if rv.mine then imgui.PopStyleColor(2) end
                            end
                        end
                        imgui.Spacing()
                    end
                end
            end
            if M.auto_scroll then imgui.SetScrollHereY(1.0); M.auto_scroll = false end
        end
    end
    imgui.EndChild()
    imgui.PopStyleColor()

    local rmb = false
    pcall(function() rmb = imgui.IsMouseReleased(1) end)
    if rmb and M.hover_msg_id then
        M.msg_ctx_id = M.hover_msg_id
        local ok, io = pcall(imgui.GetIO)
        if ok and io and io.MousePos then
            M.msg_ctx_pos = { x = io.MousePos.x, y = io.MousePos.y }
        else
            M.msg_ctx_pos = { x = wp.x + ws.x * 0.5, y = wp.y + ws.y * 0.5 }
        end
        imgui.OpenPopup('##msg_ctx')
    end
    local ctx_open = imgui.BeginPopup('##msg_ctx')
    if ctx_open then
        if M.msg_ctx_pos and type(imgui.SetWindowPos) == 'function' then
            pcall(imgui.SetWindowPos, imgui.ImVec2(M.msg_ctx_pos.x, M.msg_ctx_pos.y), imgui.Cond.Always)
        end
        local mid = M.msg_ctx_id
        local mmsg = nil
        for _, mm in ipairs(M.messages) do
            if mm.id == mid then mmsg = mm break end
        end
        if mmsg then
            imgui.TextDisabled(T('Сообщение от ') .. M.to_utf8(mmsg.sender) .. ' · ' .. message_time(mmsg.timestamp))
            imgui.Separator()
            imgui.TextDisabled(T('Реакция:'))
            for i, key in ipairs(REACT_ICONS) do
                if i > 1 then imgui.SameLine(0, 2 * dpi) end
                if imgui.SmallButton((fa[key] or '?') .. '##rct_' .. key) then
                    M.toggle_reaction(mid, key, mmsg.server)
                    imgui.CloseCurrentPopup()
                end
            end
            imgui.Separator()
            if imgui.SmallButton((fa.COPY or '') .. ' ' .. T('Скопировать текст')) then
                pcall(setClipboardText, to_clip(mmsg.text))
                imgui.CloseCurrentPopup()
            end
            if imgui.SmallButton((fa.FLAG or fa.TRIANGLE_EXCLAMATION or '') .. ' ' .. T('Пожаловаться')) then
                M.report_message(mmsg)
                imgui.CloseCurrentPopup()
            end
            if M.is_admin() then
                if imgui.SmallButton((fa.THUMBTACK or fa.STAR or '') .. ' ' .. T((M.pinned and M.pinned.id == mid) and 'Открепить' or 'Закрепить')) then
                    if M.pinned and M.pinned.id == mid then M.set_pin(mid, false)
                    else M.set_pin(mid, true) end
                    imgui.CloseCurrentPopup()
                end
                if imgui.SmallButton((fa.USER_SHIELD or fa.GEAR or '') .. ' ' .. T('Админ-панель')) then
                    M.admin_panel = { id = mmsg.id, sender = mmsg.sender, text = mmsg.text, time = message_time(mmsg.timestamp) }
                    M.admin_confirm = nil
                    M.admin_panel_want_open = true
                    imgui.CloseCurrentPopup()
                end
            end
        end
        imgui.EndPopup()
    else
        M.msg_ctx_pos = nil
    end

    if M.show_users then
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.ChildBg, panel)
        if imgui.BeginChild('##messenger_user_list', imgui.ImVec2(users_w, body_h), true) then
            local ucmin, ucmax = imgui.GetWindowContentRegionMin().x, imgui.GetWindowContentRegionMax().x
            imgui.AlignTextToFramePadding()
            imgui.TextColored(green, fa.USERS or '')
            imgui.SameLine(0, 4 * dpi)
            imgui.Text(T('Онлайн: '))
            imgui.SameLine(0, 2 * dpi)
            imgui.TextColored(green, tostring(helper_online))
            imgui.SameLine(0, 2 * dpi)
            imgui.TextColored(muted, '/ ' .. tostring(#(M.all_users or {})))
            local hide_label = T('Скрыть')
            local hide_w = imgui.CalcTextSize(hide_label).x + 2 * st.FramePadding.x
            imgui.SameLine(0, 0)
            imgui.SetCursorPosX(ucmax - hide_w)
            if imgui.SmallButton(hide_label .. '##hide_users') then M.show_users = false end
            imgui.Separator()
            if #(M.all_users or {}) == 0 then
                imgui.TextColored(muted, T('Загрузка списка...'))
                if M.last_error ~= '' then
                    imgui.TextColored(red, T('Ошибка: '))
                    imgui.SameLine()
                    imgui.TextDisabled(tostring(M.last_error))
                end
            end
            local at_w = imgui.CalcTextSize('@').x + 2 * st.FramePadding.x
            for _, user in ipairs(M.all_users or {}) do
                local nick = tostring(user.nick or '')
                local since = since_text(user.first_seen)
                local is_admin_user = user.admin == true or M.admin_users[nick] == true
                local is_online = user.online == true
                local is_banned = M.banned_users[nick] == true
                local col = is_admin_user and gold or (is_banned and red or (is_online and green or red))
                imgui.TextColored(is_online and green or red, fa.CIRCLE or fa.CIRCLE_CHECK or '*')
                imgui.SameLine(0, 4 * dpi)
                local icon = is_admin_user and ((fa.STAR or '') .. ' ') or ''
                local text = icon .. M.to_utf8(nick) .. server_tag_for(nick)
                if is_banned then
                    draw_text_strikethrough(imgui, text, col)
                else
                    imgui.TextColored(col, text)
                end
                if imgui.IsItemClicked() and M.is_admin() then
                    M.admin_panel = { id = nil, sender = nick, text = '', time = '', since = since }
                    M.admin_confirm = nil
                    M.admin_panel_want_open = true
                end
                if imgui.IsItemHovered() then
                    local lines = {}
                    if since ~= '' then lines[#lines + 1] = T('С хелпером с ') .. since end
                    local dev = M.user_devices[nick] or user.device or ''
                    if dev ~= '' then
                        local dev_label = (dev == 'MOBILE') and T('мобильное устройство') or ((dev == 'PC') and T('ПК') or dev)
                        lines[#lines + 1] = T('Устройство: ') .. dev_label
                    end
                    local frac = M.user_fractions[nick] or user.fraction or ''
                    if frac ~= '' then lines[#lines + 1] = T('Фракция: ') .. frac end
                    if #lines > 0 then imgui.SetTooltip(table.concat(lines, '\n')) end
                end
                imgui.SameLine(0, 0)
                imgui.SetCursorPosX(ucmax - at_w)
                if imgui.SmallButton('@##mention_' .. nick) then M.insert_mention(nick) end
                if imgui.IsItemHovered() then imgui.SetTooltip(T('Упомянуть')) end
            end
        end
        imgui.EndChild()
        imgui.PopStyleColor()
    end

    if M.admin and type(M.admin.draw_panel) == 'function' then
        M.admin.draw_panel({ M = M, imgui = imgui, fa = fa, u8 = u8, dpi = dpi, st = st, yellow = yellow, gold = gold, red = red })
    end

    local now_ts = os.time()
    local ni = 1
    while ni <= #M.notices do
        if M.notices[ni].until_ts <= now_ts then table.remove(M.notices, ni) else ni = ni + 1 end
    end
    if #M.notices > 0 then
        local nline = imgui.GetTextLineHeight()
        local nx_right = wp.x + ws.x - st.WindowPadding.x - 6 * dpi
        local ny = wp.y + ws.y - dynamic_input_h - st.ItemSpacing.y * 2 - 6 * dpi
        for i = #M.notices, 1, -1 do
            local n = M.notices[i]
            local ntxt = (fa.TRIANGLE_EXCLAMATION or '!') .. ' ' .. n.text
            local nw = imgui.CalcTextSize(ntxt).x
            ny = ny - nline - 6 * dpi
            local col = n.kind == 'err' and red or yellow
            local bg = light and imgui.ImVec4(0.15, 0.15, 0.15, 0.88) or imgui.ImVec4(0.04, 0.04, 0.04, 0.88)
            pcall(function()
                dl:AddRectFilled(imgui.ImVec2(nx_right - nw - 10 * dpi, ny - 4 * dpi),
                    imgui.ImVec2(nx_right + 4 * dpi, ny + nline + 4 * dpi),
                    imgui.GetColorU32Vec4(bg), 6 * dpi)
                dl:AddText(imgui.ImVec2(nx_right - nw - 4 * dpi, ny), imgui.GetColorU32Vec4(col), ntxt)
            end)
        end
    end

    local old_scroll_size = st.ScrollbarSize
    st.ScrollbarSize = 0
    imgui.PushStyleColor(imgui.Col.FrameBg, input_bg)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, input_bg)
    imgui.PushStyleColor(imgui.Col.FrameBgActive, input_bg)
    imgui.PushItemWidth(input_w)
    imgui.InputTextMultiline('##messenger_input_' .. tostring(M.input_gen or 0), M.input, 4096, imgui.ImVec2(input_w, dynamic_input_h))
    imgui.PopItemWidth()
    imgui.PopStyleColor(3)
    st.ScrollbarSize = old_scroll_size
    if imgui.IsItemHovered() then imgui.SetTooltip(T('Enter - новая строка. Отправка - кнопкой справа.')) end

    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button, btn_bg)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, btn_hover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, btn_active)
    if imgui.Button((fa.FACE_SMILE or ':)') .. '##emoji_btn', imgui.ImVec2(btn_size, btn_size)) then imgui.OpenPopup('##emoji_popup') end
    imgui.PopStyleColor(3)
    if imgui.BeginPopup('##emoji_popup') then
        imgui.Text(T('Эмодзи:'))
        imgui.Separator()
        for i, key in ipairs(EMOJIS_ICONS) do
            if (i - 1) % 6 ~= 0 then imgui.SameLine() end
            if fa[key] then
                if imgui.Button(fa[key] .. '##emj_' .. i, imgui.ImVec2(30 * dpi, 30 * dpi)) then
                    insert_to_input(fa[key])
                    imgui.CloseCurrentPopup()
                end
            end
        end
        imgui.EndPopup()
    end

    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button, btn_bg)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, btn_hover)
    imgui.PushStyleColor(imgui.Col.ButtonActive, btn_active)
    if imgui.Button('@##mention_btn', imgui.ImVec2(btn_size, btn_size)) then imgui.OpenPopup('##mention_popup') end
    imgui.PopStyleColor(3)
    if imgui.BeginPopup('##mention_popup') then
        local is_cross_server = (tostring(M.get_server()) == '900')
        if is_cross_server then
            imgui.TextColored(red, (fa.BAN or '') .. T(' Упоминания групп запрещены в межпроектном чате'))
            imgui.TextColored(muted, T('Используйте только эмодзи и личные упоминания (@ник)'))
        else
            imgui.Text(T('Упомянуть группу:'))
            imgui.Separator()
            if not M.is_admin() then
                local elapsed = os.time() - (M.last_group_mention_at or 0)
                if elapsed < M.MENTION_COOLDOWN then
                    imgui.TextColored(red, (fa.CLOCK or '') .. T(string.format(' КД: %d сек', M.MENTION_COOLDOWN - elapsed)))
                else
                    imgui.TextColored(green, (fa.CIRCLE_CHECK or '') .. T(' Готово к использованию'))
                end
                imgui.Separator()
            end
            imgui.TextColored(muted, T('Фракции:'))
            for _, mode in ipairs(MENTION_MODES) do
                if imgui.SmallButton('@' .. mode .. '##mode_' .. mode) then
                    insert_to_input('@' .. mode)
                    imgui.CloseCurrentPopup()
                end
                imgui.SameLine()
            end
            imgui.NewLine()
        end
        imgui.EndPopup()
    end

    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button, accent)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(math.min(1, accent.x * 1.15), math.min(1, accent.y * 1.15), math.min(1, accent.z * 1.15), 1))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(accent.x * 0.85, accent.y * 0.85, accent.z * 0.85, 1))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
    if imgui.Button((fa.PAPER_PLANE or '>') .. T(' Отправить'), imgui.ImVec2(send_w, dynamic_input_h)) then
        local text = ffi.string(M.input, 4096):match("^[^%z]*") or ""
        if M.send(text) then
            ffi.fill(M.input, 4096, 0)
            M.input_gen = (M.input_gen or 0) + 1
        end
    end
    imgui.PopStyleColor(4)

    if M.window[0] ~= true then M.chat_open = false end
    imgui.End()
end

function M.return_home()
    M.set_server(0)
end
function M.set_server(value)
    local str_val = tostring(value)
    local is_cross = (str_val == '00' or str_val == 'Межпроектный')
    local is_reset = (str_val == '0' or str_val == '')
    if is_reset then
        M.admin_lobby = nil; M.messages = {}; M.system_messages = {}; M.last_id = 0; M.last_system_id = 0
        M.session = ''
        M.pending_initial_sync = true
        M.msg_reactions, M.pinned = {}, nil
        M.heartbeat()
        return
    end
    if not is_cross and not M.is_admin() then M.print('Другие серверы доступны только администраторам.'); return end
    local server_num = tonumber(str_val) or 0
    if not is_cross and (server_num < 1 or server_num > 1000) then return end
    local server_label = is_cross and '00' or (server_num < 10 and string.format('0%d', server_num) or tostring(server_num))
    M.admin_lobby = server_label; M.messages = {}; M.system_messages = {}; M.last_id = 0; M.last_system_id = 0
    M.session = ''
    M.pending_initial_sync = true
    M.msg_reactions, M.pinned = {}, nil
    M.heartbeat()
end

function M.print(text)
    if type(sampAddChatMessage) == 'function' then
        local prefix = tostring(ctx().chat_prefix or 'Arizona Helper')
        local safe_text = to_clip(tostring(text))
        pcall(sampAddChatMessage, '[' .. prefix .. '] {ffffff}' .. safe_text, ctx().message_color or 40703)
    end
end

function M.init(opts)
    M.ctx = opts or {}
    if M.admin and type(M.admin.init) == 'function' then
        local admin_inited = pcall(M.admin.init, { config_dir = opts.config_dir or '', chat_prefix = opts.chat_prefix, message_color = opts.message_color, decodeJson = opts.decodeJson, encodeJson = opts.encodeJson, asyncHttpRequest = opts.asyncHttpRequest, base_url = M.base_url, hwid = M.hwid })
        if not admin_inited then M.admin = nil end
    end
    M.disabled = opts.disabled == true
    local config = read_config()
    M.base_url = M.default_url
    M.server = tonumber(opts.server or config.server or 1) or 1
    M.hwid = tostring(config.hwid or '')
    M.last_id = tonumber(config.last_id) or 0
    M.last_system_id = tonumber(config.last_system_id) or 0
    M.last_cleared_at = tostring(config.last_cleared_at or '')
    M.hide_system = config.hide_system == true
    M.show_avatars = config.show_avatars ~= false
    M.chat_crowns = config.chat_crowns ~= false
    M.avatar_mode = config.avatar_mode or 'letters'
    M.avatar_icon = config.avatar_icon or 'FACE_SMILE'
    M.avatar_outline = tonumber(config.avatar_outline) or 1
    M.avatar_bg = type(config.avatar_bg) == 'table' and config.avatar_bg or nil
    M.avatar_fg = type(config.avatar_fg) == 'table' and config.avatar_fg or nil
    if M.hwid == '' and not M.disabled then M.hwid = make_hwid() end
    M.enabled = (not M.disabled) and M.base_url ~= ''
    if opts.enabled ~= nil then M.enabled = opts.enabled == true and M.base_url ~= '' end
    M.save_config()
    if ctx().imgui then
        M.window = ctx().imgui.new.bool(false)
        M.input = ctx().imgui.new.char[4096]('')
        M.admin_mute_buf = ffi.new("int[1]", 15)
        ctx().imgui.OnFrame(function() return M.window and M.window[0] end, function(player) M.draw(player) end)
    end
    if type(ctx().module) == 'table' then
        ctx().module.Messenger = M
        ctx().module.HelperUsers = ctx().module.HelperUsers or {}
        ctx().module.HelperUsers.list = M.users
    end
    M.start()
    return M
end

return M