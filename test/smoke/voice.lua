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
-- Recorded, not implemented: any CreateThread at all is the regression this
-- file exists to catch. Mic sampling runs on client/hud.lua's single shared
-- scheduler thread -- FiveM walks every live coroutine each frame, so a second
-- loop here would be a permanent per-frame cost for one boolean.
_G.CreateThread = function(fn)
    threads[#threads + 1] = fn
end
_G.Wait = function() coroutine.yield() end
_G.Voice = nil

dofile(repoRoot .. 'client/voice.lua')

harness.test('voice.lua owns no thread at all', function()
    harness.assertEqual(#threads, 0, 'voice.lua must not create a thread at load')
    Voice.setActive(true)
    harness.assertEqual(#threads, 0, 'activating must not create a sampler thread either')
    harness.assertEqual(calls, 0, 'activation alone must not call the voice native')
end)

harness.test('sampling is inert until the HUD activates it, and again once it stops', function()
    Voice.setActive(false)
    harness.assertFalse(Voice.isActive(), 'the HUD gates sampling through setActive')

    Voice.sample()
    harness.assertEqual(calls, 0, 'a sample while inactive must not reach the native')

    Voice.setActive(true)
    harness.assertTrue(Voice.isActive(), 'the scheduler drives its voice task off this')
    Voice.sample()
    harness.assertEqual(calls, 1, 'an active sample reads the native exactly once')
end)

harness.test('the player index is resolved once, not on every sample', function()
    local before = playerIdReads
    for _ = 1, 5 do Voice.sample() end

    harness.assertEqual(calls, 6, 'sanity: every sample reached the native')
    harness.assertEqual(playerIdReads, before, 'a session constant must not be re-read per sample')
end)

harness.test('deactivating clears the talking state so the icon cannot stick on', function()
    local seen = {}
    Voice.onChange(function(value) seen[#seen + 1] = value end)

    _G.NetworkIsPlayerTalking = function() calls = calls + 1; return true end
    Voice.sample()
    harness.assertTrue(Voice.isTalking(), 'a talking sample flips the state')
    harness.assertEqual(seen[1], true, 'and notifies listeners')

    Voice.setActive(false)
    harness.assertFalse(Voice.isTalking(), 'deactivating must not leave the mic indicator lit')
    harness.assertEqual(seen[2], false, 'listeners see the clear too')
end)

harness.report('voice')
