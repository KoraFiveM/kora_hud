-- Stress gain from fast driving and shooting.
--
-- kora_hud only ever DISPLAYED stress; nothing in the Kora stack raised it (the
-- gain logic lived in qb-hud). This module restores it, client-side, behind
-- Config.stress. The value is persisted through kora_core metadata via the
-- allow-listed QBCore:Server:SetMetaData compat event (Config.compat.clientMetadataKeys
-- enables `stress` by default, clamped 0-100 server-side); the HUD then picks it up
-- from the metadata delta stream like any other stress change.
--
-- Config is read every tick, never cached, so live edits apply immediately.
local Stress = {}

local MS_TO_KMH, MS_TO_MPH = 3.6, 2.236936

---@return table
local function cfg()
    return type(Config) == "table" and type(Config.stress) == "table" and Config.stress or {}
end

---@param section any
---@return table
local function sub(section)
    return type(section) == "table" and section or {}
end

---@param list any
---@param value string|nil
---@return boolean
local function listed(list, value)
    if type(list) ~= "table" or value == nil then return false end
    if list[value] == true then return true end
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end
    return false
end
Stress.listed = listed

---@param min any
---@param max any
---@return number
local function rollAmount(min, max, random)
    min, max = tonumber(min) or 0, tonumber(max) or 0
    if max < min then min, max = max, min end
    return (random or math.random)(math.floor(min), math.floor(max))
end

---@param speedMs number entity speed in m/s
---@return number
function Stress.speedInUnit(speedMs)
    return speedMs * (cfg().speed and cfg().speed.unit == "mph" and MS_TO_MPH or MS_TO_KMH)
end

---@param state { speed: number, isDriver: boolean, job: string|nil }
---@return number amount 0 when nothing should be gained
function Stress.speedGain(state, random)
    local c, speed = cfg(), sub(cfg().speed)
    if c.enabled == false or speed.enabled == false then return 0 end
    if speed.driverOnly ~= false and not state.isDriver then return 0 end
    if Stress.speedInUnit(state.speed) < (tonumber(speed.threshold) or 180) then return 0 end
    -- `job` may be a function so the caller only pays for the player-data
    -- export once the cheap speed checks have passed.
    local job = state.job
    if type(job) == "function" then job = job() end
    if listed(c.whitelistedJobs, job) then return 0 end
    return rollAmount(speed.gainMin or 1, speed.gainMax or 3, random)
end

---@param state { weapon: number, job: string|nil }
---@return number amount 0 when nothing should be gained
function Stress.shootingGain(state, random)
    local c, shooting = cfg(), sub(cfg().shooting)
    if c.enabled == false or shooting.enabled == false then return 0 end
    if listed(c.whitelistedJobs, state.job) then return 0 end
    if listed(shooting.whitelistedWeapons, state.weapon) then return 0 end
    local chance = tonumber(shooting.chance) or 50
    if (random or math.random)(1, 100) > chance then return 0 end
    return rollAmount(shooting.gainMin or 1, shooting.gainMax or 3, random)
end

---@param current number
---@param delta number
---@return number
function Stress.apply(current, delta)
    return math.min(100, math.max(0, (tonumber(current) or 0) + delta))
end

if type(CreateThread) ~= "function" then return Stress end

---@return table|nil
local function playerData()
    local ok, data = pcall(function() return exports.kora_core:getPlayerData() end)
    if ok and type(data) == "table" then return data end
    return nil
end

local lastSent = 0

---@param delta number
---@param data table|nil player data already fetched this tick
local function gain(delta, data)
    if delta <= 0 then return end
    data = data or playerData()
    if not data then return end
    local meta = type(data.metadata) == "table" and data.metadata or {}
    local current = tonumber(meta.stress) or 0
    local nextValue = Stress.apply(current, delta)
    if nextValue == current then return end
    TriggerServerEvent("QBCore:Server:SetMetaData", "stress", nextValue)
    if cfg().notify ~= false and GetGameTimer() - lastSent > 10000 then
        lastSent = GetGameTimer()
        TriggerEvent("kora_hud:client:stressGained", nextValue)
    end
end

local function jobName(data)
    local job = data and data.job
    return type(job) == "table" and job.name or nil
end

-- Guns and throwables (IsPedArmed flags 4 | 2). IsPedShooting can only be true
-- with one of those selected, so the fast shot sampling is skipped otherwise.
local ARMED_FLAGS = 6

local function armed(ped)
    if type(IsPedArmed) ~= "function" then return true end
    local result = IsPedArmed(ped, ARMED_FLAGS)
    return result == true or result == 1
end

CreateThread(function()
    while true do
        Wait(math.max(500, tonumber(cfg().speed and cfg().speed.interval) or 10000))
        -- On foot first: it is the common case and costs one native, before
        -- the state bag read. Player data (a full cross-resource export) is
        -- only fetched once speed and seat say stress may be gained, and is
        -- then reused by gain() instead of being fetched a second time.
        local ped = PlayerPedId()
        if cfg().enabled ~= false and IsPedInAnyVehicle(ped, false) and LocalPlayer.state.isLoggedIn ~= false then
            local veh = GetVehiclePedIsIn(ped, false)
            local data
            local amount = Stress.speedGain({
                speed = GetEntitySpeed(veh),
                isDriver = GetPedInVehicleSeat(veh, -1) == ped,
                job = function()
                    data = playerData()
                    return jobName(data)
                end,
            })
            gain(amount, data)
        end
    end
end)

CreateThread(function()
    while true do
        local wait = 500
        if cfg().enabled ~= false and sub(cfg().shooting).enabled ~= false then
            local ped = PlayerPedId()
            -- Unarmed (on foot or driving) keeps the 500ms idle sleep; the 50ms
            -- shot sampling only runs while a gun or throwable is selected.
            if armed(ped) then
                wait = 50
                if IsPedShooting(ped) then
                    local data = playerData()
                    gain(Stress.shootingGain({ weapon = GetSelectedPedWeapon(ped), job = jobName(data) }), data)
                    wait = math.max(100, tonumber(cfg().shooting and cfg().shooting.cooldown) or 3000)
                end
            end
        end
        Wait(wait)
    end
end)

return Stress
