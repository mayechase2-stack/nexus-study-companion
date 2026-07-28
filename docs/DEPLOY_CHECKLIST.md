# NEXUS — Deploy Checklist

Your standing to-do for anything that needs the **Supabase dashboard** or a
function **redeploy**. The front-end auto-deploys on `git push` (GitHub Pages);
these are the pieces that don't.

---

## 🔴 Pending right now (do these to activate shipped features)

Everything below is already written and pushed — it just needs you to run SQL
and/or redeploy functions to turn on.

### 1. Run the bundled SQL (one paste)
Supabase → **SQL Editor** → open
[`supabase/migrations/ALL_pending_0002-0005.sql`](../supabase/migrations/ALL_pending_0002-0005.sql),
**find-and-replace `PUT_YOUR_OWNER_EMAIL_HERE`** (2 spots) with your owner
account's email → **Run**.

This does five things at once:
- Makes your account **server-side owner** (retires the client password backdoor)
- Creates the **client_errors** table (error reporting)
- Creates the **feedback** table (in-app feedback inbox)
- Adds the **per-IP monthly cap** table + updated `ai_gate()`
- Creates the **leaderboard** table (real opt-in rankings)

✅ Check: the first result grid shows one row with `tier = owner`.

### 2. Redeploy the `ai` edge function  *(after step 1)*
Supabase → **Edge Functions → `ai`** → paste from
[`supabase/functions/ai/index.ts`](../supabase/functions/ai/index.ts) → **Deploy**.
Picks up: unverified trial = 5, per-IP monthly cap = 25, gpt-4o quiz keys.

> Order matters: SQL first, then this. If you redeploy first, AI still works —
> it falls back to the old gate until the SQL runs.

### 3. Confirm owner + finish the backdoor removal
Sign in on nexusasc.com with your owner account → confirm you get owner perks
(30k credits, all items). **Then tell Claude** — the hardcoded `chase_owner`
password hash gets deleted from the client as the final step.

### 4. Verify AI still answers
Ask the tutor a question on nexusasc.com. A normal answer = the `ai` redeploy
worked and its `OPENAI_API_KEY` secret is intact.

---

## ⚙️ Optional live tuning (no redeploy — just secrets)

Supabase → Edge Functions → `ai` → **Secrets**. Add/edit and it takes effect
immediately, overriding the code defaults:

| Secret | Default | What it controls |
|---|---|---|
| `ANON_MONTHLY_LIMIT` | **0** | AI answers for **unverified** accounts. 0 = STRICT: no AI without a confirmed email (anonymous + unconfirmed both blocked). Raise (e.g. 2) to re-enable a taster. |
| `IP_ANON_MONTHLY_LIMIT` | 25 | Unverified answers per **IP** per month |
| `FREE_MONTHLY_LIMIT` | 1500 | Verified-email monthly allotment |
| `PAID_MONTHLY_LIMIT` | 6000 | Paid monthly allotment |
| `PER_MIN_LIMIT` | 12 | Per-user requests/minute |
| `IP_PER_MIN_LIMIT` | 20 | Per-IP requests/minute |

Also set the **OpenAI spend cap** in the OpenAI billing dashboard (done).

---

## 🚀 Before PAID launch (not needed for the free beta)

- [ ] COPPA / privacy counsel (the real gate)
- [ ] Stripe **live** mode + deploy `checkout` and `stripe-webhook` functions
- [ ] Supabase **Pro** ($25/mo) — enables database backups
- [ ] Drop `ANON_MONTHLY_LIMIT` further if farming shows up in `client_errors`/usage
- [ ] Privacy policy page live (matches real data behavior)

---

## 🔁 The deploy rules (how NEXUS ships)

- **Front-end** (`index.html`, `script.js`, `style.css`): auto-deploys on
  `git push`. **Always bump BOTH cache tags** (`?v=...`) in `index.html` or
  browsers serve stale JS/CSS. Verify:
  `curl -s https://nexusasc.com/index.html | grep 'v=<new>'`
- **Edge functions** (`supabase/functions/*`): never auto-deploy — paste into
  Supabase → Edge Functions → Deploy (or `npx supabase functions deploy <name>
  --project-ref hmgouywiiqukisupqbsq`).
- **Migrations** (`supabase/migrations/*`): run once in the SQL Editor. All are
  idempotent (safe to re-run).
