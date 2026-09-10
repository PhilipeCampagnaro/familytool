/// Connect a school calendar by pasting its link — IServ and WebUntis.
///
///   POST { action: 'check',  provider, url | ics }
///     -> { ok: true, name, events, covers_to }
///   POST { action: 'add',    provider, url | (ics, file_name), name,
///                            connection_id? | account }
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
/// Like calendar-caldav, the credential it stores is sealed: the pasted URL is
/// the whole credential — it needs no login, works from anywhere, and is
/// revoked only by regenerating it in the school platform — so it goes into
/// `calendar_connection_secrets.feed_urls` under CALENDAR_SECRET_KEY and never
/// into `config`, which only holds the feed's opaque id, its host and the name
/// the household gave it.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { assertPublicUrl } from "../_shared/net.ts";
import { membershipOf } from "../_shared/calendar.ts";
import {
  assertCalendarFile,
  type FeedEntry,
  type FeedProbe,
  feedsOf,
  feedUrls,
  hostOf,
  keepFeedFiles,
  keepFeedUrls,
  migrateLegacyFeeds,
  probeFeed,
  probeIcs,
  putFeedFile,
  putFeedUrl,
  redact,
  sealFeedFile,
  sealFeedUrl,
  setFeedFiles,
  setFeedUrls,
} from "../_shared/ics_feed.ts";

/// The providers connected this way. Every one is somebody else's system of
/// record and none offers a write API worth having, so all are read-only
/// without a per-connection question.
///
/// `ical` is the same mechanism with the vendor taken out: any published ICS
/// feed — a Verein's fixtures, a Kita's closing days, a partner's shared work
/// calendar. IServ and WebUntis keep their own names because the hard part is
/// never the pasting, it is finding the link, and those two get instructions.
const LABELS: Record<string, string> = {
  iserv: "IServ",
  webuntis: "WebUntis",
  ical: "Kalender",
};

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
    /// The contents of a picked .ics file, in place of [url].
    ///
    /// A household is sometimes handed a calendar rather than a link — a German
    /// waste vendor outside the six in `_shared/abfall.ts` usually offers a
    /// download and nothing to subscribe to. The file is then the source, and
    /// it goes down the same road as a link from here on: proved to be a
    /// calendar, sealed, parsed fresh on every refresh.
    ics?: string;
    file_name?: string;
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

  // An uploaded file is offered on the vendorless tile only. IServ and WebUntis
  // both mint subscription links, and a school calendar frozen on the day it
  // was exported is worse than no school calendar — so those two keep the one
  // route that stays current.
  const uploaded = typeof body.ics === "string";
  if (uploaded && provider !== "ical") return fail("Für diesen Anbieter geht nur ein Link.");

  let prepared: { payload: Payload; probe: FeedProbe };

  if (uploaded) {
    // Proving it is a calendar *is* the connect on this route, exactly as
    // fetching the link is on the other. Nothing is stored until it has parsed.
    try {
      const ics = assertCalendarFile(body.ics);
      const probe = probeIcs(ics);
      prepared = {
        probe,
        payload: {
          kind: "file",
          ics,
          fileName: fileNameOf(body.file_name),
          coversTo: probe.coversTo,
        },
      };
    } catch (e) {
      return fail((e as Error).message);
    }
  } else {
    // The pasted URL becomes an outbound request target, so it is checked
    // before a socket is ever opened to it — same rule the IServ server field
    // follows.
    let url: URL;
    try {
      url = assertPublicUrl(webcalToHttps(body.url));
    } catch (e) {
      return fail((e as Error).message);
    }

    // Proving the link works *is* the connect. A dead or revoked one fails
    // here, before anything is written, so a stored feed is always one we have
    // read.
    try {
      prepared = {
        probe: await probeFeed(url.href),
        payload: { kind: "url", url: url.href, host: hostOf(url.href) },
      };
    } catch (e) {
      return fail((e as Error).message);
    }
  }

  const { payload, probe } = prepared;

  if (action === "check") {
    return json({
      ok: true,
      name: probe.name,
      events: probe.events,
      covers_to: probe.coversTo,
    });
  }

  return await add(db, membership.familyId, uid, provider, payload, probe.name, body);
});

/// What the caller handed us, once it has been proved to be a calendar.
///
/// The two are the same feed from here on and differ in one place each: which
/// sealed map the body goes into, and what a re-submission of the same thing is
/// recognised by — the URL, or the file's name.
type Payload =
  | { kind: "url"; url: string; host: string }
  | { kind: "file"; ics: string; fileName: string; coversTo: string | null };

/// The picked file's name, kept only so a re-upload replaces rather than
/// duplicates. Stripped of any path a picker might have put in front of it, so
/// that what is stored is a label and never a location on somebody's device.
function fileNameOf(raw: unknown): string {
  const name = typeof raw === "string" ? raw.split(/[/\\]/).pop()?.trim() ?? "" : "";
  return (name || "kalender.ics").slice(0, 80);
}

// ---------------------------------------------------------------------------
// Add
// ---------------------------------------------------------------------------

async function add(
  db: SupabaseClient,
  familyId: string,
  uid: string,
  provider: string,
  payload: Payload,
  probedName: string | null,
  body: { name?: string; account?: string; connection_id?: string },
): Promise<Response> {
  // A file has no host. "datei" stands in wherever the host was doing work
  // beyond display — the account key, above all, which has to be stable and
  // must not collide with a real hostname.
  const host = payload.kind === "url" ? payload.host : "datei";
  const fallback = payload.kind === "file" ? payload.fileName : host;
  const name = (body.name?.trim() || probedName || fallback || LABELS[provider]).slice(0, 80);

  // Adding to an existing account — the "+ Kalender hinzufügen" case, which is
  // the whole reason a connection holds a list. The family filter is the tenant
  // boundary: service_role sees every connection.
  if (body.connection_id) {
    const { data: found } = await db
      .from("calendar_connections")
      .select("id, config, selected_calendars, calendar_names, calendar_owners")
      .eq("id", body.connection_id)
      .eq("family_id", familyId)
      .maybeSingle();

    if (!found) return fail("Die Verbindung wurde nicht gefunden.", 404);

    // A connection made before the URLs were sealed still carries them in
    // `config`. Migrating here rather than adding beside them keeps this
    // function's read-modify-write on one shape.
    let existing;
    try {
      existing = await migrateLegacyFeeds(db, {
        id: found.id,
        config: (found.config ?? {}) as Record<string, unknown>,
        selected_calendars: found.selected_calendars as string[] | null,
        calendar_names: found.calendar_names as Record<string, string> | null,
        calendar_owners: found.calendar_owners as Record<string, string> | null,
      });
    } catch (e) {
      console.error("feed migration failed", (e as Error).message);
      return fail("Der Kalender konnte nicht gespeichert werden.", 500);
    }

    const feeds = feedsOf(existing.config);

    // Submitting the same calendar twice updates it in place rather than adding
    // a duplicate — and *what* counts as the same thing is the one real
    // difference between the two routes.
    //
    // A link is told apart on its URL, which is the calendar's identity. Told
    // apart on the *unsealed* ones, since two envelopes over one URL are two
    // different strings by design.
    //
    // A file is told apart on its name, and that is the point rather than a
    // compromise: handing the app next year's `abfuhr.ics` is how a snapshot is
    // kept current, and it has to land on the calendar the household already
    // named, ticked and put in front of the family — not beside it as a second
    // one with the same title.
    let at: number;
    if (payload.kind === "url") {
      const stored = await feedUrls(db, existing.id);
      at = feeds.findIndex((f) => f.kind !== "file" && stored[f.id] === payload.url);
    } else {
      at = feeds.findIndex((f) => f.kind === "file" && f.file_name === payload.fileName);
    }

    const id = at >= 0 ? feeds[at].id : crypto.randomUUID();
    const entry = entryFor(id, name, host, payload);

    if (at >= 0) feeds[at] = { ...feeds[at], ...entry, added_at: feeds[at].added_at };
    else if (feeds.length >= MAX_FEEDS_PER_CONNECTION) {
      return fail("Für diesen Zugang sind schon genug Kalender hinterlegt.");
    } else feeds.push(entry);

    // The payload is sealed before the connection row names the feed, never
    // after. seal() throws when CALENDAR_SECRET_KEY is missing, and doing it
    // second leaves exactly the row this flow exists to prevent: one the
    // settings screen calls "verbunden" that holds no credential and can never
    // sync.
    try {
      const keep = feeds.map((f) => f.id);
      if (payload.kind === "url") await putFeedUrl(db, existing.id, id, payload.url, keep);
      else await putFeedFile(db, existing.id, id, payload.ics, keep);
    } catch (e) {
      console.error("feed payload seal failed", (e as Error).message);
      return fail("Der Kalender konnte nicht gespeichert werden.", 500);
    }

    // A newly added feed has to end up ticked. `selected_calendars` null means
    // "never asked", which reads everything, so it is left alone in that state
    // rather than being turned into a list that then has to stay correct.
    const selected = Array.isArray(existing.selected_calendars)
      ? [...new Set([...existing.selected_calendars as string[], id])]
      : null;

    const { error } = await db
      .from("calendar_connections")
      .update({
        config: { ...existing.config, feeds },
        selected_calendars: selected,
        calendar_names: { ...(existing.calendar_names ?? {}), [id]: name },
        status: "active",
        status_detail: null,
      })
      .eq("id", existing.id);

    if (error) {
      console.error("link feed append failed", error.message);
      return fail("Der Kalender konnte nicht gespeichert werden.", 500);
    }

    return json({ connection_id: existing.id, external_id: id, name });
  }

  // A new account. `external_account` is what makes two children at one school
  // two connections rather than an upsert collision, so it carries the label
  // the user gave as well as the host.
  const account = (body.account?.trim() || "").slice(0, 60);
  const key = `${host}/${slug(account) || "kalender"}`;
  const label = LABELS[provider];
  const displayName = account
    ? `${label} · ${account}`
    : payload.kind === "file"
    ? `${label} (${payload.fileName})`
    : `${label} (${host})`;

  const id = crypto.randomUUID();
  const entry = entryFor(id, name, host, payload);

  // Sealed before the connection row exists, for the same reason calendar-caldav
  // seals before its upsert: if the key is missing or unusable we must fail with
  // nothing written, not leave an account the settings screen calls "verbunden"
  // that can never sync.
  let envelope: string;
  try {
    envelope = payload.kind === "url"
      ? await sealFeedUrl(payload.url)
      : await sealFeedFile(payload.ics);
  } catch (e) {
    console.error("feed payload seal failed", (e as Error).message);
    return fail("Der Kalender konnte nicht gespeichert werden.", 500);
  }

  const { data: created, error } = await db
    .from("calendar_connections")
    .upsert({
      family_id: familyId,
      provider,
      // "No credential" here means nothing to *log in* with and nothing to
      // write back to — the URL itself is a credential, and it is sealed. The
      // check constraint `auth_type <> 'public' or is_read_only` makes the
      // read-only pairing structural. An uploaded file is read-only for a
      // second reason on top: there is no server behind it to write to.
      auth_type: "public",
      external_account: key,
      display_name: displayName,
      config: { feeds: [entry], host },
      selected_calendars: [id],
      calendar_names: { [id]: name },
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

  // Wholesale, and **both** maps, matching the `config` this upsert just wrote:
  // on the conflict path it replaced the feed list with this one entry, so any
  // payload sealed for the feeds that list used to hold has nothing left
  // pointing at it and must not be kept — including the ones of the other kind,
  // since a connection may hold a mix and this row now holds neither.
  try {
    const urls = payload.kind === "url" ? { [id]: envelope } : {};
    const files = payload.kind === "file" ? { [id]: envelope } : {};
    await setFeedUrls(db, created.id, urls);
    await setFeedFiles(db, created.id, files);
  } catch (e) {
    // The row is already there and would be a connection with no credential, so
    // it goes rather than being left for the user to puzzle over. Nothing else
    // references it yet — it was created one statement ago.
    console.error("feed payload write failed", (e as Error).message);
    await db.from("calendar_connections").delete().eq("id", created.id);
    return fail("Der Kalender konnte nicht gespeichert werden.", 500);
  }

  if (payload.kind === "url") {
    console.log(`linked ${provider} feed ${redact(payload.url)} for family ${familyId}`);
  } else {
    // No file name in the log line, for the same reason a feed URL is redacted:
    // "Krebsvorsorge.ics" is content, and a log is the one place content ends
    // up outside the sealed column.
    console.log(`uploaded ${provider} calendar for family ${familyId}`);
  }
  return json({ connection_id: created.id, external_id: id, name });
}

/// One `config.feeds` entry for either kind of payload.
///
/// `kind` is written explicitly even for a link, where it is the default the
/// reader would have assumed. An entry that says what it is costs one key and
/// removes the only question the read path would otherwise have to guess at.
function entryFor(id: string, name: string, host: string, payload: Payload): FeedEntry {
  const base: FeedEntry = { id, name, host, added_at: new Date().toISOString() };
  if (payload.kind === "url") return { ...base, kind: "url" };
  return {
    ...base,
    kind: "file",
    file_name: payload.fileName,
    covers_to: payload.coversTo ?? undefined,
  };
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

  const { data: found } = await db
    .from("calendar_connections")
    .select("id, config, selected_calendars, calendar_names, calendar_owners")
    .eq("id", body.connection_id)
    .eq("family_id", familyId)
    .maybeSingle();

  if (!found) return fail("Die Verbindung wurde nicht gefunden.", 404);

  // Migrate first even though we are about to delete something: the id the app
  // sent is one this deploy minted, so a connection still on the old shape has
  // no entry matching it and the removal would silently do nothing.
  let existing;
  try {
    existing = await migrateLegacyFeeds(db, {
      id: found.id,
      config: (found.config ?? {}) as Record<string, unknown>,
      selected_calendars: found.selected_calendars as string[] | null,
      calendar_names: found.calendar_names as Record<string, string> | null,
      calendar_owners: found.calendar_owners as Record<string, string> | null,
    });
  } catch (e) {
    console.error("feed migration failed", (e as Error).message);
    return fail("Der Kalender konnte nicht entfernt werden.", 500);
  }

  const feeds = feedsOf(existing.config).filter((f) => f.id !== body.external_id);

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
      config: { ...existing.config, feeds },
      selected_calendars: selected,
      calendar_names: names,
    })
    .eq("id", existing.id);

  if (error) {
    console.error("link feed removal failed", error.message);
    return fail("Der Kalender konnte nicht entfernt werden.", 500);
  }

  // Removing a calendar has to destroy what was behind it, not just stop
  // pointing at it. After the connection row, so a failure here leaves an
  // unreferenced envelope rather than a feed whose payload has gone.
  //
  // Both maps, because the removal does not know which kind it was and does not
  // need to: an id absent from a map prunes nothing there.
  try {
    const keep = feeds.map((f) => f.id);
    await keepFeedUrls(db, existing.id, keep);
    await keepFeedFiles(db, existing.id, keep);
  } catch (e) {
    console.error("feed payload prune failed", (e as Error).message);
  }

  // The `calendars` row for the dropped feed is not deleted here: the next
  // `calendar-events` read finds it missing from the wanted set and sweeps it,
  // which is the same path a deselected Google calendar takes.
  return json({ ok: true, remaining: feeds.length });
}

/// `webcal://` is the same URL with a scheme that means "subscribe to this".
///
/// It is not a protocol — nothing speaks webcal, every client rewrites it to
/// https and fetches that — but it is what half the "Kalender abonnieren"
/// buttons on the web put on the clipboard, and Apple's own share sheet emits
/// it. Refusing it would mean telling a user their correct link is wrong
/// because of five characters they never chose.
///
/// Only the scheme is touched, and only that exact one: `assertPublicUrl` still
/// gets the last word on the host, and anything else is passed through to be
/// rejected there rather than quietly repaired here.
function webcalToHttps(raw: unknown): unknown {
  if (typeof raw !== "string") return raw;
  const trimmed = raw.trim();
  return /^webcal:\/\//i.test(trimmed) ? `https://${trimmed.slice("webcal://".length)}` : trimmed;
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
