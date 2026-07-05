// NEXUS Stripe Checkout — Supabase Edge Function `checkout`.
//
// The signed-in client calls this to start a subscription. It creates a Stripe
// Checkout Session and — critically — stamps the user id + chosen modules onto
// the session/subscription so the `stripe-webhook` function can write the
// verified entitlement back to Supabase. Without these stamps, a completed
// payment can't be linked to an account.
//
// Client contract (already in script.js `_pbConfirm`):
//   POST /functions/v1/checkout   Authorization: Bearer <user JWT>
//   body: { modules: string[], priceId, successUrl, cancelUrl }
//   returns: { url }   ← redirect the browser here
//
// Env vars (Supabase → Edge Functions → checkout → Secrets):
//   STRIPE_SECRET_KEY   (secret)
//   SUPABASE_URL, SUPABASE_ANON_KEY  (auto-provided)
//
// Pricing: the price is a $2/mo recurring "module" price; quantity = # of modules
// (4-module minimum → $8 floor). Which modules were bought travels in metadata.

import Stripe from "https://esm.sh/stripe@16.2.0?target=deno";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
  httpClient: Stripe.createFetchHttpClient(),
});
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const MODULE_MIN = 4;

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // 1. Auth — identify the user paying, so the webhook can credit the right account.
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Please sign in before subscribing." }, 401);
  const userRes = await fetch(`${SB_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: ANON },
  });
  if (!userRes.ok) return json({ error: "Your session expired — sign in again." }, 401);
  const user = await userRes.json();
  const uid = user?.id;
  const email = user?.email ?? undefined;
  if (!uid) return json({ error: "Invalid session." }, 401);

  // 2. Validate the plan.
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Bad request." }, 400); }
  const modules: string[] = Array.isArray(body?.modules)
    ? body.modules.map((m: unknown) => String(m)).filter(Boolean)
    : [];
  const priceId = String(body?.priceId ?? "");
  if (!priceId) return json({ error: "Missing price." }, 400);
  if (modules.length < MODULE_MIN) {
    return json({ error: `Pick at least ${MODULE_MIN} modules.` }, 400);
  }
  const origin = req.headers.get("origin") ?? "";
  const successUrl = String(body?.successUrl || `${origin}/?checkout=success`);
  const cancelUrl = String(body?.cancelUrl || `${origin}/?checkout=cancel`);

  // 3. Create the Checkout Session, stamping user_id + modules everywhere the
  //    webhook might read them (session-level and subscription-level).
  try {
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: priceId, quantity: modules.length }],
      client_reference_id: uid,
      customer_email: email,
      metadata: { user_id: uid, modules: modules.join(",") },
      subscription_data: { metadata: { user_id: uid, modules: modules.join(",") } },
      success_url: successUrl,
      cancel_url: cancelUrl,
      allow_promotion_codes: true,
    });
    return json({ url: session.url });
  } catch (e) {
    return json({ error: (e as Error).message || "Could not start checkout." }, 502);
  }
});
