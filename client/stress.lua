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

-- Speed stress can only be gained in a vehicle, so instead of a session-long
-- poll the worker is started by kora_lib's cache 'vehicle' enter edge and ends
-- on the exit edge (generation token: rapid exit/enter or a re-registration
-- can never leave two workers running).
local speedGeneration = 0
local speedInVehicle = false

local function startSpeedWorker()
    speedGeneration = speedGeneration + 1
    local generation = speedGeneration
    CreateThread(function()
        while generation == speedGeneration do
            Wait(math.max(500, tonumber(cfg().speed and cfg().speed.interval) or 10000))
            if generation ~= speedGeneration then return end
            -- In-vehicle native check kept as the per-sample gate before the
            -- state bag read. Player data (a full cross-resource export) is
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
end

local function speedVehicleChanged(vehicle)
    local inVehicle = vehicle ~= nil and vehicle ~= false and vehicle ~= 0
    if inVehicle == speedInVehicle then return end
    speedInVehicle = inVehicle
    if inVehicle then
        startSpeedWorker()
    else
        speedGeneration = speedGeneration + 1 -- the running worker exits on its next wake
    end
end

-- kora_lib drops onChange listeners when it restarts: re-register, and seed from
-- the current value (onChange never reports it), at load and on every restart.
-- pcall'd so kora_lib mid-restart cannot abort this chunk before the shooting
-- loop below starts; the restart handler registers it once kora_lib is back.
local function watchSpeedVehicle()
    Kora.cache.onChange('vehicle', speedVehicleChanged)
    speedVehicleChanged(Kora.cache.vehicle())
end
pcall(watchSpeedVehicle)
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'kora_lib' then pcall(watchSpeedVehicle) end
end)

-- Shooting stress is driven by kora_lib's cached weapon rather than polled:
-- IsPedShooting can only be true with a gun or throwable selected, so the fast
-- shot sampling thread runs ONLY while one is held and nothing at all runs
-- otherwise. Weapon groups (GetWeapontypeGroup) that can fire; melee, unarmed,
-- petrol can, fire extinguisher, parachute, etc. are deliberately absent.
local WEAPON_UNARMED = 2725352035
local SHOOTING_GROUPS = {
    [416676503] = true,  -- GROUP_PISTOL
    [3337201093] = true, -- GROUP_SMG
    [970310034] = true,  -- GROUP_RIFLE
    [1159398588] = true, -- GROUP_MG
    [860033945] = true,  -- GROUP_SHOTGUN
    [3082541095] = true, -- GROUP_SNIPER
    [2725924767] = true, -- GROUP_HEAVY
    [1548507267] = true, -- GROUP_THROWN
    [690389602] = true,  -- GROUP_STUNGUN
}

-- Natives and the cache may hand hashes back signed; compare them unsigned.
local function unsigned(hash)
    hash = tonumber(hash)
    if hash and hash < 0 then hash = hash + 4294967296 end
    return hash
end

---@param weapon any
---@return boolean
local function shootingWeapon(weapon)
    weapon = unsigned(weapon)
    if not weapon or weapon == 0 or weapon == WEAPON_UNARMED then return false end
    if type(GetWeapontypeGroup) ~= "function" then return false end
    return SHOOTING_GROUPS[unsigned(GetWeapontypeGroup(weapon))] == true
end

local function shootingEnabled()
    return cfg().enabled ~= false and sub(cfg().shooting).enabled ~= false
end

local currentWeapon, dead = nil, false
-- Bumped whenever the sampling thread should stop; a thread only keeps looping
-- while the generation it was started with is still current.
local shootingGen, shootingActive = 0, false

local function evaluateShooting()
    local want = not dead and shootingEnabled() and shootingWeapon(currentWeapon)
    if want == shootingActive then return end
    shootingGen = shootingGen + 1
    shootingActive = want
    if not want then return end
    local gen = shootingGen
    CreateThread(function()
        while gen == shootingGen do
            if not shootingEnabled() then
                -- Re-evaluated on the next weapon change.
                shootingActive = false
                return
            end
            local wait = 50
            local ped = PlayerPedId()
            if IsPedShooting(ped) then
                local data = playerData()
                gain(Stress.shootingGain({ weapon = GetSelectedPedWeapon(ped), job = jobName(data) }), data)
                wait = math.max(100, tonumber(cfg().shooting and cfg().shooting.cooldown) or 3000)
            end
            Wait(wait)
        end
    end)
end

-- Re-reads the cached state (load, kora_lib restart) and re-evaluates.
local function refreshShooting()
    local ok, weapon = pcall(function() return Kora.cache.weapon() end)
    if ok then currentWeapon = weapon end
    local okDead, isDead = pcall(function() return Kora.cache.isDead() end)
    if okDead then dead = isDead == true end
    evaluateShooting()
end

-- A ped change needs no listener of its own: the cached weapon is read from
-- the current ped, so a different weapon arrives as a weapon change, and the
-- sampling thread resolves PlayerPedId() on every pass.
local function subscribeShooting()
    pcall(function()
        Kora.cache.onChange("weapon", function(weapon)
            currentWeapon = weapon
            evaluateShooting()
        end)
    end)
    pcall(function()
        Kora.cache.onChange("isDead", function(isDead)
            dead = isDead == true
            evaluateShooting()
        end)
    end)
    refreshShooting()
end

subscribeShooting()

-- A kora_lib restart drops its onChange listeners; register them again and
-- re-read the weapon rather than trusting a value that no longer updates.
AddEventHandler("onClientResourceStart", function(resource)
    if resource == "kora_lib" then subscribeShooting() end
end)

return Stress
