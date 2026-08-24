local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local calls, threads = 0, {}
_G.Config = { voice = { enabled = true } }
_G.QB = { cache = { playerId = function() return 3 end } }
_G.NetworkIsPlayerTalking = function()
    calls = calls + 1
    return false
end
_G.CreateThread = function(fn)
    local thread = coroutine.create(fn)
    threads[#threads + 1] = thread
    assert(coroutine.resume(thread))
end
_G.Wait = function() coroutine.yield() end
_G.Voice = nil

dofile(repoRoot .. 'client/voice.lua')

harness.test('voice sampling is dormant until the HUD activates it', function()
    harness.assertEqual(#threads, 0, 'voice.lua must not create an always-running sampler at load')
    harness.assertEqual(calls, 0, 'voice.lua must not call the voice native while inactive')
end)

harness.test('voice sampling starts once and stops immediately when inactive', function()
    Voice.setActive(true)
    harness.assertEqual(#threads, 1, 'activating voice should create one sampler')
    harness.assertEqual(calls, 1, 'activation should sample immediately')

    Voice.setActive(true)
    harness.assertEqual(#threads, 1, 're-activation must not create a duplicate sampler')

    Voice.setActive(false)
    assert(coroutine.resume(threads[1]))
    harness.assertEqual(calls, 1, 'a stopped sampler must not make another native call')
end)

harness.report('voice')
