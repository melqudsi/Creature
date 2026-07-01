-- Slice 1: shapeshift form sync.
-- Run in the Supabase SQL Editor (Dashboard -> SQL -> New query) AFTER schema.sql
-- + migration-godot-session.sql.
--
-- Adds the `form` column so other players can see each other in their current
-- shapeshift form (Alien / Altima / Magnolia Tree / Pothole / Propane Tank...).
--
-- The Godot client degrades gracefully WITHOUT this column: it only writes
-- `form` once it detects the column exists in fetched rows, and remote players
-- default to the alien form. So the game keeps working before you run this;
-- running it simply turns on cross-player form visibility.

alter table public.creatures
  add column if not exists form text not null default 'alien';

-- No new RLS policy is needed: the existing creatures_update_own policy already
-- lets a player write any column on their own row, and creatures_select already
-- lets everyone read it.
