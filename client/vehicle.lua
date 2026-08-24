-- Vehicle telemetry (speed/fuel/engine). qblib's modules/entities and
-- modules/loops have no vehicle-telemetry helpers to build on, so this calls
-- natives directly. Crucially, it never owns a polling thread: client/hud.lua
-- is the single vehicle-only scheduler and calls getSnapshot only while
-- QB.cache.vehicle() says the local player is in a vehicle.
--
-- Seatbelt is deliberately not read here. Stock FiveM has no seatbelt native;
-- it remains bridge state and is refreshed by that same HUD vehicle tick.
Vehicle = Vehicle or {}

---@return { speed: number, fuel: number | nil, engineOn: boolean } | nil
function Vehicle.getSnapshot()
    -- The qblib cache is the single source of vehicle lifecycle truth. This
    -- avoids a second IsPedInAnyVehicle loop in qbhud and guarantees no vehicle
    -- native is touched while the player is on foot.
    local vehicle = QB.cache.vehicle()
    if not vehicle then return nil end

    -- GetVehicleFuelLevel and IsVehicleEngineRunning are not guaranteed on all
    -- FiveM builds; degrade each optional value instead of losing the entire HUD.
    local fuelOk, fuel = pcall(GetVehicleFuelLevel, vehicle)
    local engineOk, engineOn = pcall(IsVehicleEngineRunning, vehicle)

    return {
        speed = GetEntitySpeed(vehicle) * 3.6, -- m/s -> km/h
        fuel = fuelOk and fuel or nil,
        engineOn = engineOk and engineOn == true,
    }
end
