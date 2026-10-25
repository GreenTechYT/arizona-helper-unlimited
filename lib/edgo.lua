local function setup(ctx)
	ctx = ctx or {}
	local u8 = ctx.u8
	local ffi = ctx.ffi
	local MODULE = ctx.MODULE
	local settings = ctx.settings
	local modules = ctx.modules
	if not (u8 and ffi and MODULE and settings and modules) then
		print('[EDGO] lib/edgo.lua: не переданы зависимости (u8, ffi, MODULE, settings, modules)')
		return
	end
	local function edgo_lower(s)
		if type(s) ~= "string" then return "" end
		return s:rlower()
	end
	MODULE.Edgo.lower = edgo_lower
	local function format_nick_for_rp(nick)
		if not nick or nick == "" then return "" end
		nick = nick:gsub('%[%d+%]', '')
		nick = nick:gsub('_', ' ')
		nick = nick:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
		return nick
	end
	local function edgo_is_fbi()
		if type(isMode) == "function" and isMode("fbi") then return true end
		local fr, ft = modules.player.data.fraction, modules.player.data.fraction_tag
		return ft == "ФБР" or fr == "FBI" or fr == "ФБР"
	end
	local function edgo_go_phone()
		local b = MODULE.Edgo.badge
		b.phase = "phone"; b.order = nil; b.org_pos = 0
		MODULE.Edgo.sched("open", nil, 0)
	end
	local function edgo_go_members_or_phone()
		local b = MODULE.Edgo.badge
		if b.use_members then
			b.phase = "members"; b.last_active_time = os.clock()
			MODULE.Edgo.send_cmd("/members")
		else
			edgo_go_phone()
		end
	end	
	local function edgo_open_app(appId)
		local str = ('launchedApp|%s'):format(appId)
		local bs = raknetNewBitStream()
		raknetBitStreamWriteInt8(bs, 220); raknetBitStreamWriteInt8(bs, 18)
		raknetBitStreamWriteInt16(bs, #str); raknetBitStreamWriteString(bs, str)
		raknetBitStreamWriteInt32(bs, 0); raknetSendBitStream(bs); raknetDeleteBitStream(bs)
	end
	local function edgo_str(buf) return u8:decode(ffi.string(buf)):gsub("^%s+", ""):gsub("%s+$", "") end
	local function edgo_num(s) return tonumber(type(s) == "string" and s or tostring(s or "")) end
	function MODULE.Edgo.collect()
		return {
			online = MODULE.Edgo.Online[0], id = edgo_num(edgo_str(MODULE.Edgo.id_buf)),
			nick = edgo_str(MODULE.Edgo.nick_buf), year = edgo_str(MODULE.Edgo.year_buf),
			org = edgo_str(MODULE.Edgo.org_buf), rank = edgo_str(MODULE.Edgo.rank_buf),
			phone = edgo_str(MODULE.Edgo.phone_buf), status = edgo_str(MODULE.Edgo.status_buf),
		}
	end
	function MODULE.Edgo.validate(d)
		if d.online then
			if not d.id then return false, 'Введите корректный ID игрока.' end
			if not sampIsPlayerConnected(d.id) then return false, 'Игрок с ID ' .. d.id .. ' не в сети (режим Online).' end
		else
			if d.nick == '' and d.year == '' and d.org == '' and d.rank == '' and d.phone == '' and d.status == '' then
				return false, 'Режим Offline: заполните хотя бы одно поле.'
			end
		end
		return true
	end
	function MODULE.Edgo.target_name(d)
		if d.online then
			return format_nick_for_rp(sampGetPlayerNickname(d.id))
		else
			return (d.nick ~= '' and format_nick_for_rp(d.nick)) or '(по данным паспорта)'
		end
	end
	function MODULE.Edgo.ru_name(d)
		local nick
		if d.online then
			nick = translate(sampGetPlayerNickname(d.id)) or sampGetPlayerNickname(d.id)
		else
			if d.nick:find('[A-Za-z]') and d.nick:find('_') then
				nick = translate(d.nick) or d.nick
			else
				nick = d.nick
			end
		end
		return format_nick_for_rp(nick)
	end
	local function rp_sex()
		local f = modules.player.data.sex == "Женщина"
		return (f and "а" or ""), (f and "ла" or "ёл")
	end
	function MODULE.Edgo.say(line) table.insert(MODULE.Edgo.rp_queue, { line = line }) end
	function MODULE.Edgo.done() table.insert(MODULE.Edgo.rp_queue, { done = true }) end
	local function edgo_send_raw(bytes)
		local bs = raknetNewBitStream()
		for i = 1, #bytes do raknetBitStreamWriteInt8(bs, bytes[i]) end
		raknetSendBitStream(bs); raknetDeleteBitStream(bs)
	end
	function MODULE.Edgo.sched(t, payload, delay_ms)
		local q = MODULE.Edgo.queue
		q.type = t; q.payload = payload or {}
		q.timestamp = os.clock() * 1000 + (delay_ms or 0); q.active = true
	end
	function MODULE.Edgo.stop_badge(reason)
		MODULE.Edgo.close_phone()
		local b = MODULE.Edgo.badge
		MODULE.Edgo._num_suppress_id = b.target_id
		MODULE.Edgo._num_suppress_until = os.clock() + 6
		b.closing = true; b.order = nil; b.org_pos = 0
		MODULE.Edgo.queue.active = false; MODULE.Edgo.cmd_queue = {}; MODULE.Edgo.rp_queue = {}
		MODULE.Binder.state.isActive = false
		lua_thread.create(function() wait(1000); local bb = MODULE.Edgo.badge; bb.active = false; bb.closing = false; bb.phase = "phone" end)
		if reason then sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}' .. reason, message_color) end
	end
	function MODULE.Edgo.clean(s) return s:gsub('%{......%}', ''):gsub('<<', ''):gsub('>>', ''):gsub('^%s*(.-)%s*$', '%1') end
	function MODULE.Edgo.org_tag(name)
		if not name or name == "" then return name or "-" end
		if not MODULE.Edgo.ORG_TAG then return name end
		local low = edgo_lower(name)
		for k, tag in pairs(MODULE.Edgo.ORG_TAG) do
			local kl = edgo_lower(k)
			if kl == low or low:find(kl, 1, true) or kl:find(low, 1, true) then return tag end
		end
		return name
	end
	local RP_START_LINES = {
		bodycam_offline = 	'/me загрузил%s в КПК сохранённую запись нательной камеры и передал%s фрагмент на опознание по архиву ЭБГО.',
		bodycam_online = {
							'/me достал%s из нательной камеры SD-накопитель и, вставив его в КПК, система запросила объект опознания.',
							'/me проведя пальцем по экрану, выделил%s лицо человека на фрагменте и передал%s его на опознание в ЭБГО.',
		},
		voiced = {
							'/me выш%s в эфир рации департамента и получил%s запись переговоров.',
							'/me загрузил%s образец голоса в ЭБГО и запустил%s идентификацию.',
		},	
		voice = 			'/me загрузил%s в ЭБГО сохранённый образец голоса и запустил%s поиск совпадений по базе.',
		unsu =				'/me запросил%s у диспетчера данные о снятии розыска с гражданина и, получив их, запустил%s пробив по базе.',
		offline = 			'/me вручную ввёл%s в систему имеющиеся данные и запросил%s сверку по архиву ЭБГО.',
		online = 			'/me открыл%s в системе ЭБГО раздел сотрудников организаций и запустил%s поиск по базе.',
	}
	function MODULE.Edgo.rp_start(mode, who, offline)
		if not settings.mj.edgo_rp_enabled then return end
		local p, g = rp_sex()
		MODULE.Edgo.say('/me достал'..p..' из кармана служебный КПК и, включив его, на дисплее отобразилась система "ЭБГО".')
		local lines
		if mode == 'bodycam' then lines = offline and RP_START_LINES.bodycam_offline or RP_START_LINES.bodycam_online
		elseif mode == 'voiced' then lines = RP_START_LINES.voiced
		elseif mode == 'voice' then lines = RP_START_LINES.voice
		elseif mode == 'unsu' then lines = RP_START_LINES.unsu
		else lines = offline and RP_START_LINES.offline or RP_START_LINES.online end
		
		if type(lines) == 'table' then
			for _, line in ipairs(lines) do MODULE.Edgo.say(line:format(p, p)) end
		else
			MODULE.Edgo.say(lines:format(p, p))
		end
	end
	local function edgo_init_badge(mode, d)
		local b = MODULE.Edgo.badge
		local who = MODULE.Edgo.ru_name(d)
		b.active = true; b.closing = false; b.mode = mode
		b.target_id = d.online and d.id or -1
		b.match_nick = d.online and sampGetPlayerNickname(d.id) or ""
		b.display_name = who
		b.target_color = d.online and ("%06X"):format(bit.band(sampGetPlayerColor(d.id), 0xFFFFFF)) or nil
		b.order = nil; b.org_pos = 0; b.full_org_name = "..."; b.result_org = "..."
		b.found = false; b.result = nil; b.phone_opened = false
		b.use_members = edgo_is_fbi(); b.last_active_time = os.clock(); b.retry_count = 0; b.phase = 'leaders'
		return b, who
	end
	function MODULE.Edgo.start_unsu(arg)
		if MODULE.Edgo.badge.active or MODULE.Binder.state.isActive then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив уже идёт, дождитесь завершения.', message_color); play_sound(); return
		end
		local d = { online = false, id = -1 }
		if type(arg) == 'number' then
			if sampIsPlayerConnected(arg) then d.online = true; d.id = arg end
		else
			for id = 0, 999 do
				if sampIsPlayerConnected(id) and sampGetPlayerNickname(id) == arg then
					d.online = true; d.id = id; break
				end
			end
		end
		if not d.online then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Игрок не в сети. Используйте Offline-пробив с ручным вводом данных.', message_color); play_sound(); return
		end
		MODULE.Edgo.Window[0] = false; MODULE.Binder.state.isActive = true
		MODULE.Edgo.rp_queue = {}; MODULE.Edgo.cmd_queue = {}; MODULE.Edgo.last_send = 0
		local b, who = edgo_init_badge('unsu', d)
		if settings.mj.edgo_rp_enabled then info_stop_command() end
		sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив ЭБГО для ' .. message_color_hex .. who .. '{ffffff} запущен.', message_color)
		MODULE.Edgo.rp_start('unsu', who, false); MODULE.Edgo.send_cmd('/leaders')
	end
	function MODULE.Edgo.emit_result(mode, who, r, org_raw)
		MODULE.Edgo.close_phone()
		local has_phone  = r and r.phone  and r.phone  ~= "" and r.phone  ~= "-"
		local has_status = r and r.status and r.status ~= "" and r.status ~= "-"
		local phone  = has_phone and r.phone or "-"
		local status = has_status and r.status or "В штате"
		local year = (r and r.year and r.year ~= "" and r.year ~= "-") and r.year or nil
		local found_gov = org_raw and org_raw ~= "" and org_raw ~= "-"
		if not settings.mj.edgo_rp_enabled then
			if found_gov then
				local org = MODULE.Edgo.org_tag(org_raw)
				local rank = (r and r.rank ~= "" and r.rank) or "-"
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Гражданин ' .. message_color_hex .. who .. '{ffffff} найден в организации: ' .. message_color_hex .. org .. '{ffffff}, на должности: ' .. message_color_hex .. rank .. '{ffffff}.', message_color)
			else
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Гражданин ' .. message_color_hex .. who .. '{ffffff} по базе ЭБГО на гос. службе не числится. Контакт: ' .. message_color_hex .. phone .. '{ffffff}.', message_color)
			end
			MODULE.Binder.state.isActive = false
			MODULE.Edgo.stop_badge(nil)
			return
		end
		local p = rp_sex()
		if mode == 'bodycam' then MODULE.Edgo.say('/do КПК выдал результат опознания.') end
		if found_gov then
			local org = MODULE.Edgo.org_tag(org_raw)
			local rank = (r and r.rank ~= "" and r.rank) or "-"
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Гражданин ' .. message_color_hex .. who .. '{ffffff} найден в организации: ' .. message_color_hex .. org .. '{ffffff}, на должности: ' .. message_color_hex .. rank .. '{ffffff}.', message_color)
			MODULE.Edgo.say('/do ЭБГО: по гражданину ' .. who .. ' найдено совпадение.')
			MODULE.Edgo.say('/do Организация: ' .. org .. ', должность: ' .. rank .. '.')
			local extra = {}
			if year then table.insert(extra, 'год рождения: ' .. year) end
			if has_phone then table.insert(extra, 'контакт: ' .. r.phone) end
			if has_status then table.insert(extra, 'статус: ' .. r.status) end
			if #extra > 0 then MODULE.Edgo.say('/do Дополнительно: ' .. table.concat(extra, ', ') .. '.') end
		else
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Гражданин ' .. message_color_hex .. who .. '{ffffff} по базе ЭБГО на гос. службе не числится. Контакт: ' .. message_color_hex .. phone .. '{ffffff}.', message_color)
			MODULE.Edgo.say('/do ЭБГО: запрос по гражданину ' .. who .. ' обработан.')
			MODULE.Edgo.say('/do Гражданин: ' .. who .. ', контакт: ' .. phone .. ', статус: ' .. status .. '.')
			if year then MODULE.Edgo.say('/do Год рождения: ' .. year .. '.') end
		end
		MODULE.Edgo.say('/me ознакомившись с результатами, убрал'..p..' служебный КПК обратно.')
		MODULE.Edgo.done()
	end
	local function edgo_notfound_basic(b)
		b.closing = true
		MODULE.Edgo.request_number(b.mode, b.display_name, { phone = "", status = "В штате", rank = "-" }, "", b.target_id)
	end
	local function edgo_parse_leader_line(raw, target_id)
		local cleaned = MODULE.Edgo.clean(raw)
		local name, idstr = cleaned:match("([%w_]+)%s*%[(%d+)%]")
		if not name or tonumber(idstr) ~= target_id then return nil end
		local org = cleaned:match("[%-%–]%s*([^\t]+)") or "-"
		org = org:gsub("^%s+", ""):gsub("%s+$", "")
		local phone = cleaned:match("ТЕЛ[:%s]+(%d+)") or cleaned:match("%[%(]%s*(%d+)") or ""
		return { org = org, phone = phone }
	end
	local function edgo_org_order(target_color)
		local ORGS = MODULE.Edgo.ORGS
		local ORG_TAG = MODULE.Edgo.ORG_TAG
		if not ORGS then return {} end
		local tag_to_full = {}
		for full_name, tag in pairs(ORG_TAG) do
			tag_to_full[tag:upper()] = full_name
		end
		local target_full_name = nil
		if target_color then
			for _, o in ipairs(ORGS) do
				if o.color:upper() == target_color then
					target_full_name = tag_to_full[o.name:upper()]
					break
				end
			end
		end
		local prio, rest = {}, {}
		for _, o in ipairs(ORGS) do
			local full_name = tag_to_full[o.name:upper()]
			local is_prio = false
			if target_color and o.color:upper() == target_color then
				is_prio = true
			elseif target_full_name and full_name then
				local low_full = edgo_lower(full_name)
				local low_target = edgo_lower(target_full_name)
				if low_full == low_target then
					is_prio = true
				end
			end
			if is_prio then
				table.insert(prio, o)
			else
				table.insert(rest, o)
			end
		end
		local order = {}
		for _, o in ipairs(prio) do table.insert(order, o) end
		for _, o in ipairs(rest) do table.insert(order, o) end
		return #order == 0 and ORGS or order
	end
	local function edgo_advance_org(id)
		local b = MODULE.Edgo.badge
		b.org_pos = b.org_pos + 1
		if b.order == nil or b.org_pos > #b.order then
			sampSendDialogResponse(id, 0, 0, ""); edgo_notfound_basic(b)
		else
			sampSendDialogResponse(id, 0, 0, "")
			lua_thread.create(function() wait(80) if b.active then MODULE.Edgo.sched('open', nil, 0) end end)
		end
	end
	local function edgo_parse_members(text, target_id, match_nick)
		local low_match = edgo_lower(match_nick or "")
		for line in (text or ""):gmatch("[^\r\n]+") do
			local cl = MODULE.Edgo.clean(line)
			local lcl = edgo_lower(cl)
			local hit = false
			if target_id > 0 and cl:match("([%w_]+)%(" .. target_id .. "%)") then hit = true
			elseif low_match ~= "" and lcl:find(low_match .. "(", 1, true) then hit = true end
			if hit then
				local rank = nil
				if target_id > 0 then 
					rank = cl:match("%(" .. target_id .. "%)%s*([^%(]+)%(%d+%)") 
				end
				if (not rank or rank:match("^%s*$")) and target_id > 0 then
					rank = cl:match("%(" .. target_id .. "%)%s*([^%[%]]+)%[")
				end
				if (not rank or rank:match("^%s*$")) and target_id > 0 then
					rank = cl:match("%[%d+%]%s+(%S+)%s+([%w_]+)%(" .. target_id .. "%)")
				end
				if (not rank or rank:match("^%s*$")) and target_id > 0 then
					if cl:find("([%w_]+)%(" .. target_id .. "%)") then
						local last_bracket_content = nil
						for content in cl:gmatch("%[%s*([^%[%]]-)%s*%]") do
							last_bracket_content = content
						end
						if last_bracket_content then
							last_bracket_content = last_bracket_content:gsub("^%s+", ""):gsub("%s+$", "")
							local low_content = edgo_lower(last_bracket_content)
							if last_bracket_content ~= "" 
							and not last_bracket_content:match("^%d+$") 
							and not low_content:find("работает", 1, true) 
							and not low_content:find("не работает", 1, true)
							and not low_content:find("афк", 1, true) 
							and not low_content:find("спец", 1, true) then
								rank = last_bracket_content
							end
						end
					end
				end
				if (not rank or rank:match("^%s*$")) and low_match ~= "" then
					rank = lcl:match(low_match .. "%(%d+%)%s*([^%(]+)%(%d+%)")
				end
				rank = (rank or ""):gsub("^%s+", ""):gsub("%s+$", "")
				return (rank ~= "") and rank or "-"
			end
		end
		return nil
	end
	local function edgo_handle_dialog(id, style, title, text)
		local b = MODULE.Edgo.badge
		if not (b and b.active) then return false end
		b.last_active_time = os.clock(); b.retry_count = 0
		if b.closing then
			sampSendDialogResponse(id, 0, 0, ""); return false
		end
		local lines = {}
		for line in (text or ""):gmatch("[^\r\n]+") do table.insert(lines, line) end
		local low_text = edgo_lower(text or "")
		local low_title = edgo_lower(title or "")
		local _ht = low_title
		local detected_type = nil
		if low_title:find("лидер", 1, true) or low_title:find("руководит", 1, true) then
			detected_type = 'leaders'
		elseif low_title:find("заместит", 1, true) then
			detected_type = 'zams'
		elseif low_title:find("сотрудники онлайн", 1, true) or low_title:find("%(в сети", 1, true) or low_title:find("в сети всего", 1, true) then
			detected_type = 'members'
		end
		local effective_phase = detected_type or b.phase
		local _is_own_members = _ht:find("(в сети", 1, true) or _ht:find("в сети всего", 1, true)
		local _is_lead_dialog = (not _is_own_members) and (_ht:find("лидер", 1, true) or _ht:find("заместит", 1, true) or _ht:find("руководит", 1, true))
		if _is_lead_dialog or effective_phase == 'leaders' or effective_phase == 'zams' then
			local role_from_header = nil
			if _ht:find("лидер", 1, true) or _ht:find("руководит", 1, true) then role_from_header = "Руководитель"
			elseif _ht:find("заместит", 1, true) then role_from_header = "Заместитель" end
			local hit = nil
			for _, line in ipairs(lines) do
				local r = edgo_parse_leader_line(MODULE.Edgo.clean(line), b.target_id)
				if r then hit = r; break end
			end
			sampSendDialogResponse(id, 1, 0, "")
			if hit then
				b.closing = true
				local role = role_from_header or ((effective_phase == 'leaders') and "Руководитель" or "Заместитель")
				MODULE.Edgo.request_number(b.mode, b.display_name, { phone = hit.phone, status = "В штате", rank = role }, hit.org, b.target_id)
			else
				local cur = b.phase
				lua_thread.create(function()
					wait(250)
					if not b.active or b.phase ~= cur then return end
					if cur == 'leaders' then 
						b.phase = 'zams'; b.last_active_time = os.clock(); MODULE.Edgo.send_cmd('/zams')
					elseif cur == 'zams' then 
						edgo_go_members_or_phone()
					end
				end)
			end
			return false
		end
		local is_members_dialog = low_title:find("сотрудники онлайн", 1, true) ~= nil
		if is_members_dialog or _is_own_members or effective_phase == 'members' then
			local hit_rank = edgo_parse_members(text, b.target_id, b.match_nick)
			if hit_rank then
				b.found = true; b.closing = true
				sampSendDialogResponse(id, 0, 0, "")
				local org_for_result = (b.phase == 'members') and "ФБР" or (b.full_org_name or "...")
				MODULE.Edgo.request_number(b.mode, b.display_name, { phone = "", status = "В штате", rank = hit_rank }, org_for_result, b.target_id)
				return false
			end
			local count, next_btn = 0, -1
			for line in (text or ""):gmatch("[^\r\n]+") do
				count = count + 1
				local ll = edgo_lower(line)
				if ll:find("следующая", 1, true) or ll:find(">>>", 1, true) or ll:find("вперед", 1, true) then
					next_btn = count - 2
				end
			end
			if next_btn >= 0 then
				sampSendDialogResponse(id, 1, next_btn, "")
			else
				if b.phase == 'members' then
					sampSendDialogResponse(id, 0, 0, ""); edgo_go_phone()
				else
					edgo_advance_org(id)
				end
			end
			return false
		end
		local is_emp = (style == 5 and low_title:find("сотрудники онлайн", 1, true)) or (low_text:find("сотрудник", 1, true) and low_text:find("ранг", 1, true))
		local is_empty = low_text:find("0 игроков", 1, true) or low_text:find("всего в онлайне: 0", 1, true)
		local is_orglist = (id == 8744) or (style == 2 and not is_emp and not is_empty)
		if is_emp or is_empty then
			if is_empty then 
				edgo_advance_org(id); return false 
			end
			local offset = (style == 4 or style == 5) and 1 or 0
			local next_btn = -1
			local low_match = edgo_lower(b.match_nick or "")
			for i, line in ipairs(lines) do
				local raw = MODULE.Edgo.clean(line)
				if not (offset == 1 and i == 1) then
					local hit = false
					if b.target_id > 0 and raw:match("[%w_]+%(" .. b.target_id .. "%)") then hit = true
					elseif low_match ~= "" and edgo_lower(raw):find(low_match .. "(", 1, true) then hit = true end
					if hit then
						b.found = true; b.result = MODULE.Edgo.format_found(raw); b.result_org = b.full_org_name
						b.closing = true; sampSendDialogResponse(id, 0, 0, "")
						MODULE.Edgo.request_number(b.mode, b.display_name, b.result, b.full_org_name, b.target_id)
						return false
					end
					if raw:find("Следующая", 1, true) or raw:find(">>>") or raw:find("лед") then
						next_btn = (i - 1) - offset
					end
				end
			end
			if next_btn ~= -1 then 
				sampSendDialogResponse(id, 1, next_btn, "")
			else 
				edgo_advance_org(id)
			end
			return false
		end
		if is_orglist then
			if b.order == nil then 
				b.order = edgo_org_order(b.target_color); b.org_pos = 1 
			end
			local is_orglist_dialog = low_text:find("<< список собеседований", 1, true) or 
									low_text:find("<< полиция", 1, true) or
									low_text:find("<< больница", 1, true) or
									low_text:find("<< правительство", 1, true)
			if is_orglist_dialog then
				local item = b.order[b.org_pos]
				if item == nil then 
					sampSendDialogResponse(id, 0, 0, ""); edgo_notfound_basic(b)
				else 
					b.full_org_name = item.name
					sampSendDialogResponse(id, 1, item.index, "")
				end
			else
				local hit_rank = edgo_parse_members(text, b.target_id, b.match_nick)
				if hit_rank then
					b.found = true; b.closing = true
					sampSendDialogResponse(id, 0, 0, "")
					MODULE.Edgo.request_number(b.mode, b.display_name, { phone = "", status = "В штате", rank = hit_rank }, b.full_org_name, b.target_id)
				else
					b.org_pos = b.org_pos + 1
					if b.org_pos > #b.order then
						sampSendDialogResponse(id, 0, 0, ""); edgo_notfound_basic(b)
					else
						sampSendDialogResponse(id, 0, 0, "")
						lua_thread.create(function() wait(80) if b.active then MODULE.Edgo.sched('open', nil, 0) end end)
					end
				end
			end
			return false
		end
		return false
	end
	MODULE.Edgo.handle_dialog = edgo_handle_dialog
	function MODULE.Edgo.request_number(mode, who, r, org_raw, target_id)
		MODULE.Edgo._num_token = (MODULE.Edgo._num_token or 0) + 1
		local token = MODULE.Edgo._num_token
		MODULE.Edgo.pending_number = { token = token, mode = mode, who = who, r = r, org_raw = org_raw, target_id = target_id }
		sampSendChat('/number ' .. tostring(target_id)); MODULE.Edgo.last_send = os.clock() * 1000
		lua_thread.create(function()
			wait(3500)
			local pn = MODULE.Edgo.pending_number
			if pn and pn.token == token then MODULE.Edgo.pending_number = nil; MODULE.Edgo.emit_result(pn.mode, pn.who, pn.r, pn.org_raw) end
		end)
	end
	function MODULE.Edgo.try_consume_number(text)
		local pn = MODULE.Edgo.pending_number
		if not pn then return false end
		local c = (text or ""):gsub('%{......%}', '')
		local id_in = c:match('%[(%d+)%]')
		local num = c:match(':%s*(%d+)%s*$')
		if id_in and num and tonumber(id_in) == pn.target_id then
			pn.r.phone = num; MODULE.Edgo.pending_number = nil
			MODULE.Edgo.emit_result(pn.mode, pn.who, pn.r, pn.org_raw)
			return true
		end
		return false
	end
	local function edgo_run_scan(mode)
		if MODULE.Edgo.badge.active then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив уже идёт, дождитесь завершения.', message_color); play_sound(); return
		end
		if MODULE.Binder.state.isActive then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Дождитесь завершения предыдущей команды.', message_color); play_sound(); return
		end
		local _now = os.clock()
		if MODULE.Edgo.last_scan_time and (_now - MODULE.Edgo.last_scan_time) < 5 then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив можно запускать не чаще раза в 5 секунд.', message_color); play_sound(); return
		end
		MODULE.Edgo.last_scan_time = _now
		local d = MODULE.Edgo.collect()
		local ok, err = MODULE.Edgo.validate(d)
		if not ok then sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}' .. err, message_color); play_sound(); return end
		local who = MODULE.Edgo.ru_name(d)
		MODULE.Edgo.Window[0] = false; MODULE.Binder.state.isActive = true
		MODULE.Edgo.rp_queue = {}; MODULE.Edgo.cmd_queue = {}; MODULE.Edgo.last_send = 0
		if not d.online then
			local b = MODULE.Edgo.badge
			b.active = true; b.closing = true; b.mode = mode; b.phase = 'offline'
			b.display_name = who; b.target_id = -1; b.match_nick = ""; b.last_active_time = os.clock()
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив ЭБГО для ' .. message_color_hex .. who .. '{ffffff} по введённым данным.', message_color)
			MODULE.Edgo.rp_start(mode, who, true)
			MODULE.Edgo.emit_result(mode, who, { phone = d.phone, status = d.status, rank = d.rank, year = d.year }, d.org)
			return
		end
		if not d.id or not sampIsPlayerConnected(d.id) then
			MODULE.Binder.state.isActive = false
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Введите корректный ID игрока в сети.', message_color); play_sound(); return
		end
		local b, who_full = edgo_init_badge(mode, d)
		if settings.mj.edgo_rp_enabled then info_stop_command() end
		sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив ЭБГО для ' .. message_color_hex .. who_full .. '{ffffff} запущен.', message_color)
		sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Происходит поиск организации гражданина ' .. message_color_hex .. who_full .. '{ffffff}. Может занять некоторое время.', message_color)
		MODULE.Edgo.rp_start(mode, who, false); MODULE.Edgo.send_cmd('/leaders')
	end
	MODULE.Edgo.run_badge = function() edgo_run_scan('badge') end
	MODULE.Edgo.run_voice = function() edgo_run_scan('voice') end
	MODULE.Edgo.run_voiced = function() edgo_run_scan('voiced') end
	MODULE.Edgo.run_bodycam = function() edgo_run_scan('bodycam') end
	function MODULE.Edgo.run_history()
		if not MODULE.Edgo.Online[0] then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}История имён доступна только в режиме Online (по ID игрока).', message_color); play_sound(); return
		end
		if MODULE.Binder.state.isActive then
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Дождитесь завершения предыдущей команды.', message_color); play_sound(); return
		end
		local d = MODULE.Edgo.collect()
		local token
		if d.online then
			if not d.id or not sampIsPlayerConnected(d.id) then
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Введите корректный ID игрока в сети.', message_color); play_sound(); return
			end
			token = sampGetPlayerNickname(d.id)
		else
			token = d.nick
			if token == "" then
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Для истории имён введите никнейм (Name_Surname) в поле "Имя и фамилия".', message_color); play_sound(); return
			end
		end
		local now = os.time()
		if now - (MODULE.Edgo.last_history_check or 0) < 15 then
			local rem = 15 - (now - (MODULE.Edgo.last_history_check or 0))
			sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Историю имён можно проверять не чаще раза в 15 секунд. Повторите через ' .. rem .. ' сек.', message_color)
			play_sound(); return
		end
		MODULE.Edgo.last_history_check = now
		local who = MODULE.Edgo.ru_name(d)
		MODULE.Edgo.Window[0] = false; MODULE.Binder.state.isActive = true
		if settings.mj.edgo_rp_enabled then info_stop_command() end
		sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Пробив ЭБГО для ' .. message_color_hex .. who .. '{ffffff} запущен.', message_color)
		local H = MODULE.Edgo.history
		H.active = true; H.finished = false; H.got = nil; H.waiting_result = false
		H.token = token; H.display_name = who
		lua_thread.create(function()
			local p = rp_sex()
			local rp_on = settings.mj.edgo_rp_enabled
			if rp_on then
				sampSendChat('/me достал'..p..' служебный КПК, запустил'..p..' ЭБГО и, пройдя авторизацию, открыл'..p..' архивный раздел истории имён.'); wait(4000)
				sampSendChat('/me инициировал'..p..' запрос архивной истории гражданина.'); wait(4000)
			else
				wait(500)
			end
			H.waiting_result = true
			H.result_time = os.time()
			sampSendChat('/phone'); wait(500); edgo_open_app(33); wait(500); sampSendChat('/phone')
			while H.active and not H.finished and (os.time() - H.result_time) < 12 do wait(100) end
			H.active = false; H.waiting_result = false
			if H.got and H.got ~= "" then
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Гражданин ' .. message_color_hex .. who .. '{ffffff}, ранее известен как: ' .. message_color_hex .. H.got .. '{ffffff}.', message_color)
				if rp_on then wait(4000) end
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Смен никнеймов ' .. message_color_hex .. who .. '{ffffff} в архиве ЭБГО: ' .. tostring(H.count or 0) .. '.', message_color)
				if rp_on then
					sampSendChat('/do Архив ЭБГО: запрос по гражданину ' .. who .. ' обработан.'); wait(4000)
					sampSendChat('/do Ранее был зарегистрирован как: ' .. H.got .. '.'); wait(4000)
				end
			else
				sampAddChatMessage('[' .. CHAT_PREFIX .. '] {ffffff}Архивных записей о смене имени гражданина ' .. message_color_hex .. who .. '{ffffff} не обнаружено.', message_color)
				if rp_on then
					sampSendChat('/do Архив ЭБГО: записей о прежних именах гражданина ' .. who .. ' не обнаружено.'); wait(4000)
				end
			end
			if rp_on then sampSendChat('/me убрал'..p..' служебный КПК обратно.') end
			MODULE.Binder.state.isActive = false
		end)
	end
	function MODULE.Edgo.send_cmd(cmd) table.insert(MODULE.Edgo.cmd_queue, cmd) end
	lua_thread.create(function()
		while true do
			wait(80)
			local b = MODULE.Edgo.badge
			if b and b.active and MODULE.Binder.state.isStop then
				MODULE.Edgo.rp_queue = {}
				MODULE.Binder.state.isStop = false
				MODULE.Edgo.stop_badge('Пробив ЭБГО досрочно остановлен.')
			elseif #MODULE.Edgo.rp_queue > 0 and (os.clock() * 1000 - MODULE.Edgo.last_send) >= (settings.mj.edgo_rp_cd or 3000) then
				local e = table.remove(MODULE.Edgo.rp_queue, 1)
				if e.done then MODULE.Edgo.stop_badge(nil)
				else sampSendChat(e.line); MODULE.Edgo.last_send = os.clock() * 1000 end
			end
		end
	end)
	local function edgo_close_phone()
		local b = MODULE.Edgo.badge
		if b.phone_opened then b.phone_opened = false; MODULE.Edgo.last_send = os.clock() * 1000; sampSendChat('/phone') end
	end
	MODULE.Edgo.close_phone = edgo_close_phone
	lua_thread.create(function()
		while true do
			wait(80)
			local b = MODULE.Edgo.badge
			if not (b and b.active) then
				if #MODULE.Edgo.cmd_queue > 0 then MODULE.Edgo.cmd_queue = {} end
			elseif #MODULE.Edgo.cmd_queue > 0 and (os.clock() * 1000 - MODULE.Edgo.last_send) >= MODULE.Edgo.RP_CD then
				local c = table.remove(MODULE.Edgo.cmd_queue, 1)
				sampSendChat(c); MODULE.Edgo.last_send = os.clock() * 1000
			end
		end
	end)
	lua_thread.create(function()
		while true do
			wait(500)
			local b = MODULE.Edgo.badge
			if b and b.active and not b.closing and (b.phase == 'leaders' or b.phase == 'zams' or b.phase == 'members') and (os.clock() - b.last_active_time) > 5.0 then
				b.last_active_time = os.clock()
				if b.phase == 'leaders' then b.phase = 'zams'; MODULE.Edgo.send_cmd('/zams')
				elseif b.phase == 'zams' then edgo_go_members_or_phone()
				else edgo_go_phone() end
			end
		end
	end)
	lua_thread.create(function()
		while true do
			wait(50)
			local b = MODULE.Edgo.badge
			if b and b.active then
				local q = MODULE.Edgo.queue
				if q.active and q.type == 'open' and os.clock() * 1000 >= q.timestamp then
					q.active = false; b.phone_opened = true
					edgo_send_raw({220, 0, 80, 64}); wait(0); edgo_send_raw(MODULE.Edgo.PACKET_APP32)
				end
				if not b.closing and (os.clock() - b.last_active_time) > 5.0 then
					b.last_active_time = os.clock()
					if b.phase == 'phone' then edgo_notfound_basic(b)
					elseif b.phase == 'members' then edgo_go_phone()
					elseif b.phase == 'leaders' then b.phase = 'zams'; MODULE.Edgo.send_cmd('/zams')
					elseif b.phase == 'zams' then edgo_go_members_or_phone() end
				end
			end
		end
	end)
end
return setup