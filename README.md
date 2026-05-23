# Creature

Phase 1: browser-based multiplayer creature field (Stardew-style top-down pixel vibe). Static hosting on GitHub Pages + Supabase for auth, positions, and events.

## Quick start

1. **Supabase** (project `gimlaqcnfdbzwdaitfec`):
   - **Required:** Authentication → Sign In / Providers → **Anonymous sign-ins** → turn **ON**, then click **Save** (unsaved toggles still fail in the game)
   - SQL Editor → run [`supabase/schema.sql`](supabase/schema.sql)
   - **Realtime / table replication is not required** — other players refresh every ~1.5s via normal REST reads (free-tier friendly)

### Supabase cost note

Dashboard **Database → Replication** (toggling a table for Realtime) is **not** the same as paid **read replica** compute. It only exposes row changes to Realtime subscribers.

This game **does not use Realtime** anymore, so you can skip that step entirely. You stay on normal free-tier usage: Auth, Postgres, and REST API calls. No extra compute instance is spun up for polling.

2. **Config**  
   `js/config.example.js` holds the publishable Supabase keys (used on GitHub Pages). Optional: copy to `js/config.js` (gitignored) for local overrides.

3. **Run locally** (static server required for ES modules):

   ```bash
   npx --yes serve .
   ```

   Open `http://localhost:3456`

   **LAN / phone on same Wi‑Fi** (bind all interfaces):

   ```bash
   python -m http.server 3456 --bind 0.0.0.0
   ```

   Then open from other devices:

   - **Phone / tablet:** use your PC’s **Wi‑Fi** IP, e.g. `http://192.168.1.26:3456` (check with `ipconfig` under “Wireless LAN adapter Wi‑Fi”). The hostname `gamepc2` usually **does not** resolve on phones.
   - **Another PC on Ethernet:** may use `http://10.5.0.2:3456` if that’s your wired adapter’s IP.

   If the page never loads on the phone: allow port **3456** in Windows Firewall (Private), and disable **AP isolation / guest Wi‑Fi** on the router if enabled.

   Quick start script: `.\start-server.ps1` (prints all URLs).

4. **GitHub Pages**  
   Settings → Pages → deploy from **main**, folder **/ (root)**. Live site: [https://melqudsi.github.io/Creature/](https://melqudsi.github.io/Creature/)

## Controls

| Key | Action |
|-----|--------|
| WASD / arrows | Move (1 tile/sec, 1 stamina per tile) |
| F | Fight nearby creature (−15 HP, 2 stamina) |
| E | Eat smaller adjacent creature (grow + heal) |

AFK ~45s or tab hidden → creature sleeps and shrinks slightly. Returning after being eaten shows a toast naming who ate you.

## Phase 2 (later)

Godot client, passkey persistence, visual health/stamina instead of bars.

## Security note

Only the **anon/publishable** key belongs in the browser. Never commit the Postgres password from project notes; rotate if it was exposed.
