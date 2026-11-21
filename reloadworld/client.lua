local busy = false
local cleanupState = nil

local function clampInteger(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    value = math.floor(value)
    if value < minimum or value > maximum then return default end
    return value
end
local function clampNumber(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value or value <= -math.huge or value >= math.huge then return default end
    if value < minimum or value > maximum then return default end
    return value
end
Config.TimeoutMs = clampInteger(Config.TimeoutMs, 30000, 10000, 90000)
Config.FadeDurationMs = clampInteger(Config.FadeDurationMs, 350, 0, 5000)
Config.CollisionRequestIntervalMs = clampInteger(Config.CollisionRequestIntervalMs, 100, 0, 1000)
Config.InitialRequestMs = clampInteger(Config.InitialRequestMs, 1500, 250, 10000)
Config.SwitchOutHoldMs = clampInteger(Config.SwitchOutHoldMs, 6000, 1000, 20000)
Config.SwitchReturnTimeoutMs = clampInteger(Config.SwitchReturnTimeoutMs, 7000, 1000, 20000)
Config.LocalHoldMs = clampInteger(Config.LocalHoldMs, 8000, 1000, 30000)
Config.SceneRadius = clampNumber(Config.SceneRadius, 180.0, 10.0, 1000.0)
Config.HdRadius = clampNumber(Config.HdRadius, 250.0, 10.0, 1000.0)
if type(Config.PlayerSwitchEnabled) ~= 'boolean' then Config.PlayerSwitchEnabled = true end
if type(Config.HdAreaEnabled) ~= 'boolean' then Config.HdAreaEnabled = true end
if type(Config.LoadAllObjectsNow) ~= 'boolean' then Config.LoadAllObjectsNow = true end

local holdBudget = math.max(1500, Config.TimeoutMs - 2000)
local configuredHoldTotal = Config.InitialRequestMs + Config.SwitchOutHoldMs
    + Config.SwitchReturnTimeoutMs + Config.LocalHoldMs
if configuredHoldTotal > holdBudget then
    local scale = holdBudget / configuredHoldTotal
    Config.InitialRequestMs = math.max(250, math.floor(Config.InitialRequestMs * scale))
    Config.SwitchOutHoldMs = math.max(1000, math.floor(Config.SwitchOutHoldMs * scale))
    Config.SwitchReturnTimeoutMs = math.max(1000, math.floor(Config.SwitchReturnTimeoutMs * scale))
    Config.LocalHoldMs = math.max(1000, math.floor(Config.LocalHoldMs * scale))
end

local function debugLog(message)
    if Config.Debug then print(('[reloadworld] %s'):format(message)) end
end

local function notify(message)
    if not Config.Notifications then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('[reloadworld] %s'):format(message))
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent('reloadworld:client:notify', function(message)
    if type(message) == 'string' and #message <= 256 then notify(message) end
end)

local function isVehicleTransitionUnsafe(ped)
    if IsPedInAnyVehicle(ped, false) then return true end
    if IsPedGettingIntoAVehicle(ped) then return true end
    if IsPedJumpingOutOfVehicle(ped) then return true end
    return GetVehiclePedIsTryingToEnter(ped) ~= 0
end

local function cleanup()
    local state = cleanupState
    cleanupState = nil
    if not state then return end
    if state.sceneStarted then pcall(NewLoadSceneStop) end
    if state.hdAreaSet then pcall(ClearHdArea) end
    if state.focusOverridden then pcall(ClearFocus) end
    if state.playerSwitchStarted then pcall(StopPlayerSwitch) end
    if state.frozenByUs and state.ped and DoesEntityExist(state.ped) then
        pcall(FreezeEntityPosition, state.ped, false)
    end
    if state.fadeStarted then pcall(DoScreenFadeIn, Config.FadeDurationMs) end
end

local function waitForFadeOut(timeoutMs)
    local started = GetGameTimer()
    while not IsScreenFadedOut() and (GetGameTimer() - started) < timeoutMs do Wait(0) end
    return IsScreenFadedOut()
end

local function playerStateError(ped)
    if not DoesEntityExist(ped) or IsEntityDead(ped) then return 'ped_lost' end
    if isVehicleTransitionUnsafe(ped) then return 'vehicle_state_changed' end
    return nil
end

local function stopLoadScene()
    if cleanupState and cleanupState.sceneStarted then
        NewLoadSceneStop()
        cleanupState.sceneStarted = false
    end
end

local function clearStreamingFocus()
    if cleanupState and cleanupState.focusOverridden then
        ClearFocus()
        cleanupState.focusOverridden = false
    end
end

local function clearRecoveryHdArea()
    if cleanupState and cleanupState.hdAreaSet then
        ClearHdArea()
        cleanupState.hdAreaSet = false
    end
end

local function runReload(reloadId, mode)
    local started = GetGameTimer()
    local result = {
        reload_id = reloadId, mode = mode, success = false, timed_out = false,
        collision_loaded = false, scene_started = false, scene_loaded = false,
        stages = {}, error_code = nil
    }
    local ok, err = xpcall(function()
        local ped = PlayerPedId()
        if ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then
            result.error_code = 'ped_unavailable'; return
        end
        if isVehicleTransitionUnsafe(ped) then result.error_code = 'vehicle_unsafe'; return end
        if IsScreenFadedOut() or IsScreenFadingOut() or IsScreenFadingIn() then
            result.error_code = 'screen_transition_active'; return
        end
        if IsPlayerSwitchInProgress() then
            result.error_code = 'player_switch_active'; return
        end

        local coords = GetEntityCoords(ped)
        result.before = { x = coords.x, y = coords.y, z = coords.z,
            heading = GetEntityHeading(ped), speed = GetEntitySpeed(ped), falling = IsPedFalling(ped) }
        cleanupState = { ped = ped, frozenByUs = false, fadeStarted = false,
            sceneStarted = false, focusOverridden = false, hdAreaSet = false,
            playerSwitchStarted = false }
        DoScreenFadeOut(Config.FadeDurationMs)
        cleanupState.fadeStarted = true
        waitForFadeOut(math.max(Config.FadeDurationMs * 3, 1000))

        if not DoesEntityExist(ped) or IsEntityDead(ped) or isVehicleTransitionUnsafe(ped) then
            result.error_code = 'state_changed'; return
        end
        FreezeEntityPosition(ped, true)
        cleanupState.frozenByUs = true

        local deadline = GetGameTimer() + Config.TimeoutMs
        local basicDeadline = math.min(deadline, GetGameTimer() + Config.InitialRequestMs)
        result.stages.basic = { started = true, loaded = false }
        while GetGameTimer() < basicDeadline do
            local stateError = playerStateError(ped)
            if stateError then result.error_code = stateError; return end
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
            if HasCollisionLoadedAroundEntity(ped) then
                result.collision_loaded = true
                result.stages.basic.loaded = true
            end
            Wait(Config.CollisionRequestIntervalMs)
        end

        if GetGameTimer() < deadline then
            result.stages.player_switch = { attempted = Config.PlayerSwitchEnabled,
                started = false, out_hold_completed = false, return_started = false,
                completed = false, forced_stop = false }

            if Config.PlayerSwitchEnabled then
                SwitchToMultiFirstPart(ped, 0, 1)
                cleanupState.playerSwitchStarted = true

                local switchStartDeadline = math.min(deadline, GetGameTimer() + 1500)
                while not IsPlayerSwitchInProgress() and GetGameTimer() < switchStartDeadline do
                    local stateError = playerStateError(ped)
                    if stateError then result.error_code = stateError; return end
                    Wait(0)
                end
                result.stages.player_switch.started = IsPlayerSwitchInProgress()

                if result.stages.player_switch.started then
                    local outHoldEnd = math.min(GetGameTimer() + Config.SwitchOutHoldMs,
                        deadline - Config.SwitchReturnTimeoutMs - Config.LocalHoldMs)
                    while IsPlayerSwitchInProgress() and GetGameTimer() < outHoldEnd do
                        local stateError = playerStateError(ped)
                        if stateError then result.error_code = stateError; return end
                        Wait(Config.CollisionRequestIntervalMs)
                    end
                    result.stages.player_switch.out_hold_completed = GetGameTimer() >= outHoldEnd

                    SwitchToMultiSecondPart(ped)
                    result.stages.player_switch.return_started = true
                    local switchReturnDeadline = math.min(
                        GetGameTimer() + Config.SwitchReturnTimeoutMs,
                        deadline - Config.LocalHoldMs)
                    while IsPlayerSwitchInProgress() and GetGameTimer() < switchReturnDeadline do
                        local stateError = playerStateError(ped)
                        if stateError then result.error_code = stateError; return end
                        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                        RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
                        Wait(Config.CollisionRequestIntervalMs)
                    end
                    result.stages.player_switch.completed = not IsPlayerSwitchInProgress()
                end

                if IsPlayerSwitchInProgress() then
                    StopPlayerSwitch()
                    result.stages.player_switch.forced_stop = true
                end
                cleanupState.playerSwitchStarted = false
            end

            result.stages.local_stream = { attempted = true, focus_set = false,
                hd_area_set = false, load_scene_called = false, objects_forced = false,
                scene_started = false, scene_loaded = false, collision_loaded = false,
                hold_completed = false }
            result.collision_loaded = false

            SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
            cleanupState.focusOverridden = true
            result.stages.local_stream.focus_set = true

            if Config.HdAreaEnabled then
                SetHdArea(coords.x, coords.y, coords.z, Config.HdRadius)
                cleanupState.hdAreaSet = true
                result.stages.local_stream.hd_area_set = true
            end

            local loadSceneOk = pcall(LoadScene, coords.x, coords.y, coords.z)
            result.stages.local_stream.load_scene_called = loadSceneOk
            if Config.LoadAllObjectsNow then
                result.stages.local_stream.objects_forced = pcall(LoadAllObjectsNow)
            end

            local sceneOk = NewLoadSceneStartSphere(coords.x, coords.y, coords.z,
                Config.SceneRadius, 0)
            result.scene_started = sceneOk == true
            result.stages.local_stream.scene_started = result.scene_started
            if result.scene_started then cleanupState.sceneStarted = true end

            local localHoldEnd = math.min(deadline, GetGameTimer() + Config.LocalHoldMs)
            while GetGameTimer() < deadline do
                local stateError = playerStateError(ped)
                if stateError then result.error_code = stateError; return end
                RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
                if result.scene_started and IsNewLoadSceneLoaded() then
                    result.scene_loaded = true
                    result.stages.local_stream.scene_loaded = true
                end
                if HasCollisionLoadedAroundEntity(ped) then
                    result.collision_loaded = true
                    result.stages.local_stream.collision_loaded = true
                end
                if GetGameTimer() >= localHoldEnd and result.collision_loaded
                    and (not result.scene_started or result.scene_loaded) then break end
                Wait(Config.CollisionRequestIntervalMs)
            end
            result.stages.local_stream.hold_completed = GetGameTimer() >= localHoldEnd
            stopLoadScene()
            clearRecoveryHdArea()
            clearStreamingFocus()
        end
        result.timed_out = not result.collision_loaded
            or (result.scene_started and not result.scene_loaded)
        result.success = result.collision_loaded
    end, debug.traceback)
    if not ok then
        result.error_code = 'client_exception'
        result.error_message = tostring(err):sub(1, 512)
        debugLog(result.error_message)
    end
    cleanup()
    result.duration_ms = math.max(0, GetGameTimer() - started)
    busy = false
    TriggerServerEvent('reloadworld:server:complete', reloadId, result)
end

RegisterNetEvent('reloadworld:client:start', function(reloadId, mode)
    if busy then
        TriggerServerEvent('reloadworld:server:complete', reloadId, {
            reload_id = reloadId, mode = mode, success = false, timed_out = false,
            duration_ms = 0, error_code = 'client_busy' })
        return
    end
    if type(reloadId) ~= 'string' or #reloadId > 96 or mode ~= 'normal' then return end
    busy = true
    CreateThread(function() runReload(reloadId, mode) end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanup(); busy = false
end)

