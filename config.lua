Config = {}

-- Per-element toggles. Health, armour, and job/gang are NOT here -- they're
-- baseline "usual player data" and always render (see AGENTS.md).
Config.hud = {
    elements = {
        mic          = true,
        cash         = true,
        bank         = true,
        hungerThirst = true,
        stamina      = true,
        stress       = true,
        vehicle      = true, -- speed/fuel/engine/seatbelt, shown only while in a vehicle
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
    -- 10Hz is visually smooth for a HUD speedometer but avoids 50 Lua-to-NUI
    -- messages per second while driving. The browser can interpolate values
    -- between messages if a future skin wants a smoother needle.
    vehicleInterval = 100, -- ms between vehicle HUD refreshes (speed/fuel/engine) while in a vehicle
    bridgeInterval  = 500, -- ms between HudBridge.getSnapshot() polls -- job/gang/cash/etc. don't need per-frame freshness
}
