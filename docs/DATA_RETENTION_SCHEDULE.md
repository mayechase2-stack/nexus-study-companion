# NEXUS — Data Retention & Deletion Schedule

**Status: ADOPTED (self-drafted v1, November 14, 2026).** Matches the public Privacy Policy at nexusasc.com/privacy.html (section 7). An attorney review is still recommended but not required to operate.
Product: NEXUS (nexusasc.com)

**Age rule:** NEXUS accounts and purchases are 13+ only (`MIN_AGE` in script.js, enforced at sign-up, on every sign-in via `_nxAgeGate` in `completeLogin`, and on the purchase screen). Children under 13 may use NEXUS only with a parent/guardian, on the adult's account, under supervision. NEXUS does not knowingly collect personal information from children under 13; if a child's own account is discovered, it is deleted.

| Data category | Retention | Deletion mechanism |
|---|---|---|
| Account identity (username, email, password hash) | Life of the account | Settings → Data & History → Delete My Account (calls the `delete-account` Edge Function: deletes `app_state` + the auth user; `profiles`, `subscriptions`, `ai_usage`, `parental_consent` cascade) |
| Date of birth (age check) | **Not kept** (v24.50) — checked once, then discarded; only a yes/no `age_ok_<user>` flag is kept | n/a; migration 0012 drops `profiles.dob` |
| Study progress / synced app state (`app_state`) — progress only; personal keys (`_NX_PRIVATE_KEYS`: chats, history, lessons, companion memory, DOB, API keys, profile pic/bio, library, scans) never sync (v24.50) | Life of the account | Deleted with the account; local copy cleared by the same button |
| AI prompts and images | **Not stored by NEXUS** — forwarded to OpenAI at question time | OpenAI API retention per OpenAI's policy (currently up to 30 days, not used for training by default) |
| AI usage counts (`ai_usage`), rate-limit records incl. IP (`ai_recent`, `ai_ip_usage`) | Up to 24 months | `nexus_purge_old_records()` daily via pg_cron (migration 0011) |
| Feature-usage events (`feature_events`) — opt-in only, anonymous | Up to 24 months | Same purge job |
| Error reports (`client_errors`) | Up to 24 months | Same purge job |
| Feedback (`feedback`) | Up to 24 months | Same purge job |
| Server/function logs | ~90 days | Supabase default |
| Leaderboard row (opt-in) | While opted in | Removed automatically when the user turns it off |
| Stripe billing records (once live) | As required for tax/accounting | Held by Stripe |
| Local device data (localStorage / IndexedDB) | Until the user clears it | Settings → Data & History, or browser settings |

## Deletion requests

1. **In-app:** Settings → Data & History → "Delete My Account & All Data".
2. **By email:** support@nexusasc.com from the account's email address. Commitment: completed within **30 days**.
3. **Parents/guardians:** email support@nexusasc.com; verify the relationship/identity before acting. Delete any account found to belong to a child under 13.

## To do (owner)

- ~~Run 0011~~ done 2026-11-15. Run `supabase/migrations/0012_strip_personal_sync.sql` once (removes personal keys older versions synced).
- Optional: have an attorney review the Privacy Policy and Terms; add the operator's legal name and mailing address to both pages if/when you're comfortable publishing them (some state laws expect a postal address).
