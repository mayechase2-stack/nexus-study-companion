/* ═══════════════════════════════════════════════════════════════════════
   NEXUS — MODE AUDIT HARNESS  (v234, D-4)
   ═══════════════════════════════════════════════════════════════════════

   WHAT IT IS
   Intercepts window.fetch, drives every AI feature once per mode, records the
   system prompt each one actually sends, and prints a tool x mode matrix.
   Every request is answered with a canned stub — no API credit is spent, no
   signed-in account is needed, and nothing is written to the user's data.

   WHY IT EXISTS
   Automated scanning of this app catches crashes and dead buttons but has
   never caught a semantic bug. This harness found four in one pass:
     · English Generator was told "Do NOT solve it" in Tutor mode
     · all 7 English Aid tools were told the same
     · Casual mode's "1-3 sentences max" was truncating explicit word counts
       (a "100 word message" came back at 78)
     · Region Explorer's five ~90-word sections were being squeezed by the
       same brevity clause

   RUN IT before any release that touches a prompt.

   HOW TO RUN
     1. Open the app (preview or nexusasc.com) and sign in, or just load it —
        no real key is needed, the harness installs a fake one.
     2. Open DevTools -> Console.
     3. Paste this whole file and press Enter.
     4. Wait for the table. Read the EXPECTED column.
     5. It restores fetch and your settings automatically when it finishes.

   EXPECTED RESULT (v234 onward)
     tutor=true  only for: Math Lab, Science Lab, Social Studies (all sub-tools)
     tutor=false everywhere else — in particular EVERY English Generator and
     English Aid row must be false in both modes. A true there is the v233
     regression coming back.
   ═══════════════════════════════════════════════════════════════════════ */

(async function nexusModeAudit() {
    const saved = {
        key: localStorage.getItem('openai_api_key'),
        streaming: localStorage.getItem('ai_streaming'),
        tier: localStorage.getItem('user_tier'),
        mode: localStorage.getItem('difficulty_mode')
    };
    const origFetch = window.fetch.bind(window);
    let captured = [];

    // Fake key + non-streaming so a plain JSON stub is enough.
    localStorage.setItem('openai_api_key', 'sk-MODEAUDIT000000000000000000000000');
    localStorage.setItem('ai_streaming', '0');
    localStorage.setItem('user_tier', 'pro');

    window.fetch = function (url, opts) {
        const u = (typeof url === 'string') ? url : (url && url.url) || '';
        if (u.indexOf('chat/completions') !== -1 || u.indexOf('/functions/v1/ai') !== -1) {
            let body = {};
            try { body = JSON.parse(opts.body); } catch (_) {}
            captured.push({
                model: body.model,
                sys: (body.messages || []).filter(m => m.role === 'system')
                    .map(m => typeof m.content === 'string' ? m.content : JSON.stringify(m.content)).join('\n')
            });
            return Promise.resolve(new Response(
                JSON.stringify({ choices: [{ message: { content: '<p>stub</p>' } }] }),
                { status: 200, headers: { 'Content-Type': 'application/json' } }
            ));
        }
        return origFetch(url, opts);
    };

    const setv = (id, v) => { const e = document.getElementById(id); if (e) { e.value = v; return true; } return false; };
    const wait = ms => new Promise(r => setTimeout(r, ms));

    // [label, setup, invoke, expectedTutorBlock]
    const TESTS = [
        ['English Gen: Write',        () => setv('english-prompt-input', 'write a 100 word message about my school day'), () => processEnglishPrompt(), false],
        ['English Gen: Prompt',       () => setv('eng-gen-prompt-input', 'an essay outline on Of Mice and Men'),          () => generateEnglishGenPrompt(), false],
        ['English Aid: grammar',      () => setv('english-input', 'i has went to the store yesterday'),                   () => englishAction('grammar'), false],
        ['English Aid: summarize',    () => setv('english-input', 'A long passage about photosynthesis.'),                () => englishAction('summarize'), false],
        ['English Aid: analyze',      () => setv('english-input', 'It was the best of times.'),                           () => englishAction('analyze'), false],
        ['English Aid: rewrite',      () => setv('english-input', 'the thing was good and stuff'),                        () => englishAction('rewrite'), false],
        ['English Aid: essay-score',  () => setv('english-input', 'My essay about Gatsby.'),                              () => englishAction('essay-score'), false],
        ['English Aid: outline',      () => setv('english-input', 'Symbolism in Of Mice and Men'),                        () => englishAction('essay-outline'), false],
        ['English Aid: plagiarism',   () => setv('english-input', 'In conclusion, this essay has shown many things.'),    () => englishAction('plagiarism'), false],
        ['Math Lab',                  () => setv('math-text-input', 'solve 2x + 5 = 13'),                                 () => processMathInput(), true],
        ['Science Lab',               () => setv('science-input', 'why is the sky blue'),                                 () => solveScience(), true],
        ['Social: region',            () => {},                                                                          () => searchSocial('region', 'France'), true],
        ['Social: character',         () => setv('social-char-search', 'Napoleon Bonaparte'),                             () => searchSocial('character'), true],
        ['Social: war',               () => setv('social-war-search', 'World War II'),                                    () => searchSocial('war'), true],
        ['Quick Quiz',                () => setv('quiz-content', 'photosynthesis'),                                       () => generateQuiz(), false],
        ['Practice Test',             () => {},                                                                          () => generatePracticeTest(), false],
        ['Debate',                    () => setv('debate-user-input', 'School uniforms limit expression.'),               () => sendDebateMsg(), false],
        ['Concept Map',               () => { openConceptMap(); setv('concept-map-topic', 'the water cycle'); },          () => generateConceptMap(), false],
        ['History Timeline',          () => setv('tl-search-year', '1776'),                                               () => searchHistoryYear(), false]
    ];

    const rows = [];
    for (const mode of ['casual', 'tutor']) {
        localStorage.setItem('difficulty_mode', mode);
        for (const [name, setup, invoke, expectTutor] of TESTS) {
            captured = [];
            let err = null;
            try { setup(); await invoke(); } catch (e) { err = String((e && e.message) || e); }
            await wait(160);
            const c = captured[captured.length - 1] || null;
            const sawTutor = c ? /\[TUTOR MODE/.test(c.sys) : null;
            const sawCasual = c ? /\[CASUAL MODE/.test(c.sys) : null;
            let verdict;
            if (!c) verdict = err ? 'ERROR' : 'no request (UI not open?)';
            else if (mode === 'tutor') verdict = (sawTutor === expectTutor) ? 'OK' : '*** UNEXPECTED ***';
            else verdict = (sawCasual === expectTutor) ? 'OK' : '*** UNEXPECTED ***';
            rows.push({
                tool: name, mode, model: c ? c.model : '-',
                'tutor block': sawTutor, 'casual block': sawCasual,
                'mode block expected': expectTutor, verdict, error: err || ''
            });
        }
    }

    // Restore everything.
    window.fetch = origFetch;
    const put = (k, v) => v === null ? localStorage.removeItem(k) : localStorage.setItem(k, v);
    put('openai_api_key', saved.key);
    put('ai_streaming', saved.streaming);
    put('user_tier', saved.tier);
    put('difficulty_mode', saved.mode);

    console.table(rows);
    const bad = rows.filter(r => r.verdict !== 'OK');
    if (bad.length === 0) {
        console.log('%c MODE AUDIT PASSED — every tool sends the mode block it should. ', 'background:#00b894;color:#fff;font-weight:700;padding:3px 8px;');
    } else {
        console.log('%c MODE AUDIT: ' + bad.length + ' row(s) need a look ', 'background:#ff6b6b;color:#fff;font-weight:700;padding:3px 8px;');
        console.table(bad);
    }
    return rows;
})();
