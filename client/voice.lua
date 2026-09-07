-- Mic/talking indicator. Primary source: FiveM's own native voice-talking
-- state, which reflects whichever voice resource sits on top of it --
-- pma-voice, saltychat, and mumble-voip all use the same underlying Mumble
-- backend, so this works without any pma-voice-specific integration at all.
--
-- Proximity presentation comes from the configured voice resource's
-- getTalkingMode export. It is optional and pcall-guarded: swapping voice
-- resources can remove the range display, but can never take down the mic.
--
-- This module owns NO thread. Mic state is the one HUD input with no change
-- notification of its own, so it genuinely has to be sampled -- but the HUD
-- already runs a single scheduler thread (client/hud.lua) for exactly this
-- kind of periodic work, and FiveM's scheduler walks every live coroutine each
-- frame to decide what to resume. A second thread here would be a second entry
-- in that walk for one boolean. Voice.sample() is the unit of work; the HUD
-- decides when to call it and stops calling it the moment the HUD is hidden or
-- the mic element is off.
Voice = Voice or {}

local talking = false
local listeners = {}
local mode = nil
local modeListeners = {}
local active = false

local function setTalking(value)
    if value == talking then return end
    talking = value

    for _, handler in ipairs(listeners) do
        local ok, err = pcall(handler, value)
        if not ok then
            print(("[qb-hud:voice] onChange handler errored: %s"):format(tostring(err)))
        end
    end
end

local function normaliseMode(value)
    if type(value) ~= 'table' then return nil end

    local index = math.floor(tonumber(value.index) or 0)
    local range = tonumber(value.range)
    if index < 1 or range == nil or range < 0 then return nil end

    return {
        index = index,
        name = type(value.name) == 'string' and value.name or '',
        label = type(value.label) == 'string' and value.label or ('Range %d'):format(index),
        range = range + 0.0,
    }
end

local function sameMode(a, b)
    if a == nil or b == nil then return a == b end
    return a.index == b.index and a.name == b.name and a.label == b.label and a.range == b.range
end

local function setMode(value)
    local nextMode = normaliseMode(value)
    if sameMode(mode, nextMode) then return end
    mode = nextMode

    for _, handler in ipairs(modeListeners) do
        local ok, err = pcall(handler, mode)
        if not ok then
            print(("[qb-hud:voice] onModeChange handler errored: %s"):format(tostring(err)))
        end
    end
end

local function sampleMode()
    local resource = Config.voice.resource
    if type(resource) ~= 'string' or resource == '' then
        setMode(nil)
        return
    end

    local ok, result = pcall(function()
        return exports[resource]:getTalkingMode()
    end)
    setMode(ok and result or nil)
end

-- Resolved once, not per sample. The local player index is a session constant,
-- and QB.cache.playerId() is a cross-resource export call (see qblib/init.lua's
-- proxy metatable) -- a full boundary crossing to be handed back the same
-- integer the native returns directly. The cache exists to avoid natives that
-- are expensive or need a shared tick; PlayerId() is neither.
local playerId

---Reads the native once and notifies onChange listeners if the state flipped.
---Called by client/hud.lua's scheduler on Config.voice.interval, and only
---while Voice.isActive() -- a no-op otherwise, so a stray call during
---character select can't light up the mic indicator.
function Voice.sample()
    if not active then return end
    if playerId == nil then playerId = PlayerId() end

    local ok, result = pcall(NetworkIsPlayerTalking, playerId)
    setTalking(ok and result or false)
    sampleMode()
end

---Enables/disables mic sampling. HUD visibility owns this lifecycle so nothing
---is sampled during character select, logout, or when the mic element is
---disabled -- the HUD's scheduler skips the sample task entirely while this is
---false, rather than calling into a no-op.
---@param value boolean
function Voice.setActive(value)
    active = value == true and Config.voice.enabled == true

    if not active then setTalking(false) end
end

---Whether mic sampling is currently enabled. Drives the HUD scheduler's voice
---task, so the sample native is never reached while the HUD is hidden.
---@return boolean
function Voice.isActive()
    return active
end

---@return boolean
function Voice.isTalking()
    return talking
end

---@return { index: integer, name: string, label: string, range: number }|nil
function Voice.currentMode()
    return mode
end

---Registers `handler(talking)` to run whenever the talking state flips.
---@param handler fun(talking: boolean)
function Voice.onChange(handler)
    listeners[#listeners + 1] = handler
end

---Registers `handler(mode)` to run whenever the proximity mode changes.
---@param handler fun(mode: table|nil)
function Voice.onModeChange(handler)
    modeListeners[#modeListeners + 1] = handler
end
