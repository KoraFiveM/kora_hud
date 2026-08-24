local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local vehicle = nil
local speedCalls, fuelCalls, engineCalls, lightsCalls = 0, 0, 0, 0

_G.QB = { cache = { vehicle = function() return vehicle end } }
_G.GetEntitySpeed = function() speedCalls = speedCalls + 1; return 10 end
_G.GetVehicleFuelLevel = function() fuelCalls = fuelCalls + 1; return 55 end
_G.IsVehicleEngineRunning = function() engineCalls = engineCalls + 1; return true end
_G.GetVehicleLightsState = function() lightsCalls = lightsCalls + 1; return true, true, false end

dofile(repoRoot .. 'client/vehicle.lua')

harness.test('vehicle telemetry is completely dormant while the cache reports on foot', function()
    vehicle = nil
    local snapshot = Vehicle.getSnapshot()
    harness.assertTrue(snapshot == nil, 'on-foot state should have no vehicle snapshot')
    harness.assertEqual(speedCalls, 0, 'on-foot state must not read speed')
    harness.assertEqual(fuelCalls, 0, 'on-foot state must not read fuel')
    harness.assertEqual(engineCalls, 0, 'on-foot state must not read engine state')
    harness.assertEqual(lightsCalls, 0, 'on-foot state must not read headlight state')
end)

harness.test('vehicle telemetry reads the cache-selected vehicle only when requested by the HUD', function()
    vehicle = 42
    local snapshot = Vehicle.getSnapshot()
    harness.assertEqual(snapshot.speed, 36, 'speed should be converted from m/s to km/h')
    harness.assertEqual(snapshot.fuel, 55, 'fuel should be passed through')
    harness.assertTrue(snapshot.engineOn, 'engine state should be passed through')
    harness.assertEqual(snapshot.headlights, 'low', 'headlight state should be normalized for the NUI')
    harness.assertEqual(speedCalls, 1, 'one HUD request should read speed once')
    harness.assertEqual(lightsCalls, 1, 'one HUD request should read headlights once')
end)

harness.report('vehicle')
