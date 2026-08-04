/// Exchange a share token for a durable guest grant.
///
/// The token is never itself an access credential — it buys exactly one row in
/// guest_access and is then irrelevant. That is what keeps every policy in the
/// schema `to authenticated`: there is no code path anywhere that reads family
/// data for an anonymous caller holding a URL.
///
/// The caller is already signed up by the time they get here (the web landing
/// page sends them through registration first), which is the point of the whole
/// funnel — they arrive with a household of their own and this one extra list
/// inside it.

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
  if (!token) return fail("Kein Freigabe-Code angegeben.");

  const db = serviceClient();
  const { data, error } = await db.rpc("redeem_share_link", {
    p_token_hash: await hashToken(token),
    p_user_id: uid,
  });

  if (error) {
    console.error("redeem-share-link rejected", error.message);
    return fail(error.message, 400);
  }

  const grant = Array.isArray(data) ? data[0] : data;
  if (!grant) return fail("Dieser Link ist ungültig.", 400);

  return json({ kind: grant.resource_kind, resource_id: grant.resource_id });
});
