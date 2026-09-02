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

---@param opts table|nil  -- { snapshotError, bridgePush, inVehicle, dynamicHud, maxHealth }
local function loadHud(opts)
    opts = opts or {}
    local sent, callbacks, threads = {}, {}, {}
    local cacheHandlers, bridgeHandlers, loginHandlers = {}, {}, {}
    local snapshots, vehicle = 0, opts.inVehicle and 42 or nil
    local seatbelt = false
    local loggedIn = opts.loggedIn ~= false
    local exported = {}
    -- Every ms value any thread has ever passed to Wait, so a reintroduced
    -- per-frame loop is a test failure rather than a resmon surprise.
    local waits = {}
    -- Every QB.cache.<fn>() read, by key. Each one is a cross-resource export
    -- call, so "how many of these happen per update" IS this resource's cost
    -- while the player is moving -- pinned below.
    local cacheReads = { health = 0, armour = 0, stamina = 0, ped = 0, vehicle = 0 }
    -- Vehicle telemetry is deduplicated before it goes on the wire, so a mock
    -- that reports the same reading forever can't tell a live sampler from a
    -- dead one. Move one field per sample, the way a driven car does.
    local vehicleSamples = 0
    local vehicleHandles = {}

    _G.SendNUIMessage = function(message) sent[#sent + 1] = message end
    _G.RegisterNUICallback = function(name, handler) callbacks[name] = handler end
    -- The runtime `exports('name', fn)` registrar (callable, unlike the
    -- `exports.<resource>` consumer side) -- hud.lua registers show/hide here.
    _G.exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end })
    _G.GetEntityMaxHealth = function() return opts.maxHealth or 200 end
    _G.GetPlayerStamina = function() return 100 end

    -- client/hud.lua requests the minimap scaleform at load time (to suppress
    -- the engine's own health/armour cluster via SETUP_HEALTH_ARMOUR) and then
    -- reissues the method every tick. Unmocked, the load-time
    -- RequestScaleformMovie aborts the whole chunk, which fails every
    -- assertion in this file rather than just the scaleform behaviour.
    _G.RequestScaleformMovie = function(movie) return 'scaleform:' .. tostring(movie) end
    _G.BeginScaleformMovieMethod = function() end
    _G.ScaleformMovieMethodAddParamInt = function() end
    _G.EndScaleformMovieMethod = function() end
    _G.CreateThread = function(callback)
        local thread = coroutine.create(callback)
        threads[#threads + 1] = thread
        -- Runs to the first Wait(); a sampling thread suspends there.
        assert(coroutine.resume(thread))
    end
    _G.Wait = function(ms)
        waits[#waits + 1] = ms
        coroutine.yield()
    end

    _G.Config = {
        hud = { dynamic = opts.dynamicHud == true, elements = { mic = true, cash = true, vehicle = true } },
        poll = {
            vitalsInterval = 100,
            playerInterval = 100,
            vehicleInterval = 250,
            bridgeInterval = 500,
            minimapInterval = 250,
        },
    }

    _G.HudBridge = {
        isLoggedIn = function() return loggedIn end,
        onLoginChange = function(handler) loginHandlers[#loginHandlers + 1] = handler end,
        getSnapshot = function()
            if opts.snapshotError then error('qbcore export not resolvable', 0) end
            snapshots = snapshots + 1
            return { job = {}, gang = nil, cash = 0, bank = 0, hunger = 100, thirst = 100, stress = 0,
                     seatbelt = seatbelt, status = {} }
        end,
        getSeatbelt = function() return seatbelt end,
    }
    -- Only the adapters that can push implement this (the stub does not).
    if opts.bridgePush then
        _G.HudBridge.onChange = function(handler) bridgeHandlers[#bridgeHandlers + 1] = handler end
    end

    _G.Vehicle = {
        -- Reads the handle it is HANDED, not the cache: client/hud.lua already
        -- has the vehicle from QB.cache.onChange and must not pay for an
        -- export call to re-ask for it four times a second.
        getSnapshot = function(handle)
            vehicleHandles[#vehicleHandles + 1] = handle
            if not handle then return nil end
            vehicleSamples = vehicleSamples + 1
            local speed = opts.staticVehicle and 60 or (59 + vehicleSamples)
            return { speed = speed, fuel = 50, engineOn = true, headlights = 'low' }
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
            health = function() cacheReads.health = cacheReads.health + 1; return 200 end,
            ped = function() cacheReads.ped = cacheReads.ped + 1; return 42 end,
            armour = function() cacheReads.armour = cacheReads.armour + 1; return 0 end,
            stamina = function() cacheReads.stamina = cacheReads.stamina + 1; return 100 end,
            vehicle = function() cacheReads.vehicle = cacheReads.vehicle + 1; return vehicle end,
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
        waits = function() return waits end,
        cacheReads = function() return cacheReads end,
        vehicleHandles = function() return vehicleHandles end,
        -- Drives one qblib cache change notification, exactly as qblib's own
        -- modules/cache setValue does: handler(newValue, oldValue).
        pushCache = function(key, value, old)
            for _, handler in ipairs(cacheHandlers[key] or {}) do handler(value, old) end
        end,
        exported = exported,
        setLoggedIn = function(value)
            loggedIn = value
            for _, handler in ipairs(loginHandlers) do handler(value) end
        end,
        -- The most recent qbhud:visibility payload, or nil if none was sent.
        lastVisibility = function()
            for i = #sent, 1, -1 do
                if sent[i].action == 'qbhud:visibility' then return sent[i].data end
            end
            return nil
        end,
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

harness.test('a bridge that throws at load cannot take the HUD down with it', function()
    -- Every bridge read in the chunk (initial snapshot, the polling fallback)
    -- is pcall-guarded, so a mid-restart qbcore degrades to default data
    -- instead of aborting the chunk -- and the qbhud:ready callback (kept
    -- FIRST in the chunk as a last line of defence) still answers, so the
    -- page can never 404 forever on its ready ping.
    local hud = loadHud({ snapshotError = true })
    harness.assertTrue(hud.loaded, 'a throwing bridge must not abort the chunk: ' .. tostring(hud.loadError))
    harness.assertEqual(type(hud.callbacks['qbhud:ready']), 'function',
        'qbhud:ready must be registered before anything that can throw')

    local replies = 0
    hud.callbacks['qbhud:ready']({}, function() replies = replies + 1 end)
    harness.assertEqual(replies, 1,
        'the handler must always answer exactly once, or the page fetch hangs forever')
    harness.assertTrue(hud.contains('qbhud:visibility'),
        'the ready ping must still deliver the visibility push on default data')
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

harness.test('the HUD forwards the dynamic gauge option to the NUI', function()
    local hud = loadHud({ dynamicHud = true })
    local config
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:config' then config = message.data end
    end

    harness.assertTrue(config ~= nil, 'initial state should include the HUD config')
    harness.assertTrue(config.dynamic, 'Config.hud.dynamic should reach the gauge components')
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
        if message.action == 'qbhud:vitals' then latest = message.data end
    end

    harness.assertTrue(latest ~= nil, 'initial state should include the vitals channel')
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

    local before = hud.snapshots()
    hud.tick()
    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:vehicle' then latest = message.data end
    end
    harness.assertTrue(latest ~= nil, 'the vehicle tick should be running')
    harness.assertTrue(latest.seatbelt, 'a seatbelt toggle must reach the NUI while driving')
    harness.assertEqual(latest.headlights, 'low', 'headlight status must reach the NUI while driving')
    harness.assertEqual(hud.snapshots(), before,
        'the vehicle tick must not rebuild the full bridge snapshot just to read seatbelt state')
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

-- --- visibility: login transitions and the show/hide exports ---

harness.test('a login shows the HUD and a logout hides it', function()
    local hud = loadHud({ loggedIn = false })
    harness.assertEqual(hud.lastVisibility(), false, 'logged out at start means the HUD starts hidden')
    hud.reset()

    hud.setLoggedIn(true)
    harness.assertEqual(hud.lastVisibility(), true, 'a login transition must push visibility true')
    harness.assertTrue(hud.countAction('qbhud:update') > 0,
        'showing must also push a fresh data snapshot, not leave stale defaults on screen')

    hud.reset()
    hud.setLoggedIn(false)
    harness.assertEqual(hud.lastVisibility(), false, 'a logout transition must push visibility false')
end)

harness.test('the hide export force-hides the HUD and show restores it', function()
    local hud = loadHud()
    harness.assertEqual(type(hud.exported.hide), 'function', 'exports.qbhud:hide must be registered')
    harness.assertEqual(type(hud.exported.show), 'function', 'exports.qbhud:show must be registered')
    hud.reset()

    hud.exported.hide()
    harness.assertEqual(hud.lastVisibility(), false, 'hide() must push visibility false while logged in')
    harness.assertEqual(hud.exported.isVisible(), false, 'isVisible() reflects the forced hide')

    hud.reset()
    hud.exported.show()
    harness.assertEqual(hud.lastVisibility(), true, 'show() must clear the override and re-show')
    harness.assertEqual(hud.exported.isVisible(), true, 'isVisible() reflects the restore')
end)

harness.test('a login cannot undo another resource\'s forced hide', function()
    local hud = loadHud({ loggedIn = false })
    hud.exported.hide()
    hud.reset()

    hud.setLoggedIn(true)
    harness.assertEqual(hud.lastVisibility(), nil,
        'logging in while force-hidden must not push visibility true')
    harness.assertEqual(hud.exported.isVisible(), false, 'still hidden until show() clears the override')

    hud.exported.show()
    harness.assertEqual(hud.lastVisibility(), true, 'show() after login reveals the HUD')
end)

harness.test('show cannot reveal the HUD while logged out', function()
    local hud = loadHud({ loggedIn = false })
    hud.reset()

    hud.exported.show()
    harness.assertEqual(hud.lastVisibility(), nil, 'show() clears the override but login still gates')
    harness.assertEqual(hud.exported.isVisible(), false, 'the HUD stays hidden during character select')
end)

-- --- cost: nothing per frame, nothing re-read across the export boundary ---

harness.test('no HUD thread runs on a per-frame Wait(0)', function()
    -- The whole resource is written against a per-frame budget: every loop it
    -- owns is an interval, including the minimap scaleform re-assert that used
    -- to be a Wait(0) spin. A 0 (or nil, which Wait rejects in FiveM) here
    -- means something went back to running 60 times a second.
    local hud = loadHud({ bridgePush = true })
    hud.tick()
    hud.tick()

    for _, ms in ipairs(hud.waits()) do
        harness.assertTrue(type(ms) == 'number' and ms > 0,
            ('every HUD loop must wait a real interval, got %s'):format(tostring(ms)))
    end
end)

harness.test('a vitals change costs zero cross-resource cache reads', function()
    -- Every QB.cache.<fn>() is an export call. The old push read four of them
    -- (health/ped/armour/stamina) EVERY time stamina moved -- ten times a
    -- second for the whole length of a sprint. The change handlers are handed
    -- the new value as an argument; there is nothing left to go and ask for.
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    local before = hud.cacheReads()
    local baseline = { health = before.health, armour = before.armour,
                       stamina = before.stamina, ped = before.ped, vehicle = before.vehicle }

    for value = 99, 90, -1 do hud.pushCache('stamina', value) end
    hud.tick()

    local after = hud.cacheReads()
    for key, count in pairs(baseline) do
        harness.assertEqual(after[key], count,
            ('a stamina tick must not read QB.cache.%s across the export boundary'):format(key))
    end
end)

harness.test('stamina goes out on the vitals channel, not with job/gang/status', function()
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    hud.pushCache('stamina', 42)
    harness.assertEqual(hud.countAction('qbhud:vitals'), 1, 'a stamina change pushes vitals')
    harness.assertEqual(hud.countAction('qbhud:update'), 0,
        'the job label, gang table and status list must not be re-serialized for a stamina tick')

    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:vitals' then latest = message.data end
    end
    harness.assertEqual(latest.stamina, 42, 'the pushed value is the one the cache handed us')
    harness.assertTrue(latest.job == nil, 'player data has no business on the fast channel')
end)

harness.test('a burst of changes inside one interval collapses into a single message', function()
    -- Leading edge: the first change is immediate (no added latency on a
    -- one-off), everything arriving before the interval elapses is coalesced.
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    hud.pushCache('stamina', 80)
    harness.assertEqual(hud.countAction('qbhud:vitals'), 1, 'the first change must not wait for the interval')

    for value = 79, 70, -1 do hud.pushCache('stamina', value) end
    harness.assertEqual(hud.countAction('qbhud:vitals'), 1, 'ten more changes inside the interval add no messages')

    hud.tick()
    harness.assertEqual(hud.countAction('qbhud:vitals'), 2, 'the interval elapsing sends the latest value once')
end)

harness.test('sub-unit drift never reaches the wire', function()
    -- GetPedArmour/GetPlayerStamina are floats, so qblib's cache reports a
    -- change for movement far below what a 44px ring can render. Rounding on
    -- the way in is what lets the throttle actually go idle.
    local hud = loadHud({ bridgePush = true })
    hud.reset()

    hud.pushCache('stamina', 90.4)
    harness.assertEqual(hud.countAction('qbhud:vitals'), 1, 'the first whole-unit value is sent')
    hud.tick()
    hud.reset()

    hud.pushCache('stamina', 90.1)
    hud.pushCache('stamina', 89.8)
    hud.pushCache('stamina', 90.3)
    harness.assertEqual(hud.countAction('qbhud:vitals'), 0,
        'drift that rounds to the same whole unit must not send anything')
end)

harness.test('maximum health is resolved on a ped change, not on every push', function()
    local hud = loadHud({ bridgePush = true, maxHealth = 200 })
    hud.reset()

    _G.GetEntityMaxHealth = function() return 175 end
    hud.pushCache('ped', 77)

    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:vitals' then latest = message.data end
    end
    harness.assertTrue(latest ~= nil, 'a ped change must refresh the vitals')
    harness.assertEqual(latest.maxHealth, 175, 'a respawn onto a different ped model updates the maximum')
end)

harness.test('an unchanged vehicle reading is sampled but not re-sent', function()
    -- Idling at a red light, or parked with the engine running, produces the
    -- same reading every tick. Sampling is unavoidable (no event carries speed
    -- or fuel); sending is not.
    local hud = loadHud({ bridgePush = true, inVehicle = true, staticVehicle = true })
    hud.tick()
    hud.reset()

    local sampledBefore = #hud.vehicleHandles()
    hud.tick()
    hud.tick()

    harness.assertTrue(#hud.vehicleHandles() > sampledBefore, 'the sampler must keep running')
    harness.assertEqual(hud.countAction('qbhud:vehicle'), 0,
        'a reading identical to the last one sent is not worth a NUI message')
end)

harness.test('the vehicle sampler is handed the cached handle rather than re-reading it', function()
    local hud = loadHud({ bridgePush = true, inVehicle = true })
    hud.tick()

    local handles = hud.vehicleHandles()
    harness.assertTrue(#handles > 0, 'sanity: the sampler ran')
    for _, handle in ipairs(handles) do
        harness.assertEqual(handle, 42, 'every sample must use the handle QB.cache.onChange pushed')
    end
end)

harness.test('a hidden HUD does no work for a change nobody can see', function()
    -- Stamina keeps ticking through character select and cutscenes. The mirror
    -- must stay current (a later show has to paint real values) but nothing
    -- should reach the wire, and no throttle thread should be started to find
    -- that out.
    local hud = loadHud({ bridgePush = true, loggedIn = false })
    hud.reset()

    local threadsBefore = hud.threadCount()
    for value = 99, 90, -1 do hud.pushCache('stamina', value) end

    harness.assertEqual(hud.countAction('qbhud:vitals'), 0, 'a hidden HUD sends nothing')
    harness.assertEqual(hud.threadCount(), threadsBefore, 'and starts no thread to send nothing with')

    hud.setLoggedIn(true)
    local latest
    for _, message in ipairs(hud.sent) do
        if message.action == 'qbhud:vitals' then latest = message.data end
    end
    harness.assertTrue(latest ~= nil, 'showing the HUD paints it immediately')
    harness.assertEqual(latest.stamina, 90, 'with the value the mirror tracked while hidden')
end)

harness.test('the HUD subscribes to exactly the cache keys it mirrors', function()
    local hud = loadHud({ bridgePush = true })
    harness.assertEqual(table.concat(hud.cacheKeys(), ','), 'armour,health,ped,stamina,vehicle',
        'a new subscription here is a new hot path -- add it deliberately')
end)

harness.report('nui')
