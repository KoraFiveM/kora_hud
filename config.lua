Config = {}

-- Descriptors are optional so the configuration remains compatible with an
-- older kora_lib during a rolling upgrade.
local configEnum = QB and QB.config and QB.config.enum
local configInteger = QB and QB.config and QB.config.integer
local configBoolean = QB and QB.config and QB.config.boolean
local configNumber = QB and QB.config and QB.config.number

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
    --   'always'  -- leave the radar exactly as the game left it. kora_hud does
    --              not touch DisplayRadar at all in this mode, so another
    --              resource hiding the radar for a cutscene still works.
    --   'vehicle' -- only while the player is in a vehicle.
    --   'never'   -- always hidden.
    minimap = 'vehicle',

    -- While another resource force-hides the HUD (exports.kora_hud:hide(), as
    -- kora_clothing does for its menu) also keep the radar hidden, and let
    -- `minimap` above take over again on show(). Set false for the old
    -- behaviour: the radar is handed back as visible, which with
    -- minimap = 'vehicle' shows it on foot. Logout and resource stop always
    -- restore the radar. Read live, so changes apply on the next hide().
    hideMinimapWhenForcedHidden = configBoolean and configBoolean(true, {
        label = 'Hide minimap with forced-hidden HUD',
        description = 'Keeps the minimap hidden while another resource hides the HUD, such as a clothing menu, and returns it to the minimap mode when the HUD is shown again. When off, the minimap is handed back as visible instead, which shows it on foot in vehicle mode.',
        live = true,
    }) or true,

    -- Optional minimap layout. When enabled, kora_hud positions the minimap,
    -- its mask and its border/blur frame from one calculation (vanilla 16:9
    -- sizes, widths scaled for other aspect ratios) so they stay aligned at
    -- every aspect ratio and GTA safezone size, re-applied automatically when
    -- either changes. Off by default: the stock minimap is left untouched.
    -- Read live.
    minimapLayout = {
        -- Default false: kora_hud does not touch the minimap components or the
        -- bigmap at all, and exports.kora_hud:applyMinimapLayout() returns
        -- false. Opt in per server if the stock minimap overruns its border.
        enabled = configBoolean and configBoolean(false, {
            label = 'Manage minimap layout (off = stock minimap)',
            description = 'Off by default, which leaves the stock GTA minimap alone. When on, the HUD positions the minimap, mask and border together at vanilla size so the map stays inside its frame across aspect ratios and safezone sizes. Leave off if another resource positions the minimap.',
            live = true,
        }) or false,
        -- Screen-fraction offsets applied to the whole minimap (positive x is
        -- right, positive y is down). Default 0: the calculated position.
        x = configNumber and configNumber(0.0, {
            label = 'Minimap X offset',
            description = 'Moves the whole minimap horizontally as a fraction of the screen width; positive moves right.',
            min = -0.5, max = 0.5, step = 0.001, live = true,
        }) or 0.0,
        y = configNumber and configNumber(0.0, {
            label = 'Minimap Y offset',
            description = 'Moves the whole minimap vertically as a fraction of the screen height; positive moves down.',
            min = -0.5, max = 0.5, step = 0.001, live = true,
        }) or 0.0,
        -- Size multiplier for map, mask and border together. Default 1.0.
        scale = configNumber and configNumber(1.0, {
            label = 'Minimap size scale',
            description = 'Scales the minimap, its mask and its border together; 1.0 is the stock size.',
            min = 0.5, max = 2.0, step = 0.01, live = true,
        }) or 1.0,
        -- Fraction of the safezone margin to cancel. The engine already keeps
        -- the minimap inside the safezone, so 0 is correct unless the mask
        -- drifts from the border at small safezones on your build.
        safezoneCompensation = configNumber and configNumber(0.0, {
            label = 'Safezone compensation',
            description = 'Cancels this fraction of the GTA safezone margin for the minimap. Leave at 0 unless the map drifts from its border when the safezone slider is lowered.',
            min = 0.0, max = 2.0, step = 0.05, live = true,
            advanced = true,
        }) or 0.0,
        -- Fine offsets for one component, to correct a single layer that is a
        -- hair off on your setup (screen fractions, same signs as above).
        offsets = {
            map  = { x = 0.0, y = 0.0 },
            mask = { x = 0.0, y = 0.0 },
            blur = { x = 0.0, y = 0.0 },
        },
    },

    -- Unit used by the vehicle speedometer.
    --   'kmh' -- kilometres per hour
    --   'mph' -- miles per hour
    speedUnit = configEnum and configEnum('kmh', {
        label = 'Speed unit',
        description = 'Selects the unit displayed by the live vehicle speedometer. Kilometres per hour uses the game speed multiplied by 3.6, while miles per hour uses 2.236936; saving updates the active HUD immediately.',
        options = { 'kmh', 'mph' },
        live = true,
    }) or 'kmh',
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

-- Seatbelt feedback. The seatbelt itself lives in kora_utils; kora_hud only
-- plays the sound when that state changes. All values are read each time a
-- sound plays, so edits apply without a restart.
Config.seatbelt = {
    sound = {
        enabled = configBoolean and configBoolean(true, {
            label = 'Seatbelt sounds',
            description = 'Plays a buckle sound when the seatbelt goes on and a different unbuckle sound when it comes off, for the local player only. Turn off on servers that already play their own seatbelt audio.',
            live = true,
        }) or true,
        volume = configNumber and configNumber(0.5, {
            label = 'Seatbelt sound volume',
            description = 'Volume of the buckle and unbuckle sounds from 0.0 (silent) to 1.0 (full). Only applies to the bundled NUI sounds; native frontend sounds cannot be scaled.',
            min = 0.0, max = 1.0, step = 0.05, live = true,
        }) or 0.5,
        -- 'nui'    -- play the bundled files below from the HUD page. Needs no
        --             other resource and honours `volume`.
        -- 'native' -- GTA frontend sounds (PlaySoundFrontend), fixed volume. Use if
        --             the NUI audio is unavailable on a client.
        backend = configEnum and configEnum('nui', {
            label = 'Seatbelt sound backend',
            description = 'Chooses how seatbelt sounds are played. NUI plays the bundled audio files at the configured volume; native uses GTA frontend sounds at a fixed volume.',
            options = { 'nui', 'native' },
            live = true,
        }) or 'nui',
        -- File names inside web/build/sounds (source: web/public/sounds). Any
        -- file you add there must also be listed in fxmanifest.lua `files`.
        buckleFile = 'seatbelt_buckle.wav',
        unbuckleFile = 'seatbelt_unbuckle.wav',
        -- Backend 'native' only: { name = ..., set = ... } per sound.
        native = {
            buckle = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
            unbuckle = { name = 'BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
        },
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
    -- Resource that describes the current proximity mode through
    -- getTalkingMode() -> { index, name, label, range }. kora_voice exposes this
    -- directly; a replacement voice resource can implement the same small
    -- presentation-only contract without coupling the HUD to its internals.
    resource = "kora_voice",
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
    -- continuously (every 100ms kora_lib cache tick for the whole length of a
    -- sprint), so this is the cadence that decides the resource's cost while
    -- the player is moving.
    --
    -- This value is forwarded to the NUI, which sets its gauge animation to
    -- match, so the rings interpolate exactly between samples rather than
    -- stepping. That makes this a pure cost knob: raising it cuts the message
    -- rate and the visible result is identical. What it does trade is the
    -- worst-case age of a value -- and only for a SECOND change inside one
    -- interval, since the first of any burst is sent on the frame it happens.
    vitalsInterval  = configInteger and configInteger(150, {
        label = 'Vitals update interval',
        description = 'Sets the minimum interval, in milliseconds, between burst updates for health, armour, stamina, and voice state. The first change is immediate; later changes inside the interval are coalesced to reduce NUI traffic.',
        min = 50, max = 5000, step = 50, live = true,
    }) or 150,

    -- Job/gang/cash/bank/hunger/thirst/stress/status. These are event-driven
    -- (the kora_core adapter pushes off kora_core's delta stream), so this interval
    -- only ever collapses a burst -- e.g. a full resync firing the adapter's
    -- money/job/gang/metadata subscriptions back-to-back within one frame.
    playerInterval  = configInteger and configInteger(100, {
        label = 'Player update interval',
        description = 'Sets the minimum interval, in milliseconds, used to coalesce bursts of event-driven job, gang, money, hunger, thirst, stress, and status updates before they reach the HUD.',
        min = 50, max = 5000, step = 50, live = true,
    }) or 100,

    -- Four updates per second keeps the numeric speedometer responsive without
    -- making vehicle natives and Lua-to-NUI messages a hot 10Hz path.
    vehicleInterval = configInteger and configInteger(250, {
        label = 'Vehicle update interval',
        description = 'Sets the minimum interval, in milliseconds, between speed, fuel, engine, and headlight refreshes while the player is in a vehicle. Lower values feel more immediate but increase native and NUI work.',
        min = 50, max = 5000, step = 50, live = true,
    }) or 250, -- ms between speed/fuel/engine/headlight refreshes while in a vehicle

    bridgeInterval  = configInteger and configInteger(500, {
        label = 'Bridge update interval',
        description = 'Sets the minimum interval, in milliseconds, between framework bridge snapshots for job, gang, money, and related player data. These values do not need per-frame polling, so larger values reduce background work.',
        min = 50, max = 10000, step = 50, live = true,
    }) or 500, -- ms between HudBridge.getSnapshot() polls -- job/gang/cash/etc. don't need per-frame freshness

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

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if QB and QB.config and QB.config.object then
    Config.poll = QB.config.object(Config.poll, { advanced = true })
end
if QB and QB.config and QB.config.adopt then Config = QB.config.adopt(Config) end
