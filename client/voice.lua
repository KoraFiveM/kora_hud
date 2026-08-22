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

CreateThread(function()
    while true do
        if Config.voice.enabled then
            local ok, result = pcall(NetworkIsPlayerTalking, QB.cache.playerId())
            setTalking(ok and result or false)
        else
            setTalking(false)
        end

        Wait(200)
    end
end)

---@return boolean
function Voice.isTalking()
    return talking
end

---Registers `handler(talking)` to run whenever the talking state flips.
---@param handler fun(talking: boolean)
function Voice.onChange(handler)
    table.insert(listeners, handler)
end
