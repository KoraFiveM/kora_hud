-- Local-player buckle/unbuckle sound.
--
-- The seatbelt itself is owned by kora_utils (B key); this resource only hears
-- about it through seatbelt:client:ToggleSeatbelt, the same event the bridge
-- adapter already consumes, so no second keybind or poll is needed. The stub
-- bridge raises the same event from its own toggle.
--
-- kora_utils fires that event with `false` on every vehicle change as well as on
-- a real toggle, so a sound only plays on an actual change of state AND while
-- the player is still seated -- entering or leaving a vehicle is silent.
--
-- Every Config value is read when a sound plays, never cached at load.
-- SendNUIMessage is the raw native on purpose (see the NOTE in client/hud.lua):
-- this resource owns its own NUI frame.
local buckled = LocalPlayer.state.seatbelt == true

local DEFAULT_NATIVE = {
    buckle = { name = 'SELECT', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    unbuckle = { name = 'BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}

---@return table
local function soundConfig()
    local seatbelt = type(Config) == 'table' and Config.seatbelt
    return type(seatbelt) == 'table' and type(seatbelt.sound) == 'table' and seatbelt.sound or {}
end

---@param value any
---@return number
local function clampVolume(value)
    local volume = tonumber(value)
    if volume == nil then return 0.5 end
    return math.min(1.0, math.max(0.0, volume))
end

---@param isBuckle boolean
local function play(isBuckle)
    local cfg = soundConfig()
    if cfg.enabled == false then return end
    local volume = clampVolume(cfg.volume)
    if volume <= 0 then return end

    if cfg.backend == 'native' then
        -- Frontend sounds have no volume control; the volume option only
        -- applies to the bundled NUI sounds.
        local native = type(cfg.native) == 'table' and cfg.native or {}
        local pick = (isBuckle and native.buckle or native.unbuckle)
            or (isBuckle and DEFAULT_NATIVE.buckle or DEFAULT_NATIVE.unbuckle)
        PlaySoundFrontend(-1, pick.name, pick.set, true)
        return
    end

    local file = isBuckle and (cfg.buckleFile or 'seatbelt_buckle.wav')
        or (cfg.unbuckleFile or 'seatbelt_unbuckle.wav')
    SendNUIMessage({ action = 'qbhud:seatbeltSound', data = { file = file, volume = volume } })
end

AddEventHandler('seatbelt:client:ToggleSeatbelt', function(enabled)
    local now = enabled == true
    if now == buckled then return end
    buckled = now
    if not IsPedInAnyVehicle(PlayerPedId(), false) then return end
    play(now)
end)
