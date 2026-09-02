-- Mic/talking indicator. Primary source: FiveM's own native voice-talking
-- state, which reflects whichever voice resource sits on top of it --
-- pma-voice, saltychat, and mumble-voip all use the same underlying Mumble
-- backend, so this works without any pma-voice-specific integration at all.
--
-- ASSUMPTION TO VERIFY AT IMPLEMENTATION TIME: pma-voice has historically
-- also exposed richer state (proximity range, etc.) via its own exports or
-- state bags, but the exact name varies by version and isn't installed in
-- this repo to check against. If you want that richer state, look up the
-- installed pma-voice version's actual export/state-bag name and add the
-- lookup here, wrapped in pcall like NetworkIsPlayerTalking below -- so a
-- missing/renamed pma-voice API degrades to "use the native", not an error.
Voice = Voice or {}

local talking = false
local listeners = {}
local active = false
local sampling = false

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

-- Resolved once, not per sample. The local player index is a session constant,
-- and QB.cache.playerId() is a cross-resource export call (see qblib/init.lua's
-- proxy metatable) -- a full boundary crossing to be handed back the same
-- integer the native returns directly. The cache exists to avoid natives that
-- are expensive or need a shared tick; PlayerId() is neither.
local playerId

local function sample()
    if playerId == nil then playerId = PlayerId() end

    local ok, result = pcall(NetworkIsPlayerTalking, playerId)
    setTalking(ok and result or false)
end

---Starts/stops the native voice sampler. HUD visibility owns this lifecycle so
---the resource has no polling thread during character select, logout, or when
---the mic element is disabled.
---@param value boolean
function Voice.setActive(value)
    active = value == true and Config.voice.enabled == true

    if not active then
        setTalking(false)
        return
    end
    if sampling then return end

    sampling = true
    local interval = Config.voice.interval or 200

    CreateThread(function()
        while active do
            sample()
            Wait(interval)
        end
        sampling = false
    end)
end

---@return boolean
function Voice.isTalking()
    return talking
end

---Registers `handler(talking)` to run whenever the talking state flips.
---@param handler fun(talking: boolean)
function Voice.onChange(handler)
    table.insert(listeners, handler)
end
