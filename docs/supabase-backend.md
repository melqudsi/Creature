# Supabase backend: setup, migrations, REST recipes

> Read this when touching the **database schema, RLS, migrations, or doing dev-ops over REST** (announcements, cleanup).

## One-time project setup

1. Dashboard → **Authentication → Anonymous sign-ins → ON → Save** (Save is mandatory or auth fails).
2. SQL Editor → run `supabase/schema.sql`.
3. **Do not** enable Realtime/replication — the game uses REST polling.

Project URL + publishable (anon) key live in `creature-godot/scripts/config.gd` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Full credentials (Postgres password, project ref) are in the gitignored `_first.txt` — **never commit**.

## Migrations (run in SQL Editor, in order)

| Migration | Purpose | Status |
|-----------|---------|--------|
| `supabase/schema.sql` | Base tables + RLS (includes `world_objects`) | applied |
| `supabase/migration-temp-profile-admin.sql` | Temp name-claim + admin delete (replace with passkeys before shipping) | applied |
| `supabase/migration-forms.sql` | `creatures.form` (form sync) | applied |
| `supabase/migration-world-objects.sql` | `public.world_objects` (shared/persistent objects) | applied |
| `supabase/migration-money.sql` | `world_objects.owner_name` (money labels) | applied |
| `supabase/migration-pattern-lock.sql` | `creatures.pattern_hash` (pattern-lock auth) | applied |
| `supabase/migration-announcements.sql` | `public.announcements` (developer broadcasts) | applied |
| `supabase/migration-godot-session.sql` | Optional: allow `appearance=worm` in DB | optional |

The client degrades gracefully when a migration is missing (probes tables/columns, logs a notice, disables the feature). New rows use `appearance: "cute"` (schema constraint) regardless of rendering.

## Tables

- **`creatures`** — one row per profile: `user_id` (anon session), `name` (UPPERCASE), `color`, `x`, `y`, `form`, `pattern_hash`, `last_active`.
- **`world_objects`** — shared props/money/transients: `type`, `x`, `y`, `state` (`idle`/`possessed`/`carried`), `possessed_by`, `owner_name` (overloaded per type — see `docs/architecture-networking.md`), `updated_at`.
- **`announcements`** — developer broadcasts: `id`, `message`, `created_at`. RLS: select for authenticated; **temp** insert/delete for anon + authenticated (game UI gates the composer to MOE; replace with service-role-only before real shipping).

## REST recipes (PowerShell, no game needed)

Setup used by all recipes:

```powershell
$u = "https://gimlaqcnfdbzwdaitfec.supabase.co"   # or read from config.gd
$k = "<anon key from creature-godot/scripts/config.gd>"
# Some tables' RLS needs an authed JWT — get one via anonymous signup:
$auth = Invoke-RestMethod -Method Post -Uri "$u/auth/v1/signup" -Headers @{apikey=$k; "Content-Type"="application/json"} -Body '{}'
$jwt = $auth.access_token
$h = @{apikey=$k; Authorization="Bearer $jwt"; "Content-Type"="application/json"}
```

**Broadcast an announcement** (popup for every player within ~30s):

```powershell
Invoke-RestMethod -Method Post -Uri "$u/rest/v1/announcements" -Headers $h -Body (@{message="Hello Memphis"} | ConvertTo-Json)
```

**List / clear announcements:**

```powershell
Invoke-RestMethod -Uri "$u/rest/v1/announcements?select=id,message,created_at&order=created_at.desc" -Headers $h
Invoke-RestMethod -Method Delete -Uri "$u/rest/v1/announcements?id=not.is.null" -Headers $h
```

(If delete affects 0 rows, the live table predates the `announcements_temp_delete` policy — run that policy statement from `supabase/migration-announcements.sql` once, or `delete from public.announcements;` in the SQL editor.)

Players' announcement "seen" state is per-row-id and stored client-side, so clearing rows never re-pops old messages; only a genuinely new row pops.

## Security notes

- Browser ships the **publishable key only**.
- `_first.txt`, `.env`, Postgres password: gitignored, never commit.
- `creature-godot/web-certs/` is dev-only self-signed TLS.
- The permissive name-claim / world-object / announcement RLS policies are **prototype-temporary** by design.

## Further reading

- `docs/supabase-multiplayer-guide.md` — the reusable auth + polling + RLS pattern write-up.
