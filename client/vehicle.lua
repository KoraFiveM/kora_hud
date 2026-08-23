-- Vehicle telemetry (speed/fuel/engine). qblib's modules/entities and
-- modules/loops have no vehicle-telemetry helpers to build on (entities is
-- spawn/despawn only) -- so this calls natives directly. Seatbelt state is
-- NOT read here: stock FiveM has no seatbelt native at all (that's a
-- framework-added mechanic), so it comes from HudBridge.getSnapshot().seatbelt
-- instead -- see shared/bridge.lua.
Vehicle = Vehicle or {}

local snapshot = false -- false when not in a vehicle, else { speed, fuel, engineOn }

local function readSnapshot(vehicle)
    -- GetVehicleFuelLevel and IsVehicleEngineRunning aren't present on every
    -- FiveM build/patch (or every server config -- some headless/CI runtimes
    -- expose only a subset of natives); degrade to nil/false rather than
    -- erroring the whole thread if either is missing.
    local fuelOk, fuel = pcall(GetVehicleFuelLevel, vehicle)
    local engineOk, engineOn = pcall(IsVehicleEngineRunning, vehicle)

    return {
        speed = GetEntitySpeed(vehicle) * 3.6, -- m/s -> km/h
        fuel = fuelOk and fuel or nil,
        engineOn = engineOk and engineOn == true,
    }
end

-- Lazily started/stopped as the player enters/exits a vehicle -- mirrors
-- qblib's modules/zones lazy tick-thread pattern -- rather than a bare
-- always-running CreateThread, so this costs nothing while on foot.
local function startTickThread()
    CreateThread(function()
        while true do
            local vehicle = QB.cache.vehicle()
            if not vehicle then
                snapshot = false
                return
            end

            snapshot = readSnapshot(vehicle)
            Wait(Config.poll.vehicleInterval)
        end
    end)
end

QB.cache.onChange("vehicle", function(vehicle)
    if vehicle then startTickThread() end
end)

-- Cover the case where this resource starts while already in a vehicle
-- (e.g. a resource restart) -- onChange alone only fires on the next actual
-- transition.
if QB.cache.vehicle() then
    startTickThread()
end

---@return { speed: number, fuel: number | nil, engineOn: boolean } | false
function Vehicle.getSnapshot()
    return snapshot
end
