# NEXUS Backend Setup — deploying the protections

This guide turns the code in `supabase/` into a live, protected backend. Everything
here is done by **you** in the Supabase/Stripe/OpenAI dashboards — Claude wrote the
code but cannot deploy it (that needs your account logins).

Do it in this order. Steps 1–3 give you the cost/abuse protection (the urgent part);
4–5 turn on real payments; 6 is the optional bot check.

---

## What's in the repo now

| File | What it is |
|---|---|
| `supabase/migrations/0001_backend_schema.sql` | All tables + Row-Level Security + the `ai_gate` rate-limit function |
| `supabase/functions/ai/index.ts` | Hardened AI proxy: auth, rate limits, monthly allotment, size caps, **fail-closed moderation**, model routing |
| `supabase/functions/stripe-webhook/index.ts` | Verifies Stripe payments and writes entitlements server-side |

> These replace the versions currently only living inside the Supabase dashboard.
> Committing them means the source is now backed up in git (the runbook flagged
> that they weren't).

---

## 1. Create the tables (5 min)

Supabase dashboard → **SQL Editor** → paste the entire contents of
`supabase/migrations/0001_backend_schema.sql` → **Run**. It's safe to re-run.

Verify: **Table Editor** should now show `profiles`, `subscriptions`, `ai_usage`,
`ai_recent`, `parental_consent`, `app_state`, all with the RLS shield icon.

## 2. Set the AI function's secrets (5 min)

Supabase → **Edge Functions → ai → Secrets** (Manage secrets). Add:

| Name | Value |
|---|---|
| `OPENAI_API_KEY` | your OpenAI secret key (`sk-...`) |

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected
automatically — you don't add them.

### AI usage limits — how to think about them

There are three separate defenses; they do different jobs, so don't conflate them:

| Knob | Default (beta) | Its actual job |
|---|---|---|
| `PER_MIN_LIMIT` | 12 / user / min | **The real script-stopper.** A burst can't exceed this. |
| `IP_PER_MIN_LIMIT` | 20 / IP / min | Stops many accounts abused from one machine. |
| `ANON_MONTHLY_LIMIT` | **100** | Cap for anonymous / unverified accounts. Kept low because they're free to mint — each fake account is worth only pennies of usage. |
| `FREE_MONTHLY_LIMIT` | **1500** | Cap for email-verified free users (~50/day; ~$1.50/mo of OpenAI even if maxed). Generous so real students never feel limited. |
| `PAID_MONTHLY_LIMIT` | **6000** | Paid users (later). |
| OpenAI **spend cap** | set in OpenAI billing | Absolute dollar ceiling — the final backstop. |

Key point: the **per-minute** limits stop a script; the **monthly** caps bound cost
and account-farming. A verified email doesn't stop a script — it just makes the
*generous* cap expensive to mass-create (you'd need many real inboxes). Text
questions cost ~0.1¢ each (gpt-4o-mini); Live Vision images ~1.6¢.

To change any of these, add it as a secret above (a secret overrides the code
default). **Before flipping on PAID plans, drop `ANON_MONTHLY_LIMIT` to ~30** — the
low anonymous cap is your anti-farming defense, and it only matters once there's
paid value to protect. During the free beta, the OpenAI spend cap is the real
protection, so generous caps are fine.

## 3. Deploy the AI function + fund/cap OpenAI (15 min) — THE URGENT ONE

Deploy the function. Easiest is the dashboard editor: **Edge Functions → ai → Edit**,
paste `supabase/functions/ai/index.ts`, **Deploy**. (Or CLI: `supabase functions deploy ai`.)

Then at **platform.openai.com → Settings → Billing**:
- Add a real balance (start small, e.g. $20–50).
- **Usage limits → set a hard monthly cap** (e.g. $50) and an email alert at ~75%.
- Turn **off** auto-recharge, or cap it low, so a spike can't silently rebill you.

Test it: sign into nexusasc.com, ask the tutor a question — it should answer. Then
in SQL Editor, `select * from ai_usage;` should show your request counted. Spam ~15
questions fast on a fresh anonymous session and you should hit the friendly limit
message — that's the protection working.

**After this step you are protected against the cost-blowout risk**, which was the
#3 GA blocker. Payments (below) can follow on their own timeline.

## 4. Stripe webhook secrets + deploy (10 min)

1. Stripe dashboard (LIVE mode once verified) → **Developers → Webhooks → Add endpoint**.
   - URL: `https://hmgouywiiqukisupqbsq.supabase.co/functions/v1/stripe-webhook`
   - Events: `checkout.session.completed`, `customer.subscription.updated`,
     `customer.subscription.deleted`, `invoice.payment_failed`.
   - Copy the **Signing secret** (`whsec_...`).
2. Supabase → **Edge Functions → stripe-webhook → Secrets**: add
   `STRIPE_SECRET_KEY` (`sk_live_...` or `sk_test_...`) and `STRIPE_WEBHOOK_SECRET` (`whsec_...`).
3. Deploy **without JWT check** (Stripe isn't a logged-in user):
   `supabase functions deploy stripe-webhook --no-verify-jwt`
   (Dashboard: create the function, paste the file, then toggle "Enforce JWT" **off**.)

## 5. Deploy the checkout function (links payments to accounts)

`supabase/functions/checkout/index.ts` is now provided — it stamps the user id +
chosen modules onto the Stripe session so the webhook can credit the right
account (without this, a completed payment can't be linked to anyone).

1. Supabase → **Edge Functions → checkout** → paste `checkout/index.ts` → **Deploy**.
   (If a `checkout` function already exists from before, replace its code with this.)
2. Secrets: it needs `STRIPE_SECRET_KEY` (same one as the webhook). The Supabase
   keys are auto-provided.
3. It matches the client call already in `script.js` (`_pbConfirm` → POST
   `/functions/v1/checkout` with `{ modules, priceId, successUrl, cancelUrl }`),
   so no front-end change is needed.

The full loop is now: **checkout** stamps `user_id` + `modules` → **stripe-webhook**
writes the verified entitlement to `subscriptions` + `profiles` → the **ai** function
reads `profiles.tier` for the allotment. The browser only *reflects* entitlement,
never grants it.

Test end-to-end with a Stripe **test-mode** card (`4242 4242 4242 4242`) before going live.

## 6. (Optional) Turn on the bot check

Cloudflare dash → **Turnstile → Add widget** (domain `nexusasc.com`) → copy the
**Site key** → paste into `TURNSTILE_SITE_KEY` in `script.js` and redeploy the front
end. The widget then appears on signup. For full protection, verify the token
server-side (a small `signup` Edge Function, or check it on first AI call) using your
Turnstile **secret** key — ask Claude to write that when you're ready.

---

## Quick reference — where each protection lives

- **Cost cap / abuse:** OpenAI billing cap (step 3) + `ai_gate` rate limits (step 1) + per-user monthly allotment (`ai` function).
- **Account farming:** anonymous accounts get only `ANON_MONTHLY_LIMIT`; full allotment needs a verified email; per-IP limits in `ai_gate`; optional Turnstile.
- **Bad AI output:** fail-closed moderation in the `ai` function (blocks on flag *or* on a moderation error).
- **Payment integrity:** Stripe signature check + server-written entitlements in `subscriptions`/`profiles`.
- **Kill switch:** Supabase → Edge Functions → `ai` → disable (see OPERATIONS_RUNBOOK.md).
