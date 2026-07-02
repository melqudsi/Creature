-- Slice 2: Money system.
-- Run in the Supabase SQL Editor (Dashboard -> SQL -> New query) AFTER
-- migration-world-objects.sql. This is the ONLY SQL you need for Slice 2.
--
-- Money objects (money_stack / money_bag / vault) and the MATA Bus reuse the
-- existing public.world_objects table as new `type` values, so no new table is
-- required. Carried money reuses the existing columns: state = 'carried' and
-- possessed_by = the carrier's user_id (no separate carried_by column needed).
--
-- The ONLY new column is `owner_name`, which stores the ALL-CAPS owner label
-- shown floating above money bags and vaults ("MOE's Money Bag", "TAZ's Vault").
--
-- GRACEFUL DEGRADATION: the Godot client works WITHOUT this column. It probes for
-- `owner_name` on any fetched world_objects row; if absent it simply omits the
-- column from writes (no crashes). Money can still be collected, carried,
-- combined and dropped; only the *persistent owner labels* need this column.
-- The client also auto-seeds the Slice 2 money + bus objects on first poll if a
-- pre-Slice-2 world already exists (no wipe needed), so running this migration is
-- enough — you do not have to touch existing rows.

alter table public.world_objects
  add column if not exists owner_name text;

-- The existing permissive prototype policies (world_objects_temp_insert /
-- _temp_update / _temp_delete, from migration-world-objects.sql) already allow
-- any authenticated player to seed / carry / combine / drop money objects, so no
-- new RLS policy is required for Slice 2.
