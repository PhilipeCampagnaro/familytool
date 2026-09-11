/// Enrol this device to write Apple Pay transactions, and hand it back a token.
///
/// The token is the whole reason this function exists. An Apple Pay Personal
/// Automation fires with the phone locked and nobody signed in, so the App
/// Intent that receives it has no session to present — it presents this token
/// instead, from the Keychain, and `spend-ingest` resolves it to a household and
/// a payer. `authenticated` holds no INSERT grant on `spend_ingest_devices` for
/// exactly that reason: a device row may only exist because somebody proved,
/// with a real session, that they are an admin of the household it names.
///
/// Re-enrolling the same phone **rotates** its row rather than adding one. The
/// key is the device's `identifierForVendor`, so a reinstall replaces the old
/// token instead of leaving it working behind a row the user no longer
/// recognises in the revoke list.
///
/// The raw token is returned exactly once and never stored — same contract as
/// `invite-member` and `create-share-link`.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { createToken, hashToken } from "../_shared/tokens.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: { label?: string; device_uid?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const label = (body.label ?? "").trim();
  const deviceUid = (body.device_uid ?? "").trim();
  if (!label || label.length > 120) return fail("Gerätename fehlt.");
  if (!deviceUid || deviceUid.length > 200) return fail("Gerätekennung fehlt.");

  const db = serviceClient();

  // Spend is admin-only, and enrolment is the write that makes every later
  // ingest possible — so the role is checked here, where there is still a
  // session to check it against. `spend-ingest` never re-asks: by then the
  // household has already vouched for this device.
  const { data: membership } = await db
    .from("family_members")
    .select("family_id, role")
    .eq("user_id", uid)
    .maybeSingle();

  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role !== "admin") {
    return fail("Nur Admins können Ausgaben erfassen.", 403);
  }

  const token = createToken();

  // Upsert on (user_id, device_uid). `revoked_at: null` is written explicitly so
  // that re-enrolling a phone the user previously revoked brings it back —
  // which is what pressing "Aktivieren" again plainly means.
  const { data: device, error } = await db
    .from("spend_ingest_devices")
    .upsert(
      {
        family_id: membership.family_id,
        user_id: uid,
        device_uid: deviceUid,
        label,
        token_hash: await hashToken(token),
        revoked_at: null,
      },
      { onConflict: "user_id,device_uid" },
    )
    .select("id, label, created_at")
    .single();

  if (error) {
    console.error("spend-enroll upsert failed", error);
    return fail("Das Gerät konnte nicht aktiviert werden.", 500);
  }

  return json({
    device_id: device.id,
    label: device.label,
    token,
  });
});
