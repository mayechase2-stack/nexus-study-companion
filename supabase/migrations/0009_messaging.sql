-- ═══════════════════════════════════════════════════════════════════════════
-- NEXUS — 0009 ANNOUNCEMENTS  (v20.0 → trimmed v20.3)
-- Run once in Supabase → SQL Editor. Idempotent. No `ai` redeploy needed.
--
-- v20.3: the two-way support_messages table was REMOVED from this migration.
-- A private DM channel between minors and an adult account is a predator/
-- liability risk we won't take on. Only owner→everyone announcements remain.
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

-- (support_messages table intentionally omitted — see header note, v20.3.)
