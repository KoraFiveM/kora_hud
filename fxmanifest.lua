fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'kora_hud'
-- Keep the legacy resource name resolvable for exports['qbhud'] callers.
provide 'qbhud'
author 'Jamie'
version '0.1.0'
description 'Configurable HUD built on kora_lib and qbtheme'

dependency 'kora_theme'
dependency 'kora_lib'
-- The HUD now sources real player data from kora_core via client/bridge/qbcore.lua
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
    'client/bridge/qbcore.lua',
    'client/voice.lua',
    'client/vehicle.lua',
    'client/seatbelt_sound.lua',
    'client/minimap.lua',
    'client/stress.lua',
    'client/hud.lua'
}

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
