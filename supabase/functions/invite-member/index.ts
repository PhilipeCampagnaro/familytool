/// Invite someone into the caller's household.
///
/// The row itself could almost be a client insert; the reason this is a
/// function is the token. It has to be generated somewhere the client cannot
/// see, stored only as a hash, and mailed out — none of which a policy can do.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { createToken, hashToken } from "../_shared/tokens.ts";
import { escapeHtml, sendMail } from "../_shared/mail.ts";

const ROLES = ["admin", "member", "kid"] as const;
type Role = (typeof ROLES)[number];

/// Every invite sends mail to an address the caller chose, so this is the same
/// spam vector create-share-link caps — and it was the one left uncapped. Without
/// it a single admin can point unlimited mail at any address, which costs us the
/// Resend quota and the sending domain's reputation, and costs the recipient
/// their inbox. A real household invites a handful of people, once.
const MAX_INVITES_PER_DAY = 20;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: { email?: string; name?: string; role?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const email = body.email?.trim().toLowerCase();
  const role = (body.role ?? "member") as Role;

  if (!email || !email.includes("@")) return fail("Bitte gib eine gültige E-Mail-Adresse an.");
  if (!ROLES.includes(role)) return fail("Unbekannte Rolle.");

  const db = serviceClient();

  // Only an admin may invite, and only into their own household.
  const { data: membership } = await db
    .from("family_members")
    .select("family_id, role")
    .eq("user_id", uid)
    .maybeSingle();

  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role !== "admin") {
    return fail("Nur Admins können Mitglieder einladen.", 403);
  }

  // Counted before the row is written, and counted per inviter rather than per
  // household so one admin cannot spend another's allowance.
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await db
    .from("family_invites")
    .select("id", { count: "exact", head: true })
    .eq("invited_by", uid)
    .gte("created_at", since);

  if ((count ?? 0) >= MAX_INVITES_PER_DAY) {
    return fail(
      "Du hast heute zu viele Einladungen verschickt. Versuch es morgen wieder.",
      429,
    );
  }

  // Re-inviting an address that already has a live invite replaces it, so the
  // newest mail is always the one that works.
  await db
    .from("family_invites")
    .update({ status: "revoked" })
    .eq("family_id", membership.family_id)
    .eq("status", "pending")
    .ilike("email", email);

  const token = createToken();
  const { data: invite, error } = await db
    .from("family_invites")
    .insert({
      family_id: membership.family_id,
      email,
      name: body.name?.trim() || null,
      role,
      token_hash: await hashToken(token),
      invited_by: uid,
    })
    .select("id, expires_at")
    .single();

  if (error) {
    console.error("invite-member insert failed", error);
    return fail("Die Einladung konnte nicht erstellt werden.", 500);
  }

  const { data: family } = await db
    .from("families")
    .select("name")
    .eq("id", membership.family_id)
    .single();

  const link = `${Deno.env.get("APORAH_WEB_URL") ?? "https://aporah.app"}/invite/${token}`;
  const mail = await sendMail(
    email,
    `Einladung zu ${family?.name ?? "Aporah"}`,
    `<p>Du wurdest zu <strong>${escapeHtml(family?.name ?? "Aporah")}</strong> eingeladen.</p>
     <p><a href="${link}">Einladung annehmen</a></p>
     <p>Der Link ist 14 Tage gültig.</p>`,
  );

  // The raw token is returned exactly once. The app needs it for the "Link
  // kopieren" fallback whenever mail is not configured or delivery failed.
  return json({
    invite_id: invite.id,
    expires_at: invite.expires_at,
    token,
    link,
    mail_sent: mail.sent,
  });
});
