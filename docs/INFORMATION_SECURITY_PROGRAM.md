# NEXUS — Written Information Security Program (WISP)

**Status: DRAFT for privacy-counsel review — not yet adopted.**
Owner: Chase Maye (founder/operator) · Product: NEXUS (nexusasc.com) · Last updated: July 3, 2026

The amended COPPA Rule requires operators collecting children's personal information to maintain a written information-security program. This document describes NEXUS's current controls and committed practices. Items marked **[PLANNED]** are not yet live and are tracked in the GA launch plan.

## 1. Scope and data inventory

NEXUS collects and processes, for students in Grade 9 through college (including users under 13 with parental consent):

| Data | Where it lives | Purpose |
|---|---|---|
| Username, email, hashed password | Supabase Auth (Postgres, US region) | Account + cross-device sync |
| Date of birth, under-13 parent email + consent record | Supabase `profiles` / localStorage | Age gate, parental consent (COPPA) |
| Study progress, notes, app state | Supabase `app_state` + device localStorage | The product itself |
| Study questions/prompts (incl. Live Vision images) | Transient — forwarded to OpenAI via Edge Function; usage *counts* stored, prompt content not stored server-side | AI answers |
| AI usage counts per user | Supabase `ai_usage` | Rate/limit enforcement, cost control |

NEXUS does not collect payment card data (Stripe hosts all payment fields), precise location, or contacts; there are no ads and no sale of data.

## 2. Access controls

- Every user-data table has Postgres **Row-Level Security** enforcing owner-only access; verified per table.
- Secrets (OpenAI API key, Stripe secret key, Supabase service-role key) exist **only** in Supabase Edge Function environment variables — never in the repository, client bundle, or browser.
- Privileged operations run server-side in Edge Functions; the client holds only the public anon key.
- Administrative access: Supabase, Stripe, GitHub, and Cloudflare accounts are held by the founder. **[PLANNED]** Hardware-key 2FA on all four; an emergency-access note for a designated adult (bus-factor mitigation).

## 3. Transmission and storage security

- All traffic is HTTPS/TLS (GitHub Pages + Cloudflare front end; Supabase APIs).
- Passwords are hashed (client-side legacy path) and managed by Supabase Auth (bcrypt) for cloud accounts.
- **[PLANNED]** Supabase Pro tier for daily automated backups; restore procedure exercised and documented in the Operations Runbook.

## 4. Service providers (processors)

| Provider | Role | Data shared |
|---|---|---|
| Supabase | Database, auth, functions hosting | All account + app data |
| OpenAI | AI model provider | Study prompts/images at question time; per its API data-usage terms (no training on API data) |
| Stripe | Payments (dormant during beta) | Payment/billing data once live |
| GitHub Pages / Cloudflare | Static hosting / DNS-CDN | No user data at rest |
| EmailJS | Transactional email (not yet configured) | Username + email when enabled |

Counsel to confirm each is named appropriately in the Privacy Policy's third-party notice, and whether any disclosure requires separate verifiable parental consent under the amended Rule.

## 5. AI safety controls

- Hosted AI runs through a single Edge Function (`ai`) with per-user usage metering.
- **[PLANNED — P0]** Fail-closed moderation on hosted AI input and output; per-user and per-IP rate limits; hard monthly OpenAI spend cap.

## 6. Incident response

See `docs/OPERATIONS_RUNBOOK.md` §Incidents. Summary commitment: contain (rotate affected secrets, disable affected function), assess scope via Supabase logs, notify affected users — and parents, for under-13 accounts — without unreasonable delay, and record a post-incident note. Counsel to advise on statutory notification triggers/timelines by state.

## 7. Data retention and deletion

Per `docs/DATA_RETENTION_SCHEDULE.md`. Users can export their data (Settings → Data) and request full cloud deletion via support@nexusasc.com; parents may make requests on a child's behalf.

## 8. Review

This program is reviewed at every major release and at least every 6 months, and updated when a new provider, data type, or feature is added.
