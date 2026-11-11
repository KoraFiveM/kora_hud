fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'kora_hud'
provide 'qb-hud'
author 'Jamie'
version '0.1.0'
description 'Configurable HUD built on kora_lib and kora_theme'

dependency 'kora_theme'
dependency 'kora_lib'
-- The HUD now sources real player data from kora_core via client/bridge/kora_core.lua
-- (Config.bridge.adapter = 'kora_core'). Revert to the stub by flipping both.
dependency 'kora_core'
dependency 'kora_fuel'

-- Required to reach Kora.cache -- see kora_lib's own AGENTS.md for
-- why this is how a consumer resource pulls in the Kora proxy (init.lua).
shared_script '@kora_lib/init.lua'

shared_scripts {
    'config.lua',
    'shared/bridge.lua'
}

-- bridge/stub.lua must load before hud.lua/vehicle.lua/voice.lua reference
-- HudBridge -- listed explicitly rather than globbed, same reasoning kora_lib's
-- own fxmanifest.lua uses for local/**.
client_scripts {
    '@kora_theme/client/bridge.lua',
    'client/bridge/kora_core.lua',
    'client/voice.lua',
    'client/vehicle.lua',
    'client/seatbelt_sound.lua',
    'client/minimap.lua',
    'client/stress.lua',
    'client/compat.lua',
    -- /ui element registry (HudUi). Before hud.lua, which owns the editor.
    'client/uiregistry.lua',
    'client/hud.lua',
    -- Optional FFT hooks: returns immediately unless fft_kora_hooks is true.
    'fft_hooks.lua'
}

-- stream/kora_hud_squaremap.ytd (the square radar mask, built by
-- tools/gen_minimap_ytd.py) needs no files entry: FiveM streams everything in
-- stream/ automatically and the dictionary name is the file name.

-- web/build is committed (see kora_lib's AGENTS.md "UI (web/) layout" -- same
-- convention here). FiveM serves it statically, there's no build step at
-- resource-start time.
ui_page 'web/build/index.html'

-- A bare trailing '**' does NOT match files in FiveM's resource globber --
-- see kora_lib/fxmanifest.lua's comment. Needs the explicit '/*'.
files {
    'web/build/index.html',
    'web/build/assets/**/*',
    'web/build/sounds/*.wav'
}

-- kora_qa: Gherkin test scenarios (converted legacy tests), see [kora]/kora_qa/README.md
qa_feature 'tests/*.feature'
