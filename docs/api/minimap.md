---
title: "Minimap"
sidebar_position: 5
---


# Minimap

Owns the stock FiveM minimap's position, mask texture and clip type per `Config.hud.minimapLayout`, plus the separate visibility layers (`Config.hud.minimap` mode, the player `/minimap` toggle, and `Config.hud.minimapVehicleOnly`) — see the Config tables in How to use for the full toggle reference.

Namespace: `exports.kora_hud` · Source: `client/minimap.lua`

## How it works

Minimap component rects and masks are only re-read by the engine on a bigmap toggle, so every change is followed by one owner-serialised `SetBigmapActive(true)` → wait → `(false)` refresh rather than one per caller. `Config.hud.minimapLayout.guardBigmap` additionally forces a stuck-on bigmap back off (two consecutive detections, so a short deliberate toggle by another script is left alone) while kora_hud manages the layout and the pause menu is closed.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Managed | True when `Config.hud.minimapLayout.enabled` is true and `shape` is not `'stock'` — kora_hud owns the component rects/mask; otherwise the stock minimap is left alone (or any earlier change undone). |

## Functions

One export, for the one case Lua on its own cannot cover: restoring the layout after another resource changed it.

### `exports.kora_hud:applyMinimapLayout()`

Re-applies kora_hud's minimap layout (position, mask, clip type) right away. Intended for a resource that moved the minimap itself temporarily (for example a phone Maps app) and needs it put back exactly as kora_hud would have it.

**Parameters**



**Returns**

- **applied** — `true` once re-applied; `false` when `Config.hud.minimapLayout.enabled` is `false` or `shape` is `'stock'` — the caller should restore the stock layout itself in that case.

**Example**

```lua
if not exports.kora_hud:applyMinimapLayout() then
    restoreStockMinimap()
end
```

**Representative console output**

```text
true (kora_hud repositioned the minimap/mask/border and refreshed the clip type via a bigmap toggle).
```

## Limits and related APIs

Returns `false` instead of applying anything when the layout is disabled or `shape = 'stock'`. There is no export to change `Config.hud.minimapLayout` at runtime — edit `config.lua` (it is read live apart from the streamed texture file itself).

## Related guides

- [UI element registry](./ui-registry.md)
- [HUD visibility](./visibility.md)



kora_hud controls two things about the minimap: whether it is visible, and (optionally) its layout and shape.

## Visibility

`Config.hud.minimap` decides when the radar can show:

- `'always'` - kora_hud never calls `DisplayRadar`, so other resources can hide the radar freely.
- `'vehicle'` (default) - only while in a vehicle.
- `'never'` - always hidden; never overridden by a player.

On top of that:

- **Player toggle** (`/minimap` or a key bound in Settings) can hide the radar further. With `allowOnFoot` a player can also bring it back on foot when the mode is vehicle only. The choice is saved in client KVP when `remember` is on.
- **Minimap only in vehicle** can be switched per player in the editor (`Config.hud.minimapVehicleOnly`). It also works with the `'always'` mode.
- Pause menu, phone and force-hidden HUD keep working as before. `DisplayRadar` is only called when the answer changes.

The kora_hud health and armour gauges replace the stock health/armour cluster on the radar; `Config.poll.minimapInterval` controls how often this is re-asserted.

## Managed layout

With `Config.hud.minimapLayout.enabled` (default `true`) kora_hud positions the minimap, mask and border, and refreshes the radar with one `SetBigmapActive(true)` then `(false)` toggle. Setting it to `false` leaves the stock minimap alone and undoes anything applied earlier.

| Option | Default | Notes |
| --- | --- | --- |
| `shape` | `'square'` | `'square'` streams `stream/kora_hud_squaremap.ytd` (`textureDict = 'kora_hud_squaremap'`, `maskTexture = 'radarmasksm'`) and replaces `radarmasksm` and `radarmask1g` of `platform:/textures/graphics`, clip type 0. `'circle'` keeps the stock round mask, clip type 1. `'stock'` touches nothing. |
| `x`, `y` | `0.0` (live) | Added to every component, range -0.5 to 0.5. |
| `scale` | `1.0` (live) | Scales map, mask and border together, range 0.5-2.0. |
| `safezoneCompensation` | `0.0` (live, advanced) | Leave at 0 unless the map drifts from its border at small safezone sizes. |
| `offsets.map`, `offsets.mask`, `offsets.blur` | `0.0` each | Per-component nudge in screen fractions. |
| `aspectOffset.divisor`, `.bias`, `.tolerance` | `3.6`, `-0.008`, `0.01` | For aspects wider than 16:9 each x gets `((16/9 - aspect) / divisor) + bias`; aspects within `tolerance` count as 16:9. |
| `shapes.<shape>.rects`, `clipType` | see `config.lua` | Rects are left/bottom anchored `x`, `y`, `w`, `h` for `minimap`, `minimap_mask`, `minimap_blur`. Widths and heights are not aspect scaled. |
| `dictTimeoutMs` | `5000` | Wait for the texture dictionary. On timeout a warning is printed and the stock minimap is kept. |
| `retryMs`, `maxRetries` | `10000`, `3` | Retry a failed apply. |
| `bigmapWaitMs` | `50` | Delay between the two `SetBigmapActive` calls. |
| `readySettleMs`, `readyTimeoutMs` | `2000`, `30000` | Wait for the ped and minimap scaleform before the first apply. |
| `pollMs` | `1000` | Resolution and config check interval (clamped to 250-60000 by the poll loop). The layout is only re-applied when something changed. |
| `guardBigmap` | `true` (live) | Forces a bigmap that stays on (seen twice in a row, pause menu closed) back off. |

One owner (`client/minimap.lua`) runs every bigmap refresh; overlapping requests are coalesced. The layout is re-applied on `playerSpawned`, and on resource stop the masks, clip type and rects are put back to stock. The mask texture is generated by `python3 tools/gen_minimap_ytd.py [output.ytd]`.

Players can move and resize the minimap in `/ui` when `Config.uiEditor.minimap` is on, the layout is enabled and the shape is not `'stock'`. Visibility there is the same choice as `/minimap`.

`exports.kora_hud:applyMinimapLayout()` re-applies the layout; see [Exports](./index.md).
