/// Shared request plumbing for Aporah's Edge Functions.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// German, because it may be surfaced verbatim in the UI.
export function fail(message: string, status = 400): Response {
  return json({ error: message }, status);
}

/// The privileged client. Bypasses RLS, so every function using it is
/// responsible for its own authorisation checks — that is the whole reason
/// these operations are functions rather than policies.
export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/// Resolves the caller from their bearer token. Returns null when the request
/// is unauthenticated or the token is no longer valid.
export async function callerId(req: Request): Promise<string | null> {
  const auth = req.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } },
  );

  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user.id;
}
