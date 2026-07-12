# Agent Index — START HERE

This file is the entry point for AI agents working on this project. It holds the general rules and points to topic docs so you only load the context you actually need. **Do not read the whole README up front** — it's the full historical record and will bloat your context.

## What this project is (one paragraph)

**Creature** — a multiplayer alien-shapeshifting sandbox set in a simplified Memphis. Godot 4.7 client (`creature-godot/`), web-exported to the repo root and served by GitHub Pages; Supabase (anonymous auth + Postgres/RLS, REST polling — no realtime) as the shared backend. Players shapeshift into cars/props/animals, collect and steal physical money, claim houses, and kill each other in funny ways. Live: [https://melqudsi.github.io/Creature/](https://melqudsi.github.io/Creature/)

## Rules for using this index (and in general)

1. **Route by task, load minimally.** Find your task in the routing table below and read only the doc(s) listed. Pull in a second doc only when the task actually crosses topics.
2. **Ask clarifying questions** before implementing if the request is ambiguous, conflicts with existing design, or has meaningful trade-offs. Don't guess at game-design intent — the user (MOE) decides design.
3. **Maintain the docs as you work.** When you change behavior, update the relevant `docs/*.md` topic file in the same task (keep them current, concise, and deduplicated — move detail, don't copy it). Add a short build entry to `README.md`'s current section when shipping a build. If you create a genuinely new topic, add a new doc and register it in the routing table here.
4. **Test after code updates when possible.** Minimum: run the headless compile check after any GDScript change (command in `docs/build-deploy-testing.md`). For gameplay changes, boot the game in the editor or dev server and exercise the changed path when practical; for backend/REST changes, verify with a real REST call. Report what you tested and what you couldn't.
5. **Ship discipline:** bump `BUILD_ID` (config + shell) on every export; commit when asked; **never push to GitHub unless the user explicitly asks** (pushing deploys the live game).
6. `_first.txt` (gitignored) holds credentials — never commit it or secrets.



## Routing table — read the right doc for the task


| Task involves…                                                                                                              | Read                                                                                       |
| --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Gameplay: forms, kill rules, money, houses/Big Houses, NPCs, zoo, map content, announcements UX, admin tools                | `[docs/gameplay-features.md](docs/gameplay-features.md)`                                   |
| Multiplayer sync, Supabase calls from the client, world-object state/possession, boot/session/login, polling, seeding/reset | `[docs/architecture-networking.md](docs/architecture-networking.md)`                       |
| DB schema, migrations, RLS, REST recipes (broadcast/clear announcements), security posture                                  | `[docs/supabase-backend.md](docs/supabase-backend.md)`                                     |
| Compile check, web export, GitHub Pages deploy, build stamp/PWA caching, local/phone testing, dev environment paths         | `[docs/build-deploy-testing.md](docs/build-deploy-testing.md)`                             |
| Godot code map (which script owns what), HUD/UI/admin panel, onboarding, camera/input, meshes, engine gotchas, perf rules   | `[docs/godot-client-internals.md](docs/godot-client-internals.md)`                         |
| Supabase multiplayer pattern deep-dive (reusable write-up)                                                                  | `[docs/supabase-multiplayer-guide.md](docs/supabase-multiplayer-guide.md)`                 |
| Original Godot port notes (historical)                                                                                      | `[creature-godot/docs/godot-porting-notes.md](creature-godot/docs/godot-porting-notes.md)` |
| Full build-by-build history, roadmap checklists, legacy web client (`_arc/`)                                                | `[README.md](README.md)` (historical record — search it, don't read linearly)              |




## Universal facts (worth knowing regardless of task)

- Real Godot binary: `C:\godot47\Godot_v4.7-stable_win64_console.exe` (repo's `Godot_v4.7/` folder is a Drive-FS stub — don't launch it). Workspace is on Google Drive FS (git can hiccup; retry).
- Dev shell is PowerShell — `&&` doesn't work, use `;`.
- Web export lands at the **repo root** (`index.html`, `index.pck`, …); GitHub Pages serves `main`'s root. Never hand-edit root `index.html` — edit `creature-godot/web/custom_shell.html` and re-export.
- Kills/combines/claims are **client-local** by design (prototype); sync is REST polling every 1.5s.
- Admin player is **MOE** (uppercase names, max 10 chars).
- Current build id lives in `creature-godot/scripts/config.gd` (`GameConfig.BUILD_ID`).

