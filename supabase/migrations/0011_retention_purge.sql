-- NEXUS — automatic data-retention cleanup. Run once in Supabase → SQL Editor.
-- Makes the Privacy Policy's retention promises true automatically:
--   • AI usage counts, rate-limit records (incl. IP addresses), feature-usage
--     events, error reports and feedback older than 24 months are deleted.
-- Safe to re-run. Tables that don't exist yet are skipped.

create or replace function public.nexus_purge_old_records()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if to_regclass('public.ai_recent') is not null then
    delete from public.ai_recent where at < now() - interval '24 months';
  end if;
  if to_regclass('public.ai_ip_usage') is not null then
    -- ai_ip_usage is keyed by month text 'YYYY-MM'
    execute $q$delete from public.ai_ip_usage where yyyymm < to_char(now() - interval '24 months', 'YYYY-MM')$q$;
  end if;
  if to_regclass('public.ai_usage') is not null then
    delete from public.ai_usage where yyyymm < to_char(now() - interval '24 months', 'YYYY-MM');
  end if;
  if to_regclass('public.feature_events') is not null then
    delete from public.feature_events where created_at < now() - interval '24 months';
  end if;
  if to_regclass('public.client_errors') is not null then
    execute $q$delete from public.client_errors where ts < now() - interval '24 months'$q$;
  end if;
  if to_regclass('public.feedback') is not null then
    execute $q$delete from public.feedback where ts < now() - interval '24 months'$q$;
  end if;
end;
$$;

-- Only the database owner/service role may run it.
revoke all on function public.nexus_purge_old_records() from public, anon, authenticated;

-- Run it daily at 03:17 UTC with pg_cron (Supabase → Database → Extensions → enable "pg_cron" first).
-- If pg_cron isn't enabled, this block does nothing; you can enable it later and re-run this file.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'nexus-retention-purge';
    perform cron.schedule('nexus-retention-purge', '17 3 * * *', 'select public.nexus_purge_old_records();');
  end if;
end $$;

-- Run it once now:
select public.nexus_purge_old_records();
