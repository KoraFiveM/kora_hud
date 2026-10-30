local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local aspect, safezone = 16 / 9, 1.0
local placed, bigmap, exported, threads = {}, {}, {}, {}
local handlers = {}

_G.Config = { hud = { minimapLayout = { enabled = true, x = 0.0, y = 0.0, scale = 1.0 } } }
_G.json = { encode = function(t)
    local keys = {}
    for k, v in pairs(t) do keys[#keys + 1] = tostring(k) .. '=' .. tostring(type(v) == 'table' and 't' or v) end
    table.sort(keys)
    return table.concat(keys, ',')
end }
_G.GetAspectRatio = function() return aspect end
_G.GetSafeZoneSize = function() return safezone end
_G.SetMinimapComponentPosition = function(name, h, v, x, y, w, hh)
    placed[#placed + 1] = { name = name, h = h, v = v, x = x, y = y, w = w, hh = hh }
end
_G.SetBigmapActive = function(on) bigmap[#bigmap + 1] = on end
_G.exports = function(name, fn) exported[name] = fn end
_G.AddEventHandler = function(name, fn) handlers[name] = fn end
_G.CreateThread = function(fn) threads[#threads + 1] = fn end
_G.Wait = function() coroutine.yield() end

dofile(repoRoot .. 'client/minimap.lua')

local function near(a, b) return math.abs(a - b) < 1e-9 end
local function reset() placed, bigmap = {}, {} end

harness.test('16:9 at full safezone uses the base rects', function()
    local r = HudMinimap.layout(16 / 9, 1.0, {})
    harness.assertTrue(near(r.minimap.x, 0.0) and near(r.minimap.y, -0.047), 'map position')
    harness.assertTrue(near(r.minimap.w, 0.1638) and near(r.minimap.h, 0.183), 'map size')
    harness.assertTrue(near(r.minimap_blur.x, -0.01), 'blur sits just outside the map')
end)

harness.test('4:3 and 16:10 need no ultrawide correction', function()
    for _, a in ipairs({ 4 / 3, 16 / 10, 16 / 9 }) do
        local r = HudMinimap.layout(a, 1.0, {})
        harness.assertTrue(near(r.minimap.x, 0.0), 'no shift at aspect ' .. a)
    end
end)

harness.test('ultrawide shifts every component by the same amount, further as it widens', function()
    local last = 0
    for _, a in ipairs({ 21 / 9, 32 / 9 }) do
        local r = HudMinimap.layout(a, 1.0, {})
        local base = HudMinimap.layout(16 / 9, 1.0, {})
        local d = r.minimap.x - base.minimap.x
        harness.assertTrue(d < last, 'shift grows leftwards with aspect')
        last = d
        for _, n in ipairs(HudMinimap.COMPONENTS) do
            harness.assertTrue(near(r[n].x - base[n].x, d), n .. ' keeps its offset from the map')
            harness.assertTrue(near(r[n].y, base[n].y), n .. ' y is unaffected by aspect')
        end
    end
end)

harness.test('mask and blur always keep the same relative layout around the map', function()
    local base = HudMinimap.layout(16 / 9, 1.0, {})
    for _, a in ipairs({ 4 / 3, 16 / 10, 21 / 9, 32 / 9 }) do
        for _, s in ipairs({ 1.0, 0.9, 0.7 }) do
            local r = HudMinimap.layout(a, s, { scale = 1.3, x = 0.02, y = -0.01 })
            harness.assertTrue(near((r.minimap_blur.x - r.minimap.x) - (base.minimap_blur.x - base.minimap.x) * 1.3, 0), 'blur x relative')
            harness.assertTrue(near((r.minimap_mask.y - r.minimap.y) - (base.minimap_mask.y - base.minimap.y) * 1.3, 0), 'mask y relative')
        end
    end
end)

harness.test('scale multiplies sizes of all three components', function()
    local one, two = HudMinimap.layout(16 / 9, 1.0, {}), HudMinimap.layout(16 / 9, 1.0, { scale = 1.5 })
    for _, n in ipairs(HudMinimap.COMPONENTS) do
        harness.assertTrue(near(two[n].w, one[n].w * 1.5) and near(two[n].h, one[n].h * 1.5), n .. ' scales')
    end
end)

harness.test('safezone is neutral by default and compensates when asked', function()
    local a = HudMinimap.layout(16 / 9, 1.0, {})
    local b = HudMinimap.layout(16 / 9, 0.9, {})
    harness.assertTrue(near(a.minimap.x, b.minimap.x) and near(a.minimap.y, b.minimap.y), 'default does not depend on safezone')
    local c = HudMinimap.layout(16 / 9, 0.9, { safezoneCompensation = 1.0 })
    harness.assertTrue(near(c.minimap.x, -0.05) and near(c.minimap.y, -0.047 + 0.05), 'margin cancelled')
    for _, n in ipairs(HudMinimap.COMPONENTS) do
        harness.assertTrue(near(c[n].x - b[n].x, -0.05), n .. ' moves together')
    end
end)

harness.test('offsets: global applies to all, per-component to one only', function()
    local base = HudMinimap.layout(16 / 9, 1.0, {})
    local r = HudMinimap.layout(16 / 9, 1.0, { x = 0.01, y = 0.02, offsets = { mask = { x = 0.005 } } })
    harness.assertTrue(near(r.minimap.x - base.minimap.x, 0.01) and near(r.minimap.y - base.minimap.y, 0.02), 'global offset')
    harness.assertTrue(near(r.minimap_mask.x - base.minimap_mask.x, 0.015), 'mask fine offset stacks')
    harness.assertTrue(near(r.minimap_blur.x - base.minimap_blur.x, 0.01), 'blur unaffected by mask offset')
end)

harness.test('garbage config and inputs fall back to safe values', function()
    local r = HudMinimap.layout('x', nil, { scale = 'big', x = 0/0, y = 99, offsets = 5 })
    harness.assertTrue(near(r.minimap.w, 0.1638), 'scale falls back to 1')
    harness.assertTrue(near(r.minimap.x, 0.0), 'nan offset ignored')
    harness.assertTrue(near(r.minimap.y, -0.047 + 1.0), 'offset clamped')
end)

harness.test('apply places all three components then toggles bigmap once', function()
    reset()
    harness.assertTrue(HudMinimap.apply(true), 'applied')
    harness.assertEqual(#placed, 3, 'three components')
    harness.assertEqual(placed[1].h .. placed[1].v, 'LB', 'left/bottom anchor')
    harness.assertTrue(bigmap[1] == true and bigmap[2] == false and #bigmap == 2, 'bigmap toggled on then off')
end)

harness.test('apply is a no-op until aspect, safezone or config changes', function()
    reset()
    HudMinimap.apply()
    harness.assertEqual(#placed, 0, 'unchanged')
    aspect = 21 / 9; HudMinimap.apply()
    harness.assertEqual(#placed, 3, 'aspect change re-applies')
    reset(); safezone = 0.8; HudMinimap.apply()
    harness.assertEqual(#placed, 3, 'safezone change re-applies')
    reset(); Config.hud = { minimapLayout = { enabled = true, scale = 1.2 } }; HudMinimap.apply()
    harness.assertEqual(#placed, 3, 'config change re-applies live')
    reset(); HudMinimap.apply()
    harness.assertEqual(#placed, 0, 'settled again')
end)

harness.test('disabled layout never touches the minimap, and re-enabling applies', function()
    reset()
    Config.hud = { minimapLayout = { enabled = false } }
    harness.assertFalse(HudMinimap.apply(true), 'force does not override disabled')
    harness.assertFalse(exported.applyMinimapLayout(), 'export reports not applied')
    harness.assertEqual(#placed + #bigmap, 0, 'no natives called')
    Config.hud = { minimapLayout = { enabled = true } }
    harness.assertTrue(HudMinimap.apply(), 'enabled again')
    harness.assertEqual(#placed, 3, 'applied after re-enable')
end)

harness.test('export and spawn force a re-apply; missing config is a no-op', function()
    reset()
    harness.assertTrue(exported.applyMinimapLayout(), 'export applies')
    harness.assertEqual(#placed, 3, 'export forced')
    reset(); handlers.playerSpawned()
    harness.assertEqual(#placed, 3, 'spawn forced')
    reset(); Config.hud = {}
    harness.assertFalse(HudMinimap.apply(true), 'no config table')
    harness.assertEqual(#placed, 0, 'nothing placed')
end)

harness.test('the poll thread survives a failing native', function()
    Config.hud = { minimapLayout = { enabled = true } }
    local co = coroutine.create(threads[1])
    _G.GetAspectRatio = function() error('boom') end
    harness.assertTrue(coroutine.resume(co), 'first tick does not raise')
    harness.assertTrue(coroutine.resume(co), 'second tick still alive')
    harness.assertEqual(coroutine.status(co), 'suspended', 'loop still running')
end)

harness.report('minimap')
