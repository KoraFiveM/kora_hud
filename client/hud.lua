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
-- The minimap visibility block's vehicle mirror (see radarVehicle below).
local radarVehicle

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

-- "Minimap only in vehicle" (Config.hud.minimapVehicleOnly) is a per-player
-- preference saved in the same KVP blob as the section layout, as the boolean
-- `minimapVehicleOnly`. nil means the player never chose, so the server default
-- applies. Cached here and updated on every write/reset, so the visibility task
-- never parses JSON.
local vehicleOnlyChoice

---@return boolean default, boolean playerMayChange
local function minimapVehicleOnlySettings()
    local cfg = Config.hud.minimapVehicleOnly
    cfg = type(cfg) == 'table' and cfg or {}
    -- minimap = 'vehicle' already limits the radar to vehicles, so that is the
    -- effective default: the switch shows on, and switching it off is a real
    -- (stored) choice that lifts the on-foot gate via minimapOnFootForced.
    local default = cfg.default == true or Config.hud.minimap == 'vehicle'
    -- A pinned layout has no editor, so nobody could change it either.
    return default, cfg.allowPlayerChange ~= false and LAYOUT.movable ~= false
end

---Whether the radar is currently limited to vehicles for this player.
---@return boolean
local function minimapVehicleOnly()
    local default, mayChange = minimapVehicleOnlySettings()
    if mayChange and vehicleOnlyChoice ~= nil then return vehicleOnlyChoice end
    return default
end

local function loadVehicleOnlyChoice()
    local raw = GetResourceKvpString(LAYOUT_KVP)
    if type(raw) ~= 'string' or raw == '' then return nil end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' and type(decoded.minimapVehicleOnly) == 'boolean' then
        return decoded.minimapVehicleOnly
    end
    return nil
end
vehicleOnlyChoice = loadVehicleOnlyChoice()

local function emptyLayout()
    return {
        offsets = {}, scales = {}, justifications = {}, hidden = {}, settings = {},
        gaugesBottomAnchored = true, minimapVehicleOnly = minimapVehicleOnly(),
    }
end

-- Unified /ui editor (Config.uiEditor). kora_hud hosts it: its NUI draws the
-- panel and an outline proxy for every element another resource registered
-- through exports.kora_hud:registerUiElement (client/uiregistry.lua), and the
-- owners are told where to put their real element with the client-local event
-- `kora_hud:ui:apply`. With the editor disabled none of this runs and
-- /hudlayout behaves exactly as before.
local UI = type(Config.uiEditor) == 'table' and Config.uiEditor or {}
local function uiEnabled()
    return HudUi ~= nil and UI.enabled ~= false and LAYOUT.movable ~= false
end
local function hideAllowed()
    return uiEnabled() and UI.allowHide ~= false
end
local function minimapEditable()
    return uiEnabled() and UI.minimap ~= false
end
-- Bounds on what a submitted layout may grow the KVP blob to.
local MAX_LAYOUT_ENTRIES = 48
local MAX_LAYOUT_BYTES = 16384
local HIDEABLE_SECTIONS = { gauges = true, vehicle = true, identity = true, status = true }
-- Filled in by the minimap visibility block further down (its locals are
-- declared after this point): isHidden() / setHidden(bool) / toggleEnabled().
local minimapHooks = {}

---Fires a client-local event. Guarded: the smoke tests and a mid-restart
---runtime may not have TriggerEvent, and an owner's handler erroring must not
---abort the editor callback that triggered it.
local function emit(name, ...)
    if type(TriggerEvent) ~= 'function' then return end
    local ok, err = pcall(TriggerEvent, name, ...)
    if not ok then print(('[kora_hud] %s handler failed: %s'):format(name, tostring(err))) end
end

-- Assigned below, once the KVP helpers it needs exist.
local applyToOwners

---Leaves edit mode. Every owner then gets the STORED layout: after a Save that
---is the new one, after a Cancel (or the HUD hiding mid-edit) it undoes the
---previews they were sent. `skipApply` is for a caller that applies itself.
---@param skipApply boolean|nil
local function closeLayout(skipApply)
    if not layoutEditing then return end
    layoutEditing = false
    SetNuiFocus(false, false)
    send('qbhud:layoutMode', false)
    if uiEnabled() then
        emit('kora_hud:ui:editing', false)
        if not skipApply and applyToOwners then applyToOwners('saved') end
    end
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
    status = { minX = -0.95, maxX = 0.00, minY = 0.00, maxY = 1.00 }, -- reaches the bottom edge (the editor keeps it on screen)
    -- kora_chat's composer has a top-left zero point. It is rendered by a
    -- separate NUI, but shares this KVP so /hudlayout remains the one place a
    -- player arranges all of their on-screen interface.
    chatInput = { minX = -0.95, maxX = 0.95, minY = -0.95, maxY = 0.95 },
}
-- Elements registered by other resources (and the minimap) have no fixed
-- anchor here: the editor keeps them on screen from their registered rect, so
-- Lua only enforces "within one screen of the zero point" as a backstop.
local FALLBACK_LAYOUT_LIMIT = 1.0
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

---Scale for any element: HUD sections and the chat composer keep their
---75-150% range, registered elements use their own, and an element whose
---owner is not running is held to the registry's outer 50-200% range.
---@param section string
---@param value any
---@return number|nil
local function layoutScaleFor(section, value)
    if LAYOUT_BOUNDS[section] and not (HudUi and HudUi.get(section)) then return layoutScale(value) end
    if HudUi then
        local def = HudUi.get(section)
        if def then return HudUi.clampScale(def, value) end
        return HudUi.clampScale(nil, value)
    end
    return layoutScale(value)
end

---@param section any
---@return boolean
local function validSection(section)
    if type(section) ~= 'string' or #section > 32 then return false end
    if HudUi then return HudUi.validId(section) end
    return true
end

---The decoded KVP blob, or an empty table. Untrusted: every consumer
---re-validates the fields it reads.
---@return table
local function readRawLayout()
    if LAYOUT.movable == false then return {} end
    local raw = GetResourceKvpString(LAYOUT_KVP)
    if type(raw) ~= 'string' or raw == '' then return {} end
    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return {} end
    return decoded
end

---This player's saved section layout, split for the NUI into offsets and scales.
---
---Returns an empty table for anything malformed rather than raising: a corrupt
---or hand-edited KVP value must cost the player their layout, not their HUD.
---@return table
local function readLayout()
    if LAYOUT.movable == false then return emptyLayout() end

    local raw = GetResourceKvpString(LAYOUT_KVP)
    if type(raw) ~= 'string' or raw == '' then
        local empty = emptyLayout()
        if minimapHooks.isHidden then empty.hidden.minimap = minimapHooks.isHidden() or nil end
        return empty
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' then return emptyLayout() end

    local offsets, scales, justifications, hidden, settings = {}, {}, {}, {}, {}
    local gaugesBottomAnchored = not (type(decoded.gauges) == 'table' and decoded.gauges.bottomAnchored == false)
    local allowHide = hideAllowed()
    for section, entry in pairs(decoded) do
        if validSection(section) and type(entry) == 'table' then
            local justification = layoutJustification(entry.justification)
            local x, y = layoutOffset(section, 'x', entry.x), layoutOffset(section, 'y', entry.y)
            local scale = layoutScaleFor(section, entry.scale)
            if x and y then offsets[section] = { x = x, y = y } end
            if scale then scales[section] = scale end
            if justification then justifications[section] = justification end
            if allowHide and entry.hidden == true and section ~= 'minimap' then hidden[section] = true end
            if HudUi and type(entry.settings) == 'table' then
                local def = HudUi.get(section)
                settings[section] = def and HudUi.cleanSettings(def, entry.settings) or (not def and HudUi.preserveSettings(entry.settings)) or nil
            end
        end
    end
    -- The minimap's visibility is the /minimap toggle's own choice (its own
    -- KVP), so the editor switch and the command can never disagree.
    if minimapHooks.isHidden then hidden.minimap = minimapHooks.isHidden() or nil end
    return {
        offsets = offsets, scales = scales, justifications = justifications,
        hidden = hidden, settings = settings,
        gaugesBottomAnchored = gaugesBottomAnchored, minimapVehicleOnly = minimapVehicleOnly(),
    }
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
    local requestedHidden = hideAllowed() and type(payload.hidden) == 'table' and payload.hidden or {}
    local requestedSettings = uiEnabled() and type(payload.settings) == 'table' and payload.settings or {}
    local gaugesBottomAnchored = payload.gaugesBottomAnchored ~= false
    local clean = {}
    local count = 0

    -- Every entry beyond the first needs a slot; the cap keeps a malformed
    -- submission from growing the stored blob without bound. A setting, scale
    -- or alignment without a move still needs an entry: the zero offset
    -- preserves the component's shipped position.
    local function entryFor(section)
        local entry = clean[section]
        if not entry and count < MAX_LAYOUT_ENTRIES then
            entry = { x = 0, y = 0 }
            clean[section] = entry
            count = count + 1
        end
        return entry
    end

    for section, offset in pairs(offsets) do
        -- Section ids come from the NUI's own fixed list or from the registry;
        -- validSection caps the key length and rejects reserved keys.
        if validSection(section) and type(offset) == 'table' and count < MAX_LAYOUT_ENTRIES then
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
        if validSection(section) and justification then
            local entry = entryFor(section)
            if entry then entry.justification = justification end
        end
    end

    for section, value in pairs(scales) do
        if validSection(section) then
            local scale = layoutScaleFor(section, value)
            if scale then
                local entry = entryFor(section)
                if entry then entry.scale = scale end
            end
        end
    end

    -- Hidden: HUD sections and registered elements that declared hideable.
    -- The minimap is excluded: its visibility is the /minimap toggle's KVP.
    for section, value in pairs(requestedHidden) do
        if value == true and validSection(section) and section ~= 'minimap' then
            local def = HudUi and HudUi.get(section)
            if HIDEABLE_SECTIONS[section] or (def and def.hideable) then
                local entry = entryFor(section)
                if entry then entry.hidden = true end
            end
        end
    end

    -- Settings are only accepted for a registered element, against its schema.
    if HudUi then
        for section, raw in pairs(requestedSettings) do
            local def = validSection(section) and HudUi.get(section)
            if def and not def.internal then
                local values = HudUi.cleanSettings(def, raw)
                if values then
                    local entry = entryFor(section)
                    if entry then entry.settings = values end
                end
            end
        end
    end

    -- Bottom anchoring is opt-out, so old KVPs retain the improved default.
    -- Keep it beside the gauges' other saved settings rather than introducing
    -- a second preference blob for one Boolean.
    if not gaugesBottomAnchored then
        local entry = entryFor('gauges')
        if entry then entry.bottomAnchored = false end
    end

    -- An element whose owner is not running right now could not be shown in
    -- the editor, so the player never had a chance to keep or change it: its
    -- saved entry is carried over instead of silently dropped.
    if uiEnabled() then
        for section, entry in pairs(readRawLayout()) do
            if clean[section] == nil and validSection(section) and type(entry) == 'table'
                and not LAYOUT_BOUNDS[section] and section ~= 'minimap' and not HudUi.get(section)
                and count < MAX_LAYOUT_ENTRIES then
                local x, y = layoutOffset(section, 'x', entry.x), layoutOffset(section, 'y', entry.y)
                if x and y then
                    local kept = { x = x, y = y, scale = layoutScaleFor(section, entry.scale) }
                    if entry.hidden == true then kept.hidden = true end
                    kept.settings = HudUi.preserveSettings(entry.settings)
                    clean[section] = kept
                    count = count + 1
                end
            end
        end
    end

    -- Minimap-only-in-vehicle rides in the same blob. A choice is only stored
    -- once the player picked something other than the server default (or had
    -- already chosen), so players who never touch it keep following the default.
    -- When the server forbids changing it the old saved choice is kept as it was.
    local default, mayChange = minimapVehicleOnlySettings()
    local requested = payload.minimapVehicleOnly
    local previousChoice = vehicleOnlyChoice
    if mayChange and type(requested) == 'boolean' and (requested ~= default or vehicleOnlyChoice ~= nil) then
        vehicleOnlyChoice = requested
    end
    if vehicleOnlyChoice ~= nil then clean.minimapVehicleOnly = vehicleOnlyChoice end
    if HudUi then clean.v = 2 end

    local encoded = json.encode(clean)
    if #encoded > MAX_LAYOUT_BYTES then
        vehicleOnlyChoice = previousChoice
        return false
    end
    SetResourceKvp(LAYOUT_KVP, encoded)
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

---Hands the minimap its per-player layout (nil = the server layout only).
---@param entry table|nil
local function applyMinimapPlayerLayout(entry)
    if not (HudMinimap and HudMinimap.setPlayerLayout) then return end
    if not minimapEditable() or type(entry) ~= 'table' then
        HudMinimap.setPlayerLayout(nil)
        return
    end
    local def = HudUi.get('minimap')
    HudMinimap.setPlayerLayout({
        x = tonumber(entry.x) or 0,
        y = tonumber(entry.y) or 0,
        scale = (def and HudUi.clampScale(def, entry.scale)) or 1,
    })
end

---Tells every registered owner where its element goes. `entries` overrides
---the saved blob (a reset passes {}); every value is re-validated by
---HudUi.layoutFor, so a hand-edited KVP can never reach an owner's CSS.
---@param reason 'saved'|'reset'
---@param entries table|nil
applyToOwners = function(reason, entries)
    if not uiEnabled() then return end
    local saved = entries or readRawLayout()
    for id, def in HudUi.each() do
        if not def.internal then
            emit('kora_hud:ui:apply', def.owner, id, HudUi.layoutFor(def, saved[id]), reason)
        end
    end
    applyMinimapPlayerLayout(saved.minimap)
end

-- The minimap is one of kora_hud's own elements but is drawn by the game, so
-- the editor shows it as a proxy box like an external element. Its rect comes
-- from the same calculation client/minimap.lua applies, so the box sits on the
-- real radar; it is refreshed whenever the editor opens (resolution changes).
local function registerMinimapElement()
    if not minimapEditable() or not (HudMinimap and HudMinimap.screenRect) then
        if HudUi and HudUi.get('minimap') then HudUi.unregister(GetCurrentResourceName(), 'minimap') end
        return
    end
    local managed = HudMinimap.isManaged and HudMinimap.isManaged() or false
    local rect = HudMinimap.screenRect() or { x = 0.01, y = 0.78, w = 0.15, h = 0.19 }
    HudUi.register(GetCurrentResourceName(), {
        id = 'minimap',
        label = 'Minimap',
        group = 'Minimap',
        rect = rect,
        origin = 'left bottom',
        movable = managed,
        scalable = managed,
        hideable = minimapHooks.toggleEnabled and minimapHooks.toggleEnabled() or false,
        scaleMin = 0.6,
        scaleMax = 1.6,
    }, true)
end

-- Layout edit mode is an explicit mode, entered by command, rather than the HUD
-- being draggable all the time. The HUD is pointer-transparent during play and
-- has to stay that way -- a permanently grabbable HUD would eat the clicks the
-- game needs. The NUI takes focus only while this mode is open.
local function openLayoutEditor()
    if LAYOUT.movable == false then
        Kora.notify.send({ title = 'HUD', message = 'Moving HUD sections is disabled on this server.', type = 'error' })
        return
    end

    -- Running the command again while the editor is open must not silently
    -- commit or discard a layout whose result is still being reviewed.
    if not visible or layoutEditing then return end

    layoutEditing = true
    if uiEnabled() then
        registerMinimapElement()
        send('qbhud:uiElements', HudUi.list())
        -- Owners close their own focused UI (chat input, inventory) and show
        -- a preview of their element while the editor is open.
        emit('kora_hud:ui:editing', true)
    end
    SetNuiFocus(true, true)
    send('qbhud:layoutMode', true)
end

local function validCommandName(name)
    return type(name) == 'string' and name:match('^[%w_]+$') ~= nil and #name <= 32
end

RegisterCommand(LAYOUT.command or 'hudlayout', openLayoutEditor, false)
if uiEnabled() then
    local seen = { [LAYOUT.command or 'hudlayout'] = true }
    local names = { UI.command or 'ui' }
    for _, alias in ipairs(type(UI.aliases) == 'table' and UI.aliases or {}) do names[#names + 1] = alias end
    for _, name in ipairs(names) do
        if validCommandName(name) and not seen[name] then
            seen[name] = true
            RegisterCommand(name, openLayoutEditor, false)
        end
    end
end

-- Live preview for elements another resource renders (and the minimap). The
-- HUD's own sections preview in the page itself. Only accepted while the
-- editor is open; values are re-validated by HudUi.layoutFor before an owner
-- sees them. The minimap applies on `final` (the drop) only: every apply costs
-- one bigmap refresh, which must not run at the page's drag rate.
RegisterNUICallback('qbhud:uiPreview', function(payload, cb)
    cb({})
    if not layoutEditing or not uiEnabled() then return end
    if type(payload) ~= 'table' or type(payload.elements) ~= 'table' then return end
    local count = 0
    for id, entry in pairs(payload.elements) do
        count = count + 1
        if count > MAX_LAYOUT_ENTRIES then break end
        local def = validSection(id) and HudUi.get(id)
        if def and type(entry) == 'table' then
            if def.internal then
                if id == 'minimap' and payload.final == true then applyMinimapPlayerLayout(entry) end
            else
                emit('kora_hud:ui:apply', def.owner, id, HudUi.layoutFor(def, entry), 'preview')
            end
        end
    end
end)

-- Confirm and Cancel are deliberately one callback. Both release NUI focus;
-- only Confirm supplies geometry to persist. Until this callback arrives all
-- dragging is merely a browser-side preview, so Cancel never needs a rollback
-- write and cannot briefly persist a layout the player rejected.
RegisterNUICallback('qbhud:finishLayout', function(payload, cb)
    -- Answer first and unconditionally, same reasoning as qbhud:ready above.
    cb({})
    if not layoutEditing then return end

    if type(payload) == 'table' and payload.confirmed == true then
        local ok, saved = pcall(writeLayout, payload)
        if ok and saved == false and LAYOUT.movable ~= false and type(payload) == 'table' then
            Kora.notify.send({ title = 'UI', message = 'That layout is too large to save. Reset a few elements and try again.', type = 'error' })
        end
        if hideAllowed() and type(payload.hidden) == 'table' and minimapHooks.setHidden then
            local requested = payload.hidden.minimap
            if type(requested) == 'boolean' then minimapHooks.setHidden(requested) end
        end
        syncChatInputLayout()
        -- Always re-evaluate: "only in vehicle = off" can lift the on-foot gate
        -- without changing minimapVehicleOnly() itself.
        if minimapChoiceChanged then minimapChoiceChanged() end
    end

    -- Saved or cancelled, closeLayout hands every owner the stored layout.
    closeLayout()
end)

-- `reset` is separate from the editor rather than a button inside it: a player
-- whose layout put a section somewhere unreachable needs a way out that does
-- not require clicking on the HUD.
local function resetLayout()
    DeleteResourceKvp(LAYOUT_KVP)
    vehicleOnlyChoice = nil
    closeLayout(true)
    send('qbhud:layoutReset', true)
    syncChatInputLayout()
    applyToOwners('reset', {})
    if minimapHooks.sync then minimapHooks.sync(false) end -- the page clears its hidden switches
    if minimapChoiceChanged then minimapChoiceChanged() end
    Kora.notify.send({ title = 'HUD', message = 'HUD layout reset to defaults.', type = 'success' })
end
RegisterCommand('hudlayoutreset', resetLayout, false)
if uiEnabled() and validCommandName(UI.resetCommand or 'uireset') and (UI.resetCommand or 'uireset') ~= 'hudlayoutreset' then
    RegisterCommand(UI.resetCommand or 'uireset', resetLayout, false)
end

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

-- Harness icon beside the belt (Config.seatbelt.harnessIcon, read live):
-- 'attached' = only while a harness is on, 'always' = also a dimmed "none"
-- icon, 'off' = never. nil leaves the field out of the payload (no icon).
local function harnessIconState()
    local mode = type(Config.seatbelt) == 'table' and Config.seatbelt.harnessIcon or 'attached'
    if mode == 'off' or mode == false or not HudBridge.getHarness then return nil end
    local attached = HudBridge.getHarness() == true
    if attached or mode == 'always' then return attached end
    return nil
end

-- kora_lib draws its progress bar in its own NUI frame at the bottom centre,
-- under this frame, exactly where the gauge row sits while a vehicle panel is
-- shown. Report an active bar so the NUI can lift the gauges clear of it.
local function progressBarActive()
    if Config.hud.avoidProgressBar == false then return false end
    local ok, active = pcall(function() return Kora.progressbar.isActive() end)
    return ok and active == true
end

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
        harness = harnessIconState(),
        progress = progressBarActive(),
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
        or payload.harness ~= lastVehiclePayload.harness
        or payload.progress ~= lastVehiclePayload.progress
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
local minimapHiddenChoice = loadMinimapChoice()

-- On-foot override. In 'vehicle' mode (and with "minimap only in vehicle") the
-- radar is hidden on foot, so a player who asks for the map back there needs a
-- choice that outranks that gate. Set by the toggle when it is pressed on foot
-- and saved next to the hide choice; also granted by an explicit "minimap only
-- in vehicle = off" in /hudlayout. Config.hud.minimapToggle.allowOnFoot gates both.
local MINIMAP_FOOT_KVP = 'kora_hud:minimapOnFoot'
local function loadMinimapOnFoot()
    return MINIMAP_TOGGLE.remember ~= false and GetResourceKvpString(MINIMAP_FOOT_KVP) == '1'
end
local minimapOnFootChoice = loadMinimapOnFoot()

---Whether this player's own choice currently lifts the vehicle-only gate.
local function minimapOnFootForced()
    if MINIMAP_TOGGLE.allowOnFoot == false then return false end
    if minimapOnFootChoice and minimapToggleEnabled() then return true end
    local _, mayChange = minimapVehicleOnlySettings()
    return mayChange and vehicleOnlyChoice == false
end

---Whether the player's choice is currently hiding the radar.
local function minimapPlayerHidden()
    return minimapToggleEnabled() and minimapHiddenChoice == true
end

---Whether anything wants the radar managed: a mode other than 'always', the
---player's own hide choice, or their "minimap only in vehicle" option.
local function minimapManaged()
    return MINIMAP_MODE ~= 'always' or minimapPlayerHidden() or minimapVehicleOnly()
end

-- The vehicle the radar decision is made from, mirrored from the cache rather
-- than read across the export boundary on every 250ms visibility pass (cost
-- model rule 3). Subscribed lazily, the first time a mode actually needs it, so
-- a server in 'always' mode with nobody using "only in vehicle" never pays for
-- the notification. Falls back to the direct read if subscribing failed (e.g.
-- kora_lib mid-restart) and retries the subscription on the next pass.
local radarVehicleMirror -- nil until subscribed, then the vehicle or false
local onRadarVehicleChange -- assigned in the visibility block below

---@return integer|false|nil
radarVehicle = function()
    if radarVehicleMirror ~= nil then return radarVehicleMirror end
    local subscribed = pcall(function()
        Kora.cache.onChange("vehicle", function(vehicle)
            radarVehicleMirror = vehicle or false
            if onRadarVehicleChange then onRadarVehicleChange() end
        end)
    end)
    local ok, vehicle = pcall(function() return Kora.cache.vehicle() end)
    vehicle = ok and vehicle or nil
    if subscribed then radarVehicleMirror = vehicle or false end
    return vehicle
end

-- A kora_lib restart drops its onChange listeners, so forget the mirror and
-- resubscribe on the next pass instead of trusting a value that no longer updates.
AddEventHandler("onClientResourceStart", function(resource)
    if resource == "kora_lib" then radarVehicleMirror = nil end
end)

---Whether the radar should be on screen right now, or nil for "not our call".
---The player's hide choice and 'never' win over everything; 'vehicle' mode and
---the per-player vehicle-only option share one test (any seat of a vehicle).
---@return boolean|nil
local function minimapShouldShow()
    if minimapPlayerHidden() then return false end
    if MINIMAP_MODE == 'never' then return false end
    if MINIMAP_MODE == 'vehicle' or minimapVehicleOnly() then
        local vehicle = radarVehicle()
        if vehicle ~= nil and vehicle ~= false and vehicle ~= 0 then return true end
        return minimapOnFootForced()
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

    -- Registered in every mode so a live change of `minimap`, of the toggle or
    -- of the vehicle-only option needs no restart, but only RUNS when something
    -- wants the radar managed: 'always' with the player neither hiding it nor
    -- limiting it to vehicles is still hands-off.
    minimapVisibilityTask = addTask({
        interval = MINIMAP_INTERVAL,
        active = minimapManaged,
        run = applyMinimap,
    })

    -- Entering or leaving a vehicle applies the radar on the spot; the task's
    -- next pass then finds nothing changed.
    onRadarVehicleChange = function()
        if visible and not radarHeldHidden and minimapManaged() then applyMinimap() end
    end

    ---Applies a changed player choice at once instead of on the next tick.
    ---With nothing managing the radar there is no task running, so un-hiding
    ---must hand the radar back explicitly.
    minimapChoiceChanged = function()
        if not minimapManaged() then
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
    if hudVisible and minimapManaged() then return end
    DisplayRadar(true)
end

local minimapChoiceSet = false

local function toggleMinimap()
    if not minimapToggleEnabled() then
        Kora.notify.send({ title = 'Minimap', message = 'The minimap toggle is disabled on this server.', type = 'error' })
        return
    end

    -- Decide from what the player sees now, so the toggle on foot in 'vehicle'
    -- mode turns the (hidden) map on instead of flipping an invisible flag.
    local showing = minimapShouldShow()
    if showing == nil then showing = not minimapPlayerHidden() end
    local remember = MINIMAP_TOGGLE.remember ~= false

    minimapChoiceSet = true
    minimapHiddenChoice = showing
    -- Turning it on while the vehicle gate hides it is the on-foot override;
    -- turning it on elsewhere, or off, leaves the gate as the mode defines it.
    local vehicle = radarVehicle()
    local onFoot = vehicle == nil or vehicle == false or vehicle == 0
    local gated = not showing and onFoot and MINIMAP_MODE ~= 'never'
        and (MINIMAP_MODE == 'vehicle' or minimapVehicleOnly())
    minimapOnFootChoice = gated and MINIMAP_TOGGLE.allowOnFoot ~= false
    if remember then
        SetResourceKvp(MINIMAP_KVP, minimapHiddenChoice and 'hidden' or 'visible')
        if minimapOnFootChoice then SetResourceKvp(MINIMAP_FOOT_KVP, '1') else DeleteResourceKvp(MINIMAP_FOOT_KVP) end
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

-- The /ui editor's minimap "Visible" switch is this same choice, so the switch
-- and the command can never disagree (see minimapHooks near readLayout).
-- What the switch shows: hidden by the player's choice, or held back on foot by
-- the vehicle gate (so a player on foot sees it Off and can turn it On).
local function minimapEditorHidden()
    if minimapPlayerHidden() then return true end
    return minimapToggleEnabled() and MINIMAP_TOGGLE.allowOnFoot ~= false
        and MINIMAP_MODE ~= 'never' and minimapShouldShow() == false
end

-- The value the editor page currently holds for the switch (what it was last
-- sent, then what it last submitted). The page sends it back on every confirm,
-- so only a difference from it is the player actually flipping the switch.
local minimapEditorShown
minimapHooks.sync = function(hidden) minimapEditorShown = hidden == true end
minimapHooks.isHidden = minimapEditorHidden
minimapHooks.toggleEnabled = minimapToggleEnabled
minimapHooks.setHidden = function(hidden)
    hidden = hidden == true
    local shown = minimapEditorShown
    if shown == nil then shown = minimapEditorHidden() end
    minimapEditorShown = hidden
    if not minimapToggleEnabled() or hidden == shown then return end
    minimapChoiceSet = true
    minimapHiddenChoice = hidden
    if hidden then
        minimapOnFootChoice = false
    else
        -- Turning it on while the vehicle gate would hide it is the on-foot
        -- override, same as the toggle command does on foot.
        local gated = MINIMAP_MODE ~= 'never' and (MINIMAP_MODE == 'vehicle' or minimapVehicleOnly())
        minimapOnFootChoice = gated and MINIMAP_TOGGLE.allowOnFoot ~= false
    end
    if MINIMAP_TOGGLE.remember ~= false then
        SetResourceKvp(MINIMAP_KVP, minimapHiddenChoice and 'hidden' or 'visible')
        if minimapOnFootChoice then SetResourceKvp(MINIMAP_FOOT_KVP, '1') else DeleteResourceKvp(MINIMAP_FOOT_KVP) end
    end
    minimapChoiceChanged()
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
-- Cache listeners live in kora_lib and are dropped when it restarts, so they
-- are registered from subscribeCache() (defined below, called at load and again
-- on every kora_lib start) rather than once at file scope.
Voice.onChange(function(value) setVital('talking', value == true) end)
Voice.onModeChange(function(value) setVital('voiceMode', value) end)

-- Stamina moves continuously while sprinting -- it belongs to no framework
-- delta and no adapter can announce it -- which makes it far and away the
-- highest-frequency notification the HUD receives, and each one is a
-- cross-resource funcref invocation. So it is subscribed ONLY when something
-- actually renders it: a server with the stamina ring switched off pays
-- nothing for it, rather than paying to receive and discard it.

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

local function onPedChange(ped)
    refreshMaxHealth(ped)
    -- A respawn rebuilds the minimap, which is the one moment the suppression
    -- above is most likely to have been dropped. Re-assert it now rather than
    -- leaving the stock cluster on screen until the next interval.
    if visible then setupMinimapHealthArmour(MINIMAP_DRAW_NEITHER) end
end

-- Vehicle lifecycle is announced; only the telemetry inside it is sampled.
-- Both edges push on the spot rather than waiting for the sampling task's next
-- turn: getting into a car should fill the panel on the frame the door shuts,
-- and getting out should clear it just as fast (that push is the null payload
-- the NUI reads as "on foot"). The task's own next run is deduplicated against
-- this one, so the immediacy costs no extra message.
local function onVehicleChange(vehicle)
    currentVehicle = vehicle or false
    pushVehicleUpdate()
    if currentVehicle then startScheduler() end
end

local function subscribeCache()
    Kora.cache.onChange("health", function(value) setVital('health', round(value)) end)
    Kora.cache.onChange("armour", function(value) setVital('armour', round(value)) end)
    if ELEMENTS.stamina then
        Kora.cache.onChange("stamina", function(value) setVital('stamina', round(value)) end)
    end
    Kora.cache.onChange("ped", onPedChange)
    if ELEMENTS.vehicle then Kora.cache.onChange("vehicle", onVehicleChange) end
end

subscribeCache()

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

-- After a kora_lib restart: register the listeners again and catch up on any
-- change missed while it was down (onChange never reports the current value).
-- setVital and onVehicleChange are no-ops when nothing changed.
AddEventHandler("onClientResourceStart", function(resource)
    if resource ~= "kora_lib" then return end
    if not pcall(subscribeCache) then return end
    pcall(function()
        setVital('health', round(Kora.cache.health()))
        setVital('armour', round(Kora.cache.armour()))
        if ELEMENTS.stamina then setVital('stamina', round(Kora.cache.stamina())) end
        onPedChange(Kora.cache.ped())
        if ELEMENTS.vehicle and (Kora.cache.vehicle() or false) ~= currentVehicle then
            onVehicleChange(Kora.cache.vehicle())
        end
    end)
end)

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

-- The pause menu and the full map (ESC, P) are drawn by the engine ABOVE the
-- game screen but BELOW the NUI, so the HUD would sit over the map and its
-- legend. While Config.hud.hideOnPauseMenu is on the NUI is told to hide, and
-- told to show again when the menu closes. This is only the NUI's drawn state:
-- `visible`, the radar policy, forced hides and the minimap toggle are not
-- touched, so whatever else hides the HUD keeps doing so after the menu closes.
-- It is a scheduler task (nothing runs while the HUD is hidden) and sends one
-- message per open/close, never one per tick.
local pauseHidden = false

local function pauseMenuActive()
    if Config.hud.hideOnPauseMenu == false then return false end
    local ok, active = pcall(IsPauseMenuActive)
    return ok and active == true
end

local function nuiVisible()
    return visible and not pauseHidden
end

local function syncPauseHidden()
    local active = pauseMenuActive()
    if active == pauseHidden then return end
    pauseHidden = active
    if visible then send("qbhud:visibility", nuiVisible()) end
end

addTask({
    interval = MINIMAP_INTERVAL,
    active = function() return true end,
    run = syncPauseHidden,
})

local function refreshVisibility()
    local newVisible = loggedIn and not forcedHidden
    if radarHeldHidden and not wantsRadarHeldHidden(loggedIn, forcedHidden, resourceStopping) then
        releaseHeldRadar(newVisible)
    end
    if not newVisible then closeLayout() end
    if newVisible == visible then return end
    visible = newVisible
    -- Hidden HUDs do not poll, so the pause state may be stale on a show.
    pauseHidden = visible and pauseMenuActive()
    syncVoiceSampling()
    send("qbhud:visibility", nuiVisible())

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
        else
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

-- /ui element registry surface (client/uiregistry.lua). The owner is always
-- the invoking resource, never an argument, so one resource can neither
-- claim nor change another's element. Every registration answers at once with
-- the player's saved layout through `kora_hud:ui:apply`, so an owner has to
-- add its handler BEFORE it registers and needs no separate read.
local uiElementsQueued = false
local function queueUiElements()
    if uiElementsQueued then return end
    uiElementsQueued = true
    -- Coalesced: a resource registering several elements sends one list.
    CreateThread(function()
        Wait(100)
        uiElementsQueued = false
        send('qbhud:uiElements', HudUi.list())
    end)
end
if HudUi then HudUi.onChange(queueUiElements) end

local function invoker()
    local owner = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    if type(owner) ~= 'string' or owner == '' or owner == GetCurrentResourceName() then return nil end
    return owner
end

exports('registerUiElement', function(def)
    if not uiEnabled() or UI.allowExternal == false then return false, 'ui editor disabled' end
    local owner = invoker()
    if not owner then return false, 'unknown owner' end
    local clean, err = HudUi.register(owner, def)
    if not clean then return false, err end
    emit('kora_hud:ui:apply', owner, clean.id, HudUi.layoutFor(clean, readRawLayout()[clean.id]), 'saved')
    return true
end)

exports('updateUiElement', function(id, patch)
    if not uiEnabled() then return false, 'ui editor disabled' end
    local owner = invoker()
    if not owner then return false, 'unknown owner' end
    return HudUi.update(owner, id, patch)
end)

exports('unregisterUiElement', function(id)
    if not HudUi then return false end
    local owner = invoker()
    if not owner then return false end
    return HudUi.unregister(owner, id)
end)

exports('getUiLayout', function(id)
    local def = uiEnabled() and HudUi.get(id)
    if not def then return nil end
    return HudUi.layoutFor(def, readRawLayout()[id])
end)

-- A stopped owner's elements leave the editor; their saved layout stays.
AddEventHandler('onClientResourceStop', function(resource)
    if HudUi and resource ~= GetCurrentResourceName() then HudUi.dropOwner(resource) end
end)

-- Assignment, NOT `local function`: that would declare a fresh local shadowing
-- the forward declaration at the top of the file, silently leaving the
-- qbhud:ready callback's upvalue nil.
sendInitialState = function()
    local savedLayout = readLayout()
    if minimapHooks.sync then minimapHooks.sync(savedLayout.hidden.minimap == true) end
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
            -- Effective value for this player, the server default it resets
            -- to, and whether the editor may offer the switch at all.
            minimapVehicleOnly = savedLayout.minimapVehicleOnly,
            minimapVehicleOnlyDefault = (minimapVehicleOnlySettings()),
            minimapVehicleOnlyAllowed = select(2, minimapVehicleOnlySettings()),
            -- Seeded from this player's own machine. Sent with the config
            -- rather than on its own channel so the HUD's first paint is
            -- already in the right place instead of visibly jumping.
            offsets = savedLayout.offsets,
            scales = savedLayout.scales,
            justifications = savedLayout.justifications,
            gaugesBottomAnchored = savedLayout.gaugesBottomAnchored,
            -- /ui editor additions (all optional for the page).
            hidden = savedLayout.hidden,
            settings = savedLayout.settings,
            editor = {
                enabled = uiEnabled(),
                allowHide = hideAllowed(),
                command = uiEnabled() and (UI.command or 'ui') or (LAYOUT.command or 'hudlayout'),
                previewInterval = math.max(50, math.min(1000, tonumber(UI.previewInterval) or 100)),
            },
        },
    })
    if uiEnabled() then send('qbhud:uiElements', HudUi.list()) end

    send("qbhud:visibility", nuiVisible())
    send("qbhud:compat", HudCompat.state)

    if visible then
        -- Direct, un-throttled and unconditional: this is a REMOUNT, so the
        -- page holds no state at all and the change checks the channels rely
        -- on would happily conclude there is nothing to say.
        flushVitals()
        flushPlayer()
        pushVehicleUpdate(true)
    end
end

HudCompat.attach({
    overlay = function(fields)
        local merged = {}
        for key, value in pairs(latestBridgeSnapshot) do merged[key] = value end
        for key, value in pairs(fields) do merged[key] = value end
        latestBridgeSnapshot = merged
        requestPlayer()
    end,
    snapshot = function() return latestBridgeSnapshot end,
    push = function() send("qbhud:compat", HudCompat.state) end,
    applyMinimap = function()
        Wait(50)
        HudMinimap.apply(true)
    end,
})

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
    if uiEnabled() then
        -- The minimap's own per-player layout, before its first apply pass
        -- (that pass waits for the radar to exist, so this always wins).
        registerMinimapElement()
        applyMinimapPlayerLayout(readRawLayout().minimap)
        -- Owners that started before this (re)start register again.
        emit('kora_hud:ui:ready')
    end
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

    local previousVehicleOnly = minimapVehicleOnly()
    Config.hud = type(settings.hud) == 'table' and settings.hud or Config.hud
    Config.voice = type(settings.voice) == 'table' and settings.voice or Config.voice
    Config.poll = type(settings.poll) == 'table' and settings.poll or Config.poll
    Config.layout = type(settings.layout) == 'table' and settings.layout or Config.layout
    Config.uiEditor = type(settings.uiEditor) == 'table' and settings.uiEditor or Config.uiEditor
    UI = type(Config.uiEditor) == 'table' and Config.uiEditor or {}

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
    local previousOnFoot = minimapOnFootForced()
    MINIMAP_TOGGLE = Config.hud.minimapToggle or {}
    if not minimapChoiceSet then
        minimapHiddenChoice = loadMinimapChoice()
        minimapOnFootChoice = loadMinimapOnFoot()
    end
    local previousMinimapMode = MINIMAP_MODE
    MINIMAP_MODE = type(Config.hud.minimap) == 'string' and Config.hud.minimap or 'always'
    if previousMinimapMode ~= MINIMAP_MODE and MINIMAP_MODE == 'always' then
        minimapRelease()
    end
    if previousPlayerHidden ~= minimapPlayerHidden() or previousVehicleOnly ~= minimapVehicleOnly()
        or previousOnFoot ~= minimapOnFootForced() then
        minimapChoiceChanged()
    end

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
