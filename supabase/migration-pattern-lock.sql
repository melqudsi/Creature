-- Pattern-lock onboarding (Slice 7): Login / Register with an Android-style
-- 4+ dot swipe pattern instead of a password.
--
-- The client stores sha256("creature:<NAME>:<dot-index-sequence>") here at
-- registration and verifies it at login before claiming the row for the
-- current anonymous session (the claim itself still rides the temporary
-- creatures_temp_claim_by_name policy from migration-temp-profile-admin.sql).
--
-- NOT real security (the hash is verifiable client-side and the temp claim
-- policy is wide open) — it's a friendly lock, per the design notes.
--
-- Run in Supabase SQL Editor.

alter table public.creatures
  add column if not exists pattern_hash text;
