-- Orchestrator: the only file that talks to the NUI. Combines qblib's cache
-- (health/armour, push-driven via onChange), client/voice.lua, client/vehicle.lua,
-- and HudBridge (the configured adapter, currently client/bridge/stub.lua)
-- into two consolidated payloads -- qbhud:update (general) and qbhud:vehicle
-- (fast-cadence vehicle telemetry, sent separately so it doesn't drag the
-- rest of the HUD onto its cadence) -- rather than one NUI message per
-- element, so the NUI side has a small, fixed wire contract to keep in sync
-- (web/src/lib/types.ts).
--
-- NOTE: this resource owns its own NUI frame (ui_page in fxmanifest.lua), so
-- every NUI native below is called RAW rather than through QB.nui.*. Each
-- QB.<module>.<fn> access is a cross-resource export call (see qblib/init.lua's
-- proxy metatable), so the body runs in QBLIB's Lua VM: SendNUIMessage would
-- post into qblib's frame, and RegisterNUICallback would publish the callback
-- at https://qblib/<name> while this resource's page fetches
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

local function buildVehiclePayload()
    local snapshot = Vehicle.getSnapshot()
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

    return {
        speed = snapshot.speed,
        fuel = snapshot.fuel,
        engineOn = snapshot.engineOn,
        headlights = snapshot.headlights,
        seatbelt = seatbelt,
    }
end

local function pushUpdate()
    if not visible then return end

    send("qbhud:update", {
        health = QB.cache.health(),
        maxHealth = GetEntityMaxHealth(QB.cache.ped()),
        armour = QB.cache.armour(),
        stamina = QB.cache.stamina(),
        talking = Voice.isTalking(),
        job = latestBridgeSnapshot.job,
        gang = latestBridgeSnapshot.gang,
        cash = latestBridgeSnapshot.cash,
        bank = latestBridgeSnapshot.bank,
        hunger = latestBridgeSnapshot.hunger,
        thirst = latestBridgeSnapshot.thirst,
        stress = latestBridgeSnapshot.stress,
        status = latestBridgeSnapshot.status or {},
    })
end

-- Sent separately from qbhud:update (see buildVehiclePayload) so vehicle
-- telemetry can refresh on Config.poll.vehicleInterval -- much faster than
-- the rest of the HUD needs -- without dragging job/cash/hunger/etc. along
-- for the ride on every tick while driving.
local function pushVehicleUpdate()
    if not visible then return end

    send("qbhud:vehicle", buildVehiclePayload())
end

-- Push-driven for anything that already has cheap change notification --
-- these fire immediately instead of waiting for a tick.
QB.cache.onChange("health", pushUpdate)
QB.cache.onChange("armour", pushUpdate)
-- Stamina moves continuously while sprinting, so it is the one HUD field that
-- would visibly lag on any push-only path -- it belongs to no framework delta
-- and no adapter can announce it. qblib's cache re-reads it on its own shared
-- tick (Config.cache.tickInterval, 100ms) and only notifies on an actual
-- change: full rate mid-sprint, silent standing still, and no second thread
-- here to own.
QB.cache.onChange("stamina", pushUpdate)
Voice.onChange(pushUpdate)

-- Vehicle telemetry is the ONE thing that genuinely has to be sampled: speed
-- and fuel change continuously, so no event can carry them. Everything else
-- about it is event-driven -- the cache tells us when the player gets in or
-- out, and the sampling thread exists only for that span. Mirrors the lazy
-- tick-thread pattern client/vehicle.lua already uses to READ the telemetry
-- (and qblib's own modules/zones); previously this ran forever at
-- bridgeInterval even on foot, pushing a null payload every tick.
local vehicleTickRunning = false

local function startVehicleTick()
    if vehicleTickRunning then return end
    vehicleTickRunning = true

    CreateThread(function()
        while QB.cache.vehicle() do
            pushVehicleUpdate()
            Wait(Config.poll.vehicleInterval)
        end

        vehicleTickRunning = false
        -- One final push so the NUI gets the null payload that clears the
        -- vehicle panel -- the loop above exits before sending it.
        pushVehicleUpdate()
    end)
end

QB.cache.onChange("vehicle", function(vehicle)
    if vehicle then startVehicleTick() else pushVehicleUpdate() end
end)
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
        pushUpdate()
    end)
end)

-- Recomputes `visible` from the two inputs and pushes the change to the NUI.
-- Show/hide happen immediately on a login transition rather than waiting for
-- the next poll tick -- e.g. qbcore's adapter pushes this off its replicated
-- login state bag. Adapters with no login concept (the stub) don't implement
-- onLoginChange, so for them only the exports below ever change visibility.
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
        pushUpdate()
        pushVehicleUpdate()
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
        pushUpdate()
        pushVehicleUpdate()
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
        pushUpdate()
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
                pushUpdate()
            end
            Wait(Config.poll.bridgeInterval)
        end
    end)
end

CreateThread(function()
    -- Best-effort: lost if the page hasn't mounted yet (the qbhud:ready
    -- callback at the top of this file covers that). pcall'd so a failure here
    -- can't abort the thread before the vehicle tick below is armed.
    pcall(sendInitialState)
    syncVoiceSampling()

    -- Arms the vehicle tick for a player who is ALREADY in a vehicle when this
    -- resource starts (`ensure qbhud` mid-drive): QB.cache.onChange only ever
    -- observes future transitions, so nothing else would start it until the
    -- player got out and back in.
    if QB.cache.vehicle() then startVehicleTick() end
end)

-- The minimap's own scaleform draws its own health/armour/breath cluster
-- straight from the engine's internal ped state -- it is not driven by
-- QB.cache.health() and has its own smoothing/thresholds, so left alone it
-- visibly disagrees with the radial gauges above (that's the "health isn't
-- matching the default hud" symptom: two independent renderers of the same
-- stat). SETUP_HEALTH_ARMOUR's param controls which of health(1)/armour(2)
-- the minimap draws; 3 draws neither, ceding the stat entirely to this
-- resource's NUI. Requested once (not per-frame) since scaleform handles are
-- movie instances, not frame-scoped state -- re-requesting every tick would
-- leak a new instance each frame. Reissued every tick because the game
-- re-applies its own default (0, both shown) each frame if not told
-- otherwise, same reason the native is documented as a per-frame call.
local minimapScaleform = RequestScaleformMovie("minimap")

CreateThread(function()
    while true do
        Wait(0)
        if visible then
            BeginScaleformMovieMethod(minimapScaleform, "SETUP_HEALTH_ARMOUR")
            ScaleformMovieMethodAddParamInt(3)
            EndScaleformMovieMethod()
        end
    end
end)
