fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'qbhud'
author 'Jamie'
version '0.1.0'
description 'Configurable HUD built on qblib (cache, theme, nui)'

dependency 'qblib'
-- The HUD now sources real player data from qbcore via client/bridge/qbcore.lua
-- (Config.bridge.adapter = 'qbcore'). Revert to the stub by flipping both.
dependency 'qbcore'

-- Required to reach QB.cache/QB.theme/QB.nui -- see qblib's own AGENTS.md for
-- why this is how a consumer resource pulls in the QB proxy (init.lua).
shared_script '@qblib/init.lua'

shared_scripts {
    'config.lua',
    'shared/bridge.lua'
}

-- bridge/stub.lua must load before hud.lua/vehicle.lua/voice.lua reference
-- HudBridge -- listed explicitly rather than globbed, same reasoning qblib's
-- own fxmanifest.lua uses for local/**.
client_scripts {
    'client/bridge/qbcore.lua',
    'client/voice.lua',
    'client/vehicle.lua',
    'client/hud.lua'
}

-- web/build is committed (see qblib's AGENTS.md "UI (web/) layout" -- same
-- convention here). FiveM serves it statically, there's no build step at
-- resource-start time.
ui_page 'web/build/index.html'

-- A bare trailing '**' does NOT match files in FiveM's resource globber --
-- see qblib/fxmanifest.lua's comment. Needs the explicit '/*'.
files {
    'web/build/index.html',
    'web/build/assets/**/*'
}
