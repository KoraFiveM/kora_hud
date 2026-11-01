-- Optional minimap layout owner. When Config.hud.minimapLayout.enabled is true
-- kora_hud positions the minimap, minimap_mask and minimap_blur components so
-- the map texture, its mask and its border/blur frame move and scale together.
-- When it is false (the default) this file never touches a component position
-- or the bigmap, and the stock minimap is left alone.
--
-- Everything that depends on the screen goes through HudMinimap.layout(), a
-- pure function of (aspect ratio, safezone, config) so it is unit-tested
-- without the game. apply() is the only part that calls natives.
--
-- Config.hud.minimapLayout is read at use time (kora_lib live config replaces
-- Config.hud wholesale), so a change takes effect on the next check without a
-- restart.
HudMinimap = {}

local WIDESCREEN = 16 / 9

-- Vanilla 16:9 rects, left/bottom anchored (x, y, w, h). These are the widely
-- used community reference values for the stock GTA V minimap; at 16:9, scale
-- 1.0 and no offsets the layout is exactly these numbers.
local BASE = {
    minimap      = { x = -0.0045, y = 0.002, w = 0.150, h = 0.188 },
    minimap_mask = { x = 0.020,   y = 0.032, w = 0.111, h = 0.159 },
    minimap_blur = { x = -0.03,   y = 0.022, w = 0.266, h = 0.237 },
}

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

---Computes the three component rects.
---@param aspect number GetAspectRatio(false)
---@param safezone number GetSafeZoneSize()
---@param cfg table|nil Config.hud.minimapLayout
---@return table<string, {x:number, y:number, w:number, h:number}>
function HudMinimap.layout(aspect, safezone, cfg)
    cfg = type(cfg) == 'table' and cfg or {}
    aspect = number(aspect, WIDESCREEN, 1.0, 10.0)
    safezone = number(safezone, 1.0, 0.5, 1.0)

    local scale = number(cfg.scale, 1.0, 0.5, 2.0)
    local shiftX = number(cfg.x, 0.0, -1.0, 1.0)
    local shiftY = number(cfg.y, 0.0, -1.0, 1.0)
    local compensation = number(cfg.safezoneCompensation, 0.0, 0.0, 2.0)

    -- Screen fractions are relative to the screen width, so on a wider screen
    -- the same fraction is more pixels and the map would stretch. Scaling the
    -- widths (and the left inset) by (16/9)/aspect keeps the pixel size and
    -- shape the same as at 16:9: narrower fractions on 21:9 and 32:9, wider on
    -- 4:3. Exactly 1.0 at 16:9, so 16:9 is vanilla.
    local widthFactor = WIDESCREEN / aspect
    -- The engine already anchors L/B components inside the safezone; the
    -- optional compensation cancels part of that margin for builds where the
    -- mask drifts relative to the blur at small safezones.
    local margin = (1.0 - safezone) / 2.0 * compensation

    local fine = type(cfg.offsets) == 'table' and cfg.offsets or {}
    local out = {}
    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local base, own = BASE[name], fine[FINE_KEY[name]]
        own = type(own) == 'table' and own or {}
        out[name] = {
            -- Size and the in-frame offsets scale; the safezone margin and
            -- user offsets are screen-space and do not.
            x = base.x * scale * widthFactor - margin + shiftX + number(own.x, 0.0, -1.0, 1.0),
            y = base.y * scale + margin + shiftY + number(own.y, 0.0, -1.0, 1.0),
            w = base.w * scale * widthFactor,
            h = base.h * scale,
        }
    end
    return out
end

local function settings()
    local hud = type(Config) == 'table' and Config.hud
    local cfg = type(hud) == 'table' and hud.minimapLayout
    if type(cfg) ~= 'table' or cfg.enabled ~= true then return nil end
    return cfg
end

local lastKey
local running, pending = false, false

local function snapshot()
    local cfg = settings()
    if not cfg then return nil end
    local aspect, safezone = GetAspectRatio(false), GetSafeZoneSize()
    return cfg, aspect, safezone, string.format('%.4f|%.4f|%s', aspect, safezone, json.encode(cfg))
end

-- Waits (bounded) for the minimap scaleform so the bigmap refresh below is not
-- lost when this runs at resource start or spawn, before the radar exists.
local function waitForMinimap()
    local ok, handle = pcall(RequestScaleformMovie, 'minimap')
    if not ok or not handle then return end
    for _ = 1, 100 do
        if HasScaleformMovieLoaded(handle) then return end
        Wait(0)
    end
end

local function place()
    local cfg, aspect, safezone, key = snapshot()
    if not cfg then
        lastKey = nil
        return
    end
    lastKey = key
    local rects = HudMinimap.layout(aspect, safezone, cfg)
    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local r = rects[name]
        SetMinimapComponentPosition(name, 'L', 'B', r.x, r.y, r.w, r.h)
    end
    -- The engine only re-reads component positions on a bigmap toggle, and it
    -- needs a frame between the two calls: toggling both in the same frame can
    -- leave the bigmap radar on.
    SetBigmapActive(true, false)
    Wait(0)
    SetBigmapActive(false, false)
end

local function run()
    repeat
        pending = false
        local ok = pcall(function()
            waitForMinimap()
            place()
        end)
        -- Whatever happened, never leave the bigmap on.
        if not ok then pcall(SetBigmapActive, false, false) end
    until not pending
    running = false
end

---Applies the layout to the game. Returns false when the layout is disabled
---(nothing is touched); otherwise true, with the natives applied from a thread.
---@param force boolean|nil re-apply even if aspect/safezone/config are unchanged
---@return boolean applied
function HudMinimap.apply(force)
    local _, _, _, key = snapshot()
    if not key then
        lastKey = nil
        return false
    end
    if not force and key == lastKey then return true end
    -- One apply at a time: a request that arrives mid-apply runs once more
    -- with the latest values when the current one finishes.
    if running then
        pending = true
        return true
    end
    running = true
    CreateThread(run)
    return true
end

-- Optional square map mask. The stock radar clips the rotating map tiles with a
-- round/rounded mask, so inside a square border the corner tiles show outside
-- it. 'square' swaps the radar masks for the ones in a streamed texture dict
-- the server supplies and sets the square clip type. 'stock' (the default)
-- touches nothing and, if square was applied earlier, undoes it. kora_hud ships
-- no mask texture: the dict (Config.hud.minimapLayout.squareTextureDict) must
-- be streamed by some resource, or the shape stays stock and one line is logged.
local MASK_TXD = 'platform:/textures/graphics'
local MASK_NAMES = { 'radarmasksm', 'radarmask1g' }
local shapeKey, shapeFailedKey, shapeDict

local function shapeSettings()
    local hud = type(Config) == 'table' and Config.hud
    local cfg = type(hud) == 'table' and hud.minimapLayout
    cfg = type(cfg) == 'table' and cfg or {}
    local dict = type(cfg.squareTextureDict) == 'string' and cfg.squareTextureDict ~= '' and cfg.squareTextureDict or 'squaremap'
    return cfg.shape == 'square' and 'square' or 'stock', dict
end

local function loadMaskDict(dict)
    RequestStreamedTextureDict(dict, false)
    for _ = 1, 100 do
        if HasStreamedTextureDictLoaded(dict) then return true end
        Wait(0)
    end
    return false
end

local function removeMasks()
    for _, name in ipairs(MASK_NAMES) do RemoveReplaceTexture(MASK_TXD, name) end
    SetMinimapClipType(1)
    if shapeDict then SetStreamedTextureDictAsNoLongerNeeded(shapeDict) end
    shapeDict = nil
end

---Applies Config.hud.minimapLayout.shape. Safe to call often: it only acts when
---the shape or dict changed, and may Wait (call it from a thread).
function HudMinimap.applyShape()
    local shape, dict = shapeSettings()
    local key = shape .. '|' .. dict
    if key == shapeKey or key == shapeFailedKey then return end
    if shape == 'stock' then
        if shapeDict then removeMasks() end
        shapeKey = key
        return
    end
    if not loadMaskDict(dict) then
        shapeFailedKey = key
        print(('[kora_hud] minimap shape "square": texture dict "%s" is not streamed, keeping the stock mask'):format(dict))
        return
    end
    if shapeDict and shapeDict ~= dict then removeMasks() end
    for _, name in ipairs(MASK_NAMES) do AddReplaceTexture(MASK_TXD, name, dict, name) end
    SetMinimapClipType(0)
    shapeDict, shapeKey, shapeFailedKey = dict, key, nil
end

-- Re-applies the HUD layout: used by resources that moved the minimap
-- temporarily (the phone Maps app) to put it back. Returns false when the
-- layout is disabled so the caller can restore the stock positions itself.
exports('applyMinimapLayout', function()
    return HudMinimap.apply(true)
end)

AddEventHandler('playerSpawned', function()
    HudMinimap.apply(true)
    -- A respawn can rebuild the radar; re-assert the mask on the next poll.
    shapeKey = nil
end)

-- A texture dict streamed after this resource started is picked up on the next
-- poll instead of staying failed.
AddEventHandler('onClientResourceStart', function()
    shapeFailedKey = nil
end)

-- Resolution, aspect ratio and the GTA safezone slider have no change event,
-- so poll the two cheap natives once a second. Re-applying only happens when
-- the answer changes. Not part of the HUD scheduler because that stops while
-- the HUD is hidden (character select), when the layout should still be right.
CreateThread(function()
    while true do
        pcall(HudMinimap.apply)
        pcall(HudMinimap.applyShape)
        Wait(1000)
    end
end)
