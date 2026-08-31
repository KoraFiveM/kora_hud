local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()

-- RegisterCommand/RegisterKeyMapping are specific to the stub bridge, so
-- mocked here rather than in test/mocks.lua. `commands` captures every
-- registered handler by name so tests can invoke them directly, the same way
-- qblib's own smoke tests capture NUI callbacks/net handlers.
local commands = {}
_G.RegisterCommand = function(name, handler)
    commands[name] = handler
end
_G.RegisterKeyMapping = function() end
_G.QB = {
    status = { getActive = function() return {} end },
    keybind = {
        add = function(options)
            commands[options.name] = options.onPressed
            return { remove = function() return true end }
        end,
    },
}

dofile(repoRoot .. "client/bridge/stub.lua")

harness.test("getSnapshot returns every field the QBHudBridgeSnapshot contract documents", function()
    local snapshot = HudBridge.getSnapshot()

    harness.assertTrue(type(snapshot.job) == "table", "job should be a table")
    harness.assertTrue(type(snapshot.job.name) == "string", "job.name should be a string")
    harness.assertTrue(type(snapshot.job.label) == "string", "job.label should be a string")
    harness.assertTrue(type(snapshot.job.grade) == "number", "job.grade should be a number")
    harness.assertTrue(type(snapshot.job.gradeLabel) == "string", "job.gradeLabel should be a string")
    harness.assertTrue(type(snapshot.job.onDuty) == "boolean", "job.onDuty should be a boolean")
    harness.assertEqual(snapshot.gang, nil, "the stub ships with no gang by default")
    harness.assertTrue(type(snapshot.cash) == "number", "cash should be a number")
    harness.assertTrue(type(snapshot.bank) == "number", "bank should be a number")
    harness.assertTrue(type(snapshot.hunger) == "number", "hunger should be a number")
    harness.assertTrue(type(snapshot.thirst) == "number", "thirst should be a number")
    harness.assertTrue(type(snapshot.stress) == "number", "stress should be a number")
    harness.assertTrue(type(snapshot.seatbelt) == "boolean", "seatbelt should be a boolean")
end)

harness.test("hudtest_cash/_bank/_stress commands update the next snapshot", function()
    commands["hudtest_cash"](1, { "1234" })
    commands["hudtest_bank"](1, { "9999" })
    commands["hudtest_stress"](1, { "50" })

    local snapshot = HudBridge.getSnapshot()
    harness.assertEqual(snapshot.cash, 1234, "hudtest_cash should set cash")
    harness.assertEqual(snapshot.bank, 9999, "hudtest_bank should set bank")
    harness.assertEqual(snapshot.stress, 50, "hudtest_stress should set stress")
end)

harness.test("hudtest_stress clamps to the 0-100 range", function()
    commands["hudtest_stress"](1, { "500" })
    harness.assertEqual(HudBridge.getSnapshot().stress, 100, "stress should clamp to 100")

    commands["hudtest_stress"](1, { "-20" })
    harness.assertEqual(HudBridge.getSnapshot().stress, 0, "stress should clamp to 0")
end)

harness.test("hud_toggleseatbelt flips the seatbelt placeholder", function()
    local before = HudBridge.getSnapshot().seatbelt
    commands["hud_toggleseatbelt"]()
    harness.assertEqual(HudBridge.getSnapshot().seatbelt, not before, "seatbelt should flip")
    harness.assertEqual(HudBridge.getSeatbelt(), not before, "the cheap vehicle accessor should stay in sync")
end)

harness.report("bridge")
