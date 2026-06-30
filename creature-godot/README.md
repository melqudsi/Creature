# Creature — Godot 4 (SC2-inspired)

Local-first 3D port pivoting from the web Creature game. Isometric RTS camera with procedural worm assets.

**Current scope:** onboarding spawn screen (name + color), default worm, fluid movement, A* pathfinding, **Supabase session save**, **live field** (other players via 1.5s REST poll). Camera starts fully zoomed in. Name-only HUD + admin panel with logs. PWA supports portrait and landscape. No health/stamina, fight, eat, or appearance customization.

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (Forward+)
- Supabase project with anonymous auth enabled (same as web client)

## Run

1. Open Godot → **Import** → `creature-godot/project.godot`
2. Press **F5**

Boot chain:

```
main.gd _ready()
  → await NetworkService.boot()              # auth + load existing session profile
  → show onboarding if no profile exists     # name + color
  → world_map.spawn_player()                 # spawn at saved x,y
  → NetworkService.start_creature_poll(...)  # when online
  → camera follow
```

Boot is silent on success (no save/restore toasts). Offline boot toasts **"Could not reach server — starting locally"**.

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| **admin** (top-right) | Pain test controls, profile deletion, logs |
| Pinch / mouse wheel | Zoom camera (starts fully zoomed in) |
| WASD / screen edge | Pan camera |

## Features

| Feature | Status |
|---------|--------|
| Default worm (procedural capsules + slither) | Done |
| Fluid movement + A* pathfinding | Done |
| Supabase anonymous session + position save | Done |
| Live field: poll + render other players | Done |
| Onboarding spawn screen: name + color | Done |
| Admin panel: configurable pain test + profile deletion + logs | Done |
| Top stat bar (name only) | Done |
| Mobile web tap + pinch | Done |
| PWA portrait + landscape (no forced landscape) | Done |
| Health / stamina | **Removed** |
| Creature create / fight / eat / AI / minimap | Removed or bypassed |

## Supabase session save

[`scripts/autoload/network_service.gd`](scripts/autoload/network_service.gd):

| Step | What |
|------|------|
| Auth | Anonymous sign-in or refresh; session persisted |
| Load | `GET /rest/v1/creatures?user_id=eq.<uuid>` |
| Onboarding | If no row exists for the session, ask for name + color |
| Create / claim | Insert a new row, or claim an existing typed name by changing its `user_id` |
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

If auth succeeds but no row exists for the session, `NetworkService.boot()` leaves `GameState.player_data` empty so `main.gd` shows onboarding. Do not recreate the previous behavior that filled `default_player_data()` on successful no-row boot.

**Temporary profile migration:** name-claim login and admin profile deletion require [`../supabase/migration-temp-profile-admin.sql`](../supabase/migration-temp-profile-admin.sql). It is intentionally permissive and should be replaced by passkeys/password phrases before shipping. Admin delete only reports success when Supabase returns at least one deleted row; zero rows usually means RLS blocked the delete or the migration was not applied.

Keys: [`scripts/config.gd`](scripts/config.gd) (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — same publishable key as [`../js/config.example.js`](../js/config.example.js).

## Live multiplayer (Godot)

Mirrors web polling (`GameConfig.POLL_OTHERS_SEC` = 1.5):

1. `NetworkService.start_creature_poll(world_map)` after boot when online
2. `world_map.sync_remote_creatures(rows)` — spawn/update/remove by `user_id` (skips local player)
3. Remote worms: `is_remote=true`, interpolate to server `{x,y}`, no selection ring, no local pathfinding

Test: two editor instances, or editor + phone on `https://<wifi-ip>:8443`. The admin logs show fetched row count and `Remote sync: <other profiles>, <visible>` when those counts change.

## Worm mesh

Procedural in [`scripts/units/creature.gd`](scripts/units/creature.gd). Segments along local +Z; each capsule rotated 90° on X; **`body_root` must not rotate 90° on X** (snowman bug). Tune `SEGMENT_SPECS`.

## Movement and pathfinding

- [`scripts/units/creature.gd`](scripts/units/creature.gd) — continuous waypoint movement, smooth rotation; `_process_remote()` for other players
- [`scripts/world/grid_nav.gd`](scripts/world/grid_nav.gd) — A* with 8 neighbors, obstacle avoidance, path simplification

## Pain test

[`scripts/debug/pain_test.gd`](scripts/debug/pain_test.gd) — configurable wandering worms + props for 30s. Launched from the top-right **admin** panel.

## Admin Logs

`GameState.add_admin_log()` stores the last 80 log lines and `sc2_hud.gd` renders them in **admin → Logs**. Current logs cover:

- Boot path: restored profile vs no profile/onboarding
- Supabase fetch failures and fetched creature row count
- Profile create/claim/delete attempts and RLS-like zero-row deletes
- Remote sync count changes

## Map

`GameConfig` sets a **32×24** map with 16 tree tiles and 6 building tiles. `GameState.blocked_tiles` includes trees and buildings; `world_map.gd` renders both as simple procedural props.

Buildings use a box body, two sloped `BoxMesh` roof panels, and a door. Avoid using the earlier single rotated `PrismMesh` roof; it looked like a giant wedge/needle on mobile.

## PWA / mobile orientation

- Manifest: [`web/manifest.webmanifest`](web/manifest.webmanifest) — `orientation: any`
- Shell: [`web/custom_shell.html`](web/custom_shell.html) — **no** `screen.orientation.lock('landscape')`, **no** fullscreen retry on `orientationchange` (causes flashing when returning to portrait)
- After manifest changes: remove and re-add to home screen on iOS

## Key files

| File | Role |
|------|------|
| `scripts/main.gd` | Async boot, onboarding, pointer forwarding, starts creature poll |
| `scripts/autoload/network_service.gd` | Supabase REST, web bridge, profile create/claim/delete, poll loop, admin logs |
| `scripts/autoload/game_state.gd` | Player data, creatures registry, admin log buffer |
| `scripts/world/world_map.gd` | Map, `spawn_player()`, `sync_remote_creatures()` |
| `scripts/units/creature.gd` | Worm mesh, movement, remote interpolation |
| `scripts/world/grid_nav.gd` | Pathfinding |
| `scripts/camera/rts_camera.gd` | Tap-to-move, zoom (starts at `zoom_min`) |
| `scripts/ui/creature_create.gd` | Onboarding name/color screen |
| `scripts/ui/sc2_hud.gd` | Name bar + admin panel/logs |
| `web/custom_shell.html` | PWA shell, dev mode, **CreatureNet** |

## Web export

1. **Project → Export… → Web** → `web/index.html`
2. Edit `custom_shell.html` only — re-export to apply
3. Verify `export_presets.cfg`: COI off, orientation any
4. Serve: `python serve-web-https.py` → `https://<wifi-ip>:8443`

Dev mode on `:8443` / `:8080` clears service worker cache (no incognito needed).

Latest validation command used:

```powershell
& "C:\workspace_C\godot_console.exe" --headless --path "f:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --quit-after 900
```

## Agent handoff — next tasks

1. Replace temporary name-claim login with passkeys/password phrases
2. Remote player names on HUD / minimap
3. Re-enable appearance customization for pivot game
4. Fight/eat ported to Godot (if pivot needs them)
5. Worm polish, new gameplay systems for pivot direction

Docs: [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md), [`../docs/supabase-multiplayer-guide.md`](../docs/supabase-multiplayer-guide.md)

Parent repo: [`../README.md`](../README.md)
