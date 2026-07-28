// NEXUS hosted-AI proxy — Supabase Edge Function `ai`.
//
// This is the SINGLE server-side chokepoint for all hosted AI. Every protection
// lives here because the client cannot be trusted (anyone can POST to this URL
// directly). In order, each request must pass:
//   1. Auth      — a valid Supabase JWT (rejects anonymous callers to the raw URL)
//   2. Size caps — body size, message length, and max_tokens are clamped
//   3. Model     — only gpt-4o / gpt-4o-mini allowed; default mini
//   4. Rate/limit — per-user/min, per-IP/min, and per-user monthly allotment (ai_gate)
//   5. Moderation — OpenAI moderation on the input, FAIL-CLOSED for the minor audience
//   6. Call OpenAI, moderate the output, return { content, used, limit }
//
// Env vars (Supabase → Edge Functions → ai → Secrets):
//   OPENAI_API_KEY            (secret)
//   SUPABASE_URL              (auto-provided)
//   SUPABASE_ANON_KEY         (auto-provided)
//   SUPABASE_SERVICE_ROLE_KEY (auto-provided) — used for usage tables via RLS bypass
//   ANON_MONTHLY_LIMIT        (optional, default 10)    — anonymous/unverified email (trial)
//   FREE_MONTHLY_LIMIT        (optional, default 1500)  — email-verified free accounts
//   PAID_MONTHLY_LIMIT        (optional, default 6000)  — paid accounts
//   PER_MIN_LIMIT             (optional, default 12)
//   IP_PER_MIN_LIMIT          (optional, default 20)
//
// How the limits work together (see docs/BACKEND_SETUP.md for the full reasoning):
//   - PER_MIN / IP_PER_MIN are the real script-stopper — a burst can't exceed them.
//   - The monthly caps bound cost + account-farming, NOT script speed.
//   - Anonymous accounts are cheap to mint, so their cap is LOW (each fake account
//     is worth ~pennies). The generous cap unlocks only with a verified email,
//     which is expensive to mass-create; per-IP limits + Turnstile blunt bulk signup.
//   - The OpenAI hard spend cap (set in the OpenAI billing dashboard) is the
//     absolute backstop no matter what.
// STRICT policy (v19.7): ANON_MONTHLY defaults to 0 — a CONFIRMED email is
// required for any AI. Verified accounts get FREE_MONTHLY; the per-IP cap only
// matters if ANON_MONTHLY is ever raised back above 0 for a taster.

const OPENAI_KEY = Deno.env.get("OPENAI_API_KEY")!;
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// v19.7 — STRICT: no AI at all without a CONFIRMED email. Default 0 means
// anonymous accounts AND signed-up-but-unconfirmed accounts get zero AI; a
// confirmed email unlocks FREE_MONTHLY. Anonymous/unverified accounts are
// near-free to mint, so gating them entirely is the strongest account-farming
// defense. To re-enable a small taster later, raise this (e.g. 2) — via the
// ANON_MONTHLY_LIMIT secret in Supabase, no redeploy needed.
const ANON_MONTHLY = parseInt(Deno.env.get("ANON_MONTHLY_LIMIT") ?? "0", 10);
const FREE_MONTHLY = parseInt(Deno.env.get("FREE_MONTHLY_LIMIT") ?? "1500", 10);
const PAID_MONTHLY = parseInt(Deno.env.get("PAID_MONTHLY_LIMIT") ?? "6000", 10);
const PER_MIN = parseInt(Deno.env.get("PER_MIN_LIMIT") ?? "12", 10);
const IP_PER_MIN = parseInt(Deno.env.get("IP_PER_MIN_LIMIT") ?? "20", 10);
// v19.3 — per-IP MONTHLY cap for the unverified tier (anti account-farming:
// clearing the browser mints a fresh anon account, but they share an IP). Only
// applied to unverified callers; a verified email escapes it entirely. Requires
// migration 0005_ip_month_cap.sql. Override live via IP_ANON_MONTHLY_LIMIT.
const IP_ANON_MONTHLY = parseInt(Deno.env.get("IP_ANON_MONTHLY_LIMIT") ?? "25", 10);

const ALLOWED_MODELS = new Set(["gpt-4o", "gpt-4o-mini"]);
const MAX_BODY_BYTES = 3_000_000;  // ~3 MB — detailed Live Vision graph screenshots can exceed 600 KB; still blocks true abuse
const MAX_OUTPUT_TOKENS = 1500;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Pull plain text out of the OpenAI messages array (content may be a string OR an
// array of {type:'text'|'image_url', ...} parts for vision). Images are ignored
// for moderation text but their presence forces gpt-4o.
function extractText(messages: any[]): { text: string; hasImage: boolean } {
  let text = "";
  let hasImage = false;
  for (const m of messages ?? []) {
    const c = m?.content;
    if (typeof c === "string") text += " " + c;
    else if (Array.isArray(c)) {
      for (const part of c) {
        if (part?.type === "text") text += " " + (part.text ?? "");
        if (part?.type === "image_url") hasImage = true;
      }
    }
  }
  return { text: text.trim(), hasImage };
}

async function moderate(input: string): Promise<{ ok: boolean; flagged: boolean }> {
  // FAIL-CLOSED: if the moderation call errors, treat as NOT ok (block) — for a
  // minor audience we never let unmoderated input through on an error.
  try {
    const r = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_KEY}` },
      body: JSON.stringify({ model: "omni-moderation-latest", input: input.slice(0, 8000) }),
    });
    if (!r.ok) return { ok: false, flagged: false };
    const d = await r.json();
    const flagged = !!d?.results?.[0]?.flagged;
    return { ok: true, flagged };
  } catch {
    return { ok: false, flagged: false };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // ── 1. Auth ────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Sign in to use NEXUS AI." }, 401);

  const userRes = await fetch(`${SB_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: ANON },
  });
  if (!userRes.ok) return json({ error: "Your session expired — sign in again." }, 401);
  const user = await userRes.json();
  const uid = user?.id;
  if (!uid) return json({ error: "Invalid session." }, 401);

  // ── 2. Size caps ───────────────────────────────────────────────────────
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Request too large." }, 413);
  let body: any;
  try { body = JSON.parse(raw); } catch { return json({ error: "Bad request." }, 400); }
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  if (!messages.length) return json({ error: "No messages." }, 400);

  const { text, hasImage } = extractText(messages);
  if (text.length > 24_000) return json({ error: "Message too long." }, 413);

  // ── 3. Model routing ───────────────────────────────────────────────────
  // Vision or explicitly-requested 4o gets 4o; everything else is cheap mini.
  let model = String(body?.model ?? "gpt-4o-mini");
  if (!ALLOWED_MODELS.has(model)) model = "gpt-4o-mini";
  if (hasImage) model = "gpt-4o";

  // ── 4. Entitlement + rate/limit gate ───────────────────────────────────
  // Base allotment on email verification: anonymous / unconfirmed accounts get
  // the small ANON allotment (farming defense); a confirmed email unlocks FREE.
  const emailVerified = !!user?.email_confirmed_at && user?.is_anonymous !== true;
  let monthlyLimit = emailVerified ? FREE_MONTHLY : ANON_MONTHLY;
  try {
    const pr = await fetch(
      `${SB_URL}/rest/v1/profiles?id=eq.${uid}&select=tier`,
      { headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}` } },
    );
    const rows = pr.ok ? await pr.json() : [];
    const tier = rows?.[0]?.tier ?? "free";
    if (tier === "owner") monthlyLimit = -1;            // unlimited
    else if (tier === "paid") monthlyLimit = PAID_MONTHLY;
  } catch { /* fall back to the verification-based limit */ }

  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;

  // Per-IP monthly cap applies to the UNVERIFIED tier only; verified accounts
  // pass -1 (no IP cap). "No verified email is their problem, not ours."
  const ipMonthLimit = emailVerified ? -1 : IP_ANON_MONTHLY;

  const gateHeaders = {
    "Content-Type": "application/json",
    apikey: ANON, // MUST be the anon key so the user's Bearer token sets auth.uid()
    Authorization: `Bearer ${token}`, // run as the caller so auth.uid() is set
  };
  async function callGate(withIpMonth: boolean) {
    const b: Record<string, unknown> = {
      p_ip: ip, p_month_limit: monthlyLimit,
      p_per_min: PER_MIN, p_ip_per_min: IP_PER_MIN,
    };
    if (withIpMonth) b.p_ip_month_limit = ipMonthLimit;
    return fetch(`${SB_URL}/rest/v1/rpc/ai_gate`, { method: "POST", headers: gateHeaders, body: JSON.stringify(b) });
  }
  // Try the 5-arg gate; if migration 0005 isn't applied yet the function
  // signature won't match, so fall back to the 4-arg call (AI keeps working,
  // just without the IP cap until the migration is run).
  let gateRes = await callGate(true);
  if (!gateRes.ok) {
    const legacy = await callGate(false);
    if (legacy.ok) gateRes = legacy;
  }
  const gate = gateRes.ok ? await gateRes.json() : { allowed: false, reason: "gate_error" };
  if (!gate?.allowed) {
    let msg, reason = gate?.reason;
    if (gate?.reason === "month_limit") {
      if (emailVerified) {
        // Real cap for a verified user.
        msg = "You've reached your free AI allotment for this month. Upgrade to keep going.";
      } else if (user?.email && user?.is_anonymous !== true) {
        // Signed up but hasn't clicked the confirmation link — this is the path
        // to usage, so point them at it (not "upgrade").
        msg = ANON_MONTHLY === 0
          ? "NEXUS AI needs a verified email. Check your inbox for the confirmation link — it's free, and unlocks AI right away."
          : "You've used your free trial questions. Verify your email — check your inbox for the confirmation link — to unlock a lot more, free.";
        reason = "verify_email";
      } else {
        // Truly anonymous (never made an account).
        msg = ANON_MONTHLY === 0
          ? "NEXUS AI needs a free account with a verified email. Sign up and confirm your email to unlock it."
          : "You've used your free trial questions. Create a free account (with an email) to unlock a lot more.";
        reason = "make_account";
      }
    } else if (gate?.reason === "ip_month_limit") {
      // This network has used up the shared UNVERIFIED trial budget. The escape
      // hatch is verifying an email (which removes the IP cap entirely).
      if (user?.email && user?.is_anonymous !== true) {
        msg = "This network's free trial questions are used up. Verify your email — check your inbox for the confirmation link — to unlock your own free allotment.";
        reason = "verify_email";
      } else {
        msg = "This network's free trial questions are used up. Create a free account with an email to get your own allotment.";
        reason = "make_account";
      }
    } else if (gate?.reason?.startsWith("rate")) {
      msg = "You're going a little fast — wait a few seconds and try again.";
    } else {
      msg = "AI is temporarily unavailable. Please try again shortly.";
    }
    return json({ error: msg, reason }, 429);
  }

  // ── 5. Input moderation (FAIL-CLOSED) ──────────────────────────────────
  const mod = await moderate(text);
  if (!mod.ok) return json({ error: "Safety check unavailable — please try again." }, 503);
  if (mod.flagged) {
    return json({ error: "That request was blocked by NEXUS's safety filter. Try rephrasing your question." }, 400);
  }

  // ── 6. Call OpenAI (non-streaming; the client synthesizes SSE) ─────────
  // Graceful fallback: on a low-tier / unfunded account gpt-4o has a very small
  // per-minute limit and returns "Request too large". If that happens we retry
  // once on gpt-4o-mini (much higher limit, cheaper) so the student still gets an
  // answer. On a funded account gpt-4o is used normally.
  const maxTok = Math.min(Number(body?.max_tokens) || 1024, MAX_OUTPUT_TOKENS);
  async function callModel(useModel: string) {
    const payload: any = { model: useModel, messages, max_tokens: maxTok };
    if (typeof body?.temperature === "number") payload.temperature = body.temperature;
    if (body?.response_format) payload.response_format = body.response_format;
    const r = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${OPENAI_KEY}` },
      body: JSON.stringify(payload),
    });
    return { r, d: await r.json() };
  }
  let content = "";
  try {
    let { r, d } = await callModel(model);
    if (!r.ok && model !== "gpt-4o-mini" &&
        /too large|tokens per min|rate limit|TPM|quota|429|413/i.test(JSON.stringify(d || {}))) {
      ({ r, d } = await callModel("gpt-4o-mini")); // retry on the higher-limit model
    }
    if (!r.ok) return json({ error: d?.error?.message ?? "AI provider error." }, 502);
    content = d?.choices?.[0]?.message?.content ?? "";
  } catch {
    return json({ error: "AI request failed." }, 502);
  }

  // Output moderation: if flagged, replace with a safe message. If the check
  // itself errors we allow it through (the INPUT was already moderated), so a
  // transient moderation outage doesn't block a legitimately-generated answer.
  if (content && !body?.response_format) {
    const outMod = await moderate(content);
    if (outMod.ok && outMod.flagged) {
      content = "I can't help with that one. Let's keep it to schoolwork — try asking about the concept instead.";
    }
  }

  return json({ content, used: gate?.month ?? null, limit: monthlyLimit });
});
