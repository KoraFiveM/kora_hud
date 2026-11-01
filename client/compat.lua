-- qb-hud client events. Display only: nothing here writes server state or
-- metadata. Needs and stress overlay the local snapshot until the next
-- authoritative kora_core push replaces it; the rest are presentation flags
-- sent to the NUI on qbhud:compat.
HudCompat = {}

local function clamp(value, min, max)
    value = tonumber(value)
    if value ~= value or value == nil then return nil end
    return math.min(max, math.max(min, value))
end

local state = {
    dynamicHealth = false,
    altitude = false,
    showSeatbelt = true,
    cruise = false,
    harness = nil,
    nitrous = { level = 0, active = false },
}
HudCompat.state = state

local host

---@param hooks { overlay: fun(fields: table), snapshot: fun(): table, push: fun(), applyMinimap: fun()|nil }
function HudCompat.attach(hooks)
    host = hooks
end

local function push()
    if host then host.push() end
end

---@param hunger any
---@param thirst any
function HudCompat.updateNeeds(hunger, thirst)
    if not host then return end
    local fields = {}
    fields.hunger = clamp(hunger, 0, 100)
    fields.thirst = clamp(thirst, 0, 100)
    if fields.hunger or fields.thirst then host.overlay(fields) end
end

---@param stress any
function HudCompat.updateStress(stress)
    local value = clamp(stress, 0, 100)
    if host and value then host.overlay({ stress = value }) end
end

---@param level any
---@param active any
function HudCompat.updateNitrous(level, active)
    state.nitrous = { level = clamp(level, 0, 100) or 0, active = active == true }
    push()
end

---@param uses any
function HudCompat.updateHarness(uses)
    state.harness = clamp(uses, 0, 100)
    push()
end

function HudCompat.toggle(key)
    state[key] = not state[key]
    push()
end

local ACCOUNT_LABELS = { cash = 'Cash', bank = 'Bank' }

---Shows the player's own balance from the authoritative snapshot; the amount a
---caller passes is ignored.
---@param account any
---@return number|nil amount
function HudCompat.showAccount(account)
    if not host or ACCOUNT_LABELS[account] == nil then return nil end
    local amount = tonumber((host.snapshot() or {})[account]) or 0
    amount = math.floor(amount + 0.5)
    if HudCompat.notify then HudCompat.notify(ACCOUNT_LABELS[account], amount) end
    return amount
end

RegisterNetEvent('hud:client:UpdateNeeds', HudCompat.updateNeeds)
RegisterNetEvent('hud:client:UpdateStress', HudCompat.updateStress)
RegisterNetEvent('hud:client:UpdateNitrous', HudCompat.updateNitrous)
RegisterNetEvent('hud:client:UpdateHarness', HudCompat.updateHarness)
RegisterNetEvent('hud:client:ToggleHealth', function() HudCompat.toggle('dynamicHealth') end)
RegisterNetEvent('hud:client:ToggleAirHud', function() HudCompat.toggle('altitude') end)
RegisterNetEvent('hud:client:ToggleShowSeatbelt', function() HudCompat.toggle('showSeatbelt') end)
RegisterNetEvent('seatbelt:client:ToggleCruise', function() HudCompat.toggle('cruise') end)
RegisterNetEvent('hud:client:ShowAccounts', function(account) HudCompat.showAccount(account) end)

RegisterNetEvent('hud:client:LoadMap', function()
    if host and host.applyMinimap then host.applyMinimap() end
end)

if type(BeginTextCommandThefeedPost) == 'function' then
    HudCompat.notify = function(label, amount)
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('%s: $%d'):format(label, amount))
        EndTextCommandThefeedPostTicker(false, false)
    end
end

for account in pairs(ACCOUNT_LABELS) do
    RegisterCommand(account, function() HudCompat.showAccount(account) end, false)
end
