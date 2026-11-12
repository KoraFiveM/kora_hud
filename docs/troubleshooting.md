---
title: Troubleshooting
sidebar_position: 11
---

# Troubleshooting

**The resource does not start.** `kora_theme`, `kora_lib`, `kora_core` and `kora_fuel` are hard dependencies in `fxmanifest.lua`. Start them first. See [Installation](./installation.md).

**The HUD never appears.** With the `kora_core` adapter it renders only when `kora_core:loggedIn` is true, `kora_multichar:mode` is cleared and the player data mirror exists. Check that a character is logged in and that no other resource has called `exports.kora_hud:hide()` without `show()`.

**The HUD disappears on the map.** Intentional: `Config.hud.hideOnPauseMenu`.

**The minimap is missing on foot.** The default mode is `'vehicle'`. Players can show it with `/minimap` while `allowOnFoot` is on, or you can set `Config.hud.minimap = 'always'`.

**The square minimap does not apply or another resource positions the radar.** If the texture dictionary does not stream within `dictTimeoutMs` a warning is printed and the stock minimap is kept (retried up to `maxRetries`). If another resource positions the minimap, set `Config.hud.minimapLayout.enabled = false`. An oversized bigmap stuck on is forced off by `guardBigmap`.

**The stock health/armour cluster shows through.** Set `Config.poll.minimapInterval = 0` to re-assert every frame.

**`/ui` does nothing.** The editor needs the HUD visible, and `Config.layout.movable` true. `/hudlayout` reports when moving is disabled.

**Stress never rises.** Check `Config.stress.enabled`, the job whitelist, the speed `threshold` and unit, and that `kora_core` accepts `stress` from `QBCore:Server:SetMetaData`.

**No seatbelt sound.** The sound plays only on real seatbelt state changes raised as `seatbelt:client:ToggleSeatbelt` while seated. Check `Config.seatbelt.sound.enabled` and `volume`; `volume = 0` is silent.

**Mic indicator shows no mode or range.** `Config.voice.resource` must be running and export `getTalkingMode()`; otherwise only the talking icon is shown.

**Layout looks wrong after changing monitors.** Layouts are fractions of the viewport and stored per machine. Run `/hudlayoutreset`.
