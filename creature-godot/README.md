# Creature — Godot 4 (SC2-inspired)

Local-first 3D port of the web Creature game. Isometric RTS camera with original procedural assets — not affiliated with Blizzard.

**Current scope:** spawn a creature and move around the map. Fight, eat, AI, minimap, and portrait panel were intentionally removed.

## Requirements

- [Godot 4.7+](https://godotengine.org/download) (Forward+)

## Run

1. Open Godot → **Import** → `creature-godot/project.godot`
2. Press **F5** (creature create → field)

## Controls

| Input | Action |
|-------|--------|
| Tap / click ground | Move creature |
| Pinch / mouse wheel | Zoom camera |
| WASD | Pan camera |
| Mouse at screen edge | Pan camera |

## Features

- Creature creation: name, color, cute/ugly, 3D preview
- 20×15 grid, trees, movement, stamina regen, AFK sleep
- Top stat bar only (name, HP, stamina)
- Mobile web: virtual keyboard on name field, tap-to-move, pinch zoom

## Key implementation files

| File | Role |
|------|------|
| `scripts/main.gd` | Forwards pointer events to camera |
| `scripts/camera/rts_camera.gd` | Tap, pinch, zoom, ground raycast |
| `scripts/ui/creature_create.gd` | Spawn UI + mobile keyboard |
| `scripts/units/creature.gd` | Unit movement (`class_name Creature`) |
| `scripts/world/world_map.gd` | Map, ground collision, click marker |
| `web/custom_shell.html` | HTML shell — edit this, not `index.html` |

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

### Mobile notes

- **Tap to start** banner in browser dismisses on tap (iOS cannot fullscreen canvas in Safari — use Add to Home Screen)
- PWA: Share → Add to Home Screen (iPhone) or Install app (Android)
- If spawn screen is broken (no colors, summon dead): check Godot output for script compile errors — wrong `DisplayServer` keyboard API breaks `creature_create.gd` entirely

## Multiplayer (future)

`NetworkService` mirrors [`../js/api.js`](../js/api.js). Currently local `GameState` + `user://creature_save.json`. See [`docs/godot-porting-notes.md`](docs/godot-porting-notes.md).

## Project layout

```
scenes/     main, world, creature, UI
scripts/    autoload, units, camera, world, ui
web/        custom_shell.html, export output, manifest
assets/     themes (SC2-inspired UI)
```

Parent repo handoff: [`../README.md`](../README.md)
