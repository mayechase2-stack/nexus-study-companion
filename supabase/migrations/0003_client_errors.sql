-- NEXUS — client error telemetry. Run once in Supabase → SQL Editor.
-- Collects front-end JS errors so the owner can see real user breakage without
-- users having to report it. Privacy: no message body content is stored beyond
-- the error text itself; rows are readable ONLY by an owner account.

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

-- Anyone with a session (incl. the anonymous hosted-AI session) may INSERT their
-- own error rows. They cannot read them back — errors are write-only for users.
drop policy if exists client_errors_insert on public.client_errors;
create policy client_errors_insert on public.client_errors
  for insert with check (true);

-- Only an OWNER account can read the aggregated feed.
drop policy if exists client_errors_owner_read on public.client_errors;
create policy client_errors_owner_read on public.client_errors
  for select using (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

-- Keep the table small: index by time for the "recent errors" query.
create index if not exists client_errors_ts_idx on public.client_errors (ts desc);
