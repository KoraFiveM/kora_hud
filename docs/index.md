---
title: kora_hud
sidebar_position: 1
---

# kora_hud

`kora_hud` is the Kora player HUD. It draws radial gauges (health, armour, stamina, hunger, thirst, stress), cash and bank, job and gang, a microphone indicator, active status effects and a vehicle panel (speed, fuel or charge, engine, headlights, seatbelt, race harness) in its own `kora_lib` / `kora_theme` NUI page. It also manages the minimap layout, gives players a layout editor (`/ui`), plays seatbelt sounds, raises stress from fast driving and shooting, and answers the stock `qb-hud` client events (the resource declares `provide 'qb-hud'`).

Version: see `version` in `fxmanifest.lua`.

## Features

- **Gauges and panels** - health and armour (always present), stamina, hunger and thirst, stress, plus job/gang, cash/bank and the microphone pill. Individual elements are switched with `Config.hud.elements`. See [UI](./ui.md).
- **Dynamic mode** - with `Config.hud.dynamic` gauges only show while they differ from their neutral value.
- **Vehicle panel** - speed (km/h or mph), fuel (or charge for electric vehicles, classified by `kora_fuel`), engine, headlights, seatbelt and race harness icons. Shown only in a vehicle.
- **Status effects** - effects from `Kora.status.getActive()` are listed with their severity.
- **Voice indicator** - reads `NetworkIsPlayerTalking`; if `Config.voice.resource` exports `getTalkingMode`, the mode and range are shown too.
- **Minimap management** - visibility mode, per-player toggle, "minimap only in vehicle", square/circle/stock shape with a streamed mask. See [Minimap](./api/minimap.md).
- **Layout editor** - `/ui` (or `/hudlayout`) lets each player move, resize, align and hide HUD sections and elements registered by other resources. Saved client-side. See [UI editor](./ui-editor.md).
- **Seatbelt sounds** - buckle/unbuckle sound for the local player. See [Configuration](./configuration.md).
- **Stress gain** - client-side stress from speeding and shooting. See [Stress](./api/stress.md).
- **qb-hud compatibility** - display-only handlers for stock `hud:client:*` events and the `/cash` and `/bank` commands. See [Compatibility](./api/compat.md).

This resource has no server scripts, no database tables, no items and no ACE permissions. All state a player changes (layout, minimap choice) is stored in the player's own client KVP.

## Documentation map

- [Installation](./installation.md) - legacy install guide plus manifest and runtime dependencies, stub adapter, web build.
- [How to use](./how-to-use.md) - NUI data channels, callbacks, `Config` tables and integration examples.
- [Commands](./commands.md) - every command with examples, plus the code-derived command table and key bindings.
- [API reference](./api/index.md) - all client exports, with the summary of every export.
  - [HUD visibility](./api/visibility.md) - `hide`, `show`, `isVisible`.
  - [Layout](./api/layout.md) - `getLayout` and how layouts are stored and validated.
  - [UI element registry](./api/ui-registry.md) - register your own element in the `/ui` editor.
  - [Minimap](./api/minimap.md) - `applyMinimapLayout`, visibility rules, managed layout options.
  - [Legacy compat events](./api/compat.md) - qb-hud `hud:client:*` events and the `/cash` and `/bank` commands.
  - [Voice integration](./api/voice-integration.md) - the `getTalkingMode` contract.
  - [Stress gain](./api/stress.md) - how stress is gained and persisted, and the `stressGained` event.
- [Configuration](./configuration.md) - every `config.lua` option and its default.
- [Events](./events.md) - events the resource listens for and raises, NUI callbacks, state bags.
- [UI](./ui.md) - what the HUD shows and how elements behave.
- [UI editor](./ui-editor.md) - `/ui`, `/hudlayout`, storage and registering your own element.
- [Bridge](./bridge.md) - the adapter contract between the HUD and a framework.
- [Troubleshooting](./troubleshooting.md) - common problems.
