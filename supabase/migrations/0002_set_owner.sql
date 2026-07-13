-- NEXUS — grant server-side OWNER status to your account.
-- Run once in Supabase → SQL Editor after signing in to nexusasc.com at least
-- once with the account you want to be owner (so its auth user + profiles row
-- exist). This replaces the old client-side password backdoor: owner status now
-- lives in the database, readable only for your own row via RLS.
--
-- STEP 1 — put YOUR owner account's email between the quotes:
--   (the email you use to sign in / linked to the account)
--
-- STEP 2 — Run. It flips your profiles.tier to 'owner'. If your profiles row
-- doesn't exist yet, the INSERT..SELECT creates it from your auth user.

-- Ensure a profiles row exists for the account, then mark it owner.
insert into public.profiles (id, tier)
select u.id, 'owner'
from auth.users u
where lower(u.email) = lower('PUT_YOUR_OWNER_EMAIL_HERE')
on conflict (id) do update set tier = 'owner';

-- Verify (should show one row, tier = owner):
select p.tier, u.email
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = lower('PUT_YOUR_OWNER_EMAIL_HERE');
