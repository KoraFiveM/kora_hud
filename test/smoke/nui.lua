-- Guards the NUI transport contract in client/hud.lua.
--
-- qbhud owns its own ui_page, so its NUI I/O MUST use the raw natives. Going
-- through QB.nui.* routes the call into qblib's Lua VM (every QB.* access is a
-- cross-resource export call), which posts messages into qblib's frame and
-- publishes callbacks at https://qblib/<name> while this resource's page
-- fetches https://qbhud/<name> -- a permanent 404 that leaves the HUD stuck on
-- DEFAULT_VISIBLE=false. That regression is invisible in-game until someone
-- restarts the resource, so it is pinned here instead.

local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

-- Any QB.nui.<anything> access explodes with an explanatory message, so a
-- reintroduced QB.nui.send/registerCallback fails this suite loudly rather
-- than silently shipping a dead HUD.
local FORBIDDEN_NUI = setmetatable({}, {
    __index = function(_, key)
        error(("QB.nui.%s would run in qblib's VM and target qblib's frame, not qbhud's -- "
            .. 'use the raw SendNUIMessage/RegisterNUICallback natives'):format(tostring(key)), 2)
    end,
})

---@param opts table|nil  -- { snapshotError, bridgePush, inVehicle }
local function loadHud(opts)
    opts = opts or {}
    local sent, callbacks, threads = {}, {}, {}
    local cacheHandlers, bridgeHandlers = {}, {}
    local snapshots, vehicle = 0, opts.inVehicle and 42 or nil
    local seatbelt = false

    _G.SendNUIMessage = function(message) sent[#sent + 1] = message end
    _G.RegisterNUICallback = function(name, handler) callbacks[name] = handler end
    _G.GetEntityMaxHealth = function() return opts.maxHealth or 200 end
    _G.GetPlayerStamina = function() return 100 end
    _G.CreateThread = function(callback)
        local thread = coroutine.create(callback)
        threads[#threads + 1] = thread
        -- Runs to the first Wait(); a sampling thread suspends there.
        assert(coroutine.resume(thread))
    end
    _G.Wait = function() coroutine.yield() end

    _G.Config = {
        hud = { elements = { mic = true, cash = true, vehicle = true } },
        poll = { bridgeInterval = 500, vehicleInterval = 100 },
    }

    _G.HudBridge = {
        isLoggedIn = function() return true end,
        onLoginChange = function() end,
        getSnapshot = function()
            if opts.snapshotError then error('qbcore export not resolvable', 0) end
            snapshots = snapshots + 1
            return { job = {}, gang = nil, cash = 0, bank = 0, hunger = 100, thirst = 100, stress = 0,
                     seatbelt = seatbelt, status = {} }
        end,
    }
    -- Only the adapters that can push implement this (the stub does not).
    if opts.bridgePush then
        _G.HudBridge.onChange = function(handler) bridgeHandlers[#bridgeHandlers + 1] = handler end
    end

    _G.Vehicle = {
        getSnapshot = function()
            if not vehicle then return nil end
            return { speed = 60, fuel = 50, engineOn = true }
        end,
    }
    _G.Voice = { isTalking = function() return false end, onChange = function() end, setActive = function() end }

    _G.QB = {
        nui = FORBIDDEN_NUI,
        cache = {
            onChange = function(key, handler)
                cacheHandlers[key] = cacheHandlers[key] or {}
                table.insert(cacheHandlers[key], handler)
            end,
            health = function() return 200 end,
            ped = function() return 42 end,
            armour = function() return 0 end,
            stamina = function() return 100 end,
            vehicle = function() return vehicle end,
            playerId = function() return 3 end,
        },
        theme = { tokens = function() return { bg = '0 0% 0%' } end },
        status = { onChange = function() end, getActive = function() return {} end },
    }

    local ok, err = pcall(dofile, repoRoot .. 'client/hud.lua')

    local function actions()
        local names = {}
        for _, message in ipairs(sent) do names[#names + 1] = message.action end
        return names
    end

    local function contains(action)
        for _, message in ipairs(sent) do
            if message.action == action then return true end
        end
        return false
    end

    local function countAction(action)
        local n = 0
        for _, message in ipairs(sent) do
            if message.action == action then n = n + 1 end
        end
        return n
    end

    return {
        loaded = ok, loadError = err,
        sent = sent, actions = actions, contains = contains, countAction = countAction,
        callbacks = callbacks,
        snapshots = function() return snapshots end,
        threadCount = function() return #threads end,
        reset = function() for i = #sent, 1, -1 do sent[i] = nil end end,
        -- Drives every suspended sampling thread one more iteration.
        tick = function()
            for _, thread in ipairs(threads) do
                if coroutine.status(thread) == 'suspended' then assert(coroutine.resume(thread)) end
            end
        end,
        setVehicle = function(value)
            vehicle = value
            for _, handler in ipairs(cacheHandlers.vehicle or {}) do handler(value) end
        end,
        setSeatbelt = function(value) seatbelt = value end,
        pushBridge = function(snapshot)
            for _, handler in ipairs(bridgeHandlers) do handler(snapshot) end
        end,
        cacheKeys = function()
            local keys = {}
            for key in pairs(cacheHandlers) do keys[#keys + 1] = key end
            table.sort(keys)
            return keys
        end,
    }
end

harness.test('qbhud registers qbhud:ready on the raw native, not through the qblib proxy', function()
    local hud = loadHud()
    harness.assertTrue(hud.loaded, 'client/hud.lua should load cleanly: ' .. tostring(hud.loadError))
    harness.assertEqual(type(hud.callbacks['qbhud:ready']), 'function',
        'qbhud:ready must be registered via the raw RegisterNUICallback so it resolves at https://qbhud/')
end)

harness.test('qbhud never routes NUI through QB.nui (which targets qblib\'s frame)', function()
    -- FORBIDDEN_NUI raises on any access, so a clean load is itself the proof.
    local hud = loadHud()
    harness.assertTrue(hud.loaded, 'a QB.nui.* call would abort the chunk: ' .. tostring(hud.loadError))
    harness.assertTrue(hud.contains('qbhud:config'), 'initial state should reach the frame via SendNUIMessage')
end)

harness.test('the ready callback is registered even when the bridge throws at load', function()
    -- The callback must be the FIRST statement in the chunk: if it were
    -- registered after HudBridge.getSnapshot(), a mid-restart qbcore would
    -- abort the chunk and the page would 404 forever with nothing to retry it.
    local hud = loadHud({ snapshotError = true })
    harness.assertFalse(hud.loaded, 'this case is meant to abort the chunk partway')
    harness.assertEqual(type(hud.callbacks['qbhud:ready']), 'function',
        'qbhud:ready must be registered before anything that can throw')

    local replies = 0
    hud.callbacks['qbhud:ready']({}, function() replies = replies + 1 end)
    harness.assertEqual(replies, 1,
        'the handler must always answer exactly once, or the page fetch hangs forever')
end)

harness.test('the ready callback is idempotent and re-pushes the full initial state', function()
    local hud = loadHud()
    hud.reset()

    local replies = 0
    local function cb() replies = replies + 1 end

    hud.callbacks['qbhud:ready']({}, cb)
    local first = table.concat(hud.actions(), ',')
    harness.assertTrue(hud.contains('qbhud:config'), 'ready should push the element config')
    harness.assertTrue(hud.contains('qbhud:theme'), 'ready should push the theme tokens')
    harness.assertTrue(hud.contains('qbhud:visibility'), 'ready should push current visibility')

    hud.reset()
    hud.callbacks['qbhud:ready']({}, cb)
    harness.assertEqual(table.concat(hud.actions(), ','), first,
        'a second ping (page remount / nui_reload) must produce the same push')
    harness.assertEqual(replies, 2, 'every ping gets exactly one reply')
end)

harness.test('a failing QB.theme.tokens cannot stop the visibility push', function()
    local hud = loadHud()
    QB.theme.tokens = function() error('qblib restarting', 0) end
    hud.reset()

    hud.callbacks['qbhud:ready']({}, function() end)
    harness.assertFalse(hud.contains('qbhud:theme'), 'a broken theme read should be skipped, not fatal')
    harness.assertTrue(hud.contains('qbhud:visibility'),
        'visibility must still be sent -- it is what makes the HUD render at all')
end)

harness.test('the HUD sends the ped-specific maximum health for percentage conversion', function()
    local hud = loadHud({ maxHealth = 175 })
    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:update' then latest = message.data end
    end

    harness.assertTrue(latest ~= nil, 'initial state should include a HUD update')
    harness.assertEqual(latest.maxHealth, 175,
        'female freemode peds use a 175 maximum rather than the male 200 maximum')
end)

-- --- event-driven updates (no constant polling) ---

harness.test('bridge fields are pushed via HudBridge.onChange, never polled', function()
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    local before = hud.snapshots()
    hud.tick()   -- nothing should be sampling the bridge on a timer
    harness.assertEqual(hud.snapshots(), before,
        'no thread may poll getSnapshot when the adapter can push')
    harness.assertEqual(hud.countAction('qbhud:update'), 0, 'a tick alone must not push an update')

    hud.pushBridge({ job = {}, cash = 999, hunger = 100, thirst = 100, stress = 0,
                     seatbelt = false, status = {} })
    harness.assertEqual(hud.countAction('qbhud:update'), 1, 'a delta from the adapter pushes immediately')
end)

harness.test('an adapter without onChange still gets the documented polling fallback', function()
    -- shared/bridge.lua documents onChange as OPTIONAL; the stub omits it.
    local hud = loadHud({ bridgePush = false })
    hud.reset()

    local before = hud.snapshots()
    hud.tick()
    harness.assertTrue(hud.snapshots() > before, 'the stub adapter must still be polled')
    harness.assertTrue(hud.countAction('qbhud:update') > 0, 'polling should still push updates')
end)

harness.test('no vehicle telemetry thread runs while on foot', function()
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    hud.tick()
    harness.assertEqual(hud.countAction('qbhud:vehicle'), 0,
        'on foot nothing should be sampling or pushing vehicle telemetry')
end)

harness.test('entering a vehicle starts the sampling thread, leaving stops it', function()
    local hud = loadHud({ bridgePush = true })
    harness.assertTrue(hud.contains('qbhud:visibility'), 'sanity: the hud loaded')
    hud.reset()

    hud.setVehicle(42)
    harness.assertTrue(hud.countAction('qbhud:vehicle') > 0, 'entering a vehicle pushes telemetry')

    hud.reset()
    hud.tick()
    harness.assertTrue(hud.countAction('qbhud:vehicle') > 0, 'the thread keeps sampling while driving')

    -- Leaving: the loop condition goes false, so it drains and stops.
    hud.setVehicle(nil)
    hud.tick()
    hud.reset()
    hud.tick()
    harness.assertEqual(hud.countAction('qbhud:vehicle'), 0,
        'the sampling thread must stop once the player is out of the vehicle')
end)

harness.test('seatbelt stays live while driving even though no adapter can push it', function()
    -- Seatbelt is a local keybind the adapter owns, not framework player data,
    -- so HudBridge.onChange never fires for it -- the vehicle tick refreshes it.
    local hud = loadHud({ bridgePush = true, inVehicle = true })
    hud.setSeatbelt(true)
    hud.reset()

    hud.tick()
    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:vehicle' then latest = message.data end
    end
    harness.assertTrue(latest ~= nil, 'the vehicle tick should be running')
    harness.assertTrue(latest.seatbelt, 'a seatbelt toggle must reach the NUI while driving')
end)

harness.test('a player already in a vehicle at resource start gets telemetry', function()
    -- QB.cache.onChange only observes FUTURE transitions, so `ensure qbhud`
    -- mid-drive needs an explicit arm at startup.
    local hud = loadHud({ bridgePush = true, inVehicle = true })
    hud.reset()

    hud.tick()
    harness.assertTrue(hud.countAction('qbhud:vehicle') > 0,
        'restarting mid-drive must not leave the vehicle panel dead until the player gets out')
end)

harness.report('nui')
