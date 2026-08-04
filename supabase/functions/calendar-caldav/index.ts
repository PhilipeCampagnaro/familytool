/// Connect an iCloud or IServ account over CalDAV.
///
///   POST { provider, server?, username, password }
///     -> { connection_id, calendars: [{ external_id, name, read_only }] }
///
/// There is no redirect dance here — the user types an app-specific password
/// (iCloud) or their school password (IServ) and it goes straight to the server.
/// That is precisely why this is a function and not a client insert: the
/// password must never be written by a client that could also read it back, and
/// it must be proven to work before we store it.
///
/// Validation is the connect: we run the full PROPFIND discovery chain and list
/// the account's calendars. A wrong password fails at the first PROPFIND with a
/// 401 and nothing is written, so "verbunden" in the UI always means "we reached
/// this server with these credentials just now".
///
/// Function secrets: CALENDAR_SECRET_KEY.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { seal } from "../_shared/secrets.ts";
import { assertPublicUrl, membershipOf, type Provider } from "../_shared/calendar.ts";
import { baseUrl, collections, discover } from "../_shared/caldav.ts";

const LABELS: Record<string, string> = { icloud: "iCloud", iserv: "IServ" };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: { provider?: string; server?: string; username?: string; password?: string };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const provider = body.provider as Provider;
  const username = body.username?.trim();
  const password = body.password ?? "";

  if (provider !== "icloud" && provider !== "iserv") return fail("Unbekannter Anbieter.");
  if (!username || !password) return fail("Bitte Benutzername und Passwort angeben.");
  if (provider === "iserv" && !body.server?.trim()) {
    return fail("Bitte die Adresse der Schule angeben.");
  }

  // The IServ server address becomes an outbound request target, so it is
  // checked before we ever open a socket to it. iCloud uses a fixed base and
  // needs no check.
  let server = "";
  if (provider === "iserv") {
    try {
      server = assertPublicUrl(withScheme(body.server!)).origin;
    } catch (e) {
      return fail((e as Error).message);
    }
  }

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role === "kid") return fail("Kinder können keine Kalender verbinden.", 403);

  // IServ runs DAViCal, where the calendars that matter — the school-wide feed,
  // class and group calendars — sit under sibling principals rather than in the
  // pupil's own home set. `deep` is what finds them.
  const deep = provider === "iserv";

  let home: string;
  let found: Awaited<ReturnType<typeof collections>>;
  try {
    home = await discover(provider, server, username, password);
    found = await collections(home, username, password, deep);
  } catch (e) {
    // These messages are already German and already user-facing ("Benutzername
    // oder Passwort ist falsch."), which is the whole reason discover() throws
    // Error rather than returning a code.
    return fail((e as Error).message, 400);
  }

  if (!found.length) return fail("Für dieses Konto wurde kein Kalender gefunden.");

  const label = LABELS[provider] ?? provider;

  const { data: connection, error } = await db
    .from("calendar_connections")
    .upsert({
      family_id: membership.familyId,
      provider,
      auth_type: "caldav",
      external_account: username,
      display_name: `${label} (${username})`,
      // The discovered home set, so later syncs skip the PROPFIND chain. Not a
      // secret — it is a URL that answers nothing without the password.
      config: provider === "iserv"
        ? { home_url: home, server_url: baseUrl(provider, server) }
        : { home_url: home },
      // A school calendar is somebody else's system of record. Writing to it is
      // not a feature we are missing; it is one we refuse.
      is_read_only: provider === "iserv",
      status: "active",
      status_detail: null,
      created_by: uid,
    }, { onConflict: "family_id,provider,external_account" })
    .select("id")
    .single();

  if (error || !connection) {
    console.error("caldav connection upsert failed", error?.message);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  const { error: secretError } = await db
    .from("calendar_connection_secrets")
    .upsert({
      connection_id: connection.id,
      caldav_password: await seal(password),
      updated_at: new Date().toISOString(),
    }, { onConflict: "connection_id" });

  if (secretError) {
    console.error("caldav secret upsert failed", secretError.message);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  // The calendar list goes back so the app can show the sub-calendar checklist
  // immediately, without a second round trip.
  return json({
    connection_id: connection.id,
    calendars: found.map((c) => ({
      external_id: c.url,
      name: c.name || c.url,
      read_only: c.readOnly || deep,
    })),
  });
});

/// Users type "schule.de", not "https://schule.de". Only https is ever added —
/// assertPublicUrl rejects everything else, so this cannot downgrade anyone.
function withScheme(raw: string): string {
  const trimmed = raw.trim();
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
}
