-- Real QBHudBridge adapter, sourcing live player data from qbcore (see
-- shared/bridge.lua for the contract). This is the end-to-end proof that qbcore
-- + qbsql work against a consumer that already existed in this repo: the HUD
-- shows real job/gang/money/needs, driven by qbcore's DELTA replication rather
-- than polling framework internals.
--
-- Swapped in by setting Config.bridge.adapter = "qbcore" and listing this file
-- (instead of stub.lua) in qbhud/fxmanifest.lua's client_scripts. client/hud.lua
-- never changes -- it only ever calls HudBridge.getSnapshot()/onChange.
--
-- Reads go through qbcore's client mirror (exports.qbcore:getPlayerData), which
-- is a plain local table lookup with zero per-read network cost. Changes are
-- PUSHED via exports.qbcore:onPlayerDataChange, so the HUD updates the instant a
-- delta lands rather than on a poll interval -- the whole point of the delta
-- protocol.

HudBridge = HudBridge or {}

-- Character-session state is server-owned.  Do not use the legacy load/unload
-- events here: they are compatibility signals, not the HUD's authority.  The
-- state bag persists across qbhud restarts and is replicated to LocalPlayer.
local LOGIN_STATE = 'qbcore:loggedIn'
local CINEMATIC_MODE_STATE = 'qbmultichar:mode'
local CASH_STATE = 'qbcore:money:cash'
local loggedIn = false
local loginHandlers = {}
local loginGeneration = 0
local dataHandlers = {}

-- Status effects are an optional qblib enhancement to the HUD, never a
-- prerequisite for the base player HUD.  In particular, this lets qbhud
-- start cleanly during a rolling update where qbhud has been updated before a
-- server has restarted qblib with the status exports.  A missing export must
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

-- pcall'd: qbcore may itself be mid-restart (its export table not yet
-- published, or its own resource not fully started) at the exact moment this
-- thread runs -- e.g. a supervisor restarting qbcore and qbhud together. An
-- uncaught error from a cross-resource export call would otherwise silently
-- kill this CreateThread body (standard Lua coroutine behaviour), leaving
-- `loggedIn` stuck at whatever it last was. Treat a failed call the same as
-- "no data yet" -- the retry loop below already handles that.
local function tryGetPlayerData()
    local ok, data = pcall(function() return exports.qbcore:getPlayerData() end)
    if ok then return data end
    return nil
end

local function reconcileLogin(value)
    loginGeneration = loginGeneration + 1
    local generation = loginGeneration

    if value ~= true or LocalPlayer.state[CINEMATIC_MODE_STATE] ~= nil then
        notifyLoginChange(false)
        return
    end

    -- State bags and net events are independently replicated.  qbcore writes
    -- this key after sending its snapshot, but wait defensively until the
    -- mirror is actually visible before letting the HUD render player data.
    -- Capped at 200 frames per round rather than an unbounded Wait(0) spin, so
    -- a mirror that never populates can't leave this thread running forever --
    -- not QB.loops.controlled, since this file must keep working even with QB
    -- entirely absent (see the "missing optional qblib status export" test).
    --
    -- A single 200-frame timeout used to be treated as permanent failure: if
    -- qbcore was ALSO restarting/still booting at that moment, `loggedIn`
    -- would stay false forever with nothing left to re-arm this thread (the
    -- state bag only changes again on an actual login/logout). Instead, retry
    -- up to RECONCILE_MAX_ROUNDS times, nudging qbcore for a fresh snapshot
    -- via its resync export between rounds -- bounded, so this still can't
    -- hang forever, but no longer gives up after one attempt.
    CreateThread(function()
        for round = 1, RECONCILE_MAX_ROUNDS do
            local attempts = 0
            local data = tryGetPlayerData()
            while generation == loginGeneration and LocalPlayer.state[LOGIN_STATE] == true
                and LocalPlayer.state[CINEMATIC_MODE_STATE] == nil
                and data == nil
                and attempts < RECONCILE_WAIT_FRAMES do
                Wait(0)
                attempts = attempts + 1
                data = tryGetPlayerData()
            end

            if generation ~= loginGeneration or LocalPlayer.state[LOGIN_STATE] ~= true
                or LocalPlayer.state[CINEMATIC_MODE_STATE] ~= nil then
                return
            end

            if data ~= nil then
                notifyLoginChange(true)
                return
            end

            if round < RECONCILE_MAX_ROUNDS then
                pcall(function() exports.qbcore:requestResync() end)
            end
        end
    end)
end

local localPlayerBag = ('player:%s'):format(QB.cache.serverId())
AddStateBagChangeHandler(LOGIN_STATE, localPlayerBag, function(_, _, value)
    reconcileLogin(value == true)
end)

-- qbcore marks the character logged in before the mandatory spawn carousel
-- ends. qbmultichar's replicated mode is the authoritative cinematic gate, so
-- the HUD stays hidden through selection, spawning, and scene-studio previews.
AddStateBagChangeHandler(CINEMATIC_MODE_STATE, localPlayerBag, function(_, _, value)
    if value ~= nil then
        loginGeneration = loginGeneration + 1
        notifyLoginChange(false)
    else
        reconcileLogin(LocalPlayer.state[LOGIN_STATE] == true)
    end
end)

-- Reconcile immediately for `ensure qbhud` after a character is already
-- loaded; a bag-change handler only observes future transitions.
reconcileLogin(LocalPlayer.state[LOGIN_STATE] == true)

AddStateBagChangeHandler(CASH_STATE, localPlayerBag, function(_, _, value)
    if type(value) ~= 'number' then return end
    for _, handler in ipairs(dataHandlers) do handler(HudBridge.getSnapshot()) end
end)

---@return boolean
function HudBridge.isLoggedIn()
    return loggedIn
end

---@param handler fun(loggedIn: boolean)
function HudBridge.onLoginChange(handler)
    loginHandlers[#loginHandlers + 1] = handler
end

-- Seatbelt is still a placeholder: qbcore's default metadata has no seatbelt
-- state (it's a vehicle-script mechanic), so this adapter owns the same keybind
-- the stub did until a seatbelt system is wired into a vehicle resource.
local seatbelt = false
local function toggleSeatbelt() seatbelt = not seatbelt end
RegisterCommand('hud_toggleseatbelt', toggleSeatbelt, false)
QB.keybind.add({
    name = 'hud_toggleseatbelt',
    description = 'Toggle seatbelt (qbcore adapter)',
    defaultMapper = 'keyboard',
    defaultKey = 'B',
    onPressed = toggleSeatbelt,
})

-- Cheap hot-path accessor for the vehicle sampler. Keeping this separate from
-- getSnapshot avoids framework and status exports on every telemetry tick.
---@return boolean
function HudBridge.getSeatbelt()
    return seatbelt
end

-- Map qbcore's PlayerData shape onto the HUD snapshot contract. Defensive about
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
        seatbelt = seatbelt,
        status = activeStatus(),
    }
end

---@return QBHudBridgeSnapshot
function HudBridge.getSnapshot()
    return snapshotFrom(exports.qbcore:getPlayerData())
end

-- Optional push path: subscribe to the money/job/gang/metadata roots and hand
-- the consumer a fresh snapshot the instant any of them changes. client/hud.lua
-- uses this when present and falls back to polling getSnapshot otherwise.
---@param handler fun(snapshot: QBHudBridgeSnapshot)
function HudBridge.onChange(handler)
    dataHandlers[#dataHandlers + 1] = handler
    local function push()
        handler(HudBridge.getSnapshot())
    end
    -- One subscription per relevant root. onPlayerDataChange fires the handler
    -- with (path, value); we ignore the specifics and re-snapshot (cheap).
    for _, root in ipairs({ 'money', 'job', 'gang', 'metadata' }) do
        exports.qbcore:onPlayerDataChange({ root }, function() push() end)
    end
    -- Push once immediately so the HUD reflects current state without waiting
    -- for the first change. Capped rather than an unbounded poll -- see the
    -- reconcileLogin thread above for why this doesn't use QB.loops.controlled.
    CreateThread(function()
        local attempts = 0
        while exports.qbcore:getPlayerData() == nil and attempts < 100 do
            Wait(100)
            attempts = attempts + 1
        end
        push()
    end)
end
