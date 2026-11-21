local active, cooldownUntil, history = {}, {}, {}
local sequence = 0

local function clampInteger(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    value = math.floor(value)
    if value < minimum or value > maximum then return default end
    return value
end
Config.CooldownSeconds = clampInteger(Config.CooldownSeconds, 20, 0, 86400)
Config.FeedbackExpirySeconds = clampInteger(Config.FeedbackExpirySeconds, 300, 10, 86400)
Config.WorlddiagPreDelayMs = clampInteger(Config.WorlddiagPreDelayMs, 750, 0, 5000)
Config.FadeDurationMs = clampInteger(Config.FadeDurationMs, 350, 0, 5000)
Config.TimeoutMs = clampInteger(Config.TimeoutMs, 30000, 10000, 90000)
if type(Config.CommandName) ~= 'string' or not Config.CommandName:match('^[A-Za-z0-9_-]+$') then Config.CommandName = 'reloadworld' end
if type(Config.WorlddiagResourceName) ~= 'string' or not Config.WorlddiagResourceName:match('^[A-Za-z0-9_-]+$') then
    Config.WorlddiagResourceName = 'worlddiag'
end

local function notify(src, message)
    TriggerClientEvent('reloadworld:client:notify', src, tostring(message):sub(1, 256))
end
local function makeId(prefix, src)
    sequence = (sequence + 1) % 1000000
    local timer = math.abs(GetGameTimer()) % 0xffffffff
    return ('%s-%s-%d-%06d-%08x-%06x'):format(prefix, os.date('!%Y%m%dT%H%M%S'), src,
        sequence, timer, math.random(0, 0xffffff))
end
local function worlddiagStarted()
    return Config.WorlddiagIntegration and GetResourceState(Config.WorlddiagResourceName) == 'started'
end
local function invokeWorlddiag(exportName, ...)
    if not worlddiagStarted() then return false, nil end
    local args = { ... }
    local ok, result = pcall(function()
        return exports[Config.WorlddiagResourceName][exportName](table.unpack(args))
    end)
    if not ok and Config.Debug then print(('[reloadworld] worlddiag %s failed: %s'):format(exportName, result)) end
    return ok, result
end
local function hasPermission(src)
    return not Config.UseAce or IsPlayerAceAllowed(src, Config.AcePermission)
end
local function knownUnfrozen(src)
    if not Config.RequireKnownUnfrozenState then return true end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false, 'ped_unknown' end
    local ok, frozen = pcall(IsEntityPositionFrozen, ped)
    if not ok then return false, 'freeze_state_unknown' end
    if frozen then return false, 'already_frozen' end
    return true
end
local function sanitizeResult(data, expectedMode, expectedId)
    if type(data) ~= 'table' or data.reload_id ~= expectedId or data.mode ~= expectedMode then return nil end
    local duration = tonumber(data.duration_ms)
    if not duration or duration ~= duration or duration < 0 or duration > 120000 then return nil end
    local stages = nil
    if type(data.stages) == 'table' then
        stages = {}
        if type(data.stages.basic) == 'table' then
            stages.basic = { started = data.stages.basic.started == true, loaded = data.stages.basic.loaded == true }
        end
        if type(data.stages.player_switch) == 'table' then
            stages.player_switch = { attempted = data.stages.player_switch.attempted == true,
                started = data.stages.player_switch.started == true,
                out_hold_completed = data.stages.player_switch.out_hold_completed == true,
                return_started = data.stages.player_switch.return_started == true,
                completed = data.stages.player_switch.completed == true,
                forced_stop = data.stages.player_switch.forced_stop == true }
        end
        if type(data.stages.local_stream) == 'table' then
            stages.local_stream = { attempted = data.stages.local_stream.attempted == true,
                focus_set = data.stages.local_stream.focus_set == true,
                hd_area_set = data.stages.local_stream.hd_area_set == true,
                load_scene_called = data.stages.local_stream.load_scene_called == true,
                objects_forced = data.stages.local_stream.objects_forced == true,
                scene_started = data.stages.local_stream.scene_started == true,
                scene_loaded = data.stages.local_stream.scene_loaded == true,
                collision_loaded = data.stages.local_stream.collision_loaded == true,
                hold_completed = data.stages.local_stream.hold_completed == true }
        end
    end
    return {
        reload_id = expectedId, mode = expectedMode, success = data.success == true,
        timed_out = data.timed_out == true, collision_loaded = data.collision_loaded == true,
        scene_started = data.scene_started == true, scene_loaded = data.scene_loaded == true,
        duration_ms = math.floor(duration),
        error_code = type(data.error_code) == 'string' and data.error_code:sub(1, 64) or nil,
        error_message = type(data.error_message) == 'string' and data.error_message:sub(1, 512) or nil,
        stages = stages
    }
end
local function handleFeedback(src, feedback)
    local item = history[src]
    if not item then notify(src, '直近のリロードがないため報告できません。'); return end
    if item.feedback then notify(src, 'このリロードにはすでに報告済みです。'); return end
    if os.time() > item.feedback_expires_at then notify(src, '改善報告の期限が切れています。'); return end
    item.feedback = feedback
    invokeWorlddiag('RecordFeedback', src, item.reload_id, feedback)
    notify(src, feedback == 'fixed' and '「改善した」と報告しました（主観的な報告として記録）。' or '「改善しなかった」と報告しました（主観的な報告として記録）。')
end

RegisterCommand(Config.CommandName, function(source, args)
    local src = tonumber(source)
    if not src or src <= 0 then print('[reloadworld] このコマンドはゲーム内プレイヤー専用です。'); return end
    local arg = type(args[1]) == 'string' and args[1]:lower() or ''
    if arg == 'fixed' or arg == 'notfixed' then handleFeedback(src, arg); return end
    if arg ~= '' then notify(src, ('使用法: /%s [fixed|notfixed]'):format(Config.CommandName)); return end
    if not hasPermission(src) then notify(src, '実行権限がありません。'); return end
    local mode = 'normal'
    if active[src] then notify(src, 'すでに処理中です。'); return end
    local remaining = (cooldownUntil[src] or 0) - os.time()
    if remaining > 0 then notify(src, ('クールダウン中です。残り%d秒。'):format(remaining)); return end
    local safe, reason = knownUnfrozen(src)
    if not safe then
        notify(src, reason == 'already_frozen' and '既存リソースによる固定を保護するため、現在は実行できません。' or 'プレイヤーの固定状態を安全に確認できないため、実行を中止しました。')
        return
    end

    local reloadId = makeId('reload', src)
    cooldownUntil[src] = os.time() + Config.CooldownSeconds
    active[src] = { reload_id = reloadId, mode = mode, started_at = os.time() }
    notify(src, 'ワールド再読み込みを開始します。プレイヤースイッチと強制ストリーミングのため約20秒以上かかります。')
    local linked, diagnosticId = false, nil
    local ok, result = invokeWorlddiag('BeginReload', src, {
        reload_id = reloadId, mode = mode, server_started_utc = os.date('!%Y-%m-%dT%H:%M:%SZ') })
    if ok and type(result) == 'string' then linked, diagnosticId = true, result end
    active[src].diagnostic_id = diagnosticId
    CreateThread(function()
        if linked and Config.WorlddiagPreDelayMs > 0 then Wait(Config.WorlddiagPreDelayMs) end
        local current = active[src]
        if current and current.reload_id == reloadId and GetPlayerName(src) then
            TriggerClientEvent('reloadworld:client:start', src, reloadId, mode)
        end
    end)
    CreateThread(function()
        local maximum = Config.TimeoutMs + Config.WorlddiagPreDelayMs
            + math.max(Config.FadeDurationMs * 4, 2000) + 2000
        Wait(maximum)
        local current = active[src]
        if current and current.reload_id == reloadId then
            active[src] = nil
            history[src] = { reload_id = reloadId, diagnostic_id = current.diagnostic_id,
                completed_at = os.time(), feedback_expires_at = os.time() + Config.FeedbackExpirySeconds }
            local fallback = { reload_id = reloadId, mode = mode, success = false, timed_out = true,
                collision_loaded = false, scene_started = false, scene_loaded = false,
                duration_ms = maximum, error_code = 'client_response_timeout' }
            invokeWorlddiag('EndReload', src, fallback)
            notify(src, 'クライアント応答がタイムアウトしました。安全状態を確認してください。')
        end
    end)
end, false)

RegisterNetEvent('reloadworld:server:complete', function(reloadId, data)
    local src = source
    if type(reloadId) ~= 'string' or #reloadId > 96 then return end
    local current = active[src]
    if not current or current.reload_id ~= reloadId then return end
    local result = sanitizeResult(data, current.mode, reloadId)
    if not result then return end
    active[src] = nil
    history[src] = { reload_id = reloadId, diagnostic_id = current.diagnostic_id,
        completed_at = os.time(), feedback_expires_at = os.time() + Config.FeedbackExpirySeconds }
    invokeWorlddiag('EndReload', src, result)
    local seconds, label = result.duration_ms / 1000.0, 'ワールド再読み込み'
    if result.error_code == 'vehicle_unsafe' or result.error_code == 'vehicle_state_changed' then
        notify(src, '車両から降り、乗降動作が終わってから実行してください。')
    elseif result.error_code == 'screen_transition_active' then
        notify(src, '画面切り替え中です。画面が戻ってから再実行してください。')
    elseif result.error_code == 'player_switch_active' then
        notify(src, '既にプレイヤースイッチ中です。スポーン／観戦／カットシーン終了後に再実行してください。')
    elseif result.error_code then
        notify(src, ('%s：エラー（%s、%.1f秒）'):format(label, result.error_code, seconds))
    elseif result.timed_out then
        notify(src, ('%s：タイムアウト（%.1f秒）。表示改善の有無は別途確認してください。'):format(label, seconds))
    else
        notify(src, ('%s：読み込み確認完了（%.1f秒）。表示改善を保証する結果ではありません。'):format(label, seconds))
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    active[src], cooldownUntil[src], history[src] = nil, nil, nil
end)

