-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — 0007 SINGLE ACTIVE SESSION  (v237)
-- Enforces "one person logged in at a time": the client records which session id
-- currently owns the account; the newest login wins, and older sessions detect
-- they were displaced (their session_id no longer matches) and sign out.
--
-- Run ONCE in Supabase → SQL Editor. Idempotent. No `ai` redeploy needed.
-- Until this runs, the client fails OPEN (single-session simply doesn't enforce).
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.active_sessions (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  session_id text not null,
  updated_at timestamptz not null default now()
);

alter table public.active_sessions enable row level security;

-- A user may only see and manage their OWN active-session row.
drop policy if exists active_sessions_select on public.active_sessions;
create policy active_sessions_select on public.active_sessions
  for select using (auth.uid() = user_id);

drop policy if exists active_sessions_insert on public.active_sessions;
create policy active_sessions_insert on public.active_sessions
  for insert with check (auth.uid() = user_id);

drop policy if exists active_sessions_update on public.active_sessions;
create policy active_sessions_update on public.active_sessions
  for update using (auth.uid() = user_id);

drop policy if exists active_sessions_delete on public.active_sessions;
create policy active_sessions_delete on public.active_sessions
  for delete using (auth.uid() = user_id);
