-- Optional FFT development hooks (client). Listed last in fxmanifest.lua and
-- inert unless `setr fft_kora_hooks true`. No other file references FFT.
--
-- kora_hud talks to its own NUI page through the raw SendNUIMessage native
-- (client/hud.lua's file-local `send`, client/seatbelt_sound.lua), and every
-- piece of state behind it is file-local. This hook therefore only OBSERVES:
-- it wraps the global SendNUIMessage (both callers look the global up at call
-- time, neither captures it as a local) and keeps a bounded log of what the
-- page was sent. The wrap forwards every message unchanged. The page's own NUI
-- callbacks are not run from here: the suite calls them with a real fetch
-- (FFT's K.nui), because a script-fired __cfx_nui event is never answered.
-- This proves the Lua -> NUI payloads, not what the page renders.
--
-- UNVERIFIED LIVE: the manifest sets use_experimental_fxv2_oal; `state().wrapped`
-- reports whether a function was found to wrap, and a suite must still see a
-- logged message before trusting the observer.
if GetConvar('fft_kora_hooks', 'false') ~= 'true' then return end

local RUNNER = 'fft'
local VERSION = 2
local MAX_LOG = 300

local function session()
    if GetResourceState(RUNNER) ~= 'started' then return nil end
    local id = LocalPlayer.state.fftSession
    return type(id) == 'string' and id or nil
end

local sequence = 0
local log = {}

-- Bounded, JSON-safe copy: functions and deep or huge values never leave the VM.
local function summary(value, depth)
    depth = depth or 0
    local kind = type(value)
    if kind == 'string' then return #value > 300 and (value:sub(1, 300) .. '...') or value end
    if kind == 'number' or kind == 'boolean' or value == nil then return value end
    if kind ~= 'table' then return '<' .. kind .. '>' end
    if depth >= 6 then return '<table>' end
    local out, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 60 then out['...'] = 'truncated' break end
        out[type(key) == 'number' and key or tostring(key)] = summary(item, depth + 1)
    end
    return out
end

local function record(message)
    if type(message) ~= 'table' or type(message.action) ~= 'string' then return end
    sequence = sequence + 1
    log[#log + 1] = { seq = sequence, t = GetGameTimer(), action = message.action, data = summary(message.data) }
    if #log > MAX_LOG then table.remove(log, 1) end
end

local original = SendNUIMessage
local wrapped = type(original) == 'function'
if wrapped then
    SendNUIMessage = function(message, ...)
        if session() then
            local ok, err = pcall(record, message)
            if not ok then print('[kora_hud:fft] observer failed: ' .. tostring(err)) end
        end
        return original(message, ...)
    end
end

local actions = {}

function actions.state()
    return {
        wrapped = wrapped,
        sequence = sequence,
        focused = IsNuiFocused() == true,
        compat = type(HudCompat) == 'table' and summary(HudCompat.state) or nil,
    }
end

---Messages sent to the page after sequence number `since`, optionally one action only.
function actions.log(since, action)
    if action ~= nil and (type(action) ~= 'string' or #action > 64) then return false, 'Invalid action filter', 'invalid' end
    since = tonumber(since) or 0
    local out = {}
    for _, entry in ipairs(log) do
        if entry.seq > since and (action == nil or entry.action == action) then out[#out + 1] = entry end
    end
    return out
end

exports('fftVersion', function() return VERSION end)
exports('fftAction', function(action, ...)
    if GetInvokingResource() ~= RUNNER or not session() then
        return false, 'FFT hooks are disabled or session is not authorised'
    end
    local handler = actions[action]
    if not handler then return false, 'Unsupported FFT action: ' .. tostring(action) end
    return handler(...)
end)

AddStateBagChangeHandler('fftSession', nil, function(bag, _, value)
    if bag ~= ('player:%s'):format(GetPlayerServerId(PlayerId())) or type(value) == 'string' then return end
    log = {}
end)
