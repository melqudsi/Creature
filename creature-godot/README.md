# Creature — Godot 4 (SC2-inspired)

Local-first 3D port of the web Creature game. Isometric RTS camera with original procedural assets — not affiliated with Blizzard.

**Current scope:** boot straight into the map with a default dark-gray alien worm. Tap/click to move, pinch/wheel to zoom. Top stat bar only. No customization, fight, eat, AI, minimap, or portrait.

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (Forward+)

## Run

1. Open Godot → **Import** → `creature-godot/project.godot`
2. Press **F5** — spawns directly into `scenes/main.tscn` (no create screen)

Boot chain:

```
project.godot (main_scene = main.tscn)
  → GameState._ready() loads GameConfig.default_player_data()
  → world_map.gd _spawn_player() instantiates creature.tscn + setup()
  → main.gd binds camera follow to player
```

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| Pinch / mouse wheel | Zoom camera |
| WASD | Pan camera |
| Mouse at screen edge | Pan camera |

## Features

| Feature | Status |
|---------|--------|
| Default worm (procedural capsules + slither) | Done |
| 20×15 grid, trees, movement, stamina regen, AFK sleep | Done |
| Top stat bar (name, HP, stamina) | Done |
| Mobile web tap + pinch | Done |
| Creature create / color picker | Bypassed (scene still in repo) |
| Fight / eat / AI / minimap / portrait | Removed |

## Default player

Defined in `scripts/config.gd` → `GameConfig.default_player_data()`:

- Name: `"Creature"`
- Color: `DEFAULT_CREATURE_COLOR` (~dark gray `Color(0.22, 0.22, 0.26)`)
- Appearance: `"worm"` (only appearance implemented)
- Spawn: map center (`MAP_W/2`, `MAP_H/2`)

To change defaults, edit `default_player_data()` — not the unused create screen.

## Worm mesh (agent notes)

All mesh logic is procedural in `scripts/units/creature.gd`. Scene file `scenes/units/creature.tscn` only provides `$Body` (empty `Node3D`), selection ring, hidden health bar, and FX nodes.

**Layout:**

- Five overlapping `CapsuleMesh` segments, spaced along **local +Z** (head at +Z)
- Each segment: `rotation_degrees = Vector3(90, 0, 0)` — capsule length runs forward along Z
- Rest position: `Vector3(0, radius * 0.92, z)` so the belly sits on the ground
- `body_root` (`$Body`): **no rotation** — position and scale only

**Common mistake (“snowman” bug):** rotating `body_root` 90° on X turns segment Z offsets into world Y, stacking spheres vertically. Fix: rotate each segment, not the body root.

**Tuning:** edit `SEGMENT_SPECS` array (z, radius, length, shade). Overlap segments so gaps do not show. Slither animation in `_apply_slither()` wiggles segment position/rotation; eyes are tiny emissive spheres on the head.

**Health bar:** `HealthBar` node exists for future AI/enemies but stays `visible = false` for the player. Set in both `_ready()` and `setup()` — `_ready()` runs before `is_player` is known.

## Camera and input

`scripts/camera/rts_camera.gd`:

- Pitch ~38°, yaw 45°, follows player creature
- Zoom: `_desired_distance` scales the full `_camera_offset()` vector (moves camera toward subject, not just lowering Y)
- Ground pick: physics raycast on terrain collider; brief click marker via `world_map.show_click_marker()`

`scripts/main.gd` forwards touch/mouse to `rts_camera.process_pointer_input()` from both `_input` and `_unhandled_input` (web emulated mouse).

Project setting: `input_devices/pointing/emulate_mouse_from_touch=true`

## Key implementation files

| File | Role |
|------|------|
| `project.godot` | Main scene, autoloads, touch emulation |
| `scripts/config.gd` | Shared constants + `default_player_data()` |
| `scripts/autoload/game_state.gd` | Player data, creatures dict, stamina/AFK |
| `scripts/main.gd` | Boot wiring, pointer forwarding |
| `scripts/camera/rts_camera.gd` | Tap, pinch, zoom, raycast, follow |
| `scripts/units/creature.gd` | Worm mesh, movement, spawn anim (`class_name Creature`) |
| `scripts/world/world_map.gd` | Map, ground collision, player spawn |
| `scripts/ui/sc2_hud.gd` | Top bar only |
| `web/custom_shell.html` | HTML shell — edit this, not `index.html` |

**Legacy (unused):** `scenes/ui/creature_create.tscn`, `scripts/ui/creature_create.gd` — customization flow bypassed; safe to re-wire if needed.

## Web export

### Preset (`export_presets.cfg`)

| Setting | Value |
|---------|-------|
| Export path | `web/index.html` |
| Custom HTML shell | `res://web/custom_shell.html` |
| Experimental virtual keyboard | On |
| Focus canvas on start | Off |
| PWA | Enabled |

### Steps

1. **Project → Export…** → **Web**
2. Export to `web/index.html`
3. Edit `web/custom_shell.html` for HTML/JS changes — re-export to apply
4. Keep `web/manifest.webmanifest` in place

### Testing after re-export (no incognito)

`serve-web-https.py` (port **8443**) and `serve-web.py` (port **8080**) enable **dev mode** automatically:

- Unregisters service workers
- Clears cached game files
- Disables Godot PWA service worker

Re-export → refresh on phone. No need to clear site data.

| URL flag | Effect |
|----------|--------|
| (default on `:8443` / `:8080`) | Dev mode |
| `?dev=1` | Force dev mode |
| `?dev=0` | Force service workers (test PWA caching) |

**Installed PWA:** close app fully and reopen after re-export.

### Serve

```powershell
cd creature-godot
python serve-web-https.py
```

- Desktop: `https://127.0.0.1:8443/`
- Phone: `https://<wifi-ip>:8443/` (accept cert; allow firewall port 8443)

Godot wasm **does not run** on `http://<LAN-IP>` — HTTPS or localhost only.

Desktop-only HTTP: `python serve-web.py` → `http://localhost:8080`

### Mobile notes

- **Tap to start** banner in browser dismisses on tap (iOS cannot fullscreen canvas in Safari — use Add to Home Screen)
- PWA: Share → Add to Home Screen (iPhone) or Install app (Android)
- If create screen is re-enabled and broken: check Godot output for compile errors — wrong `DisplayServer` keyboard API breaks `creature_create.gd`

## Multiplayer (future)

`NetworkService` mirrors [`../js/api.js`](../js/api.js). Currently local `GameState` + `user://creature_save.json`. See [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md).

## Agent handoff — likely next tasks

1. **Supabase sync** — implement HTTP in `network_service.gd`, poll like web (~1.5s)
2. **Re-add gameplay** — fight/eat removed from Godot; constants still in `GameConfig`
3. **Re-enable customization** — wire `creature_create.tscn` back as main scene or sub-flow
4. **Worm polish** — tune `SEGMENT_SPECS`, add tail taper, better materials/shaders
5. **AI creatures** — `creature_ai.gd` still on scene node but no spawns; re-add via `world_map.gd`

## Project layout

```
scenes/     main, world, creature, UI (hud + legacy create)
scripts/    autoload, units, camera, world, ui
web/        custom_shell.html, export output, manifest
assets/     themes (SC2-inspired UI)
docs/       godot-porting-notes.md
```

Parent repo handoff: [`../README.md`](../README.md)
