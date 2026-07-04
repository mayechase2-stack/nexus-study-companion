// NEXUS Stripe webhook — Supabase Edge Function `stripe-webhook`.
//
// Stripe calls this URL when a payment/subscription changes. It verifies the
// signature (so nobody can forge "user X paid"), then writes the VERIFIED
// entitlement into Supabase. This table — not the browser — is the source of
// truth for what a user has paid for; the `ai` function and feature gates read it.
//
// Deploy WITHOUT JWT verification (it's called by Stripe, not a logged-in user):
//   supabase functions deploy stripe-webhook --no-verify-jwt
//
// Env vars (Supabase → Edge Functions → stripe-webhook → Secrets):
//   STRIPE_SECRET_KEY          (secret)
//   STRIPE_WEBHOOK_SECRET      (secret — from the Stripe webhook endpoint page)
//   SUPABASE_URL               (auto)
//   SUPABASE_SERVICE_ROLE_KEY  (auto)
//
// REQUIREMENT on the checkout side: when you create the Checkout Session (in the
// `checkout` function), set BOTH of these so this webhook can link the payment
// to the account and the modules bought:
//   client_reference_id: <supabase user id>
//   subscription_data: { metadata: { user_id: <id>, modules: "math,science,..." } }

import Stripe from "https://esm.sh/stripe@16.2.0?target=deno";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2024-06-20",
  httpClient: Stripe.createFetchHttpClient(),
});
const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Write entitlement to BOTH subscriptions (full record) and profiles (the fast
// path the ai function reads). Uses the service-role key (bypasses RLS).
async function writeEntitlement(row: {
  user_id: string;
  stripe_customer_id?: string | null;
  stripe_sub_id?: string | null;
  tier: string;
  modules: string[];
  status: string;
  current_period_end?: string | null;
}) {
  const headers = {
    "Content-Type": "application/json",
    apikey: SERVICE,
    Authorization: `Bearer ${SERVICE}`,
    Prefer: "resolution=merge-duplicates",
  };
  await fetch(`${SB_URL}/rest/v1/subscriptions`, {
    method: "POST",
    headers,
    body: JSON.stringify({ ...row, updated_at: new Date().toISOString() }),
  });
  await fetch(`${SB_URL}/rest/v1/profiles?id=eq.${row.user_id}`, {
    method: "PATCH",
    headers: { ...headers, Prefer: "return=minimal" },
    body: JSON.stringify({ tier: row.tier, modules: row.modules }),
  });
}

Deno.serve(async (req) => {
  const sig = req.headers.get("stripe-signature");
  if (!sig) return new Response("No signature", { status: 400 });

  const raw = await req.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(raw, sig, WEBHOOK_SECRET);
  } catch (err) {
    return new Response(`Signature verification failed: ${(err as Error).message}`, { status: 400 });
  }

  try {
    switch (event.type) {
      case "checkout.session.completed": {
        const s = event.data.object as Stripe.Checkout.Session;
        const uid = s.client_reference_id ?? (s.metadata?.user_id as string);
        const modules = (s.metadata?.modules ?? "").split(",").map((m) => m.trim()).filter(Boolean);
        if (uid) {
          await writeEntitlement({
            user_id: uid,
            stripe_customer_id: (s.customer as string) ?? null,
            stripe_sub_id: (s.subscription as string) ?? null,
            tier: "paid",
            modules,
            status: "active",
          });
        }
        break;
      }
      case "customer.subscription.updated": {
        const sub = event.data.object as Stripe.Subscription;
        const uid = sub.metadata?.user_id as string;
        const modules = (sub.metadata?.modules ?? "").split(",").map((m) => m.trim()).filter(Boolean);
        if (uid) {
          const active = sub.status === "active" || sub.status === "trialing";
          await writeEntitlement({
            user_id: uid,
            stripe_customer_id: sub.customer as string,
            stripe_sub_id: sub.id,
            tier: active ? "paid" : "free",
            modules: active ? modules : [],
            status: sub.status,
            current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
          });
        }
        break;
      }
      case "customer.subscription.deleted": {
        const sub = event.data.object as Stripe.Subscription;
        const uid = sub.metadata?.user_id as string;
        if (uid) {
          await writeEntitlement({
            user_id: uid,
            stripe_customer_id: sub.customer as string,
            stripe_sub_id: sub.id,
            tier: "free",
            modules: [],
            status: "canceled",
          });
        }
        break;
      }
      case "invoice.payment_failed": {
        const inv = event.data.object as Stripe.Invoice;
        const uid = (inv.subscription_details?.metadata?.user_id as string) ?? null;
        if (uid) {
          await fetch(`${SB_URL}/rest/v1/subscriptions?user_id=eq.${uid}`, {
            method: "PATCH",
            headers: {
              "Content-Type": "application/json",
              apikey: SERVICE,
              Authorization: `Bearer ${SERVICE}`,
              Prefer: "return=minimal",
            },
            body: JSON.stringify({ status: "past_due", updated_at: new Date().toISOString() }),
          });
        }
        break;
      }
    }
  } catch (err) {
    // Log but still 200 so Stripe doesn't hammer retries for a transient DB blip;
    // Stripe keeps the event and you can replay from the dashboard if needed.
    console.error("webhook handler error:", (err as Error).message);
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
