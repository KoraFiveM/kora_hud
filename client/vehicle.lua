-- Vehicle telemetry (speed/fuel/engine/headlights). qblib's modules/entities and
-- modules/loops have no vehicle-telemetry helpers to build on, so this calls
-- natives directly. Crucially, it never owns a polling thread: client/hud.lua
-- is the single vehicle-only scheduler and calls getSnapshot only while
-- QB.cache.vehicle() says the local player is in a vehicle.
--
-- Seatbelt is deliberately not read here. Stock FiveM has no seatbelt native;
-- it remains bridge state and is refreshed by that same HUD vehicle tick.
Vehicle = Vehicle or {}

---@param vehicle integer|false|nil The caller's already-known vehicle handle. Every
---QB.<module>.<fn> access is a cross-resource export call, so the sampling loop
---in client/hud.lua -- which is already handed the handle by
---QB.cache.onChange('vehicle') -- passes it in rather than paying for that
---crossing four times a second to re-ask for a value it was pushed. Omitted,
---this falls back to the cache read, so a caller with no handle of its own
---(and the standalone smoke test) still works unchanged.
---@return { speed: number, fuel: number | nil, engineOn: boolean, headlights: 'off'|'low'|'high' } | nil
function Vehicle.getSnapshot(vehicle)
    -- The qblib cache is the single source of vehicle lifecycle truth. This
    -- avoids a second IsPedInAnyVehicle loop in qbhud and guarantees no vehicle
    -- native is touched while the player is on foot.
    if vehicle == nil then vehicle = QB.cache.vehicle() end
    if not vehicle then return nil end

    -- GetVehicleFuelLevel and IsVehicleEngineRunning are not guaranteed on all
    -- FiveM builds; degrade each optional value instead of losing the entire HUD.
    local fuelOk, fuel = pcall(GetVehicleFuelLevel, vehicle)
    local engineOk, engineOn = pcall(IsVehicleEngineRunning, vehicle)
    local lightsOk, _, lightsOn, highbeamsOn = pcall(GetVehicleLightsState, vehicle)

    local headlights = 'off'
    if lightsOk then
        if highbeamsOn == true then
            headlights = 'high'
        elseif lightsOn == true then
            headlights = 'low'
        end
    end

    return {
        speed = GetEntitySpeed(vehicle) * 3.6, -- m/s -> km/h
        fuel = fuelOk and fuel or nil,
        engineOn = engineOk and engineOn == true,
        headlights = headlights,
    }
end
