-- Stub KoraHudBridge implementation (see shared/bridge.lua for the contract).
-- Returns normalized mock data since no framework (QBCore/ESX/ox_core) is
-- installed to source real job/gang/money/needs data from yet. Swapping this
-- for a real adapter later means writing a new client/bridge/<name>.lua that
-- assigns the same HudBridge.getSnapshot -- client/hud.lua never changes.
HudBridge = HudBridge or {}

-- Status effects enrich the standalone bridge when kora_lib provides them, but
-- they must never make the HUD unavailable during a staggered kora_lib update.
local function activeStatus()
    local ok, status = pcall(function() return Kora.status.getActive() end)
    if ok and type(status) == 'table' then return status end
    return {}
end

local state = {
    job = { name = "unemployed", label = "Civilian", grade = 0, gradeLabel = "Civilian", onDuty = false },
    gang = nil,
    cash = 500,
    bank = 5000,
    hunger = 100,
    thirst = 100,
    stress = 0,
    seatbelt = false,
}

-- Slowly drains hunger/thirst so the HUD visibly changes during manual
-- testing -- purely a dev/demo convenience, not meant to be realistic.
CreateThread(function()
    while true do
        Wait(60000)
        state.hunger = math.max(0, state.hunger - 1)
        state.thirst = math.max(0, state.thirst - 1.5)
    end
end)

-- Stock FiveM has no seatbelt native/state at all -- that's a framework-added
-- mechanic normally toggled by the framework's own vehicle script. Until a
-- real adapter wires up that framework's actual seatbelt state, the stub
-- owns a placeholder toggled by its own keybind.
local function toggleSeatbelt()
    state.seatbelt = not state.seatbelt
    -- Same event kora_utils raises, so the buckle sound and any other listener
    -- see the stub's toggle exactly like the real seatbelt.
    TriggerEvent('seatbelt:client:ToggleSeatbelt', state.seatbelt)
end

-- Retain the documented console command while Kora.keybind owns the actual
-- settings mapping and lifecycle.
RegisterCommand('hud_toggleseatbelt', toggleSeatbelt, false)
Kora.keybind.add({
    name = 'hud_toggleseatbelt',
    description = 'Toggle seatbelt (qb-hud stub bridge)',
    defaultMapper = 'keyboard',
    defaultKey = 'B',
    onPressed = toggleSeatbelt,
})

---@return boolean
function HudBridge.getSeatbelt()
    return state.seatbelt
end

-- Manual-test commands, mirroring kora_lib-playground's command-driven style --
-- dev convenience only.
RegisterCommand("hudtest_cash", function(_, args)
    state.cash = tonumber(args[1]) or state.cash
end, false)

RegisterCommand("hudtest_bank", function(_, args)
    state.bank = tonumber(args[1]) or state.bank
end, false)

RegisterCommand("hudtest_stress", function(_, args)
    state.stress = math.max(0, math.min(100, tonumber(args[1]) or state.stress))
end, false)

---@return KoraHudBridgeSnapshot
function HudBridge.getSnapshot()
    return {
        job = state.job,
        gang = state.gang,
        cash = state.cash,
        bank = state.bank,
        hunger = state.hunger,
        thirst = state.thirst,
        stress = state.stress,
        seatbelt = state.seatbelt,
        status = activeStatus(),
    }
end
