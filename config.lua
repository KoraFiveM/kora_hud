Config = {}

-- Per-element toggles. Health, armour, and job/gang are NOT here -- they're
-- baseline "usual player data" rather than independently toggleable elements.
-- Dynamic mode can still suppress health/armour while they are neutral.
Config.hud = {
    -- When enabled, radial gauges only appear while they differ from their
    -- neutral value: full health/stamina/hunger/thirst/fuel and empty
    -- armour/stress are hidden. Non-gauge HUD elements are unaffected.
    -- Defaults to false so upgrading an existing server doesn't silently
    -- start hiding gauges players are used to always seeing -- opt in per
    -- server.
    dynamic = false,
    elements = {
        mic          = true,
        cash         = false,
        bank         = true,
        hungerThirst = true,
        stamina      = true,
        stress       = true,
        vehicle      = true, -- speed/fuel/engine/headlights/seatbelt, shown only while in a vehicle
    },
}

Config.bridge = {
    -- Which adapter to load (see fxmanifest.lua's client_scripts and
    -- shared/bridge.lua for the contract every adapter -- stub or real --
    -- must satisfy). Swapping in a real framework later means writing a new
    -- client/bridge/<adapter>.lua and changing this value plus the
    -- fxmanifest.lua script list; client/hud.lua itself never changes.
    adapter = "qbcore",
}

Config.voice = {
    enabled  = true,        -- master toggle for the mic indicator element
    resource = "pma-voice", -- name of the voice resource providing talk state; see client/voice.lua's documented assumption
}

Config.poll = {
    -- Four updates per second keeps the numeric speedometer responsive without
    -- making vehicle natives and Lua-to-NUI messages a hot 10Hz path.
    vehicleInterval = 250, -- ms between speed/fuel/engine/headlight refreshes while in a vehicle
    bridgeInterval  = 500, -- ms between HudBridge.getSnapshot() polls -- job/gang/cash/etc. don't need per-frame freshness
}
