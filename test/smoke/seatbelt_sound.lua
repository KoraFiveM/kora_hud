-- client/seatbelt_sound.lua: sound only on a real buckle/unbuckle while seated,
-- gated by config that is read at play time.
local scriptDir = debug.getinfo(1, 'S').source:match('@?(.*/)') or './'
local testDir = scriptDir .. '../'
local repoRoot = testDir .. '../'
package.path = testDir .. '?.lua;' .. package.path

local harness = require('harness')

local function load(sound, opts)
    opts = opts or {}
    local handlers, nui, frontend = {}, {}, {}
    local fixture = { inVehicle = opts.inVehicle ~= false }
    _G.Config = { seatbelt = { sound = sound } }
    _G.LocalPlayer = { state = { seatbelt = opts.initial == true } }
    _G.PlayerPedId = function() return 1 end
    _G.IsPedInAnyVehicle = function() return fixture.inVehicle end
    _G.AddEventHandler = function(name, fn) handlers[name] = fn end
    _G.SendNUIMessage = function(msg) nui[#nui + 1] = msg end
    _G.PlaySoundFrontend = function(...) frontend[#frontend + 1] = { ... } end
    assert(loadfile(repoRoot .. 'client/seatbelt_sound.lua'))()
    fixture.toggle = handlers['seatbelt:client:ToggleSeatbelt']
    fixture.nui, fixture.frontend = nui, frontend
    return fixture
end

harness.test('buckle and unbuckle send distinct files at the configured volume', function()
    local f = load({ volume = 0.4, buckleFile = 'a.wav', unbuckleFile = 'b.wav' })
    harness.assertTrue(f.toggle, 'listens for the seatbelt event')
    f.toggle(true)
    f.toggle(false)
    harness.assertEqual(#f.nui, 2)
    harness.assertEqual(f.nui[1].action, 'qbhud:seatbeltSound')
    harness.assertEqual(f.nui[1].data.file, 'a.wav')
    harness.assertEqual(f.nui[1].data.volume, 0.4)
    harness.assertEqual(f.nui[2].data.file, 'b.wav')
end)

harness.test('defaults apply when config keys are missing', function()
    local f = load({})
    f.toggle(true)
    harness.assertEqual(f.nui[1].data.file, 'seatbelt_buckle.wav')
    harness.assertEqual(f.nui[1].data.volume, 0.5)
    f.toggle(false)
    harness.assertEqual(f.nui[2].data.file, 'seatbelt_unbuckle.wav')
end)

harness.test('repeated identical state and false-while-unbuckled are silent', function()
    local f = load({})
    f.toggle(false)
    f.toggle(true)
    f.toggle(true)
    harness.assertEqual(#f.nui, 1)
end)

harness.test('no sound when the player is not in a vehicle (vehicle exit reset)', function()
    local f = load({}, { initial = true })
    f.inVehicle = false
    f.toggle(false)
    harness.assertEqual(#f.nui, 0)
    f.inVehicle = true
    f.toggle(true)
    harness.assertEqual(#f.nui, 1)
end)

harness.test('enabled=false is read at play time and silences everything', function()
    local f = load({ enabled = true })
    f.toggle(true)
    harness.assertEqual(#f.nui, 1)
    Config.seatbelt.sound.enabled = false
    f.toggle(false)
    harness.assertEqual(#f.nui, 1)
end)

harness.test('volume is clamped and zero is silent', function()
    local f = load({ volume = 7 })
    f.toggle(true)
    harness.assertEqual(f.nui[1].data.volume, 1.0)
    Config.seatbelt.sound.volume = 0
    f.toggle(false)
    harness.assertEqual(#f.nui, 1)
end)

harness.test('native backend uses frontend sounds and no NUI message', function()
    local f = load({ backend = 'native' })
    f.toggle(true)
    f.toggle(false)
    harness.assertEqual(#f.nui, 0)
    harness.assertEqual(#f.frontend, 2)
    harness.assertTrue(f.frontend[1][2] ~= f.frontend[2][2], 'distinct sounds')
end)

harness.test('missing Config.seatbelt does not error', function()
    local f = load({})
    _G.Config = {}
    f.toggle(true)
    harness.assertEqual(#f.nui, 1)
end)

harness.report('seatbelt_sound')
