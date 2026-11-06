# NEXUS — Product & GA-Readiness Brief
**Prepared for:** external GA market analysis + readiness scorecard
**App version:** v18.4 ("Polish & True Tracking")
**Status:** Live in **free open beta** at **https://nexusasc.com**
**Date of brief:** 2026-06-29

> This document describes what NEXUS is, what's built, how it's deployed, how it makes money, and — importantly — what is **deliberately not done yet**. It is written to be scored honestly for commercial (paid, public) release. Where something is beta/test-mode/deferred, it says so.

---

## 1. Product summary

**NEXUS** is an AI study companion for students **Grade 9 through college**, covering **Math, Science, English, and Social Studies**. Its core differentiator vs. a generic chatbot is a **Socratic "Tutor Mode"** that coaches the student to the next step instead of dumping answers, wrapped in a full study toolkit (notebook, flashcards, quizzes, grade tracking, focus tools) and a **gamified progression system** (XP, levels, ranks, quests, rewards, cosmetics).

- **Positioning:** "Your AI tutor. Always ready. Never judging." — teaches you to think, not just finish homework.
- **Target user:** secondary + early-college students; built by a student.
- **Platform:** browser-based web app (desktop + mobile responsive); installable PWA.
- **Tone/brand:** dark, modern, gamified; purple/teal gradient identity.

---

## 2. Tech stack & architecture

| Layer | Implementation |
|---|---|
| **Frontend** | Vanilla JavaScript single-page app (no framework). One `index.html` + `script.js` (~26k lines) + `style.css`. |
| **Hosting** | GitHub Pages (static), auto-deploy on push to `main`. Repo: `mayechase2-stack/nexus-study-companion`. |
| **Domain / DNS / CDN** | Custom domain **nexusasc.com** via Cloudflare (registrar + DNS + email routing). HTTPS enforced (Let's Encrypt). |
| **Backend** | **Supabase** — Postgres + Auth + Edge Functions (Deno). Row-Level Security (RLS) for per-user data isolation. |
| **AI** | OpenAI (gpt-4o for vision/tutor, gpt-4o-mini for routine) via a **server-side proxy** (Supabase Edge Function) so users need no key. BYO-key also supported. |
| **Payments** | **Stripe** (currently **test/sandbox mode only**). À-la-carte subscription model. |
| **Email** | Cloudflare Email Routing → `support@nexusasc.com` (forwards to owner). EmailJS available for transactional/receipts (optional). |
| **Offline/PWA** | Service worker (network-first, offline fallback), web manifest, installable. |
| **Auth (legacy + unified)** | Originally local username/password (hashed via `crypto.subtle`, localStorage). Now **unified** so signup/login automatically creates + uses a Supabase cloud account (cross-device sync). Local-only still works if offline/not signed in. |

**Architecture notes for scoring:**
- The app is **client-side**, so any client-only entitlement (e.g., "this module is unlocked") is **not secure on its own**; real enforcement requires the backend (built, see §6/§7).
- Edge Functions deployed: **`ai`** (hosted AI proxy with per-user monthly usage tracking) and **`checkout`** (Stripe Checkout session creation). Secrets (OpenAI key, Stripe secret, Supabase service role) live only in Edge Function env, never in the repo.

---

## 3. Feature inventory

### Core academic
- **AI Homework Help** across Math, Science, English, Social Studies — type, paste, or upload a photo.
- **Two tutoring modes:** **Tutor** (Socratic, step-by-step, never reveals the answer) and **Casual** (instant answers for quick checks).
- **Live Vision (screen reading):** reads on-screen material (any web platform — Acellus, Edgenuity, Canvas, Khan, etc.), detects question type (fill-in-blank, MCQ, true/false, matching, computation…), and explains it. Includes a **"Work it out" scratch board** so students attempt steps themselves. Positioned as a study aid with integrity disclaimers (not for graded tests).
- **Scientific calculator**, **grade/GPA tracker**, **formula cheat sheet**, **study planner**.

### Study tools
- **Smart Notebook** — lined paper, drawing canvas, tags, highlights, auto-save (to cloud when signed in).
- **Flashcards** with **spaced repetition (SM-2)**.
- **Quiz generator**, **citation generator**, **text summarizer/rewriter**, **literary analysis**.
- **Command Center** — one launcher for Live Vision, Quick Quiz, Math Visualizer, Science Simulator, History Timeline, Prompt Engine, English Generator, plus collapsible **Debate Practice** and **Study History** nodes.
- **Focus tools** — Pomodoro timer, ambient soundscapes (rain/café/white noise mixer), lo-fi.
- **Knowledge Library Hub**, **Word of the Day** + vocabulary.

### Gamification & engagement (expanded in v18.3)
- **XP + Levels** — earn XP from solving problems, claiming quests, and daily logins; level bar on the home hub.
- **Rank titles** — Novice → Student → Apprentice → Scholar → Honor Roll → Master → Sage → Legend.
- **Level-up rewards** with **milestone gold bonuses** at levels 3/5/10/15/20/25/30/40.
- **Quests** — hourly/daily/weekly with progress + claimable credit rewards (surfaced on the Profile).
- **Daily Reward chest** (gold + XP, streak bonus).
- **Achievements** with progress tracking; **leaderboard** (XP / problems / streak / minutes / badges).
- **Daily Challenge** on the home page; **study streaks** with streak-freeze.
- **Shop & economy** — earn credits, spend on **themes, wallpapers (animated + static), cursors, fonts, click/trail effects, badges, companions**; daily **Mystery Box**; mythic-tier cosmetics.
- **NEXUS Sprite companion** — on-screen study buddy that can **link to a session** (Math/Science/Live Vision) and answer follow-ups with full context; draggable/resizable chat; personas; memory across sessions.
- **Profile** — avatar, level ring, rank, XP, gold, stats (problems, streak, sessions, GPA, minutes), member-since, most-studied subject, flashcards due, today's quests, 7-day activity heatmap, next-milestone tracker.

### Customization
- Multiple themes (Dark/Grey/Onyx + light options), custom wallpaper upload, full cosmetic loadout, accessibility options (focus rings, reduced-motion, dyslexic font, compact UI), mobile-responsive layout.

---

## 4. AI capabilities & cost model

- **Hosted AI (no key needed):** prompts route through the `ai` Edge Function → OpenAI. Per-user **monthly usage count** stored (not prompt content) to enforce limits. Limit is currently set very high (effectively unlimited) during beta to gauge adoption; designed to support a **free-tester allotment** (e.g., 10 free uses/user/month) at launch.
- **Bring-your-own key:** users can paste a personal OpenAI key (stored in their browser) for unlimited use; it bypasses the proxy.
- **Models:** gpt-4o (vision, tutor, complex), gpt-4o-mini (routine) — routed for cost control.
- **Streaming:** responses stream token-by-token across features (tutor, subjects, prompt engine, deep dive, companion, concept board).
- **Cost exposure:** OpenAI billing is prepaid on the owner's account (currently ~$3 test credit). **A funded balance + spend cap is required before public scale.**

---

## 5. Accounts, data & privacy

- **Unified cloud accounts:** signing up/in creates + connects a Supabase account automatically; progress syncs across devices and survives a cache-clear. Local-only mode works without an account.
- **Data stored on backend (only with a cloud account):** email, auth record, and a synced copy of app data, protected by **per-user RLS**.
- **Local data:** username, password hash, settings, history, inventory, credits, quest state.
- **Downloadable `.json` backup** as an extra offline copy.
- **Privacy posture:** no ads, no selling data, no analytics on prompt content; prompts forwarded to OpenAI only to generate answers. Privacy Policy + Terms are **drafted and accurate** but carry a beta disclaimer (**not yet counsel-reviewed** — see §8).

---

## 6. Monetization model

- **À-la-carte "Build Your Plan":** users pick individual modules at **$2/month each, minimum 4** ($8/mo floor; all 8 modules = $16/mo). Modules: Math, Science, English Aid, Social Studies, Smart Notebook + Focus, AI Command Center, Shop/Customization + Companion, Competition.
- **Billing:** one Stripe recurring "module" price × quantity (= number of modules chosen); selected modules stored on the account.
- **Plan management:** built into signup (Step 1) and Settings → "Manage My Plan."
- **Current state:** **all free during open beta.** Stripe is wired in **test mode only** and dormant. Per-module entitlement *gating* is intentionally **off** during beta (so no one is locked out).

---

## 7. What's built vs. what's left (phased)

| Phase | Status |
|---|---|
| Domain + HTTPS + support email | ✅ Done (nexusasc.com) |
| Public launch (beta, indexable, sitemap, share meta) | ✅ Done |
| Backend: cloud accounts + cross-device sync (Supabase + RLS) | ✅ Done |
| Hosted AI proxy (no key needed) | ✅ Done & live |
| Payments plumbing (à-la-carte checkout, test mode) | 🟡 Built, dormant by design |
| **Stripe webhook (server-verified entitlements) + per-module gating + live mode** | 🔴 Not done (launch-time) |
| **Legal review (COPPA/FERPA) of Privacy/Terms** | 🔴 **Deliberately deferred** (owner chose to stay free-beta, low-risk, until ready to fund counsel) |
| Stripe business/bank verification + tax handling (Managed Payments) | 🔴 Not done (launch-time) |
| Optional: Google Sign-In, EmailJS receipts | ⚪ Optional, not wired |

---

## 8. Known gaps / pre-GA blockers (for honest scoring)

These are the items a paid-public launch still needs:

1. **Legal/compliance (highest priority):** The app collects data from **minors** (date of birth, under-13 parental-consent email, accounts, prompts to OpenAI). It has an **age gate + parental-consent flow** and drafted policies, but **no attorney review** of COPPA/FERPA compliance yet. This is the gating item for charging money / scaling to real minors.
2. **Payments not live:** webhook for server-verified purchases, per-module gating enforcement, and Stripe live-mode (business + bank verification) are not done.
3. **AI cost/billing at scale:** only a small prepaid OpenAI balance; needs a funded account + spend caps + abuse limits before public scale.
4. **Security hardening:** entitlements must be enforced server-side (client-side unlock is bypassable); no formal pen-test.
5. **Accessibility:** good baseline (landmarks, focus rings, reduced-motion, dyslexic font) but **no formal WCAG audit**.
6. **Support/ops:** single support inbox; no ticketing, status page, or monitoring/alerting beyond client-side error logging.
7. **Single maintainer / bus factor:** built and operated by one student.
8. **No real user reviews/testimonials yet** (intentionally omitted rather than fabricated).
9. **Content accuracy/safety:** AI can be wrong; disclaimers present; hosted moderation is currently fail-open (not enforced) for hosted-AI users.

---

## 9. Recent development history (condensed changelog)

- **v17.1–17.6:** Removed card collection → free beta + age gate + parental consent; real Privacy/Terms; AI accuracy disclaimers; reworked loot-box into a non-gambling daily Mystery Box; error monitoring + built-in self-test diagnostics; accessibility/mobile/perf passes; honest positioning.
- **v18.0:** Cloud accounts + cross-device sync (Supabase).
- **v18.2:** Hosted AI (no key needed); unified accounts; à-la-carte Build-Your-Plan + Stripe checkout (test); full landing-page rebuild; companion + Live Vision fixes.
- **v18.3 ("The Progression Update"):** XP/levels/ranks that actually progress; level-up + milestone rewards; daily reward chest; revamped profile; gamified home hub; 2 new shop badges; plus a wave of bug/UX fixes — hosted-AI streaming (blank-answer fix), Live Vision answer clipping, study-activity heatmap clipping, scratchpad sizing, home declutter, collapsible Debate/Study-History nodes, a "Work it out" board in Live Vision, and a **content/claims accuracy pass** (corrected privacy copy that falsely said "100% local / data never leaves your browser" now that cloud + hosted AI exist).
- **v18.4 ("Polish & True Tracking"):** real study-time tracking (heatmap + profile now show true minutes; previously always zero); Today's Quests moved to Profile, Daily Challenge back on home; rewarding level milestones; Social Studies + Command Center declutter (collapsible nodes/sections); **draggable, persistent sidebar width**; privacy-copy accuracy fix; achievement-on-open bug fix (Lore Keeper no longer auto-granted at launch). A built-in self-test (`runNexusDiagnostics`) was run headless: **40 pass / 1 warn (not-signed-in AI notice) / 0 fail.**

---

## 10. Quick facts for the scorecard

- **Live URL:** https://nexusasc.com (free beta, indexable)
- **Current version:** v18.4
- **Pricing (planned):** à-la-carte, $2/module/mo, 4-module minimum ($8–$16/mo range); free during beta
- **Backend:** Supabase (Postgres/Auth/Edge Functions, RLS)
- **AI:** OpenAI via server-side proxy (no key needed) + BYO-key option
- **Payments:** Stripe (test mode, dormant)
- **Compliance:** age gate + parental consent in product; policies drafted; **counsel review pending**
- **Biggest blockers to paid GA:** legal review, live payments + server-side entitlement gating, funded AI billing + abuse controls
- **Team:** solo (student founder)

*End of brief.*
