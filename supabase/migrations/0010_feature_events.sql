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
