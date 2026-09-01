local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function loadBridge(initialState, initialData, initialMode)
    local handlers, threads, registeredEvents = {}, {}, {}
    local playerData = initialData
    local resyncCalls = 0
    -- Default getPlayerData behaviour just returns the mutable `playerData`
    -- local (see setPlayerData below). Tests that need to exercise the
    -- retry-round / pcall paths swap this out via setPlayerDataImpl instead.
    local getPlayerDataImpl = function() return playerData end

    _G.HudBridge = nil
    _G.LocalPlayer = { state = { ['qbcore:loggedIn'] = initialState == true, ['qbmultichar:mode'] = initialMode } }
    _G.PlayerId = function() return 3 end
    _G.GetPlayerServerId = function() return 17 end
    _G.QB = {
        cache = { serverId = function() return 17 end },
        keybind = { add = function() return { remove = function() return true end } end },
    }
    _G.RegisterCommand = function() end
    _G.RegisterKeyMapping = function() end
    _G.RegisterNetEvent = function(name) registeredEvents[name] = true end
    _G.AddStateBagChangeHandler = function(key, bagName, callback)
        handlers[#handlers + 1] = { key = key, bagName = bagName, callback = callback }
        return #handlers
    end
    _G.CreateThread = function(callback)
        local thread = coroutine.create(callback)
        threads[#threads + 1] = thread
        assert(coroutine.resume(thread))
    end
    _G.Wait = function() coroutine.yield() end
    _G.exports = {
        qbcore = {
            getPlayerData = function(...) return getPlayerDataImpl(...) end,
            onPlayerDataChange = function() end,
            requestResync = function() resyncCalls = resyncCalls + 1 end,
        },
    }

    dofile(repoRoot .. 'client/bridge/qbcore.lua')

    return {
        bridge = HudBridge,
        handlers = handlers,
        events = registeredEvents,
        setPlayerData = function(value) playerData = value end,
        -- Lets a test fully replace getPlayerData's behaviour, e.g. to return
        -- nil for longer than one 200-frame round, or to raise for the first
        -- N calls before succeeding (simulating qbcore mid-restart).
        setPlayerDataImpl = function(fn) getPlayerDataImpl = fn end,
        resyncCalls = function() return resyncCalls end,
        setLoginState = function(value)
            LocalPlayer.state['qbcore:loggedIn'] = value
            for _, handler in ipairs(handlers) do
                if handler.key == 'qbcore:loggedIn' then
                    handler.callback('player:17', 'qbcore:loggedIn', value, nil, true)
                end
            end
        end,
        setCinematicMode = function(value)
            LocalPlayer.state['qbmultichar:mode'] = value
            for _, handler in ipairs(handlers) do
                if handler.key == 'qbmultichar:mode' then
                    handler.callback('player:17', 'qbmultichar:mode', value, nil, true)
                end
            end
        end,
        step = function()
            for _, thread in ipairs(threads) do
                if coroutine.status(thread) == 'suspended' then assert(coroutine.resume(thread)) end
            end
        end,
    }
end

harness.test('the bridge gates HUD login on the local replicated state bag and PlayerData snapshot', function()
    local bridge = loadBridge(false, nil)
    local transitions = {}
    bridge.bridge.onLoginChange(function(value) transitions[#transitions + 1] = value end)

    harness.assertFalse(bridge.bridge.isLoggedIn(), 'HUD should start hidden before character login')
    harness.assertEqual(#bridge.handlers, 3, 'the bridge should register login, cinematic mode, and authoritative cash handlers')
    harness.assertEqual(bridge.handlers[1].key, 'qbcore:loggedIn', 'handler should watch qbcore login state')
    harness.assertEqual(bridge.handlers[1].bagName, 'player:17', 'handler should be scoped to LocalPlayer state')

    bridge.setLoginState(true)
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'a true state bag waits for the PlayerData snapshot')
    bridge.setPlayerData({ money = { cash = 10 }, metadata = {} })
    bridge.step()
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'HUD becomes visible only after the mirror is populated')
    harness.assertEqual(transitions[1], true, 'login change should be emitted after the snapshot')

    bridge.setLoginState(false)
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'logout hides immediately from the state bag')
    harness.assertEqual(transitions[2], false, 'logout change should be emitted immediately')
    harness.assertFalse(bridge.events['QBCore:Client:OnPlayerLoaded'], 'qbhud must not register the legacy loaded event')
    harness.assertFalse(bridge.events['QBCore:Client:OnPlayerUnload'], 'qbhud must not register the legacy unload event')
end)

harness.test('the cinematic mode state keeps the HUD hidden until spawn cleanup completes', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} }, 'spawn')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'logged-in characters remain hidden during spawn selection')

    bridge.setCinematicMode(nil)
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'clearing the server-owned mode restores the HUD')

    bridge.setCinematicMode('creator')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'the scene studio hides the HUD too')
end)

harness.test('a qbhud restart reconciles an already-present local login state', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} })
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'an already logged-in LocalPlayer should restore the HUD bridge')
end)

harness.test('a missing optional qblib status export cannot stop the core HUD bridge', function()
    _G.QB = nil
    local bridge = loadBridge(false, { money = {}, metadata = {} })
    local snapshot = bridge.bridge.getSnapshot()
    harness.assertEqual(type(snapshot.status), 'table', 'status should degrade to an empty array')
    harness.assertEqual(#snapshot.status, 0, 'a missing status provider must not block HUD startup')
end)

harness.test('a reconcile that times out its first 200-frame round retries via requestResync instead of giving up', function()
    local bridge = loadBridge(false, nil)
    local calls = 0
    -- Returns nil for the first 210 calls (past the 200-frame cap of a single
    -- round), then starts returning real data -- simulating qbcore itself
    -- still being mid-restart when qbhud's reconcile thread starts.
    bridge.setPlayerDataImpl(function()
        calls = calls + 1
        if calls <= 210 then return nil end
        return { money = { cash = 5 }, metadata = {} }
    end)

    bridge.setLoginState(true)
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'still waiting on the mirror right after the state bag flips')

    -- Drive well past a single 200-frame round (and comfortably within the
    -- 3-round cap) so the retry path has to kick in.
    for _ = 1, 500 do
        bridge.step()
        if bridge.bridge.isLoggedIn() then break end
    end

    harness.assertTrue(bridge.bridge.isLoggedIn(), 'a timed-out first round must retry rather than leave loggedIn stuck false')
    harness.assertTrue(bridge.resyncCalls() > 0, 'a timed-out round should nudge qbcore via requestResync before retrying')
end)

harness.test('a pcall-guarded getPlayerData error does not kill the reconcile thread', function()
    local bridge = loadBridge(false, nil)
    local calls = 0
    -- Errors on the very first call (as a raw cross-resource export call
    -- would if qbcore's resource wasn't fully started yet), then succeeds.
    bridge.setPlayerDataImpl(function()
        calls = calls + 1
        if calls == 1 then error('qbcore export not ready') end
        return { money = { cash = 7 }, metadata = {} }
    end)

    bridge.setLoginState(true)
    bridge.step()

    harness.assertTrue(bridge.bridge.isLoggedIn(), 'an error on one export call must be swallowed and retried, not kill the thread')
end)

harness.report('qbcore_bridge')
