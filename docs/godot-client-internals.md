# Godot client internals: code map, UI, input, gotchas

> Read this when working **inside the Godot client**: which script owns what, HUD/UI, onboarding, camera/input, meshes, and the engine gotchas that have bitten before.

Godot **4.7+**, Forward+. Main scene `scenes/main.tscn`. Use `class_name` + typed references (generic `Node3D` + `grid_pos` causes inference errors).

## Key files (all under `creature-godot/`)

| File | Role |
|------|------|
| `scripts/config.gd` | `GameConfig`: constants, `BUILD_ID`, Supabase URL/key, regions, seeding helpers, `default_player_data()` |
| `scripts/main.gd` | Async boot, onboarding/world entry, input forwarding, idle logout |
| `scripts/autoload/game_state.gd` | Shared runtime state, registries (`world_objects`, creatures), signals, toasts, `free_drop_tile()` |
| `scripts/autoload/network_service.gd` | Supabase auth/REST, polling, seeds/top-ups/reset, announcements, `CreatureNet` web bridge |
| `scripts/forms/form_defs.gd` | `FormDefs`: per-form speed/radius/kind/visual, carry rules, kill matrix, death lines |
| `scripts/forms/object_mesh.gd` | `ObjectMesh`: procedural meshes shared by props + shapeshifted players; human rig + `animate_biped` |
| `scripts/units/creature.gd` | Player/remote creature: movement, shapeshift, contacts/kills, carrying, specials, house actions, death |
| `scripts/world/world_map.gd` | Map build, object spawn/sync, explosions, transient FX, occlusion fade, safe-house index |
| `scripts/world/world_object.gd` | Shared object node: money labels, safe-house/Big-House segments, window glow, occlusion fade |
| `scripts/world/memphis_layout.gd` | `MemphisLayout`: regions, roads, landmarks, scatter (fixed seed) |
| `scripts/world/grid_nav.gd` | A* pathfinding (8-dir, LOS simplification) around `GameState.blocked_tiles` (a Dictionary — perf) |
| `scripts/world/npc_traffic.gd` / `npc_humans.gd` / `zoo_animals.gd` | Client-local NPCs (traffic / pedestrians / zoo) |
| `scripts/camera/rts_camera.gd` | Tap-to-move, pinch/wheel zoom, follow, death/abduction zoom |
| `scripts/ui/sc2_hud.gd` (+ `scenes/ui/sc2_hud.tscn`) | HUD buttons, menu dropdown, announcement popup, admin panel, respawn choice, toasts |
| `scripts/ui/creature_create.gd` / `pattern_pad.gd` | Onboarding (login/register/continue) + 3×3 pattern lock |
| `scripts/debug/pain_test.gd` | Mobile stress-test spawner |
| `web/custom_shell.html` | PWA shell, splash/loading UI, dev mode, `CreatureNet` fetch/localStorage bridge |
| `export-web.ps1` / `export_presets.cfg` | Web export helper / preset |

## HUD (`sc2_hud.gd`)

- Action buttons live in `$ActionBar` (tscn): Become, Special, Pop Out, Pick Up, Drop, Steal, Eat, House (contextual Upgrade/Take Vault/Rob — driven by `creature.house_action()` polling in `_process`).
- Top-left **menu button** (code-drawn hamburger icon) → dropdown with Sign Out + MOE-only Admin. Top-right **loudspeaker button** (code-drawn megaphone icon) re-opens the latest announcement. Icons are procedural `ImageTexture`s because the theme font has no emoji/symbol glyphs.
- **Announcement popup** is a `PanelContainer` that auto-sizes to the message (label wrap width ~500px) and re-centers a frame after the text is set (`_center_announcement_panel`).
- **Every tappable control must be registered in `consumes_pointer_at()`** or taps on it will also move the creature.
- Admin panel (MOE only, `_is_admin_player()`): built in code in `_build_admin_panel()`; includes close X, test mode, pain test, money tools, world reset, announcement broadcast, profile list (last-login timestamps) + delete, logs, clear-session.
- Safe-area insets for iPhone notch/home bar applied via `_apply_safe_area()` (CSS px → 720-design-unit conversion).

## Onboarding & input

- Onboarding (`creature_create.gd`): uppercase name (live-uppercased), color palette (no 3D preview), pattern lock (min 4 dots), Continue-as when a session exists.
- Mobile caret gotcha: open the virtual keyboard with `cursor_start`/`cursor_end` at text length; use `KEYBOARD_TYPE_DEFAULT` (NOT `VIRTUAL_KEYBOARD_TYPE_DEFAULT` — 4.7 compile error).
- Tap-to-move fires on **finger down** (solo touch) with emulated-mouse dedupe; input routes `main.gd` → `rts_camera.process_pointer_input()`. Ground pick = raycast on the ground `StaticBody3D` + plane fallback. `emulate_mouse_from_touch=true` stays on.
- Camera: perspective, pitch 38° / yaw 45°, offset scaled by `_desired_distance` (`_camera_offset()`); camera sits to the map's south-east — the **south (+Z) and east (+X) faces of objects are the camera-visible ones** (why houses snap to face south/east). Starts fully zoomed in. Mouse-edge pan is desktop-only.

## Meshes & visuals

- Worm: five overlapping `CapsuleMesh` segments along local +Z on `$Body`; `body_root` must stay at zero rotation (rotating it 90° on X stacks segments into a vertical "snowman"). Tune via `SEGMENT_SPECS` in code, not the scene.
- All props/forms are procedural in `ObjectMesh.build(visual)` — add new visuals there so props and worn forms match 1:1.
- Buildings: box body + flat roof slab (regular houses); the Big House uses a `PrismMesh` gable roof (rotated 90° on Y for a ridge along X). Meshes with self-managed materials (window panes, light beams) carry a `no_fade` meta so the occlusion fade doesn't stomp them.
- Idle animations: local "breathing" vs remote "sway" with per-creature phase offsets; remote facing is seeded per `user_id`.

## Engine / platform gotchas (hard-won — do not rediscover)

1. **Never name methods after engine virtuals** (`_enter_world`, `_exit_world`, `_ready`, `_process`, `_input`, …) — the engine auto-invokes them. World entry is `_begin_world()` for this reason.
2. Worm "snowman" if `body_root` rotated on X (see above).
3. `queue_free()` is deferred — a freed child still passes `is_instance_valid()` in the same frame. Null cached child references (e.g. labels) when rebuilding a node's children.
4. HUD buttons need `focus_mode = FOCUS_NONE` and registration in `consumes_pointer_at()`.
5. Theme font lacks emoji/symbol glyphs — draw icons as procedural `ImageTexture`s.
6. iOS browser fullscreen API doesn't work — PWA Add to Home Screen. Don't call `screen.orientation.lock()` (portrait/landscape flashing).
7. Display: 720×720 base + `stretch/aspect="expand"` (short side = 720 design px); camera flips `KEEP_WIDTH`/`KEEP_HEIGHT` by aspect.
8. PowerShell (this dev shell) doesn't support `&&` — use `;` to chain commands.

## Performance rules

- `GameState.blocked_tiles` is a Dictionary (Array lookup made A* crawl on ~1,600 water tiles).
- Per-frame loops over NPCs must not nest scans (past bug: `npc_humans._check_kills()` ran per human per frame → ~98k distance checks). Keep O(n) per frame.
- Occlusion fade runs at 10Hz, not per frame. Follow that pattern for new periodic scans (deposit checks run at 1Hz).
