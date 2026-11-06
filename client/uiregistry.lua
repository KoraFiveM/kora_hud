-- UI element registry for the unified /ui layout editor.
--
-- kora_hud hosts the editor (its NUI draws the panel and an outline proxy for
-- every element), but most elements live in OTHER resources' NUI frames
-- (kora_chat's composer, kora_inventory's window). A host cannot move DOM in
-- another frame, so each owner registers a small description of its element
-- here, and kora_hud tells the owner -- through the client-local event
-- `kora_hud:ui:apply` -- where to put it. Owners only turn
-- { x, y, scale, hidden, settings } into CSS; no layout maths is duplicated.
--
-- Everything here is client-side and local. Definitions arrive through an
-- export, i.e. from another resource's Lua, and layouts arrive from this
-- resource's browser page, so both are validated as untrusted input: every
-- string is length-capped, every number range-checked, every collection
-- size-capped, and setting values are checked against the owner's schema.
HudUi = {}

local MAX_PER_OWNER = 12
local MAX_TOTAL = 32
local MAX_SETTINGS = 8
local MAX_OPTIONS = 12
local SCALE_FLOOR, SCALE_CEIL = 0.5, 2.0

-- Ids are persisted as keys of the layout KVP blob, next to these top-level
-- fields, so they can never be claimed by an element.
local RESERVED = { v = true, minimapVehicleOnly = true }
-- kora_hud's own sections. Registering one of these from outside is refused:
-- they are rendered by this page, not proxied.
HudUi.BUILTIN = { gauges = true, vehicle = true, identity = true, status = true }

local ORIGIN_X = { left = true, center = true, right = true }
local ORIGIN_Y = { top = true, center = true, bottom = true }

local registry = {}   -- id -> clean definition (with .owner)
local order = {}      -- ids in registration order, for a stable dropdown
local changed         -- set by hud.lua: called whenever the list changes

local function str(value, max)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c]', '')
    if value == '' then return nil end
    if #value > max then value = value:sub(1, max) end
    return value
end

local function num(value, min, max)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if min and value < min then value = min end
    if max and value > max then value = max end
    return value
end

---@param id any
---@return boolean
function HudUi.validId(id)
    return type(id) == 'string' and #id <= 32 and id:match('^%a[%w_]*$') ~= nil and not RESERVED[id]
end

local function cleanRect(rect)
    if type(rect) ~= 'table' then return nil end
    local x, y = num(rect.x, 0, 1), num(rect.y, 0, 1)
    local w, h = num(rect.w, 0, 1), num(rect.h, 0, 1)
    if not (x and y and w and h) or w <= 0 or h <= 0 then return nil end
    return { x = x, y = y, w = w, h = h }
end

local function cleanOffset(offset)
    if type(offset) ~= 'table' then return nil end
    local x, y = num(offset.x, -1, 1), num(offset.y, -1, 1)
    if not (x and y) then return nil end
    return { x = x, y = y }
end

local function cleanOrigin(value)
    if type(value) ~= 'string' then return 'left top' end
    local ox, oy = value:match('^(%a+) (%a+)$')
    if ORIGIN_X[ox] and ORIGIN_Y[oy] then return ox .. ' ' .. oy end
    return 'left top'
end

local function stepped(value, min, step)
    if not step or step <= 0 then return value end
    return min + math.floor((value - min) / step + 0.5) * step
end

local function cleanSetting(raw)
    if type(raw) ~= 'table' then return nil end
    local key = raw.key
    if type(key) ~= 'string' or #key > 24 or not key:match('^%a[%w_]*$') then return nil end
    local label = str(raw.label, 48) or key
    local description = str(raw.description, 160)
    if raw.type == 'toggle' then
        return { key = key, label = label, description = description, type = 'toggle', default = raw.default == true }
    elseif raw.type == 'range' then
        local min, max = num(raw.min, -1e6, 1e6), num(raw.max, -1e6, 1e6)
        if not min or not max or max <= min then return nil end
        local step = num(raw.step, 0, max - min)
        local default = num(raw.default, min, max) or min
        return {
            key = key, label = label, description = description, type = 'range',
            min = min, max = max, step = step and step > 0 and step or nil,
            default = stepped(default, min, step),
            unit = str(raw.unit, 8), zeroLabel = str(raw.zeroLabel, 16),
        }
    elseif raw.type == 'select' then
        if type(raw.options) ~= 'table' then return nil end
        local options, seen = {}, {}
        for _, option in ipairs(raw.options) do
            local value = type(option) == 'table' and option.value or option
            value = str(value, 32)
            if value and not seen[value] and #options < MAX_OPTIONS then
                seen[value] = true
                options[#options + 1] = { value = value, label = str(type(option) == 'table' and option.label, 32) or value }
            end
        end
        if #options == 0 then return nil end
        local default = seen[raw.default] and raw.default or options[1].value
        return { key = key, label = label, description = description, type = 'select', options = options, default = default }
    end
    return nil
end

---Normalises a definition from an owner. Returns nil and a reason when it
---cannot be used at all; individual bad settings are dropped silently.
---@param def any
---@return table|nil, string|nil
function HudUi.sanitiseDef(def)
    if type(def) ~= 'table' then return nil, 'definition must be a table' end
    if not HudUi.validId(def.id) then return nil, 'invalid id' end
    local rect = cleanRect(def.rect)
    if not rect then return nil, 'rect must be { x, y, w, h } in viewport fractions' end
    local scaleMin = num(def.scaleMin, SCALE_FLOOR, SCALE_CEIL) or 0.75
    local scaleMax = num(def.scaleMax, SCALE_FLOOR, SCALE_CEIL) or 1.5
    if scaleMax < scaleMin then scaleMin, scaleMax = scaleMax, scaleMin end
    if scaleMin > 1 then scaleMin = 1 end
    if scaleMax < 1 then scaleMax = 1 end

    local settings, keys = {}, {}
    if type(def.settings) == 'table' then
        for _, raw in ipairs(def.settings) do
            if #settings >= MAX_SETTINGS then break end
            local setting = cleanSetting(raw)
            if setting and not keys[setting.key] then
                keys[setting.key] = true
                settings[#settings + 1] = setting
            end
        end
    end

    return {
        id = def.id,
        label = str(def.label, 32) or def.id,
        group = str(def.group, 24) or 'Other',
        rect = rect,
        defaultOffset = cleanOffset(def.defaultOffset) or { x = 0, y = 0 },
        origin = cleanOrigin(def.origin),
        movable = def.movable ~= false,
        scalable = def.scalable ~= false,
        hideable = def.hideable == true,
        scaleMin = scaleMin,
        scaleMax = scaleMax,
        settings = settings,
    }
end

local function notify()
    if changed then pcall(changed) end
end

---@param fn function called (without arguments) after any registry change
function HudUi.onChange(fn)
    changed = fn
end

local function ownerCount(owner)
    local count = 0
    for _, def in pairs(registry) do
        if def.owner == owner then count = count + 1 end
    end
    return count
end

local function removeId(id)
    registry[id] = nil
    for index = #order, 1, -1 do
        if order[index] == id then table.remove(order, index) end
    end
end

---Registers (or replaces, for the same owner) an element.
---@param owner string resource name
---@param def table
---@param internal boolean|nil true for kora_hud's own non-section elements (minimap)
---@return table|nil clean, string|nil err
function HudUi.register(owner, def, internal)
    if type(owner) ~= 'string' or owner == '' then return nil, 'unknown owner' end
    local clean, err = HudUi.sanitiseDef(def)
    if not clean then return nil, err end
    if HudUi.BUILTIN[clean.id] then return nil, 'id is a built-in HUD section' end
    if clean.id == 'minimap' and not internal then return nil, 'id taken' end
    local existing = registry[clean.id]
    if existing and existing.owner ~= owner then return nil, 'id taken' end
    if not existing then
        if ownerCount(owner) >= MAX_PER_OWNER then return nil, 'too many elements for this resource' end
        if #order >= MAX_TOTAL then return nil, 'too many elements' end
        order[#order + 1] = clean.id
    end
    clean.owner = owner
    clean.internal = internal == true
    registry[clean.id] = clean
    notify()
    return clean
end

---Owner-only partial update of the measured geometry.
---@return boolean ok, string|nil err
function HudUi.update(owner, id, patch)
    local def = registry[id]
    if not def or def.owner ~= owner then return false, 'not registered by this resource' end
    if type(patch) ~= 'table' then return false, 'patch must be a table' end
    local rect = patch.rect ~= nil and cleanRect(patch.rect) or nil
    local offset = patch.defaultOffset ~= nil and cleanOffset(patch.defaultOffset) or nil
    if not rect and not offset then return false, 'nothing to update' end
    if rect then def.rect = rect end
    if offset then def.defaultOffset = offset end
    notify()
    return true
end

---@return boolean removed
function HudUi.unregister(owner, id)
    local def = registry[id]
    if not def or def.owner ~= owner then return false end
    removeId(id)
    notify()
    return true
end

---Drops every element of a stopped resource.
function HudUi.dropOwner(owner)
    local removed = false
    for index = #order, 1, -1 do
        local id = order[index]
        if registry[id] and registry[id].owner == owner then
            registry[id] = nil
            table.remove(order, index)
            removed = true
        end
    end
    if removed then notify() end
    return removed
end

---@return table|nil
function HudUi.get(id)
    return registry[id]
end

---Snapshot for the NUI, in registration order. Copies, so the page can never
---hold a reference into the registry.
---@return table[]
function HudUi.list()
    local out = {}
    for _, id in ipairs(order) do
        local def = registry[id]
        if def then
            out[#out + 1] = {
                id = def.id, label = def.label, group = def.group, owner = def.owner,
                rect = { x = def.rect.x, y = def.rect.y, w = def.rect.w, h = def.rect.h },
                defaultOffset = { x = def.defaultOffset.x, y = def.defaultOffset.y },
                origin = def.origin, movable = def.movable, scalable = def.scalable,
                hideable = def.hideable, scaleMin = def.scaleMin, scaleMax = def.scaleMax,
                settings = def.settings,
            }
        end
    end
    return out
end

---@return fun(): string, table iterator over (id, def)
function HudUi.each()
    local index = 0
    return function()
        index = index + 1
        local id = order[index]
        while id and not registry[id] do
            index = index + 1
            id = order[index]
        end
        if id then return id, registry[id] end
    end
end

---Clamps a scale into the element's range; nil for non-numbers.
function HudUi.clampScale(def, value)
    local number = num(value)
    if not number then return nil end
    local min = def and def.scaleMin or SCALE_FLOOR
    local max = def and def.scaleMax or SCALE_CEIL
    if number < min then return min end
    if number > max then return max end
    return number
end

---Validates one setting value against its schema; nil when invalid.
function HudUi.settingValue(setting, value)
    if setting.type == 'toggle' then
        if type(value) == 'boolean' then return value end
        return nil
    elseif setting.type == 'range' then
        local number = num(value, setting.min, setting.max)
        if not number then return nil end
        return stepped(number, setting.min, setting.step)
    elseif setting.type == 'select' then
        if type(value) ~= 'string' then return nil end
        for _, option in ipairs(setting.options) do
            if option.value == value then return value end
        end
    end
    return nil
end

---Settings validated against `def`. Only valid, known keys survive.
---@return table|nil nil when nothing valid was supplied
function HudUi.cleanSettings(def, raw)
    if not def or type(raw) ~= 'table' then return nil end
    local out, any = {}, false
    for _, setting in ipairs(def.settings) do
        local value = HudUi.settingValue(setting, raw[setting.key])
        if value ~= nil then
            out[setting.key] = value
            any = true
        end
    end
    return any and out or nil
end

---Shape check for settings of an element whose owner is NOT running: the
---schema is unknown, so only plain scalar values of bounded size are kept.
function HudUi.preserveSettings(raw)
    if type(raw) ~= 'table' then return nil end
    local out, count = {}, 0
    for key, value in pairs(raw) do
        if count >= MAX_SETTINGS then break end
        if type(key) == 'string' and #key <= 24 and key:match('^%a[%w_]*$') then
            local t = type(value)
            if t == 'boolean' or (t == 'number' and value == value and math.abs(value) <= 1e6)
                or (t == 'string' and #value <= 32) then
                out[key] = value
                count = count + 1
            end
        end
    end
    return count > 0 and out or nil
end

---The layout an owner receives: everything filled in, nothing to re-derive.
---@param def table
---@param entry table|nil saved/previewed entry { x, y, scale, hidden, settings }
function HudUi.layoutFor(def, entry)
    entry = type(entry) == 'table' and entry or {}
    local x, y = num(entry.x, -1, 1), num(entry.y, -1, 1)
    local settings = {}
    local supplied = type(entry.settings) == 'table' and entry.settings or {}
    for _, setting in ipairs(def.settings) do
        local value = HudUi.settingValue(setting, supplied[setting.key])
        if value == nil then value = setting.default end
        settings[setting.key] = value
    end
    return {
        x = def.movable and x or 0,
        y = def.movable and y or 0,
        -- An element that was never placed: the owner keeps its own default
        -- position instead of a (0, 0) offset that may not be where it sits.
        placed = def.movable and x ~= nil and y ~= nil and (x ~= 0 or y ~= 0) or false,
        scale = def.scalable and HudUi.clampScale(def, entry.scale) or 1,
        hidden = def.hideable and entry.hidden == true or false,
        settings = settings,
    }
end
