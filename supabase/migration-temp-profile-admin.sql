-- Temporary profile management policies for the Godot onboarding/admin flow.
-- Run in Supabase SQL Editor only while name-based profile claiming is acceptable.
-- Replace this with passkeys/password phrases before shipping.

-- Allows a newly authenticated anonymous session to claim an existing creature
-- row by PATCHing user_id to auth.uid(). The client currently targets by id
-- after looking up a typed name.
drop policy if exists "creatures_temp_claim_by_name" on public.creatures;
create policy "creatures_temp_claim_by_name" on public.creatures
  for update to authenticated
  using (true)
  with check (auth.uid() = user_id);

-- Allows the in-game admin panel to delete stale/test profiles.
-- This is intentionally broad and should be removed when real admin auth exists.
drop policy if exists "creatures_temp_admin_delete" on public.creatures;
create policy "creatures_temp_admin_delete" on public.creatures
  for delete to authenticated
  using (true);
