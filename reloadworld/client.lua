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
Config.NormalTimeoutMs = clampInteger(Config.NormalTimeoutMs, 5000, 500, 30000)
Config.EnhancedTimeoutMs = clampInteger(Config.EnhancedTimeoutMs, 18000, 5000, 60000)
Config.FadeDurationMs = clampInteger(Config.FadeDurationMs, 350, 0, 5000)
Config.CollisionRequestIntervalMs = clampInteger(Config.CollisionRequestIntervalMs, 100, 0, 1000)
Config.EnhancedInitialRequestMs = clampInteger(Config.EnhancedInitialRequestMs, 1500, 250, 10000)
Config.EnhancedRemoteHoldMs = clampInteger(Config.EnhancedRemoteHoldMs, 4000, 500, 20000)
Config.EnhancedReturnHoldMs = clampInteger(Config.EnhancedReturnHoldMs, 5000, 500, 20000)
Config.EnhancedSceneRadius = clampNumber(Config.EnhancedSceneRadius, 120.0, 3.0, 1000.0)
Config.EnhancedRemoteFocusDistance = clampNumber(Config.EnhancedRemoteFocusDistance, 8000.0, 1000.0, 20000.0)
Config.EnhancedRemoteFocusHeight = clampNumber(Config.EnhancedRemoteFocusHeight, 1000.0, 0.0, 5000.0)
Config.EnhancedRemoteSceneRadius = clampNumber(Config.EnhancedRemoteSceneRadius, 50.0, 3.0, 1000.0)
if type(Config.EnhancedColdCycleEnabled) ~= 'boolean' then Config.EnhancedColdCycleEnabled = true end

local enhancedHoldBudget = math.max(1500, Config.EnhancedTimeoutMs - 2000)
local configuredHoldTotal = Config.EnhancedInitialRequestMs + Config.EnhancedRemoteHoldMs + Config.EnhancedReturnHoldMs
if configuredHoldTotal > enhancedHoldBudget then
    local scale = enhancedHoldBudget / configuredHoldTotal
    Config.EnhancedInitialRequestMs = math.max(250, math.floor(Config.EnhancedInitialRequestMs * scale))
    Config.EnhancedRemoteHoldMs = math.max(500, math.floor(Config.EnhancedRemoteHoldMs * scale))
    Config.EnhancedReturnHoldMs = math.max(500, math.floor(Config.EnhancedReturnHoldMs * scale))
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
    if state.focusOverridden then pcall(ClearFocus) end
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

        local coords = GetEntityCoords(ped)
        result.before = { x = coords.x, y = coords.y, z = coords.z,
            heading = GetEntityHeading(ped), speed = GetEntitySpeed(ped), falling = IsPedFalling(ped) }
        cleanupState = { ped = ped, frozenByUs = false, fadeStarted = false,
            sceneStarted = false, focusOverridden = false }
        DoScreenFadeOut(Config.FadeDurationMs)
        cleanupState.fadeStarted = true
        waitForFadeOut(math.max(Config.FadeDurationMs * 3, 1000))

        if not DoesEntityExist(ped) or IsEntityDead(ped) or isVehicleTransitionUnsafe(ped) then
            result.error_code = 'state_changed'; return
        end
        FreezeEntityPosition(ped, true)
        cleanupState.frozenByUs = true

        local timeoutMs = mode == 'enhanced' and Config.EnhancedTimeoutMs or Config.NormalTimeoutMs
        local deadline = GetGameTimer() + timeoutMs
        local basicDeadline = mode == 'enhanced' and math.min(deadline,
            GetGameTimer() + Config.EnhancedInitialRequestMs) or deadline
        result.stages.basic = { started = true, loaded = false }
        while GetGameTimer() < basicDeadline do
            local stateError = playerStateError(ped)
            if stateError then result.error_code = stateError; return end
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
            if HasCollisionLoadedAroundEntity(ped) then
                result.collision_loaded = true
                result.stages.basic.loaded = true
                if mode == 'normal' then break end
            end
            Wait(Config.CollisionRequestIntervalMs)
        end

        if mode == 'enhanced' and Config.EnhancedColdCycleEnabled and GetGameTimer() < deadline then
            result.stages.cold_cycle = { attempted = true, focus_set = false,
                scene_started = false, scene_loaded = false, hold_completed = false }
            local headingRad = math.rad(GetEntityHeading(ped))
            local remoteHeading = headingRad + math.pi
            local remoteX = coords.x + (math.cos(remoteHeading) * Config.EnhancedRemoteFocusDistance)
            local remoteY = coords.y + (math.sin(remoteHeading) * Config.EnhancedRemoteFocusDistance)
            local remoteZ = coords.z + Config.EnhancedRemoteFocusHeight

            SetFocusPosAndVel(remoteX, remoteY, remoteZ, 0.0, 0.0, 0.0)
            cleanupState.focusOverridden = true
            result.stages.cold_cycle.focus_set = true
            local remoteSceneStarted = NewLoadSceneStart(remoteX, remoteY, remoteZ,
                0.0, 0.0, 0.0, Config.EnhancedRemoteSceneRadius, 0) == true
            result.stages.cold_cycle.scene_started = remoteSceneStarted
            if remoteSceneStarted then cleanupState.sceneStarted = true end

            local remoteHoldEnd = math.min(deadline - Config.EnhancedReturnHoldMs - 500,
                GetGameTimer() + Config.EnhancedRemoteHoldMs)
            while GetGameTimer() < remoteHoldEnd do
                local stateError = playerStateError(ped)
                if stateError then result.error_code = stateError; return end
                if remoteSceneStarted and IsNewLoadSceneLoaded() then
                    result.stages.cold_cycle.scene_loaded = true
                end
                Wait(Config.CollisionRequestIntervalMs)
            end
            result.stages.cold_cycle.hold_completed = GetGameTimer() >= remoteHoldEnd
            stopLoadScene()

            result.stages.return_stream = { attempted = true, focus_set = false,
                scene_started = false, scene_loaded = false, collision_loaded = false,
                hold_completed = false }
            SetFocusPosAndVel(coords.x, coords.y, coords.z, 0.0, 0.0, 0.0)
            result.stages.return_stream.focus_set = true
            result.collision_loaded = false

            local headingNow = math.rad(GetEntityHeading(ped))
            local currentSceneStarted = NewLoadSceneStart(coords.x, coords.y, coords.z,
                -math.sin(headingNow), math.cos(headingNow), 0.0,
                Config.EnhancedSceneRadius, 0) == true
            result.scene_started = currentSceneStarted
            result.stages.return_stream.scene_started = currentSceneStarted
            if currentSceneStarted then
                cleanupState.sceneStarted = true
            end

            local returnHoldEnd = math.min(deadline, GetGameTimer() + Config.EnhancedReturnHoldMs)
            while GetGameTimer() < deadline do
                local stateError = playerStateError(ped)
                if stateError then result.error_code = stateError; return end
                RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
                if currentSceneStarted and IsNewLoadSceneLoaded() then
                    result.scene_loaded = true
                    result.stages.return_stream.scene_loaded = true
                end
                if HasCollisionLoadedAroundEntity(ped) then
                    result.collision_loaded = true
                    result.stages.return_stream.collision_loaded = true
                end
                if GetGameTimer() >= returnHoldEnd and result.collision_loaded
                    and (not currentSceneStarted or result.scene_loaded) then
                    break
                end
                Wait(Config.CollisionRequestIntervalMs)
            end
            result.stages.return_stream.hold_completed = GetGameTimer() >= returnHoldEnd
            stopLoadScene()
            clearStreamingFocus()
        elseif mode == 'enhanced' and GetGameTimer() < deadline then
            result.stages.return_stream = { attempted = true, focus_set = false,
                scene_started = false, scene_loaded = false, collision_loaded = false,
                hold_completed = false }
            local headingRad = math.rad(GetEntityHeading(ped))
            local sceneOk = NewLoadSceneStart(coords.x, coords.y, coords.z,
                -math.sin(headingRad), math.cos(headingRad), 0.0,
                Config.EnhancedSceneRadius, 0)
            result.scene_started = sceneOk == true
            result.stages.return_stream.scene_started = result.scene_started
            if result.scene_started then cleanupState.sceneStarted = true end
            local returnHoldEnd = math.min(deadline, GetGameTimer() + Config.EnhancedReturnHoldMs)
            while GetGameTimer() < deadline do
                local stateError = playerStateError(ped)
                if stateError then result.error_code = stateError; return end
                RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
                if result.scene_started and IsNewLoadSceneLoaded() then
                    result.scene_loaded = true
                    result.stages.return_stream.scene_loaded = true
                end
                if HasCollisionLoadedAroundEntity(ped) then
                    result.collision_loaded = true
                    result.stages.return_stream.collision_loaded = true
                end
                if GetGameTimer() >= returnHoldEnd and result.collision_loaded
                    and (not result.scene_started or result.scene_loaded) then break end
                Wait(Config.CollisionRequestIntervalMs)
            end
            result.stages.return_stream.hold_completed = GetGameTimer() >= returnHoldEnd
            stopLoadScene()
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
    if type(reloadId) ~= 'string' or #reloadId > 96 or (mode ~= 'normal' and mode ~= 'enhanced') then return end
    busy = true
    CreateThread(function() runReload(reloadId, mode) end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    cleanup(); busy = false
end)

