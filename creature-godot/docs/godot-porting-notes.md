# Godot porting notes

Maps the web Creature client to the Godot 4 project in `creature-godot/`.

## File mapping

| Web | Godot |
|-----|-------|
| [`js/game.js`](../js/game.js) | [`scripts/autoload/game_state.gd`](../scripts/autoload/game_state.gd), [`scripts/units/creature.gd`](../scripts/units/creature.gd) |
| [`js/api.js`](../js/api.js) | [`scripts/autoload/network_service.gd`](../scripts/autoload/network_service.gd) |
| [`js/eyes.js`](../js/eyes.js) | [`scripts/units/creature_eyes.gd`](../scripts/units/creature_eyes.gd) |
| [`js/renderer.js`](../js/renderer.js) | [`scripts/units/creature.gd`](../scripts/units/creature.gd) (meshes/materials) |
| [`js/main.js`](../js/main.js) | [`scripts/main.gd`](../scripts/main.gd), [`scripts/ui/creature_create.gd`](../scripts/ui/creature_create.gd) (legacy, bypassed) |
| [`supabase/schema.sql`](../supabase/schema.sql) | Same tables when Phase 5 HTTP sync is added |

## Constants

All gameplay constants live in [`scripts/config.gd`](../scripts/config.gd) (`GameConfig` class), copied from `js/game.js`.

## Local vs Supabase (Phase 5)

Today `NetworkService`:

- `ensure_auth()` → fake local session
- `create_creature()` / `update_creature()` → `GameState` + `user://creature_save.json`
- `fetch_all_creatures()` → in-memory `GameState.creatures`

To go online, implement HTTP in `network_service.gd`:

1. `POST /auth/v1/signup` with `{ "data": {} }` for anonymous (or reuse stored refresh token in `user://session.json`)
2. `GET/POST/PATCH/DELETE` on `/rest/v1/creatures` with headers `apikey` + `Authorization: Bearer <access_token>`
3. Poll every 1.5s like web `pullCreatures()`, or enable Realtime channel

Use the same publishable key as [`js/config.example.js`](../../js/config.example.js).

## SC2 presentation (original)

- Camera: [`scripts/camera/rts_camera.gd`](../scripts/camera/rts_camera.gd) — ~54° pitch, 45° yaw, follow + edge pan
- UI theme: [`assets/themes/sc2_theme.tres`](../assets/themes/sc2_theme.tres)
- HUD: [`scenes/ui/sc2_hud.tscn`](../scenes/ui/sc2_hud.tscn)

## Boot flow (current)

- `project.godot` → `run/main_scene = res://scenes/main.tscn` (no create screen)
- `GameState._ready()` → `GameConfig.default_player_data()` if `player_data` empty
- `world_map.gd` → `_spawn_player()` instantiates `creature.tscn`, calls `setup()`
- Default appearance: worm only; color/name from `GameConfig`

## Known gaps vs web

- No shared world with browser clients yet
- Passkey persistence (Phase 2) not implemented
- Fight RLS on Supabase may need RPC before online combat (see multiplayer guide)
