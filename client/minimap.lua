-- Minimap layout owner. kora_hud is the single place that positions the
-- minimap, minimap_mask and minimap_blur components, so the map texture, its
-- mask and its border/blur frame always move and scale together. Before this,
-- nothing positioned them for the player's resolution at all, and the phone's
-- Maps app restored a fixed 16:9 table when it closed.
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
-- Ultrawide correction: above 16:9 the HUD is still laid out in a centred 16:9
-- area, so a left-anchored component has to be pulled back by an amount that
-- grows with the extra width. 3.6 and the 0.008 trim are the widely used
-- values for this; both are applied only above 16:9, so 16:9, 16:10 and 4:3
-- need no correction.
local ULTRAWIDE_DIVISOR = 3.6
local ULTRAWIDE_TRIM = 0.008

-- Left/bottom anchored rects (x, y, w, h) at 16:9. The mask and blur are
-- expressed relative to the same anchor as the map, so scaling one scales all.
local BASE = {
    minimap      = { x = 0.0,   y = -0.047, w = 0.1638, h = 0.183 },
    minimap_mask = { x = 0.0,   y = 0.0,    w = 0.128,  h = 0.20 },
    minimap_blur = { x = -0.01, y = 0.025,  w = 0.262,  h = 0.300 },
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

    local wide = 0.0
    if aspect > WIDESCREEN then
        wide = ((WIDESCREEN - aspect) / ULTRAWIDE_DIVISOR) - ULTRAWIDE_TRIM
    end
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
            -- Size and the in-frame offsets scale; the ultrawide correction,
            -- safezone margin and user offsets are screen-space and do not.
            x = base.x * scale + wide - margin + shiftX + number(own.x, 0.0, -1.0, 1.0),
            y = base.y * scale + margin + shiftY + number(own.y, 0.0, -1.0, 1.0),
            w = base.w * scale,
            h = base.h * scale,
        }
    end
    return out
end

local function settings()
    local hud = type(Config) == 'table' and Config.hud
    return type(hud) == 'table' and type(hud.minimapLayout) == 'table' and hud.minimapLayout or nil
end

local lastKey

---Applies the layout to the game. Returns false when the layout is disabled.
---@param force boolean|nil re-apply even if aspect/safezone/config are unchanged
---@return boolean applied
function HudMinimap.apply(force)
    local cfg = settings()
    if not cfg or cfg.enabled == false then
        lastKey = nil
        return false
    end

    local aspect, safezone = GetAspectRatio(false), GetSafeZoneSize()
    local rects = HudMinimap.layout(aspect, safezone, cfg)
    local key = string.format('%.4f|%.4f|%s', aspect, safezone, json.encode(cfg))
    if not force and key == lastKey then return true end
    lastKey = key

    for _, name in ipairs(HudMinimap.COMPONENTS) do
        local r = rects[name]
        SetMinimapComponentPosition(name, 'L', 'B', r.x, r.y, r.w, r.h)
    end
    -- The engine only re-reads component positions on a bigmap toggle.
    SetBigmapActive(true, false)
    SetBigmapActive(false, false)
    return true
end

-- Re-applies the HUD's layout: used by resources that moved the minimap
-- temporarily (the phone Maps app) to put it back.
exports('applyMinimapLayout', function()
    return HudMinimap.apply(true)
end)

AddEventHandler('playerSpawned', function()
    HudMinimap.apply(true)
end)

-- Resolution, aspect ratio and the GTA safezone slider have no change event,
-- so poll the two cheap natives once a second. Re-applying only happens when
-- the answer changes. Not part of the HUD scheduler because that stops while
-- the HUD is hidden (character select), when the layout should still be right.
CreateThread(function()
    while true do
        pcall(HudMinimap.apply)
        Wait(1000)
    end
end)
