---
title: Compatibility
sidebar_position: 12
---

# Compatibility

kora_hud declares `provide 'qb-hud'` and handles the stock client events below. They are display only: they never write server state or metadata (stress gain from `client/stress.lua` is separate, see [Stress](./stress.md)).

| Event | Effect |
| --- | --- |
| `hud:client:UpdateNeeds` (`hunger`, `thirst`) | Overlays hunger and thirst (clamped 0-100) on the local snapshot until the next `kora_core` update replaces them. |
| `hud:client:UpdateStress` (`stress`) | Same overlay for stress. |
| `hud:client:UpdateNitrous` (`level`, `active`) | Stored and sent to the page as `kora_hud:compat`. |
| `hud:client:UpdateHarness` (`uses`) | Stored and sent to the page as `kora_hud:compat`. |
| `hud:client:ToggleHealth`, `ToggleAirHud`, `ToggleShowSeatbelt`, `seatbelt:client:ToggleCruise` | Toggle a flag sent to the page as `kora_hud:compat`. |
| `hud:client:ShowAccounts` (`account`) | Shows the player's own `cash` or `bank` balance as a `kora_lib` notification. Any amount passed is ignored. |
| `hud:client:LoadMap` | Re-applies the minimap layout. |

The shipped web build does not read `kora_hud:compat`, so the nitrous, harness, cruise, altitude, dynamic-health and seatbelt-visibility flags have no visible effect.

`/cash` and `/bank` show the balance from the authoritative snapshot. `hud:server:getMenu` and the `menu`, `dev` and `resethud` commands of stock qb-hud are not provided.
