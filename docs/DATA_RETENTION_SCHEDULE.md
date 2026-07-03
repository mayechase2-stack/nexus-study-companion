# NEXUS — Data Retention & Deletion Schedule

**Status: DRAFT for privacy-counsel review — not yet adopted.**
Owner: Chase Maye · Product: NEXUS (nexusasc.com) · Last updated: July 3, 2026

Principle (per the amended COPPA Rule): children's personal information is kept **only as long as reasonably necessary for the purpose it was collected**, and is never retained indefinitely by default. This schedule applies to all users, with stricter handling noted for under-13 accounts.

| Data category | Retention | Deletion trigger / mechanism |
|---|---|---|
| Account identity (username, email, hashed password) | Life of the account | Account deletion request (user or parent) → removed from Supabase Auth + `profiles` |
| Date of birth / age-gate result | Life of the account | Deleted with account |
| Under-13 parental consent record (parent email, consent timestamp) | Life of the account **+ 3 years** kept as a minimal compliance record *(counsel: confirm period)* | Purged on schedule after account deletion |
| Study progress / app state (`app_state`) | Life of the account | Deleted with account; user can also clear via Settings → Data |
| AI prompts and Live Vision images | **Not stored by NEXUS** — forwarded transiently to OpenAI at question time | OpenAI API retention governed by OpenAI's terms *(counsel: reference in notice)* |
| AI usage counts (`ai_usage`) | 24 months rolling | Automatic purge **[PLANNED]**; deleted with account |
| Server/function logs | 90 days | Automatic (Supabase default) *(confirm setting)* |
| Waitlist entries (email, name, plan interest) | Until launch announcement + 12 months, or opt-out | Manual purge on schedule |
| Stripe billing records (once live) | Per legal/tax requirements (typically 7 years) | Held by Stripe; not deleted with app account |
| Local device data (localStorage) | Until the user clears it | User-controlled: Settings → Data, or browser clearing |
| User-downloaded JSON backups | User-controlled | Outside NEXUS's custody |

## Deletion paths

1. **User-initiated:** Settings → Data (local wipe + export); email support@nexusasc.com from the account email for full cloud deletion. Target turnaround: 7 days.
2. **Parent-initiated (any account belonging to their child):** email support@nexusasc.com; identity verified against the consent-record parent email. Parents may review, correct, or delete the child's data and refuse further collection (COPPA rights — counsel to confirm the notice states them).
3. **Dormancy:** **[PLANNED — counsel input]** accounts inactive 24 months receive a notice email, then deletion 60 days later. Under-13 accounts: counsel to advise if a shorter window is expected.

## Open questions for counsel

- Required retention period for parental-consent records after deletion.
- Whether OpenAI's API terms need to be summarized or merely referenced in the parental notice.
- State-law overlays (e.g., CA/NY student-privacy rules) if any school-adjacent use emerges.
