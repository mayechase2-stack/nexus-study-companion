-- NEXUS backend schema — run once in Supabase → SQL Editor.
-- Creates the tables the Edge Functions need, with Row-Level Security ON everywhere.
-- Safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE).

-- ── profiles: one row per auth user; entitlement + age-gate record ──────────
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  username     text,
  dob          date,
  is_minor     boolean default false,
  tier         text  not null default 'free',   -- 'free' | 'paid' | 'owner'
  modules      text[] not null default '{}',    -- which paid modules are active
  created_at   timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Owner reads/writes only their own row. (Entitlement fields are written by the
-- Stripe webhook using the service-role key, which bypasses RLS.)
drop policy if exists profiles_owner_sel on public.profiles;
create policy profiles_owner_sel on public.profiles for select using (auth.uid() = id);
drop policy if exists profiles_owner_upd on public.profiles;
create policy profiles_owner_upd on public.profiles for update using (auth.uid() = id);
drop policy if exists profiles_owner_ins on public.profiles;
create policy profiles_owner_ins on public.profiles for insert with check (auth.uid() = id);

-- ── parental_consent: COPPA record for under-13 accounts ────────────────────
create table if not exists public.parental_consent (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  parent_email  text not null,
  consented_at  timestamptz not null default now()
);
alter table public.parental_consent enable row level security;
drop policy if exists pc_owner_all on public.parental_consent;
create policy pc_owner_all on public.parental_consent
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── app_state: the cloud sync store (history, notes, credits, inventory…) ────
create table if not exists public.app_state (
  user_id    uuid not null references auth.users(id) on delete cascade,
  key        text not null,
  value      jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.app_state enable row level security;
drop policy if exists app_state_owner_all on public.app_state;
create policy app_state_owner_all on public.app_state
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── subscriptions: written ONLY by the Stripe webhook (service role) ────────
create table if not exists public.subscriptions (
  user_id             uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id  text,
  stripe_sub_id       text,
  tier                text not null default 'free',
  modules             text[] not null default '{}',
  status              text not null default 'inactive', -- active | past_due | canceled
  current_period_end  timestamptz,
  updated_at          timestamptz not null default now()
);
alter table public.subscriptions enable row level security;
-- Users may READ their own subscription; nobody writes via the anon key.
drop policy if exists subs_owner_sel on public.subscriptions;
create policy subs_owner_sel on public.subscriptions for select using (auth.uid() = user_id);

-- ── ai_usage: monthly counter per user (for the allotment cap) ──────────────
create table if not exists public.ai_usage (
  user_id  uuid not null references auth.users(id) on delete cascade,
  yyyymm   text not null,           -- e.g. '2026-07'
  requests int  not null default 0,
  tokens_in  bigint not null default 0,
  tokens_out bigint not null default 0,
  primary key (user_id, yyyymm)
);
alter table public.ai_usage enable row level security;
drop policy if exists ai_usage_owner_sel on public.ai_usage;
create policy ai_usage_owner_sel on public.ai_usage for select using (auth.uid() = user_id);
-- No insert/update policy → the anon key cannot tamper with counts; the ai
-- function updates this via the service-role key (bypasses RLS).

-- ── ai_recent: one row per AI call, for per-minute rate windows ─────────────
create table if not exists public.ai_recent (
  id       bigserial primary key,
  user_id  uuid not null,
  ip       text,
  at       timestamptz not null default now()
);
create index if not exists ai_recent_user_at on public.ai_recent (user_id, at desc);
create index if not exists ai_recent_ip_at   on public.ai_recent (ip, at desc);
alter table public.ai_recent enable row level security;
-- No policies at all → unreachable via anon key; only service role touches it.

-- ── ai_gate(): atomic rate-limit + monthly-count check, run as the caller ───
-- SECURITY DEFINER so it can read/write the service tables; it derives the user
-- from auth.uid() so a caller can only ever gate THEMSELVES.
create or replace function public.ai_gate(
  p_ip           text,
  p_month_limit  int,
  p_per_min      int,
  p_ip_per_min   int
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid           uuid := auth.uid();
  ym            text := to_char(now(), 'YYYY-MM');
  min_count     int;
  ip_min_count  int;
  month_count   int;
begin
  if uid is null then
    return jsonb_build_object('allowed', false, 'reason', 'no_auth');
  end if;

  -- prune old rate rows opportunistically (cheap; keeps the table small)
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

  -- record the call + increment the monthly counter atomically
  insert into ai_recent (user_id, ip) values (uid, p_ip);
  insert into ai_usage (user_id, yyyymm, requests) values (uid, ym, 1)
    on conflict (user_id, yyyymm) do update set requests = ai_usage.requests + 1;

  return jsonb_build_object('allowed', true, 'month', month_count + 1);
end;
$$;

-- Optional: daily anomaly view for the ops dashboard.
create or replace view public.ai_daily as
  select user_id, date_trunc('day', at) as day, count(*) as calls
  from ai_recent group by 1, 2;
