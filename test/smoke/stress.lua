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

harness.report("stress")
