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
-- msgpack (and through a React re-render of every panel) with it.
--
-- COST MODEL (this file is the HUD's whole per-frame budget, so it is written
-- against one). Three rules, in the order they matter:
--
--  1. NOTHING RUNS PER FRAME, and everything periodic shares ONE thread -- see
--     the scheduler below. FiveM walks every live coroutine each frame to
--     decide what to resume, so a sleeping thread is a cost paid every frame
--     whether or not it had any work to do.
--  2. NOTHING POLLS A VALUE SOMETHING ELSE CAN ANNOUNCE. Health, armour,
--     stamina, ped and vehicle lifecycle all arrive as qblib cache
--     notifications; job/money/needs arrive on the adapter's push path. Only
--     vehicle telemetry and mic state are genuinely sampled, because nothing
--     in the stack can announce them.
--  3. NO HOT PATH READS BACK ACROSS THE EXPORT BOUNDARY. Every
--     QB.<module>.<fn> access is a cross-resource export call (see
--     qblib/init.lua's proxy metatable) -- a full boundary crossing with
--     argument marshalling, not a table lookup. Values are mirrored into
--     plain locals once and kept current from the change handlers' own
--     arguments.
--
-- And the whole thing is gated on visibility: while the HUD is hidden
-- (character select, a cutscene, a logout) this resource owns no thread and
-- does no work at all.
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
-- `ensure qbhud` while testing -- because refreshVisibility() below only
-- resends qbhud:visibility on a change from *Lua's* perspective, and Lua
-- already believes it sent `visible` once. The NUI is left stuck on its
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
-- every scheduler pass: a missing key would otherwise reach Wait(nil), which
-- raises in FiveM.
local POLL = (type(Config) == 'table' and Config.poll) or {}
local VITALS_INTERVAL = POLL.vitalsInterval or 150
local PLAYER_INTERVAL = POLL.playerInterval or 100
local VEHICLE_INTERVAL = POLL.vehicleInterval or 250
local BRIDGE_INTERVAL = POLL.bridgeInterval or 500
local MINIMAP_INTERVAL = POLL.minimapInterval or 250
local VOICE_INTERVAL = (Config.voice and Config.voice.interval) or 200

-- Element toggles decide what this resource SUBSCRIBES TO and SAMPLES, not
-- merely what the NUI paints. A server with the stamina ring switched off has
-- no reason to receive the highest-frequency notification in the whole HUD,
-- and one with the vehicle panel off has no reason to sample vehicle natives
-- four times a second. See the guarded registrations further down.
local ELEMENTS = Config.hud.elements or {}

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

-- --- the scheduler ----------------------------------------------------------
--
-- ONE thread owns every periodic thing this resource does: the vitals and
-- player-data trailing flushes, vehicle telemetry, the mic sample, and the
-- minimap re-assert. It replaces the five independent loops those used to be,
-- for the reason in rule 1 of the cost model above -- plus a second one:
-- deadlines coincide constantly (vitals at 300ms, voice at 400ms, minimap and
-- vehicle both at 500ms). One thread waking once and running three due tasks
-- is one resume; three threads waking is three.
--
-- Each task declares whether it has any reason to run at all (`active`), and
-- the sleep is computed from the tasks themselves rather than being a fixed
-- tick, so an idle HUD really is idle: standing still with nothing dirty and
-- no vehicle, the only thing left waking this thread is the minimap re-assert.
--
---@class QBHudTask
---@field interval integer ms between runs
---@field due integer earliest GetGameTimer() value this task may run at
---@field active fun(): boolean whether the task has any reason to run right now
---@field run fun() the work itself
local tasks = {}
local schedulerRunning = false

-- Only reached if every task is inactive AND none is inside a cooldown that
-- could still turn into a trailing flush -- i.e. never, while the minimap task
-- exists. Present so the loop can never reach Wait(nil).
local SCHEDULER_IDLE_SLEEP = 500

---@param task QBHudTask
---@return QBHudTask
local function addTask(task)
    task.due = 0
    tasks[#tasks + 1] = task
    return task
end

local function startScheduler()
    if schedulerRunning or not visible then return end
    schedulerRunning = true

    CreateThread(function()
        while visible do
            local now = GetGameTimer()
            local nextDue

            for i = 1, #tasks do
                local task = tasks[i]

                if task.active() then
                    if now >= task.due then
                        task.due = now + task.interval
                        task.run()
                    end
                    if not nextDue or task.due < nextDue then nextDue = task.due end
                elseif task.due > now and (not nextDue or task.due < nextDue) then
                    -- Inactive but still inside its interval: a channel that
                    -- just flushed and could be dirtied again before the
                    -- cooldown expires. Waking for it bounds how late that
                    -- trailing flush can be -- and costs nothing once the
                    -- cooldown lapses, because a task whose `due` is in the
                    -- past stops being counted here at all. That is what lets
                    -- an idle HUD stop waking for the fast channels entirely
                    -- without giving a busy one unbounded latency.
                    nextDue = task.due
                end
            end

            local sleep = nextDue and (nextDue - GetGameTimer()) or SCHEDULER_IDLE_SLEEP
            Wait(sleep > 0 and sleep or 0)
        end

        schedulerRunning = false
    end)
end

-- Builds a rate-limited output channel and returns its `request` function.
--
-- Leading edge: if the channel is outside its interval the flush happens on
-- THIS frame -- a job change, a login, a status effect applying has no reason
-- to wait -- and only a further change arriving inside the interval is
-- deferred to the scheduler's trailing pass. That ordering is what keeps the
-- HUD feeling immediate at a cadence a HUD does not otherwise need.
---@param interval integer
---@param flush fun()
---@return fun() request
local function channel(interval, flush)
    local pending = false

    local task = addTask({
        interval = interval,
        active = function() return pending end,
        run = function()
            pending = false
            flush()
        end,
    })

    return function()
        if not visible then return end

        local now = GetGameTimer()
        if now >= task.due then
            task.due = now + interval
            flush()
        else
            pending = true
            startScheduler()
        end
    end
end

-- --- vitals -----------------------------------------------------------------
--
-- Local mirror of the four continuously-moving values, kept current from the
-- change notifications that already exist for them rather than re-read per
-- push (cost model rule 3). Quantised to whole units on the way in, which is
-- what actually makes the channel idle: raw GetPedArmour/GetPlayerStamina are
-- floats, so without rounding the qblib cache reports a "change" for
-- sub-display-resolution drift and the HUD sends a message nobody can see the
-- effect of. The NUI renders these as a 44px ring, so one whole unit is
-- already finer than one pixel of arc.
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

local requestVitals = channel(VITALS_INTERVAL, flushVitals)

---Writes one mirrored vital, requesting a push only if the value really moved.
---The mirror is kept current even while the HUD is hidden -- character select,
---a cutscene -- so a later show has real values to paint; only the PUSH is
---skipped.
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

local requestPlayer = channel(PLAYER_INTERVAL, flushPlayer)

-- --- vehicle telemetry ------------------------------------------------------

-- Mirrored from the cache (see the onChange registration below) so the
-- sampling task's own condition isn't a cross-resource call four times a
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

-- --- minimap ----------------------------------------------------------------
--
-- The minimap's own scaleform draws a health/armour/breath cluster straight
-- from the engine's internal ped state -- it is not driven by
-- QB.cache.health() and has its own smoothing/thresholds, so left alone it
-- visibly disagrees with the radial gauges above (that's the "health isn't
-- matching the default hud" symptom: two independent renderers of the same
-- stat). SETUP_HEALTH_ARMOUR's param controls which of health(1)/armour(2)
-- the minimap draws; 3 draws neither, ceding the stat entirely to this
-- resource's NUI, and 0 is the engine's own default of drawing both.
--
-- Requested once (not per-run) since scaleform handles are movie instances,
-- not frame-scoped state -- re-requesting repeatedly would leak a new instance
-- each time. pcall'd because it is the one native this chunk calls at load
-- outside a handler, and a failure must not take the rest of the file (that
-- is, everything the NUI depends on) down with it.
local MINIMAP_DRAW_NEITHER = 3
local MINIMAP_DRAW_DEFAULT = 0

local minimapOk, minimapScaleform = pcall(RequestScaleformMovie, "minimap")
if not minimapOk then minimapScaleform = nil end

local function setupMinimapHealthArmour(param)
    if not minimapScaleform then return end

    BeginScaleformMovieMethod(minimapScaleform, "SETUP_HEALTH_ARMOUR")
    ScaleformMovieMethodAddParamInt(param)
    EndScaleformMovieMethod()
end

-- Re-asserted on an interval rather than every frame. The flag persists inside
-- the scaleform between calls, so the per-frame Wait(0) loop this replaces was
-- spending a thread resume plus three natives every single frame to re-state
-- something that had not changed. Config.poll.minimapInterval documents the
-- escape hatch (0 restores per-frame behaviour) if a build turns out to
-- re-assert the engine default underneath us.
--
-- Always active, so while the HUD is visible this is what keeps the scheduler
-- alive; the moment the HUD hides, refreshVisibility restores the engine
-- default once and the whole thread exits.
if minimapScaleform then
    addTask({
        interval = MINIMAP_INTERVAL,
        active = function() return true end,
        run = function() setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER) end,
    })
end

-- --- sampled inputs ---------------------------------------------------------

-- Mic state is the only HUD input with no change notification anywhere in the
-- stack, so it is genuinely sampled -- but on the shared thread, and only
-- while the element is on AND the HUD is visible (Voice.setActive owns that
-- second half). client/voice.lua deliberately owns no thread of its own.
if ELEMENTS.mic and Config.voice.enabled ~= false then
    addTask({
        interval = VOICE_INTERVAL,
        active = Voice.isActive,
        run = Voice.sample,
    })
end

-- Speed and fuel change continuously, so no event can carry them either. The
-- task goes inactive the moment the player is out of a vehicle, which is what
-- makes on-foot vehicle telemetry cost exactly nothing. Not registered at all
-- when the panel is switched off.
if ELEMENTS.vehicle then
    addTask({
        interval = VEHICLE_INTERVAL,
        active = function() return currentVehicle ~= false end,
        run = pushVehicleUpdate,
    })
end

-- --- change notifications ---------------------------------------------------

-- Push-driven for anything that already has cheap change notification --
-- these fire immediately instead of waiting for a tick. Each handler takes the
-- new value from its own ARGUMENT: qblib's cache passes (new, old), so there
-- is no reason to call back across the export boundary to ask for what we
-- were just handed.
QB.cache.onChange("health", function(value) setVital('health', round(value)) end)
QB.cache.onChange("armour", function(value) setVital('armour', round(value)) end)
Voice.onChange(function(value) setVital('talking', value == true) end)

-- Stamina moves continuously while sprinting -- it belongs to no framework
-- delta and no adapter can announce it -- which makes it far and away the
-- highest-frequency notification the HUD receives, and each one is a
-- cross-resource funcref invocation. So it is subscribed ONLY when something
-- actually renders it: a server with the stamina ring switched off pays
-- nothing for it, rather than paying to receive and discard it.
if ELEMENTS.stamina then
    QB.cache.onChange("stamina", function(value) setVital('stamina', round(value)) end)
end

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
    -- above is most likely to have been dropped. Re-assert it now rather than
    -- leaving the stock cluster on screen until the next interval.
    if visible then setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER) end
end)

-- Vehicle lifecycle is announced; only the telemetry inside it is sampled.
-- Both edges push on the spot rather than waiting for the sampling task's next
-- turn: getting into a car should fill the panel on the frame the door shuts,
-- and getting out should clear it just as fast (that push is the null payload
-- the NUI reads as "on foot"). The task's own next run is deduplicated against
-- this one, so the immediacy costs no extra message.
if ELEMENTS.vehicle then
    QB.cache.onChange("vehicle", function(vehicle)
        currentVehicle = vehicle or false
        pushVehicleUpdate()
        if currentVehicle then startScheduler() end
    end)
end

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
    if ELEMENTS.stamina then vitals.stamina = round(QB.cache.stamina()) end
    refreshMaxHealth(QB.cache.ped())
    if ELEMENTS.vehicle then currentVehicle = QB.cache.vehicle() or false end
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

-- --- visibility -------------------------------------------------------------

local function syncVoiceSampling()
    Voice.setActive(visible and ELEMENTS.mic == true)
end

-- Recomputes `visible` from the two inputs and pushes the change to the NUI.
-- Show/hide happen immediately on a login transition rather than waiting for
-- the next poll tick -- e.g. qbcore's adapter pushes this off its replicated
-- login state bag. Adapters with no login concept (the stub) don't implement
-- onLoginChange, so for them only the exports below ever change visibility.
--
-- This is also the resource's on/off switch: showing starts the scheduler,
-- hiding lets it exit on its next wake, so a hidden HUD costs nothing at all.
-- The pushes here deliberately call the flush functions DIRECTLY rather than
-- going through the channels: a show has to repaint the whole HUD on the spot,
-- and a channel already mid-interval from some unrelated change would
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
        startScheduler()
    else
        -- Hand the stat back to the engine's own minimap cluster: from here
        -- until the HUD is shown again, nothing in this resource draws it.
        setupMinimapHealthArmour(MINIMAP_DRAW_DEFAULT)
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
        -- The NUI matches its gauge animation to this so the rings interpolate
        -- exactly between samples. That is what makes the cadence a pure cost
        -- knob: raising it cuts the message rate and costs nothing visually.
        -- See web/src/components/hud/RadialGauge.tsx.
        vitalsInterval = VITALS_INTERVAL,
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
        -- page holds no state at all and the change checks the channels rely
        -- on would happily conclude there is nothing to say.
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
    -- The one loop that is NOT a scheduler task: it has to keep running while
    -- the HUD is hidden, because `latestBridgeSnapshot` must already be current
    -- the moment a login shows the HUD, and it must outlive the scheduler
    -- exiting. Only adapters with no push path ever reach this (not qbcore's).
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

CreateThread(function()
    -- Only if the load-time attempt above lost the race with a qblib restart.
    if not seeded then pcall(seedFromCache) end

    -- Best-effort: lost if the page hasn't mounted yet (the qbhud:ready
    -- callback at the top of this file covers that). pcall'd so a failure here
    -- can't abort the thread before the scheduler below is armed.
    pcall(sendInitialState)
    syncVoiceSampling()
    startScheduler()
end)
