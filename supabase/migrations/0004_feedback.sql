-- NEXUS — user feedback inbox. Run once in Supabase → SQL Editor.
-- Feedback users send from the app lands here so the owner can read it.
-- (Distinct from the public Suggestions board: feedback is private to the owner.)

create table if not exists public.feedback (
  id         bigint generated always as identity primary key,
  user_id    uuid references auth.users(id) on delete set null,
  username   text,
  category   text,          -- 'bug' | 'idea' | 'praise' | 'other'
  message    text not null,
  rating     int,           -- optional 1..5
  url        text,
  ua         text,
  handled    boolean not null default false,
  ts         timestamptz not null default now()
);
alter table public.feedback enable row level security;

-- Any session (incl. the anonymous hosted-AI session) may submit feedback,
-- but cannot read the inbox back.
drop policy if exists feedback_insert on public.feedback;
create policy feedback_insert on public.feedback
  for insert with check (true);

-- Only an OWNER account can read (and mark handled) the inbox.
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
