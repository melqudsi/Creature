# Creature — Godot 4 (SC2-inspired)

Local-first 3D port pivoting from the web Creature game. Isometric RTS camera with procedural worm assets.

**Current scope:** default worm, fluid movement, A* pathfinding, **Supabase session save**, **live field** (other players via 1.5s REST poll). Camera starts fully zoomed in. Name-only HUD + pain test button. PWA supports portrait and landscape. No health/stamina, fight, eat, or customization.

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (Forward+)
- Supabase project with anonymous auth enabled (same as web client)

## Run

1. Open Godot → **Import** → `creature-godot/project.godot`
2. Press **F5**

Boot chain:

```
main.gd _ready()
  → await NetworkService.boot()              # auth + load/create creatures row
  → world_map.spawn_player()                 # spawn at saved x,y
  → NetworkService.start_creature_poll(...)  # when online
  → camera follow
```

Boot is silent on success (no save/restore toasts). Offline boot toasts **"Could not reach server — starting locally"**.

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| **pain test** (top-right) | 30s stress test |
| Pinch / mouse wheel | Zoom camera (starts fully zoomed in) |
| WASD / screen edge | Pan camera |

## Features

| Feature | Status |
|---------|--------|
| Default worm (procedural capsules + slither) | Done |
| Fluid movement + A* pathfinding | Done |
| Supabase anonymous session + position save | Done |
| Live field: poll + render other players | Done |
| Top stat bar (name only) | Done |
| Mobile web tap + pinch | Done |
| PWA portrait + landscape (no forced landscape) | Done |
| Pain test stress button | Done |
| Health / stamina | **Removed** |
| Creature create / fight / eat / AI / minimap | Removed or bypassed |

## Supabase session save

[`scripts/autoload/network_service.gd`](scripts/autoload/network_service.gd):

| Step | What |
|------|------|
| Auth | Anonymous sign-in or refresh; session persisted |
| Load | `GET /rest/v1/creatures?user_id=eq.<uuid>` |
| Create | Insert row on first visit (defaults from `GameConfig.default_player_data()`) |
| Save | Debounced `PATCH {x, y}` on move; flush when path completes |
| Poll | `GET /rest/v1/creatures?select=*` every 1.5s → `world_map.sync_remote_creatures()` |

**Session storage:**

| Platform | Location |
|----------|----------|
| Editor / desktop | `user://supabase_session.json` |
| Web export | `localStorage` key `creature_supabase_session` via `CreatureNet` |

**Web export:** Supabase HTTP uses browser `fetch` in [`web/custom_shell.html`](web/custom_shell.html) (`window.CreatureNet`) — not Godot `HTTPRequest`. Re-export after editing the shell.

**Export settings** ([`export_presets.cfg`](export_presets.cfg)):

| Setting | Value |
|---------|-------|
| COI headers | **Off** (`ensure_cross_origin_isolation_headers=false`) |
| PWA orientation | **Any** (`orientation=0`) |

Godot re-export may flip these — verify after each export.

**DB appearance:** inserts use `"cute"` (schema constraint); client renders worm. Optional SQL: [`../supabase/migration-godot-session.sql`](../supabase/migration-godot-session.sql).

Keys: [`scripts/config.gd`](scripts/config.gd) (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — same publishable key as [`../js/config.example.js`](../js/config.example.js).

## Live multiplayer (Godot)

Mirrors web polling (`GameConfig.POLL_OTHERS_SEC` = 1.5):

1. `NetworkService.start_creature_poll(world_map)` after boot when online
2. `world_map.sync_remote_creatures(rows)` — spawn/update/remove by `user_id` (skips local player)
3. Remote worms: `is_remote=true`, interpolate to server `{x,y}`, no selection ring, no local pathfinding

Test: two editor instances, or editor + phone on `https://<wifi-ip>:8443`.

## Worm mesh

Procedural in [`scripts/units/creature.gd`](scripts/units/creature.gd). Segments along local +Z; each capsule rotated 90° on X; **`body_root` must not rotate 90° on X** (snowman bug). Tune `SEGMENT_SPECS`.

## Movement and pathfinding

- [`scripts/units/creature.gd`](scripts/units/creature.gd) — continuous waypoint movement, smooth rotation; `_process_remote()` for other players
- [`scripts/world/grid_nav.gd`](scripts/world/grid_nav.gd) — A* with 8 neighbors, obstacle avoidance, path simplification

## Pain test

[`scripts/debug/pain_test.gd`](scripts/debug/pain_test.gd) — 20 wandering worms + 50 props for 30s. Top-right HUD button.

## PWA / mobile orientation

- Manifest: [`web/manifest.webmanifest`](web/manifest.webmanifest) — `orientation: any`
- Shell: [`web/custom_shell.html`](web/custom_shell.html) — **no** `screen.orientation.lock('landscape')`, **no** fullscreen retry on `orientationchange` (causes flashing when returning to portrait)
- After manifest changes: remove and re-add to home screen on iOS

## Key files

| File | Role |
|------|------|
| `scripts/main.gd` | Async boot, pointer forwarding, starts creature poll |
| `scripts/autoload/network_service.gd` | Supabase REST, web bridge, poll loop |
| `scripts/autoload/game_state.gd` | Player data, creatures registry |
| `scripts/world/world_map.gd` | Map, `spawn_player()`, `sync_remote_creatures()` |
| `scripts/units/creature.gd` | Worm mesh, movement, remote interpolation |
| `scripts/world/grid_nav.gd` | Pathfinding |
| `scripts/camera/rts_camera.gd` | Tap-to-move, zoom (starts at `zoom_min`) |
| `scripts/ui/sc2_hud.gd` | Name bar + pain test |
| `web/custom_shell.html` | PWA shell, dev mode, **CreatureNet** |

## Web export

1. **Project → Export… → Web** → `web/index.html`
2. Edit `custom_shell.html` only — re-export to apply
3. Verify `export_presets.cfg`: COI off, orientation any
4. Serve: `python serve-web-https.py` → `https://<wifi-ip>:8443`

Dev mode on `:8443` / `:8080` clears service worker cache (no incognito needed).

## Agent handoff — next tasks

1. Remote player names on HUD / minimap
2. Re-enable customization or new create flow for pivot game
3. Account linking (passkey / email) atop anonymous sessions
4. Fight/eat ported to Godot (if pivot needs them)
5. Worm polish, new gameplay systems for pivot direction

Docs: [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md), [`../docs/supabase-multiplayer-guide.md`](../docs/supabase-multiplayer-guide.md)

Parent repo: [`../README.md`](../README.md)
