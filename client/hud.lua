-- Orchestrator: the only file that talks to the NUI. Combines qblib's cache
-- (health/armour/stamina, push-driven via onChange), client/voice.lua,
-- client/vehicle.lua, and HudBridge (the configured adapter) into three
-- consolidated payloads -- qbhud:vitals (health/armour/stamina/talking),
-- qbhud:update (job/gang/money/needs/status) and qbhud:vehicle (vehicle
-- telemetry) -- rather than one NUI message per element, so the NUI side has
-- a small, fixed wire contract to keep in sync (web/src/lib/types.ts).
--
-- The three channels are split by CADENCE, not by topic: stamina alone moves
-- on every 100ms cache tick for the whole length of a sprint, and it has no
-- business dragging the job label, the gang table and the status list through
-- msgpack (and through a React re-render of every panel) ten times a second
-- with it. Each channel is independently throttled -- see `throttle` below.
--
-- COST MODEL (this file is the HUD's whole per-frame budget, so it is written
-- against one): nothing here runs per frame, nothing here polls a value that
-- something else can announce, and every value read on a hot path is mirrored
-- into a plain local first. That last one matters more than it looks: every
-- QB.<module>.<fn> access is a cross-resource export call (see qblib/init.lua's
-- proxy metatable), i.e. a full boundary crossing with argument marshalling --
-- not a table lookup. Reading four of them (health/ped/armour/stamina) inside a
-- 10Hz push was most of this resource's cost while sprinting. They are now read
-- exactly once at load and kept current from the onChange handlers' own
-- arguments.
--
-- NOTE: this resource owns its own NUI frame (ui_page in fxmanifest.lua), so
-- every NUI native below is called RAW rather than through QB.nui.*. Because
-- the body of a QB.* call runs in QBLIB's Lua VM, SendNUIMessage would post
-- into qblib's frame and RegisterNUICallback would publish the callback at
-- https://qblib/<name> while this resource's page fetches
-- https://qbhud/<name> (web/src/lib/fetchNui.ts uses GetParentResourceName) --
-- a permanent 404 that leaves the HUD stuck on DEFAULT_VISIBLE=false. Same
-- reasoning and same fix as qbloading/client.lua and qbinventory/client/ui.lua.
-- QB.cache/QB.theme/QB.status stay on the proxy: pure Lua, no NUI natives.
local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Forward-declared so the qbhud:ready callback can be registered as the very
-- FIRST statement in this chunk, ahead of everything that can throw at load
-- (HudBridge.getSnapshot below, QB.cache.onChange -- all cross-resource export
-- calls that fail if qbcore/qblib are mid-restart). A raised error aborts the
-- whole chunk; if that happened before registration, this resource's page would
-- 404 on its ready ping forever with nothing left to retry it.
local sendInitialState

-- FiveM delivers SendNUIMessage like postMessage, not like a mailbox: if the
-- NUI page hasn't finished mounting (and attaching its "message" listener)
-- yet, a send is lost, not queued. That's silent AND permanent for a player
-- who's already logged in when this resource (re)starts -- e.g. every
-- `ensure qbhud` while testing -- because setVisible() below only resends
-- qbhud:visibility on a change from *Lua's* perspective, and Lua already
-- believes it sent `visible` once. The NUI is left stuck on its
-- DEFAULT_VISIBLE=false forever, with nothing left to nudge it. This callback
-- is the reliable half: web/src/lib/hudState.tsx pings it once mounted,
-- guaranteeing a fresh push arrives after the listener is live, regardless of
-- whether the best-effort send in CreateThread below did.
RegisterNUICallback('qbhud:ready', function(_, cb)
    -- Answer first, unconditionally: a raw handler that errors before calling
    -- cb leaves the page's fetch promise hanging forever. QB.nui.register-
    -- Callback used to pcall + cb({}) on our behalf; that safety net is ours
    -- now that we register directly.
    cb({})

    -- nil only if this chunk aborted between here and the assignment below;
    -- the page still gets a 200 rather than a 404 in that case.
    if not sendInitialState then return end

    local ok, err = pcall(sendInitialState)
    if not ok then
        print(('[qbhud] qbhud:ready initial push failed: %s'):format(tostring(err)))
    end
end)

-- Hoisted to locals with defaults rather than read from the Config table on
-- every loop iteration: these are read inside the hot paths, and a missing key
-- would otherwise reach Wait(nil), which raises in FiveM.
local POLL = (type(Config) == 'table' and Config.poll) or {}
local VITALS_INTERVAL = POLL.vitalsInterval or 100
local PLAYER_INTERVAL = POLL.playerInterval or 100
local VEHICLE_INTERVAL = POLL.vehicleInterval or 250
local BRIDGE_INTERVAL = POLL.bridgeInterval or 500
local MINIMAP_INTERVAL = POLL.minimapInterval or 250

-- Leading-edge throttle. `request()` fires `fn` IMMEDIATELY when nothing is
-- in flight, then collapses every further request arriving inside `interval`
-- into a single trailing call. That ordering is the point: a one-off change
-- (job label, a login, a status effect applying) reaches the NUI on the same
-- frame it happened -- no interval of added latency -- while a continuous
-- stream (stamina draining, four adapter subscriptions all firing off one
-- resync) is capped at one message per interval.
--
-- The worker thread exists only while requests keep arriving and returns to
-- nothing once they stop, the same lazy-thread shape the vehicle sampler and
-- qblib's own modules/zones use. `running`/`pending` need no locking: Lua
-- threads here are cooperative, and neither is read across a Wait boundary
-- without being re-checked after it.
local function throttle(interval, fn)
    local pending, running = false, false

    return function()
        pending = true
        if running then return end
        running = true

        CreateThread(function()
            while pending do
                pending = false
                fn()
                Wait(interval)
            end
            running = false
        end)
    end
end

-- Bare cross-resource call AT CHUNK LOAD (not inside any function): if qbcore
-- (or qblib, via the status export inside getSnapshot) is mid-restart right
-- when this chunk loads, this would raise and abort the REST of this file's
-- chunk -- meaning the qbhud:ready NUI callback registered above stays
-- registered (that's why it's first), but `sendInitialState` below never gets
-- assigned, so the ready-ping handler's existing nil-guard makes it silently
-- no-op forever. pcall'd, falling back to the same shape snapshotFrom(nil)
-- produces in the qbcore adapter, so downstream field reads below
-- (latestBridgeSnapshot.job/gang/cash/... ) stay structurally valid.
local DEFAULT_BRIDGE_SNAPSHOT = {
    job = { name = 'unemployed', label = 'Civilian', grade = 0, gradeLabel = 'Civilian', onDuty = true },
    gang = nil,
    cash = 0,
    bank = 0,
    hunger = 100,
    thirst = 100,
    stress = 0,
    seatbelt = false,
    status = {},
}

local function safeGetBridgeSnapshot()
    local ok, snapshot = pcall(function() return HudBridge.getSnapshot() end)
    if ok and type(snapshot) == 'table' then return snapshot end
    return DEFAULT_BRIDGE_SNAPSHOT
end

local latestBridgeSnapshot = safeGetBridgeSnapshot()

-- An adapter with no login/character-select concept (the stub) has nothing
-- to gate on, so a missing isLoggedIn means "always visible" -- unchanged
-- behaviour for that adapter.
local function currentlyLoggedIn()
    if HudBridge.isLoggedIn then return HudBridge.isLoggedIn() end
    return true
end

-- Two independent inputs decide visibility: the adapter's login state and a
-- forced-hide override other resources control via the show/hide exports
-- below (cutscenes, phone camera, pause screens). The HUD renders only when
-- logged in AND not force-hidden, so an export consumer can never reveal the
-- HUD during character select, and a login can never undo another resource's
-- deliberate hide.
local loggedIn = currentlyLoggedIn()
local forcedHidden = false
local visible = loggedIn and not forcedHidden

local function syncVoiceSampling()
    Voice.setActive(visible and Config.hud.elements.mic == true)
end

-- --- vitals -----------------------------------------------------------------
--
-- Local mirror of the four continuously-moving values, kept current from the
-- change notifications that already exist for them rather than re-read per
-- push (see the COST MODEL note at the top of this file). Quantised to whole
-- units on the way in, which is what actually makes the throttle idle: raw
-- GetPedArmour/GetPlayerStamina are floats, so without rounding the qblib
-- cache reports a "change" for sub-display-resolution drift and the HUD sends
-- a message nobody can see the effect of. The NUI renders these as a 44px
-- ring, so one whole unit is already finer than one pixel of arc.
local vitals = {
    health = 0,
    maxHealth = 200,
    armour = 0,
    stamina = 100,
    talking = false,
}

local function round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function flushVitals()
    if not visible then return end

    send("qbhud:vitals", {
        health = vitals.health,
        maxHealth = vitals.maxHealth,
        armour = vitals.armour,
        stamina = vitals.stamina,
        talking = vitals.talking,
    })
end

local requestVitals = throttle(VITALS_INTERVAL, flushVitals)

---Writes one mirrored vital, requesting a push only if the value really moved.
---The mirror is kept current even while the HUD is hidden -- character select,
---a cutscene -- so a later show has real values to paint; only the PUSH is
---skipped, so a hidden HUD doesn't spin up a throttle thread per stamina tick
---to feed a flush that would return early anyway.
local function setVital(key, value)
    if vitals[key] == value then return end
    vitals[key] = value
    if visible then requestVitals() end
end

-- --- bridge-sourced player data ---------------------------------------------

local function flushPlayer()
    if not visible then return end

    local snapshot = latestBridgeSnapshot
    send("qbhud:update", {
        job = snapshot.job,
        gang = snapshot.gang,
        cash = snapshot.cash,
        bank = snapshot.bank,
        hunger = snapshot.hunger,
        thirst = snapshot.thirst,
        stress = snapshot.stress,
        status = snapshot.status or {},
    })
end

local requestPlayer = throttle(PLAYER_INTERVAL, flushPlayer)

-- --- vehicle telemetry ------------------------------------------------------

-- Mirrored from the cache (see the onChange registration below) so the
-- sampling loop's own condition isn't a cross-resource call four times a
-- second for a value the cache already pushes to us.
---@type integer|false
local currentVehicle = false

-- Last payload actually sent, for the change check below. Vehicle telemetry is
-- the one thing here that genuinely has to be SAMPLED -- speed and fuel change
-- continuously, so no event can carry them -- but "sampled" doesn't have to
-- mean "sent": a car idling at a red light, or parked with the engine running,
-- produces the same reading every tick.
local lastVehiclePayload = nil

local function buildVehiclePayload()
    local snapshot = Vehicle.getSnapshot(currentVehicle)
    if not snapshot then return nil end

    -- Seatbelt is local adapter state. Prefer its cheap accessor so this hot
    -- vehicle path never rebuilds the full player-data/status snapshot merely
    -- to read one boolean; older adapters can fall back to their last snapshot.
    local seatbelt
    if HudBridge.getSeatbelt then
        seatbelt = HudBridge.getSeatbelt() == true
    else
        seatbelt = latestBridgeSnapshot.seatbelt == true
    end

    -- Rounded for the same reason the vitals are: the NUI renders speed as a
    -- whole number and fuel as a ring, so sub-unit float drift is a message
    -- with no visible effect. It also makes fuel's "neutral" 100 exact, which
    -- is what Config.hud.dynamic compares against to hide a full gauge.
    return {
        speed = round(snapshot.speed),
        fuel = snapshot.fuel and round(snapshot.fuel) or nil,
        engineOn = snapshot.engineOn,
        headlights = snapshot.headlights,
        seatbelt = seatbelt,
    }
end

local function vehiclePayloadChanged(payload)
    if payload == nil or lastVehiclePayload == nil then
        return payload ~= lastVehiclePayload
    end

    return payload.speed ~= lastVehiclePayload.speed
        or payload.fuel ~= lastVehiclePayload.fuel
        or payload.engineOn ~= lastVehiclePayload.engineOn
        or payload.headlights ~= lastVehiclePayload.headlights
        or payload.seatbelt ~= lastVehiclePayload.seatbelt
end

-- Sent on its own channel (not folded into qbhud:update) so vehicle telemetry
-- can refresh on Config.poll.vehicleInterval -- much faster than the rest of
-- the HUD needs -- without dragging job/cash/hunger/etc. along for the ride on
-- every tick while driving.
---@param force boolean|nil Send even if nothing changed (visibility/initial-state pushes).
local function pushVehicleUpdate(force)
    if not visible then return end

    local payload = buildVehiclePayload()
    if not force and not vehiclePayloadChanged(payload) then return end

    lastVehiclePayload = payload
    send("qbhud:vehicle", payload)
end

-- Push-driven for anything that already has cheap change notification --
-- these fire immediately instead of waiting for a tick. Each handler takes the
-- new value from its own ARGUMENT: qblib's cache passes (new, old), so there
-- is no reason to call back across the export boundary to ask for what we
-- were just handed.
QB.cache.onChange("health", function(value) setVital('health', round(value)) end)
QB.cache.onChange("armour", function(value) setVital('armour', round(value)) end)
-- Stamina moves continuously while sprinting, so it is the one HUD field that
-- would visibly lag on any push-only path -- it belongs to no framework delta
-- and no adapter can announce it. qblib's cache re-reads it on its own shared
-- tick (Config.cache.tickInterval, 100ms) and only notifies on an actual
-- change: full rate mid-sprint, silent standing still, and no second thread
-- here to own.
QB.cache.onChange("stamina", function(value) setVital('stamina', round(value)) end)
Voice.onChange(function(value) setVital('talking', value == true) end)

-- Forward-declared: the ped handler below re-asserts the minimap suppression
-- on respawn, but the scaleform is only requested further down (after
-- everything that can throw at load).
local reassertMinimap

-- Maximum health is per-ped (freemode male 200, female 175) and only ever
-- changes when the ped itself does -- a respawn, a model change, a script
-- setting a new maximum. Reading it per push meant a native call AND a
-- cross-resource QB.cache.ped() on every single stamina tick.
--
-- A non-positive reading is discarded rather than published: the native
-- answers 0 for a handle that isn't a valid entity yet (the join/loading
-- window, the frame either side of a respawn), and the NUI divides by this to
-- get a percentage. Keeping the last good maximum is always closer to the
-- truth than zero.
local function refreshMaxHealth(ped)
    local maxHealth = GetEntityMaxHealth(ped)
    if type(maxHealth) ~= 'number' or maxHealth <= 0 then return end
    setVital('maxHealth', maxHealth)
end

QB.cache.onChange("ped", function(ped)
    refreshMaxHealth(ped)
    -- A respawn rebuilds the minimap, which is the one moment the suppression
    -- below is most likely to have been dropped. Re-assert it now rather than
    -- leaving the stock cluster on screen until the next interval.
    if reassertMinimap then reassertMinimap() end
end)

-- Everything else about the vehicle is event-driven -- the cache tells us when
-- the player gets in or out, and the sampling thread exists only for that
-- span. Mirrors the lazy tick-thread pattern client/vehicle.lua already uses
-- to READ the telemetry (and qblib's own modules/zones); previously this ran
-- forever at bridgeInterval even on foot, pushing a null payload every tick.
local vehicleTickRunning = false

local function startVehicleTick()
    if vehicleTickRunning then return end
    vehicleTickRunning = true

    CreateThread(function()
        while currentVehicle do
            pushVehicleUpdate()
            Wait(VEHICLE_INTERVAL)
        end

        vehicleTickRunning = false
        -- One final push so the NUI gets the null payload that clears the
        -- vehicle panel -- the loop above exits before sending it.
        pushVehicleUpdate()
    end)
end

QB.cache.onChange("vehicle", function(vehicle)
    currentVehicle = vehicle or false
    if currentVehicle then startVehicleTick() else pushVehicleUpdate() end
end)

-- Seeds the mirrors above with the values the change handlers will keep current
-- from here on. Runs at CHUNK LOAD rather than in the start-up thread below,
-- because the qbhud:ready callback can fire first (a page that mounts before
-- that thread is scheduled) and sendInitialState must never paint a HUD out of
-- the zeroed defaults. pcall'd as a group -- these are cross-resource reads,
-- and qblib mid-restart must leave the HUD on its defaults, not abort the rest
-- of this chunk; the start-up thread retries once if that happens.
local seeded = false

local function seedFromCache()
    vitals.health = round(QB.cache.health())
    vitals.armour = round(QB.cache.armour())
    vitals.stamina = round(QB.cache.stamina())
    refreshMaxHealth(QB.cache.ped())
    currentVehicle = QB.cache.vehicle() or false
    seeded = true
end

pcall(seedFromCache)

-- QB.status isn't part of latestBridgeSnapshot's poll-refresh cadence below
-- in spirit (it's read directly from qblib, not through HudBridge's own
-- change notification), so a status effect applying/clearing needs its own
-- push here rather than waiting up to Config.poll.bridgeInterval to show up.
-- Treat it as optional: a rolling restart must not stop this script before it
-- registers qbhud:ready, otherwise the web NUI receives a 404 and can never
-- request the initial visibility/configuration snapshot.
pcall(function()
    QB.status.onChange(function()
        local ok, status = pcall(function() return QB.status.getActive() end)
        latestBridgeSnapshot.status = ok and type(status) == 'table' and status or {}
        requestPlayer()
    end)
end)

-- Recomputes `visible` from the two inputs and pushes the change to the NUI.
-- Show/hide happen immediately on a login transition rather than waiting for
-- the next poll tick -- e.g. qbcore's adapter pushes this off its replicated
-- login state bag. Adapters with no login concept (the stub) don't implement
-- onLoginChange, so for them only the exports below ever change visibility.
--
-- The pushes here deliberately call the flush functions DIRECTLY rather than
-- going through the throttles: a show has to repaint the whole HUD on the spot,
-- and a throttle already mid-interval from some unrelated change would
-- otherwise defer it.
local function refreshVisibility()
    local newVisible = loggedIn and not forcedHidden
    if newVisible == visible then return end
    visible = newVisible
    syncVoiceSampling()
    send("qbhud:visibility", visible)

    if visible then
        -- pcall'd (via safeGetBridgeSnapshot): this runs inside the adapter's
        -- login-notify loop, and a mid-restart qbcore export must not abort
        -- it after the visibility send already went out.
        latestBridgeSnapshot = safeGetBridgeSnapshot()
        flushVitals()
        flushPlayer()
        pushVehicleUpdate(true)
    end
end

if HudBridge.onLoginChange then
    HudBridge.onLoginChange(function(value)
        loggedIn = value == true
        refreshVisibility()
    end)
end

-- Cross-resource control surface: exports.qbhud:hide() force-hides the HUD
-- regardless of login state (cutscenes, cameras, custom pause menus);
-- exports.qbhud:show() clears that override -- it does NOT force the HUD on,
-- login state still gates, so calling show() during character select stays a
-- safe no-op. isVisible() reports the composed result the NUI currently has.
exports('hide', function()
    forcedHidden = true
    refreshVisibility()
end)

exports('show', function()
    forcedHidden = false
    refreshVisibility()
end)

exports('isVisible', function()
    return visible
end)

-- Assignment, NOT `local function`: that would declare a fresh local shadowing
-- the forward declaration at the top of the file, silently leaving the
-- qbhud:ready callback's upvalue nil.
sendInitialState = function()
    send("qbhud:config", {
        dynamic = Config.hud.dynamic == true,
        elements = Config.hud.elements,
    })

    -- QB.theme.tokens() is a cross-resource call into qblib; a qblib restart
    -- must not abort the visibility send that follows it (that used to be
    -- swallowed by QB.nui.registerCallback's own pcall). A missing theme just
    -- leaves the NUI on the defaults in web/src/styles/globals.css.
    local ok, tokens = pcall(function() return QB.theme.tokens() end)
    if ok and type(tokens) == 'table' then send("qbhud:theme", tokens) end

    send("qbhud:visibility", visible)

    if visible then
        -- Direct, un-throttled and unconditional: this is a REMOUNT, so the
        -- page holds no state at all and the change checks the throttled paths
        -- rely on would happily conclude there is nothing to say.
        flushVitals()
        flushPlayer()
        pushVehicleUpdate(true)
    end
end

-- Bridge-sourced fields (job/cash/hunger/etc.) are PUSHED when the adapter can
-- push them. The qbcore adapter drives this straight off qbcore's delta stream
-- (exports.qbcore:onPlayerDataChange), so the HUD updates the instant a delta
-- lands instead of up to Config.poll.bridgeInterval later -- and nothing runs
-- at all in between. onChange is optional in the contract (see
-- shared/bridge.lua), so an adapter that only implements getSnapshot -- the
-- stub does -- still gets the documented polling fallback.
if HudBridge.onChange then
    HudBridge.onChange(function(snapshot)
        latestBridgeSnapshot = snapshot
        requestPlayer()
    end)
else
    CreateThread(function()
        while true do
            -- Unlike safeGetBridgeSnapshot, a failed poll keeps the LAST good
            -- snapshot rather than reverting to defaults -- a framework
            -- restart mid-session must not flash placeholder data, and an
            -- uncaught error here would kill this thread for good.
            local ok, snapshot = pcall(function() return HudBridge.getSnapshot() end)
            if ok and type(snapshot) == 'table' then
                latestBridgeSnapshot = snapshot
                requestPlayer()
            end
            Wait(BRIDGE_INTERVAL)
        end
    end)
end

-- The minimap's own scaleform draws its own health/armour/breath cluster
-- straight from the engine's internal ped state -- it is not driven by
-- QB.cache.health() and has its own smoothing/thresholds, so left alone it
-- visibly disagrees with the radial gauges above (that's the "health isn't
-- matching the default hud" symptom: two independent renderers of the same
-- stat). SETUP_HEALTH_ARMOUR's param controls which of health(1)/armour(2)
-- the minimap draws; 3 draws neither, ceding the stat entirely to this
-- resource's NUI, and 0 is the engine's own default of drawing both.
--
-- Requested once (not per-tick) since scaleform handles are movie instances,
-- not frame-scoped state -- re-requesting repeatedly would leak a new instance
-- each time.
local MINIMAP_DRAW_NEITHER = 3
local MINIMAP_DRAW_DEFAULT = 0

local minimapScaleform = RequestScaleformMovie("minimap")

local function setupMinimapHealthArmour(param)
    BeginScaleformMovieMethod(minimapScaleform, "SETUP_HEALTH_ARMOUR")
    ScaleformMovieMethodAddParamInt(param)
    EndScaleformMovieMethod()
end

-- Assignment, not `local function` -- see sendInitialState above for why the
-- forward declaration must not be shadowed.
reassertMinimap = function()
    if visible then setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER) end
end

-- Re-asserted on an interval rather than every frame. The flag persists inside
-- the scaleform between calls, so the per-frame Wait(0) loop this replaces was
-- spending a thread resume plus three natives every single frame to re-state
-- something that had not changed -- for a HUD whose entire job here is one
-- boolean. Config.poll.minimapInterval documents the escape hatch (0 restores
-- the per-frame behaviour) if a build turns out to re-assert the engine
-- default underneath us.
--
-- `suppressed` tracks what was last asked for so the engine default is
-- restored exactly once when the HUD hides (a cutscene, a logout), instead of
-- leaving the stock cluster suppressed on a screen this resource is no longer
-- drawing on.
CreateThread(function()
    local suppressed = false

    while true do
        if visible then
            setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER)
            suppressed = true
        elseif suppressed then
            setupMinimapHealthArmour(MINIMAP_DRAW_DEFAULT)
            suppressed = false
        end

        Wait(MINIMAP_INTERVAL)
    end
end)

CreateThread(function()
    -- Only if the load-time attempt above lost the race with a qblib restart.
    if not seeded then pcall(seedFromCache) end

    -- Best-effort: lost if the page hasn't mounted yet (the qbhud:ready
    -- callback at the top of this file covers that). pcall'd so a failure here
    -- can't abort the thread before the vehicle tick below is armed.
    pcall(sendInitialState)
    syncVoiceSampling()

    -- Arms the vehicle tick for a player who is ALREADY in a vehicle when this
    -- resource starts (`ensure qbhud` mid-drive): QB.cache.onChange only ever
    -- observes future transitions, so nothing else would start it until the
    -- player got out and back in.
    if currentVehicle then startVehicleTick() end
end)
