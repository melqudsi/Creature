# Godot porting notes

Maps the web Creature client to the Godot 4 project in `creature-godot/`.

## File mapping

| Web | Godot |
|-----|-------|
| [`js/game.js`](../js/game.js) | [`scripts/autoload/game_state.gd`](../scripts/autoload/game_state.gd), [`scripts/units/creature.gd`](../scripts/units/creature.gd) |
| [`js/api.js`](../js/api.js) | [`scripts/autoload/network_service.gd`](../scripts/autoload/network_service.gd) |
| [`js/eyes.js`](../js/eyes.js) | [`scripts/units/creature_eyes.gd`](../scripts/units/creature_eyes.gd) |
| [`js/renderer.js`](../js/renderer.js) | [`scripts/units/creature.gd`](../scripts/units/creature.gd) (meshes/materials) |
| [`js/main.js`](../js/main.js) | [`scripts/main.gd`](../scripts/main.gd), [`scripts/ui/creature_create.gd`](../scripts/ui/creature_create.gd) (active onboarding/spawn screen) |
| [`supabase/schema.sql`](../supabase/schema.sql) | Same tables; run [`migration-godot-session.sql`](../supabase/migration-godot-session.sql) for worm appearance |

## Constants

All gameplay constants live in [`scripts/config.gd`](../scripts/config.gd) (`GameConfig` class).

## Supabase (Godot client — session persistence)

[`network_service.gd`](../scripts/autoload/network_service.gd) implements REST + anonymous auth:

1. Load `user://supabase_session.json` (refresh token + user id)
2. Refresh session via `POST /auth/v1/token?grant_type=refresh_token`, or anonymous `POST /auth/v1/signup`
3. `GET /rest/v1/creatures?user_id=eq.<uuid>` — restore profile + last `x`, `y`
4. If no profile exists, onboarding asks for name + color; successful auth with no row must leave `GameState.player_data` empty
5. `register_or_claim_profile()` inserts a new row, or claims a typed existing name by PATCHing `user_id`. Names are stored/matched in **UPPERCASE** — both `register_or_claim_profile()` and `fetch_creature_by_name()` uppercase the stored value and the `eq` lookup (Postgres `eq` is case-sensitive), deduping case-variant profiles and letting returning users match regardless of typed case. It also forces `GameState.player_data["color"]` to the chosen color on both paths (so the in-game creature isn't stuck at the DB round-trip color); `claim_creature()` also PATCHes the chosen color. `GameConfig.color_from_hex()` is hardened against malformed values
6. Debounced `PATCH` on movement (~1.5s + flush on path complete)

Same publishable key as [`js/config.example.js`](../../js/config.example.js). See [`docs/supabase-multiplayer-guide.md`](../../docs/supabase-multiplayer-guide.md).

**Temporary DB note (applied):** name-claim login and admin profile deletion require [`../../supabase/migration-temp-profile-admin.sql`](../../supabase/migration-temp-profile-admin.sql) (policies `creatures_temp_claim_by_name` + `creatures_temp_admin_delete`), which has been applied to the current project. It is intentionally permissive and **temporary** — replace with passwords/passkeys before shipping. Without it, delete and name-claim silently no-op. Deletes request returned rows and re-fetch the target if Supabase returns an empty body; success means either a deleted row was returned or the row is confirmed gone.

**Not implemented yet:** fight/eat, events inbox, web+Godot unified gameplay rules.

## Live multiplayer (Godot — implemented)

Poll interval: `GameConfig.POLL_OTHERS_SEC` (1.5s), same as web.

| Component | Role |
|-----------|------|
| `network_service.gd` | `fetch_all_creatures()`, `start_creature_poll()`, `_poll_remote_creatures()` |
| `world_map.gd` | `sync_remote_creatures(rows)` — spawn/update/remove by `user_id` |
| `creature.gd` | `is_remote`, `apply_remote_state()`, `_process_remote()` — lerp to server position |

Local player row is skipped (matched by `NetworkService.get_user_id()`). Admin logs show fetched row count and remote-sync counts when they change, which is the first place to check if two simultaneous players do not see each other.

Remote creatures also get a **stable randomized facing** on spawn: `creature.gd`'s `_random_facing_for(user_id)` seeds `rotation.y` per user so idle remotes don't all point the same way (kept fixed unless they walk).

## Idle rest animations

`creature.gd` plays a rest animation when a creature is stationary and awake:

- Local/player: `_apply_idle_local()` — subtle vertical "breathing" undulation (slow, low amplitude)
- Remote/offline: `_apply_idle_remote()` — a distinct slower, wider side-to-side "sway"; never touches `rotation.y` so the spawn facing is preserved
- `_phase_offset` (set in `setup()`) desyncs creatures so they don't animate in lockstep; the asleep breathing behavior is unchanged

## Onboarding / spawn screen (redesigned)

`creature_create.gd` + `creature_create.tscn`:

- **3D creature preview removed** — replaced by a color palette of 52px swatch `Button`s in a `GridContainer`; the selected swatch gets a bright cyan (`#00e5ff`) border (`_apply_swatch_style()`). `GameConfig.CREATURE_COLORS` is an expanded palette led by dark gray (also the default selection).
- **Uppercase names:** live-uppercased while typing and on submit (mirrors `network_service.gd`).
- **Caret:** desktop caret to end on refocus; mobile `DisplayServer.virtual_keyboard_show()` is passed `cursor_start`/`cursor_end` = text length so it opens at the END of existing text (was a mobile-only prepend-only bug at index 0). Use `KEYBOARD_TYPE_DEFAULT`.

## Admin panel diagnostics

The **admin** button and panel are gated to the player whose uppercased name is `MOE` (`sc2_hud.gd` `_is_admin_player()`): the button is hidden for everyone else and `_toggle_admin_panel()` refuses to open for non-MOE sessions.

`GameState.add_admin_log()` stores the last 80 log lines. `sc2_hud.gd` shows them under **admin → Logs** in a read-only `TextEdit`; do not use one `Label` per line because it wrapped after each character on mobile. Current log sources:

- `NetworkService.boot()` logs restored profile vs no profile/onboarding
- `fetch_all_creatures()` logs failures and row count changes
- Profile create/claim/delete logs failures and temporary migration/RLS hints
- `world_map.sync_remote_creatures()` logs remote count changes
- **clear session / reload** removes the saved anonymous session and reloads the scene to test onboarding

## Map/building notes

`world_map.gd` renders buildings procedurally. The current roof is a flat red `BoxMesh` slab with a chimney; avoid reverting to the rotated `PrismMesh` or sloped roof panels, which looked wrong in mobile testing.

## Boot flow (current)

```
main.gd _ready()
  → await NetworkService.boot()              # auth + load existing session profile
  → show onboarding if no profile exists     # name + color, create/claim row
  → _begin_world() → world_map.spawn_player()# reveal HUD, spawn at saved x,y
  → NetworkService.start_creature_poll(...)  # when online
  → camera follow
```

**Engine-virtual naming gotcha (critical):** world entry is `_begin_world()`, not `_enter_world()`. `_enter_world` is a `Node3D` engine virtual — Godot auto-invokes it on tree entry *before* boot/onboarding, which previously spawned a default gray creature, set the `_world_started` guard, and left the HUD hidden (root cause of "creature stuck gray" + "HUD missing for new player"). Never reuse engine-virtual names (`_ready`, `_process`, `_enter_world`, `_exit_world`, `_input`, …) for your own non-override methods.

## Dev environment + web export

- **Filesystem:** the repo lives on a **Google Drive virtual filesystem**; the in-repo `Godot_v4.7/` folder is an unmaterialized stub — do not launch it. Real editor: `C:\godot47\Godot_v4.7-stable_win64.exe` (console: `...win64_console.exe`).
- **Export command** (run import/compile, then export):

```powershell
& "C:\godot47\Godot_v4.7-stable_win64.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --import
& "C:\godot47\Godot_v4.7-stable_win64.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --export-release "Web" "web/index.html"
```

- **Export gotchas:** Godot may revert `export_presets.cfg` (`ensure_cross_origin_isolation_headers` back to true, `orientation` off 0) and re-serialize `project.godot` (dropping a default line). Verify/restore both to keep the git diff clean.
- **Build freshness:** GDScript compiles to `.gdc` bytecode, so string literals are **not** plain-text searchable in `web/index.pck` — don't grep the `.pck` to check whether a build is fresh; use `CACHE_VERSION` in `web/index.service.worker.js` + file timestamps.
- **PWA cache-busting:** `custom_shell.html`'s `setupServiceWorkerAutoUpdate()` force-activates a newer service worker on reload (Godot's default SW is cache-first / never `skipWaiting()`s). Bump `GameConfig.BUILD_ID` (currently `build 2026-07-01c`; + the `#build-stamp` string in `custom_shell.html`) each shipped build / re-export; it renders bottom-right in the shell and on the onboarding screen so users can confirm freshness.

## Known gaps vs web

- No fight/eat/stamina in Godot client
- Remote worms visible but names not on HUD/minimap
- Passkey / account linking not implemented; temporary name-claim login is insecure
- Health/stamina removed from Godot client (DB columns remain for legacy web)
