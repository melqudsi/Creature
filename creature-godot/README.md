# Creature — Godot 4 (SC2-inspired)

Local-first 3D port pivoting from the web Creature game. Isometric RTS camera with procedural worm assets.

> **📄 GAME DESIGN — READ FIRST:** gameplay is defined by **`Multiplayer Alien Shapeshifting Prototype.pdf`** in the repo root (one level up from this folder). Read it before changing gameplay — it is the source of truth for forms, the kill matrix, money, shapeshifting, and the phased build order.

## Slice 1 — shapeshifting prototype

Forms/shapeshifting, landfill spawn, kill matrix, death/respawn, and shared world-object state are implemented. See the root [`README.md`](../README.md#slice-1--shapeshifting-prototype) for the feature overview and Supabase migrations.

## Slice 2 — money system (current)

Money stacks/bags/vaults, pick-up/drop/combine, ownership labels, claim-zone stealing, death drops, and Shopping Cart + MATA Bus forms. See root [`README.md`](../README.md#slice-2--money-system-current). Run [`supabase/migration-money.sql`](../supabase/migration-money.sql) for persistent owner labels (client degrades without it).

Key Slice 2 files:

| File | Role |
|------|------|
| [`scripts/forms/form_defs.gd`](scripts/forms/form_defs.gd) | `carry_check()`, money tiers, cart/bus forms |
| [`scripts/units/creature.gd`](scripts/units/creature.gd) | Pick up / drop / combine / claim / death-drop |
| [`scripts/autoload/network_service.gd`](scripts/autoload/network_service.gd) | `carry_world_object`, `drop_money_object`, `create_world_object`, Slice 2 seed |
| [`scripts/world/world_map.gd`](scripts/world/world_map.gd) | Money object configs, carried sync, combine FX |
| [`scripts/ui/sc2_hud.gd`](scripts/ui/sc2_hud.gd) | Pick Up / Drop buttons |

Key Slice 1 files:

| File | Role |
|------|------|
| [`scripts/forms/form_defs.gd`](scripts/forms/form_defs.gd) | `FormDefs`: per-form speed/radius/kind/visual, kill matrix (`resolve_player_death`), death lines |
| [`scripts/forms/object_mesh.gd`](scripts/forms/object_mesh.gd) | `ObjectMesh`: procedural meshes shared by forms and world props |
| [`scripts/world/world_object.gd`](scripts/world/world_object.gd) | `WorldObject`: interactive/solid props, `consume()`/`respawn_at()`, shared `object_id`/`type_key`/`spawn_tile` |
| [`scripts/world/world_map.gd`](scripts/world/world_map.gd) | Object placement, `sync_world_objects()` (shared state), explosion FX |
| [`scripts/units/creature.gd`](scripts/units/creature.gd) | Forms/collision/shapeshift/death, possession sync, remote form render + teleport-on-large-jump |
| [`scripts/autoload/network_service.gd`](scripts/autoload/network_service.gd) | `world_objects` fetch/seed/possess/release + missing-table detection |
| [`scripts/ui/sc2_hud.gd`](scripts/ui/sc2_hud.gd) | Become / Pop Out / Speed Burst buttons, top-banner toasts, bottom-left region label |

**Notes for agents:**
- **Kills are CLIENT-LOCAL** — a client only decides whether *its own* player dies (remote blast damage is not synced). Keep this in mind before "fixing" cross-player death.
- **Shared world objects:** possession (`possessed`) hides an object as a standalone prop for everyone so the possessing player's synced form isn't duplicated; pop-out releases it `idle` at the drop position (persists across disconnect). Positions in `world_objects` are **tile/grid coords** (like `creatures.x/y`).
- **Remote death = teleport:** `creature.gd` snaps a remote when its position jumps > `REMOTE_SNAP_TILES` tiles in one update (dead players don't "walk" to the dump); normal walking still interpolates.
- **Form scale:** object forms cancel the creature root's `_body_scale` on `body_root` (`_form_body_scale()`) so a shapeshifted object matches its world prop 1:1.

**Current scope:** redesigned onboarding spawn screen (uppercase name + color palette, no 3D preview), default worm with **idle rest animations** (local "breathing" vs remote "sway"), fluid movement, A* pathfinding, **Supabase session save**, **live field** (other players via 1.5s REST poll, each with a stable randomized facing). Camera starts fully zoomed in. Name-only HUD + admin panel (visible only to player `MOE`) with readable logs and clear-session/reload. Player names are forced UPPERCASE (dedupes case-variant profiles). PWA supports portrait and landscape. No health/stamina, fight, eat, or appearance customization.

## Slice 2 — Money system (current)

Physical **money** (Money Stack / Money Bag / Vault) + two **transport forms** (Shopping Cart, MATA Bus), built on top of the Slice 1 world-object sync. See the root [`README.md`](../README.md#slice-2--money-system-steps-3--4-of-the-pdf) for the full feature list and the single **`migration-money.sql`** to run.

- **Money objects reuse `world_objects`** — new `type` values `money_stack`/`money_bag`/`vault` (`_object_cfg()` in `world_map.gd`, meshes in `object_mesh.gd`). Carried money = `state='carried'` + `possessed_by=<carrier uid>`; the optional `owner_name` column stores bag/vault owner labels.
- **Carrying** — `creature.gd` holds `_carried` (player-driven); `carried_object_ids()` is the local authority the sync uses so carried props don't flicker. Capacity/eligibility + the "no mixing stacks with bags" and vault-only-bus rules live in `FormDefs.carry_check()`; carrying applies a weight-based speed penalty (`_carry_speed_factor()`).
- **Combine / steal / drop-on-death** — combining two same-tier idle money merges them one tier up (client-local, `_run_combines()` / `_combine_pair()`), stamping the combiner as owner + a `money_combined` FX. Dropping a bag/vault you don't own inside the landfill claim zone steals it. `apply_death()` scatters carried money at the death tile.
- **New kill matrix** — `FormDefs.resolve_player_death()` adds `bus` (crushes alien/altima/cart, dies at buildings + propane) and `cart` (squished by altima/bus) kinds; `explosion_kills()` now includes cart + bus; `ignores_units()` makes both the Altima and the bus reckless in pathfinding.
- **HUD** — `sc2_hud.gd` adds **Pick Up** (shown when eligible money is in reach) and **Drop** (shown while carrying) buttons; both are added to `consumes_pointer_at()` so they don't leak taps to the map.
- **Graceful degradation** — money works without `migration-money.sql` (only persistent owner labels need it); `NetworkService` detects the `owner_name` column from any fetched row and top-up-seeds the Slice 2 money/bus objects once for pre-Slice-2 worlds.

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
  → _begin_world() → world_map.spawn_player()# reveal HUD, spawn at saved x,y
  → NetworkService.start_creature_poll(...)  # when online
  → camera follow
```

Boot is silent on success (no save/restore toasts). Offline boot toasts **"Could not reach server — starting locally"**.

> **Engine-virtual naming gotcha (critical):** world entry is `_begin_world()`, **not** `_enter_world()`. `_enter_world` is a `Node3D` engine virtual that Godot auto-invokes on tree entry (before boot), which previously spawned a default gray creature, tripped the `_world_started` guard, and left the HUD hidden — the root cause of "creature stuck gray" and "HUD missing for a new player". Never name your own methods after engine virtuals (`_ready`, `_process`, `_enter_world`, `_exit_world`, `_input`…).

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| **admin** (top-right, `MOE` only) | Pain test controls, profile deletion, logs, clear-session/reload |
| Pinch / mouse wheel | Zoom camera (starts fully zoomed in) |
| WASD / screen edge | Pan camera |

## Features

| Feature | Status |
|---------|--------|
| Default worm (procedural capsules + slither) | Done |
| Fluid movement + A* pathfinding | Done |
| Idle rest animations (local "breathing" vs remote "sway") | Done |
| Randomized-but-stable facing for remote players | Done |
| Supabase anonymous session + position save | Done |
| Live field: poll + render other players | Done |
| Onboarding spawn screen: uppercase name + color palette (no 3D preview) | Done |
| Uppercase name rule (dedupes case-variant profiles) | Done |
| Admin panel (MOE-only): configurable pain test + profile deletion + logs | Done |
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
| Create / claim | Insert a new row, or claim an existing typed name by changing its `user_id`. Names are stored/looked up in **UPPERCASE** (`register_or_claim_profile()` + `fetch_creature_by_name()` uppercase both the stored value and the `eq` query), so case-variant duplicates can't be created and returning users match regardless of typed case. Both paths force `GameState.player_data["color"]` to the chosen color (not the DB round-trip) so the in-game creature shows the picked color; `claim_creature()` also PATCHes the color |
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

**Temporary profile migration (applied):** name-claim login and admin profile deletion require [`../supabase/migration-temp-profile-admin.sql`](../supabase/migration-temp-profile-admin.sql) (policies `creatures_temp_claim_by_name` + `creatures_temp_admin_delete`). It has been applied to the current Supabase project. It is intentionally permissive and **temporary** — must be replaced by passkeys/password phrases before shipping. Without it, delete and name-claim silently do nothing. Admin delete requests returned rows, then re-fetches if Supabase returns an empty body; it only reports success when the deleted row is returned or the re-fetch confirms the row is gone.

Keys: [`scripts/config.gd`](scripts/config.gd) (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — same publishable key as [`../js/config.example.js`](../js/config.example.js).

## Live multiplayer (Godot)

Mirrors web polling (`GameConfig.POLL_OTHERS_SEC` = 1.5):

1. `NetworkService.start_creature_poll(world_map)` after boot when online
2. `world_map.sync_remote_creatures(rows)` — spawn/update/remove by `user_id` (skips local player)
3. Remote worms: `is_remote=true`, interpolate to server `{x,y}`, no selection ring, no local pathfinding

Test: two editor instances, or editor + phone on `https://<wifi-ip>:8443`. The admin logs show fetched row count and `Remote sync: <other profiles>, <visible>` when those counts change.

## Onboarding / spawn screen

[`scripts/ui/creature_create.gd`](scripts/ui/creature_create.gd) + [`scenes/ui/creature_create.tscn`](scenes/ui/creature_create.tscn), run before spawning when no profile exists:

- **No 3D creature preview** — replaced by a color palette. Swatches are 52px `Button`s in a `GridContainer`, styled by `_apply_swatch_style()`; the selected swatch gets a bright cyan (`#00e5ff`) border. `GameConfig.CREATURE_COLORS` is an expanded palette led by dark gray, which is also the default selection.
- **Uppercase names:** input is live-uppercased while typing (`_on_name_text_changed()`), and `_on_summon()` uppercases + trims before calling `NetworkService.register_or_claim_profile()`.
- **Caret handling:** desktop caret jumps to the end on refocus (`_place_caret_end()`); the mobile virtual keyboard is opened via `DisplayServer.virtual_keyboard_show()` with `cursor_start`/`cursor_end` = text length so it lands at the END of existing text (fixes the mobile-only prepend-only bug where it opened at index 0). Use `KEYBOARD_TYPE_DEFAULT`, not `VIRTUAL_KEYBOARD_TYPE_DEFAULT` (Godot 4.7 compile error).

## Admin gating

The top-right **admin** button (`sc2_hud.gd`) is only shown when the player's uppercased name is `MOE` (`_is_admin_player()`); `_refresh_stats()` hides it for everyone else and `_toggle_admin_panel()` refuses to open for non-MOE sessions.

## Worm mesh

Procedural in [`scripts/units/creature.gd`](scripts/units/creature.gd). Segments along local +Z; each capsule rotated 90° on X; **`body_root` must not rotate 90° on X** (snowman bug). Tune `SEGMENT_SPECS`.

## Movement and pathfinding

- [`scripts/units/creature.gd`](scripts/units/creature.gd) — continuous waypoint movement, smooth rotation; `_process_remote()` for other players
- [`scripts/world/grid_nav.gd`](scripts/world/grid_nav.gd) — A* with 8 neighbors, obstacle avoidance, path simplification

**Idle rest animations** (in `creature.gd`) play when a creature is stationary and awake:

- Local/player: `_apply_idle_local()` — subtle vertical "breathing" undulation (slow, low amplitude, never translates the creature)
- Remote/offline: `_apply_idle_remote()` — a distinct slower, wider side-to-side "sway"; it never touches `rotation.y` so the spawn facing is preserved
- A per-creature `_phase_offset` (set in `setup()`) desyncs the animations so nearby worms don't move in lockstep; asleep behavior is unchanged
- **Remote facing:** `_random_facing_for(user_id)` seeds a stable randomized `rotation.y` on spawn so idle remote players don't all face the same way (fixed unless they actually walk)

## Pain test

[`scripts/debug/pain_test.gd`](scripts/debug/pain_test.gd) — configurable wandering worms + props for 30s. Launched from the top-right **admin** panel.

## Admin Logs

`GameState.add_admin_log()` stores the last 80 log lines and `sc2_hud.gd` renders them in **admin → Logs** using a read-only `TextEdit`. Avoid returning to per-line `Label` nodes; they wrapped after each character in mobile layout. Current logs cover:

- Boot path: restored profile vs no profile/onboarding
- Supabase fetch failures and fetched creature row count
- Profile create/claim/delete attempts and RLS-like zero-row deletes
- Remote sync count changes
- Clear-session/reload action

## Map

`GameConfig` sets a **32×24** map with 16 tree tiles and 6 building tiles. `GameState.blocked_tiles` includes trees and buildings; `world_map.gd` renders both as simple procedural props.

Buildings use a box body, flat red roof slab, chimney, and door. Avoid using the earlier rotated `PrismMesh` roof or sloped roof panels; both looked wrong on mobile.

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
| `scripts/ui/sc2_hud.gd` | Name bar + admin panel/logs + clear-session button |
| `web/custom_shell.html` | PWA shell, dev mode, **CreatureNet** |

## Web export

> **Dev environment:** the repo is on a **Google Drive virtual filesystem**; the in-repo `Godot_v4.7/` folder is an unmaterialized stub. Use the real editor at `C:\godot47\Godot_v4.7-stable_win64.exe` (console: `...win64_console.exe`).

CLI export — run an import/compile pass, then export:

```powershell
& "C:\godot47\Godot_v4.7-stable_win64.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --import
& "C:\godot47\Godot_v4.7-stable_win64.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --export-release "Web" "../index.html"
```

**The export lands in the REPO ROOT** (GitHub Pages serves from `main` root). Push `main` to deploy.

Or from the editor:

1. **Project → Export… → Web** → `../index.html` (repo root; preset default)
2. Edit `custom_shell.html` only — re-export to apply
3. Verify `export_presets.cfg`: COI off (`ensure_cross_origin_isolation_headers=false`), orientation any (`orientation=0`) — Godot can revert these; also restore `project.godot` if a default line was dropped on export
4. Serve: `python serve-web-https.py` → `https://<wifi-ip>:8443`

Dev mode on `:8443` / `:8080` clears service worker cache (no incognito needed).

**Build freshness / cache-busting:**

- Bump `GameConfig.BUILD_ID` (currently `build 2026-07-01f`) and the matching `#build-stamp` string in `custom_shell.html` on each shipped build (every time you re-export the web build). It renders bottom-right in the shell and on the onboarding screen so users can confirm a fresh load.
- `custom_shell.html` runs `setupServiceWorkerAutoUpdate()` to force-activate a newer service worker on reload (Godot's default SW is cache-first and never `skipWaiting()`s). Skipped on the dev-server path.
- **Do not grep `web/index.pck`** to judge freshness — GDScript compiles to `.gdc` bytecode, so string literals aren't plain-text there. Check `CACHE_VERSION` in `web/index.service.worker.js` and file timestamps instead.

## Agent handoff — next tasks

1. Replace temporary name-claim login with passkeys/password phrases
2. Remote player names on HUD / minimap
3. Re-enable appearance customization for pivot game
4. Fight/eat ported to Godot (if pivot needs them)
5. Worm polish, new gameplay systems for pivot direction

Docs: [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md), [`../docs/supabase-multiplayer-guide.md`](../docs/supabase-multiplayer-guide.md)

Parent repo: [`../README.md`](../README.md)
