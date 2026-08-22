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

-- Seatbelt is still a placeholder: qbcore's default metadata has no seatbelt
-- state (it's a vehicle-script mechanic), so this adapter owns the same keybind
-- the stub did until a seatbelt system is wired into a vehicle resource.
local seatbelt = false
RegisterCommand('hud_toggleseatbelt', function() seatbelt = not seatbelt end, false)
RegisterKeyMapping('hud_toggleseatbelt', 'Toggle seatbelt (qbcore adapter)', 'keyboard', 'B')

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
        cash = money.cash or 0,
        bank = money.bank or 0,
        hunger = meta.hunger or 100,
        thirst = meta.thirst or 100,
        stress = meta.stress or 0,
        seatbelt = seatbelt,
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
    local function push()
        handler(HudBridge.getSnapshot())
    end
    -- One subscription per relevant root. onPlayerDataChange fires the handler
    -- with (path, value); we ignore the specifics and re-snapshot (cheap).
    for _, root in ipairs({ 'money', 'job', 'gang', 'metadata' }) do
        exports.qbcore:onPlayerDataChange({ root }, function() push() end)
    end
    -- Push once immediately so the HUD reflects current state without waiting
    -- for the first change.
    CreateThread(function()
        -- Wait until the mirror is populated (first snapshot has arrived).
        while exports.qbcore:getPlayerData() == nil do Wait(100) end
        push()
    end)
end
