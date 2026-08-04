/// Mint a link that shares one list, box or task with people outside the
/// household — the work-party shopping list case.
///
/// Two separate authorisation questions, answered by two different clients on
/// purpose:
///
///   1. "Can this user see the resource?" — asked through the caller's own JWT,
///      so RLS answers it with the same can_read_* predicate the rest of the
///      app uses. Re-implementing that check here would create a second copy
///      that could quietly drift.
///   2. "Is this user allowed to share outward at all?" — public.
///      may_share_externally, which excludes kids and anyone outside the
///      owning household.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { createToken, hashToken } from "../_shared/tokens.ts";
import { escapeHtml, sendMail } from "../_shared/mail.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const KINDS = { list: "lists", box: "boxes", task: "tasks" } as const;
type Kind = keyof typeof KINDS;

/// Mailing invitations is a spam vector, so it is capped per user per day.
const MAX_LINKS_PER_DAY = 20;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: {
    kind?: string;
    resource_id?: string;
    can_edit?: boolean;
    expires_in_days?: number;
    max_uses?: number;
    email?: string;
  };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const kind = body.kind as Kind;
  const resourceId = body.resource_id;
  if (!kind || !(kind in KINDS)) return fail("Diese Inhalte lassen sich nicht extern teilen.");
  if (!resourceId) return fail("Keine Ressource angegeben.");

  // (1) Visibility, through the caller's own token so RLS decides.
  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: req.headers.get("Authorization")! } },
      auth: { persistSession: false },
    },
  );

  const { data: resource } = await asCaller
    .from(KINDS[kind])
    .select("id, name, family_id")
    .eq("id", resourceId)
    .maybeSingle();

  if (!resource) return fail("Diese Ressource existiert nicht oder ist für dich nicht sichtbar.", 404);

  const db = serviceClient();

  // (2) Role and household.
  const { data: mayShare } = await db.rpc("may_share_externally", {
    p_kind: kind,
    p_resource_id: resourceId,
    p_user_id: uid,
  });

  if (!mayShare) return fail("Du darfst diese Inhalte nicht extern teilen.", 403);

  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await db
    .from("share_links")
    .select("id", { count: "exact", head: true })
    .eq("created_by", uid)
    .gte("created_at", since);

  if ((count ?? 0) >= MAX_LINKS_PER_DAY) {
    return fail("Du hast heute zu viele Freigabe-Links erstellt. Versuch es morgen wieder.", 429);
  }

  const token = createToken();
  const expiresAt = body.expires_in_days
    ? new Date(Date.now() + body.expires_in_days * 86_400_000).toISOString()
    : null;

  const { data: link, error } = await db
    .from("share_links")
    .insert({
      resource_kind: kind,
      resource_id: resourceId,
      family_id: resource.family_id,
      token_hash: await hashToken(token),
      created_by: uid,
      can_edit: body.can_edit ?? true,
      expires_at: expiresAt,
      max_uses: body.max_uses ?? null,
    })
    .select("id, expires_at, can_edit")
    .single();

  if (error) {
    console.error("create-share-link insert failed", error);
    return fail("Der Freigabe-Link konnte nicht erstellt werden.", 500);
  }

  const url = `${Deno.env.get("APORAH_WEB_URL") ?? "https://aporah.app"}/share/${token}`;

  let mailSent = false;
  if (body.email) {
    const { data: profile } = await db
      .from("profiles").select("display_name").eq("id", uid).single();

    const mail = await sendMail(
      body.email.trim().toLowerCase(),
      `${profile?.display_name ?? "Jemand"} teilt „${resource.name}" mit dir`,
      `<p><strong>${escapeHtml(profile?.display_name ?? "Jemand")}</strong> teilt
         „${escapeHtml(resource.name)}" mit dir.</p>
       <p><a href="${url}">Jetzt öffnen</a></p>
       <p>Du siehst ausschließlich diese eine Liste — sonst nichts.</p>`,
    );
    mailSent = mail.sent;
  }

  return json({
    link_id: link.id,
    url,
    token,
    can_edit: link.can_edit,
    expires_at: link.expires_at,
    mail_sent: mailSent,
  });
});
