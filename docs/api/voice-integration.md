---
title: "Voice integration"
sidebar_position: 7
---


# Voice integration

The mic-talking indicator itself needs no integration at all: it reads FiveM's own `NetworkIsPlayerTalking` native, which reflects whichever voice resource sits on top of it (pma-voice, saltychat, mumble-voip all share the same Mumble backend). The only thing a voice resource can add is the proximity-range label, through one export.

Namespace: `Config.voice` · Source: `client/voice.lua, config.lua (Config.voice)`

## How it works

`client/voice.lua` owns no thread of its own: `client/hud.lua`'s single scheduler calls `Voice.sample()` on `Config.voice.interval`, but only while the HUD is visible and `Config.voice.enabled`/`elements.mic` are both true. A sample reads the talking native directly, then calls `exports[Config.voice.resource]:getTalkingMode()` in a `pcall` — swapping voice resources can remove the range display, but can never take down the mic icon.

## Terms used on this page

| Term | Meaning |
| --- | --- |
| Talking (boolean) | Read every sample from `NetworkIsPlayerTalking(PlayerId())` — independent of any voice resource. |
| Mode (proximity label) | Optional, sourced entirely from `Config.voice.resource`'s `getTalkingMode` export. |

## Functions

One contract function, implemented by the voice resource, not by kora_hud.

### `exports.<Config.voice.resource>:getTalkingMode()`

Not a kora_hud export — the reverse: kora_hud calls this on whichever resource `Config.voice.resource` names (default `"kora_voice"`), inside a `pcall`, every `Config.voice.interval` ms while the mic is sampled. Implement it on your own voice resource to show a proximity-range label next to the mic icon.

**Parameters**



**Returns**

- **mode** — `{ index, name, label, range }` (index ≥ 1, range ≥ 0) or anything falsy/invalid. An invalid shape (e.g. `index < 1` or a missing `range`) is treated as "no mode" by `client/voice.lua`'s own normaliser.

**Example**

```lua
-- inside your voice resource
exports('getTalkingMode', function()
    return { index = 1, name = 'normal', label = 'Normal', range = 10.0 }
end)
```

**Representative console output**

```text
kora_hud's mic indicator shows the "Normal" range label; `kora_hud:vitals.voiceMode` carries `{ index = 1, name = 'normal', label = 'Normal', range = 10 }`.
```

## Limits and related APIs

`Config.voice.enabled = false` removes the mic element's sampling entirely, independent of whether `elements.mic` is set. A voice resource that errors or returns a malformed table simply loses the range label for that sample — never an exception the HUD has to handle.

## Related guides

- [Legacy compat events](./compat.md)
