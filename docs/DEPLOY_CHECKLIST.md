# NEXUS — Deploy Checklist (single source of truth)

The front-end auto-deploys on `git push` (GitHub Pages). Everything below needs
the **Supabase dashboard** — SQL Editor or an Edge Function redeploy. Do the
🔴 steps **in order**; each is idempotent (safe to re-run).

---

## 🔴 RUN IN ORDER — activates everything currently shipped

### Step 1 — Bundled SQL: owner tier + tables + AI gate
**File:** [`supabase/migrations/ALL_pending_0002-0005.sql`](../supabase/migrations/ALL_pending_0002-0005.sql) (covers migrations 0002–0006)

1. Find-and-replace **`PUT_YOUR_OWNER_EMAIL_HERE`** (2 spots) with your owner account's email (`mayechase2@gmail.com`).
2. Supabase → **SQL Editor** → paste → **Run**.

Does all of this at once: server-side **owner tier**, `client_errors`, `feedback`, `ai_ip_usage` + updated `ai_gate()`, `leaderboard`.

✅ **Check:** the first result grid shows one row with `tier = owner`. Zero rows = that email has never signed into NEXUS — sign in once, then re-run.

### Step 2 — Single-session table
**File:** [`supabase/migrations/0007_active_sessions.sql`](../supabase/migrations/0007_active_sessions.sql)

Supabase → **SQL Editor** → paste → **Run**. Activates "one person logged in at a time" (the v237 client code fails open until this table exists).

### Step 3 — Redeploy the `ai` edge function  *(must be AFTER Step 1)*
**File:** [`supabase/functions/ai/index.ts`](../supabase/functions/ai/index.ts)

Supabase → **Edge Functions → `ai`** → paste the whole file → **Deploy**.

- ⚠️ Confirm the **`OPENAI_API_KEY` secret** is still set (the code reads it with `!` — a missing key breaks every AI call).
- Activates: **strict no-email gate** (`ANON_MONTHLY = 0`), 3 MB body cap, fail-closed moderation, gpt-4o routing, per-IP monthly cap.
- Order matters: if you deploy this before Step 1, AI still works — it falls back to the old 4-arg gate until the SQL runs.

### Step 4 — Verify
- Sign in with a **confirmed-email** account → confirm **owner perks** (30k credits, all items) come through the server path.
- Ask the tutor a question → a normal answer means the redeploy worked and `OPENAI_API_KEY` is intact.
- Try an **unverified / anonymous** account → it should now get the friendly *"verify your email"* block (strict gate working, no scary error string).

---

## ⚙️ Optional live tuning (secrets — no redeploy, instant)

Supabase → Edge Functions → `ai` → **Secrets**. Overrides the code defaults immediately.

| Secret | Default | Controls |
|---|---|---|
| `ANON_MONTHLY_LIMIT` | **0** | AI for unverified accounts. 0 = STRICT (no AI without a confirmed email). Raise (e.g. 2) for a taster. |
| `IP_ANON_MONTHLY_LIMIT` | 25 | Unverified answers per IP per month (moot while ANON is 0). |
| `FREE_MONTHLY_LIMIT` | 1500 | Verified-email monthly allotment. |
| `PAID_MONTHLY_LIMIT` | 6000 | Paid monthly allotment. |
| `PER_MIN_LIMIT` / `IP_PER_MIN_LIMIT` | 12 / 20 | Per-minute rate limits. |

OpenAI **spend cap**: set in the OpenAI billing dashboard (done).

---

## 🚀 Before PAID launch (not needed for the free beta)

- [ ] COPPA / privacy counsel (**the real gate**)
- [ ] Stripe **live** mode + deploy `checkout` and `stripe-webhook` functions
- [ ] Supabase **Pro** ($25/mo) — enables database backups
- [ ] Privacy policy page live (matches real data behavior)

---

## 📌 Notes

- **Owner account:** the client PIN backdoor is being **kept** (your call). PIN = `OWNER_PIN_CODE` in script.js. Once Step 1 sets your email account to `tier=owner`, your **email/Google login also grants owner** via the server path — and with the v236 attach prompt, carries your existing data across.
- **Device-swap safety (auto cloud-sync) and single-session only work for accounts with a cloud session.** The local-first owner account gets one once you sign in via email/Google (Step 4). Until then, keep the owner PIN in your password manager — don't rely on owner Notes as the only copy.

---

## 🔁 Deploy rules (how NEXUS ships)

- **Front-end** (`index.html`, `script.js`, `style.css`): auto-deploys on `git push`. **Always bump BOTH cache tags** (`?v=…`) in `index.html` or browsers serve stale JS/CSS. Verify: `curl -s https://nexusasc.com/index.html | grep 'v=<new>'`.
- **Edge functions** (`supabase/functions/*`): never auto-deploy — paste into Supabase → Edge Functions → Deploy.
- **Migrations** (`supabase/migrations/*`): run once in the SQL Editor. All idempotent.
