-- Orchestrator: the only file that talks to the NUI. Combines qblib's cache
-- (health/armour, push-driven via onChange), client/voice.lua, client/vehicle.lua,
-- and HudBridge (the configured adapter, currently client/bridge/stub.lua)
-- into one consolidated payload per tick, rather than one NUI message per
-- element -- so the NUI side has a single wire contract to keep in sync
-- (web/src/lib/types.ts).
local latestBridgeSnapshot = HudBridge.getSnapshot()

-- An adapter with no login/character-select concept (the stub) has nothing
-- to gate on, so a missing isLoggedIn means "always visible" -- unchanged
-- behaviour for that adapter.
local function currentlyLoggedIn()
    if HudBridge.isLoggedIn then return HudBridge.isLoggedIn() end
    return true
end

local visible = currentlyLoggedIn()

local function buildVehiclePayload()
    local snapshot = Vehicle.getSnapshot()
    if not snapshot then return nil end

    return {
        speed = snapshot.speed,
        fuel = snapshot.fuel,
        engineOn = snapshot.engineOn,
        seatbelt = latestBridgeSnapshot.seatbelt,
    }
end

local function pushUpdate()
    if not visible then return end

    QB.nui.send("qbhud:update", {
        health = QB.cache.health(),
        armour = QB.cache.armour(),
        -- Not in qblib's cache (out of scope for that module -- only
        -- health/armour were added there) -- read directly here instead,
        -- same as vehicle telemetry. GetPlayerStamina already returns 0-100.
        stamina = GetPlayerStamina(QB.cache.playerId()),
        talking = Voice.isTalking(),
        job = latestBridgeSnapshot.job,
        gang = latestBridgeSnapshot.gang,
        cash = latestBridgeSnapshot.cash,
        bank = latestBridgeSnapshot.bank,
        hunger = latestBridgeSnapshot.hunger,
        thirst = latestBridgeSnapshot.thirst,
        stress = latestBridgeSnapshot.stress,
        vehicle = buildVehiclePayload(),
    })
end

-- Push-driven for anything that already has cheap change notification --
-- these fire immediately instead of waiting for the next poll tick below.
QB.cache.onChange("health", pushUpdate)
QB.cache.onChange("armour", pushUpdate)
QB.cache.onChange("vehicle", pushUpdate)
Voice.onChange(pushUpdate)

-- Show/hide immediately on a login transition rather than waiting for the
-- next poll tick -- e.g. qbcore's adapter pushes this off QBCore:Client:On-
-- PlayerLoaded/OnPlayerUnload. Adapters with no login concept (the stub)
-- don't implement onLoginChange, so this is a no-op for them and the HUD
-- stays visible per currentlyLoggedIn()'s default above.
if HudBridge.onLoginChange then
    HudBridge.onLoginChange(function(loggedIn)
        visible = loggedIn
        QB.nui.send("qbhud:visibility", visible)

        if visible then
            latestBridgeSnapshot = HudBridge.getSnapshot()
            pushUpdate()
        end
    end)
end

CreateThread(function()
    QB.nui.send("qbhud:config", { elements = Config.hud.elements })
    QB.nui.send("qbhud:theme", QB.theme.tokens())
    QB.nui.send("qbhud:visibility", visible)

    while true do
        latestBridgeSnapshot = HudBridge.getSnapshot()
        pushUpdate()

        -- Fast enough to track speed/fuel smoothly while driving; otherwise
        -- only as often as bridge-sourced fields (job/cash/hunger/etc.) need
        -- refreshing. One shared loop rather than two separate always-on
        -- threads -- both intervals are still honoured, just not
        -- simultaneously.
        Wait(QB.cache.vehicle() and Config.poll.vehicleInterval or Config.poll.bridgeInterval)
    end
end)
