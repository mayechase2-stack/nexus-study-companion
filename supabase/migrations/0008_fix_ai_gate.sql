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
