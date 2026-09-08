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
        cash         = true,
        bank         = true,
        hungerThirst = true,
        stamina      = true,
        stress       = true,
        vehicle      = true, -- speed/fuel/engine/headlights/seatbelt, shown only while in a vehicle
    },

    -- Money display. Off by default: cash and bank shown side by side is the
    -- existing behaviour, and an upgrading server should not silently start
    -- hiding half of it.
    money = {
        -- Show one account at a time, alternating. Useful where the HUD is
        -- crowded, or where two money rows read as clutter.
        scrollAccounts = true,
        -- ms each account is shown for before switching to the other. Only
        -- meaningful while scrollAccounts is true, and only when BOTH
        -- `elements.cash` and `elements.bank` are enabled -- with one of them
        -- off there is nothing to alternate with.
        scrollAccountsTime = 5000,
    },

    -- Minimap visibility.
    --   'always'  -- leave the radar exactly as the game left it. qbhud does
    --              not touch DisplayRadar at all in this mode, so another
    --              resource hiding the radar for a cutscene still works.
    --   'vehicle' -- only while the player is in a vehicle.
    --   'never'   -- always hidden.
    minimap = 'vehicle',

    -- Unit used by the vehicle speedometer.
    --   'kmh' -- kilometres per hour
    --   'mph' -- miles per hour
    speedUnit = 'kmh',
}

-- Per-player HUD layout. Each section can be dragged to a new position and the
-- result is saved on that player's own machine, so it survives a reconnect
-- without a database column or a server round trip.
Config.layout = {
    -- Set false to pin the layout for everyone; /hudlayout then reports that
    -- moving sections is disabled rather than opening the editor.
    movable = true,
    -- Command that enters layout edit mode. Confirm or Cancel in the editor
    -- leaves it. The HUD is
    -- pointer-transparent during normal play and must stay that way, so
    -- dragging is only possible inside this explicit mode.
    command = 'hudlayout',
    -- FiveM KVP key the saved offsets are written to, as JSON. Client-side
    -- storage only -- nothing here ever reaches the server.
    kvpKey = 'qbhud:layout',
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
    -- Resource that describes the current proximity mode through
    -- getTalkingMode() -> { index, name, label, range }. qbvoice exposes this
    -- directly; a replacement voice resource can implement the same small
    -- presentation-only contract without coupling the HUD to its internals.
    resource = "qbvoice",
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
    -- the player is moving.
    --
    -- This value is forwarded to the NUI, which sets its gauge animation to
    -- match, so the rings interpolate exactly between samples rather than
    -- stepping. That makes this a pure cost knob: raising it cuts the message
    -- rate and the visible result is identical. What it does trade is the
    -- worst-case age of a value -- and only for a SECOND change inside one
    -- interval, since the first of any burst is sent on the frame it happens.
    vitalsInterval  = 150,

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

-- Registers this resource-owned configuration with qblib without changing its public Config table.
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
