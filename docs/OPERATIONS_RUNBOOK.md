# NEXUS — Operations Runbook

Purpose: let Chase — or, in an emergency, a trusted adult with access to the accounts below — operate, fix, or safely shut down NEXUS. Written for someone competent but unfamiliar with the codebase. Last updated: July 5, 2026.

## The moving parts

| Piece | Where | What it does |
|---|---|---|
| Front end | GitHub repo `mayechase2-stack/nexus-study-companion` → **GitHub Pages** (NOT Netlify), domain nexusasc.com (Cloudflare DNS + CNAME file in repo) | The whole visible app (index.html + script.js + style.css) |
| Backend | Supabase project `hmgouywiiqukisupqbsq` | Auth, Postgres (user data, RLS), Edge Functions |
| Edge Functions | Supabase dashboard → Edge Functions (`ai`, `checkout`, `stripe-webhook`) — source now versioned in the repo under `supabase/functions/` | AI proxy to OpenAI; Stripe checkout + webhook |
| AI provider | OpenAI platform account | Serves gpt-4o / gpt-4o-mini via the `ai` function |
| Payments | Stripe account (test mode, dormant until launch) | Future billing |
| Email | support@nexusasc.com (forwarded inbox); EmailJS (not configured) | Support + future receipts |

## Hosting — GitHub Pages only (Netlify is being retired)

The live site is served by **GitHub Pages**, confirmed by the response headers
(`Server: GitHub.com`). Netlify does **not** serve nexusasc.com.

A leftover Netlify site is still linked to the repo and was building on every push,
burning Netlify credits. Mitigation in the repo: `netlify.toml` now contains
`[build] ignore = "true"`, which makes Netlify cancel every build (no more credit
drain). **To fully cut Netlify (do this once):**
1. app.netlify.com → open the NEXUS site.
2. Site configuration → Build & deploy → Continuous deployment → **Unlink repository**,
   or Site configuration → Danger zone → **Delete this site** (cleaner).
3. This is safe — nexusasc.com is on GitHub Pages and is unaffected. Deleting the
   Netlify site also removes any outdated `*.netlify.app` public copy of the app.

## Deploy / rollback

- **Deploy:** commit to `main`, `git push` → GitHub Pages redeploys in ~1–10 minutes. Verify: `curl -s https://nexusasc.com/script.js | grep <new marker>`.
- **Rollback:** `git revert <bad commit>` and push. (Prefer revert over force-push — Pages rebuilds either way.)
- **Cache note:** index.html pins `script.js?v=...`; bump that version string when shipping to force clients past CDN/browser caches.

## Rotate a leaked secret (do this FIRST in any incident)

1. **OpenAI key:** platform.openai.com → API keys → revoke + create new → paste into Supabase → Edge Functions → `ai` → Secrets.
2. **Stripe keys:** dashboard.stripe.com → Developers → API keys → roll → update `checkout` function secret.
3. **Supabase service-role key:** Supabase dashboard → Settings → API → regenerate → update every function that uses it.
4. The public `SUPABASE_ANON_KEY` in the client is *designed* to be public (RLS is the guard) — rotating it means updating script.js too.

## Backup & restore

- **Current risk:** the project is on the Supabase **free tier — no automated backups, and it auto-pauses after 7 days idle**. Upgrade to Pro ($25/mo) before charging money.
- Once on Pro: dashboard → Database → Backups. **Exercise one restore into a scratch project and note the steps here** (unexercised backups don't count).
- Users' JSON export (Settings → Data) is a per-user fallback, not a substitute.

## Incidents

**Kill switches, in order of severity:**
1. AI misbehaving/cost spike → Supabase → Edge Functions → disable `ai` (app falls back to BYO-key only).
2. Data concern → Supabase → Auth: disable sign-ups; worst case pause the project (Settings → General).
3. Site-level problem → GitHub repo → Settings → Pages → unpublish (takes the whole app offline).

**Steps:** contain (rotate secrets / disable function) → assess via Supabase logs (Functions → Logs; Auth → Logs) → fix → notify affected users (and parents for under-13 accounts) per the WISP → write a 5-line post-mortem in this file's changelog.

**Watch-fors:** OpenAI spend (platform usage page — hard cap set in the OpenAI billing dashboard), Supabase egress/DB size, GitHub Pages status (githubstatus.com), Netlify credit emails (until the site is deleted — see Hosting section).

## Known gaps (tracked in GA plan)

- No server-side alerting or status page yet — failures surface via user email only.
- No second operator: if Chase is unreachable, this runbook + password-manager emergency access is the plan.

## Emergency contacts / accounts

GitHub, Supabase, OpenAI, Stripe, Cloudflare — all under mayechase2@gmail.com. Support inbox: support@nexusasc.com. *(Keep credentials in a password manager with a family emergency-access contact — not in this file.)*
