-- Real QBHudBridge adapter, sourcing live player data from kora_core (see
-- shared/bridge.lua for the contract). This is the end-to-end proof that kora_core
-- + kora_sql work against a consumer that already existed in this repo: the HUD
-- shows real job/gang/money/needs, driven by kora_core's DELTA replication rather
-- than polling framework internals.
--
-- Swapped in by setting Config.bridge.adapter = "qbcore" and listing this file
-- (instead of stub.lua) in kora_hud/fxmanifest.lua's client_scripts. client/hud.lua
-- never changes -- it only ever calls HudBridge.getSnapshot()/onChange.
--
-- Reads go through kora_core's client mirror (exports.kora_core:getPlayerData), which
-- is a plain local table lookup with zero per-read network cost. Changes are
-- PUSHED via exports.kora_core:onPlayerDataChange, so the HUD updates the instant a
-- delta lands rather than on a poll interval -- the whole point of the delta
-- protocol.

HudBridge = HudBridge or {}

-- Character-session state is server-owned.  Do not use the legacy load/unload
-- events here: they are compatibility signals, not the HUD's authority.  The
-- state bag persists across kora_hud restarts and is replicated to LocalPlayer.
local LOGIN_STATE = 'qbcore:loggedIn'
local CINEMATIC_MODE_STATE = 'qbmultichar:mode'

-- kora_multichar publishes a MODE STRING while a cinematic session is open and a
-- falsy value once cleanup has finished (`false` on a current kora_multichar, nil
-- on a server that never ran one -- see kora_multichar/server.lua's writeMode for
-- why the clear cannot be a nil deletion). Gate on truthiness so both spellings
-- of "no cinematic mode" release the HUD.
local function inCinematicMode()
    return LocalPlayer.state[CINEMATIC_MODE_STATE] and true or false
end
local CASH_STATE = 'qbcore:money:cash'
local loggedIn = false
local loginHandlers = {}
local loginGeneration = 0
local dataHandlers = {}

-- Rebuilding the snapshot is not free -- it is a getPlayerData export call
-- plus a QB.status.getActive one -- and kora_core's delta stream routinely fires
-- several of the roots this adapter subscribes to for ONE logical update (a
-- resync touches money, job, gang and metadata). Coalesce every notification
-- landing in the same frame into a single rebuild and a single push.
--
-- The one-frame wait is load-bearing beyond the coalescing: CFX fires a state
-- bag change handler BEFORE the new value is committed to the local store, and
-- snapshotFrom reads CASH_STATE back out of it, so pushing synchronously from
-- a bag handler would hand consumers the OLD balance.
local pushScheduled = false

local function schedulePush()
    if pushScheduled then return end
    pushScheduled = true

    CreateThread(function()
        Wait(0)
        pushScheduled = false

        local snapshot = HudBridge.getSnapshot()
        for _, handler in ipairs(dataHandlers) do handler(snapshot) end
    end)
end

-- Status effects are an optional kora_lib enhancement to the HUD, never a
-- prerequisite for the base player HUD.  In particular, this lets kora_hud
-- start cleanly during a rolling update where kora_hud has been updated before a
-- server has restarted kora_lib with the status exports.  A missing export must
-- not prevent the NUI-ready callback below in client/hud.lua from registering.
local function activeStatus()
    local ok, status = pcall(function() return QB.status.getActive() end)
    if ok and type(status) == 'table' then return status end
    return {}
end

local function notifyLoginChange(value)
    if loggedIn == value then return end
    loggedIn = value
    for _, handler in ipairs(loginHandlers) do handler(value) end
end

local RECONCILE_WAIT_FRAMES = 200
local RECONCILE_MAX_ROUNDS = 3

-- pcall'd: kora_core may itself be mid-restart (its export table not yet
-- published, or its own resource not fully started) at the exact moment this
-- thread runs -- e.g. a supervisor restarting kora_core and kora_hud together. An
-- uncaught error from a cross-resource export call would otherwise silently
-- kill this CreateThread body (standard Lua coroutine behaviour), leaving
-- `loggedIn` stuck at whatever it last was. Treat a failed call the same as
-- "no data yet" -- the retry loop below already handles that.
local function tryGetPlayerData()
    local ok, data = pcall(function() return exports.kora_core:getPlayerData() end)
    if ok then return data end
    return nil
end

local function reconcileLogin(value)
    loginGeneration = loginGeneration + 1
    local generation = loginGeneration

    if value ~= true or inCinematicMode() then
        notifyLoginChange(false)
        return
    end

    -- State bags and net events are independently replicated.  kora_core writes
    -- this key after sending its snapshot, but wait defensively until the
    -- mirror is actually visible before letting the HUD render player data.
    -- Capped at 200 frames per round rather than an unbounded Wait(0) spin, so
    -- a mirror that never populates can't leave this thread running forever --
    -- not QB.loops.controlled, since this file must keep working even with QB
    -- entirely absent (see the "missing optional kora_lib status export" test).
    --
    -- A single 200-frame timeout used to be treated as permanent failure: if
    -- kora_core was ALSO restarting/still booting at that moment, `loggedIn`
    -- would stay false forever with nothing left to re-arm this thread (the
    -- state bag only changes again on an actual login/logout). Instead, retry
    -- up to RECONCILE_MAX_ROUNDS times, nudging kora_core for a fresh snapshot
    -- via its resync export between rounds -- bounded, so this still can't
    -- hang forever, but no longer gives up after one attempt.
    CreateThread(function()
        for round = 1, RECONCILE_MAX_ROUNDS do
            local attempts = 0
            local data = tryGetPlayerData()
            while generation == loginGeneration and LocalPlayer.state[LOGIN_STATE] == true
                and not inCinematicMode()
                and data == nil
                and attempts < RECONCILE_WAIT_FRAMES do
                Wait(0)
                attempts = attempts + 1
                data = tryGetPlayerData()
            end

            if generation ~= loginGeneration or LocalPlayer.state[LOGIN_STATE] ~= true
                or inCinematicMode() then
                return
            end

            if data ~= nil then
                notifyLoginChange(true)
                return
            end

            if round < RECONCILE_MAX_ROUNDS then
                pcall(function() exports.kora_core:requestResync() end)
            end
        end
    end)
end

-- Deferred until the session is live, NOT run at chunk load: a state bag
-- handler is bound to a bag NAME resolved once, at registration, and the local
-- player's server id does not exist yet while this chunk loads. Client scripts
-- start during the join/loading screen, where GetPlayerServerId(PlayerId())
-- (and therefore QB.cache.serverId(), which just mirrors it) is -1 -- so
-- registering here would permanently subscribe to `player:-1`, a bag nothing
-- ever writes. Every login, cinematic-mode and cash change would then be
-- invisible to this adapter: `loggedIn` stays false for the whole session and
-- the HUD never appears at all. kora_multichar/client.lua defers its own
-- `qbcore:loggedIn` handler for exactly this reason.
--
-- Waiting on the server id itself as well as the session flag: QB.cache
-- re-reads the native on kora_lib's shared tick (Config.cache.tickInterval), so
-- it can still be reporting the pre-session -1 for one tick after
-- NetworkIsSessionStarted() flips.
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end

    local serverId = QB.cache.serverId()
    while type(serverId) ~= 'number' or serverId <= 0 do
        Wait(0)
        serverId = QB.cache.serverId()
    end

    local localPlayerBag = ('player:%s'):format(serverId)

    -- CFX fires a state bag change handler BEFORE the new value is committed
    -- to the local bag store -- reading LocalPlayer.state inside the handler
    -- still returns the PREVIOUS value (the docs' own guidance is to Wait(0)
    -- first). reconcileLogin's show path re-reads BOTH keys from the store,
    -- so any handler-triggered reconcile that could SHOW the HUD must wait a
    -- frame or it decides on stale state. This was the second "HUD never
    -- shows" bug: the login sequence ends with qbmultichar:mode flipping
    -- 'spawn' -> false, and the release-side reconcile re-read the store
    -- synchronously, still saw 'spawn', and concluded "still cinematic" --
    -- permanently, since that clear is a login's final transition. Hide paths
    -- stay synchronous: they act on the handler's own authoritative argument
    -- and never read the store, so logout/cutscene-start hide instantly.
    local function reconcileNextFrame()
        CreateThread(function()
            Wait(0) -- let the notifying change (and any batched with it) commit
            reconcileLogin(LocalPlayer.state[LOGIN_STATE] == true)
        end)
    end

    AddStateBagChangeHandler(LOGIN_STATE, localPlayerBag, function(_, _, value)
        if value ~= true then
            reconcileLogin(false) -- pure hide: short-circuits before any store read
        else
            reconcileNextFrame()
        end
    end)

    -- kora_core marks the character logged in before the mandatory spawn carousel
    -- ends. kora_multichar's replicated mode is the authoritative cinematic gate,
    -- so the HUD stays hidden through selection, spawning, and scene-studio
    -- previews.
    AddStateBagChangeHandler(CINEMATIC_MODE_STATE, localPlayerBag, function(_, _, value)
        if value then
            loginGeneration = loginGeneration + 1
            notifyLoginChange(false)
        else
            reconcileNextFrame()
        end
    end)

    AddStateBagChangeHandler(CASH_STATE, localPlayerBag, function(_, _, value)
        if type(value) ~= 'number' then return end
        schedulePush()
    end)

    -- Reconcile immediately for `ensure kora_hud` after a character is already
    -- loaded; a bag-change handler only observes future transitions. Runs after
    -- the handlers are armed so a transition landing mid-reconcile is still
    -- observed rather than dropped.
    reconcileLogin(LocalPlayer.state[LOGIN_STATE] == true)
end)

---@return boolean
function HudBridge.isLoggedIn()
    return loggedIn
end

---@param handler fun(loggedIn: boolean)
function HudBridge.onLoginChange(handler)
    loginHandlers[#loginHandlers + 1] = handler
end

-- Seatbelt gameplay is owned by kora_smallresources. The old HUD command remains
-- a forwarding entry point, and the B key is registered by that owner once.
local seatbelt = LocalPlayer.state.seatbelt == true
RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function(enabled)
    seatbelt = enabled == true
end)
RegisterCommand('hud_toggleseatbelt', function()
    TriggerEvent('qbsmallresources:client:toggleSeatbelt')
end, false)

-- Cheap hot-path accessor for the vehicle sampler. Keeping this separate from
-- getSnapshot avoids framework and status exports on every telemetry tick.
---@return boolean
function HudBridge.getSeatbelt()
    return seatbelt
end

-- Map kora_core's PlayerData shape onto the HUD snapshot contract. Defensive about
-- nils: the mirror may be empty for a moment right after join, before the first
-- snapshot arrives.
local function snapshotFrom(data)
    data = data or {}
    local job = data.job or {}
    local gang = data.gang
    local money = data.money or {}
    local meta = data.metadata or {}

    local jobSnap = {
        name = job.name or 'unemployed',
        label = job.label or 'Civilian',
        grade = (job.grade and job.grade.level) or 0,
        gradeLabel = (job.grade and job.grade.name) or 'Civilian',
        onDuty = job.onduty ~= false,
    }

    local gangSnap = nil
    if gang and gang.name and gang.name ~= 'none' then
        gangSnap = {
            name = gang.name,
            label = gang.label or gang.name,
            grade = (gang.grade and gang.grade.level) or 0,
            gradeLabel = (gang.grade and gang.grade.name) or '',
        }
    end

    return {
        job = jobSnap,
        gang = gangSnap,
        cash = tonumber(LocalPlayer.state[CASH_STATE]) or money.cash or 0,
        bank = money.bank or 0,
        hunger = meta.hunger or 100,
        thirst = meta.thirst or 100,
        stress = meta.stress or 0,
        seatbelt = HudBridge.getSeatbelt(),
        status = activeStatus(),
    }
end

---@return QBHudBridgeSnapshot
function HudBridge.getSnapshot()
    return snapshotFrom(exports.kora_core:getPlayerData())
end

-- Optional push path: subscribe to the money/job/gang/metadata roots and hand
-- the consumer a fresh snapshot the instant any of them changes. client/hud.lua
-- uses this when present and falls back to polling getSnapshot otherwise.
---@param handler fun(snapshot: QBHudBridgeSnapshot)
function HudBridge.onChange(handler)
    dataHandlers[#dataHandlers + 1] = handler

    -- One subscription per relevant root. onPlayerDataChange fires the handler
    -- with (path, value); we ignore the specifics and re-snapshot -- but via
    -- schedulePush, so four roots changing together cost one snapshot, not
    -- four.
    for _, root in ipairs({ 'money', 'job', 'gang', 'metadata' }) do
        exports.kora_core:onPlayerDataChange({ root }, schedulePush)
    end

    -- Push once immediately so the HUD reflects current state without waiting
    -- for the first change. Capped rather than an unbounded poll -- see the
    -- reconcileLogin thread above for why this doesn't use QB.loops.controlled.
    CreateThread(function()
        local attempts = 0
        while exports.kora_core:getPlayerData() == nil and attempts < 100 do
            Wait(100)
            attempts = attempts + 1
        end
        handler(HudBridge.getSnapshot())
    end)
end
