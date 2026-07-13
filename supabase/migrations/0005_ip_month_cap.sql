-- NEXUS — per-IP monthly cap for the UNVERIFIED (anon) tier. Run once in
-- Supabase → SQL Editor, BEFORE redeploying the `ai` function. Safe to re-run.
--
-- Why: the monthly allotment is per-account, so clearing the browser / going
-- incognito mints a fresh anonymous account with a fresh trial. This adds a
-- ceiling on how many ANON-tier answers a single IP can consume per month, so
-- account-cycling on one network hits a wall. Verified-email accounts pass
-- p_ip_month_limit = -1 from the `ai` function and are NEVER limited here.

-- Per-IP monthly counter. Only the SECURITY DEFINER ai_gate() touches it, so
-- RLS is on with no policies (no direct client access).
create table if not exists public.ai_ip_usage (
  ip        text not null,
  yyyymm    text not null,
  requests  int  not null default 0,
  primary key (ip, yyyymm)
);
alter table public.ai_ip_usage enable row level security;

-- Replace ai_gate with a 5-arg version. The new p_ip_month_limit defaults to
-- -1 (disabled), so any existing 4-arg caller keeps working during the window
-- between running this migration and redeploying the ai function.
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

  -- Per-IP monthly ceiling — enforced ONLY when the caller opts in with a
  -- non-negative limit (the ai function passes it for the anon tier only).
  if p_ip is not null and p_ip_month_limit >= 0 then
    select coalesce(requests, 0) into ip_month_count from ai_ip_usage where ip = p_ip and yyyymm = ym;
    if ip_month_count >= p_ip_month_limit then
      return jsonb_build_object('allowed', false, 'reason', 'ip_month_limit', 'month', month_count);
    end if;
  end if;

  -- Record the call + increment counters atomically.
  insert into ai_recent (user_id, ip) values (uid, p_ip);
  insert into ai_usage (user_id, yyyymm, requests) values (uid, ym, 1)
    on conflict (user_id, yyyymm) do update set requests = ai_usage.requests + 1;
  -- Only bill the per-IP bucket for anon-tier calls, so a verified user's usage
  -- never eats an anon user's IP budget on the same network.
  if p_ip is not null and p_ip_month_limit >= 0 then
    insert into ai_ip_usage (ip, yyyymm, requests) values (p_ip, ym, 1)
      on conflict (ip, yyyymm) do update set requests = ai_ip_usage.requests + 1;
  end if;

  return jsonb_build_object('allowed', true, 'month', month_count + 1);
end;
$$;

grant execute on function public.ai_gate(text, int, int, int, int) to anon, authenticated;
