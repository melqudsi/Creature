-- Slice 1 refinement: shared / persistent interactive world objects.
-- Run in the Supabase SQL Editor (Dashboard -> SQL -> New query) AFTER schema.sql.
--
-- Backs the interactive/shapeshiftable objects (Rusty Altima, small tree,
-- pothole, propane tank, shopping cart, road cone, ...) with server state so all
-- clients agree on where they are and who is currently possessing one. This is
-- what eliminates the "shapeshift duplicate" (a possessed object is hidden as a
-- standalone prop for everyone) and makes popped-out objects PERSIST where they
-- were dropped, even across a disconnect.
--
-- GRACEFUL DEGRADATION: the Godot client works WITHOUT this table. It probes for
-- the table on its first world-object poll; if the table is missing it logs a
-- notice and falls back to client-local config placement (no crashes, no sync).
-- Running this migration turns on shared/persistent objects.
--
--   x, y     : position in TILE (grid) space, matching creatures.x / creatures.y
--   type     : object key (altima / magnolia / propane / pothole / cart / cone / trash)
--   state    : 'idle' (rendered as a world prop) or 'possessed' (a player is wearing it)
--   possessed_by : user_id of the controlling player while possessed, else null

create table if not exists public.world_objects (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  x real not null default 0,
  y real not null default 0,
  state text not null default 'idle',
  possessed_by uuid,
  updated_at timestamptz not null default now()
);

create index if not exists world_objects_updated_idx on public.world_objects (updated_at);

alter table public.world_objects enable row level security;

-- Anyone authenticated can read the shared object set.
create policy "world_objects_select" on public.world_objects
  for select to authenticated using (true);

-- TEMPORARY prototype policies: any authenticated player can seed/possess/release
-- objects. This is intentionally permissive (like the temp creature-admin
-- policies) so the shared world can be edited by whoever interacts with it.
-- Replace with owner/possession-scoped rules before shipping.
create policy "world_objects_temp_insert" on public.world_objects
  for insert to authenticated with check (true);

create policy "world_objects_temp_update" on public.world_objects
  for update to authenticated using (true) with check (true);

create policy "world_objects_temp_delete" on public.world_objects
  for delete to authenticated using (true);
