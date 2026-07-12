# Build, export, deploy & testing

> Read this when you need to **compile-check, export the web build, ship to GitHub Pages, or test locally / on a phone**. This is the doc for the end-of-task "ship" routine.

## Environment (dev PC)

- Real Godot editor: `C:\godot47\Godot_v4.7-stable_win64.exe` (console build for CLI: `C:\godot47\Godot_v4.7-stable_win64_console.exe`). The in-repo `Godot_v4.7/` folder is an unmaterialized Google Drive FS stub — do not launch it.
- Workspace lives on **Google Drive virtual filesystem**; git can throw phantom "File exists" errors on checkout/merge — retry, or move refs without touching the tree (`git branch -f main <sha>` + push).
- Hostname `GamePc2`; Wi-Fi typically `192.168.1.26` (phones use the Wi-Fi IP).

## Compile check (do this after code changes)

```powershell
& "C:\godot47\Godot_v4.7-stable_win64_console.exe" --headless --path "F:\GdriveFS\My Drive\_DEV\Game\Creature_game\creature-godot" --quit-after 3
```

A clean boot (no script errors printed) = all scripts compile. Note: `--check-only` on individual scripts false-positives on autoload references (`GameState` etc.) — use the headless boot instead.

## Ship checklist (every shipped build)

1. **Bump `GameConfig.BUILD_ID`** in `creature-godot/scripts/config.gd` AND the matching `#build-stamp` string in `creature-godot/web/custom_shell.html` (format: `build YYYY-MM-DDx`).
2. Export: `powershell -ExecutionPolicy Bypass -File creature-godot/export-web.ps1` (imports, exports Web preset to repo-root `../index.html`, converts/copies the splash). Requires `creature-godot/loading_splash2.jpg`.
3. Verify the exported `index.html` contains the new build stamp.
4. Update `README.md` / relevant `docs/*.md`, commit the changed root export files + sources. **Push only when the user asks** — Pages redeploys `main` root automatically in ~1–2 min.
5. Verify live: build stamp shows bottom-right on the spawn screen.

## Export settings that must not drift

Godot can silently reserialize `export_presets.cfg` / `project.godot` on export — check the git diff afterwards:

| Setting | Value | Why |
|---------|-------|-----|
| Export path | `../index.html` (repo root) | GitHub Pages serves `main` root |
| Custom HTML shell | `res://web/custom_shell.html` | PWA/CreatureNet/dev-mode survive export |
| `ensure_cross_origin_isolation_headers` | **false** | Supabase fetch from wasm fails otherwise |
| `variant/thread_support` | **false** | Pages can't send COOP/COEP; threaded builds fail live with "SharedArrayBuffer missing" (works locally — production-only bug!) |
| PWA orientation | `0` (any) | Portrait + landscape without flashing |

`.nojekyll` at repo root must stay. **Never hand-edit repo-root `index.html`** — edit `custom_shell.html` and re-export (re-export after ANY shell edit).

## Local / phone testing

Godot wasm requires HTTPS off localhost:

```powershell
cd creature-godot
python serve-web.py         # http://localhost:8080  (desktop only)
python serve-web-https.py   # https://<wifi-ip>:8443 (phone; accept self-signed cert)
```

Ports 8443/8080 auto-enable **dev mode** in the shell (unregisters service workers, clears cached wasm/pck) so re-export → refresh is enough. `?dev=1` forces dev mode on any host; `?dev=0` forces service workers on (to test PWA caching). Installed PWA: fully close and reopen after re-export.

Multiplayer testing: run two sessions (editor F5 + browser, or two phones). Admin → Logs shows fetched row counts and remote-sync counts.

## Build stamp + PWA cache-busting

- `BUILD_ID` is the user-visible freshness check (bottom-right).
- `custom_shell.html` runs `setupServiceWorkerAutoUpdate()` (update check + skipWaiting + one-time reload) to defeat Godot's cache-first service worker. Returning visitors from very old builds may need one hard refresh.
- Don't grep `index.pck` for strings to judge freshness — GDScript exports as `.gdc` bytecode. Use `CACHE_VERSION` in `index.service.worker.js` + timestamps.

## Run in editor

Open `creature-godot/project.godot` → F5. Move + relaunch to verify position persistence; open a second session to see remote players.
