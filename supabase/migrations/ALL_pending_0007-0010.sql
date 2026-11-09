-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — BUNDLED PENDING MIGRATIONS (0007 + 0008 + 0009 + 0010)
-- Paste this whole file ONCE into Supabase → SQL Editor and press Run.
-- Safe to re-run: every statement is if-not-exists / drop-if-exists.
-- No edits needed (no emails or keys to fill in).
--
--   0007  active_sessions   — one signed-in session at a time per account
--   0008  fix ai_gate       — drops the stale duplicate so the monthly AI cap enforces
--   0009  announcements     — one-way owner announcements in the notification center
--   0010  feature_events    — which features get used (owner-only read)
--
-- After it runs: open nexusasc.com once signed in and the board's migration
-- items can all be marked Done.
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- 0007_active_sessions.sql
-- ─────────────────────────────────────────────────────────────────────────
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


-- ─────────────────────────────────────────────────────────────────────────
-- 0008_fix_ai_gate.sql
-- ─────────────────────────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — 0008 FIX ai_gate  (2026-07-28)
-- The bundled SQL's CREATE OR REPLACE didn't take (Postgres can't rename an
-- existing function's parameters, so a name mismatch made it a no-op / error,
-- leaving an OLD ai_gate deployed that returns month:null and doesn't block at
-- limit 0). This drops EVERY ai_gate overload, then creates exactly one correct
-- copy — so the per-user monthly cap + per-IP cap actually enforce.
--
-- Run once in Supabase → SQL Editor. Safe to re-run. No `ai` redeploy needed.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Drop ALL ai_gate overloads (regardless of signature or param names).
do $$
declare r record;
begin
  for r in select oid::regprocedure as sig from pg_proc where proname = 'ai_gate' loop
    execute 'drop function ' || r.sig::text || ' cascade';
  end loop;
end $$;

-- 2. Recreate the single correct version.
create function public.ai_gate(
  p_ip             text,
  p_month_limit    int,
  p_per_min        int,
  p_ip_per_min     int,
  p_ip_month_limit int default -1
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid            uuid := auth.uid();
  ym             text := to_char(now(), 'YYYY-MM');
  min_count      int;
  ip_min_count   int;
  month_count    int;
  ip_month_count int;
begin
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'no_auth');
  end if;

  delete from ai_recent where at < now() - interval '2 minutes';

  select count(*) into min_count    from ai_recent where user_id = uid and at > now() - interval '60 seconds';
  select count(*) into ip_min_count from ai_recent where ip = p_ip     and at > now() - interval '60 seconds';
  select coalesce(requests, 0) into month_count from ai_usage where user_id = uid and yyyymm = ym;

  if min_count >= p_per_min then
    return jsonb_build_object('allowed', false, 'reason', 'rate_user', 'month', month_count);
  end if;
  if p_ip is not null and ip_min_count >= p_ip_per_min then
    return jsonb_build_object('allowed', false, 'reason', 'rate_ip', 'month', month_count);
  end if;
  if p_month_limit >= 0 and month_count >= p_month_limit then
    return jsonb_build_object('allowed', false, 'reason', 'month_limit', 'month', month_count);
  end if;

  if p_ip is not null and p_ip_month_limit >= 0 then
    select coalesce(requests, 0) into ip_month_count from ai_ip_usage where ip = p_ip and yyyymm = ym;
    if ip_month_count >= p_ip_month_limit then
      return jsonb_build_object('allowed', false, 'reason', 'ip_month_limit', 'month', month_count);
    end if;
  end if;

  insert into ai_recent (user_id, ip) values (uid, p_ip);
  insert into ai_usage (user_id, yyyymm, requests) values (uid, ym, 1)
    on conflict (user_id, yyyymm) do update set requests = ai_usage.requests + 1;
  if p_ip is not null and p_ip_month_limit >= 0 then
    insert into ai_ip_usage (ip, yyyymm, requests) values (p_ip, ym, 1)
      on conflict (ip, yyyymm) do update set requests = ai_ip_usage.requests + 1;
  end if;

  return jsonb_build_object('allowed', true, 'month', month_count + 1);
end;
$$;

grant execute on function public.ai_gate(text, int, int, int, int) to anon, authenticated;

-- 3. Verify — should list exactly ONE ai_gate with 5 named args.
select pg_get_function_arguments(oid) as args
from pg_proc where proname = 'ai_gate';


-- ─────────────────────────────────────────────────────────────────────────
-- 0009_messaging.sql
-- ─────────────────────────────────────────────────────────────────────────
-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — 0009 ANNOUNCEMENTS  (v20.0 → trimmed v20.3)
-- Run once in Supabase → SQL Editor. Idempotent. No `ai` redeploy needed.
--
-- v20.3: the two-way support_messages table was REMOVED from this migration.
-- A private DM channel between minors and an adult account is a predator/
-- liability risk we won't take on. Only owner→everyone announcements remain.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── announcements: owner broadcasts, everyone reads ────────────────────────
create table if not exists public.announcements (
  id         bigint generated always as identity primary key,
  title      text not null,
  body       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.announcements enable row level security;

drop policy if exists announcements_read on public.announcements;
create policy announcements_read on public.announcements
  for select using (true);                       -- everyone may read announcements

drop policy if exists announcements_owner_ins on public.announcements;
create policy announcements_owner_ins on public.announcements
  for insert with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner'));

drop policy if exists announcements_owner_upd on public.announcements;
create policy announcements_owner_upd on public.announcements
  for update using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner'));

drop policy if exists announcements_owner_del on public.announcements;
create policy announcements_owner_del on public.announcements
  for delete using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner'));

create index if not exists announcements_created_idx on public.announcements (created_at desc);

-- (support_messages table intentionally omitted — see header note, v20.3.)


-- ─────────────────────────────────────────────────────────────────────────
-- 0010_feature_events.sql
-- ─────────────────────────────────────────────────────────────────────────
-- NEXUS — feature usage analytics. Run once in Supabase → SQL Editor.
-- Records which features get opened so the owner can see real "who uses what"
-- instead of guessing. Privacy: stores only the feature key + the username the
-- user chose in-app + a timestamp — no message content, no PII beyond the
-- handle. Rows are write-only for users and readable ONLY by an owner account
-- (same model as client_errors / feedback). The app degrades gracefully to
-- local-only counts until this table exists.

create table if not exists public.feature_events (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users(id) on delete set null,
  feature    text not null,
  username   text,
  created_at timestamptz not null default now()
);
alter table public.feature_events enable row level security;

-- Anyone with a session (incl. the anonymous hosted-AI session) may INSERT
-- usage rows. They cannot read them back — usage is write-only for users.
drop policy if exists feature_events_insert on public.feature_events;
create policy feature_events_insert on public.feature_events
  for insert with check (true);

-- Only an OWNER account can read the aggregated usage feed.
drop policy if exists feature_events_owner_read on public.feature_events;
create policy feature_events_owner_read on public.feature_events
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

-- Index by time for the "recent events" query the owner dashboard runs.
create index if not exists feature_events_created_idx on public.feature_events (created_at desc);
create index if not exists feature_events_feature_idx on public.feature_events (feature);

