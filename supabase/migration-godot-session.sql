-- Godot client pivot: session persistence + worm appearance
-- Run in Supabase SQL Editor after schema.sql

alter table public.creatures drop constraint if exists creatures_appearance_check;
alter table public.creatures add constraint creatures_appearance_check
  check (appearance in ('cute', 'ugly', 'worm'));

-- Health/stamina remain for legacy web client; Godot ignores them.
