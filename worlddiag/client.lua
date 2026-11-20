local collecting = false

local function notify(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('[worlddiag] %s'):format(message))
    EndTextCommandThefeedPostTicker(false, true)
end

RegisterNetEvent('worlddiag:client:notify', function(message)
    if type(message) == 'string' and #message <= 256 then notify(message) end
end)

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

local function collectDiagnostic(requestId, options)
    local started = GetGameTimer()
    local data = {
        request_id = requestId,
        client_measurement = {
            source = 'client_native',
            measured_game_timer_ms = started
        },
        quality = {}
    }
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then
        data.quality.ped = { success = false, reason = 'ped_unavailable' }
        return data
    end
    data.quality.ped = { success = true }

    if options.fields.position then
        local coords = GetEntityCoords(ped)
        data.position = { x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped) }
    end
    local inVehicle = IsPedInAnyVehicle(ped, false)
    if options.fields.movement then
        data.movement = {
            speed_mps = GetEntitySpeed(ped),
            on_foot = not inVehicle,
            falling = IsPedFalling(ped),
            getting_into_vehicle = IsPedGettingIntoAVehicle(ped)
        }
    end
    if options.fields.vehicle then
        data.vehicle = { in_vehicle = inVehicle }
        if inVehicle then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and DoesEntityExist(vehicle) then
                data.vehicle.model_hash = tostring(GetEntityModel(vehicle))
                data.vehicle.speed_mps = GetEntitySpeed(vehicle)
                data.vehicle.quality = { success = true, source = 'client_native' }
            else
                data.vehicle.quality = { success = false, reason = 'vehicle_entity_unavailable' }
            end
        end
    end
    if options.fields.collision then
        data.collision = {
            loaded_around_ped = HasCollisionLoadedAroundEntity(ped),
            source = 'client_native',
            note = 'Native state does not prove that visible map assets are correct.'
        }
    end
    if options.fields.fps then
        local requested = math.max(1, math.min(120, tonumber(options.fps_sample_count) or 30))
        local total, accepted = 0.0, 0
        for _ = 1, requested do
            Wait(0)
            local frame = GetFrameTime()
            if finite(frame) and frame > 0.0 and frame < 1.0 then
                total, accepted = total + frame, accepted + 1
            end
        end
        if accepted > 0 then
            local average = total / accepted
            data.fps = {
                estimated = 1.0 / average,
                average_frame_time_ms = average * 1000.0,
                samples_requested = requested,
                samples_accepted = accepted,
                method = 'arithmetic mean of GetFrameTime over consecutive rendered frames',
                source = 'client_native'
            }
        else
            data.fps = { samples_requested = requested, samples_accepted = 0,
                method = 'GetFrameTime', source = 'client_native', unavailable_reason = 'no_valid_samples' }
        end
    end
    if options.fields.environment then
        data.environment = {
            game_build = GetGameBuildNumber(),
            game_name = GetGameName(),
            source = 'client_cfx_native'
        }
    end
    data.client_measurement.completed_game_timer_ms = GetGameTimer()
    data.client_measurement.duration_ms = data.client_measurement.completed_game_timer_ms - started
    return data
end

RegisterNetEvent('worlddiag:client:collect', function(requestId, options)
    if type(requestId) ~= 'string' or #requestId > 96 or type(options) ~= 'table' then return end
    if type(options.fields) ~= 'table' then return end
    if collecting then
        TriggerServerEvent('worlddiag:server:response', requestId, {
            request_id = requestId,
            quality = { collection = { success = false, reason = 'client_busy' } }
        })
        return
    end
    collecting = true
    CreateThread(function()
        local ok, result = xpcall(function() return collectDiagnostic(requestId, options) end, debug.traceback)
        collecting = false
        if not ok then
            result = { request_id = requestId,
                quality = { collection = { success = false, reason = 'client_exception', detail = tostring(result):sub(1, 256) } } }
        end
        TriggerServerEvent('worlddiag:server:response', requestId, result)
    end)
end)

