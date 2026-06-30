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
| [`supabase/schema.sql`](../supabase/schema.sql) | Same tables; run [`migration-godot-session.sql`](../supabase/migration-godot-session.sql) for worm appearance |

## Constants

All gameplay constants live in [`scripts/config.gd`](../scripts/config.gd) (`GameConfig` class).

## Supabase (Godot client — session persistence)

[`network_service.gd`](../scripts/autoload/network_service.gd) implements REST + anonymous auth:

1. Load `user://supabase_session.json` (refresh token + user id)
2. Refresh session via `POST /auth/v1/token?grant_type=refresh_token`, or anonymous `POST /auth/v1/signup`
3. `GET /rest/v1/creatures?user_id=eq.<uuid>` — restore last `x`, `y`
4. Insert row on first visit; debounced `PATCH` on movement (~1.5s + flush on path complete)

Same publishable key as [`js/config.example.js`](../../js/config.example.js). See [`docs/supabase-multiplayer-guide.md`](../../docs/supabase-multiplayer-guide.md).

**Not implemented yet:** polling other players, fight/eat, events inbox.

## Boot flow (current)

```
main.gd _ready()
  → await NetworkService.boot()   # auth + load/create creature row
  → world_map.spawn_player()      # spawn at saved x,y
  → camera follow
```

## Known gaps vs web

- No shared live world (other players not rendered)
- Passkey / account linking not implemented
- Health/stamina removed from Godot client (DB columns remain for legacy web)
