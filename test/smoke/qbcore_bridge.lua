local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function loadBridge(initialState, initialData, initialMode, sessionStarted)
    local handlers, threads, registeredEvents = {}, {}, {}
    -- One entry per root client/bridge/qbcore.lua subscribes to via kora_core's
    -- delta stream, so a test can fire several of them in one frame the way a
    -- server-side resync does.
    local dataChangeHandlers = {}
    local snapshotBuilds = 0
    -- Defaults to an already-live session: every test but the deferred-
    -- registration ones below is about what happens once the bag handlers are
    -- actually armed.
    local sessionLive = sessionStarted ~= false
    local playerData = initialData
    local resyncCalls = 0
    -- Default getPlayerData behaviour just returns the mutable `playerData`
    -- local (see setPlayerData below). Tests that need to exercise the
    -- retry-round / pcall paths swap this out via setPlayerDataImpl instead.
    local getPlayerDataImpl = function() return playerData end

    _G.HudBridge = nil
    _G.LocalPlayer = { state = { ['qbcore:loggedIn'] = initialState == true, ['qbmultichar:mode'] = initialMode } }
    _G.PlayerId = function() return 3 end
    -- The real native returns -1 until the session is live, which is the whole
    -- reason the bridge defers its state bag registration.
    _G.GetPlayerServerId = function() return sessionLive and 17 or -1 end
    _G.NetworkIsSessionStarted = function() return sessionLive end
    _G.Kora = {
        cache = { serverId = function() return sessionLive and 17 or -1 end },
        keybind = { add = function() return { remove = function() return true end } end },
    }
    _G.RegisterCommand = function() end
    _G.RegisterKeyMapping = function() end
    _G.RegisterNetEvent = function(name, fn) registeredEvents[name] = fn or true end
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
        kora_core = {
            getPlayerData = function(...) snapshotBuilds = snapshotBuilds + 1; return getPlayerDataImpl(...) end,
            -- Colon-called by the adapter (`exports.kora_core:onPlayerDataChange`),
            -- so the receiver arrives as the first argument ahead of the
            -- (paths, callback) pair.
            onPlayerDataChange = function(_, _paths, callback) dataChangeHandlers[#dataChangeHandlers + 1] = callback end,
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
        -- N calls before succeeding (simulating kora_core mid-restart).
        setPlayerDataImpl = function(fn) getPlayerDataImpl = fn end,
        resyncCalls = function() return resyncCalls end,
        snapshotBuilds = function() return snapshotBuilds end,
        -- Fires every root subscription in one frame, as a full resync does.
        fireAllDataChanges = function()
            for _, callback in ipairs(dataChangeHandlers) do callback({ 'money' }, nil) end
            return #dataChangeHandlers
        end,
        setCash = function(value)
            for _, handler in ipairs(handlers) do
                if handler.key == 'qbcore:money:cash' then
                    handler.callback('player:17', 'qbcore:money:cash', value, nil, true)
                end
            end
            LocalPlayer.state['qbcore:money:cash'] = value
        end,
        startSession = function() sessionLive = true end,
        -- REAL CFX ORDERING: a state bag change handler fires BEFORE the new
        -- value is committed to the local store -- LocalPlayer.state still
        -- returns the OLD value inside the handler. These setters fire first
        -- and commit after, so a bridge that reads the store synchronously
        -- from a handler decides on stale state and fails here, exactly as it
        -- did live ("HUD never shows" #2). Do not "fix" the order.
        setLoginState = function(value)
            for _, handler in ipairs(handlers) do
                if handler.key == 'qbcore:loggedIn' then
                    handler.callback('player:17', 'qbcore:loggedIn', value, nil, true)
                end
            end
            LocalPlayer.state['qbcore:loggedIn'] = value
        end,
        setCinematicMode = function(value)
            for _, handler in ipairs(handlers) do
                if handler.key == 'qbmultichar:mode' then
                    handler.callback('player:17', 'qbmultichar:mode', value, nil, true)
                end
            end
            LocalPlayer.state['qbmultichar:mode'] = value
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
    bridge.step() -- the release reconcile waits a frame for the bag commit
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'clearing the server-owned mode restores the HUD')

    bridge.setCinematicMode('creator')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'the scene studio hides the HUD too, and instantly')
end)

-- kora_multichar publishes its cleared mode as `false` rather than deleting the
-- key: a state bag DELETION does not replicate to the owning client, so a nil
-- clear never reaches this bridge and the HUD stays hidden for the rest of the
-- session. Both spellings of "cleared" must release the gate -- `false` from a
-- current kora_multichar, nil on a server that never ran one.
harness.test('an explicitly cleared cinematic mode (false, not a nil deletion) releases the HUD', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} }, 'spawn')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'the spawn carousel hides the HUD')

    bridge.setCinematicMode(false)
    bridge.step()
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'a false cinematic mode means cleanup finished')
end)

-- The exact live login sequence, with the harness's fire-before-commit
-- ordering: kora_core flips the login bag true while kora_multichar's mode is still
-- truthy, and the LAST transition of the whole sequence is the mode clearing.
-- A reconcile that reads the store synchronously from that final handler sees
-- the stale mode, decides "still cinematic", and nothing ever fires again --
-- the HUD is hidden for the rest of the session while every bag reads correct.
harness.test('the full login sequence (login during spawn mode, then the mode clear) opens the gate', function()
    local bridge = loadBridge(false, { money = {}, metadata = {} }, 'selection')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'hidden at character select')

    bridge.setLoginState(true)
    bridge.step()
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'login during a cinematic mode stays hidden')

    bridge.setCinematicMode('spawn')
    bridge.step()
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'hidden through the spawn carousel')

    bridge.setCinematicMode(false)
    bridge.step()
    harness.assertTrue(bridge.bridge.isLoggedIn(),
        'the final mode clear must open the gate despite firing before the bag commit')
end)

harness.test('a false cinematic mode present at chunk load does not gate the reconcile', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} }, false)
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'a cleared mode already in the bag must not hide the HUD on restart')
end)

-- Client scripts load during the join/loading screen, BEFORE the session is
-- live -- GetPlayerServerId(PlayerId()) is -1 there. A state bag handler binds
-- to the bag name it is given at registration time, so registering at chunk
-- load subscribes to 'player:-1' forever: no login, cinematic-mode or cash
-- change ever reaches the bridge and the HUD stays hidden for the entire
-- session. kora_multichar/client.lua defers its own login handler for this reason.
harness.test('state bag handlers are not registered against the pre-session -1 server id', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} }, nil, false)
    harness.assertEqual(#bridge.handlers, 0, 'nothing may be registered before the session is live')
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'the HUD stays hidden while the session is still starting')

    bridge.startSession()
    bridge.step()

    harness.assertEqual(#bridge.handlers, 3, 'login, cinematic mode and cash handlers arm once the session is live')
    for _, handler in ipairs(bridge.handlers) do
        harness.assertEqual(handler.bagName, 'player:17', 'every handler must bind the real local player bag')
    end
end)

harness.test('a login that lands only after the session starts still shows the HUD', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} }, nil, false)
    harness.assertFalse(bridge.bridge.isLoggedIn(), 'hidden while the session is still starting')

    bridge.startSession()
    bridge.step() -- arms the handlers and runs the catch-up reconcile
    bridge.step() -- lets the reconcile thread observe the populated mirror

    harness.assertTrue(bridge.bridge.isLoggedIn(), 'the deferred reconcile must still open the HUD gate')
end)

harness.test('a qbhud restart reconciles an already-present local login state', function()
    local bridge = loadBridge(true, { money = {}, metadata = {} })
    harness.assertTrue(bridge.bridge.isLoggedIn(), 'an already logged-in LocalPlayer should restore the HUD bridge')
end)

harness.test('a missing optional kora_lib status export cannot stop the core HUD bridge', function()
    _G.Kora = nil
    local bridge = loadBridge(false, { money = {}, metadata = {} })
    local snapshot = bridge.bridge.getSnapshot()
    harness.assertEqual(type(snapshot.status), 'table', 'status should degrade to an empty array')
    harness.assertEqual(#snapshot.status, 0, 'a missing status provider must not block HUD startup')
end)

harness.test('a reconcile that times out its first 200-frame round retries via requestResync instead of giving up', function()
    local bridge = loadBridge(false, nil)
    local calls = 0
    -- Returns nil for the first 210 calls (past the 200-frame cap of a single
    -- round), then starts returning real data -- simulating kora_core itself
    -- still being mid-restart when kora_hud's reconcile thread starts.
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
    -- would if kora_core's resource wasn't fully started yet), then succeeds.
    bridge.setPlayerDataImpl(function()
        calls = calls + 1
        if calls == 1 then error('qbcore export not ready') end
        return { money = { cash = 7 }, metadata = {} }
    end)

    bridge.setLoginState(true)
    bridge.step() -- runs the frame-deferred reconcile; its first read errors
    bridge.step() -- the retry succeeds

    harness.assertTrue(bridge.bridge.isLoggedIn(), 'an error on one export call must be swallowed and retried, not kill the thread')
end)

harness.test('a burst of delta roots costs one snapshot rebuild, not one per root', function()
    -- kora_core fires money/job/gang/metadata separately, and a resync touches all
    -- four at once. Each rebuild is a getPlayerData export call plus a
    -- Kora.status.getActive one, so re-snapshotting per root turns one logical
    -- update into four boundary crossings and four HUD pushes.
    local bridge = loadBridge(true, { money = { cash = 10 }, metadata = {} })
    local pushes = 0
    bridge.bridge.onChange(function() pushes = pushes + 1 end)
    bridge.step()

    local roots = bridge.fireAllDataChanges()
    harness.assertEqual(roots, 4, 'sanity: money/job/gang/metadata are all subscribed')

    -- Measured as deltas: onChange itself pushes once on registration so the
    -- HUD reflects current state without waiting for a first change.
    local buildsBefore, pushesBefore = bridge.snapshotBuilds(), pushes
    bridge.step()

    harness.assertEqual(bridge.snapshotBuilds() - buildsBefore, 1,
        'four roots changing in one frame must rebuild the snapshot once')
    harness.assertEqual(pushes - pushesBefore, 1, 'and push once')
end)

harness.test('an authoritative cash change still reaches the HUD, one frame later', function()
    -- The deferred frame is load-bearing: CFX fires a bag handler before the
    -- new value is committed, and snapshotFrom reads the cash key back out of
    -- the store.
    local bridge = loadBridge(true, { money = { cash = 10 }, metadata = {} })
    local latest
    bridge.bridge.onChange(function(snapshot) latest = snapshot end)
    bridge.step()

    bridge.setCash(250)
    bridge.step()

    harness.assertTrue(latest ~= nil, 'the cash bag handler must push a snapshot')
    harness.assertEqual(latest.cash, 250, 'and it must carry the COMMITTED balance, not the pre-change one')
end)

harness.test('seatbelt presentation follows the gameplay owner rather than a HUD-only toggle', function()
    local fixture = loadBridge(true, {citizenid='TEST'})
    harness.assertFalse(fixture.bridge.getSeatbelt())
    fixture.events['seatbelt:client:ToggleSeatbelt'](true)
    harness.assertTrue(fixture.bridge.getSeatbelt())
    fixture.events['seatbelt:client:ToggleSeatbelt'](false)
    harness.assertFalse(fixture.bridge.getSeatbelt())
end)

harness.test('harness icon state follows the kora_utils attached flag, not the use count', function()
    local fixture = loadBridge(true, {citizenid='TEST'})
    harness.assertFalse(fixture.bridge.getHarness())
    fixture.events['seatbelt:client:ToggleHarness'](true, 0)
    harness.assertTrue(fixture.bridge.getHarness(), 'a spent last-use harness is still attached')
    harness.assertFalse(fixture.bridge.getSeatbelt(), 'the harness never implies the belt')
    fixture.events['seatbelt:client:ToggleHarness'](false, 0)
    harness.assertFalse(fixture.bridge.getHarness())
end)

harness.report('qbcore_bridge')
