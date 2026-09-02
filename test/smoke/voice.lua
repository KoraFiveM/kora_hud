local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local calls, threads = 0, {}
local playerIdReads = 0
_G.Config = { voice = { enabled = true, interval = 200 } }
-- The local player index is a session constant; voice.lua resolves it once
-- from the native rather than paying for a QB.cache export call every sample.
_G.PlayerId = function()
    playerIdReads = playerIdReads + 1
    return 3
end
_G.QB = { cache = { playerId = function() error('voice.lua must not cross the export boundary to read PlayerId()', 0) end } }
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

harness.test('the player index is resolved once, not on every sample', function()
    local before = playerIdReads
    Voice.setActive(true)
    for _ = 1, 5 do assert(coroutine.resume(threads[#threads])) end
    Voice.setActive(false)

    harness.assertEqual(playerIdReads, before, 'a session constant must not be re-read per sample')
end)

harness.report('voice')
