-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — 0009 MESSAGING (announcements + two-way support)  v20.0
-- Run once in Supabase → SQL Editor. Idempotent. No `ai` redeploy needed.
--
-- SAFETY IS THE POINT of this migration. The RLS policies below are what stop
-- one student from reading another's support messages. Do not loosen them.
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

-- ── support_messages: two-way user <-> owner threads ───────────────────────
create table if not exists public.support_messages (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  sender        text not null check (sender in ('user', 'owner')),
  body          text not null,
  read_by_user  boolean not null default false,
  read_by_owner boolean not null default false,
  created_at    timestamptz not null default now()
);
alter table public.support_messages enable row level security;

-- READ: a user sees ONLY their own thread; the owner sees all.
drop policy if exists support_read on public.support_messages;
create policy support_read on public.support_messages
  for select using (
    auth.uid() = user_id
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

-- INSERT: a user may post to their OWN thread only, and only as 'user'. The
-- owner may post to any thread, and only as 'owner'. (This is what prevents a
-- user from forging an owner reply or writing into someone else's thread.)
drop policy if exists support_insert on public.support_messages;
create policy support_insert on public.support_messages
  for insert with check (
    (auth.uid() = user_id and sender = 'user')
    or (sender = 'owner' and exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner'))
  );

-- UPDATE: mark-as-read only — a user on their own rows, the owner on any.
drop policy if exists support_update on public.support_messages;
create policy support_update on public.support_messages
  for update using (
    auth.uid() = user_id
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.tier = 'owner')
  );

create index if not exists support_user_idx on public.support_messages (user_id, created_at);
