-- Run in Supabase SQL Editor (Dashboard → SQL → New query)
-- Enable anonymous sign-ins: Authentication → Providers → Anonymous sign-ins

create table if not exists public.creatures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 10),
  color text not null,
  appearance text not null check (appearance in ('cute', 'ugly')),
  x real not null default 8,
  y real not null default 6,
  health integer not null default 100 check (health >= 0 and health <= 100),
  stamina integer not null default 10 check (stamina >= 0 and stamina <= 10),
  size_level integer not null default 1 check (size_level >= 1),
  is_asleep boolean not null default false,
  last_active timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.map_objects (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('tree')),
  x integer not null,
  y integer not null
);

create table if not exists public.creature_events (
  id uuid primary key default gen_random_uuid(),
  victim_user_id uuid not null references auth.users (id) on delete cascade,
  attacker_name text not null,
  event_type text not null check (event_type in ('eaten')),
  read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists creatures_updated_idx on public.creatures (updated_at);
create index if not exists creature_events_victim_idx on public.creature_events (victim_user_id, read);

alter table public.creatures enable row level security;
alter table public.map_objects enable row level security;
alter table public.creature_events enable row level security;

-- Creatures: anyone authenticated can read; only owner can write own row
create policy "creatures_select" on public.creatures
  for select to authenticated using (true);

create policy "creatures_insert" on public.creatures
  for insert to authenticated with check (auth.uid() = user_id);

create policy "creatures_update_own" on public.creatures
  for update to authenticated using (auth.uid() = user_id);

create policy "creatures_delete_own" on public.creatures
  for delete to authenticated using (auth.uid() = user_id);

-- Bigger creature can remove a smaller one (eat)
create policy "creatures_delete_smaller" on public.creatures
  for delete to authenticated
  using (
    exists (
      select 1 from public.creatures eater
      where eater.user_id = auth.uid()
        and eater.size_level > creatures.size_level
    )
  );

-- Map objects: read all; service role seeds — allow anon read
create policy "map_objects_select" on public.map_objects
  for select to authenticated using (true);

-- Events: victim reads/updates own
create policy "events_select_own" on public.creature_events
  for select to authenticated using (auth.uid() = victim_user_id);

create policy "events_update_own" on public.creature_events
  for update to authenticated using (auth.uid() = victim_user_id);

create policy "events_insert" on public.creature_events
  for insert to authenticated with check (true);

-- Realtime optional (game polls via REST); enable only if you wire up subscribeCreatures again

-- Seed trees (run once; skip if rows exist)
insert into public.map_objects (type, x, y)
select 'tree', x, y from (values
  (3, 3), (16, 4), (5, 10), (14, 11), (9, 2), (12, 13)
) as t(x, y)
where not exists (select 1 from public.map_objects limit 1);
