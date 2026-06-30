# Creature — Godot 4 (SC2-inspired)

Local-first 3D port pivoting from the web Creature game. Isometric RTS camera with procedural worm assets.

**Current scope:** default worm, fluid movement, A* pathfinding, **Supabase session save** (restore last position on return). Name-only HUD + pain test button. No health/stamina, fight, eat, or live multiplayer.

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (Forward+)
- Supabase project with anonymous auth enabled (same as web client)

## Run

1. Open Godot → **Import** → `creature-godot/project.godot`
2. Press **F5**

Boot chain:

```
main.gd _ready()
  → await NetworkService.boot()     # auth + load/create creatures row
  → world_map.spawn_player()        # spawn at saved x,y
  → camera follow
```

Expected toasts: **"New player saved to server"** or **"Restored save from server"**.

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| **pain test** (top-right) | 30s stress test |
| Pinch / mouse wheel | Zoom camera |
| WASD / screen edge | Pan camera |

## Features

| Feature | Status |
|---------|--------|
| Default worm (procedural capsules + slither) | Done |
| Fluid movement + A* pathfinding | Done |
| Supabase anonymous session + position save | Done |
| Top stat bar (name only) | Done |
| Mobile web tap + pinch | Done |
| Pain test stress button | Done |
| Health / stamina | **Removed** |
| Creature create / fight / eat / AI / minimap | Removed or bypassed |
| Other players visible | Not started |

## Supabase session save

[`scripts/autoload/network_service.gd`](scripts/autoload/network_service.gd):

| Step | What |
|------|------|
| Auth | Anonymous sign-in or refresh; session persisted |
| Load | `GET /rest/v1/creatures?user_id=eq.<uuid>` |
| Create | Insert row on first visit (defaults from `GameConfig.default_player_data()`) |
| Save | Debounced `PATCH {x, y}` on move; flush when path completes |

**Session storage:**

| Platform | Location |
|----------|----------|
| Editor / desktop | `user://supabase_session.json` |
| Web export | `localStorage` key `creature_supabase_session` via `CreatureNet` |

**Web export:** Supabase HTTP uses browser `fetch` in [`web/custom_shell.html`](web/custom_shell.html) (`window.CreatureNet`) — not Godot `HTTPRequest`. Re-export after editing the shell.

**Export setting:** `progressive_web_app/ensure_cross_origin_isolation_headers=false` in [`export_presets.cfg`](export_presets.cfg) (COI blocks third-party fetch from wasm).

**DB appearance:** inserts use `"cute"` (schema constraint); client renders worm. Optional SQL: [`../supabase/migration-godot-session.sql`](../supabase/migration-godot-session.sql).

Keys: [`scripts/config.gd`](scripts/config.gd) (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — same publishable key as [`../js/config.example.js`](../js/config.example.js).

## Worm mesh

Procedural in [`scripts/units/creature.gd`](scripts/units/creature.gd). Segments along local +Z; each capsule rotated 90° on X; **`body_root` must not rotate 90° on X** (snowman bug). Tune `SEGMENT_SPECS`.

## Movement and pathfinding

- [`scripts/units/creature.gd`](scripts/units/creature.gd) — continuous waypoint movement, smooth rotation
- [`scripts/world/grid_nav.gd`](scripts/world/grid_nav.gd) — A* with 8 neighbors, obstacle avoidance, path simplification

## Pain test

[`scripts/debug/pain_test.gd`](scripts/debug/pain_test.gd) — 20 wandering worms + 50 props for 30s. Top-right HUD button.

## Key files

| File | Role |
|------|------|
| `scripts/main.gd` | Async boot, pointer forwarding |
| `scripts/autoload/network_service.gd` | Supabase REST + web bridge |
| `scripts/autoload/game_state.gd` | Player data, creatures |
| `scripts/world/world_map.gd` | Map + `spawn_player()` |
| `scripts/units/creature.gd` | Worm mesh + movement |
| `scripts/world/grid_nav.gd` | Pathfinding |
| `scripts/ui/sc2_hud.gd` | Name bar + pain test |
| `web/custom_shell.html` | PWA shell, dev mode, **CreatureNet** |

## Web export

1. **Project → Export… → Web** → `web/index.html`
2. Edit `custom_shell.html` only — re-export to apply
3. Serve: `python serve-web-https.py` → `https://<wifi-ip>:8443`

Dev mode on `:8443` / `:8080` clears service worker cache (no incognito needed).

## Agent handoff — next tasks

1. Poll/render other players (shared live world)
2. Re-enable customization or new create flow for pivot game
3. Account linking (passkey / email) atop anonymous sessions
4. Worm polish, new gameplay systems for pivot direction

Docs: [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md), [`../docs/supabase-multiplayer-guide.md`](../docs/supabase-multiplayer-guide.md)

Parent repo: [`../README.md`](../README.md)
