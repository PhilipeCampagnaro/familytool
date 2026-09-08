/// Connect a school calendar by pasting its link — IServ and WebUntis.
///
///   POST { action: 'check',  provider, url }
///     -> { ok: true, name, events }
///   POST { action: 'add',    provider, url, name, connection_id? | account }
///     -> { connection_id, external_id, name }
///   POST { action: 'remove', connection_id, external_id }
///     -> { ok: true, remaining }
///
/// Why this is a function and not a client insert, twice over:
///
///   1. `authenticated` holds no INSERT grant on `calendar_connections` and no
///      UPDATE grant on `config` — the column the feed URLs live in. A feed can
///      therefore only be added by a server that has first fetched the URL and
///      seen an actual VCALENDAR come back, which is the same contract every
///      other connect path in this app keeps: "verbunden" means "we reached it
///      just now".
///
///   2. The URL is the entire credential. A household member may read the feeds
///      on their own connection, but nobody may *introduce* one, because an
///      unchecked URL written straight to `config` is an outbound request this
///      server would then make on a schedule.
///
/// Unlike calendar-caldav this stores no secret at all, so it needs no function
/// secrets — there is nothing to seal.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { assertPublicUrl } from "../_shared/net.ts";
import { membershipOf } from "../_shared/calendar.ts";
import { type FeedEntry, feedsOf, hostOf, probeFeed, redact } from "../_shared/ics_feed.ts";

/// The two providers that are connected this way. Both are somebody else's
/// system of record and neither offers a write API worth having, so both are
/// read-only without a per-connection question.
const LABELS: Record<string, string> = { iserv: "IServ", webuntis: "WebUntis" };

/// One household is not going to legitimately paste fifty school calendars, and
/// each one is a fetch on every calendar refresh.
const MAX_FEEDS_PER_CONNECTION = 20;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: {
    action?: string;
    provider?: string;
    url?: string;
    name?: string;
    account?: string;
    connection_id?: string;
    external_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role === "kid") return fail("Kinder können keine Kalender verbinden.", 403);

  const action = body.action ?? "add";
  if (action === "remove") return await remove(db, membership.familyId, body);
  if (action !== "check" && action !== "add") return fail("Unbekannte Aktion.");

  const provider = body.provider ?? "";
  if (!LABELS[provider]) return fail("Unbekannter Anbieter.");

  // The pasted URL becomes an outbound request target, so it is checked before
  // a socket is ever opened to it — same rule the IServ server field follows.
  let url: URL;
  try {
    url = assertPublicUrl(body.url);
  } catch (e) {
    return fail((e as Error).message);
  }

  // Proving the link works *is* the connect. A dead or revoked one fails here,
  // before anything is written, so a stored feed is always one we have read.
  let probe: { name: string | null; events: number };
  try {
    probe = await probeFeed(url.href);
  } catch (e) {
    return fail((e as Error).message);
  }

  if (action === "check") {
    return json({ ok: true, name: probe.name, events: probe.events });
  }

  return await add(db, membership.familyId, uid, provider, url.href, probe.name, body);
});

// ---------------------------------------------------------------------------
// Add
// ---------------------------------------------------------------------------

async function add(
  db: SupabaseClient,
  familyId: string,
  uid: string,
  provider: string,
  url: string,
  probedName: string | null,
  body: { name?: string; account?: string; connection_id?: string },
): Promise<Response> {
  const host = hostOf(url);
  const name = (body.name?.trim() || probedName || host || LABELS[provider]).slice(0, 80);

  const entry: FeedEntry = { url, name, host, added_at: new Date().toISOString() };

  // Adding to an existing account — the "+ Kalender hinzufügen" case, which is
  // the whole reason a connection holds a list. The family filter is the tenant
  // boundary: service_role sees every connection.
  if (body.connection_id) {
    const { data: existing } = await db
      .from("calendar_connections")
      .select("id, config, selected_calendars, calendar_names")
      .eq("id", body.connection_id)
      .eq("family_id", familyId)
      .maybeSingle();

    if (!existing) return fail("Die Verbindung wurde nicht gefunden.", 404);

    const feeds = feedsOf(existing.config ?? {});
    // Pasting the same link twice renames it rather than adding a duplicate:
    // the URL is the calendar's identity, and two rows for it would be two
    // chips for one school calendar.
    const at = feeds.findIndex((f) => f.url === url);
    if (at >= 0) feeds[at] = { ...feeds[at], name };
    else if (feeds.length >= MAX_FEEDS_PER_CONNECTION) {
      return fail("Für diesen Zugang sind schon genug Kalender hinterlegt.");
    } else feeds.push(entry);

    // A newly added feed has to end up ticked. `selected_calendars` null means
    // "never asked", which reads everything, so it is left alone in that state
    // rather than being turned into a list that then has to stay correct.
    const selected = Array.isArray(existing.selected_calendars)
      ? [...new Set([...existing.selected_calendars as string[], url])]
      : null;

    const { error } = await db
      .from("calendar_connections")
      .update({
        config: { ...(existing.config ?? {}), feeds },
        selected_calendars: selected,
        calendar_names: { ...(existing.calendar_names ?? {}), [url]: name },
        status: "active",
        status_detail: null,
      })
      .eq("id", existing.id);

    if (error) {
      console.error("link feed append failed", error.message);
      return fail("Der Kalender konnte nicht gespeichert werden.", 500);
    }

    return json({ connection_id: existing.id, external_id: url, name });
  }

  // A new account. `external_account` is what makes two children at one school
  // two connections rather than an upsert collision, so it carries the label
  // the user gave as well as the host.
  const account = (body.account?.trim() || "").slice(0, 60);
  const key = `${host}/${slug(account) || "kalender"}`;
  const label = LABELS[provider];
  const displayName = account ? `${label} · ${account}` : `${label} (${host})`;

  const { data: created, error } = await db
    .from("calendar_connections")
    .upsert({
      family_id: familyId,
      provider,
      // No credential, nothing to write back to. The check constraint
      // `auth_type <> 'public' or is_read_only` makes the pairing structural.
      auth_type: "public",
      external_account: key,
      display_name: displayName,
      config: { feeds: [entry], host },
      selected_calendars: [url],
      calendar_names: { [url]: name },
      is_read_only: true,
      status: "active",
      status_detail: null,
      created_by: uid,
    }, { onConflict: "family_id,provider,external_account" })
    .select("id")
    .single();

  if (error || !created) {
    console.error("link connection upsert failed", error?.message);
    return fail("Der Kalender konnte nicht gespeichert werden.", 500);
  }

  console.log(`linked ${provider} feed ${redact(url)} for family ${familyId}`);
  return json({ connection_id: created.id, external_id: url, name });
}

// ---------------------------------------------------------------------------
// Remove
// ---------------------------------------------------------------------------

/// Drops one feed from a connection, and the connection with it when that was
/// the last one. Deleting the row cascades its `calendars` — and therefore the
/// events they carried — through the foreign key that already exists.
async function remove(
  db: SupabaseClient,
  familyId: string,
  body: { connection_id?: string; external_id?: string },
): Promise<Response> {
  if (!body.connection_id || !body.external_id) return fail("Ungültige Anfrage.");

  const { data: existing } = await db
    .from("calendar_connections")
    .select("id, config, selected_calendars, calendar_names")
    .eq("id", body.connection_id)
    .eq("family_id", familyId)
    .maybeSingle();

  if (!existing) return fail("Die Verbindung wurde nicht gefunden.", 404);

  const feeds = feedsOf(existing.config ?? {}).filter((f) => f.url !== body.external_id);

  if (!feeds.length) {
    const { error } = await db.from("calendar_connections").delete().eq("id", existing.id);
    if (error) {
      console.error("link connection delete failed", error.message);
      return fail("Der Kalender konnte nicht entfernt werden.", 500);
    }
    return json({ ok: true, remaining: 0 });
  }

  const names = { ...(existing.calendar_names ?? {}) } as Record<string, string>;
  delete names[body.external_id];

  const selected = Array.isArray(existing.selected_calendars)
    ? (existing.selected_calendars as string[]).filter((id) => id !== body.external_id)
    : null;

  const { error } = await db
    .from("calendar_connections")
    .update({
      config: { ...(existing.config ?? {}), feeds },
      selected_calendars: selected,
      calendar_names: names,
    })
    .eq("id", existing.id);

  if (error) {
    console.error("link feed removal failed", error.message);
    return fail("Der Kalender konnte nicht entfernt werden.", 500);
  }

  // The `calendars` row for the dropped feed is not deleted here: the next
  // `calendar-events` read finds it missing from the wanted set and sweeps it,
  // which is the same path a deselected Google calendar takes.
  return json({ ok: true, remaining: feeds.length });
}

/// A stable, boring key from what the user typed — "Alice" and "alice " must
/// not become two connections for one child.
function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
}
