# NEXUS — What's Holding Us Back

Honest, current state as of 2026-07-28. The app is **live and fully functional as a
free beta** — nothing below blocks a student from using it today. These are the gaps
between "working free beta" and "charging money / running at scale."

---

## 🟢 Not blocked
- App is live at nexusasc.com, all subjects + tools working (verified via live test).
- Owner account server-verified (`tier=owner`). Strict no-email AI gate live + verified.
- Auto cloud-sync, per-account data, single-session all shipped.

---

## 🟡 Backend cleanliness (should fix — low urgency, no user impact today)

1. **`ai_gate` is a stale version.** The Step-1 SQL didn't replace it (likely a duplicate
   overloaded function). Result: the per-user **monthly cap (1500)** and per-IP cap may
   not enforce for verified users. Strict-email and per-minute rate limits are unaffected
   (enforced elsewhere). Backstop: the OpenAI spend cap. **Fix:** a migration that DROPs
   all `ai_gate` overloads then recreates one clean copy.

---

## 🟠 Data safety (real, money-adjacent)

2. **No cloud database backups** (Supabase free tier). All cloud data — accounts, notes,
   owner tier — has no safety net. **Free fix:** a GitHub Actions scheduled `pg_dump`
   workflow (weekly snapshot, $0). Paid fix: Supabase Pro ($25/mo, automatic backups).

---

## 🔴 Paid-launch gates (the real "can't charge money yet")

3. **COPPA / privacy legal counsel** — THE gate. The app collects data from minors
   (DOB, parental-consent email, accounts, prompts to OpenAI). Age gate + consent flow +
   drafted policies exist, but **no attorney review**. Nothing about charging money or
   scaling to real minors should happen before this.
4. **Stripe live mode** — currently test/sandbox only. Needs: business + bank verification,
   deploy the `checkout` and `stripe-webhook` Edge Functions, live-mode keys.
5. **Per-module entitlement gating** — intentionally OFF during beta (nobody's locked out).
   Must be enforced server-side before paid, or entitlements are bypassable.
6. **Privacy policy page live** — matching the real data behavior (hosted-AI proxy, cloud
   sync, telemetry). Drafted; needs to be published + counsel-checked (ties to #3).

---

## ⚪ Scale / operational (not blockers for beta, matter later)

7. **AI cost at scale** — OpenAI billing is prepaid; a spend cap is set. Many verified
   users = real monthly cost. Watch usage; the caps in #1 exist to bound it.
8. **Single maintainer / bus factor** — built + run by one person.
9. **Monitoring** — only client-side error logging (`client_errors`). No uptime/alerting.
10. **Security** — client-side owner PIN backdoor is plaintext in `script.js` (kept by
    choice); entitlements not yet server-enforced; no formal pen-test.

---

## 🔵 Nice-to-have (deferred, not blocking)

11. **Native identity linking** — email + Google currently reconcile at the app layer
    (both resolve to the same local account) rather than as one Supabase auth user via
    `linkIdentity`. Works for users; cleaner if unified later.
12. **WCAG accessibility audit** — good baseline (landmarks, focus rings, reduced-motion,
    dyslexic font), no formal audit.

---

### Shortlist if the goal is "make it a real paid product"
1. Lawyer (COPPA) — #3. Everything else is downstream.
2. Stripe live + webhook + gating — #4, #5.
3. Backups — #2 (do the free GitHub Actions version now regardless).
4. Clean up `ai_gate` — #1.
