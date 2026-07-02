# Godot porting notes

Maps the web Creature client to the Godot 4 project in `creature-godot/`.

> **📄 GAME DESIGN — READ FIRST:** the authoritative gameplay spec is **`Multiplayer Alien Shapeshifting Prototype.pdf`** in the repo root. Read it before touching gameplay.

## Slice 1 — shapeshifting prototype

Forms, shapeshifting, landfill spawn/respawn, the kill matrix, and shared/persistent interactive objects are implemented (Phase 1 of the PDF).

| Component | Role |
|-----------|------|
| `scripts/forms/form_defs.gd` | `FormDefs` — per-form speed/radius/kind/visual, `resolve_player_death()` kill matrix, death lines |
| `scripts/forms/object_mesh.gd` | `ObjectMesh` — procedural meshes shared by forms and world props |
| `scripts/world/world_object.gd` | `WorldObject` — props + shared-state fields (`object_id`, `type_key`, `spawn_tile`) |
| `scripts/world/world_map.gd` | `sync_world_objects()` reconciles shared objects; `spawn_explosion()` FX |
| `scripts/units/creature.gd` | forms/collision/shapeshift/death; possession sync; `apply_remote_state()` snaps on big jumps |
| `scripts/autoload/network_service.gd` | `world_objects` fetch/seed/possess/release + graceful missing-table detection |

**Shared world objects (Fix pass):** backed by Supabase `public.world_objects` (see `supabase/migration-world-objects.sql`, **must be run**; schema.sql also carries it). Rows: `{id, type (object key), x, y (tile coords), state ('idle'|'possessed'), possessed_by}`. Polled on the same ~1.5s cadence as creatures (right after the creature poll, so the possession-liveness check sees the freshest creature set).

- **No duplicate:** a `possessed` object whose controller is a currently-seen creature is hidden as a standalone prop (the possessing player's synced form represents it).
- **Persistence:** popping out releases the object `idle` at the drop tile → renders for everyone from shared state; survives disconnect because state is server-side. An object possessed by a controller with no creature row is shown idle again.
- **Graceful degradation:** the client probes the table on its first world-object poll; if missing it logs a notice and keeps client-local config objects (`_fallback_interactive`). Seeding: if the table exists but is empty, the first client seeds it from `GameConfig.interactive_objects()`.
- **Kills stay CLIENT-LOCAL** (each client only kills its own player); shared state only governs where objects are and who possesses them.

Other Slice-1 refinements: top-banner toasts, bottom-left region label (`GameConfig.region_for_tile()`), object forms rendered 1:1 with their world prop (`Creature._form_body_scale()`), remote death teleport (`REMOTE_SNAP_TILES`), and a bigger/brighter propane explosion that lingers before respawn (`EXPLODE_RESPAWN_DELAY`).

## Slice 2 — money system

Physical money + transport forms (Steps 3 & 4 of the PDF), built on the Slice 1 world-object sync.

**Data model.** Money objects reuse `public.world_objects` as new `type` values (`money_stack`, `money_bag`, `vault`) — no new table. Carried money = `state='carried'` with `possessed_by = <carrier user_id>` (no separate `carried_by` column needed). The only new column is **`owner_name`** (bag/vault labels), added by **`supabase/migration-money.sql`** (also folded into `schema.sql`). `NetworkService` detects the column from any fetched row (`_note_world_object_columns`) and strips it from writes when absent, so **money fully works without the migration** (only persistent owner labels degrade). `_ensure_slice2_seed()` top-up-seeds the money + bus objects once for worlds seeded before Slice 2.

| Component | Slice 2 role |
|-----------|--------------|
| `form_defs.gd` | `CART` + `BUS` forms; `CARRY_CAPS` + `carry_check()` (capacity / vault-only-bus / no-mixing); `TIER_*` + `tier_weight()`; extended `resolve_player_death()` (bus/cart kinds) + `explosion_kills()` + `ignores_units()` |
| `object_mesh.gd` | `money_stack` / `money_bag` / `vault` / `bus` procedural meshes |
| `world_object.gd` | money `tier` / `owner_name` / `carried_by`; floating `Label3D` owner label shown by proximity (`_process`, bag/vault only) |
| `world_map.gd` | money/bus `_object_cfg`; `sync_world_objects()` handles `carried` state + remote carried-loot visuals + owner labels; `spawn_money_object()`; `spawn_combine_fx()` |
| `creature.gd` | `_carried` list; `pick_up_nearest()` / `drop_all()` / `_run_combines()` / `_combine_pair()`; `carried_object_ids()` (sync authority); `update_carried_display()`; `_carry_speed_factor()`; drop-on-death in `apply_death()` |
| `network_service.gd` | `carry_world_object()`, `drop_money_object()`, `create_world_object()`, `delete_world_object()`; `owner_name` column detection; Slice 2 top-up seed |
| `sc2_hud.gd` | **Pick Up** / **Drop** buttons (+ `consumes_pointer_at`) |
| `config.gd` | money + bus seeds (`slice2_objects()`), Bus Stop region/rect, landfill claim zone |

**Rules.** Alien carries one stack or one bag (slow); Shopping Cart several stacks or one bag (faster than alien, slower than Altima, can't kill); Altima several stacks or one bag; MATA Bus several bags **or** one vault (crushes alien/altima/cart **only while moving**, dies at buildings/trees + propane, shrugs off potholes). Combine two same-tier idle money → next tier (Stack+Stack=Bag, Bag+Bag=Vault), combiner becomes owner. Steal = carry a bag/vault you don't own into the Landfill claim zone and drop it. Death scatters carried money at the death tile (owner labels preserved) + a fading blood splat for squish deaths. Pop-out drops ALL carried loot at the vehicle; Become re-validates carry rules and drops overflow (`_revalidate_carried_for_form()`).

**Client-local authority (deferred limitation):** combine, steal/claim and kills are all resolved on the acting client, so simultaneous actions on the same money can race. Acceptable for the prototype.

## Slice 3 — BBQ Smoker economy

The money faucet (PDF Step 6) + explosion scatter (Step 5 gap). Design intent: earning is an **active, defendable choice** — the smoker only generates while player-possessed, parked, and near houses, so it creates a spot worth raiding, and a world-wide loose-stack cap (20) makes combining the pressure valve instead of inflation.

| Component | Slice 3 role |
|-----------|--------------|
| `form_defs.gd` | `BBQ_SMOKER` form (kind `"smoker"`: dies to moving bus/explosion, NOT Altima — theft > squish); carry 1 bag / 2 stacks |
| `config.gd` | `SMOKER_GEN_*`, `MONEY_STACK_WORLD_CAP`, `SMOKE_CLOUD_*`, `BBQ_CORNER_RECT` + `BUS_STOP_RECT` regions, `is_near_building()` |
| `creature.gd` | `_update_smoker_economy()` (parked money gen, cap + hint toasts), `_deploy_smoke_cloud()` special |
| `world_map.gd` | `smoke_cloud` row interception in `sync_world_objects()` (never becomes a `WorldObject`; remaining life from `updated_at`; stale-row cleanup), `register_smoke_cloud()` + `_process()` concealment pass, `_scatter_money()` on explosions |
| `object_mesh.gd` | `smoker` trailer mesh (barrel + chimney + wheels) |
| `sc2_hud.gd` | per-form Special button text (Speed Burst / Smoke Cloud) |

**Smoke cloud sync trick:** clouds are transient `world_objects` rows (`type='smoke_cloud'`) — zero schema changes. The deployer creates the row, registers the visual locally, and deletes the row after the duration; other clients register it from the poll with remaining life computed from `updated_at`, and ANY client deletes a stale cloud row whose deployer died/disconnected. Concealment (remote creatures + loose money invisible inside a cloud) is a per-frame visibility pass in `WorldMap._process()` — kill checks intentionally still work inside smoke (a bus lurking in smoke is funny and legal).

### Sync-robustness layer (post-playtest — read before touching sync)

The 1.5s poll + in-flight REST writes race each other; these mechanisms keep clients converged (all in `world_map.gd` unless noted):

- **`_local_authority`** — ids the local player just changed (pickup/drop/pop-out/repair) skip server rows for ~6s while the PATCH lands. Registered from `creature.gd` via `_note_local_authority()`. Anti-flicker.
- **`_tombstones`** — ids deleted locally (combines) are ignored ~15s so a stale poll can never resurrect them. Skipping this is how one combine used to produce two bags.
- **Per-request web bridge** (`network_service.gd`) — browser fetches are keyed by request id (`_web_request_results`); a single shared pending flag used to cross responses between overlapping requests and silently drop PATCHes (stuck carried money, drifting placements).
- **Self-repair** — a row claiming the local player carries something it doesn't gets PATCHed back to idle; a `possessed` row matching the player's current form on session restore is **re-adopted** (`Creature.adopt_possessed_object()`) instead of rendering a duplicate prop.
- **Absent carriers** — money `carried` by a user with no live creature renders idle (not invisible).
- **Remote vehicles** — interpolation speed and the teleport-snap threshold scale with form speed (`apply_remote_state` / `_process_remote`), so a 3x-speed Altima neither lags behind its server position nor "teleports" every poll; `_resolve_contacts()` only lets a **moving** vehicle kill.
- **Seeding** — first-boot seed + Slice 2 top-up both re-check after a random delay so two clients booting together don't double-seed.
- **Admin recovery (MOE)** — remove all money / spawn stacks / **reset ALL world objects** (full table wipe + re-seed) in the admin panel.

## File mapping

The legacy web client now lives in `_arc/` (archived; repo root belongs to the Godot web export).

| Web (archived) | Godot |
|-----|-------|
| [`_arc/js/game.js`](../../_arc/js/game.js) | [`scripts/autoload/game_state.gd`](../scripts/autoload/game_state.gd), [`scripts/units/creature.gd`](../scripts/units/creature.gd) |
| [`_arc/js/api.js`](../../_arc/js/api.js) | [`scripts/autoload/network_service.gd`](../scripts/autoload/network_service.gd) |
| [`_arc/js/eyes.js`](../../_arc/js/eyes.js) | [`scripts/units/creature_eyes.gd`](../scripts/units/creature_eyes.gd) |
| [`_arc/js/renderer.js`](../../_arc/js/renderer.js) | [`scripts/units/creature.gd`](../scripts/units/creature.gd) (meshes/materials) |
| [`_arc/js/main.js`](../../_arc/js/main.js) | [`scripts/main.gd`](../scripts/main.gd), [`scripts/ui/creature_create.gd`](../scripts/ui/creature_create.gd) (active onboarding/spawn screen) |
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
& "C:\godot47\Godot_v4.7-stable_win64.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --export-release "Web" "../index.html"
```

The export lands in the **repo root** (GitHub Pages serves from `main` root; the old web client was archived to `_arc/`). Push `main` to deploy.

- **GitHub Pages deploy:** the export lands at the **repo root**; Pages serves `main`'s root. Deploy = export → commit changed root files → push `main` (rebuilds in ~1–2 min). **`variant/thread_support` must stay `false`** — Pages can't send COOP/COEP headers, so a threaded build fails in production with "SharedArrayBuffer missing" (local dev servers send the headers, masking it). Keep `.nojekyll` at the root.
- **Responsive display:** base viewport is **720×720** + `stretch/aspect="expand"` (short window side = 720 design units, long side expands; no letterboxing in portrait/landscape/ultrawide). Keep centered UI panels ≤ ~640px wide so portrait never clips them. `rts_camera.gd::_update_aspect_mode()` flips to `KEEP_WIDTH` in portrait so the horizontal 3D view matches landscape.
- **iOS installed-PWA quirks:** (1) stale window size at launch shifts the canvas down until a rotation — fixed by `position: fixed` body + `setupViewportResizeKicks()` in `custom_shell.html` (synthetic `resize` events after start / orientationchange / visualViewport resize / pageshow); (2) notch + rounded corners + home bar clip edge HUD — `CreatureNet.getSafeAreaJson()` reads `env(safe-area-inset-*)` CSS vars and `sc2_hud.gd::_apply_safe_area()` insets the HUD root (css px → design units via ×720/min(vw,vh)). Neither issue reproduces in plain mobile Safari.
- **Export gotchas:** Godot may revert `export_presets.cfg` (`ensure_cross_origin_isolation_headers` back to true, `orientation` off 0, `thread_support` back to true) and re-serialize `project.godot` (dropping a default line). Verify/restore both to keep the git diff clean.
- **Build freshness:** GDScript compiles to `.gdc` bytecode, so string literals are **not** plain-text searchable in `index.pck` — don't grep the `.pck` to check whether a build is fresh; use `CACHE_VERSION` in the repo-root `index.service.worker.js` + file timestamps.
- **PWA cache-busting:** `custom_shell.html`'s `setupServiceWorkerAutoUpdate()` force-activates a newer service worker on reload (Godot's default SW is cache-first / never `skipWaiting()`s). Bump `GameConfig.BUILD_ID` (currently `build 2026-07-02b`; + the `#build-stamp` string in `custom_shell.html`) each shipped build / re-export; it renders bottom-right in the shell and on the onboarding screen so users can confirm freshness.
- **Git on Google Drive:** `git checkout`/`merge` across many files can fail with phantom "File exists" errors (Drive FS lag). Workaround: update refs without touching the tree (`git branch -f main <sha>` + push), or retry `checkout -f` until clean.

## Known gaps vs web

- No fight/eat/stamina in Godot client
- Remote worms visible but names not on HUD/minimap
- Passkey / account linking not implemented; temporary name-claim login is insecure
- Health/stamina removed from Godot client (DB columns remain for legacy web)
