-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — BUNDLED PENDING MIGRATIONS (0002 + 0003 + 0004 + 0005 + 0006)
-- Run ONCE in Supabase → SQL Editor. Safe to re-run (idempotent).
--
-- ⚠️ BEFORE YOU RUN: replace BOTH copies of PUT_YOUR_OWNER_EMAIL_HERE below
--    (in section 1) with the email of the account you want to be OWNER. Do a
--    find-and-replace on PUT_YOUR_OWNER_EMAIL_HERE. Everything else needs no edits.
--
-- ⚠️ AFTER YOU RUN: redeploy the `ai` edge function so it starts enforcing the
--    per-IP cap (section 4). Order matters — this SQL must run FIRST.
--
-- What each section does:
--   1. Make your account server-side OWNER (retires the client password backdoor)
--   2. client_errors  — user JS errors flow to you (owner-only read)
--   3. feedback       — in-app feedback inbox (owner-only read)
--   4. ai_ip_usage + ai_gate() — per-IP monthly cap on the unverified tier
--   5. leaderboard    — real opt-in rankings (write-own / read-all)
-- ═══════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────
-- SECTION 1 — SERVER-SIDE OWNER  (edit the email in BOTH lines below)
-- Sign in to nexusasc.com at least once with this account first so it exists.
-- ─────────────────────────────────────────────────────────────────────────
-- Safety: older deployments created public.profiles before the tier/modules
-- columns existed (create-table-if-not-exists then skipped them). Add any that
-- are missing so the owner insert below can't fail with "column tier does not exist".
alter table public.profiles add column if not exists tier text not null default 'free';
alter table public.profiles add column if not exists modules text[] not null default '{}';
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists dob date;
alter table public.profiles add column if not exists is_minor boolean default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

insert into public.profiles (id, tier)
select u.id, 'owner'
from auth.users u
where lower(u.email) = lower('PUT_YOUR_OWNER_EMAIL_HERE')
on conflict (id) do update set tier = 'owner';

-- Verify section 1 (should return one row, tier = owner):
select p.tier, u.email
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('PUT_YOUR_OWNER_EMAIL_HERE');


-- ─────────────────────────────────────────────────────────────────────────
-- SECTION 2 — CLIENT ERROR TELEMETRY  (owner-only read)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.client_errors (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users(id) on delete set null,
  kind       text,
  msg        text,
  where_at   text,
  url        text,
  ua         text,
  ts         timestamptz not null default now()
);
alter table public.client_errors enable row level security;

drop policy if exists client_errors_insert on public.client_errors;
create policy client_errors_insert on public.client_errors
  for insert with check (true);

drop policy if exists client_errors_owner_read on public.client_errors;
create policy client_errors_owner_read on public.client_errors
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

create index if not exists client_errors_ts_idx on public.client_errors (ts desc);


-- ─────────────────────────────────────────────────────────────────────────
-- SECTION 3 — FEEDBACK INBOX  (owner-only read)
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users(id) on delete set null,
  username   text,
  category   text,
  message    text not null,
  rating     int,
  url        text,
  ua         text,
  handled    boolean not null default false,
  ts         timestamptz not null default now()
);
alter table public.feedback enable row level security;

drop policy if exists feedback_insert on public.feedback;
create policy feedback_insert on public.feedback
  for insert with check (true);

drop policy if exists feedback_owner_read on public.feedback;
create policy feedback_owner_read on public.feedback
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

drop policy if exists feedback_owner_upd on public.feedback;
create policy feedback_owner_upd on public.feedback
  for update using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

create index if not exists feedback_ts_idx on public.feedback (ts desc);


-- ─────────────────────────────────────────────────────────────────────────
-- SECTION 4 — PER-IP MONTHLY CAP (unverified tier)
-- After this runs, REDEPLOY the `ai` function.
-- ─────────────────────────────────────────────────────────────────────────
create table if not exists public.ai_ip_usage (
  ip        text not null,
  yyyymm    text not null,
  requests  int  not null default 0,
  primary key (ip, yyyymm)
);
alter table public.ai_ip_usage enable row level security;

drop function if exists public.ai_gate(text, int, int, int);
create or replace function public.ai_gate(
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


-- ─────────────────────────────────────────────────────────────────────────
-- SECTION 5 — REAL LEADERBOARD  (opt-in, username-only, write-own/read-all)
-- ─────────────────────────────────────────────────────────────────────────
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

drop policy if exists leaderboard_read on public.leaderboard;
create policy leaderboard_read on public.leaderboard for select using (true);
drop policy if exists leaderboard_upsert on public.leaderboard;
create policy leaderboard_upsert on public.leaderboard for insert with check (auth.uid() = user_id);
drop policy if exists leaderboard_update on public.leaderboard;
create policy leaderboard_update on public.leaderboard for update using (auth.uid() = user_id);
drop policy if exists leaderboard_delete on public.leaderboard;
create policy leaderboard_delete on public.leaderboard for delete using (auth.uid() = user_id);

create index if not exists leaderboard_xp_idx on public.leaderboard (xp desc);

-- ═══════════════════════════════════════════════════════════════════════════
-- DONE. Now: (1) confirm section 1 returned tier=owner, (2) redeploy the `ai`
-- function, (3) sign in on nexusasc.com and confirm you get owner perks, then
-- tell Claude so the old password backdoor can be deleted from the client.
-- ═══════════════════════════════════════════════════════════════════════════
