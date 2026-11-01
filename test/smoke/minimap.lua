local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')
local realPrint = print

-- A tiny game: a clock, a coroutine scheduler for CreateThread/Wait, and every
-- native client/minimap.lua uses, recorded in `log` in call order.
local game
local function encode(value)
    if type(value) ~= 'table' then return tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. '=' .. encode(value[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function readConfig(boolean)
    _G.Config = nil
    _G.Kora = boolean and { config = { boolean = boolean } } or nil
    dofile(repoRoot .. 'config.lua')
    return _G.Config
end

---Fresh game plus a fresh copy of client/minimap.lua, with the real config.lua.
---@param tweak fun(layout: table, hud: table)|nil
local function boot(tweak)
    game = {
        t = 0, log = {}, threads = {}, handlers = {}, exported = {}, warnings = {},
        w = 1920, h = 1080, ped = 1, dictLoaded = true, bigmap = false, paused = false,
        dictRequests = 0,
    }
    local log = game.log
    local function note(...) log[#log + 1] = table.concat({ ... }, ':') end

    readConfig(nil)
    if tweak then tweak(Config.hud.minimapLayout, Config.hud) end
    _G.Kora = nil
    _G.json = { encode = encode }
    _G.print = function(...) game.warnings[#game.warnings + 1] = table.concat({ ... }, ' ') end
    _G.GetGameTimer = function() return game.t end
    _G.GetActiveScreenResolution = function() return game.w, game.h end
    _G.GetAspectRatio = function() return game.w / game.h end
    _G.GetSafeZoneSize = function() return 1.0 end
    _G.PlayerPedId = function() return game.ped end
    _G.DoesEntityExist = function(e) return e ~= 0 end
    _G.PlayerId = function() return 0 end
    _G.NetworkIsPlayerActive = function() return true end
    _G.GetIsLoadingScreenActive = function() return false end
    _G.RequestScaleformMovie = function() return 7 end
    _G.HasScaleformMovieLoaded = function() return true end
    _G.IsPauseMenuActive = function() return game.paused end
    _G.IsBigmapActive = function() return game.bigmap end
    _G.SetBigmapActive = function(on, big)
        game.bigmap = on
        note('bigmap', tostring(on), tostring(big))
    end
    _G.SetMinimapClipType = function(c) note('clip', tostring(c)) end
    _G.RequestStreamedTextureDict = function(d, b)
        game.dictRequests = game.dictRequests + 1
        note('request', d, tostring(b))
    end
    _G.HasStreamedTextureDictLoaded = function() return game.dictLoaded end
    _G.SetStreamedTextureDictAsNoLongerNeeded = function(d) note('release', d) end
    _G.AddReplaceTexture = function(txd, name, dict, tex) note('add', txd, name, dict, tex) end
    _G.RemoveReplaceTexture = function(txd, name) note('remove', txd, name) end
    _G.SetMinimapComponentPosition = function(name, h, v, x, y, w, hh)
        note('place', name, h, v, string.format('%.6f', x), string.format('%.6f', y), string.format('%.6f', w), string.format('%.6f', hh))
    end
    _G.GetCurrentResourceName = function() return 'kora_hud' end
    _G.exports = function(name, fn) game.exported[name] = fn end
    _G.AddEventHandler = function(name, fn) game.handlers[name] = fn end
    _G.CreateThread = function(fn)
        local thread = { co = coroutine.create(fn), wake = 0 }
        game.threads[#game.threads + 1] = thread
        local ok, err = coroutine.resume(thread.co)
        assert(ok, err)
        thread.wake = game.t + (thread.nextWait or 0)
    end
    _G.Wait = function(ms)
        ms = ms or 0
        for i, thread in ipairs(game.threads) do
            if thread.co == coroutine.running() then
                thread.nextWait = ms
                -- thread 1 is the poll loop; only the apply worker's waits are interesting
                if ms ~= 0 and i > 1 then note('wait', tostring(ms)) end
            end
        end
        coroutine.yield()
    end

    _G.HudMinimap = nil
    dofile(repoRoot .. 'client/minimap.lua')
    return game
end

---Runs the scheduler for `ms` of game time in `step` ms slices.
local function advance(ms, step)
    step = step or 10
    local target = game.t + ms
    while game.t < target do
        game.t = game.t + step
        for _, thread in ipairs(game.threads) do
            if coroutine.status(thread.co) == 'suspended' and thread.wake <= game.t then
                local ok, err = coroutine.resume(thread.co)
                assert(ok, err)
                thread.wake = game.t + (thread.nextWait or 0)
            end
        end
    end
end

local function clear() for i = #game.log, 1, -1 do game.log[i] = nil end end
local function count(prefix)
    local n = 0
    for _, line in ipairs(game.log) do
        if line:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end
local function nonWait()
    local n = 0
    for _, line in ipairs(game.log) do
        if line:sub(1, 5) ~= 'wait:' then n = n + 1 end
    end
    return n
end
local function lines() return table.concat(game.log, '\n') end
local function native(name) return count(name .. ':') end

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function rect(r) return { r.x, r.y, r.w, r.h } end
local function exact(r, x, y, w, h, label)
    harness.assertTrue(r.x == x and r.y == y and r.w == w and r.h == h,
        string.format('%s is %s,%s,%s,%s', label, r.x, r.y, r.w, r.h))
end
local function placeLine(name, x, y, w, h)
    return string.format('place:%s:L:B:%.6f:%.6f:%.6f:%.6f', name, x + 0.0, y + 0.0, w, h)
end

local SQUARE = {
    minimap      = { 0.0,   -0.047, 0.1638, 0.183 },
    minimap_mask = { 0.0,   0.0,    0.128,  0.20 },
    minimap_blur = { -0.01, 0.025,  0.262,  0.300 },
}
local CIRCLE = {
    minimap      = { -0.0100, -0.030, 0.180, 0.258 },
    minimap_mask = { 0.200,   0.0,    0.065, 0.20 },
    minimap_blur = { -0.00,   0.015,  0.252, 0.338 },
}
local STOCK = {
    minimap      = { -0.0045, 0.002, 0.150, 0.188 },
    minimap_mask = { 0.020,   0.032, 0.111, 0.159 },
    minimap_blur = { -0.03,   0.022, 0.266, 0.237 },
}
local ORDER = { 'minimap', 'minimap_mask', 'minimap_blur' }

-- ---------------------------------------------------------------- rect math

harness.test('16:9 square rects are exactly the proven numbers, widths unscaled', function()
    boot()
    local cfg = Config.hud.minimapLayout
    local r = HudMinimap.layout(16 / 9, 1.0, cfg)
    for _, name in ipairs(ORDER) do
        local want = SQUARE[name]
        exact(r[name], want[1], want[2], want[3], want[4], name)
    end
    exact(HudMinimap.layout(16 / 9, 1.0, { shape = 'circle', shapes = cfg.shapes }).minimap, -0.0100, -0.030, 0.180, 0.258, 'circle minimap')
    local c = HudMinimap.layout(16 / 9, 1.0, { shape = 'circle', shapes = cfg.shapes })
    for _, name in ipairs(ORDER) do exact(c[name], CIRCLE[name][1], CIRCLE[name][2], CIRCLE[name][3], CIRCLE[name][4], 'circle ' .. name) end
end)

harness.test('the default config carries every number, the dictionary and the offset rule', function()
    boot()
    local cfg = Config.hud.minimapLayout
    harness.assertEqual(cfg.enabled, true, 'enabled by default')
    harness.assertEqual(cfg.shape, 'square', 'square is the default shape')
    harness.assertEqual(cfg.textureDict, 'kora_hud_squaremap')
    harness.assertEqual(cfg.maskTexture, 'radarmasksm')
    harness.assertEqual(cfg.bigmapWaitMs, 50)
    harness.assertEqual(cfg.aspectOffset.divisor, 3.6)
    harness.assertEqual(cfg.aspectOffset.bias, -0.008)
    harness.assertEqual(cfg.scale, 1.0)
    harness.assertEqual(cfg.safezoneCompensation, 0.0, 'no extra safezone correction by default')
    harness.assertEqual(cfg.guardBigmap, true)
    for shape, want in pairs({ square = SQUARE, circle = CIRCLE, stock = STOCK }) do
        for _, name in ipairs(ORDER) do
            local got = cfg.shapes[shape].rects[name]
            harness.assertTrue(got.x == want[name][1] and got.y == want[name][2] and got.w == want[name][3] and got.h == want[name][4],
                shape .. ' ' .. name .. ' matches')
        end
    end
    harness.assertEqual(cfg.shapes.square.clipType, 0)
    harness.assertEqual(cfg.shapes.circle.clipType, 1)
    harness.assertEqual(Config.hud.minimapVehicleOnly.default, false)
    harness.assertEqual(Config.hud.minimapVehicleOnly.allowPlayerChange, true)
end)

harness.test('ultrawide gets the x offset only; widths, heights and y are unchanged', function()
    boot()
    local cfg = Config.hud.minimapLayout
    for _, a in ipairs({ 2560 / 1080, 3440 / 1440, 32 / 9 }) do
        local off = ((16 / 9) - a) / 3.6 - 0.008
        harness.assertTrue(near(HudMinimap.aspectOffset(a, cfg), off), 'offset formula at ' .. a)
        local r = HudMinimap.layout(a, 1.0, cfg)
        for _, name in ipairs(ORDER) do
            local base = SQUARE[name]
            harness.assertTrue(near(r[name].x, base[1] + off), name .. ' x shifted by the offset at ' .. a)
            harness.assertTrue(r[name].y == base[2] and r[name].w == base[3] and r[name].h == base[4], name .. ' y/w/h untouched at ' .. a)
        end
    end
    local twentyOneNine = HudMinimap.aspectOffset(21 / 9, cfg)
    harness.assertTrue(near(twentyOneNine, (16 / 9 - 21 / 9) / 3.6 - 0.008), '21:9 matches the formula')
    harness.assertTrue(twentyOneNine < 0, 'and moves the map left')
end)

harness.test('16:9 and narrower screens get no offset', function()
    boot()
    local cfg = Config.hud.minimapLayout
    for _, a in ipairs({ 16 / 9, 16 / 10, 4 / 3, 5 / 4, 1919 / 1079, 1530 / 868 }) do
        harness.assertEqual(HudMinimap.aspectOffset(a, cfg), 0.0, 'no offset at ' .. a)
        local r = HudMinimap.layout(a, 1.0, cfg)
        for _, name in ipairs(ORDER) do exact(r[name], SQUARE[name][1], SQUARE[name][2], SQUARE[name][3], SQUARE[name][4], name) end
    end
end)

harness.test('user nudges stack on top; scale 1.0 and zero nudges change nothing', function()
    boot()
    local cfg = Config.hud.minimapLayout
    local base = HudMinimap.layout(16 / 9, 1.0, cfg)
    local moved = HudMinimap.layout(16 / 9, 1.0, setmetatable({ x = 0.01, y = 0.02, offsets = { mask = { x = 0.005 } } }, { __index = cfg }))
    harness.assertTrue(near(moved.minimap.x - base.minimap.x, 0.01) and near(moved.minimap.y - base.minimap.y, 0.02), 'global nudge')
    harness.assertTrue(near(moved.minimap_mask.x - base.minimap_mask.x, 0.015), 'fine offset stacks')
    harness.assertTrue(near(moved.minimap_blur.x - base.minimap_blur.x, 0.01), 'blur unaffected by the mask offset')
    local big = HudMinimap.layout(16 / 9, 1.0, setmetatable({ scale = 1.5 }, { __index = cfg }))
    harness.assertTrue(near(big.minimap.w, SQUARE.minimap[3] * 1.5) and near(big.minimap.h, SQUARE.minimap[4] * 1.5), 'scale scales sizes')
end)

harness.test('safezone is ignored by default; compensation is opt-in', function()
    boot()
    local cfg = Config.hud.minimapLayout
    local a, b = HudMinimap.layout(16 / 9, 1.0, cfg), HudMinimap.layout(16 / 9, 0.9, cfg)
    harness.assertTrue(a.minimap.x == b.minimap.x and a.minimap.y == b.minimap.y, 'default does not depend on the safezone')
    local c = HudMinimap.layout(16 / 9, 0.9, setmetatable({ safezoneCompensation = 1.0 }, { __index = cfg }))
    harness.assertTrue(near(c.minimap.x, SQUARE.minimap[1] - 0.05) and near(c.minimap.y, SQUARE.minimap[2] + 0.05), 'margin cancelled')
end)

harness.test('bad config values fall back instead of breaking the layout', function()
    boot()
    local cfg = Config.hud.minimapLayout
    local r = HudMinimap.layout('x', nil, setmetatable({ scale = 'big', x = 0 / 0, y = 99, offsets = 5 }, { __index = cfg }))
    harness.assertTrue(near(r.minimap.w, 0.1638), 'scale falls back to 1')
    harness.assertTrue(near(r.minimap.x, 0.0), 'nan nudge ignored')
    harness.assertTrue(near(r.minimap.y, -0.047 + 1.0), 'nudge clamped')
    harness.assertEqual(HudMinimap.layout(16 / 9, 1.0, { shape = 'square', shapes = { square = { rects = {} } } }), nil, 'missing rects')
end)

harness.test('resolution comes from GetActiveScreenResolution, falling back to GetAspectRatio', function()
    boot()
    game.w, game.h = 2560, 1080
    HudMinimap.apply(true)
    advance(3000)
    local off = (16 / 9 - 2560 / 1080) / 3.6 - 0.008
    harness.assertTrue(lines():find(string.format('place:minimap:L:B:%.6f', SQUARE.minimap[1] + off), 1, true), 'real resolution used')

    boot()
    game.w, game.h = 1920, 1080
    _G.GetActiveScreenResolution = function() return 0, 0 end
    _G.GetAspectRatio = function() return 21 / 9 end
    HudMinimap.apply(true)
    advance(3000)
    local off219 = (16 / 9 - 21 / 9) / 3.6 - 0.008
    harness.assertTrue(lines():find(string.format('place:minimap:L:B:%.6f', SQUARE.minimap[1] + off219), 1, true), 'aspect fallback used')
end)

-- ------------------------------------------------------------ apply: square

local function settleFree(layout) layout.readySettleMs = 0 end

harness.test('square apply: stream, clip type, replace both masks, three rects, one bigmap refresh', function()
    boot(settleFree)
    harness.assertTrue(HudMinimap.apply(true), 'managed layout reports applied')
    advance(2000)
    local want = {
        'request:kora_hud_squaremap:false',
        'clip:0',
        'add:platform:/textures/graphics:radarmasksm:kora_hud_squaremap:radarmasksm',
        'add:platform:/textures/graphics:radarmask1g:kora_hud_squaremap:radarmasksm',
        placeLine('minimap', 0.0, -0.047, 0.1638, 0.183),
        placeLine('minimap_mask', 0.0, 0.0, 0.128, 0.20),
        placeLine('minimap_blur', -0.01, 0.025, 0.262, 0.300),
        'bigmap:true:false',
        'wait:50',
        'bigmap:false:false',
    }
    harness.assertEqual(lines(), table.concat(want, '\n'), 'exact native sequence')
    harness.assertTrue(HudMinimap.isApplied(), 'applied state tracked')
    harness.assertFalse(game.bigmap, 'bigmap ends off')
end)

harness.test('nothing is applied before the player ped exists', function()
    boot(function(l) settleFree(l); game.ped = 0 end)
    advance(5000)
    harness.assertEqual(nonWait(), 0, 'no natives while the radar can not exist yet')
    game.ped = 1
    advance(1000)
    harness.assertEqual(native('bigmap'), 2, 'applied once the ped exists')
end)

harness.test('the settle delay is waited once before the first apply', function()
    boot(function(l) l.readySettleMs = 2000 end)
    HudMinimap.apply(true)
    advance(1500)
    harness.assertEqual(nonWait(), 0, 'still settling')
    advance(1000)
    harness.assertEqual(native('clip'), 1, 'applied after the settle delay')
end)

harness.test('a dictionary that never streams warns, keeps stock and leaves nothing half-applied', function()
    boot(settleFree)
    game.dictLoaded = false
    HudMinimap.apply(true)
    advance(6000, 50)
    harness.assertEqual(native('clip') + native('add') + native('place') + native('bigmap'), 0, 'no clip, texture, rect or bigmap call')
    harness.assertFalse(HudMinimap.isApplied(), 'nothing applied')
    harness.assertTrue(#game.warnings >= 1 and game.warnings[1]:find('kora_hud_squaremap', 1, true), 'a warning names the dictionary')
end)

harness.test('a failed apply is retried a limited number of times, then succeeds once the dictionary streams', function()
    boot(function(l) l.readySettleMs = 0; l.retryMs = 2000; l.maxRetries = 2; l.pollMs = 250 end)
    game.dictLoaded = false
    HudMinimap.apply(true)
    advance(40000, 50)
    harness.assertEqual(game.dictRequests, 3, 'first try plus maxRetries, then it stops')
    harness.assertFalse(HudMinimap.isApplied())

    boot(function(l) l.readySettleMs = 0; l.retryMs = 2000; l.maxRetries = 5; l.pollMs = 250 end)
    game.dictLoaded = false
    HudMinimap.apply(true)
    advance(7000, 50)
    harness.assertFalse(HudMinimap.isApplied(), 'still failing')
    game.dictLoaded = true
    advance(6000, 50)
    harness.assertTrue(HudMinimap.isApplied(), 'a later retry applies it')
    harness.assertFalse(game.bigmap)
end)

harness.test('a shape without valid rects warns and keeps the stock minimap', function()
    boot(function(l) l.readySettleMs = 0; l.shapes.square.rects.minimap = nil end)
    HudMinimap.apply(true)
    advance(2000)
    harness.assertEqual(#game.log, 0, 'nothing touched')
    harness.assertTrue(#game.warnings >= 1, 'warned')
end)

-- ---------------------------------------------------- circle / stock / off

harness.test("shape 'circle' uses the stock round mask: clip type 1, no texture replaced, its own rects", function()
    boot(function(l) l.readySettleMs = 0; l.shape = 'circle' end)
    HudMinimap.apply(true)
    advance(2000)
    harness.assertEqual(native('request') + native('add'), 0, 'no streamed dictionary, no texture replaced')
    harness.assertTrue(lines():find('clip:1', 1, true), 'round clip type')
    for _, name in ipairs(ORDER) do
        local r = CIRCLE[name]
        harness.assertTrue(lines():find(placeLine(name, r[1], r[2], r[3], r[4]), 1, true), 'circle rect ' .. name)
    end
    harness.assertEqual(native('bigmap'), 2, 'one refresh')
end)

harness.test("shape 'stock' touches nothing at all, and the export reports it", function()
    boot(function(l) l.readySettleMs = 0; l.shape = 'stock' end)
    harness.assertFalse(HudMinimap.apply(true), 'stock is not managed')
    harness.assertFalse(game.exported.applyMinimapLayout(), 'export reports not managed')
    game.handlers.playerSpawned()
    advance(5000)
    harness.assertEqual(#game.log, 0, 'no native called: pure vanilla')
end)

harness.test('layout disabled (false, nil or non-boolean) touches nothing', function()
    for _, value in ipairs({ false, 'yes', 1 }) do
        boot(function(l) l.enabled = value end)
        harness.assertFalse(HudMinimap.apply(true))
        harness.assertFalse(game.exported.applyMinimapLayout())
        advance(5000)
        harness.assertEqual(#game.log, 0, 'disabled with ' .. tostring(value))
    end
    boot(function(_, hud) hud.minimapLayout = nil end)
    harness.assertFalse(HudMinimap.apply(true), 'no layout table at all')
    advance(3000)
    harness.assertEqual(#game.log, 0)
end)

harness.test('switching to stock or disabling undoes an applied layout cleanly', function()
    for _, change in ipairs({ function(l) l.shape = 'stock' end, function(l) l.enabled = false end }) do
        boot(settleFree)
        HudMinimap.apply(true)
        advance(2000)
        harness.assertTrue(HudMinimap.isApplied())
        clear()
        change(Config.hud.minimapLayout)
        advance(3000)
        local want = {
            'remove:platform:/textures/graphics:radarmasksm',
            'remove:platform:/textures/graphics:radarmask1g',
            'release:kora_hud_squaremap',
            'clip:0',
            placeLine('minimap', -0.0045, 0.002, 0.150, 0.188),
            placeLine('minimap_mask', 0.020, 0.032, 0.111, 0.159),
            placeLine('minimap_blur', -0.03, 0.022, 0.266, 0.237),
            'bigmap:true:false',
            'wait:50',
            'bigmap:false:false',
        }
        harness.assertEqual(lines(), table.concat(want, '\n'), 'undo restores textures, clip type and the vanilla rects')
        harness.assertFalse(HudMinimap.isApplied())
    end
end)

-- ------------------------------------------------- bigmap owner / polling

harness.test('overlapping applies coalesce into one bigmap refresh', function()
    boot(settleFree)
    for _ = 1, 6 do HudMinimap.apply(true) end
    game.handlers.playerSpawned()
    game.exported.applyMinimapLayout()
    advance(3000)
    harness.assertEqual(native('bigmap'), 2, 'one on and one off for eight requests')
    harness.assertEqual(native('clip'), 1, 'and one apply')
end)

harness.test('a request during a pass runs one more pass, never an overlapping toggle', function()
    boot(settleFree)
    HudMinimap.apply(true)
    while not game.bigmap do advance(10) end
    HudMinimap.apply(true)
    HudMinimap.apply(true)
    advance(3000)
    local state, flips = false, 0
    for _, line in ipairs(game.log) do
        local on = line:match('^bigmap:(%a+):')
        if on then
            harness.assertTrue((on == 'true') ~= state, 'strict on/off alternation')
            state = on == 'true'
            if state then flips = flips + 1 end
        end
    end
    harness.assertEqual(flips, 2, 'the two mid-pass requests coalesce into one extra refresh')
    harness.assertFalse(game.bigmap, 'ends off')
end)

harness.test('a changed resolution is re-applied once, an unchanged one is not', function()
    boot(function(l) l.readySettleMs = 0; l.pollMs = 1000 end)
    HudMinimap.apply()
    advance(2000)
    clear()
    advance(10000)
    harness.assertEqual(#game.log, 0, 'ten polls with nothing changed do nothing')
    game.w, game.h = 3440, 1440
    advance(3000)
    harness.assertEqual(native('bigmap'), 2, 'one refresh after the resolution changed')
    local off = (16 / 9 - 3440 / 1440) / 3.6 - 0.008
    harness.assertTrue(lines():find(string.format('place:minimap:L:B:%.6f', SQUARE.minimap[1] + off), 1, true), 'new offset applied')
    harness.assertTrue(lines():find(placeLine('minimap_blur', -0.01 + off, 0.025, 0.262, 0.300), 1, true), 'widths unchanged')
    clear()
    advance(5000)
    harness.assertEqual(#game.log, 0, 'and quiet again')
end)

harness.test('export and respawn force a re-apply (the phone Maps app restore)', function()
    boot(settleFree)
    harness.assertTrue(game.exported.applyMinimapLayout(), 'export reports managed')
    advance(2000)
    clear()
    harness.assertTrue(game.exported.applyMinimapLayout())
    advance(2000)
    harness.assertEqual(native('place'), 3, 'export re-places the rects')
    clear()
    game.handlers.playerSpawned()
    advance(2000)
    harness.assertEqual(native('place'), 3, 'respawn re-places them')
end)

harness.test('the guard forces a stuck bigmap off while the layout is managed', function()
    boot(function(l) l.readySettleMs = 0; l.pollMs = 250 end)
    HudMinimap.apply(true)
    advance(2000)
    clear()
    game.bigmap = true
    advance(250, 250)
    harness.assertTrue(game.bigmap, 'one sighting is not enough (a short toggle by another script)')
    advance(600, 250)
    harness.assertFalse(game.bigmap, 'a stuck bigmap is forced off')
    harness.assertEqual(lines(), 'bigmap:false:false')
end)

harness.test('the guard leaves the bigmap alone in the pause menu, when disabled and when stock', function()
    boot(function(l) l.readySettleMs = 0; l.pollMs = 250 end)
    HudMinimap.apply(true)
    advance(2000)
    game.bigmap, game.paused = true, true
    advance(3000, 250)
    harness.assertTrue(game.bigmap, 'the pause menu owns it')

    boot(function(l) l.readySettleMs = 0; l.pollMs = 250; l.guardBigmap = false end)
    HudMinimap.apply(true)
    advance(2000)
    game.bigmap = true
    advance(3000, 250)
    harness.assertTrue(game.bigmap, 'guardBigmap = false')

    boot(function(l) l.pollMs = 250; l.shape = 'stock' end)
    advance(1000, 250)
    game.bigmap = true
    advance(3000, 250)
    harness.assertTrue(game.bigmap, 'stock is pure vanilla')
end)

-- ------------------------------------------------------------- resource stop

harness.test('stopping the resource reverts everything so a txAdmin restart starts clean', function()
    boot(settleFree)
    HudMinimap.apply(true)
    advance(2000)
    clear()
    game.handlers.onResourceStop('some_other_resource')
    harness.assertEqual(#game.log, 0, 'other resources stopping is ignored')
    game.handlers.onResourceStop('kora_hud')
    local text = lines()
    harness.assertEqual(native('remove'), 2, 'both mask replacements removed')
    harness.assertTrue(text:find('remove:platform:/textures/graphics:radarmasksm', 1, true) and text:find('remove:platform:/textures/graphics:radarmask1g', 1, true))
    harness.assertTrue(text:find('release:kora_hud_squaremap', 1, true), 'dictionary released')
    harness.assertTrue(text:find('clip:0', 1, true), 'stock clip type')
    for _, name in ipairs(ORDER) do
        local r = STOCK[name]
        harness.assertTrue(text:find(placeLine(name, r[1], r[2], r[3], r[4]), 1, true), 'stock rect ' .. name)
    end
    harness.assertTrue(text:find('bigmap:false:false', 1, true), 'bigmap forced off')
    harness.assertFalse(text:find('bigmap:true', 1, true), 'no toggle while stopping')
    harness.assertFalse(HudMinimap.isApplied())
    clear()
    advance(5000)
    harness.assertEqual(#game.log, 0, 'the poll does not re-apply after the stop')
end)

harness.test('stopping a resource that applied nothing touches nothing', function()
    boot(function(l) l.shape = 'stock' end)
    game.handlers.onResourceStop('kora_hud')
    harness.assertEqual(native('place') + native('clip') + native('bigmap'), 0)
end)

harness.test('stopping while the bigmap refresh is mid-flight still ends with it off', function()
    boot(settleFree)
    HudMinimap.apply(true)
    while not game.bigmap do advance(10) end
    game.handlers.onResourceStop('kora_hud')
    harness.assertFalse(game.bigmap)
end)

-- ----------------------------------------------------- config / files / cleanup

harness.test('no `X and f(...) or true` default remains in config.lua; false is expressible', function()
    local file = assert(io.open(repoRoot .. 'config.lua', 'r'))
    local source = file:read('a'):gsub('%-%-[^\n]*', '')
    file:close()
    harness.assertFalse(source:find('%)%s*or%s+true'), 'no ") or true" fallback')
    harness.assertFalse(source:find('configBoolean%s+and'), 'no "configBoolean and ..." pattern')

    -- A kora_lib whose boolean descriptor resolves every option to false.
    local config = readConfig(function() return false end)
    harness.assertEqual(config.hud.minimapLayout.enabled, false, 'minimapLayout.enabled = false is honoured')
    harness.assertEqual(config.hud.minimapLayout.guardBigmap, false)
    harness.assertEqual(config.hud.minimapToggle.enabled, false)
    harness.assertEqual(config.hud.minimapToggle.remember, false)
    harness.assertEqual(config.hud.minimapToggle.defaultVisible, false)
    harness.assertEqual(config.hud.minimapVehicleOnly.default, false)
    harness.assertEqual(config.hud.minimapVehicleOnly.allowPlayerChange, false)
    harness.assertEqual(config.hud.hideOnPauseMenu, false)
    harness.assertEqual(config.hud.hideMinimapWhenForcedHidden, false)
    harness.assertEqual(config.seatbelt.sound.enabled, false)
    -- And a kora_lib that resolves them all to true, plus the no-kora_lib default.
    harness.assertEqual(readConfig(function() return true end).hud.minimapVehicleOnly.default, true)
    harness.assertEqual(readConfig(nil).hud.minimapLayout.enabled, true, 'defaults to on without kora_lib')
    _G.Kora = nil
end)

harness.test('the square mask ships as a streamed .ytd; the runtime PNG path is gone', function()
    local ytd = assert(io.open(repoRoot .. 'stream/kora_hud_squaremap.ytd', 'rb'), 'stream/kora_hud_squaremap.ytd exists')
    local head = ytd:read(4)
    ytd:close()
    harness.assertEqual(head, 'RSC7', 'a resource-container texture dictionary')
    harness.assertTrue(assert(io.open(repoRoot .. 'tools/gen_minimap_ytd.py', 'r')) ~= nil, 'its generator is in the repo')
    harness.assertEqual(io.open(repoRoot .. 'assets/square_minimap_mask.png', 'r'), nil, 'runtime PNG removed')
    harness.assertEqual(io.open(repoRoot .. 'tools/gen_minimap_mask.py', 'r'), nil, 'PNG generator removed')
    for _, path in ipairs({ 'client/minimap.lua', 'client/hud.lua', 'config.lua', 'fxmanifest.lua' }) do
        local f = assert(io.open(repoRoot .. path, 'r'))
        local text = f:read('a')
        f:close()
        harness.assertFalse(text:find('CreateRuntimeTxd', 1, true) or text:find('CreateRuntimeTextureFromImage', 1, true)
            or text:find('square_minimap_mask', 1, true) or text:find('squareTextureDict', 1, true), path .. ' has no runtime-PNG leftovers')
    end
    local manifest = assert(io.open(repoRoot .. 'fxmanifest.lua', 'r'))
    local text = manifest:read('a')
    manifest:close()
    harness.assertFalse(text:find('stream/', 1, true) and text:find("'stream/", 1, true), 'stream/ needs no files entry')
end)

_G.print = realPrint
harness.report('minimap')
