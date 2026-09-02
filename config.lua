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
    -- Mic state is a boolean with no change notification of its own, so it is
    -- the one input the HUD genuinely has to sample. 200ms is imperceptible
    -- on an indicator that only ever flips between two icons, and the sampler
    -- only exists while the HUD is visible AND the mic element is enabled.
    interval = 200,
}

Config.poll = {
    -- Every cadence below is a CEILING on how often a given wire message can
    -- leave Lua, not a timer that fires regardless: each channel is driven by
    -- a leading-edge throttle (see client/hud.lua's `throttle`), so an
    -- isolated change is sent the instant it happens and only a BURST is
    -- coalesced down to one message per interval. A HUD whose inputs are all
    -- quiet -- standing still, full stamina, no framework delta -- owns no
    -- running thread and sends nothing at all.

    -- Health/armour/stamina/talking. Stamina is the one field that moves
    -- continuously (every 100ms qblib cache tick for the whole length of a
    -- sprint), so this is the cadence that decides the resource's cost while
    -- moving. 100ms tracks the cache tick exactly -- anything faster only
    -- re-sends values that cannot have changed.
    vitalsInterval  = 100,

    -- Job/gang/cash/bank/hunger/thirst/stress/status. These are event-driven
    -- (the qbcore adapter pushes off qbcore's delta stream), so this interval
    -- only ever collapses a burst -- e.g. a full resync firing the adapter's
    -- money/job/gang/metadata subscriptions back-to-back within one frame.
    playerInterval  = 100,

    -- Four updates per second keeps the numeric speedometer responsive without
    -- making vehicle natives and Lua-to-NUI messages a hot 10Hz path.
    vehicleInterval = 250, -- ms between speed/fuel/engine/headlight refreshes while in a vehicle

    bridgeInterval  = 500, -- ms between HudBridge.getSnapshot() polls -- job/gang/cash/etc. don't need per-frame freshness

    -- How often SETUP_HEALTH_ARMOUR is re-issued to the minimap scaleform to
    -- keep the engine's own health/armour cluster suppressed (this resource's
    -- radial gauges render it instead). The usual snippet for this does it on
    -- a Wait(0) loop; a per-frame thread that exists purely to re-assert one
    -- unchanged flag was the single largest fixed cost in this resource, and
    -- the flag persists in the scaleform between calls, so re-asserting it a
    -- few times a second is enough.
    --
    -- Set to 0 to restore the per-frame behaviour. Do that only if the stock
    -- cluster visibly flickers back in on your build -- that would mean the
    -- engine is re-asserting its own default every frame after all, and the
    -- worst case here is up to this many ms of it showing through.
    minimapInterval = 250,
}
