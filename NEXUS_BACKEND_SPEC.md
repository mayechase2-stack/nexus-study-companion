# NEXUS — Backend Build Spec (v1)

Goal: add the minimum backend that makes NEXUS a real, sellable, compliant product —
real accounts + cross-device sync, a managed AI proxy (no student key needed), real
Stripe billing, and server-side security/consent. Keep it small enough for one person
to run. Nothing here changes the existing front-end features; it swaps localStorage-only
storage for a server when the user is signed in.

## Recommended stack
- **Supabase** — Postgres DB + Auth + Edge Functions in one managed service (free tier to start, ~$25/mo Pro).
- **Stripe** — Checkout + Billing + Customer Portal for subscriptions.
- **OpenAI** — one org account; the key lives ONLY in an Edge Function (never in the browser).
- Front-end stays on GitHub Pages (or moves behind the `.com`); it calls Supabase + Edge Functions over HTTPS.

## Environment variables
**Public (safe in the front-end / repo):** `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `STRIPE_PUBLISHABLE_KEY`, Google `CLIENT_ID`.
**Secret (Edge Function env only — never in repo/chat):** `SUPABASE_SERVICE_ROLE_KEY`, `OPENAI_API_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`.

## Data model (Postgres, all with Row-Level Security ON)
- `profiles` — id (=auth user), username, dob, is_minor, created_at. RLS: owner-only.
- `parental_consent` — user_id, parent_email, consented_at. RLS: owner/admin.
- `subscriptions` — user_id, stripe_customer_id, stripe_sub_id, tier (access|pro), status, current_period_end. Written by Stripe webhook (service role).
- `app_state` — user_id, key, json value (history, decks, grades, notebook, planner, vocab, credits, inventory, loadout, quests). RLS: owner-only. This is the sync store.
- `ai_usage` — user_id, day, tokens_in, tokens_out, requests. For caps + cost tracking.
- `waitlist` — email, name, interested_plan, ts. (Migrate the current localStorage `nexus_waitlist`.)

## Auth (Supabase Auth)
- Email/password + (optional) Google OAuth (reuse the Client ID).
- Replace client-side password hashing + `auth_users` localStorage with Supabase sessions + password reset.
- On first server login, migrate existing localStorage account into `profiles` + `app_state` (one-time importer), then prefer server as source of truth with a local cache for offline.

## Managed AI proxy — Edge Function `POST /ai`
1. Verify the caller's Supabase JWT → get user_id + tier.
2. Check `ai_usage` against the per-tier monthly cap; reject if exceeded.
3. Route model: routine tasks → `gpt-4o-mini`; tutor/vision/code → `gpt-4o` (mirror the front-end split already shipped in v17.1).
4. Call OpenAI with the SECRET key; stream/return the result; record tokens in `ai_usage`.
- Front-end change: the ~24 `fetch('https://api.openai.com/...')` calls point to `/ai` instead, and the BYO-key path becomes a fallback/power-user option. This makes the live "hosted AI — no key" claim true.

## Payments — Stripe
- Products: Access ($4.50/mo), Pro ($6/mo) — also add annual prices (better margin per the report).
- Edge Function `POST /create-checkout-session` → returns a Stripe Checkout URL (replace the waitlist CTA for signed-in users at launch).
- Edge Function `POST /stripe-webhook` (verify `STRIPE_WEBHOOK_SECRET`) → upsert `subscriptions` on created/updated/canceled/payment_failed.
- Customer Portal link for cancel/refund/update card. No card data ever touches NEXUS.

## Security
- RLS on every table; service-role key only in Edge Functions.
- Sanitize all AI/user HTML before render (front-end already has `sanitizeHTML` — enforce it on every AI insert).
- Secrets never shipped to the browser. Basic request logging + error capture in functions.

## Compliance (pairs with counsel review)
- Age gate + parental consent already collected at signup (v17.2) — persist to `profiles`/`parental_consent`.
- `GET /export-my-data` and `POST /delete-my-data` Edge Functions for real data-rights (the front-end already has local export + delete).
- Document the OpenAI data flow in the Privacy Policy (done) and obtain consent (done at signup).

## Rollout sequence (matches the readiness report)
1. Supabase project + Auth + `profiles`/`app_state` + localStorage→server migration (real accounts + sync).
2. AI proxy Edge Function + repoint front-end (kills the BYO-key onboarding blocker).
3. Stripe Checkout + webhook + portal (revenue on).
4. Compliance finish + counsel sign-off; flip checkout from waitlist → live.
5. Point the `.com`, add error monitoring, relaunch.

## What stays the same
All existing front-end features (tutor, Live Vision, notebook, shop, companions, etc.) keep working; only the storage + AI-call + payment layers move server-side. Estimated MVP backend: ~4–8 weeks for one dev, faster with help.
