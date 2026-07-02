import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from './config.example.js';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export async function ensureAnonymousAuth() {
  const { data: { session } } = await supabase.auth.getSession();
  if (session) return session;

  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw error;
  return data.session;
}

export async function fetchMyCreature(userId) {
  const { data, error } = await supabase
    .from('creatures')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function fetchAllCreatures() {
  const { data, error } = await supabase.from('creatures').select('*');
  if (error) throw error;
  return data ?? [];
}

export async function fetchMapObjects() {
  const { data, error } = await supabase.from('map_objects').select('*');
  if (error) throw error;
  return data ?? [];
}

export async function createCreature(row) {
  const { data, error } = await supabase.from('creatures').insert(row).select().single();
  if (error) throw error;
  return data;
}

export async function updateCreature(id, patch) {
  const { error } = await supabase
    .from('creatures')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}

export async function deleteCreature(id) {
  const { error } = await supabase.from('creatures').delete().eq('id', id);
  if (error) throw error;
}

export async function recordEatenEvent(victimUserId, attackerName) {
  const { error } = await supabase.from('creature_events').insert({
    victim_user_id: victimUserId,
    attacker_name: attackerName,
    event_type: 'eaten',
  });
  if (error) throw error;
}

export async function fetchUnreadEvents(userId) {
  const { data, error } = await supabase
    .from('creature_events')
    .select('*')
    .eq('victim_user_id', userId)
    .eq('read', false)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

export async function markEventsRead(ids) {
  if (!ids.length) return;
  const { error } = await supabase.from('creature_events').update({ read: true }).in('id', ids);
  if (error) throw error;
}

export function subscribeCreatures(onChange) {
  return supabase
    .channel('creatures-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'creatures' }, () => onChange())
    .subscribe();
}
