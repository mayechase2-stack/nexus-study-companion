-- NEXUS — real leaderboard. Run once in Supabase → SQL Editor. Safe to re-run.
-- Opt-in, username-only public stats (no email). A user writes ONLY their own
-- row; everyone can read the board. Opting out deletes the row.

create table if not exists public.leaderboard (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  username     text not null,
  xp           int  not null default 0,
  problems     int  not null default 0,
  streak       int  not null default 0,
  minutes      int  not null default 0,
  achievements int  not null default 0,
  badge        text,
  updated_at   timestamptz not null default now()
);
alter table public.leaderboard enable row level security;

-- Public read: the board is meant to be seen. Username + aggregate stats only.
drop policy if exists leaderboard_read on public.leaderboard;
create policy leaderboard_read on public.leaderboard
  for select using (true);

-- A user may create/update/delete ONLY their own row (auth.uid() = user_id).
drop policy if exists leaderboard_upsert on public.leaderboard;
create policy leaderboard_upsert on public.leaderboard
  for insert with check (auth.uid() = user_id);
drop policy if exists leaderboard_update on public.leaderboard;
create policy leaderboard_update on public.leaderboard
  for update using (auth.uid() = user_id);
drop policy if exists leaderboard_delete on public.leaderboard;
create policy leaderboard_delete on public.leaderboard
  for delete using (auth.uid() = user_id);

create index if not exists leaderboard_xp_idx on public.leaderboard (xp desc);
