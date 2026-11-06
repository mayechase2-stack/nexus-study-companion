# NEXUS — Full Feature Test Report + Proposed Update v234

**Date:** 2026-07-22 · **Audited against:** `v=20260716v233` · **Built as:** `v=20260722v234` (app v19.6)

**Status: BUILT AND VERIFIED LOCALLY — NOT COMMITTED, NOT PUSHED.**
Chase approved the full scope on 2026-07-22 ("do the toggle for both and build it all"). Every
item below is implemented in the working tree and verified in the preview. The push is his call —
pushing deploys straight to nexusasc.com.

### Verification run (all green)

| Check | Result |
|---|---|
| `node --check script.js` | PASS |
| Mode audit (`docs/mode-audit.js`), 19 tools × 2 modes | **38/38 OK** — every English row sends no mode block in either mode; Math/Science/Social still do |
| Word-count chain, essay + 5 paragraphs + 100 words | Directive sent, 60-word draft detected, one repair pass, final **100 words**, counter green |
| Paragraphs dropdown gating | Enabled for Essay only; disabled + reset to Auto for Standard/Paragraph/Document |
| Mode badge | 6 badges, all sync on click, Casual ⇄ Tutor both directions |
| Prompt Generator Ctrl+V screenshot | Image stored + thumbnail badge appears (this textarea previously ignored paste entirely) |
| Short / Detailed toggle | Persists to localStorage, both prompts wired |
| Debate Practice separation | 34px gap + own uppercase heading, at desktop **and** 375px mobile |
| AI Tools grid | 8 cards, AI Flashcards in the freed slot |
| Full tab sweep (18 views) | 0 blank, 0 JS errors |
| Dead-handler scan (263 handlers) | 0 dead |
| Mobile 375px | No horizontal scroll, controls wrap cleanly |

---

# PART A — TEST REPORT

## A.0 How this was tested

Two passes, one in **Casual mode** and one in **Tutor mode**, over the whole app:

1. **Prompt-capture harness** — `window.fetch` was intercepted in the preview so every outgoing
   AI request was recorded (model, full system prompt, user content, max_tokens, temperature)
   and answered with a canned reply. This proves *exactly* what each feature sends to the model
   in each mode, without spending API credit or needing a signed-in account.
2. **DOM/JS sweep** — every one of the 19 views was opened, every `onclick` / `onchange` /
   `onkeydown` handler in `index.html` was resolved against `window` to find dead buttons, and
   `error` + `unhandledrejection` were hooked throughout.

Not covered (needs a real screen-share / real account, flagged as untested, not as passing):
Live Vision capture path, Supabase sign-in / cloud-sync / leaderboard writes, Stripe checkout,
and true model output quality (only the *requests* were verified, not live answers).

## A.1 Health check — nothing is crashing

| Check | Result |
|---|---|
| Page load console errors | **0** |
| All 19 views open and render | **PASS** (18 with content, 1 empty — see B-7) |
| Dead `onclick` handlers across the whole app | **0** (249 distinct handlers resolved; `Math.factorial` is polyfilled at `script.js:15956`, `saveProfile` is `NexusMemory.saveProfile` — both false alarms) |
| Uncaught JS errors during the tab sweep | **0** |
| Image-paste wiring | 6 of 7 targets wired (see B-6) |

The app is structurally healthy. **Every problem found this round is a prompt-content problem,
not a code-crash problem** — which is exactly the class of bug automated scanning missed before
and only real use surfaces.

## A.2 The casual/tutor matrix — the headline finding

`getModeSystemPrompt(subject)` (`script.js:3603`) appends a mode block to the END of the system
prompt. **The last instruction in a prompt is the one the model weights most heavily.** Here is
what actually got appended, per feature, verified by capture:

| Feature | Model | Casual mode appends | Tutor mode appends | Verdict |
|---|---|---|---|---|
| **English Generator → Write** | gpt-4o | `[CASUAL MODE]` "1-3 sentences max… keep total response short and punchy" | `[TUTOR MODE]` "Do NOT solve it… exactly TWO sections" | **BROKEN BOTH WAYS** |
| **English Aid → Fix Grammar** | gpt-4o-mini | `[CASUAL MODE]` brevity | `[TUTOR MODE]` don't-solve | **BROKEN in Tutor** |
| **English Aid → Summarize** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| **English Aid → Analyze** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| **English Aid → Rewrite** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| **English Aid → Essay Scorer** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| **English Aid → Essay Outline** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| **English Aid → Originality** | gpt-4o-mini | brevity | don't-solve | **BROKEN in Tutor** |
| Math Lab | gpt-4o | brevity | 3-block concept/strategy/your-turn | correct by design |
| Science Lab | gpt-4o | brevity | 3-block concept/terms/your-turn | correct by design |
| Social Studies (all 6 sub-tools) | gpt-4o-mini | brevity | 4-block facts/timeline/cause-effect/answer | correct by design |
| Live Vision | gpt-4o | shows "Solve This" | shows "Help Me" | correct by design |
| Prompt Engine | gpt-4o | *(none)* | *(none)* | mode-independent — fine |
| English Gen → Generate a prompt | gpt-4o | *(none)* | *(none)* | mode-independent — fine |
| Quick Quiz | gpt-4o | *(none)* | *(none)* | fine |
| Practice Test | gpt-4o | *(none)* | *(none)* | fine |
| Quick Study Quiz | gpt-4o | *(none)* | *(none)* | fine |
| Notebook Quiz Gen | gpt-4o | *(none)* | *(none)* | fine |
| Flashcard AI | gpt-4o-mini | *(none)* | *(none)* | fine |
| Concept Map | gpt-4o-mini | *(none)* | *(none)* | fine |
| Notebook Grammar | gpt-4o-mini | *(none)* | *(none)* | fine |
| Debate Practice | gpt-4o-mini | *(none)* | *(none)* | fine |
| History Timeline | gpt-4o-mini | *(none)* | *(none)* | fine |
| Dictionary | free dictionary API first, OpenAI fallback | n/a | n/a | fine |

**Read that top row again.** The English Generator — the tool whose entire job is to *write the
thing* — is told in Tutor mode:

> `- Do NOT reveal the final answer. Do NOT walk through every step. Do NOT solve it.`
> `- If asked "just give me the answer" — decline politely, mention Casual Mode in Settings.`

So in Tutor mode, "write my essay" returns a concept blurb and a guiding question. And the seven
English Aid tools get the same instruction stapled onto "Fix ALL grammar errors" / "Score this
essay out of 100" — a direct self-contradiction the model has to resolve on its own, differently
every time. That is almost certainly the source of inconsistent English results.

## A.3 Root cause of the 100-word → 78-word bug

Three causes stack, all in `processEnglishPrompt()` (`script.js:16484`):

**1. The casual-mode brevity clause is the last thing the model reads.** Captured tail of the
actual system prompt for "write a 100 word message about my school day":

```
[CASUAL MODE — INSTANT ANSWER]
- Lead with the answer in the first 1-2 sentences.
- Give the bare minimum supporting reasoning (1-3 sentences max).
- DO NOT walk through every step. Skip the hand-holding.
- For essay prompts, give the answer / thesis / conclusion directly.
- Keep total response short and punchy.        ← final line of the prompt
```

You asked for 100 words; the last thing the model was told was "1-3 sentences max, short and
punchy". 78 words is the model splitting the difference.

**2. There is no word-count enforcement anywhere.** The base prompt's LENGTH POLICY talks about
deliverable *shapes* ("a 5-paragraph essay = 600-900 words") but never says "if the user gives an
explicit count, hit it." Nothing parses "100 word" out of the request, nothing counts the output.

**3. No verification pass.** GPT-4o systematically undershoots explicit word targets by 10-25%
when it isn't told to count. 100 → 78 is textbook.

## A.4 Root cause of the "claim / reasoning / evidence" scaffolding

This is not a hidden feature someone added — it's emergent from the English Generator's system
prompt, which is an **analysis** prompt being used to drive a **writing** tool. `script.js:16506`
tells the model it is an "elite English tutor, writing coach, and literary scholar", then:

- `QUALITY BAR: Every claim about a text must be supported by a quoted phrase or paraphrased line`
- `OUTPUT REQUIREMENTS: Use <h3> for sections`
- `REASONING STRATEGY: 1. PARSE … 2. DIAGNOSE … 3. STRUCTURE … 5. CITE evidence`
- and in Casual mode, the appended `For essay prompts, give the answer / thesis / conclusion directly.`

Told to cite evidence, use `<h3>` sections, and lead with a thesis, gpt-4o produces
Claim → Reasoning → Evidence headers. Fix the prompt, the scaffolding disappears.

## A.5 Smaller findings

- **`view-homework` is an empty, unreachable div.** The Homework Tracker was removed (changelog
  v13.0, `script.js:20186`) but ~250 lines of `renderHomework` / `hwAiHelp` / `hwAiAsk` /
  `exportHomeworkPDF` still ship, plus a dead `updateHomeDailyChallenge()` that renders
  "→ Open Homework" into a `#home-tip-text` element that no longer exists.
- **`eng-gen-prompt-input` has no paste handler.** `attachImagePasteHandler` is registered for
  `math-text-input`, `science-input`, `english-prompt-input`, `prompt-engine-input`,
  `companion-chat-input` (`script.js:18497-18564`), and `english-input` has its own handler
  (`wireEnglishInputPaste`, `script.js:4622`). English Generator → *Generate a prompt* is the one
  text box in the app where Ctrl+V does nothing at all, silently.
- **English Aid's word limit is orphaned.** `#english-word-limit` (default 100) is read at
  `script.js:4811` but only ever used by the Summarize prompt. The other six tools ignore it.
- **English Generator has no length control at all** — no word count, no paragraph count, no
  format selector. Every length instruction has to be typed in prose and then loses a fight with
  the mode block.
- **Model split is inconsistent.** English Aid runs `gpt-4o-mini` for text (upgrading to `gpt-4o`
  only when an image is attached), while English Generator runs `gpt-4o` for everything. Same
  subject, two quality tiers, no user-visible reason.

## A.6 The brevity clause is a systemic bug, not an English-only one

Follow-up capture (2026-07-22) proves the 78-word bug's mechanism fires outside English too.

**Region Explorer, Casual mode.** The user prompt (`script.js:14275`) demands five `<h3>` sections
totalling roughly 300 words — Overview, History (~90 words), Government (~80), Economy (~80),
Why It Matters (~50). The system prompt then ends with:

```
- Keep total response short and punchy.        ← final line
```

Identical contradiction to the 100-word bug: an explicit length spec losing to a blanket brevity
instruction placed last. The same applies to Character / War / Civilization / Documents, which all
ask for ~100-word paragraphs, and to Math Lab (verified — same tail).

So this isn't "the English Generator has a bad prompt." It's **one blunt rule applied everywhere,
overriding every explicit length spec in the app.** Fix it once, centrally (D-2).

**And there is no mode indicator anywhere.** Neither the Command Center nor English Aid displays
which mode is active — verified, zero matches for "Casual mode" / "Tutor mode" in either view's
rendered text. You asked for 100 words, Casual mode silently edited the brief to "1-3 sentences",
and nothing on screen said so. That is why this bug survived until you counted the words by hand.

---

# PART B — PROPOSED UPDATE v234

Ordered by impact. Nothing here is written yet — this is the log to approve, reject, or edit.

## The three things you specifically asked for

### B-1. English Generator: pure writing, no analysis scaffolding
**Fix.** Replace the English Generator's system prompt with a writing-only prompt. Delete the
"literary scholar / cite evidence / `<h3>` sections / REASONING STRATEGY" material — that prompt
belongs to the *analysis* tools, not to a tool that writes things. New rules:

- Output **only** the requested piece. No preamble, no "Here's your message:", no closing note.
- **No headings, no labels, no Claim/Reasoning/Evidence structure** unless the chosen format is
  one that genuinely has headings (Document).
- Match the requested register — a message sounds like a message, not like an essay.
- Analysis, feedback and critique move to English Aid, where they already live.

### B-2. English Generator: two dropdowns
**New.** Above "Your request":

- **Type** — `Standard writing` · `Paragraph` · `Essay` · `Document`
  - *Standard writing* — messages, emails, replies, captions, short answers. Plain prose, no structure.
  - *Paragraph* — exactly one paragraph, no headings.
  - *Essay* — intro / body / conclusion, thesis-driven.
  - *Document* — report/letter/proposal shape; headings and sections allowed **here only**.
- **Paragraphs** — `Auto` · `3` · `4` · `5` · `6` · `7` · `8`. **Enabled only when Type = Essay**;
  greyed out and ignored otherwise, exactly as you described.

Both selections are compiled into a hard format directive prepended to the user's request, so
they beat anything ambiguous in the free-text box.

- **Word count** — a small number box next to the two dropdowns, blank = auto. **APPROVED
  2026-07-22.** This is the same plumbing as B-3 and it turns "100 words" from a hope into a
  setting: whatever is in this box becomes the hard target, and it overrides any count typed in
  the free-text request.

### B-3. Word-count adherence
**Fix.** Three layers:

1. **Parse** an explicit count out of the request (`/(\d{2,4})\s*[-–]?\s*words?/i`) or read it
   from the new Word count box.
2. **Inject a hard directive** when a count exists: *"Write between N-5% and N+5% words. Count
   your words before finishing. The count is a hard requirement, not a target."*
3. **Verify client-side.** Count the words of the finished output; if it lands more than 10% off,
   run **one** automatic repair pass ("expand/trim to exactly N words, keep the content, change
   nothing else"), then stop. One retry maximum — no loops, no runaway API spend.

Plus a live **word counter under the output box** so the number is visible instead of assumed.

### B-4. Remove Prompt Engine from the AI Tools grid, promote AI Flashcards into the slot
**Change.** Delete the Prompt Engine card (`index.html:1433-1439`). Also removed: the standalone
`#prompt-engine-panel` (`index.html:1740`) and the `#command-tool-switch` Debate/Prompt toggle
(`index.html:1731`) — with the prompt half gone there is nothing to toggle between.

**Q2 ANSWERED 2026-07-22 — grid stays at 8.** Debate Practice already occupies card 8, so the
freed slot goes to **AI Flashcards** (`openFlashcardAIGenerate` → `runFlashcardAIGenerate`).
Reasoning: it is a genuine AI tool that is currently three clicks deep (Notebook → Flashcards →
AI Generate) and has no sidebar entry of its own. Practice Test was the other candidate but it
*already* has a sidebar item (`index.html:1041`), so promoting it would just duplicate navigation.

Final grid: Live Vision · English Generator · Quick Quiz · Math Visualizer · Science Simulator ·
History Timeline · **AI Flashcards** · Debate Practice.

### B-5. Move Prompt Engine's guts into English Generator → Generate a prompt
**Change.** Not a merge of three tools into one — the *English Generator keeps its two tabs*
(Write something / Generate a prompt), and the Prompt tab's internals are swapped out for the
Prompt Engine's. What the Prompt tab gains that it does not have today:

| Prompt Engine has | English Gen → Generate a prompt has |
|---|---|
| Ctrl+V screenshot paste + persistent thumbnail badge with × | nothing — Ctrl+V is silently ignored |
| Forces `gpt-4o` when an image is attached | n/a |
| "GENERATED n PROMPTS" counter (`prompt_engine_uses`) | none |
| `prompt_forged` quest progress + achievement check | none |
| Logs to study history (`addToHistory('prompt-engine', …)`) | none |
| Copy button | Copy button (keep) |

Everything in the left column moves over. **See open question Q3** on short vs detailed output.

## Bug fixes

### B-6. Stop leaking mode prompts into do-it tools
**Fix.** Remove `getModeSystemPrompt('English')` from `processEnglishPrompt()` (`:16570`) and from
`englishAction()` (`:4926`). Casual/Tutor stays exactly as-is for the tools where it's a real
teaching choice: Math Lab, Science Lab, Social Studies, Live Vision, and the tutor chat.

Rationale: Casual/Tutor is a *teaching* preference — "show me vs walk me through it". It is not a
"refuse to write my essay" preference. Applying it to a generator is a category error, and it is
what breaks both modes at once in A.2.

*Optional follow-up:* if you want Tutor mode to still feel different in English, add a light
**tone** modifier ("explain your choices in one closing line") that changes the voice without
changing the deliverable. Not included unless you ask.

### B-6b. Debate Practice looks like it lives inside the English Generator
**Fix — reported by Chase 2026-07-22, confirmed in the DOM.** This is a real layout bug, not a
misread. Inside `view-dashboard`, these four elements are direct siblings in this exact order:

```
#english-prompt-panel      ← English Generator (hidden until you click its card)
#command-tool-switch       ← "Debate Practice | Prompt Generator" toggle  (ALWAYS visible)
#prompt-engine-panel       ← (hidden)
#command-debate-section    ← Debate Practice                              (ALWAYS visible)
```

The two Debate elements are always on screen. So the moment you open the English Generator, the
Debate/Prompt toggle appears **flush against the bottom edge of the English Generator panel**,
with no heading, separator, or spacing between them — it reads as a mode row belonging to the
English Generator. Same for the Debate section right below it.

Worse: B-4 deletes `#command-tool-switch` and `#prompt-engine-panel`, which would make
`#command-debate-section` the *immediate* next sibling of the English Generator panel and make
this look even more like one merged tool. So this fix is a **prerequisite** for B-4, not an
optional extra.

Fix: give Debate Practice its own labelled section in the Command Center — an uppercase
`<h3>` section header with top margin, exactly like the existing `AI Tools` and `Focus Sounds`
headers — and place it after the tool panels with real separation. The Debate Practice card in
the grid then scrolls to it instead of just un-hiding it in place.

### B-7. Delete the dead Homework code
**Fix.** Remove the empty `#view-homework` div, the ~250 lines of orphaned homework functions,
and `updateHomeDailyChallenge()`'s stale "→ Open Homework" string. Zero user-visible change, ~250
fewer lines in a 1.9 MB file.

### B-8. Give English Aid a real length control
**Fix.** `#english-word-limit` currently only affects Summarize. Either wire it into Rewrite and
Essay Outline too, or label it "Summary length" so it stops looking global. Recommend the label —
smaller change, no behavior surprise.

## My own proposals — not requested, these are the ones I'd argue for

### D-1. A mode-policy registry instead of eight scattered call sites
**Structural.** Right now each feature independently decides whether to append
`getModeSystemPrompt(...)`, by hand, at eight separate lines. That is exactly how the English
Generator ended up telling itself not to write. Replace it with one table:

```js
const TOOL_MODE_POLICY = {
  math: 'full', science: 'full', social: 'full', liveVision: 'full', tutorChat: 'full',
  englishGenerator: 'none', englishAid: 'none',
  promptGen: 'none', quiz: 'none', practiceTest: 'none', flashcards: 'none', debate: 'none'
};
```

`full` = the mode block applies. `none` = the tool does a job, mode is irrelevant. Adding a new
tool then forces an explicit choice instead of a silent copy-paste. **This is the fix I'd push
hardest for** — B-6 alone deletes two bad call sites; this makes the bug class unable to recur.

### D-2. Explicit length specs must beat the brevity clause
**Fix, generalises B-3.** Per A.6 this breaks Region Explorer and every Social Studies sub-tool,
not just English. One central rule in `getModeSystemPrompt`: if the request carries an explicit
length or section spec — a word count, a paragraph count, or an `<h3>`-section layout — the
Casual block drops its "1-3 sentences max" and "short and punchy" lines and keeps only "lead with
the answer, skip the hand-holding." Tone stays casual; the length spec wins.

Without this, B-3 fixes the English Generator and Region Explorer stays quietly truncated.

### D-3. Show which mode is active, on the tool itself
**New.** A small badge in each AI panel header — `CASUAL` / `TUTOR` — that switches mode on click.
Straight out of this incident: Casual mode rewrote your brief and nothing on screen admitted it.
Cheapest possible insurance against the whole class of "why did it do that?" reports, and it makes
the mode a deliberate choice per task instead of a setting you configured once and forgot.

### D-4. Check the audit harness in as a regression test
**New — `docs/mode-audit.js`.** The `window.fetch` capture rig I used for this report, saved as a
paste-into-console script that prints the tool × mode matrix from A.2 in about ten seconds. It
found four real bugs in one pass and costs zero API credit. The standing lesson in this project is
that automated scans catch crashes and dead buttons but never semantic bugs — this closes exactly
that gap, and it should be re-run before every release that touches a prompt.

## Smaller additions (optional — say yes/no per item)

### B-9. "Match my voice" toggle on English Generator
Feeds 2-3 of your own past pieces (already in study history) as style reference so generated
writing sounds like you instead of like an AI. Directly reduces the "this reads AI-generated"
problem the Originality tool exists to flag.

### B-10. Regenerate / Make longer / Make shorter / More formal buttons
One row under the English Generator output. Re-runs with a delta instruction instead of making
you retype the whole request. Cheap to build, high everyday value.

### B-11. Export the generated piece
Copy · Download .txt · Send to Notebook. The Notebook already exists; right now there is no path
from "AI wrote it" to "it's in my notes" except select-and-copy.

### B-12. Model consistency pass
Move English Aid's text path from `gpt-4o-mini` to `gpt-4o` (it already upgrades for images), or
expose the choice. Same reasoning as the v214 quiz-generator upgrade — mini is measurably worse
at exactly the tasks students grade you on.

---

# PART C — DECISIONS + REMAINING QUESTION

**Q1 — Word count box on English Generator? → YES (2026-07-22).** Folded into B-2 as a
first-class control alongside Type and Paragraphs.

**Q2 — What fills the freed grid slot? → AI Flashcards (2026-07-22).** Grid stays at 8. Details
and reasoning in B-4.

**Q3 — Short or detailed prompts after the merge? → BOTH, via a toggle (2026-07-22).** Built as a
Short (1-3 sentences) / Detailed (6-12 sentences) switch inside the tab, defaulting to Short and
remembering the last choice. Original question kept below for context. Prompt Engine outputs 1-3 sentences.
English Gen → Generate a prompt outputs 6-12 sentences. B-5 moves the Engine's *features* over,
but you didn't say which *output length* wins. Options: (a) short only — the Engine's behavior
moves wholesale, (b) detailed only — keep the current English Gen output, take only the
image/counter/quest plumbing, (c) **recommended:** a Short / Detailed toggle inside the tab, so
you keep both behaviors and lose nothing.

---

## Ship checklist

Done locally:

- [x] Bumped **both** `script.js?v=` and `style.css?v=` in `index.html` (`20260716v233` → `20260722v234`)
- [x] Syntax-checked `script.js` with the Playwright `node.exe --check`
- [x] Ran the casual/tutor capture harness (D-4) — English Generator + English Aid send **no**
      mode block in either mode; Math/Science/Social still do. 38/38 rows OK.
- [x] Type=Essay enables the Paragraphs dropdown; Standard/Paragraph/Document disable and reset it
- [x] Word count box overrides a conflicting count typed in the request box
- [x] Debate Practice no longer renders flush against an open tool panel — desktop and 375px mobile
- [x] AI Tools grid has 8 cards, AI Flashcards where Prompt Engine was
- [x] Ctrl+V screenshot works in English Generator → Generate a prompt
- [x] No orphaned references to `prompt-engine-input` / `_promptEngineImage` / `ctool-mode-*`;
      `openPromptEngine` / `processPromptEngine` / `copyPromptEngineOutput` kept as shims
- [x] Removed dead Homework block (~315 lines) and `updateHomeDailyChallenge`; nothing referenced them

Still to do, on the live site — **Chase's call, nothing has been pushed**:

- [ ] `git add -A && git commit && git push` (deploys straight to nexusasc.com)
- [ ] `curl -s https://nexusasc.com/index.html | grep 'v=20260722v234'` after the Pages deploy
- [ ] Real-use spot check with a live key: ask for "a 150 word message" in Casual **and** Tutor mode
      and count the words — the stub proves the plumbing, only a real call proves the model complies
- [ ] Real-use spot check: Region Explorer in Casual mode should now return all five sections at
      full length (it was silently truncated before D-2)
- [ ] Backup file `script.js.bak-v234` is in the working tree — delete it before committing, or it
      ships a 1.9 MB duplicate
