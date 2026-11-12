-- client/compat.lua: qb-hud display-only events and the cash/bank commands.
local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)") or "./"
local testDir = scriptDir .. "../"
local repoRoot = testDir .. "../"
package.path = testDir .. "?.lua;" .. package.path

local harness = require("harness")
local mocks = require("mocks")

local net = mocks.install()
local commands, serverEvents = {}, {}
_G.RegisterCommand = function(name, fn) commands[name] = fn end
local realTrigger = _G.TriggerServerEvent
_G.TriggerServerEvent = function(name, ...) serverEvents[#serverEvents + 1] = name; return realTrigger(name, ...) end

dofile(repoRoot .. "client/compat.lua")

local snapshot, pushes, notified, minimap = { cash = 120.4, bank = 5000, hunger = 90, thirst = 80, stress = 5 }, 0, {}, 0
HudCompat.attach({
    overlay = function(fields) for k, v in pairs(fields) do snapshot[k] = v end end,
    snapshot = function() return snapshot end,
    push = function() pushes = pushes + 1 end,
    applyMinimap = function() minimap = minimap + 1 end,
})
HudCompat.notify = function(label, amount) notified[#notified + 1] = label .. ":" .. amount end

harness.test("UpdateNeeds and UpdateStress overlay clamped values", function()
    TriggerEvent("hud:client:UpdateNeeds", 150, 40)
    harness.assertEqual(snapshot.hunger, 100)
    harness.assertEqual(snapshot.thirst, 40)
    TriggerEvent("hud:client:UpdateStress", 33)
    harness.assertEqual(snapshot.stress, 33)
end)

harness.test("junk arguments are ignored", function()
    TriggerEvent("hud:client:UpdateStress", "abc")
    TriggerEvent("hud:client:UpdateStress", nil)
    TriggerEvent("hud:client:UpdateNeeds", {}, nil)
    harness.assertEqual(snapshot.stress, 33)
    harness.assertEqual(snapshot.hunger, 100)
end)

harness.test("nitrous and harness update presentation state", function()
    TriggerEvent("hud:client:UpdateNitrous", 55, true)
    harness.assertEqual(HudCompat.state.nitrous.level, 55)
    harness.assertTrue(HudCompat.state.nitrous.active)
    TriggerEvent("hud:client:UpdateHarness", 12)
    harness.assertEqual(HudCompat.state.harness, 12)
    TriggerEvent("hud:client:UpdateHarness", false)
    harness.assertEqual(HudCompat.state.harness, nil)
    harness.assertTrue(pushes >= 3)
end)

harness.test("toggle events flip their flag", function()
    TriggerEvent("hud:client:ToggleHealth")
    TriggerEvent("hud:client:ToggleAirHud")
    TriggerEvent("hud:client:ToggleShowSeatbelt")
    TriggerEvent("seatbelt:client:ToggleCruise")
    harness.assertTrue(HudCompat.state.dynamicHealth)
    harness.assertTrue(HudCompat.state.altitude)
    harness.assertFalse(HudCompat.state.showSeatbelt)
    harness.assertTrue(HudCompat.state.cruise)
end)

harness.test("LoadMap re-applies the minimap layout", function()
    TriggerEvent("hud:client:LoadMap")
    harness.assertEqual(minimap, 1)
end)

harness.test("ShowAccounts and commands show the snapshot balance, not the argument", function()
    TriggerEvent("hud:client:ShowAccounts", "cash", 999999)
    harness.assertEqual(notified[1], "Cash:120")
    commands.bank()
    harness.assertEqual(notified[2], "Bank:5000")
    TriggerEvent("hud:client:ShowAccounts", "crypto", 1)
    harness.assertEqual(#notified, 2)
end)

harness.test("nothing in the listeners writes server state", function()
    harness.assertEqual(#serverEvents, 0)
end)

harness.report("compat")
