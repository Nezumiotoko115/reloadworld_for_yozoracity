local RESOURCE = GetCurrentResourceName()
local SCHEMA_VERSION = 1
local pending, sessions, manualLast = {}, {}, {}
local queue, writing = {}, false
local sequence, pendingCount = 0, 0

local function integer(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    value = math.floor(value)
    if value < minimum or value > maximum then return default end
    return value
end
Config.ResponseTimeoutMs = integer(Config.ResponseTimeoutMs, 5000, 500, 30000)
Config.ManualRateLimitSeconds = integer(Config.ManualRateLimitSeconds, 30, 0, 3600)
Config.MaxConcurrentDiagnostics = integer(Config.MaxConcurrentDiagnostics, 8, 1, 64)
Config.MaxPendingPerTarget = integer(Config.MaxPendingPerTarget, 2, 1, 8)
Config.MaxClientPayloadBytes = integer(Config.MaxClientPayloadBytes, 32768, 1024, 131072)
Config.MaxLogFileBytes = integer(Config.MaxLogFileBytes, 5242880, 65536, 1073741824)
Config.MaxRotationFilesPerDay = integer(Config.MaxRotationFilesPerDay, 999, 1, 9999)
Config.FpsSampleCount = integer(Config.FpsSampleCount, 30, 1, 120)
if type(Config.CommandName) ~= 'string' or not Config.CommandName:match('^[A-Za-z0-9_-]+$') then Config.CommandName = 'worldlog' end
if type(Config.AcePermission) ~= 'string' or #Config.AcePermission > 128 then Config.AcePermission = 'worlddiag.use' end
if type(Config.Fields) ~= 'table' then Config.Fields = {} end
if type(Config.LogDirectory) ~= 'string' or not Config.LogDirectory:match('^[A-Za-z0-9_-]+$') then
    print('[worlddiag] invalid LogDirectory; using logs')
    Config.LogDirectory = 'logs'
end

local function debugLog(message)
    if Config.Debug then print(('[worlddiag] %s'):format(message)) end
end
local function notify(src, message)
    if src and src > 0 and GetPlayerName(src) then
        TriggerClientEvent('worlddiag:client:notify', src, tostring(message):sub(1, 256))
    end
end
local function makeId(prefix, src)
    sequence = (sequence + 1) % 1000000
    local timer = math.abs(GetGameTimer()) % 0xffffffff
    return ('%s-%s-%d-%06d-%08x-%06x'):format(prefix, os.date('!%Y%m%dT%H%M%S'), src or 0,
        sequence, timer, math.random(0, 0xffffff))
end
local function utcNow() return os.date('!%Y-%m-%dT%H:%M:%SZ') end
local function finite(value, minimum, maximum)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
        and value >= minimum and value <= maximum
end
local function safeString(value, maximum)
    if type(value) ~= 'string' then return nil end
    return value:sub(1, maximum)
end
local function safeFields()
    local out = {}
    for _, name in ipairs({ 'position', 'movement', 'vehicle', 'fps', 'collision', 'environment', 'server' }) do
        out[name] = Config.Fields[name] == true
    end
    return out
end

local function fileSize(path)
    local handle = io.open(('@%s/%s'):format(RESOURCE, path), 'r')
    if not handle then return 0 end
    local size = handle:seek('end') or 0
    handle:close()
    return size
end
local function chooseLogPath(lineBytes)
    local date = os.date('!%Y-%m-%d')
    for index = 0, Config.MaxRotationFilesPerDay do
        local suffix = index == 0 and '' or ('-%03d'):format(index)
        local path = ('%s/%s%s.jsonl'):format(Config.LogDirectory, date, suffix)
        local size = fileSize(path)
        if size == 0 or size + lineBytes + 1 <= Config.MaxLogFileBytes or not Config.LogRotationEnabled then
            if not Config.LogRotationEnabled and size + lineBytes + 1 > Config.MaxLogFileBytes then
                return nil, 'daily_log_size_limit'
            end
            return path
        end
    end
    return nil, 'rotation_limit'
end
local function writeRecordNow(item)
    if not Config.LogSavingEnabled then return true, 'logging_disabled' end
    local ok, encoded = pcall(json.encode, item.record)
    if not ok or type(encoded) ~= 'string' then return false, 'json_encode_failed' end
    local path, reason = chooseLogPath(#encoded)
    if not path then return false, reason end
    local handle, openError = io.open(('@%s/%s'):format(RESOURCE, path), 'a')
    if not handle then return false, ('open_failed:%s'):format(tostring(openError)) end
    local wrote, writeError = handle:write(encoded, '\n')
    if wrote then handle:flush() end
    handle:close()
    if not wrote then return false, ('write_failed:%s'):format(tostring(writeError)) end
    return true, path
end
local function processQueue()
    if writing then return end
    writing = true
    CreateThread(function()
        while #queue > 0 do
            local item = table.remove(queue, 1)
            local ok, detail = writeRecordNow(item)
            if not ok then print(('[worlddiag] LOG WRITE FAILED: %s'):format(detail)) end
            if item.callback then pcall(item.callback, ok, detail) end
            Wait(0)
        end
        writing = false
    end)
end
local function enqueue(record, callback)
    record.schema_version = SCHEMA_VERSION
    record.utc = record.utc or utcNow()
    queue[#queue + 1] = { record = record, callback = callback }
    processQueue()
end

local function validateClientData(data, requestId)
    if type(data) ~= 'table' or data.request_id ~= requestId then return nil, 'request_id_mismatch' end
    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= 'string' or #encoded > Config.MaxClientPayloadBytes then return nil, 'payload_size' end
    local out = { request_id = requestId, quality = {} }
    if type(data.quality) == 'table' then
        for _, key in ipairs({ 'ped', 'collection' }) do
            local value = data.quality[key]
            if type(value) == 'table' and type(value.success) == 'boolean' then
                out.quality[key] = { success = value.success == true, reason = safeString(value.reason, 64),
                    detail = safeString(value.detail, 256) }
            end
        end
    end
    if type(data.position) == 'table' and finite(data.position.x, -10000, 10000)
        and finite(data.position.y, -10000, 10000) and finite(data.position.z, -2000, 10000)
        and finite(data.position.heading, -3600, 3600) then
        out.position = { x = data.position.x, y = data.position.y, z = data.position.z, heading = data.position.heading }
    end
    if type(data.movement) == 'table' and finite(data.movement.speed_mps, 0, 1000)
        and type(data.movement.on_foot) == 'boolean' and type(data.movement.falling) == 'boolean'
        and type(data.movement.getting_into_vehicle) == 'boolean' then
        out.movement = { speed_mps = data.movement.speed_mps, on_foot = data.movement.on_foot == true,
            falling = data.movement.falling == true, getting_into_vehicle = data.movement.getting_into_vehicle == true }
    end
    if type(data.vehicle) == 'table' and type(data.vehicle.in_vehicle) == 'boolean' then
        out.vehicle = { in_vehicle = data.vehicle.in_vehicle == true }
        if type(data.vehicle.model_hash) == 'string' and #data.vehicle.model_hash <= 24 then out.vehicle.model_hash = data.vehicle.model_hash end
        if finite(data.vehicle.speed_mps, 0, 1000) then out.vehicle.speed_mps = data.vehicle.speed_mps end
        if type(data.vehicle.quality) == 'table' and type(data.vehicle.quality.success) == 'boolean' then
            out.vehicle.quality = { success = data.vehicle.quality.success == true,
                source = safeString(data.vehicle.quality.source, 64),
                reason = safeString(data.vehicle.quality.reason, 64) }
        end
    end
    if type(data.fps) == 'table' then
        out.fps = { samples_requested = integer(data.fps.samples_requested, 0, 0, 120),
            samples_accepted = integer(data.fps.samples_accepted, 0, 0, 120),
            method = safeString(data.fps.method, 128), source = safeString(data.fps.source, 64),
            unavailable_reason = safeString(data.fps.unavailable_reason, 64) }
        if finite(data.fps.estimated, 0.1, 10000) then out.fps.estimated = data.fps.estimated end
        if finite(data.fps.average_frame_time_ms, 0.001, 10000) then out.fps.average_frame_time_ms = data.fps.average_frame_time_ms end
    end
    if type(data.collision) == 'table' and type(data.collision.loaded_around_ped) == 'boolean' then
        out.collision = { loaded_around_ped = data.collision.loaded_around_ped == true,
            source = safeString(data.collision.source, 64), note = safeString(data.collision.note, 160) }
    end
    if type(data.environment) == 'table' then
        out.environment = { game_build = integer(data.environment.game_build, nil, 0, 100000),
            game_name = safeString(data.environment.game_name, 32), source = safeString(data.environment.source, 64) }
    end
    if type(data.client_measurement) == 'table' then
        out.client_measurement = { source = safeString(data.client_measurement.source, 64),
            measured_game_timer_ms = integer(data.client_measurement.measured_game_timer_ms, nil, 0, 2147483647),
            completed_game_timer_ms = integer(data.client_measurement.completed_game_timer_ms, nil, 0, 2147483647),
            duration_ms = integer(data.client_measurement.duration_ms, nil, 0, 30000) }
    end
    return out
end

local function pendingForTarget(target)
    local count = 0
    for _, item in pairs(pending) do if item.target == target then count = count + 1 end end
    return count
end
local function requestDiagnostic(target, diagnosticType, requester, diagnosticId, context)
    if pendingCount >= Config.MaxConcurrentDiagnostics then return nil, 'global_limit' end
    if pendingForTarget(target) >= Config.MaxPendingPerTarget then return nil, 'target_limit' end
    if not GetPlayerName(target) then return nil, 'target_offline' end
    local requestId = makeId('req', target)
    pending[requestId] = { target = target, requester = requester, type = diagnosticType,
        diagnostic_id = diagnosticId, context = context, started_ms = GetGameTimer(),
        expires_ms = GetGameTimer() + Config.ResponseTimeoutMs }
    pendingCount = pendingCount + 1
    TriggerClientEvent('worlddiag:client:collect', target, requestId, {
        fps_sample_count = Config.FpsSampleCount, fields = safeFields() })
    CreateThread(function()
        Wait(Config.ResponseTimeoutMs + 50)
        local item = pending[requestId]
        if item then
            pending[requestId], pendingCount = nil, math.max(0, pendingCount - 1)
            if item.requester then notify(item.requester, ('診断は応答待ちでタイムアウトしました（対象ID %d）。'):format(target)) end
        end
    end)
    return requestId
end

RegisterNetEvent('worlddiag:server:response', function(requestId, data)
    local src = source
    if type(requestId) ~= 'string' or #requestId > 96 then return end
    local item = pending[requestId]
    if not item or item.target ~= src or GetGameTimer() > item.expires_ms then return end
    local client, reason = validateClientData(data, requestId)
    if not client then debugLog(('rejected response %s: %s'):format(requestId, reason)); return end
    pending[requestId], pendingCount = nil, math.max(0, pendingCount - 1)
    local record = {
        type = item.type, diagnostic_id = item.diagnostic_id, request_id = requestId,
        target_id = src, target_name = safeString(GetPlayerName(src) or 'unknown', 128),
        requester_id = item.requester, request_duration_ms = GetGameTimer() - item.started_ms,
        client = client, context = item.context
    }
    if Config.Fields.server then
        record.server = { ping_ms = GetPlayerPing(src), game_build = GetGameBuildNumber(),
            game_name = GetGameName(), source = 'server_cfx_native' }
    end
    enqueue(record, function(ok, detail)
        if item.requester then
            if ok and detail == 'logging_disabled' then
                notify(item.requester, '診断は完了しました（ログ保存は設定で無効）。')
            else
                notify(item.requester, ok and ('診断ログを保存しました: %s'):format(detail) or ('診断ログの保存に失敗しました: %s'):format(detail))
            end
        end
    end)
end)

RegisterCommand(Config.CommandName, function(source, args)
    local requester = tonumber(source)
    if not requester or requester <= 0 then print('[worlddiag] このコマンドはゲーム内管理者専用です。'); return end
    if not Config.ManualDiagnosticsEnabled then notify(requester, '手動診断は無効です。'); return end
    if not IsPlayerAceAllowed(requester, Config.AcePermission) then notify(requester, '実行権限がありません。'); return end
    local now = os.time()
    local remaining = (manualLast[requester] or 0) + Config.ManualRateLimitSeconds - now
    if remaining > 0 then notify(requester, ('レート制限中です。残り%d秒。'):format(remaining)); return end
    local target = requester
    if args[1] then
        target = tonumber(args[1])
        if not target or target < 1 or target % 1 ~= 0 then notify(requester, '対象のserverIdが不正です。'); return end
    end
    target = math.floor(target)
    if not GetPlayerName(target) then notify(requester, '対象プレイヤーが見つかりません。'); return end
    manualLast[requester] = now
    local diagnosticId = makeId('diag', target)
    local requestId, reason = requestDiagnostic(target, 'world_manual', requester, diagnosticId, { requested_by_admin = true })
    if not requestId then notify(requester, ('診断を開始できません: %s'):format(reason)); return end
    notify(requester, ('診断要求を送信しました（対象ID %d、調査ID %s）。'):format(target, diagnosticId))
    if Config.NotifyTarget and target ~= requester then notify(target, ('管理者がワールド診断を実行しています（調査ID %s）。'):format(diagnosticId)) end
end, false)

local function trustedCaller()
    return GetInvokingResource() == 'reloadworld'
end
exports('BeginReload', function(target, metadata)
    if not Config.ReloadworldIntegration or not Config.AutomaticDiagnosticLogs or not trustedCaller() then return nil end
    target = tonumber(target)
    if not target or not GetPlayerName(target) or type(metadata) ~= 'table' then return nil end
    local reloadId, mode = safeString(metadata.reload_id, 96), safeString(metadata.mode, 16)
    if not reloadId or (mode ~= 'normal' and mode ~= 'enhanced') or sessions[reloadId] then return nil end
    local diagnosticId = makeId('rw', target)
    sessions[reloadId] = { target = target, diagnostic_id = diagnosticId, mode = mode,
        created = os.time(), started_utc = safeString(metadata.server_started_utc, 32) or utcNow(),
        feedback = nil }
    requestDiagnostic(target, 'reload_before', nil, diagnosticId,
        { reload_id = reloadId, mode = mode, phase = 'before' })
    return diagnosticId
end)

exports('EndReload', function(target, result)
    if not Config.ReloadworldIntegration or not Config.AutomaticDiagnosticLogs or not trustedCaller() then return false end
    target = tonumber(target)
    if not target or type(result) ~= 'table' then return false end
    local reloadId = safeString(result.reload_id, 96)
    local session = reloadId and sessions[reloadId] or nil
    if not session or session.target ~= target or session.ended then return false end
    session.ended = os.time()
    local reload = {
        reload_id = reloadId, mode = session.mode, success = result.success == true,
        started_utc = session.started_utc, completed_utc = utcNow(),
        timed_out = result.timed_out == true, collision_loaded = result.collision_loaded == true,
        scene_started = result.scene_started == true, scene_loaded = result.scene_loaded == true,
        duration_ms = integer(result.duration_ms, nil, 0, 120000),
        error_code = safeString(result.error_code, 64), error_message = safeString(result.error_message, 512),
        stages = nil
    }
    if type(result.stages) == 'table' then
        reload.stages = {}
        if type(result.stages.basic) == 'table' then
            reload.stages.basic = { started = result.stages.basic.started == true,
                loaded = result.stages.basic.loaded == true }
        end
        if type(result.stages.enhanced) == 'table' then
            reload.stages.enhanced = { attempted = result.stages.enhanced.attempted == true,
                started = result.stages.enhanced.started == true,
                loaded = result.stages.enhanced.loaded == true }
        end
        if type(result.stages.cold_cycle) == 'table' then
            reload.stages.cold_cycle = { attempted = result.stages.cold_cycle.attempted == true,
                focus_set = result.stages.cold_cycle.focus_set == true,
                scene_started = result.stages.cold_cycle.scene_started == true,
                scene_loaded = result.stages.cold_cycle.scene_loaded == true,
                hold_completed = result.stages.cold_cycle.hold_completed == true }
        end
        if type(result.stages.return_stream) == 'table' then
            reload.stages.return_stream = { attempted = result.stages.return_stream.attempted == true,
                focus_set = result.stages.return_stream.focus_set == true,
                scene_started = result.stages.return_stream.scene_started == true,
                scene_loaded = result.stages.return_stream.scene_loaded == true,
                collision_loaded = result.stages.return_stream.collision_loaded == true,
                hold_completed = result.stages.return_stream.hold_completed == true }
        end
    end
    enqueue({ type = 'reload_result', diagnostic_id = session.diagnostic_id,
        target_id = target, target_name = safeString(GetPlayerName(target) or 'unknown', 128),
        reload = reload, feedback = { value = 'unreported', source = 'initial_state' } })
    if GetPlayerName(target) then
        requestDiagnostic(target, 'reload_after', nil, session.diagnostic_id,
            { reload_id = reloadId, mode = session.mode, phase = 'after' })
    end
    return true
end)

exports('RecordFeedback', function(target, reloadId, feedback)
    if not Config.ReloadworldIntegration or not trustedCaller() then return false end
    target, reloadId = tonumber(target), safeString(reloadId, 96)
    if feedback ~= 'fixed' and feedback ~= 'notfixed' then return false end
    local session = reloadId and sessions[reloadId] or nil
    if not session or session.target ~= target or session.feedback then return false end
    session.feedback = feedback
    enqueue({ type = 'reload_feedback', diagnostic_id = session.diagnostic_id,
        target_id = target, reload_id = reloadId,
        feedback = { value = feedback, source = 'player_subjective_report' } })
    return true
end)

AddEventHandler('playerDropped', function()
    local src = source
    manualLast[src] = nil
    for requestId, item in pairs(pending) do
        if item.target == src or item.requester == src then
            pending[requestId], pendingCount = nil, math.max(0, pendingCount - 1)
        end
    end
    for reloadId, session in pairs(sessions) do if session.target == src then sessions[reloadId] = nil end end
end)

CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = os.time() - 1800
        for reloadId, session in pairs(sessions) do if session.created < cutoff then sessions[reloadId] = nil end end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    while #queue > 0 do
        local item = table.remove(queue, 1)
        local ok, detail = writeRecordNow(item)
        if not ok then print(('[worlddiag] final log write failed: %s'):format(detail)) end
    end
end)

