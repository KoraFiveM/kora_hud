local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local aspect, safezone = 16 / 9, 1.0
local calls, placed, bigmap, exported = {}, {}, {}, {}
local handlers, pollThread, live = {}, nil, {}

_G.Config = { hud = { minimapLayout = { enabled = true, x = 0.0, y = 0.0, scale = 1.0 } } }
_G.json = { encode = function(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = tostring(k) .. '=' .. tostring(type(v) == 'table' and 't' or v) end
    table.sort(keys)
    return table.concat(keys, ',')
end }
_G.GetAspectRatio = function() return aspect end
_G.GetSafeZoneSize = function() return safezone end
_G.RequestScaleformMovie = function() calls[#calls + 1] = 'scaleform'; return 1 end
_G.HasScaleformMovieLoaded = function() return true end
_G.SetMinimapComponentPosition = function(name, h, v, x, y, w, hh)
    calls[#calls + 1] = 'place'
    placed[#placed + 1] = { name = name, h = h, v = v, x = x, y = y, w = w, hh = hh }
end
_G.SetBigmapActive = function(on) calls[#calls + 1] = 'bigmap'; bigmap[#bigmap + 1] = on end
_G.exports = function(name, fn) exported[name] = fn end
_G.AddEventHandler = function(name, fn) handlers[name] = fn end
-- The first thread is the aspect/safezone poll and is driven by hand; every
-- other thread is an apply, started at once and finished by flush().
_G.CreateThread = function(fn)
    if not pollThread then pollThread = fn return end
    local co = coroutine.create(fn)
    live[#live + 1] = co
    assert(coroutine.resume(co))
end
_G.Wait = function() coroutine.yield() end

dofile(repoRoot .. 'client/minimap.lua')

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function reset() calls, placed, bigmap = {}, {}, {} end
local function flush()
    for _ = 1, 10 do
        local any = false
        for _, co in ipairs(live) do
            if coroutine.status(co) == 'suspended' then any = true; assert(coroutine.resume(co)) end
        end
        if not any then break end
    end
    live = {}
end

local VANILLA = {
    minimap      = { x = -0.0045, y = 0.002, w = 0.150, h = 0.188 },
    minimap_mask = { x = 0.020,   y = 0.032, w = 0.111, h = 0.159 },
    minimap_blur = { x = -0.03,   y = 0.022, w = 0.266, h = 0.237 },
}

harness.test('16:9, full safezone, default config is exactly the vanilla reference', function()
    local r = HudMinimap.layout(16 / 9, 1.0, { shape = 'stock' })
    for name, want in pairs(VANILLA) do
        for _, k in ipairs({ 'x', 'y', 'w', 'h' }) do
            harness.assertTrue(r[name][k] == want[k], name .. '.' .. k .. ' is ' .. tostring(r[name][k]))
        end
    end
end)

harness.test('ultrawide gets narrower widths and unchanged heights', function()
    local base = HudMinimap.layout(16 / 9, 1.0, {})
    for _, a in ipairs({ 21 / 9, 32 / 9 }) do
        local r = HudMinimap.layout(a, 1.0, {})
        for _, n in ipairs(HudMinimap.COMPONENTS) do
            harness.assertTrue(r[n].w < base[n].w, n .. ' narrower at ' .. a)
            harness.assertTrue(near(r[n].w, base[n].w * (16 / 9) / a), n .. ' width factor')
            harness.assertTrue(near(r[n].h, base[n].h) and near(r[n].y, base[n].y), n .. ' same height and y')
        end
    end
    harness.assertTrue(HudMinimap.layout(32 / 9, 1.0, {}).minimap.w < HudMinimap.layout(21 / 9, 1.0, {}).minimap.w, '32:9 narrower than 21:9')
end)

harness.test('4:3 and 16:10 are sane: wider fractions, same height, no inversion', function()
    local base = HudMinimap.layout(16 / 9, 1.0, {})
    for _, a in ipairs({ 4 / 3, 16 / 10 }) do
        local r = HudMinimap.layout(a, 1.0, {})
        for _, n in ipairs(HudMinimap.COMPONENTS) do
            harness.assertTrue(r[n].w > base[n].w and near(r[n].h, base[n].h), n .. ' at ' .. a)
        end
        harness.assertTrue(near(r.minimap.w * a, base.minimap.w * 16 / 9), 'same pixel width at ' .. a)
        harness.assertTrue(r.minimap.w < 0.25 and r.minimap.h < 0.25, 'nothing near bigmap size')
    end
end)

harness.test('the map stays inside its mask and blur frame', function()
    for _, a in ipairs({ 4 / 3, 16 / 9, 21 / 9, 32 / 9 }) do
        local r = HudMinimap.layout(a, 1.0, {})
        harness.assertTrue(r.minimap_blur.w > r.minimap.w and r.minimap_blur.h > r.minimap.h, 'blur frames the map at ' .. a)
        harness.assertTrue(r.minimap_blur.x <= r.minimap.x and r.minimap_blur.y >= r.minimap.y, 'blur starts outside the map')
    end
end)

harness.test('scale multiplies sizes and in-frame offsets, not screen offsets', function()
    local one, two = HudMinimap.layout(16 / 9, 1.0, {}), HudMinimap.layout(16 / 9, 1.0, { scale = 1.5 })
    for _, n in ipairs(HudMinimap.COMPONENTS) do
        harness.assertTrue(near(two[n].w, one[n].w * 1.5) and near(two[n].h, one[n].h * 1.5), n .. ' scaled')
        harness.assertTrue(near(two[n].x, one[n].x * 1.5) and near(two[n].y, one[n].y * 1.5), n .. ' offsets scaled')
    end
    local s = HudMinimap.layout(16 / 9, 1.0, { x = 0.01, y = 0.02 })
    harness.assertTrue(near(s.minimap.x, -0.0045 + 0.01) and near(s.minimap.y, 0.002 + 0.02), 'shift is unscaled')
end)

harness.test('safezone does nothing by default; compensation cancels the margin', function()
    local a = HudMinimap.layout(16 / 9, 1.0, {})
    local b = HudMinimap.layout(16 / 9, 0.9, {})
    harness.assertTrue(near(a.minimap.x, b.minimap.x) and near(a.minimap.y, b.minimap.y), 'default does not depend on safezone')
    local c = HudMinimap.layout(16 / 9, 0.9, { safezoneCompensation = 1.0 })
    harness.assertTrue(near(c.minimap.x, -0.0045 - 0.05) and near(c.minimap.y, 0.002 + 0.05), 'margin cancelled')
    for _, n in ipairs(HudMinimap.COMPONENTS) do
        harness.assertTrue(near(c[n].w, a[n].w), 'size unchanged')
    end
end)

harness.test('fine offsets move one component', function()
    local base = HudMinimap.layout(16 / 9, 1.0, {})
    local r = HudMinimap.layout(16 / 9, 1.0, { x = 0.01, y = 0.02, offsets = { mask = { x = 0.005 } } })
    harness.assertTrue(near(r.minimap.x - base.minimap.x, 0.01) and near(r.minimap.y - base.minimap.y, 0.02), 'global offset')
    harness.assertTrue(near(r.minimap_mask.x - base.minimap_mask.x, 0.015), 'mask fine offset stacks')
    harness.assertTrue(near(r.minimap_blur.x - base.minimap_blur.x, 0.01), 'blur unaffected by mask offset')
end)

harness.test('bad config values fall back instead of breaking the layout', function()
    local r = HudMinimap.layout('x', nil, { scale = 'big', x = 0/0, y = 99, offsets = 5 })
    harness.assertTrue(near(r.minimap.w, 0.150), 'scale falls back to 1, aspect to 16:9')
    harness.assertTrue(near(r.minimap.x, -0.0045), 'nan offset ignored')
    harness.assertTrue(near(r.minimap.y, 0.002 + 1.0), 'offset clamped')
end)

harness.test('apply places three components, then toggles bigmap on, a frame later off', function()
    reset()
    harness.assertTrue(HudMinimap.apply(true), 'applied')
    flush()
    harness.assertEqual(#placed, 3, 'three components')
    harness.assertEqual(placed[1].h .. placed[1].v, 'LB', 'left/bottom anchor')
    harness.assertTrue(near(placed[1].w, 0.150) and near(placed[1].h and placed[1].hh, 0.188), 'vanilla size reaches the native')
    harness.assertTrue(#bigmap == 2 and bigmap[1] == true and bigmap[2] == false, 'bigmap on then off, ends off')
end)

harness.test('the bigmap off call is not in the same frame as the on call', function()
    reset(); aspect = 21 / 9
    HudMinimap.apply()
    -- the apply thread has run up to its first Wait: bigmap is on, not yet off
    harness.assertTrue(#bigmap == 1 and bigmap[1] == true, 'only on before the wait')
    flush()
    harness.assertTrue(#bigmap == 2 and bigmap[2] == false, 'off after the wait')
    aspect = 16 / 9
    HudMinimap.apply(); flush()
end)

harness.test('apply is a no-op until aspect, safezone or config changes', function()
    reset()
    HudMinimap.apply(); flush()
    harness.assertEqual(#placed, 0, 'unchanged')
    aspect = 21 / 9; HudMinimap.apply(); flush()
    harness.assertEqual(#placed, 3, 'aspect change re-applies')
    reset(); safezone = 0.8; HudMinimap.apply(); flush()
    harness.assertEqual(#placed, 3, 'safezone change re-applies')
    reset(); Config.hud = { minimapLayout = { enabled = true, scale = 1.2 } }; HudMinimap.apply(); flush()
    harness.assertEqual(#placed, 3, 'config change re-applies live')
    reset(); HudMinimap.apply(); flush()
    harness.assertEqual(#placed + #bigmap, 0, 'settled again')
end)

harness.test('concurrent applies are serialised and never leave bigmap on', function()
    reset()
    HudMinimap.apply(true)
    HudMinimap.apply(true)
    HudMinimap.apply(true)
    harness.assertEqual(#live, 1, 'a single apply thread')
    flush()
    harness.assertTrue(bigmap[#bigmap] == false, 'bigmap ends off')
    local on = 0
    for i, v in ipairs(bigmap) do
        if v then on = on + 1; harness.assertTrue(bigmap[i + 1] == false, 'every on is followed by an off') end
    end
    harness.assertTrue(on <= 2, 'queued requests coalesce')
end)

harness.test('disabled layout (default) never touches the minimap, and re-enabling applies', function()
    reset()
    for _, cfg in ipairs({ { enabled = false }, {}, { enabled = 'yes' } }) do
        Config.hud = { minimapLayout = cfg }
        harness.assertFalse(HudMinimap.apply(true), 'force does not override disabled')
        harness.assertFalse(HudMinimap.apply(), 'plain apply is disabled too')
        harness.assertFalse(exported.applyMinimapLayout(), 'export reports not applied')
        handlers.playerSpawned()
        local poll = coroutine.create(pollThread)
        harness.assertTrue(coroutine.resume(poll), 'poll tick does not raise')
        flush()
    end
    harness.assertEqual(#calls, 0, 'no natives called at all (positions, bigmap, scaleform)')
    Config.hud = { minimapLayout = { enabled = true } }
    harness.assertTrue(HudMinimap.apply(), 'enabled again')
    flush()
    harness.assertEqual(#placed, 3, 'applied after re-enable')
end)

harness.test('export and spawn force a re-apply; missing config is a no-op', function()
    reset()
    harness.assertTrue(exported.applyMinimapLayout(), 'export applies')
    flush()
    harness.assertEqual(#placed, 3, 'export forced')
    reset(); handlers.playerSpawned(); flush()
    harness.assertEqual(#placed, 3, 'spawn forced')
    reset(); Config.hud = {}
    harness.assertFalse(HudMinimap.apply(true), 'no config table')
    harness.assertEqual(#calls, 0, 'nothing touched')
end)

harness.test('the poll thread survives a failing native', function()
    Config.hud = { minimapLayout = { enabled = true } }
    local co = coroutine.create(pollThread)
    local real = _G.GetAspectRatio
    _G.GetAspectRatio = function() error('boom') end
    harness.assertTrue(coroutine.resume(co), 'first tick does not raise')
    harness.assertTrue(coroutine.resume(co), 'second tick still alive')
    harness.assertEqual(coroutine.status(co), 'suspended', 'loop still running')
    _G.GetAspectRatio = real
end)

harness.test('a failing native inside apply still ends with bigmap off and unlocks', function()
    reset(); live = {}
    Config.hud = { minimapLayout = { enabled = true, scale = 1.7 } }
    local real = _G.SetMinimapComponentPosition
    _G.SetMinimapComponentPosition = function() error('boom') end
    harness.assertTrue(HudMinimap.apply(true), 'accepted')
    flush()
    _G.SetMinimapComponentPosition = real
    harness.assertTrue(bigmap[#bigmap] == false, 'bigmap forced off after the error')
    reset(); HudMinimap.apply(true); flush()
    harness.assertEqual(#placed, 3, 'later applies still run')
end)

local mask = { added = {}, removed = {}, clip = {}, requested = {}, loaded = true, released = {}, runtimeTxd = {}, runtimeImage = {} }
_G.RequestStreamedTextureDict = function(d) mask.requested[#mask.requested + 1] = d end
_G.HasStreamedTextureDictLoaded = function() return mask.loaded end
_G.AddReplaceTexture = function(t, n, d, dn) mask.added[#mask.added + 1] = { t, n, d, dn } end
_G.RemoveReplaceTexture = function(t, n) mask.removed[#mask.removed + 1] = n end
_G.SetMinimapClipType = function(c) mask.clip[#mask.clip + 1] = c end
_G.CreateRuntimeTxd = function(n)
    mask.runtimeCalls = (mask.runtimeCalls or 0) + 1
    if mask.runtimeFails then error('no txd') end
    mask.runtimeTxd[#mask.runtimeTxd + 1] = n
    return n
end
_G.CreateRuntimeTextureFromImage = function(txd, n, path) mask.runtimeImage[#mask.runtimeImage + 1] = path end
_G.SetStreamedTextureDictAsNoLongerNeeded = function(d) mask.released[#mask.released + 1] = d end

local function runShape()
    local co = coroutine.create(HudMinimap.applyShape)
    for _ = 1, 200 do
        if coroutine.status(co) == 'dead' then break end
        assert(coroutine.resume(co))
    end
end

harness.test('shape stock touches no mask native', function()
    Config.hud = { minimapLayout = { enabled = true, shape = 'stock' } }
    runShape()
    harness.assertEqual(#mask.added + #mask.clip + #mask.requested + #mask.removed, 0, 'nothing called')
end)

harness.test('a missing mask dict leaves the stock mask and does not retry every poll', function()
    mask.added, mask.clip, mask.requested = {}, {}, {}
    mask.runtimeFails, mask.runtimeCalls = true, 0
    -- Earlier tests ran the poll thread with no natives: forget its failure.
    handlers.onClientResourceStart('x')
    Config.hud = { minimapLayout = { shape = 'stock' } }
    runShape()
    Config.hud = { minimapLayout = { shape = 'square' } }
    runShape(); runShape()
    harness.assertEqual(#mask.added + #mask.clip, 0, 'no mask change without the asset')
    harness.assertEqual(mask.runtimeCalls, 1, 'runtime texture tried until a resource starts, not every poll')
    mask.runtimeFails = false
    handlers.onClientResourceStart('x')
    runShape()
    harness.assertEqual(#mask.added, 2, 'applied once the texture can be created')
    Config.hud = { minimapLayout = { shape = 'stock' } }
    runShape()
    mask.added, mask.removed, mask.clip, mask.released = {}, {}, {}, {}
end)

harness.test('shape square swaps both masks, sets clip type 0, and applies once', function()
    Config.hud = { minimapLayout = { enabled = true, shape = 'square' } }
    runShape(); runShape()
    harness.assertEqual(#mask.added, 2, 'radarmasksm and radarmask1g replaced once')
    harness.assertEqual(mask.added[1][2], 'radarmasksm', 'radarmasksm')
    harness.assertEqual(mask.added[2][2], 'radarmask1g', 'radarmask1g')
    harness.assertEqual(mask.added[1][3], 'kora_hud_minimap', 'runtime txd by default')
    harness.assertEqual(mask.added[1][4], 'square_mask', 'runtime texture name')
    harness.assertEqual(mask.added[2][3], 'kora_hud_minimap', 'same txd for radarmask1g')
    harness.assertEqual(#mask.requested, 0, 'no streamed dict requested without squareTextureDict')
    harness.assertEqual(#mask.runtimeTxd, 1, 'runtime txd created once')
    harness.assertEqual(mask.runtimeImage[1], 'assets/square_minimap_mask.png', 'PNG path')
    harness.assertTrue(#bigmap >= 2 and bigmap[#bigmap] == false, 'bigmap refresh toggled back off')
    harness.assertEqual(mask.clip[#mask.clip], 0, 'square clip type')
    harness.assertEqual(#mask.clip, 1, 'not re-applied while unchanged')
end)

harness.test('switching back to stock removes the masks and restores the clip type', function()
    Config.hud = { minimapLayout = { enabled = true, shape = 'stock' } }
    runShape()
    harness.assertEqual(#mask.removed, 2, 'both replacements removed')
    harness.assertEqual(mask.clip[#mask.clip], 1, 'round clip type restored')
    harness.assertEqual(bigmap[#bigmap], false, 'refresh leaves the bigmap off')
end)

harness.test('square is the default shape when none is configured', function()
    Config.hud = { minimapLayout = { enabled = true } }
    mask.added = {}
    runShape()
    harness.assertEqual(#mask.added, 2, 'masks applied with no shape set')
    harness.assertEqual(mask.clip[#mask.clip], 0, 'square clip type')
end)

harness.test('square mask is square in pixels at 16:9, 21:9 and 32:9, and safezone-aware', function()
    for _, a in ipairs({ 16 / 9, 21 / 9, 32 / 9 }) do
        local m = HudMinimap.layout(a, 1.0, {}).minimap_mask
        harness.assertTrue(math.abs(m.w * a - m.h) < 0.001, 'square at aspect ' .. a)
    end
    local m = HudMinimap.layout(16 / 9, 0.9, { safezoneCompensation = 1.0 }).minimap_mask
    harness.assertTrue(m.x < HudMinimap.layout(16 / 9, 1.0, { safezoneCompensation = 1.0 }).minimap_mask.x, 'safezone compensation shifts x')
end)

harness.test('a streamed squareTextureDict is preferred over the runtime texture', function()
    mask.added = {}
    Config.hud = { minimapLayout = { enabled = true, shape = 'square', squareTextureDict = 'mydict' } }
    runShape()
    harness.assertEqual(mask.added[1][3], 'mydict', 'streamed dict used')
    harness.assertEqual(mask.added[1][4], 'radarmasksm', 'same texture name in the dict')
    Config.hud = { minimapLayout = { enabled = true, shape = 'stock' } }
    runShape()
    harness.assertEqual(mask.released[#mask.released], 'mydict', 'dict released')
end)

harness.test('a missing squareTextureDict falls back to the runtime texture', function()
    mask.added, mask.loaded = {}, false
    Config.hud = { minimapLayout = { enabled = true, shape = 'square', squareTextureDict = 'nodict' } }
    runShape()
    harness.assertEqual(mask.added[1][3], 'kora_hud_minimap', 'runtime fallback')
    mask.loaded = true
end)

harness.report('minimap')
