-- Minimap layout owner. When Config.hud.minimapLayout.enabled is true and the
-- shape is not 'stock', kora_hud
--   * streams in its own square radar mask (stream/kora_hud_squaremap.ytd,
--     texture 'radarmasksm', black = clipped, grey = visible) and swaps it in for
--     the radarmasksm/radarmask1g textures of platform:/textures/graphics, and
--   * positions the minimap, minimap_mask and minimap_blur components,
-- then refreshes the radar once, because the engine only re-reads component
-- rects and masks on a bigmap toggle. This is the proven GTA route used by the
-- widely deployed qb-hud/ps-hud square map; a runtime-built PNG texture is not:
-- the radar reads the mask from the colour channels, so a mask that is white in
-- RGB clips nothing.
--
-- The rects are config (Config.hud.minimapLayout.shapes.<shape>.rects), left /
-- bottom anchored and NOT scaled for the aspect ratio: the engine already lays
-- out L/B components in a 16:9 space. Only x gets the ultrawide offset.
--
-- Everything that touches natives runs on ONE worker (run / reconcile) and is
-- the only caller of SetBigmapActive besides the stuck-bigmap guard and the
-- resource-stop cleanup below. Every caller (poll, spawn, export, config
-- change) just asks for a pass; requests that arrive during a pass coalesce
-- into one more pass with the latest values, so there is exactly one bigmap
-- refresh per change and never two overlapping toggles.
--
-- With layout disabled or shape 'stock' nothing is touched (pure vanilla); if
-- something was applied earlier it is undone cleanly. The same cleanup runs
-- when this resource stops, so a txAdmin restart reverts and re-applies.
--
-- Config.hud.minimapLayout is read at use time (kora_lib live config replaces
-- Config.hud wholesale), so a change takes effect on the next poll.
HudMinimap = {}

local REFERENCE_ASPECT = 16 / 9
local MASK_TXD = 'platform:/textures/graphics'
local MASK_TARGETS = { 'radarmasksm', 'radarmask1g' }

HudMinimap.COMPONENTS = { 'minimap', 'minimap_mask', 'minimap_blur' }

-- Short config keys for the per-component fine offsets.
local FINE_KEY = { minimap = 'map', minimap_mask = 'mask', minimap_blur = 'blur' }

local function number(value, fallback, min, max)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    if value < min then return min end
    if value > max then return max end
    return value
end

local function layoutConfig()
    local hud = type(Config) == 'table' and Config.hud
    local cfg = type(hud) == 'table' and hud.minimapLayout
    return type(cfg) == 'table' and cfg or nil
end

---The layout config, or nil while the layout is disabled.
local function settings()
    local cfg = layoutConfig()
    if not cfg or cfg.enabled ~= true then return nil end
    return cfg
end

---Square is the default shape; 'circle' and 'stock' are the other two.
local function shapeName(cfg)
    local shape = type(cfg) == 'table' and cfg.shape
    if shape == 'circle' or shape == 'stock' then return shape end
    return 'square'
end

local function shapeDef(cfg, shape)
    local shapes = type(cfg) == 'table' and cfg.shapes
    local def = type(shapes) == 'table' and shapes[shape]
    if type(def) ~= 'table' or type(def.rects) ~= 'table' then return nil end
    return def
end

---Current screen aspect ratio plus the resolution it came from. Uses the real
---render resolution (GetActiveScreenResolution); GetAspectRatio is the fallback.
local function screen()
    local ok, w, h = pcall(GetActiveScreenResolution)
    w, h = tonumber(w), tonumber(h)
    if ok and w and h and w > 0 and h > 0 then return w / h, w, h end
    local okAspect, aspect = pcall(GetAspectRatio, false)
    aspect = tonumber(aspect)
    if okAspect and aspect and aspect > 0 then return aspect end
    return REFERENCE_ASPECT
end

---x offset for screens wider than 16:9: ((16/9 - aspect) / divisor) + bias,
---0 at or below 16:9 (and within `tolerance` above it, which absorbs windowed
---sizes such as 1919x1079).
---@param aspect number
---@param cfg table|nil Config.hud.minimapLayout
---@return number
function HudMinimap.aspectOffset(aspect, cfg)
    aspect = number(aspect, REFERENCE_ASPECT, 1.0, 10.0)
    local o = type(cfg) == 'table' and cfg.aspectOffset
    o = type(o) == 'table' and o or {}
    local tolerance = number(o.tolerance, 0.0, 0.0, 0.5)
    if aspect <= REFERENCE_ASPECT + tolerance then return 0.0 end
    return (REFERENCE_ASPECT - aspect) / number(o.divisor, 3.6, 0.1, 100.0) + number(o.bias, -0.008, -1.0, 1.0)
end

---Horizontal compression of the engine's L/B layout space on this screen: the
---engine lays left/bottom-anchored components out in a centred 16:9 frame, so
---on a wider screen one unit of component x covers less than one unit of
---screen width. This is the same fact `aspectOffset` compensates for.
---@param aspect number
---@return number k in (0, 1]
function HudMinimap.compression(aspect)
    aspect = number(aspect, REFERENCE_ASPECT, 1.0, 10.0)
    if aspect > REFERENCE_ASPECT then return REFERENCE_ASPECT / aspect end
    return 1.0
end

-- Per-player layout from the /ui editor, on top of everything the server
-- config does: x/y are SCREEN fractions (what the player dragged), scale a
-- multiplier about the map's bottom-left corner. nil = server layout only.
local playerLayout

---Sanitised copy of a player layout, or nil for "no change from the server".
local function cleanPlayer(layout)
    if type(layout) ~= 'table' then return nil end
    local x, y = number(layout.x, 0.0, -1.0, 1.0), number(layout.y, 0.0, -1.0, 1.0)
    local scale = number(layout.scale, 1.0, 0.6, 1.6)
    if x == 0 and y == 0 and scale == 1 then return nil end
    return { x = x, y = y, scale = scale }
end

---Transforms the component rects by the player layout: scale about the map's
---bottom-left corner (native y IS the bottom edge for 'B' alignment), then
---move by the dragged screen offset converted into L/B units.
local function applyPlayer(out, player, aspect)
    if not player then return out end
    local k = HudMinimap.compression(aspect)
    local ax, ay = out.minimap.x, out.minimap.y
    local dx, dy, s = player.x / k, player.y, player.scale
    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local r = out[name]
        r.x = ax + (r.x - ax) * s + dx
        r.y = ay + (r.y - ay) * s + dy
        r.w = r.w * s
        r.h = r.h * s
    end
    return out
end

---Computes the three component rects for the configured shape, or nil when the
---shape has no valid rects in the config.
---@param aspect number
---@param safezone number GetSafeZoneSize()
---@param cfg table|nil Config.hud.minimapLayout
---@param player table|nil per-player layout { x, y, scale } (ignored for 'stock')
---@return table<string, {x:number, y:number, w:number, h:number}>|nil
function HudMinimap.layout(aspect, safezone, cfg, player)
    cfg = type(cfg) == 'table' and cfg or {}
    local shape = shapeName(cfg)
    local def = shapeDef(cfg, shape)
    if not def then return nil end
    -- 'stock' is the vanilla rects exactly: used to put the stock layout back.
    local stock = shape == 'stock'

    safezone = number(safezone, 1.0, 0.5, 1.0)
    local scale = stock and 1.0 or number(cfg.scale, 1.0, 0.5, 2.0)
    local shiftX = stock and 0.0 or number(cfg.x, 0.0, -1.0, 1.0)
    local shiftY = stock and 0.0 or number(cfg.y, 0.0, -1.0, 1.0)
    -- The engine already anchors L/B components inside the safezone; the
    -- optional compensation cancels part of that margin for builds where the
    -- mask drifts relative to the blur at small safezones.
    local compensation = stock and 0.0 or number(cfg.safezoneCompensation, 0.0, 0.0, 2.0)
    local margin = (1.0 - safezone) / 2.0 * compensation
    local offset = stock and 0.0 or HudMinimap.aspectOffset(aspect, cfg)
    local fine = (not stock and type(cfg.offsets) == 'table') and cfg.offsets or {}

    local out = {}
    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local base = def.rects[name]
        if type(base) ~= 'table' then return nil end
        local x, y = number(base.x, nil, -1.0, 1.0), number(base.y, nil, -1.0, 1.0)
        local w, h = number(base.w, nil, 0.0, 1.0), number(base.h, nil, 0.0, 1.0)
        if not (x and y and w and h and w > 0 and h > 0) then return nil end
        local own = fine[FINE_KEY[name]]
        own = type(own) == 'table' and own or {}
        out[name] = {
            x = (x + offset) * scale - margin + shiftX + number(own.x, 0.0, -1.0, 1.0),
            y = y * scale + margin + shiftY + number(own.y, 0.0, -1.0, 1.0),
            w = w * scale,
            h = h * scale,
        }
    end
    if stock then return out end
    return applyPlayer(out, cleanPlayer(player), aspect)
end

---Screen-space box (viewport fractions, top-left origin) of a minimap
---component rect, for the /ui editor's proxy. Inverse of the engine's L/B
---placement: x inside the centred 16:9 frame, bottom edge at 1 - margin + y.
---@param rect table|nil component rect; default: the current layout's map
---@param aspect number|nil
---@param safezone number|nil
---@return {x:number, y:number, w:number, h:number}|nil
function HudMinimap.screenRect(rect, aspect, safezone)
    if not rect then
        local cfg = layoutConfig()
        if not cfg or cfg.enabled ~= true then cfg = { shape = 'stock', shapes = cfg and cfg.shapes } end
        local rects
        if cfg.shapes then
            rects = HudMinimap.layout(aspect or (screen()), 1.0, cfg)
        end
        rect = rects and rects.minimap
        if not rect then return nil end
    end
    aspect = aspect or (screen())
    local zone = safezone
    if not zone then
        local ok, value = pcall(GetSafeZoneSize)
        zone = ok and tonumber(value) or 1.0
    end
    zone = number(zone, 1.0, 0.5, 1.0)
    local k = HudMinimap.compression(aspect)
    local margin = (1.0 - zone) / 2.0
    local x = (1.0 - k) / 2.0 + (margin + rect.x) * k
    local y = 1.0 - margin - rect.h + rect.y
    local w, h = rect.w * k, rect.h
    -- Clamp into the screen so the proxy is always grabbable.
    x = math.max(0.0, math.min(1.0 - math.min(w, 1.0), x))
    y = math.max(0.0, math.min(1.0 - math.min(h, 1.0), y))
    return { x = x, y = y, w = math.min(w, 1.0), h = math.min(h, 1.0) }
end

local function now()
    if type(GetGameTimer) == 'function' then return GetGameTimer() end
    return 0
end

local function warn(message)
    print('[kora_hud] minimap: ' .. message)
end

-- What this resource has changed in the game, nil while it has changed nothing.
-- Set BEFORE the first native so an interrupted pass is still undone.
local state = { applied = nil }
local running, pending = false, false
local refreshing = false -- the bigmap is on because of our own refresh
local stopped, settled, failed = false, false, false
-- Set once a pass has started changing things. A request that arrives before
-- that is already covered by the running pass (it reads the config after its
-- waits), so only later requests need another pass.
local committed = false
local failures, retryAt = 0, 0
local requestedDict
local lastKey -- snapshot of the last applied screen + config, nil forces a pass
local bigmapSeen = 0

---The safezone only matters when safezoneCompensation is used; otherwise the
---native is not even read.
local function safezoneFor(cfg)
    if (tonumber(cfg.safezoneCompensation) or 0) == 0 then return 1.0 end
    local ok, zone = pcall(GetSafeZoneSize)
    return ok and tonumber(zone) or 1.0
end

-- The change check runs on every poll (once a second, for the whole session),
-- so it compares against a saved deep copy instead of building a json.encode
-- key: while nothing changed it allocates nothing. Config may be edited in
-- place, so table identity alone is not enough.
local MAX_DEPTH = 8

local function copyValue(value, depth)
    if type(value) ~= 'table' or depth >= MAX_DEPTH then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copyValue(v, depth + 1) end
    return out
end

local function sameValue(a, b, depth)
    if a == b then return true end
    if a ~= a and b ~= b then return true end -- NaN
    if type(a) ~= 'table' or type(b) ~= 'table' or depth >= MAX_DEPTH then return false end
    for k, v in pairs(a) do
        if not sameValue(v, b[k], depth + 1) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function near(a, b, eps)
    if a == b then return true end
    return type(a) == 'number' and type(b) == 'number' and math.abs(a - b) < eps
end

---Whether resolution, aspect, safezone or config differ from the last snapshot.
local function snapshotChanged(snap, cfg)
    local aspect, w, h = screen()
    local safezone = safezoneFor(cfg)
    if snap and snap.w == w and snap.h == h and near(snap.aspect, aspect, 5e-6)
        and near(snap.safezone, safezone, 5e-5) and sameValue(cfg, snap.cfg, 0) then
        return false, snap
    end
    return true, { w = w, h = h, aspect = aspect, safezone = safezone, cfg = copyValue(cfg, 0) }
end

-- The radar exists once the player ped does, the loading screen is gone and the
-- minimap scaleform is loaded. IsRadarEnabled is deliberately not used: our own
-- 'minimap only in vehicle' hides the radar on foot.
local function radarReady(scaleform)
    if type(PlayerPedId) == 'function' then
        local ped = PlayerPedId()
        if not ped or ped == 0 then return false end
        if type(DoesEntityExist) == 'function' and not DoesEntityExist(ped) then return false end
    end
    if type(NetworkIsPlayerActive) == 'function' and type(PlayerId) == 'function'
        and not NetworkIsPlayerActive(PlayerId()) then
        return false
    end
    if type(GetIsLoadingScreenActive) == 'function' and GetIsLoadingScreenActive() then return false end
    if scaleform and type(HasScaleformMovieLoaded) == 'function' and not HasScaleformMovieLoaded(scaleform) then
        return false
    end
    return true
end

-- Waits (bounded) for the radar before the first apply, then lets it settle
-- once, instead of applying blindly at resource start.
local function waitUntilReady(cfg)
    if settled then return end
    local okRequest, handle = pcall(RequestScaleformMovie, 'minimap')
    local deadline = now() + number(cfg.readyTimeoutMs, 30000, 0, 600000)
    while now() < deadline do
        local ok, ready = pcall(radarReady, okRequest and handle or nil)
        if ok and ready then break end
        Wait(100)
    end
    Wait(number(cfg.readySettleMs, 2000, 0, 60000))
    settled = true
end

local function loadDict(dict, timeoutMs)
    requestedDict = dict
    RequestStreamedTextureDict(dict, false)
    local deadline = now() + timeoutMs
    while not HasStreamedTextureDictLoaded(dict) do
        if now() >= deadline then return false end
        Wait(0)
    end
    return true
end

local function place(rects)
    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local r = rects[name]
        SetMinimapComponentPosition(name, 'L', 'B', r.x, r.y, r.w, r.h)
    end
end

---Removes the mask replacement, keeping `keepDict` streamed when it is reused.
local function removeTextures(applied, keepDict)
    if not applied.dict then return end
    for _, target in ipairs(MASK_TARGETS) do RemoveReplaceTexture(MASK_TXD, target) end
    if applied.dict ~= keepDict then SetStreamedTextureDictAsNoLongerNeeded(applied.dict) end
    applied.dict = nil
end

---Puts everything this resource changed back to stock. Never raises. Returns
---true when there was something to undo.
local function undoAll()
    local applied = state.applied
    if not applied then return false end
    state.applied = nil
    local cfg = layoutConfig()
    local stock = cfg and shapeDef(cfg, 'stock')
    pcall(removeTextures, applied, nil)
    pcall(SetMinimapClipType, stock and number(stock.clipType, 0, 0, 3) or 0)
    local rects = cfg and HudMinimap.layout(REFERENCE_ASPECT, 1.0, { shape = 'stock', shapes = cfg.shapes })
    if rects then pcall(place, rects) end
    return true
end

---The ONLY bigmap refresh: on, a short wait, off. Always ends off.
local function refreshBigmap(cfg)
    refreshing = true
    local ok, err = pcall(function()
        SetBigmapActive(true, false)
        Wait(number(cfg and cfg.bigmapWaitMs, 50, 0, 1000))
    end)
    pcall(SetBigmapActive, false, false)
    refreshing = false
    if not ok then warn('bigmap refresh failed: ' .. tostring(err)) end
end

---The state the current config asks for, or nil for stock / invalid.
local function desired(cfg)
    local shape = shapeName(cfg)
    if shape == 'stock' then return nil end
    local def = shapeDef(cfg, shape)
    local rects = def and HudMinimap.layout((screen()), safezoneFor(cfg), cfg, playerLayout)
    if not rects then return nil, 'shape "' .. shape .. '" has no valid rects in Config.hud.minimapLayout.shapes, keeping the stock minimap' end
    local want = { shape = shape, rects = rects, clipType = number(def.clipType, shape == 'circle' and 1 or 0, 0, 3) }
    if shape == 'square' then
        if type(cfg.textureDict) ~= 'string' or cfg.textureDict == '' then
            return nil, 'shape "square" needs Config.hud.minimapLayout.textureDict, keeping the stock minimap'
        end
        want.dict = cfg.textureDict
        want.texture = type(cfg.maskTexture) == 'string' and cfg.maskTexture ~= '' and cfg.maskTexture or MASK_TARGETS[1]
        want.timeout = number(cfg.dictTimeoutMs, 5000, 0, 120000)
    end
    return want
end

local function applyWanted(want)
    if want.dict and not loadDict(want.dict, want.timeout) then
        return false, string.format('texture dictionary "%s" did not stream in within %d ms (is stream/ started?), keeping the stock minimap',
            want.dict, want.timeout)
    end
    state.applied = state.applied or {}
    removeTextures(state.applied, want.dict)
    SetMinimapClipType(want.clipType)
    if want.dict then
        for _, target in ipairs(MASK_TARGETS) do AddReplaceTexture(MASK_TXD, target, want.dict, want.texture) end
        state.applied.dict = want.dict
    end
    place(want.rects)
    return true
end

-- A failed apply keeps the stock minimap and is retried a few times (the stream
-- may simply not have been ready), then left alone until a resource starts.
local function markFailed(cfg, problem)
    warn(problem)
    failed = true
    failures = failures + 1
    retryAt = now() + number(cfg and cfg.retryMs, 10000, 1000, 600000)
end

-- One full pass with the config as it is NOW: idempotent, so any mix of
-- coalesced requests ends in the right state.
local function reconcile()
    local cfg = settings()
    if cfg and shapeName(cfg) ~= 'stock' then
        waitUntilReady(cfg)
        cfg = settings() -- live config: use what is current after the wait
    end
    local want, problem
    if cfg then want, problem = desired(cfg) end
    committed = true
    if not want then
        if problem then markFailed(cfg, problem) end
        if undoAll() then refreshBigmap(cfg) end
        return
    end
    local ok, why = applyWanted(want)
    if not ok then
        markFailed(cfg, why)
        if undoAll() then refreshBigmap(cfg) end
        return
    end
    failed, failures = false, 0
    refreshBigmap(cfg)
end

local function run()
    repeat
        pending, committed = false, false
        local ok, err = pcall(reconcile)
        if not ok then
            -- Whatever happened, never leave a half-applied layout or the bigmap on.
            warn('apply failed: ' .. tostring(err))
            failed = true
            pcall(undoAll)
            pcall(SetBigmapActive, false, false)
            refreshing = false
        end
    until not pending or stopped
    running = false
end

local function schedule()
    if stopped then return end
    -- One pass at a time: a request that arrives mid-pass runs once more with
    -- the latest values when the current one finishes.
    if running then
        if committed then pending = true end
        return
    end
    running = true
    CreateThread(run)
end

---Applies the layout to the game. Returns true when the layout is managed (the
---natives are applied from a worker thread), false when it is disabled or the
---shape is 'stock' (nothing is touched; anything applied earlier is undone), so
---callers such as the phone Maps app know to restore the stock positions.
---@param force boolean|nil re-apply even if resolution/config are unchanged
---@return boolean applied
function HudMinimap.apply(force)
    local cfg = settings()
    if not cfg then
        lastKey = nil
        if state.applied then schedule() end
        return false
    end
    local active = shapeName(cfg) ~= 'stock'
    local changed, snap = snapshotChanged(lastKey, cfg)
    if not force and not changed then return active end
    lastKey = snap
    if active or state.applied then schedule() end
    return active
end

---Whether the minimap layout is managed (so a player layout can apply at all).
---@return boolean
function HudMinimap.isManaged()
    local cfg = settings()
    return cfg ~= nil and shapeName(cfg) ~= 'stock'
end

---Sets (or clears, with nil) this player's /ui minimap layout and re-applies
---once if it changed. One call = at most one bigmap refresh.
---@param layout table|nil { x, y, scale }
function HudMinimap.setPlayerLayout(layout)
    local nextLayout = cleanPlayer(layout)
    local same = (nextLayout == nil and playerLayout == nil) or (nextLayout and playerLayout
        and near(nextLayout.x, playerLayout.x, 1e-6) and near(nextLayout.y, playerLayout.y, 1e-6)
        and near(nextLayout.scale, playerLayout.scale, 1e-6))
    if same then return end
    playerLayout = nextLayout
    HudMinimap.apply(true)
end

---@return table|nil the active per-player layout (introspection/tests)
function HudMinimap.playerLayout()
    return playerLayout
end

---True while this resource has changed the game's minimap (introspection/tests).
function HudMinimap.isApplied()
    return state.applied ~= nil
end

local function paused()
    local ok, active = pcall(IsPauseMenuActive)
    return ok and active == true
end

-- A stuck expanded bigmap is the "huge radar" bug. Only while we manage the
-- layout, are not refreshing ourselves and the pause menu is closed; it must be
-- seen on twice in a row so a short toggle by another script is left alone.
local function guard(cfg)
    if cfg.guardBigmap == false or not state.applied or running or refreshing then
        bigmapSeen = 0
        return
    end
    -- Bigmap first: it is almost always off, so the pause-menu native is only
    -- read on the rare pass that could actually act.
    local ok, active = pcall(IsBigmapActive)
    if ok and active == true and paused() then
        bigmapSeen = 0
        return
    end
    if ok and active == true then
        bigmapSeen = bigmapSeen + 1
        if bigmapSeen >= 2 then
            bigmapSeen = 0
            SetBigmapActive(false, false)
        end
    else
        bigmapSeen = 0
    end
end

-- Re-applies the HUD layout: used by resources that moved the minimap
-- temporarily (the phone Maps app) to put it back. Returns false when the
-- layout is disabled or 'stock' so the caller can restore the stock positions
-- itself.
exports('applyMinimapLayout', function()
    return HudMinimap.apply(true)
end)

AddEventHandler('playerSpawned', function()
    -- A respawn can rebuild the radar; re-assert the mask and rects.
    HudMinimap.apply(true)
end)

-- A texture dictionary streamed after this resource started (or a failed apply)
-- is retried when any resource starts, instead of staying failed.
AddEventHandler('onClientResourceStart', function()
    if failed then
        failed = false
        lastKey = nil
    end
end)

-- Restart-safe cleanup: put the stock masks, clip type and rects back and make
-- sure the bigmap is off, so a txAdmin restart reverts and then re-applies. No
-- bigmap toggle here (a Wait would be cut off by the stop); the new instance's
-- first apply does the refresh.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopped = true
    local touched = state.applied ~= nil or refreshing
    undoAll()
    if requestedDict then pcall(SetStreamedTextureDictAsNoLongerNeeded, requestedDict) end
    if touched then pcall(SetBigmapActive, false, false) end
    refreshing = false
end)

-- Resolution, aspect ratio and the GTA safezone slider have no change event,
-- so poll the cheap natives. Re-applying only happens when the answer changes.
-- Not part of the HUD scheduler because that stops while the HUD is hidden
-- (character select), when the layout should still be right.
local function poll()
    local cfg = settings()
    if cfg and failed and failures <= number(cfg.maxRetries, 3, 0, 100) and now() >= retryAt then
        failed, lastKey = false, nil
    end
    HudMinimap.apply()
    cfg = settings()
    if cfg then guard(cfg) end
end

CreateThread(function()
    while not stopped do
        pcall(poll)
        Wait(number((layoutConfig() or {}).pollMs, 1000, 250, 60000))
    end
end)
