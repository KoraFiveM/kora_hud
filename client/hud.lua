-- Orchestrator: the only file that talks to the NUI. Combines kora_lib's cache
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
--     stamina, ped and vehicle lifecycle all arrive as kora_lib cache
--     notifications; job/money/needs arrive on the adapter's push path. Only
--     vehicle telemetry and mic state are genuinely sampled, because nothing
--     in the stack can announce them.
--  3. NO HOT PATH READS BACK ACROSS THE EXPORT BOUNDARY. Every
--     Kora.<module>.<fn> access is a cross-resource export call (see
--     kora_lib/init.lua's proxy metatable) -- a full boundary crossing with
--     argument marshalling, not a table lookup. Values are mirrored into
--     plain locals once and kept current from the change handlers' own
--     arguments.
--
-- And the whole thing is gated on visibility: while the HUD is hidden
-- (character select, a cutscene, a logout) this resource owns no thread and
-- does no work at all.
--
-- NOTE: this resource owns its own NUI frame (ui_page in fxmanifest.lua), so
-- every NUI native below is called RAW rather than through Kora.nui.*. Because
-- the body of a Kora.* call runs in kora_lib's Lua VM, SendNUIMessage would post
-- into kora_lib's frame and RegisterNUICallback would publish the callback at
-- https://kora_lib/<name> while this resource's page fetches
-- https://kora_hud/<name> (web/src/lib/fetchNui.ts uses GetParentResourceName) --
-- a permanent 404 that leaves the HUD stuck on DEFAULT_VISIBLE=false. Same
-- reasoning and same fix as kora_loading/client.lua and kora_inventory/client/ui.lua.
-- Kora.cache/Kora.status stay on the proxy; kora_theme's imported bridge owns theme
-- delivery for this frame.
local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

-- Forward-declared so the qbhud:ready callback can be registered as the very
-- FIRST statement in this chunk, ahead of everything that can throw at load
-- (HudBridge.getSnapshot below, Kora.cache.onChange -- all cross-resource export
-- calls that fail if kora_core/kora_lib are mid-restart). A raised error aborts the
-- whole chunk; if that happened before registration, this resource's page would
-- 404 on its ready ping forever with nothing left to retry it.
local sendInitialState

-- Hands the radar back to the engine when the HUD hides. Assigned only when
-- Config.hud.minimap or the player minimap toggle actually takes control of
-- it. In 'always' mode with nothing hidden this resource never touches
-- DisplayRadar at all.
local minimapRelease
-- Set once the minimap visibility block below has run.
local minimapChoiceChanged

-- FiveM delivers SendNUIMessage like postMessage, not like a mailbox: if the
-- NUI page hasn't finished mounting (and attaching its "message" listener)
-- yet, a send is lost, not queued. That's silent AND permanent for a player
-- who's already logged in when this resource (re)starts -- e.g. every
-- `ensure kora_hud` while testing -- because refreshVisibility() below only
-- resends qbhud:visibility on a change from *Lua's* perspective, and Lua
-- already believes it sent `visible` once. The NUI is left stuck on its
-- DEFAULT_VISIBLE=false forever, with nothing left to nudge it. This callback
-- is the reliable half: web/src/lib/hudState.tsx pings it once mounted,
-- guaranteeing a fresh push arrives after the listener is live, regardless of
-- whether the best-effort send in CreateThread below did.
RegisterNUICallback('qbhud:ready', function(_, cb)
    -- Answer first, unconditionally: a raw handler that errors before calling
    -- cb leaves the page's fetch promise hanging forever. Kora.nui.register-
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
local SPEED_UNIT = Config.hud.speedUnit == 'mph' and 'mph' or 'kmh'
local SPEED_MULTIPLIER = SPEED_UNIT == 'mph' and 0.621371 or 1

-- Element toggles decide what this resource SUBSCRIBES TO and SAMPLES, not
-- merely what the NUI paints. A server with the stamina ring switched off has
-- no reason to receive the highest-frequency notification in the whole HUD,
-- and one with the vehicle panel off has no reason to sample vehicle natives
-- four times a second. See the guarded registrations further down.
local ELEMENTS = Config.hud.elements or {}

-- Section positions are stored on THIS player's machine, as JSON in a FiveM
-- KVP key. Client-side on purpose: a HUD layout is a personal preference about
-- one screen, so it needs neither a database column nor a server round trip,
-- and nothing here ever leaves the client.
--
-- The stored value is untrusted input like any other persisted blob -- a player
-- can edit their own KVP file, and an older version of this resource may have
-- written a different shape -- so it is validated on read rather than trusted
-- because we wrote it.
local LAYOUT = Config.layout or {}
-- Whether the player currently has the layout editor open. The NUI holds focus
-- only in this state.
local layoutEditing = false
local visible
local LAYOUT_KVP = LAYOUT.kvpKey or 'qbhud:layout'

local function closeLayout()
    if not layoutEditing then return end
    layoutEditing = false
    SetNuiFocus(false, false)
    send('qbhud:layoutMode', false)
end

-- Offsets are stored as FRACTIONS of the viewport, not pixels: a layout saved
-- on a 3440x1440 ultrawide would put half the HUD off screen on a 1920x1080
-- monitor otherwise. Each section starts from a different anchor, so one
-- shared +/- limit would prevent corner-pinned sections reaching much of the
-- display. These bounds let every section cross the screen while retaining a
-- small recovery margin at the far edge.
local LAYOUT_BOUNDS = {
    gauges = { minX = -0.50, maxX = 0.50, minY = -0.95, maxY = 0.00 },
    vehicle = { minX = -0.50, maxX = 0.50, minY = -0.95, maxY = 0.00 },
    identity = { minX = -0.95, maxX = 0.00, minY = -0.95, maxY = 0.00 },
    status = { minX = -0.95, maxX = 0.00, minY = 0.00, maxY = 0.95 },
    -- kora_chat's composer has a top-left zero point. It is rendered by a
    -- separate NUI, but shares this KVP so /hudlayout remains the one place a
    -- player arranges all of their on-screen interface.
    chatInput = { minX = -0.95, maxX = 0.95, minY = -0.95, maxY = 0.95 },
}
local FALLBACK_LAYOUT_LIMIT = 0.45
-- Component scale is deliberately constrained to keep a large HUD useful
-- without letting a malformed NUI payload cover the whole screen.
local LAYOUT_SCALE_MIN = 0.75
local LAYOUT_SCALE_MAX = 1.50
---@param value any
---@return 'left'|'center'|'right'|nil
local function layoutJustification(value)
    if value == 'left' or value == 'center' or value == 'right' then return value end
    return nil
end

---@param section string
---@param axis 'x'|'y'
---@param value any
---@return number|nil
local function layoutOffset(section, axis, value)
    local number = tonumber(value)
    if not number or number ~= number then return nil end -- NaN
    local bounds = LAYOUT_BOUNDS[section]
    local minimum = bounds and bounds[axis == 'x' and 'minX' or 'minY'] or -FALLBACK_LAYOUT_LIMIT
    local maximum = bounds and bounds[axis == 'x' and 'maxX' or 'maxY'] or FALLBACK_LAYOUT_LIMIT
    if number > maximum then return maximum end
    if number < minimum then return minimum end
    return number
end

---@param value any
---@return number|nil
local function layoutScale(value)
    local number = tonumber(value)
    if not number or number ~= number then return nil end -- NaN
    if number > LAYOUT_SCALE_MAX then return LAYOUT_SCALE_MAX end
    if number < LAYOUT_SCALE_MIN then return LAYOUT_SCALE_MIN end
    return number
end

---This player's saved section layout, split for the NUI into offsets and scales.
---
---Returns an empty table for anything malformed rather than raising: a corrupt
---or hand-edited KVP value must cost the player their layout, not their HUD.
---@return table
local function readLayout()
    if LAYOUT.movable == false then return { offsets = {}, scales = {}, justifications = {}, gaugesBottomAnchored = true } end

    local raw = GetResourceKvpString(LAYOUT_KVP)
    if type(raw) ~= 'string' or raw == '' then return { offsets = {}, scales = {}, justifications = {}, gaugesBottomAnchored = true } end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return { offsets = {}, scales = {}, justifications = {}, gaugesBottomAnchored = true } end

    local offsets, scales, justifications = {}, {}, {}
    local gaugesBottomAnchored = not (type(decoded.gauges) == 'table' and decoded.gauges.bottomAnchored == false)
    for section, entry in pairs(decoded) do
        if type(section) == 'string' and type(entry) == 'table' then
            local justification = layoutJustification(entry.justification)
            local x, y = layoutOffset(section, 'x', entry.x), layoutOffset(section, 'y', entry.y)
            local scale = layoutScale(entry.scale)
            if x and y then offsets[section] = { x = x, y = y } end
            if scale then scales[section] = scale end
            if justification then justifications[section] = justification end
        end
    end
    return { offsets = offsets, scales = scales, justifications = justifications, gaugesBottomAnchored = gaugesBottomAnchored }
end

---Persists a layout the NUI submitted. Re-validated here, not merely stored:
---this is the one write in the whole resource whose payload comes from the
---browser, and the values are read back on the next boot as HUD geometry.
---@param payload any
---@return boolean saved
local function writeLayout(payload)
    if LAYOUT.movable == false then return false end
    if type(payload) ~= 'table' then return false end

    local offsets = type(payload.offsets) == 'table' and payload.offsets or {}
    local scales = type(payload.scales) == 'table' and payload.scales or {}
    local requestedJustifications = type(payload.justifications) == 'table' and payload.justifications or {}
    local gaugesBottomAnchored = payload.gaugesBottomAnchored ~= false
    local clean = {}
    local count = 0
    for section, offset in pairs(offsets) do
        -- Section ids come from the NUI's own fixed list; cap the key length
        -- and the entry count so a malformed submission cannot grow the stored
        -- blob without bound.
        if type(section) == 'string' and #section <= 32 and type(offset) == 'table' and count < 16 then
            local x, y = layoutOffset(section, 'x', offset.x), layoutOffset(section, 'y', offset.y)
            if x and y then
                clean[section] = { x = x, y = y }
                count = count + 1
            end
        end
    end

    -- Alignment is saved even when a component was not moved or resized.
    for section, value in pairs(requestedJustifications) do
        local justification = layoutJustification(value)
        if type(section) == 'string' and #section <= 32 and justification then
            local entry = clean[section]
            if not entry and count < 16 then
                entry = { x = 0, y = 0 }
                clean[section] = entry
                count = count + 1
            end
            if entry then entry.justification = justification end
        end
    end

    for section, value in pairs(scales) do
        if type(section) == 'string' and #section <= 32 then
            local scale = layoutScale(value)
            if scale then
                -- A resize without a move still needs an entry. Supplying the
                -- zero offset preserves the component's shipped position.
                local entry = clean[section]
                if not entry and count < 16 then
                    entry = { x = 0, y = 0 }
                    clean[section] = entry
                    count = count + 1
                end
                if entry then entry.scale = scale end
            end
        end
    end

    -- Bottom anchoring is opt-out, so old KVPs retain the improved default.
    -- Keep it beside the gauges' other saved settings rather than introducing
    -- a second preference blob for one Boolean.
    if not gaugesBottomAnchored then
        local entry = clean.gauges
        if not entry and count < 16 then
            entry = { x = 0, y = 0 }
            clean.gauges = entry
        end
        if entry then entry.bottomAnchored = false end
    end

    SetResourceKvp(LAYOUT_KVP, json.encode(clean))
    return true
end

---Pushes the saved chat composer layout to kora_chat when it is available.
---qbchat also reads this through getLayout when it starts after kora_hud, so
---there is no ordering dependency between the two resources.
local function syncChatInputLayout()
    if type(GetResourceState) ~= 'function' or GetResourceState('kora_chat') ~= 'started' then return end
    if type(TriggerEvent) ~= 'function' then return end
    local layout = readLayout()
    local offset = layout.offsets.chatInput or {}
    TriggerEvent('qbchat:setInputLayout', {
        x = offset.x or 0,
        y = offset.y or 0,
        scale = layout.scales.chatInput,
    })
end

-- Layout edit mode is an explicit mode, entered by command, rather than the HUD
-- being draggable all the time. The HUD is pointer-transparent during play and
-- has to stay that way -- a permanently grabbable HUD would eat the clicks the
-- game needs. The NUI takes focus only while this mode is open.
RegisterCommand(LAYOUT.command or 'hudlayout', function()
    if LAYOUT.movable == false then
        Kora.notify.send({ title = 'HUD', message = 'Moving HUD sections is disabled on this server.', type = 'error' })
        return
    end

    -- While visible, the player confirms or cancels in the NUI. Running the
    -- command again must not silently
    -- commit or discard a layout whose result is still being reviewed.
    if not visible or layoutEditing then return end

    layoutEditing = true
    SetNuiFocus(true, true)
    send('qbhud:layoutMode', true)
end, false)

-- Confirm and Cancel are deliberately one callback. Both release NUI focus;
-- only Confirm supplies geometry to persist. Until this callback arrives all
-- dragging is merely a browser-side preview, so Cancel never needs a rollback
-- write and cannot briefly persist a layout the player rejected.
RegisterNUICallback('qbhud:finishLayout', function(payload, cb)
    -- Answer first and unconditionally, same reasoning as qbhud:ready above.
    cb({})
    if not layoutEditing then return end

    if type(payload) == 'table' and payload.confirmed == true then
        pcall(writeLayout, payload)
        syncChatInputLayout()
    end

    closeLayout()
end)

-- `reset` is separate from the editor rather than a button inside it: a player
-- whose layout put a section somewhere unreachable needs a way out that does
-- not require clicking on the HUD.
RegisterCommand('hudlayoutreset', function()
    DeleteResourceKvp(LAYOUT_KVP)
    closeLayout()
    send('qbhud:layoutReset', true)
    syncChatInputLayout()
    Kora.notify.send({ title = 'HUD', message = 'HUD layout reset to defaults.', type = 'success' })
end, false)

-- Kept as a local, session-only choice: /id is a quick way to identify
-- yourself to another player or staff member, not a layout preference that
-- should unexpectedly reappear after reconnecting.
local playerIdVisible = false
RegisterCommand('id', function()
    if playerIdVisible then
        playerIdVisible = false
        send('qbhud:playerId')
        return
    end

    local serverId = GetPlayerServerId(PlayerId())
    if type(serverId) ~= 'number' or serverId <= 0 then return end

    playerIdVisible = true
    send('qbhud:playerId', serverId)
end, false)

-- Bare cross-resource call AT CHUNK LOAD (not inside any function): if kora_core
-- (or kora_lib, via the status export inside getSnapshot) is mid-restart right
-- when this chunk loads, this would raise and abort the REST of this file's
-- chunk -- meaning the qbhud:ready NUI callback registered above stays
-- registered (that's why it's first), but `sendInitialState` below never gets
-- assigned, so the ready-ping handler's existing nil-guard makes it silently
-- no-op forever. pcall'd, falling back to the same shape snapshotFrom(nil)
-- produces in the kora_core adapter, so downstream field reads below
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
visible = loggedIn and not forcedHidden

-- ONE thread owns every periodic thing this resource does: the vitals and
-- player-data trailing flushes, vehicle telemetry, the mic sample, and the
-- minimap re-assert. Deadlines coincide constantly (vitals at 300ms, voice at
-- 400ms, minimap and vehicle both at 500ms). One thread waking once and running three due tasks
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

    local function request()
        if not visible then return end

        local now = GetGameTimer()
        if now >= task.due then
            task.due = now + task.interval
            flush()
        else
            pending = true
            startScheduler()
        end
    end

    return request, task
end

-- Local mirror of the four continuously-moving values, kept current from the
-- change notifications that already exist for them rather than re-read per
-- push (cost model rule 3). Quantised to whole units on the way in, which is
-- what actually makes the channel idle: raw GetPedArmour/GetPlayerStamina are
-- floats, so without rounding the kora_lib cache reports a "change" for
-- sub-display-resolution drift and the HUD sends a message nobody can see the
-- effect of. The NUI renders these as a 44px ring, so one whole unit is
-- already finer than one pixel of arc.
local vitals = {
    health = 0,
    maxHealth = 200,
    armour = 0,
    stamina = 100,
    talking = false,
    voiceMode = nil,
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
        voiceMode = vitals.voiceMode,
    })
end

local requestVitals, vitalsTask = channel(VITALS_INTERVAL, flushVitals)

---Writes one mirrored vital, requesting a push only if the value really moved.
---The mirror is kept current even while the HUD is hidden -- character select,
---a cutscene -- so a later show has real values to paint; only the PUSH is
---skipped.
local function setVital(key, value)
    if vitals[key] == value then return end
    vitals[key] = value
    if visible then requestVitals() end
end

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

local requestPlayer, playerTask = channel(PLAYER_INTERVAL, flushPlayer)

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
        -- Vehicle snapshots use km/h as their canonical unit. Convert before
        -- rounding so the wire only changes when the displayed whole number
        -- changes, regardless of the configured unit.
        speed = round(snapshot.speed * SPEED_MULTIPLIER),
        -- Keep the rendered label in the same payload as the converted speed.
        -- A delayed or dropped config message must never pair an mph value
        -- with a km/h label (or vice versa).
        speedUnit = SPEED_UNIT,
        fuel = snapshot.fuel and round(snapshot.fuel) or nil,
        fuelKind = snapshot.fuelKind or 'fuel',
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
        or payload.speedUnit ~= lastVehiclePayload.speedUnit
        or payload.fuel ~= lastVehiclePayload.fuel
        or payload.fuelKind ~= lastVehiclePayload.fuelKind
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

-- The minimap's own scaleform draws a health/armour/breath cluster straight
-- from the engine's internal ped state -- it is not driven by
-- Kora.cache.health() and has its own smoothing/thresholds, so left alone it
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
local minimapHealthTask
if minimapScaleform then
    minimapHealthTask = addTask({
        interval = MINIMAP_INTERVAL,
        active = function() return true end,
        run = function() setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER) end,
    })
end

-- Separate from the health/armour cluster above: that decides what the radar
-- DRAWS, this decides whether it is on screen at all.
--
-- 'always' is not "call DisplayRadar(true) repeatedly" -- it is not calling
-- DisplayRadar at all. Asserting `true` every 250ms would silently override any
-- other resource that hides the radar for a cutscene, a phone, or a death
-- screen, which is a far worse default than leaving the engine alone.
local MINIMAP_MODE = (type(Config.hud.minimap) == 'string' and Config.hud.minimap) or 'always'

-- Player minimap toggle (Config.hud.minimapToggle). The player's choice sits on
-- top of MINIMAP_MODE and can only HIDE the radar: it feeds the same
-- visibility task below instead of a second DisplayRadar caller, so menus,
-- pause, phone and forced-hidden HUD keep going through their existing paths.
local MINIMAP_TOGGLE = Config.hud.minimapToggle or {}
local MINIMAP_KVP = 'kora_hud:minimapHidden'
local minimapHiddenChoice

local function minimapToggleEnabled()
    return MINIMAP_TOGGLE.enabled ~= false
end

---The saved choice wins over defaultVisible; anything else in the KVP is ignored.
local function loadMinimapChoice()
    if MINIMAP_TOGGLE.remember ~= false then
        local saved = GetResourceKvpString(MINIMAP_KVP)
        if saved == 'hidden' then return true end
        if saved == 'visible' then return false end
    end
    return MINIMAP_TOGGLE.defaultVisible == false
end
minimapHiddenChoice = loadMinimapChoice()

---Whether the player's choice is currently hiding the radar.
local function minimapPlayerHidden()
    return minimapToggleEnabled() and minimapHiddenChoice == true
end

---Whether the radar should be on screen right now, or nil for "not our call".
---@return boolean|nil
local function minimapShouldShow()
    if minimapPlayerHidden() then return false end
    if MINIMAP_MODE == 'never' then return false end
    if MINIMAP_MODE == 'vehicle' then
        local vehicle = Kora.cache.vehicle()
        return vehicle ~= nil and vehicle ~= 0
    end
    return nil
end

local minimapVisibilityTask
-- Tracked so the radar is only touched when the answer CHANGES. A resource
-- that legitimately hid the radar for its own reasons then keeps working
-- between our transitions instead of being overruled four times a second.
local lastRadar
local radarHeldHidden = false
do
    local function applyMinimap()
        local shouldShow = minimapShouldShow()
        if shouldShow == nil or shouldShow == lastRadar then return end

        lastRadar = shouldShow
        DisplayRadar(shouldShow)
    end

    -- Registered in every mode so a live change of `minimap` or of the toggle
    -- needs no restart, but only RUNS when something wants the radar managed:
    -- 'always' with the player not hiding it is still hands-off.
    minimapVisibilityTask = addTask({
        interval = MINIMAP_INTERVAL,
        active = function() return MINIMAP_MODE ~= 'always' or minimapPlayerHidden() end,
        run = applyMinimap,
    })

    ---Applies a changed player choice at once instead of on the next tick.
    ---'always' mode has no task running while the player is showing the map, so
    ---un-hiding must hand the radar back explicitly.
    minimapChoiceChanged = function()
        if MINIMAP_MODE == 'always' and not minimapPlayerHidden() then
            if lastRadar == false then
                lastRadar = nil
                if visible and not radarHeldHidden then DisplayRadar(true) end
            end
        elseif visible and not radarHeldHidden then
            applyMinimap()
        end
    end

    -- The scheduler only runs while the HUD is visible, so hand the radar back
    -- when it is not: a hidden HUD must not leave the radar forced off with
    -- nothing left running to turn it on again.
    minimapRelease = function()
        if lastRadar == false then
            lastRadar = nil
            DisplayRadar(true)
        end
    end
end

-- While another resource force-hides the HUD (exports.kora_hud:hide(), e.g. a
-- clothing menu), minimapRelease would hand the radar back as VISIBLE and
-- 'vehicle' mode would show it on foot. With hideMinimapWhenForcedHidden the
-- radar is kept off instead, and show() lets the normal mode take over again.
-- Logout and resource stop still release it, so it is never left forced off.
local function wantsRadarHeldHidden(loggedIn, forcedHidden, stopping)
    return loggedIn and forcedHidden and not stopping
        and Config.hud.hideMinimapWhenForcedHidden ~= false
end

local function holdRadarHidden()
    radarHeldHidden = true
    lastRadar = nil -- the mode must be re-applied from scratch after show()
    DisplayRadar(false)
end

-- Called when the radar is no longer held. `hudVisible` is true on show(),
-- where the scheduler reapplies 'vehicle'/'never' itself; 'always' has no
-- scheduler, so it must be handed back explicitly. Otherwise (logout, stop)
-- nothing will run again, so the radar is restored.
local function releaseHeldRadar(hudVisible)
    radarHeldHidden = false
    if hudVisible and (MINIMAP_MODE ~= 'always' or minimapPlayerHidden()) then return end
    DisplayRadar(true)
end

local minimapChoiceSet = false

local function toggleMinimap()
    if not minimapToggleEnabled() then
        Kora.notify.send({ title = 'Minimap', message = 'The minimap toggle is disabled on this server.', type = 'error' })
        return
    end

    minimapChoiceSet = true
    minimapHiddenChoice = not minimapHiddenChoice
    if MINIMAP_TOGGLE.remember ~= false then
        SetResourceKvp(MINIMAP_KVP, minimapHiddenChoice and 'hidden' or 'visible')
    end
    minimapChoiceChanged()

    if minimapHiddenChoice then
        Kora.notify.send({ title = 'Minimap', message = 'Minimap hidden.', type = 'success' })
    elseif MINIMAP_MODE == 'never' then
        Kora.notify.send({ title = 'Minimap', message = 'Minimap enabled, but this server keeps it hidden.', type = 'success' })
    else
        Kora.notify.send({ title = 'Minimap', message = 'Minimap shown.', type = 'success' })
    end
end

-- The plain command always exists so a live `enabled` change needs no restart;
-- the keybind is the same action on a key the player can rebind in Settings.
RegisterCommand(MINIMAP_TOGGLE.command or 'minimap', toggleMinimap, false)
if Kora.keybind and Kora.keybind.add then
    Kora.keybind.add({
        name = 'kora_hud_minimap',
        description = 'Toggle minimap',
        defaultMapper = 'keyboard',
        defaultKey = MINIMAP_TOGGLE.defaultKey or '',
        onPressed = toggleMinimap,
    })
end

-- Mic state is the only HUD input with no change notification anywhere in the
-- stack, so it is genuinely sampled -- but on the shared thread, and only
-- while the element is on AND the HUD is visible (Voice.setActive owns that
-- second half). client/voice.lua deliberately owns no thread of its own.
local voiceTask
if ELEMENTS.mic and Config.voice.enabled ~= false then
    voiceTask = addTask({
        interval = VOICE_INTERVAL,
        active = Voice.isActive,
        run = Voice.sample,
    })
end

-- Speed and fuel change continuously, so no event can carry them either. The
-- task goes inactive the moment the player is out of a vehicle, which is what
-- makes on-foot vehicle telemetry cost exactly nothing. Not registered at all
-- when the panel is switched off.
local vehicleTask
if ELEMENTS.vehicle then
    vehicleTask = addTask({
        interval = VEHICLE_INTERVAL,
        active = function() return ELEMENTS.vehicle == true and currentVehicle ~= false end,
        run = pushVehicleUpdate,
    })
end

-- Push-driven for anything that already has cheap change notification --
-- these fire immediately instead of waiting for a tick. Each handler takes the
-- new value from its own ARGUMENT: kora_lib's cache passes (new, old), so there
-- is no reason to call back across the export boundary to ask for what we
-- were just handed.
Kora.cache.onChange("health", function(value) setVital('health', round(value)) end)
Kora.cache.onChange("armour", function(value) setVital('armour', round(value)) end)
Voice.onChange(function(value) setVital('talking', value == true) end)
Voice.onModeChange(function(value) setVital('voiceMode', value) end)

-- Stamina moves continuously while sprinting -- it belongs to no framework
-- delta and no adapter can announce it -- which makes it far and away the
-- highest-frequency notification the HUD receives, and each one is a
-- cross-resource funcref invocation. So it is subscribed ONLY when something
-- actually renders it: a server with the stamina ring switched off pays
-- nothing for it, rather than paying to receive and discard it.
if ELEMENTS.stamina then
    Kora.cache.onChange("stamina", function(value) setVital('stamina', round(value)) end)
end

-- Maximum health is per-ped (freemode male 200, female 175) and only ever
-- changes when the ped itself does -- a respawn, a model change, a script
-- setting a new maximum. Reading it per push meant a native call AND a
-- cross-resource Kora.cache.ped() on every single stamina tick.
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

Kora.cache.onChange("ped", function(ped)
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
    Kora.cache.onChange("vehicle", function(vehicle)
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
-- and kora_lib mid-restart must leave the HUD on its defaults, not abort the rest
-- of this chunk; the start-up thread retries once if that happens.
local seeded = false

local function seedFromCache()
    vitals.health = round(Kora.cache.health())
    vitals.armour = round(Kora.cache.armour())
    if ELEMENTS.stamina then vitals.stamina = round(Kora.cache.stamina()) end
    refreshMaxHealth(Kora.cache.ped())
    if ELEMENTS.vehicle then currentVehicle = Kora.cache.vehicle() or false end
    seeded = true
end

pcall(seedFromCache)

-- Kora.status isn't part of latestBridgeSnapshot's poll-refresh cadence below
-- in spirit (it's read directly from kora_lib, not through HudBridge's own
-- change notification), so a status effect applying/clearing needs its own
-- push here rather than waiting up to Config.poll.bridgeInterval to show up.
-- Treat it as optional: a rolling restart must not stop this script before it
-- registers qbhud:ready, otherwise the web NUI receives a 404 and can never
-- request the initial visibility/configuration snapshot.
pcall(function()
    Kora.status.onChange(function()
        local ok, status = pcall(function() return Kora.status.getActive() end)
        latestBridgeSnapshot.status = ok and type(status) == 'table' and status or {}
        requestPlayer()
    end)
end)

local function syncVoiceSampling()
    Voice.setActive(visible and ELEMENTS.mic == true)
end

-- Recomputes `visible` from the two inputs and pushes the change to the NUI.
-- Show/hide happen immediately on a login transition rather than waiting for
-- the next poll tick -- e.g. kora_core's adapter pushes this off its replicated
-- login state bag. Adapters with no login concept (the stub) don't implement
-- onLoginChange, so for them only the exports below ever change visibility.
--
-- This is also the resource's on/off switch: showing starts the scheduler,
-- hiding lets it exit on its next wake, so a hidden HUD costs nothing at all.
-- The pushes here deliberately call the flush functions DIRECTLY rather than
-- going through the channels: a show has to repaint the whole HUD on the spot,
-- and a channel already mid-interval from some unrelated change would
-- otherwise defer it.
local resourceStopping = false

local function refreshVisibility()
    local newVisible = loggedIn and not forcedHidden
    if radarHeldHidden and not wantsRadarHeldHidden(loggedIn, forcedHidden, resourceStopping) then
        releaseHeldRadar(newVisible)
    end
    if not newVisible then closeLayout() end
    if newVisible == visible then return end
    visible = newVisible
    syncVoiceSampling()
    send("qbhud:visibility", visible)

    if visible then
        -- pcall'd (via safeGetBridgeSnapshot): this runs inside the adapter's
        -- login-notify loop, and a mid-restart kora_core export must not abort
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
        -- And the radar itself, for the same reason -- see minimapRelease.
        if wantsRadarHeldHidden(loggedIn, forcedHidden, resourceStopping) then
            holdRadarHidden()
        elseif minimapRelease then
            minimapRelease()
        end
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resourceStopping = true
    forcedHidden = true
    refreshVisibility()
    if minimapScaleform then
        SetScaleformMovieAsNoLongerNeeded(minimapScaleform)
        minimapScaleform = nil
    end
end)

if HudBridge.onLoginChange then
    HudBridge.onLoginChange(function(value)
        loggedIn = value == true
        refreshVisibility()
    end)
end

-- Cross-resource control surface: exports.kora_hud:hide() force-hides the HUD
-- regardless of login state (cutscenes, cameras, custom pause menus);
-- exports.kora_hud:show() clears that override -- it does NOT force the HUD on,
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

-- kora_chat uses this small read-only surface at startup to pick up a layout
-- saved before it (re)started. Returning the already validated shape means a
-- consumer never has to read the KVP or trust its contents.
exports('getLayout', readLayout)

-- Assignment, NOT `local function`: that would declare a fresh local shadowing
-- the forward declaration at the top of the file, silently leaving the
-- qbhud:ready callback's upvalue nil.
sendInitialState = function()
    local savedLayout = readLayout()
    send("qbhud:config", {
        dynamic = Config.hud.dynamic == true,
        elements = Config.hud.elements,
        speedUnit = SPEED_UNIT,
        -- The NUI matches its gauge animation to this so the rings interpolate
        -- exactly between samples. That is what makes the cadence a pure cost
        -- knob: raising it cuts the message rate and costs nothing visually.
        -- See web/src/components/hud/RadialGauge.tsx.
        vitalsInterval = VITALS_INTERVAL,
        money = Config.hud.money,
        layout = {
            movable = LAYOUT.movable ~= false,
            command = LAYOUT.command or 'hudlayout',
            -- Seeded from this player's own machine. Sent with the config
            -- rather than on its own channel so the HUD's first paint is
            -- already in the right place instead of visibly jumping.
            offsets = savedLayout.offsets,
            scales = savedLayout.scales,
            justifications = savedLayout.justifications,
            gaugesBottomAnchored = savedLayout.gaugesBottomAnchored,
        },
    })

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
-- push them. The kora_core adapter drives this straight off kora_core's delta stream
-- (exports.kora_core:onPlayerDataChange), so the HUD updates the instant a delta
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
    -- exiting. Only adapters with no push path ever reach this (not kora_core's).
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
    -- Only if the load-time attempt above lost the race with a kora_lib restart.
    if not seeded then pcall(seedFromCache) end

    -- Best-effort: lost if the page hasn't mounted yet (the qbhud:ready
    -- callback at the top of this file covers that). pcall'd so a failure here
    -- can't abort the thread before the scheduler below is armed.
    pcall(sendInitialState)
    -- Covers the inverse startup order too: if kora_chat was already running,
    -- give it the saved composer position without waiting for the next layout
    -- confirmation. If it starts later it performs the same read itself.
    syncChatInputLayout()
    syncVoiceSampling()
    startScheduler()
end)

local function interval(value, fallback)
    value = math.floor(tonumber(value) or fallback)
    return value >= 0 and value or fallback
end

---Applies kora_lib's active HUD snapshot without restarting the resource. The
---scheduler tasks keep their identity, so changing an interval cannot create
---a duplicate polling loop.
---@param settings table
local function applyConfig(settings)
    if type(settings) ~= 'table' then return end

    Config.hud = type(settings.hud) == 'table' and settings.hud or Config.hud
    Config.voice = type(settings.voice) == 'table' and settings.voice or Config.voice
    Config.poll = type(settings.poll) == 'table' and settings.poll or Config.poll
    Config.layout = type(settings.layout) == 'table' and settings.layout or Config.layout

    POLL = Config.poll or {}
    VITALS_INTERVAL = interval(POLL.vitalsInterval, VITALS_INTERVAL)
    PLAYER_INTERVAL = interval(POLL.playerInterval, PLAYER_INTERVAL)
    VEHICLE_INTERVAL = interval(POLL.vehicleInterval, VEHICLE_INTERVAL)
    BRIDGE_INTERVAL = interval(POLL.bridgeInterval, BRIDGE_INTERVAL)
    MINIMAP_INTERVAL = interval(POLL.minimapInterval, MINIMAP_INTERVAL)
    VOICE_INTERVAL = interval(Config.voice.interval, VOICE_INTERVAL)
    SPEED_UNIT = Config.hud.speedUnit == 'mph' and 'mph' or 'kmh'
    SPEED_MULTIPLIER = SPEED_UNIT == 'mph' and 0.621371 or 1
    ELEMENTS = Config.hud.elements or {}
    LAYOUT = Config.layout or {}

    vitalsTask.interval = VITALS_INTERVAL
    playerTask.interval = PLAYER_INTERVAL
    if vehicleTask then vehicleTask.interval = VEHICLE_INTERVAL end
    if voiceTask then voiceTask.interval = VOICE_INTERVAL end
    if minimapHealthTask then minimapHealthTask.interval = MINIMAP_INTERVAL end
    if minimapVisibilityTask then minimapVisibilityTask.interval = MINIMAP_INTERVAL end

    local previousPlayerHidden = minimapPlayerHidden()
    MINIMAP_TOGGLE = Config.hud.minimapToggle or {}
    if not minimapChoiceSet then minimapHiddenChoice = loadMinimapChoice() end
    local previousMinimapMode = MINIMAP_MODE
    MINIMAP_MODE = type(Config.hud.minimap) == 'string' and Config.hud.minimap or 'always'
    if previousMinimapMode ~= MINIMAP_MODE and MINIMAP_MODE == 'always' and minimapRelease then
        minimapRelease()
    end
    if previousPlayerHidden ~= minimapPlayerHidden() then minimapChoiceChanged() end

    syncVoiceSampling()
    -- The NUI remains mounted while the HUD is hidden. Refresh its complete
    -- configuration even then, so a live change made during character select
    -- or another hidden state cannot leave the page showing its old unit when
    -- it becomes visible again.
    sendInitialState()
    if visible then
        startScheduler()
    end
end

-- A kora_lib binding supplies the initial active snapshot after database
-- hydration and subsequent live updates. Older kora_lib versions keep the
-- file-backed configuration behaviour because this registration is optional.
if Kora.config and Kora.config.bind then
    Kora.config.bind('kora_hud', {}, applyConfig)
end
