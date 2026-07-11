// NEXUS account deletion — Supabase Edge Function `delete-account`.
//
// Called by the client's "Delete My Account & All Data" flow (v19.1). The
// client can only wipe its own browser; this function removes the SERVER copy:
//   1. Auth   — requires the caller's own valid Supabase JWT (you can only
//               delete yourself; no user id is accepted from the request body).
//   2. Data   — deletes the caller's app_state row (the synced study data).
//   3. Account— deletes the auth user itself via the service-role admin API.
//
// Deploy: Supabase → Edge Functions → New function `delete-account` → paste →
// Deploy. No extra secrets needed (uses the auto-provided ones below).
//
// Env vars (auto-provided by Supabase):
//   SUPABASE_URL
//   SUPABASE_ANON_KEY
//   SUPABASE_SERVICE_ROLE_KEY

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  // 1) Identify the caller from THEIR OWN token — never from the body.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json(401, { error: "Missing token" });

  const whoRes = await fetch(`${SB_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${jwt}`, apikey: ANON },
  });
  if (!whoRes.ok) return json(401, { error: "Invalid or expired session" });
  const who = await whoRes.json();
  const userId: string | undefined = who?.id;
  if (!userId) return json(401, { error: "Could not resolve user" });

  // 2) Delete the synced study data (app_state row) with the service role.
  const dataRes = await fetch(
    `${SB_URL}/rest/v1/app_state?user_id=eq.${encodeURIComponent(userId)}`,
    {
      method: "DELETE",
      headers: { Authorization: `Bearer ${SERVICE}`, apikey: SERVICE },
    },
  );
  // 404/empty is fine (nothing synced yet); real errors still proceed to the
  // account delete — leaving a data row with no owning user is the worse state,
  // and RLS keeps an orphaned row unreadable anyway.
  const dataOk = dataRes.ok || dataRes.status === 404;

  // 3) Delete the auth user itself (admin API, service role required).
  const userRes = await fetch(`${SB_URL}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${SERVICE}`, apikey: SERVICE },
  });
  if (!userRes.ok) {
    const detail = await userRes.text().catch(() => "");
    return json(500, { error: "Account delete failed", dataDeleted: dataOk, detail: detail.slice(0, 300) });
  }

  return json(200, { deleted: true, dataDeleted: dataOk });
});
