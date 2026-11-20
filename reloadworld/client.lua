local busy = false
local cleanupState = nil

local function clampInteger(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    value = math.floor(value)
    if value < minimum or value > maximum then return default end
    return value
end
Config.NormalTimeoutMs = clampInteger(Config.NormalTimeoutMs, 5000, 500, 30000)
Config.EnhancedTimeoutMs = clampInteger(Config.EnhancedTimeoutMs, 10000, 1000, 60000)
Config.FadeDurationMs = clampInteger(Config.FadeDurationMs, 350, 0, 5000)
Config.CollisionRequestIntervalMs = clampInteger(Config.CollisionRequestIntervalMs, 100, 0, 1000)
Config.EnhancedSceneRadius = tonumber(Config.EnhancedSceneRadius) or 120.0
if Config.EnhancedSceneRadius < 3.0 or Config.EnhancedSceneRadius > 1000.0 then Config.EnhancedSceneRadius = 120.0 end

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
        cleanupState = { ped = ped, frozenByUs = false, fadeStarted = false, sceneStarted = false }
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
        local basicDeadline = mode == 'enhanced'
            and math.min(deadline, GetGameTimer() + math.min(Config.NormalTimeoutMs, math.floor(timeoutMs / 2)))
            or deadline
        result.stages.basic = { started = true, loaded = false }
        while GetGameTimer() < basicDeadline do
            if not DoesEntityExist(ped) or IsEntityDead(ped) then result.error_code = 'ped_lost'; return end
            if isVehicleTransitionUnsafe(ped) then result.error_code = 'vehicle_state_changed'; return end
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
            if HasCollisionLoadedAroundEntity(ped) then
                result.collision_loaded = true; result.stages.basic.loaded = true; break
            end
            Wait(Config.CollisionRequestIntervalMs)
        end

        if mode == 'enhanced' and not result.collision_loaded and GetGameTimer() < deadline then
            result.stages.enhanced = { attempted = true, started = false, loaded = false }
            local headingRad = math.rad(GetEntityHeading(ped))
            local sceneOk = NewLoadSceneStart(coords.x, coords.y, coords.z,
                -math.sin(headingRad), math.cos(headingRad), 0.0,
                Config.EnhancedSceneRadius, 0)
            result.scene_started = sceneOk == true
            result.stages.enhanced.started = result.scene_started
            if result.scene_started then
                cleanupState.sceneStarted = true
                while GetGameTimer() < deadline do
                    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
                    RequestAdditionalCollisionAtCoord(coords.x, coords.y, coords.z)
                    if IsNewLoadSceneLoaded() then
                        result.scene_loaded = true; result.stages.enhanced.loaded = true
                    end
                    if HasCollisionLoadedAroundEntity(ped) then result.collision_loaded = true end
                    if result.scene_loaded and result.collision_loaded then break end
                    Wait(Config.CollisionRequestIntervalMs)
                end
                NewLoadSceneStop()
                cleanupState.sceneStarted = false
            end
        end
        result.timed_out = not result.collision_loaded
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

