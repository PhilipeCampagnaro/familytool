/// Says who an invitation is from before anybody accepts it.
///
/// The app asks this first so the question can name the household ("Willkommen
/// bei Familie Campagnaro") instead of a bare "Einem Haushalt beitreten?", and
/// so a dead link is reported before the person has agreed to anything.
///
/// Read-only, and a separate function rather than a flag on accept-invite on
/// purpose: an accept-invite deployed before the flag existed would ignore it
/// and join.
///
/// Answers only the address the invite was sent to — the same check
/// accept_family_invite makes — so a forwarded link does not tell a stranger
/// what the household is called or who is in it. The refusals reuse the RPC's
/// German sentences, which the app already matches on.

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
  const { data: invite, error } = await db
    .from("family_invites")
    .select("family_id, email, invited_by, expires_at")
    .eq("token_hash", await hashToken(token))
    .eq("status", "pending")
    .maybeSingle();

  if (error) {
    console.error("invite-preview lookup failed", error.message);
    return fail("Einladung konnte nicht geladen werden.", 500);
  }
  if (!invite) return fail("Diese Einladung ist ungültig oder wurde bereits verwendet.");
  // Not marked expired here: that is accept_family_invite's write to make, and
  // a preview writes nothing.
  if (new Date(invite.expires_at) <= new Date()) return fail("Diese Einladung ist abgelaufen.");

  const { data: caller } = await db.auth.admin.getUserById(uid);
  if (caller?.user?.email?.toLowerCase() !== invite.email.toLowerCase()) {
    return fail("Diese Einladung wurde an eine andere E-Mail-Adresse gesendet.");
  }

  const [family, inviter] = await Promise.all([
    db.from("families").select("name").eq("id", invite.family_id).maybeSingle(),
    db.from("profiles").select("display_name").eq("id", invite.invited_by).maybeSingle(),
  ]);
  if (!family.data) return fail("Diese Einladung ist ungültig oder wurde bereits verwendet.");

  return json({
    family_name: family.data.name,
    inviter_name: inviter.data?.display_name ?? null,
  });
});
