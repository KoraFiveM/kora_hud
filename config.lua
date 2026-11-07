Config = {}

-- Descriptors are optional so the configuration remains compatible with an
-- older kora_lib during a rolling upgrade.
local configEnum = Kora and Kora.config and Kora.config.enum
local configInteger = Kora and Kora.config and Kora.config.integer
local configBoolean = Kora and Kora.config and Kora.config.boolean
local configNumber = Kora and Kora.config and Kora.config.number

-- Boolean option: the kora_lib descriptor when available, otherwise the plain
-- default. Replaces the old `configBoolean and configBoolean(x, ...) or true`,
-- whose trailing `or true` made a `false` default impossible to express.
local function boolean(default, options)
    if configBoolean then return configBoolean(default, options) end
    return default
end

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

    -- kora_lib's progress bar sits at the bottom centre in its own NUI frame,
    -- which the game draws under this HUD. While one runs in a vehicle, lift
    -- the gauge row above it so the bar stays readable.
    avoidProgressBar = boolean(true, {
        label = 'Lift gauges above progress bars',
        description = 'While a progress bar is shown in a vehicle, the gauge row moves up so it does not cover the bar.',
        live = true,
    }),

    -- The race harness attach/remove bar is positioned to sit over the gauge
    -- row's usual spot, so the gauges stay put for it instead of lifting.
    avoidHarnessBar = boolean(false, {
        label = 'Lift gauges above the race harness bar',
        description = 'When off, the gauge row does not move while the race harness attach/remove bar is shown.',
        live = true,
    }),

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

    -- Player minimap toggle. Lets each player hide the minimap on top of the
    -- `minimap` mode above: the mode decides when the radar CAN show, the
    -- player's choice can only hide it further, except that `allowOnFoot` lets
    -- them lift the 'vehicle' gate for themselves on foot. Menus,
    -- pause, phone and forced-hidden HUD keep working as before. Enabled by
    -- default because it is harmless -- nothing changes until a player runs the
    -- command or presses a key they bound themselves (defaultKey is unbound).
    -- Set enabled = false to remove the feature; the command then only tells
    -- the player it is disabled. `enabled`, `defaultVisible` and `remember` are
    -- read live; `command` and `defaultKey` are registered at resource start.
    minimapToggle = {
        enabled = boolean(true, {
            label = 'Player minimap toggle',
            description = 'Lets players hide and show their own minimap with a command or a key they bind in Settings > Key Bindings. The minimap mode still decides when the map may appear; the toggle can only hide it further.',
            live = true,
        }),
        -- Chat/console command that toggles the minimap.
        command = 'minimap',
        -- Default key for the rebindable "Toggle minimap" binding. '' leaves it
        -- unbound; players can still bind it in Settings > Key Bindings > FiveM.
        defaultKey = '',
        -- Save each player's choice on their own machine (client KVP) so it
        -- survives reconnects. When false the choice lasts until relog/restart.
        remember = boolean(true, {
            label = 'Remember minimap choice',
            description = 'Saves each player\'s minimap on/off choice on their own machine so it survives reconnects.',
            live = true,
        }),
        -- What a player with no saved choice sees: true = the minimap follows
        -- `minimap` above, false = it starts hidden until they toggle it on.
        defaultVisible = boolean(true, {
            label = 'Minimap visible by default',
            description = 'When off, players without a saved choice start with the minimap hidden until they toggle it on.',
            live = true,
        }),
        -- Lets a player bring the minimap back on foot when `minimap` is
        -- 'vehicle' (or minimapVehicleOnly hides it on foot): toggling it on
        -- while on foot, or switching "Minimap only in vehicle" off in
        -- /hudlayout, overrides the vehicle gate for that player and is saved
        -- with their choices. false = the toggle can only ever hide it, as
        -- before. `minimap = 'never'` is never overridden.
        allowOnFoot = boolean(true, {
            label = 'Players can show the minimap on foot',
            description = 'When the minimap mode is vehicle-only, lets a player turn their minimap on while on foot with the toggle or the /hudlayout switch. Off = the toggle can only hide it.',
            live = true,
        }),
    },

    -- Minimap only in a vehicle, per player. Each player can switch this on in
    -- /hudlayout ("Minimap only in vehicle"); with it on, the radar is hidden
    -- on foot and shown in a vehicle (driver or passenger, the same test the
    -- 'vehicle' mode of `minimap` uses). It is saved with that player's HUD
    -- layout on their own machine, and /hudlayoutreset puts it back to
    -- `default`. It sits on top of the modes above like the player toggle does:
    -- `minimap = 'never'` and a player's own /minimap "hidden" choice still
    -- hide the radar, and it works with `minimap = 'always'` too. Read live.
    minimapVehicleOnly = {
        -- What a player who never chose sees: true = minimap only in vehicles
        -- for everyone by default, false = the minimap follows `minimap`.
        default = boolean(false, {
            label = 'Minimap only in vehicle (default)',
            description = 'The server-wide default for players who never changed it in /hudlayout. When on, the minimap is hidden on foot and shown in vehicles.',
            live = true,
        }),
        -- false hides the option in /hudlayout and forces `default` for every
        -- player, ignoring anything they saved earlier. Also forced to the
        -- default while Config.layout.movable is false (no layout editor).
        allowPlayerChange = boolean(true, {
            label = 'Players can change minimap-only-in-vehicle',
            description = 'Shows the "Minimap only in vehicle" switch in /hudlayout. When off, every player gets the server default and the switch is hidden.',
            live = true,
        }),
    },

    -- While another resource force-hides the HUD (exports.kora_hud:hide(), as
    -- kora_clothing does for its menu) also keep the radar hidden, and let
    -- `minimap` above take over again on show(). Set false for the old
    -- behaviour: the radar is handed back as visible, which with
    -- minimap = 'vehicle' shows it on foot. Logout and resource stop always
    -- restore the radar. Read live, so changes apply on the next hide().
    hideMinimapWhenForcedHidden = boolean(true, {
        label = 'Hide minimap with forced-hidden HUD',
        description = 'Keeps the minimap hidden while another resource hides the HUD, such as a clothing menu, and returns it to the minimap mode when the HUD is shown again. When off, the minimap is handed back as visible instead, which shows it on foot in vehicle mode.',
        live = true,
    }),

    -- Hide every HUD element (gauges, job/cash pills, status effects such as
    -- Bleeding/Limping, vehicle bar) while the pause menu or the full map
    -- (ESC, P) is open, and show them again, exactly as before, when it closes.
    -- Other reasons the HUD is hidden (forced hide, logout, minimap toggle) are
    -- unaffected. Read live.
    hideOnPauseMenu = boolean(true, {
        label = 'Hide HUD on pause menu / map',
        description = 'Hides the whole HUD while the pause menu or the full map is open so it does not draw over the map and its legend, and restores it when the menu closes.',
        live = true,
    }),

    -- Minimap layout. When enabled, kora_hud positions the minimap, its mask
    -- and its border/blur frame from one calculation and, for the 'square'
    -- shape, swaps the radar mask for its own streamed texture
    -- (stream/kora_hud_squaremap.ytd, built by tools/gen_minimap_ytd.py), so the
    -- rotating map tiles are clipped to a square instead of spilling out of the
    -- border. This is the same technique the widely used qb-hud/ps-hud square
    -- map relies on, with the same rect values (below).
    --
    -- Widths and heights are NOT scaled for the aspect ratio: the engine already
    -- lays out left/bottom-anchored components in a 16:9 space, so scaling them
    -- again would double-correct. Only the x position gets the small ultrawide
    -- offset (`aspectOffset`). The engine also already applies the safezone to
    -- L/B anchors, so no safezone compensation is applied by default.
    --
    -- Natives only re-read the component rects and masks on a bigmap toggle, so
    -- after every change one SetBigmapActive(true) -> wait -> (false) refresh is
    -- done from a single owner in client/minimap.lua. Read live (apart from the
    -- stream file itself).
    minimapLayout = {
        -- When false kora_hud does not touch the minimap components, masks or
        -- the bigmap at all (and undoes anything it applied earlier), and
        -- exports.kora_hud:applyMinimapLayout() returns false. Turn it off if
        -- another resource positions the minimap.
        enabled = boolean(true, {
            label = 'Manage minimap layout (off = stock minimap)',
            description = 'On by default: the HUD positions the minimap, mask and border together and clips the map to the chosen shape. Turn off to leave the stock GTA minimap alone, for example if another resource positions the minimap.',
            live = true,
        }),
        -- 'square' (default): streamed square mask + clip type 0.
        -- 'circle': stock round mask + clip type 1 (no texture replaced).
        -- 'stock': kora_hud touches no component position or texture (pure
        --          vanilla); if it applied one earlier it undoes it.
        shape = 'square',
        -- Streamed texture dictionary holding the square mask (stream/ is
        -- streamed automatically; the dictionary name is the .ytd file name) and
        -- the texture inside it. It replaces the radarmasksm and radarmask1g
        -- textures of platform:/textures/graphics.
        textureDict = 'kora_hud_squaremap',
        maskTexture = 'radarmasksm',
        -- How long to wait for the dictionary to stream in. On timeout a warning
        -- is printed and the stock minimap is kept (nothing half-applied).
        dictTimeoutMs = 5000,
        -- A failed apply (dictionary not streamed in time) keeps the stock
        -- minimap, is retried every retryMs up to maxRetries times, then left
        -- alone until another resource starts.
        retryMs = 10000,
        maxRetries = 3,
        -- Ms between SetBigmapActive(true) and (false) in the refresh. The
        -- engine needs a frame or more between them.
        bigmapWaitMs = 50,
        -- Applying waits for the player ped and the minimap scaleform to exist,
        -- then this long once, instead of applying blindly at resource start.
        -- readyTimeoutMs bounds that wait.
        readySettleMs = 2000,
        readyTimeoutMs = 30000,
        -- Ms between checks of the screen resolution and the config. The layout
        -- is only re-applied when the answer changed.
        pollMs = 1000,
        -- Force the bigmap back off if it is found on (twice in a row, so a
        -- short toggle by another script is left alone) while kora_hud manages
        -- the layout and is not refreshing, and the pause menu is closed. This
        -- is what un-sticks an oversized "bigmap" radar. Turn it off if another
        -- resource deliberately keeps the bigmap on.
        guardBigmap = boolean(true, {
            label = 'Force the bigmap off when stuck',
            description = 'Switches the expanded bigmap radar back off if it stays on while the HUD manages the minimap layout. Turn off if another resource keeps the bigmap on on purpose.',
            live = true,
        }),
        -- Ultrawide x offset: for aspect > 16:9 every rect x gets
        -- ((16/9 - aspect) / divisor) + bias. Aspects within `tolerance` above
        -- 16:9 (windowed 1919x1079 and the like) count as 16:9.
        aspectOffset = {
            divisor = 3.6,
            bias = -0.008,
            tolerance = 0.01,
        },
        -- Per-shape rects, left/bottom anchored, as { x, y, w, h } in screen
        -- fractions, plus the SetMinimapClipType value. Not scaled by aspect.
        shapes = {
            square = {
                clipType = 0,
                rects = {
                    minimap      = { x = 0.0,   y = -0.047, w = 0.1638, h = 0.183 },
                    minimap_mask = { x = 0.0,   y = 0.0,    w = 0.128,  h = 0.20 },
                    minimap_blur = { x = -0.01, y = 0.025,  w = 0.262,  h = 0.300 },
                },
            },
            circle = {
                clipType = 1,
                rects = {
                    minimap      = { x = -0.0100, y = -0.030, w = 0.180, h = 0.258 },
                    minimap_mask = { x = 0.200,   y = 0.0,    w = 0.065, h = 0.20 },
                    minimap_blur = { x = -0.00,   y = 0.015,  w = 0.252, h = 0.338 },
                },
            },
            -- The vanilla 16:9 rects and clip type. Only used to put the stock
            -- layout back (shape 'stock', layout disabled, resource stop); never
            -- scaled, offset or nudged.
            stock = {
                clipType = 0,
                rects = {
                    minimap      = { x = -0.0045, y = 0.002, w = 0.150, h = 0.188 },
                    minimap_mask = { x = 0.020,   y = 0.032, w = 0.111, h = 0.159 },
                    minimap_blur = { x = -0.03,   y = 0.022, w = 0.266, h = 0.237 },
                },
            },
        },
        -- Optional nudges applied on top of the shape rects (not used by
        -- 'stock'). Defaults give exactly the numbers above.
        -- x / y are added to every component's x / y (screen fractions).
        x = configNumber and configNumber(0.0, {
            label = 'Minimap X offset',
            description = 'Added to the x of the whole minimap as a fraction of the screen width.',
            min = -0.5, max = 0.5, step = 0.001, live = true,
        }) or 0.0,
        y = configNumber and configNumber(0.0, {
            label = 'Minimap Y offset',
            description = 'Added to the y of the whole minimap (bottom-anchored) as a fraction of the screen height.',
            min = -0.5, max = 0.5, step = 0.001, live = true,
        }) or 0.0,
        -- Size multiplier for map, mask and border together. Default 1.0.
        scale = configNumber and configNumber(1.0, {
            label = 'Minimap size scale',
            description = 'Scales the minimap, its mask and its border together; 1.0 is the shipped size.',
            min = 0.5, max = 2.0, step = 0.01, live = true,
        }) or 1.0,
        -- Extra safezone compensation. The engine already applies the safezone
        -- to left/bottom anchors, so this stays 0 (correcting it would double
        -- up); only raise it if the map drifts from its border at small
        -- safezone sizes on your build.
        safezoneCompensation = configNumber and configNumber(0.0, {
            label = 'Safezone compensation',
            description = 'Cancels this fraction of the GTA safezone margin for the minimap. Leave at 0 unless the map drifts from its border when the safezone slider is lowered.',
            min = 0.0, max = 2.0, step = 0.05, live = true,
            advanced = true,
        }) or 0.0,
        -- Fine offsets for one component, to correct a single layer that is a
        -- hair off on your setup (screen fractions).
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

-- Unified UI layout editor. /ui opens one editor for the HUD sections and for
-- every element other resources register through
-- exports.kora_hud:registerUiElement (kora_chat's chat, kora_inventory's
-- window) plus the minimap. Each player can move, resize and hide elements and
-- change each element's own settings; everything is saved in the same client
-- KVP as Config.layout.kvpKey. Config.layout.movable = false still pins
-- everything. Set enabled = false for exactly the old /hudlayout editor (HUD
-- sections and the chat input box only, no hiding, no other resources).
-- `command`, `aliases` and `resetCommand` are registered at resource start;
-- the rest is read live.
Config.uiEditor = {
    enabled = boolean(true, {
        label = 'Unified /ui layout editor',
        description = 'Lets players arrange the HUD, chat, inventory and minimap from one /ui editor, with per-element visibility and settings. Off keeps the original /hudlayout editor.',
    }),
    -- Opens the editor. /hudlayout (Config.layout.command) keeps working too.
    command = 'ui',
    aliases = { 'hudsettings' },
    -- Wipes this player's layout without opening anything (as /hudlayoutreset).
    resetCommand = 'uireset',
    -- Players may hide individual elements (HUD sections, the minimap, and
    -- registered elements that allow it).
    allowHide = boolean(true, {
        label = 'Players can hide UI elements',
        description = 'Shows a Visible switch in /ui for each element that supports hiding.',
        live = true,
    }),
    -- Accept elements from other resources (chat, inventory). false = HUD only.
    allowExternal = true,
    -- Players may move and resize the minimap (needs minimapLayout.enabled and
    -- a shape other than 'stock'; otherwise it is shown but locked).
    minimap = boolean(true, {
        label = 'Players can move the minimap',
        description = 'Lets players drag and resize the minimap in /ui, on top of the server minimap layout.',
        live = true,
    }),
    -- Ms between live previews sent to another resource while dragging.
    previewInterval = 100,
}

-- Seatbelt feedback. The seatbelt itself lives in kora_utils; kora_hud only
-- plays the sound when that state changes. All values are read each time a
-- sound plays, so edits apply without a restart.
Config.seatbelt = {
    -- Race harness icon next to the seatbelt icon (state from kora_utils).
    --   'attached' -- shown only while a harness is attached
    --   'always'   -- also a dimmed icon while no harness is attached
    --   'off'      -- never shown
    harnessIcon = configEnum and configEnum('attached', {
        label = 'Race harness icon',
        description = 'Shows a race harness icon next to the seatbelt icon in the vehicle HUD: only while attached, always (dimmed when not attached), or never.',
        options = { 'attached', 'always', 'off' },
        live = true,
    }) or 'attached',
    sound = {
        enabled = boolean(true, {
            label = 'Seatbelt sounds',
            description = 'Plays a buckle sound when the seatbelt goes on and a different unbuckle sound when it comes off, for the local player only. Turn off on servers that already play their own seatbelt audio.',
            live = true,
        }),
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

-- Stress gain. kora_hud only displayed stress before; this restores the
-- qb-hud behaviour of gaining it from fast driving and shooting (client/stress.lua).
-- Values are written through kora_core metadata (QBCore:Server:SetMetaData, which
-- needs Config.compat.clientMetadataKeys.stress = true in kora_core -- its default).
-- Set enabled = false to turn the whole feature off.
Config.stress = {
    enabled = true,
    -- Job names that never gain stress (e.g. { 'police', 'ambulance' }).
    whitelistedJobs = { 'police' },
    notify = true, -- fire kora_hud:client:stressGained (at most every 10 s) for notification resources

    speed = {
        enabled = true,
        unit = 'kmh',   -- 'kmh' or 'mph'; threshold is compared in this unit
        threshold = 180,  -- vehicle speed at or above which stress is gained
        driverOnly = true,
        interval = 10000, -- ms between speed checks
        gainMin = 1,
        gainMax = 3,
    },

    shooting = {
        enabled = true,
        chance = 50,      -- percent chance per shooting check to gain stress
        gainMin = 1,
        gainMax = 3,
        cooldown = 3000,  -- ms to wait after a shot that was checked
        -- Weapon hashes that never cause stress, e.g. { [`WEAPON_STUNGUN`] = true }.
        whitelistedWeapons = {},
    },
}

-- Registers this resource-owned configuration with kora_lib without changing its public Config table.
if Kora and Kora.config and Kora.config.object then
    Config.poll = Kora.config.object(Config.poll, { advanced = true })
end
if Kora and Kora.config and Kora.config.adopt then Config = Kora.config.adopt(Config) end
