---
title: "Layout"
sidebar_position: 3
---


# Layout

HUD section positions (and `kora_chat`'s composer offset, which shares the same KVP blob) are saved per player as JSON in a FiveM KVP (`Config.layout.kvpKey`, default `kora_hud:layout`) — client-side only, nothing ever reaches the server or a database.

Namespace: `exports.kora_hud` · Source: `client/hud.lua`

## How it works

Every read re-validates the stored blob (`readLayout`): unknown/invalid section ids are dropped, offsets are clamped per-section (`LAYOUT_BOUNDS`, or a ±1.0 viewport-fraction fallback for externally-registered elements), scales are clamped 0.75–1.50 for built-in sections (an externally registered element uses its own declared `scaleMin`/`scaleMax`). A corrupt or hand-edited KVP value degrades to an empty layout rather than breaking the HUD.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Viewport fraction | Every offset/rect is stored as a fraction of screen width/height, not pixels, so a layout saved at one resolution still makes sense at another. |

## Functions

One read-only export. Writing a layout only happens through the `/hudlayout`/`/ui` editor's own NUI callback — there is no export to set another player's (or your own) layout programmatically.

### `exports.kora_hud:getLayout()`

Read-only snapshot of this player's saved HUD layout, already validated. kora_chat uses this at startup to pick up a layout saved before it (re)started, without reading the KVP or trusting its contents itself.

**Parameters**



**Returns**

- **layout** — `{ offsets, scales, justifications, hidden, settings, gaugesBottomAnchored, minimapVehicleOnly }`. `offsets`/`scales`/`justifications`/`hidden`/`settings` are each keyed by section/element id; `gaugesBottomAnchored` and `minimapVehicleOnly` are booleans. An empty table for anything unsaved — never `nil`.

**Example**

```lua
local layout = exports.kora_hud:getLayout()
if layout.offsets.chatInput then
    applyComposerOffset(layout.offsets.chatInput)
end
```

**Representative console output**

```text
`{ offsets = { chatInput = { x = 0.1, y = -0.05 } }, scales = {}, justifications = {}, hidden = {}, settings = {}, gaugesBottomAnchored = true, minimapVehicleOnly = false }`
```

## Limits and related APIs

Read-only and client-side. Returns `{}`-shaped fields (not `nil`) when `Config.layout.movable` is `false` or nothing has been saved yet.

## Related guides

- [UI element registry](./ui-registry.md)
- [HUD visibility](./visibility.md)
