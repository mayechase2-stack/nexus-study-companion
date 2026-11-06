# NEXUS — Build & Commercial-Readiness Report

> **Purpose:** A factual snapshot of the NEXUS study app as currently built, prepared to feed into a market analysis / GA (general-availability) readiness scorecard.
> **As of:** v16.5 · June 2026
> **Live (unlisted):** `https://mayechase2-stack.github.io/nexus-study-companion/` *(set to `noindex` — link-only, not in search)*
> **Source:** GitHub repo `mayechase2-stack/nexus-study-companion` (public, auto-deploys to GitHub Pages on push)

---

## 1. Executive Summary

NEXUS is an **AI-powered study companion** for high-school and early-college students. It bundles subject tutoring, screen-reading homework help, flashcards, quizzes, a grade calculator, focus tools, and a gamified rewards layer into a single web app.

It is currently a **100% client-side application** — vanilla HTML/CSS/JS with no backend server. All data lives in the browser (`localStorage`); AI runs on the **user's own OpenAI API key**. It is an installable PWA hosted free on GitHub Pages. Accounts, payments, and Google sign-in exist as **client-side / mock implementations** today.

**Bottom line for GA:** the product surface is broad and polished, but the commercial spine (real accounts, real billing, managed AI access, data durability) requires a **backend that does not yet exist**. The biggest GA gaps are infrastructure, not features.

---

## 2. Product Overview

- **Target user:** Grade 9–12 students; tutoring content also spans early undergraduate.
- **Core value prop:** "Ask anything, get clear explanations — learn to think, not just finish homework."
- **Subjects:** Math, Science, English (English Aid), Social Studies.
- **Form factor:** Single-page web app + installable PWA (desktop + mobile).
- **AI model:** OpenAI **GPT-4o** (and `gpt-4o-mini` for lighter tasks) via the Chat Completions + Vision APIs.

---

## 3. Tech Stack & Architecture

| Layer | Implementation |
|---|---|
| Frontend | Vanilla **HTML / CSS / JavaScript** (no framework). Single large `script.js` (~24k lines), `index.html`, `style.css`. |
| AI | OpenAI GPT-4o / gpt-4o-mini; vision via base64 screen captures; streaming for some flows. |
| Persistence | **Browser `localStorage` only** (accounts, history, settings, XP, inventory, decks, grades, etc.). |
| Auth | Local username/password in `localStorage`; **client-side Google Sign-In** (Google Identity Services) built but dormant until an OAuth Client ID is added. |
| Payments | **Mock checkout** (no real processor). Optional **EmailJS** receipt (client-side, built, dormant until configured). |
| PWA | `manifest.json` + **service worker** (network-first; installable + offline fallback). |
| Hosting | **GitHub Pages** (static), auto-deploy on push to `main`. Free, HTTPS. |
| Discoverability | `noindex` + `robots.txt` → link-only, intentionally not indexed. |

**Architectural implication:** Because there is no server, anything requiring a secret, a shared resource, or cross-device state cannot be done securely today (see §9 and §10).

---

## 4. Feature Inventory

### 4.1 AI / Learning (core)
- **Universal Tutor** — subject-aware AI tutoring with two modes: **Tutor Mode** (Socratic hints, withholds the answer) and **Helper Mode** (full explanations). One-tap "Ask Tutor" across subjects. **Per-session conversation memory** (configurable session window; resumes on reopen).
- **Live Vision** — screen-share capture → GPT-4o vision; detects and answers many question formats: multiple-choice, fill-in-the-blank, true/false, matching, multi-select, drag-and-drop, computation, definitions, and (v16.5) **graphs/charts, labeled diagrams, and data tables**.
- **Quiz Generator** — paste notes → AI multiple-choice quiz with scoring/explanations (in Notebook).
- **Flashcards (SRS)** — SM-2 spaced repetition; create manually, **AI-generate from a topic or from study history**, CSV/Quizlet import (in Notebook).
- **Debate Practice** — pick a topic + side; AI argues the opposite and judges (on Home).
- **Citation Generator** — MLA / APA / Chicago, multiple source types (in English Aid).
- **Companion ("NEXUS Sprite")** — wandering avatar + chat; selectable **personalities** (Default, Drill Sergeant, Best Friend, Sherlock, Chill Sensei); **long-term memory** with configurable retention.
- **Daily Challenge** — daily question with streaks/rewards (on Home).
- **Timed Practice Test** — subject/difficulty/length, countdown, score card.

### 4.2 Productivity
- **Notebook** — rich notes (auto-save) + drawing canvas; now also hosts **Quiz Gen** and **Flashcards** tabs; PDF export.
- **Grade Calculator** — weighted course averages, letter grades, **proper 4.0 GPA scale**, target-grade tracking ("what you need next"), built-in how-to/purpose guide.
- **Study session tracking** + **7-day Study History** chart (on Home).
- **Lo-fi music player** — bundled royalty-free MP3s (no ads, offline); play/skip/volume, sleep timer, persisted track.
- **Focus/ambient sounds** — Storm, Café, White Noise, Fireplace, Stream (YouTube-backed; may show ads).
- **Quick Notes** — draggable floating notepad bubble.

### 4.3 Engagement / Gamification
- **XP + levels**, **achievements** (tiered), **multi-category leaderboard** (XP / Problems / Streak / Minutes / Badges; simulated competitors).
- **Credits economy + Shop** — themes, cursors, fonts, wallpapers, badges, click effects; gamble/slot; refunds.
- **Merged Profile tab** — customization (avatar, bio, grade), level title, member-since, most-studied subject, streaks, stats, achievements grid.

### 4.4 Platform / UX
- Installable **PWA** (offline), responsive layout w/ mobile touch polish, light/dark themes, accessibility high-contrast mode, in-app **Help & FAQ**, dynamic **changelog/Updates** page, community **Suggestions/roadmap** board with owner-pinned items.

---

## 5. Monetization Model (as built — mock)

| Tier | Price | Includes |
|---|---|---|
| **Access** | **$4.50/mo** | The 4 subjects + Tutor Mode + Live Vision + essentials |
| **Pro** | **$6.00/mo** | Everything in Access **plus** Command Center, Notebook, history, achievements, leaderboard, shop, inventory, 300 starter gold |
| Owner | — | Full unlock (PIN) |

- Checkout is a **mock form** (collects card-like fields, validates format, but **processes nothing real** — no Stripe/processor).
- After "purchase," tier is set in `localStorage`; a post-signup paywall lock gates the app.
- **AI cost model:** currently **BYO OpenAI API key** (each user pays OpenAI directly). There is **no managed/host key** (a previously hardcoded host key was removed for security).

**GA implication:** there is **no real revenue capture and no managed AI access**. Converting "buyers" to paying subscribers and giving them frictionless AI both require a backend (billing + an API proxy).

---

## 6. Security & Privacy Posture

- **Privacy-friendly by design:** no analytics/telemetry; prompts and data stay in the browser; the user's OpenAI key is sent only to OpenAI.
- **Known weaknesses (client-only):**
  - Accounts/passwords live in `localStorage` (no server-side auth; limited protection).
  - No real session security or cross-device identity.
  - AI responses are injected as HTML (XSS surface to harden if user-generated content is ever shared).
  - A hardcoded OpenAI host key was **exposed and removed**; the leaked key was revoked. (Lesson reflected in current "BYO key" design.)
- **Data durability:** clearing the browser = losing the account/history (no backup/sync).

---

## 7. Known Limitations / GA Blockers (most important section)

These are the gaps a GA readiness scorecard should weigh heavily. **All stem from "no backend."**

1. **No real accounts / cross-device sync** — data is per-browser only. *(Needs server + database.)*
2. **No real payments** — checkout is a mock; no Stripe, receipts, subscriptions, refunds, or revenue. *(Needs server + Stripe.)*
3. **BYO API key friction** — non-technical students must create/paste an OpenAI key to use AI. High drop-off risk. *(A server-side proxy would let NEXUS provide AI under a plan, with rate limits + spend caps.)*
4. **Google Sign-In** — client-side identity only (no secure server session); dormant until an OAuth Client ID is set.
5. **Hosting/domain** — on a free `github.io` subdomain; a `.com` + branding needed for credibility.
6. **Mobile** — installable PWA with touch polish, but not a native app-store presence.
7. **Localization** — UI language switcher (EN/ES/FR) covers navigation/labels only, not full app or AI output.
8. **Content trust** — AI answers are not verified; no guardrails/citations on correctness; academic-integrity positioning needed.

---

## 8. Roadmap (owner-pinned)

| Item | Status |
|---|---|
| Timed practice test, Lo-fi music, Debate mode, Companion personalities, Pixel cursors, High-contrast, **Live Vision++**, **Installable PWA**, **Sign in with Google (client-side)**, **Language switcher** | ✅ Shipped |
| **Real .com launch** | In progress (domain purchase pending) |
| **Live Vision improvements** | ✅ Shipped (graphs/diagrams/tables) |
| **Mobile / PWA polish** | ✅ Shipped |
| **Real cross-device accounts** | Planned — **needs backend** |
| **Stripe payments** | Planned — **needs backend** |
| Spanish/French full localization | Planned (basic switcher shipped) |

---

## 9. Suggested Scorecard Dimensions (for the analysis)

When scoring GA readiness, consider rating each 1–5:

- **Product breadth / feature completeness** — *(high; broad, polished surface)*
- **Core value & differentiation** vs. competitors (Khanmigo, Quizlet, Photomath, ChatGPT, Socratic, Chegg)
- **Monetization viability** — *(low today; mock only, no revenue/AI-cost model)*
- **Infrastructure / scalability** — *(low; static, no backend, browser-only data)*
- **Onboarding friction** — *(elevated; BYO API key)*
- **Trust & safety / academic integrity** — *(unaddressed)*
- **Data durability & privacy** — *(privacy good; durability poor)*
- **Brand / distribution readiness** — *(unlisted, subdomain, no marketing funnel)*
- **Regulatory** — *(student/minor data, COPPA/FERPA considerations once accounts/payments are real)*
- **Unit economics** — *(undefined; depends on AI cost model decision)*

---

## 10. The One Strategic Decision Before GA

Everything commercial hinges on building a **backend**: it unlocks real accounts, real billing, and a server-side OpenAI proxy (so students get AI without their own key, with rate limits + spend caps). Until that exists, NEXUS is best characterized as a **feature-complete, privacy-friendly prototype / personal tool** rather than a revenue-ready commercial product.

*Report generated to support external market analysis. Figures (pricing, features) reflect the in-app configuration at v16.5.*
