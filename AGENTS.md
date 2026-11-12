# kora_hud agent guide

`kora_hud` is the Kora player HUD: a client-only resource that renders gauges, money, job/gang, status effects, a vehicle panel and a managed minimap in its own NUI page, with a per-player layout editor (`/ui`). Layout: `fxmanifest.lua`, `config.lua`, `shared/bridge.lua` (adapter contract), `client/` (`hud.lua` orchestrator and only NUI sender, `uiregistry.lua`, `minimap.lua`, `vehicle.lua`, `voice.lua`, `stress.lua`, `seatbelt_sound.lua`, `compat.lua`, `bridge/kora_core.lua`, `bridge/stub.lua`), `fft_hooks.lua` (optional test hooks), `web/` (React NUI source; `web/build` is committed), `stream/` (square minimap mask), `tools/`, `test/smoke/` (offline Lua regression) and `tests/` (kora_qa feature files). There is no server script and no database use.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and the layout editor.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
