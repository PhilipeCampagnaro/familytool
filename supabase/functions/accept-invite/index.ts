/// Join a household by redeeming an invite token.
///
/// The genuinely privileged operation in this system: it writes the caller's
/// family_members row, which no RLS policy is allowed to permit. Letting a
/// client insert there — even guarded by a token check — would mean the token
/// had to be readable, and a readable token is a way into someone else's
/// household.
///
/// All the actual work happens inside public.accept_family_invite, because
/// dissolving the old household and creating the new membership have to be one
/// transaction.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { hashToken } from "../_shared/tokens.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: { token?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const token = body.token?.trim();
  if (!token) return fail("Kein Einladungscode angegeben.");

  const db = serviceClient();
  const { data, error } = await db.rpc("accept_family_invite", {
    p_token_hash: await hashToken(token),
    p_user_id: uid,
  });

  if (error) {
    // The RPC raises German messages for every rejection a user can actually
    // hit (expired, wrong address, still in a shared household), so they are
    // safe to pass straight through.
    console.error("accept-invite rejected", error.message);
    return fail(error.message, 400);
  }

  return json({ family_id: data });
});
