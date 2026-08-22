local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function loadBridge(initialState, initialData)
    local handlers, threads, registeredEvents = {}, {}, {}
    local playerData = initialData

    _G.HudBridge = nil
    _G.LocalPlayer = { state = { ['qbcore:loggedIn'] = initialState == true } }
    _G.PlayerId = function() return 3 end
    _G.GetPlayerServerId = function() return 17 end
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
            getPlayerData = function() return playerData end,
            onPlayerDataChange = function() end,
        },
    }

    dofile(repoRoot .. 'client/bridge/qbcore.lua')

    return {
        bridge = HudBridge,
        handlers = handlers,
        events = registeredEvents,
        setPlayerData = function(value) playerData = value end,
        setLoginState = function(value)
            LocalPlayer.state['qbcore:loggedIn'] = value
            for _, handler in ipairs(handlers) do
                handler.callback('player:17', 'qbcore:loggedIn', value, nil, true)
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
    harness.assertEqual(#bridge.handlers, 1, 'the bridge should register one state-bag change handler')
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

harness.test('a qbhud restart reconciles an already-present local login state', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} })
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'an already logged-in LocalPlayer should restore the HUD bridge')
end)

harness.report('qbcore_bridge')
