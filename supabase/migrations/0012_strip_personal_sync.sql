-- NEXUS — 0012 PERSONAL STUFF OFF THE SERVER (v24.50). Run once in Supabase → SQL Editor.
-- Older versions of NEXUS synced the whole browser to app_state, including birthdays,
-- saved API keys, chat/question history, lessons and companion memory. v24.50 stops that;
-- this removes the copies already on the server. Study progress (XP, streaks, flashcards,
-- notes, practice results, settings) is kept. Safe to re-run. Keep the key list in sync
-- with _NX_PRIVATE_KEYS in script.js.

do $$
declare col_type text;
begin
  select data_type into col_type from information_schema.columns
   where table_schema = 'public' and table_name = 'app_state' and column_name = 'data';
  if col_type is null then
    raise notice 'app_state has no data column — nothing to clean';
    return;
  end if;
  execute format($q$
    update public.app_state
    set data = (coalesce((
      select jsonb_object_agg(e.key, e.value)
      from jsonb_each(app_state.data::jsonb) as e(key, value)
      where not (
           e.key like 'user\_dob\_%%'           or e.key like 'auth\_email%%'
        or e.key like 'parental\_consent\_%%'   or e.key like 'pending\_receipt\_email%%'
        or e.key like 'emailjs\_%%'             or e.key ilike '%%api\_key%%'
        or e.key like 'user\_history%%'         or e.key like 'recent\_activities%%'
        or e.key like 'tutor\_session%%'        or e.key like 'teaching\_board\_session%%'
        or e.key like 'teaching\_board\_archive%%'
        or e.key like 'companion\_memory%%'     or e.key like 'companion\_chat%%'
        or e.key like 'nexus\_mem\_turns%%'     or e.key like 'nexus\_profile\_mem%%'
        or e.key like 'companion\_linked\_session%%'
        or e.key like 'user\_profile\_pic%%'    or e.key like 'profile\_bio%%'
        or e.key like 'nexus\_error\_log%%'     or e.key like 'lib\_shelf%%'
        or e.key like 'nexus\_classes%%'        or e.key like 'nexus\_active\_class%%'
        or e.key like 'quick\_note\_draft%%'    or e.key like 'scan\_%%'
      )
    ), '{}'::jsonb))::%s
    where jsonb_typeof(data::jsonb) = 'object'
  $q$, col_type);
end $$;

-- NEXUS never stores birthdays now; drop the unused column.
alter table public.profiles drop column if exists dob;

-- check: should be 0
select count(*) as rows_still_holding_personal_keys
from public.app_state t,
     jsonb_object_keys(case when jsonb_typeof(to_jsonb(t) -> 'data') = 'object' then to_jsonb(t) -> 'data' else '{}'::jsonb end) k
where k like 'user\_dob\_%' or k ilike '%api\_key%' or k like 'companion\_memory%' or k like 'user\_history%';
