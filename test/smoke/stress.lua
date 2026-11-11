-- client/stress.lua: speed and shooting stress gain rules, all config-driven.
local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")

local function load(stress)
    _G.Config = { stress = stress }
    _G.CreateThread = nil
    return assert(loadfile(repoRoot .. "client/stress.lua"))()
end

local base = {
    enabled = true,
    whitelistedJobs = { "police" },
    speed = { threshold = 180, unit = "kmh", gainMin = 2, gainMax = 2 },
    shooting = { chance = 50, gainMin = 2, gainMax = 2, whitelistedWeapons = { [42] = true } },
}
local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
    return o
end
local function fixedRandom(roll) return function(a, b) return roll or a end end

harness.test("speed at or above threshold gains, below does not", function()
    local S = load(copy(base))
    harness.assertEqual(S.speedGain({ speed = 60, isDriver = true }, fixedRandom()), 2) -- 216 km/h
    harness.assertEqual(S.speedGain({ speed = 40, isDriver = true }, fixedRandom()), 0) -- 144 km/h
end)

harness.test("mph unit changes the comparison", function()
    local c = copy(base)
    c.speed.unit, c.speed.threshold = "mph", 100
    local S = load(c)
    harness.assertEqual(S.speedGain({ speed = 40, isDriver = true }, fixedRandom()), 0) -- 89 mph
    harness.assertEqual(S.speedGain({ speed = 50, isDriver = true }, fixedRandom()), 2) -- 112 mph
end)

harness.test("passengers and whitelisted jobs gain nothing from speed", function()
    local S = load(copy(base))
    harness.assertEqual(S.speedGain({ speed = 80, isDriver = false }, fixedRandom()), 0)
    harness.assertEqual(S.speedGain({ speed = 80, isDriver = true, job = "police" }, fixedRandom()), 0)
end)

harness.test("shooting honours chance, weapons and jobs", function()
    local S = load(copy(base))
    harness.assertEqual(S.shootingGain({ weapon = 1 }, function(a, b) return a == 1 and b == 100 and 50 or a end), 2)
    harness.assertEqual(S.shootingGain({ weapon = 1 }, function(a, b) return a == 1 and b == 100 and 51 or a end), 0)
    harness.assertEqual(S.shootingGain({ weapon = 42 }, fixedRandom(1)), 0)
    harness.assertEqual(S.shootingGain({ weapon = 1, job = "police" }, fixedRandom(1)), 0)
end)

harness.test("disabled switches turn the feature off", function()
    local c = copy(base)
    c.enabled = false
    local S = load(c)
    harness.assertEqual(S.speedGain({ speed = 80, isDriver = true }, fixedRandom()), 0)
    harness.assertEqual(S.shootingGain({ weapon = 1 }, fixedRandom(1)), 0)
    c = copy(base)
    c.shooting.enabled = false
    S = load(c)
    harness.assertEqual(S.shootingGain({ weapon = 1 }, fixedRandom(1)), 0)
end)

harness.test("apply clamps to 0-100", function()
    local S = load(copy(base))
    harness.assertEqual(S.apply(99, 5), 100)
    harness.assertEqual(S.apply(nil, 3), 3)
end)

harness.test("speed gain only looks up the job once the speed checks pass", function()
    local S = load(copy(base))
    local lookups = 0
    local job = function() lookups = lookups + 1; return "police" end
    harness.assertEqual(S.speedGain({ speed = 40, isDriver = true, job = job }, fixedRandom()), 0)
    harness.assertEqual(S.speedGain({ speed = 80, isDriver = false, job = job }, fixedRandom()), 0)
    harness.assertEqual(lookups, 0, "slow or passenger: no player-data export")
    harness.assertEqual(S.speedGain({ speed = 80, isDriver = true, job = job }, fixedRandom()), 0)
    harness.assertEqual(lookups, 1, "whitelisted job is still honoured")
end)

local mocks = require("mocks")

local PISTOL, KNIFE, UNARMED = 453432689, 2578778090, 2725352035
local GROUPS = { [PISTOL] = 416676503, [KNIFE] = 3566412244, [UNARMED] = 2685387236 }

-- Loads the module with a controllable thread list and Kora.cache, and
-- returns handles for driving the event-driven shooting thread.
local function loadShooting(initial, config)
    _G.Config = { stress = config or copy(base) }
    _G.Kora = nil
    local env = { threads = {}, handlers = {}, shooting = false, natives = 0 }
    env.cache = mocks.installKoraCache(initial)
    _G.CreateThread = function(fn)
        local co = coroutine.create(fn)
        env.threads[#env.threads + 1] = co
        local ok, ms = coroutine.resume(co)
        assert(ok, ms)
        env.lastWait = ms
    end
    _G.Wait = function(ms) coroutine.yield(ms) end
    _G.AddEventHandler = function(name, fn)
        env.handlers[name] = env.handlers[name] or {}
        table.insert(env.handlers[name], fn)
    end
    _G.PlayerPedId = function() return 1 end
    _G.GetWeapontypeGroup = function(w) return GROUPS[w] or 0 end
    _G.IsPedShooting = function() env.natives = env.natives + 1; return env.shooting end
    _G.IsPedInAnyVehicle = function() return false end
    function env.alive()
        local n = 0
        for _, co in ipairs(env.threads) do
            if coroutine.status(co) == "suspended" then n = n + 1 end
        end
        return n
    end
    -- Resumes every live thread once (the speed thread is always one of them).
    function env.step()
        for _, co in ipairs(env.threads) do
            if coroutine.status(co) == "suspended" then assert(coroutine.resume(co)) end
        end
    end
    assert(loadfile(repoRoot .. "client/stress.lua"))()
    return env
end

local function cleanup()
    _G.CreateThread, _G.Wait, _G.AddEventHandler, _G.PlayerPedId = nil, nil, nil, nil
    _G.GetWeapontypeGroup, _G.IsPedShooting, _G.IsPedInAnyVehicle, _G.Kora = nil, nil, nil, nil
end

harness.test("no shooting thread while unarmed or holding melee", function()
    local env = loadShooting({ weapon = UNARMED })
    harness.assertEqual(env.alive(), 0, "on foot and unarmed: nothing runs")
    env.cache.set("weapon", KNIFE)
    harness.assertEqual(env.alive(), 0, "melee does not start sampling")
    harness.assertEqual(env.natives, 0, "no IsPedShooting calls at all")
    cleanup()
end)

harness.test("a gun starts the 50ms sampling thread, unarmed ends it", function()
    local env = loadShooting({ weapon = UNARMED })
    env.cache.set("weapon", PISTOL)
    harness.assertEqual(env.alive(), 1, "sampling thread started")
    harness.assertEqual(env.lastWait, 50, "shots are sampled every 50ms")
    env.cache.set("weapon", UNARMED)
    env.step()
    harness.assertEqual(env.alive(), 0, "sampling thread exited")
    cleanup()
end)

harness.test("a gun held at load starts sampling; swapping guns keeps one thread", function()
    local env = loadShooting({ weapon = PISTOL })
    harness.assertEqual(env.alive(), 1)
    GROUPS[123] = 970310034 -- a rifle
    env.cache.set("weapon", 123)
    env.step()
    harness.assertEqual(env.alive(), 1, "still exactly one sampling thread")
    GROUPS[123] = nil
    cleanup()
end)

harness.test("shooting disabled or dead: no thread", function()
    local c = copy(base)
    c.shooting.enabled = false
    local env = loadShooting({ weapon = PISTOL }, c)
    harness.assertEqual(env.alive(), 0, "disabled in config")
    cleanup()
    env = loadShooting({ weapon = PISTOL })
    env.cache.set("isDead", true)
    env.step()
    harness.assertEqual(env.alive(), 0, "death stops sampling")
    env.cache.set("isDead", false)
    harness.assertEqual(env.alive(), 1, "respawn with a gun resumes it")
    cleanup()
end)

harness.test("kora_lib restart re-registers the weapon listener", function()
    local env = loadShooting({ weapon = UNARMED })
    harness.assertEqual(env.cache.listenerCount("weapon"), 1)
    env.cache.restart()
    harness.assertEqual(env.cache.listenerCount("weapon"), 0)
    for _, fn in ipairs(env.handlers.onClientResourceStart) do fn("kora_lib") end
    harness.assertEqual(env.cache.listenerCount("weapon"), 1, "listener registered again")
    env.cache.set("weapon", PISTOL)
    harness.assertEqual(env.alive(), 1, "new listener drives the thread")
    cleanup()
end)

harness.test("the speed worker runs only while in a vehicle and follows kora_lib restarts", function()
    local env = loadShooting({ weapon = UNARMED })
    harness.assertEqual(env.alive(), 0, "on foot: no speed worker")
    local samples = 0
    _G.IsPedInAnyVehicle = function() samples = samples + 1; return false end
    env.cache.set("vehicle", 5)
    harness.assertEqual(env.alive(), 1, "entering starts the speed worker")
    harness.assertEqual(env.lastWait, 10000, "worker sleeps the configured interval first")
    env.step()
    harness.assertEqual(samples, 1, "worker samples after its interval")
    env.cache.set("vehicle", 6)
    harness.assertEqual(env.alive(), 1, "switching vehicles keeps one worker")
    env.cache.set("vehicle", false)
    env.step()
    harness.assertEqual(env.alive(), 0, "leaving the vehicle ends the worker")
    harness.assertEqual(samples, 1, "no sample after leaving")
    env.cache.restart()
    env.cache.set("vehicle", 7)
    harness.assertEqual(env.alive(), 0, "listener gone while kora_lib is down")
    for _, fn in ipairs(env.handlers.onClientResourceStart) do fn("kora_lib") end
    harness.assertEqual(env.alive(), 1, "restart re-seeds from the current vehicle")
    for _, fn in ipairs(env.handlers.onClientResourceStart) do fn("kora_lib") end
    harness.assertEqual(env.alive(), 1, "re-seeding in the same state never duplicates the worker")
    cleanup()
end)

harness.report("stress")
