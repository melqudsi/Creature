-- Slice 10: developer announcements broadcast to every player.
-- Run in the Supabase SQL Editor (Dashboard -> SQL -> New query).
--
-- The Godot client polls the newest row every ~30s. When a player sees a row
-- id they haven't acknowledged yet, a popup with the message and an OK button
-- appears (in-game AND on next login). Acknowledgement is stored client-side
-- (localStorage on web, user:// file on desktop), so no per-player rows here.
--
-- GRACEFUL DEGRADATION: the client works WITHOUT this table. It probes on the
-- first poll; if the table is missing it logs a notice once and disables the
-- announcement feature (no crashes).

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists announcements_created_idx on public.announcements (created_at);

alter table public.announcements enable row level security;

-- Every authenticated player can read announcements.
create policy "announcements_select" on public.announcements
  for select to authenticated using (true);

-- TEMPORARY prototype policy (matches the world_objects posture): any client
-- may insert; the game UI only exposes the broadcast composer to the admin
-- (MOE), and `anon` is included so the developer can broadcast with a plain
-- anon-key REST call from the shell (see README). Replace with a
-- service-role-only rule before shipping for real.
create policy "announcements_temp_insert" on public.announcements
  for insert to anon, authenticated with check (true);

-- TEMPORARY prototype policy: allows clearing old/test announcements with a
-- plain anon-key REST call (the game UI never deletes). Same caveat as above.
create policy "announcements_temp_delete" on public.announcements
  for delete to anon, authenticated using (true);

-- First announcement so the feature can be tested immediately.
insert into public.announcements (message) values ('Test');
