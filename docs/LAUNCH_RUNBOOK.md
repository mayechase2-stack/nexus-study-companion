# NEXUS — Paid Launch Runbook

**Goal:** turn NEXUS from free beta into a paid, build-your-plan product ($2.50/module, capped at $18/mo), age-gated to 13+.
**Owner:** Chase · **Target:** before Halloween 2026.

The **code is already done and live** (v297–v299). Everything in this runbook is **dashboard setup** — Stripe, Supabase, OpenAI. Nothing here needs a new deploy from a terminal; edge functions are pasted + deployed in the Supabase dashboard.

Do the phases **in order**. Each box is a thing to check off. The last phase (the `FREE_BETA` flip) is the only code change, and Claude does it on your word.

Project ref: `hmgouywiiqukisupqbsq` · Functions base URL: `https://hmgouywiiqukisupqbsq.supabase.co/functions/v1/`

---

## Phase 0 — What's already done (no action)
- [x] Hard **13+ age gate** at signup (sidesteps COPPA). *(v297)*
- [x] **Server-side entitlement gating** in the `ai` function — paywall can't be bypassed. *(v298)*
- [x] **$2.50/module + $18 cap** pricing logic in the `checkout` function. *(v299)*
- [x] Plan builder UI, module sync from server, locked-tab routing — all built, dormant behind `FREE_BETA`.

---

## Phase 1 — Stripe account (start FIRST — slowest step)
Business + bank verification can take **several days**. Start before anything else.

1. [ ] Log in to **dashboard.stripe.com**.
2. [ ] Complete **Business settings → activate your account**: legal entity, address, bank account for payouts, identity. (Settings → Business settings.)
3. [ ] Wait for Stripe to confirm the account is **activated / able to accept live payments**. Until then, do the rest in **Test mode** (toggle top-right) and re-do Phase 2–3 in Live mode once activated.

> Tip: you can do a full **test-mode dry run** of Phases 2–6 now, verify the whole flow with a test card, then repeat Phases 2–3 in Live mode when activated. Highly recommended.

---

## Phase 2 — Create the two prices in Stripe
You need **two recurring prices**: a per-module price and a flat "everything" price.

1. [ ] Stripe → **Product catalog → + Add product**.
   - Name: **NEXUS Module** · Price: **$2.50 USD** · **Recurring, monthly** → Save.
   - Copy its **Price ID** (looks like `price_...`). → this is **`STRIPE_PRICE_MODULE`**.
2. [ ] **+ Add product** again.
   - Name: **NEXUS — Everything** · Price: **$18.00 USD** · **Recurring, monthly** → Save.
   - Copy its **Price ID**. → this is **`STRIPE_PRICE_EVERYTHING`**.
3. [ ] Grab your **secret key**: Developers → API keys → **Secret key** (`sk_live_...` in Live, `sk_test_...` in Test). → **`STRIPE_SECRET_KEY`**.

Keep these three values handy for Phase 4.

---

## Phase 3 — Stripe webhook endpoint
So Stripe tells NEXUS when someone pays.

1. [ ] Stripe → **Developers → Webhooks → + Add endpoint**.
2. [ ] Endpoint URL: `https://hmgouywiiqukisupqbsq.supabase.co/functions/v1/stripe-webhook`
3. [ ] **Select events to send** — add exactly these four:
   - `checkout.session.completed`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.payment_failed`
4. [ ] Save, then open the endpoint and copy its **Signing secret** (`whsec_...`). → **`STRIPE_WEBHOOK_SECRET`**.

---

## Phase 4 — Set Supabase Edge Function secrets
Supabase → **Edge Functions → Manage secrets** (or each function's **Secrets** tab). Add/confirm:

**`checkout`:**
- [ ] `STRIPE_SECRET_KEY` = your `sk_...`
- [ ] `STRIPE_PRICE_MODULE` = the $2.50 `price_...`
- [ ] `STRIPE_PRICE_EVERYTHING` = the $18 `price_...`

**`stripe-webhook`:**
- [ ] `STRIPE_SECRET_KEY` = same `sk_...`
- [ ] `STRIPE_WEBHOOK_SECRET` = the `whsec_...` from Phase 3

**`ai`:**
- [ ] `ENFORCE_MODULES` = `true`  ← **this is what turns the paywall on server-side**
- [ ] `OPENAI_API_KEY` = (already set — just confirm it's there)

> `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` are auto-provided — you don't set those.

---

## Phase 5 — Deploy the three edge functions
The function **code is in the repo** (`supabase/functions/ai`, `/checkout`, `/stripe-webhook`) but does **not** auto-deploy. Paste each into the Supabase dashboard and deploy.

1. [ ] Supabase → **Edge Functions → `ai`** → paste `supabase/functions/ai/index.ts` → **Deploy**.
2. [ ] **Edge Functions → `checkout`** → paste `supabase/functions/checkout/index.ts` → **Deploy**.
3. [ ] **Edge Functions → `stripe-webhook`** → paste `supabase/functions/stripe-webhook/index.ts` → **Deploy**.
   - ⚠️ The webhook must **not** require a JWT (Stripe calls it, not a logged-in user). Turn **Verify JWT = OFF** for `stripe-webhook` only.

---

## Phase 6 — Confirm the database is ready
Supabase → **SQL Editor**. The entitlement columns already exist (`profiles.modules`, `subscriptions`) from migration `0001`. Just confirm the other pending migrations have been run (re-running is safe — they're all `if not exists`):

- [ ] `0007_active_sessions.sql`
- [ ] `0008_fix_ai_gate.sql`
- [ ] `0009_messaging.sql`
- [ ] `0010_feature_events.sql` (usage analytics)

If unsure, paste each file's contents and run it; no harm if already applied.

---

## Phase 7 — Cost safety (do before going live)
1. [ ] **OpenAI → Settings → Limits** → set a **monthly budget / hard cap** so a launch spike can't run up a surprise bill.
2. [ ] (Optional) In the `ai` function secrets, sanity-check `FREE_MONTHLY_LIMIT` / `PAID_MONTHLY_LIMIT` are where you want them.

---

## Phase 8 — GO LIVE (Claude flips the switch)
When Phases 1–7 are done, tell Claude. Claude will:
1. [ ] Set `FREE_BETA = false` in `script.js` (and bump cache tags) → **this turns on the paywall + 13+ enforcement app-wide**.
2. [ ] Push + verify the deploy is live.

> Nothing is charged or locked until this flip **and** `ENFORCE_MODULES=true` are both set. Either one alone keeps you safe.

---

## Phase 9 — Live smoke test (do it together, right after the flip)
1. [ ] Open nexusasc.com in a **fresh/incognito** window. Sign up with a **13+ DOB** → should work. Try an **under-13 DOB** → should be blocked.
2. [ ] Open **Build your plan**, pick 3 modules, **Subscribe** → you should land on Stripe Checkout.
3. [ ] Pay with a **real card** (small real charge) or, in test mode, card `4242 4242 4242 4242`, any future expiry/CVC.
4. [ ] After returning, confirm your account shows the modules (Settings → Manage My Plan, or the owned state).
5. [ ] Confirm a **non-owned** feature is blocked and routes to the plan builder; an **owned** feature works.
6. [ ] In Supabase → Table editor → `profiles`, confirm your row's `modules` + `tier=paid` were written by the webhook.
7. [ ] Pick 8+ modules on a test account → confirm it charges **$18** (everything price), not $20+.

---

## Rollback (if something breaks at launch)
Any **one** of these instantly makes the app safe/free again:
- Ask Claude to set `FREE_BETA = true` and push (fastest — unlocks everything for everyone).
- Or set `ENFORCE_MODULES = false` in the `ai` function secrets (stops server-side blocking; no redeploy needed).

Keep both levers in mind — you can always fall back to "everything free" in under a minute.

---

## Still recommended (not a blocker)
- [ ] Book an hour with a lawyer for a **COPPA / Terms / Privacy** once-over. With the 13+ gate it's no longer a launch blocker, but it's cheap insurance for a product used by teens.
- [ ] If any client-side Stripe.js is ever used, swap the test `STRIPE_PUBLISHABLE_KEY` in `script.js` for your live `pk_live_...`. (The current hosted-checkout redirect flow doesn't need it, but check.)
