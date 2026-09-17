/// School calendars connected by a pasted link — IServ plugin feeds and
/// WebUntis iCal subscriptions.
///
/// Why a pasted URL rather than a login: IServ's plugin calendars (Aufgaben,
/// Klausuren, Geburtstage) are module-generated views, not CalDAV collections,
/// so the PROPFIND enumeration in caldav.ts cannot see them at any depth. It
/// finds the pupil's own empty home and `+public` — several hundred events
/// about every class in the school — and nothing a family actually wants. The
/// link share the user creates in IServ (Kalender → Einstellungen → Plugins)
/// returns exactly the right events and needs no credential at all. WebUntis's
/// "Kalender publizieren" mints the same shape of URL for a Stundenplan.
///
/// Neither has an API to enumerate or mint those links, which is why the user
/// pastes one per calendar and why a connection holds a *list* of them.
///
/// The token in the URL is the whole credential, so a feed URL is never logged
/// and never echoed back in an error message — see [redact].
///
/// **Which is why the URL is not in `config`.** It reads as a setting and it
/// behaves like a password: it needs no login, works from any machine on earth,
/// and is revoked only by the pupil regenerating it in the school platform. So
/// it is sealed under CALENDAR_SECRET_KEY and kept in
/// `calendar_connection_secrets.feed_urls` beside the OAuth refresh tokens and
/// the WebUntis app key, and what stays in `config.feeds` is an opaque id and
/// the household's own name for the calendar. A database dump, a leaked
/// service_role key or a mis-scoped backup yields a uuid and "Klausuren".

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { parseIcs } from "./caldav.ts";
import { fetchUntrusted } from "./net.ts";
import type { SyncedEvent } from "./calendar.ts";
import { open, seal } from "./secrets.ts";

/// One pasted calendar, as it is stored in `calendar_connections.config.feeds`.
///
/// [id] is the identity: it becomes the `RemoteCalendar.externalId`, so it is
/// what `selected_calendars` ticks and what `calendar_names` names, and the
/// `calendars` row keyed on (connection_id, external_id) follows it. It is a
/// uuid rather than a hash of the URL — a hash would be stable across a
/// re-paste, which sounds convenient until you notice it also answers "is this
/// household subscribed to *that* feed?" for anyone holding the column and a
/// guess at the URL.
export interface FeedEntry {
  id: string;
  name: string;
  host: string;
  added_at?: string;

  /// `'file'` for a calendar the household uploaded rather than linked. Absent
  /// means `'url'`, which is every entry written before uploads existed — so
  /// the default is the one that was always true, and no backfill is needed.
  ///
  /// This is what decides which sealed map the id is looked up in, so it is
  /// read from `config` (which only a function can see) rather than inferred
  /// from the presence of a value in one map or the other: inferring would make
  /// a key-rotation failure on a URL feed look like a file feed with no bytes.
  kind?: FeedKind;

  /// The name of the picked file, for a `'file'` feed. Shown nowhere by itself
  /// — it is what a re-upload is matched on, so that handing the app next
  /// year's `abfuhr.ics` replaces last year's instead of adding a second
  /// calendar beside it.
  file_name?: string;

  /// The last event in an uploaded file, as an ISO date.
  ///
  /// A link keeps itself current and a file cannot: the day the household's
  /// downloaded waste calendar runs out, the row in Kalender simply stops, and
  /// nothing about an empty calendar says "your file ended in December". This
  /// is the one fact that makes that legible, so it rides along to the settings
  /// screen on `RemoteCalendar` and is refreshed on every re-upload.
  covers_to?: string;
}

export type FeedKind = "url" | "file";

/// A feed as it was stored before the URLs were sealed: the plaintext URL in
/// `config.feeds`, doubling as the external id. Read by [migrateLegacyFeeds]
/// and by nothing else — in particular not by [feedsOf], so no code path can
/// hand a legacy entry onward and put a token back into `calendars.external_id`.
interface LegacyFeedEntry {
  url: string;
  name?: string;
  host?: string;
  added_at?: string;
}

/// A school timetable is the biggest thing we read — WebUntis writes 6-8
/// lessons per school day, so a year is well over a thousand VEVENTs. 4 MB is
/// far above that and still small enough that a wrong URL pointing at something
/// enormous cannot exhaust the function.
const MAX_FEED_BYTES = 4 * 1024 * 1024;

const USER_AGENT = "Aporah/1.0 (+calendar feed)";

/// The feeds on a connection, in the order they were added. Tolerant of a
/// malformed entry rather than throwing: one bad row must not take the
/// household's other school calendars off the screen.
///
/// A legacy entry — one carrying `url` and no `id` — is **skipped**, not
/// adapted. Passing it through would make the token the external id again, and
/// from there it would be written to `calendars.external_id` and to
/// `selected_calendars` by paths that have no idea what they are holding.
/// [migrateLegacyFeeds] runs ahead of every caller and turns those into real
/// entries first.
export function feedsOf(config: Record<string, unknown>): FeedEntry[] {
  const raw = config?.feeds;
  if (!Array.isArray(raw)) return [];

  const out: FeedEntry[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const id = (entry as FeedEntry).id;
    if (typeof id !== "string" || !id) continue;
    const name = (entry as FeedEntry).name;
    const host = (entry as FeedEntry).host;
    const kind = (entry as FeedEntry).kind;
    const fileName = (entry as FeedEntry).file_name;
    const coversTo = (entry as FeedEntry).covers_to;
    out.push({
      id,
      name: typeof name === "string" && name.trim() ? name.trim() : (host ?? ""),
      host: typeof host === "string" ? host : "",
      added_at: (entry as FeedEntry).added_at,
      // Anything but the one known value reads as a URL feed. A `kind` we do
      // not recognise must not send the read path looking for bytes that were
      // never sealed.
      kind: kind === "file" ? "file" : "url",
      file_name: typeof fileName === "string" ? fileName : undefined,
      covers_to: typeof coversTo === "string" ? coversTo : undefined,
    });
  }
  return out;
}

/// The pre-sealing entries on a connection, if it still has any.
function legacyFeedsOf(config: Record<string, unknown>): LegacyFeedEntry[] {
  const raw = config?.feeds;
  if (!Array.isArray(raw)) return [];

  const out: LegacyFeedEntry[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    if (typeof (entry as FeedEntry).id === "string" && (entry as FeedEntry).id) continue;
    const url = (entry as LegacyFeedEntry).url;
    if (typeof url !== "string" || !url.startsWith("https://")) continue;
    out.push(entry as LegacyFeedEntry);
  }
  return out;
}

export function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/// A feed URL with its token removed, safe to put in a log line or an error.
///
/// Keeps the last six characters of the token so two feeds from one school stay
/// distinguishable in a log without either being usable. The *token*, not the
/// end of the path: every IServ plugin URL ends `/calendar.ics`, so trimming
/// the tail of the whole path labels every feed in a school identically. The
/// longest path segment is the token in both providers' URLs — a 128-character
/// hash for IServ, and the `token` query value for WebUntis, which is why the
/// search covers the query string too.
export function redact(url: string): string {
  try {
    const parsed = new URL(url);
    const parts = [
      ...parsed.pathname.split("/"),
      ...[...parsed.searchParams.values()],
    ];
    let longest = "";
    for (const part of parts) if (part.length > longest.length) longest = part;
    const tail = longest.length >= 12 ? longest.slice(-6) : "";
    return tail ? `${parsed.hostname}/…${tail}` : parsed.hostname;
  } catch {
    return "<ungültige Adresse>";
  }
}

/// A link that answered, and answered "no".
///
/// Separated from every other failure because the two ask for different things:
/// a school server that times out is worth retrying on the next refresh, while a
/// revoked token will answer the same way for ever and the only fix is the user
/// pasting a new link. [readLinkedFeed] turns this one into a ReconnectRequired,
/// which is the banner that asks for exactly that; the message is unchanged, so
/// the connect path — where the user is looking at the field they just pasted
/// into — reads the same as before.
export class FeedLinkInvalid extends Error {}

/// Fetches one feed and returns its body.
///
/// Throws a German, user-facing message: this runs on the connect path, where
/// the user is looking at the field they just pasted into and the only useful
/// answer is what to do about it.
export async function fetchFeed(url: string): Promise<string> {
  let res: Response;
  try {
    res = await fetchUntrusted(url, {
      headers: { "User-Agent": USER_AGENT, Accept: "text/calendar, */*" },
    });
  } catch {
    throw new Error("Der Kalender war nicht erreichbar. Bitte prüfe den Link.");
  }

  // 401/403 is the one failure with a specific cause worth naming: the link was
  // revoked in IServ or WebUntis, or it was copied from the browser address bar
  // rather than from the share dialog.
  if (res.status === 401 || res.status === 403) {
    throw new FeedLinkInvalid("Dieser Link ist nicht mehr gültig. Bitte erstelle ihn neu.");
  }
  if (res.status === 404) throw new FeedLinkInvalid("Unter diesem Link liegt kein Kalender.");
  if (!res.ok) throw new Error("Der Kalender war nicht erreichbar. Bitte prüfe den Link.");

  const length = Number(res.headers.get("content-length") ?? "0");
  if (length > MAX_FEED_BYTES) {
    await res.body?.cancel();
    throw new Error("Dieser Kalender ist zu groß.");
  }

  const body = await res.text();
  if (body.length > MAX_FEED_BYTES) throw new Error("Dieser Kalender ist zu groß.");

  // A revoked IServ link answers 200 with the login page, and a URL copied from
  // the browser gives HTML too — both would otherwise parse to zero events and
  // read as "this calendar is empty", which is the exact confusion this whole
  // feature exists to end.
  if (!body.includes("BEGIN:VCALENDAR")) {
    throw new FeedLinkInvalid(
      "Dieser Link liefert keinen Kalender. Bitte kopiere die ICS-Adresse aus der Freigabe.",
    );
  }

  return body;
}

/// What the feed calls itself, if it says. IServ's plugin feeds carry no
/// `X-WR-CALNAME`, so this is usually null and the user names the calendar
/// themselves — but WebUntis does set it, and a prefilled field is worth the
/// four lines.
export function feedName(ics: string): string | null {
  const match = /^X-WR-CALNAME(?:;[^:\r\n]*)?:(.*)$/mi.exec(ics);
  // iCalendar escapes commas and semicolons inside a text value, so the stored
  // characters are a backslash *and* the punctuation — `/\;/` would match a
  // bare semicolon and leave every escaped one with its backslash attached.
  const name = match?.[1]?.trim().replace(/\\,/g, ",").replace(/\\;/g, ";");
  return name ? name.slice(0, 80) : null;
}

/// Fetches and parses one feed for the sync window.
export async function readFeedEvents(
  url: string,
  window: { from: Date; to: Date },
): Promise<SyncedEvent[]> {
  return eventsIn(await fetchFeed(url), window);
}

/// The same for an uploaded file, whose bytes we already hold.
///
/// It goes through the identical parse on every refresh rather than being read
/// once into rows — the file is the source, exactly as the URL is for a link
/// feed, and nothing in it is ever materialised. See the migration
/// 20260910120000 for why that distinction is the whole argument.
export function readFeedFileEvents(
  ics: string,
  window: { from: Date; to: Date },
): SyncedEvent[] {
  return eventsIn(ics, window);
}

function eventsIn(ics: string, window: { from: Date; to: Date }): SyncedEvent[] {
  return parseIcs(ics, window.from, window.to).map((p) => ({
    uid: p.uid,
    title: p.title,
    notes: p.notes,
    location: p.location,
    startsAt: p.startsAt,
    endsAt: p.endsAt,
    allDay: p.allDay,
    // No `seriesUid` either, deliberately. It exists to make "ganze Serie"
    // addressable, and nothing in a feed is writable — a Ferien block that
    // announced it repeats would only offer a choice the write path refuses.
    // A link feed is read-only and has no addressable resource behind an
    // event, so there is nothing for calendar-write to target. `is_read_only`
    // on the connection is what actually refuses the write; these are null
    // because there is genuinely no href to record.
    href: null,
    etag: null,
  }));
}

/// The connect-time check: the link answers, is a calendar, and says what it is
/// called. Deliberately *not* "and has events in the next 90 days" — a
/// Klausurplan is legitimately empty over the summer holidays, and refusing it
/// then would send the user back to IServ to fix a link that is already right.
export async function probeFeed(url: string): Promise<FeedProbe> {
  return probeIcs(await fetchFeed(url));
}

export interface FeedProbe {
  name: string | null;
  events: number;

  /// The last event anywhere in the file, ISO date, or null when it says
  /// nothing datable. Only an uploaded file records it — see [FeedEntry.covers_to].
  coversTo: string | null;
}

/// The same check for text we were handed rather than fetched.
///
/// The window is deliberately the same ±400 days used for a link, so "37
/// Termine gefunden" means the same thing on both routes — but [coversTo] looks
/// at the *whole* file, because the question it answers is when this snapshot
/// stops being any use, and a waste calendar downloaded in September runs to
/// the end of next year.
export function probeIcs(ics: string): FeedProbe {
  const now = new Date();
  const from = new Date(now.getTime() - 400 * 86_400_000);
  const to = new Date(now.getTime() + 400 * 86_400_000);
  return {
    name: feedName(ics),
    events: parseIcs(ics, from, to).length,
    coversTo: lastEventDate(ics),
  };
}

/// How far an uploaded file reaches.
///
/// Parsed over a decade either side rather than read off DTSTART lines with a
/// regex, so that a recurring rule is expanded by the same code the read path
/// uses and a weekly Verein fixture list is not reported as ending on its first
/// entry. Ten years forward is past any horizon a household will meet before
/// the file is replaced, and cheap: this runs once, on upload.
function lastEventDate(ics: string): string | null {
  const now = Date.now();
  const decade = 3650 * 86_400_000;
  const parsed = parseIcs(ics, new Date(now - decade), new Date(now + decade));

  // Compared as strings, because that is what `startsAt` is: an ISO-8601
  // instant in UTC, which sorts lexicographically in the same order it sorts
  // chronologically. Parsing each one back into a Date to compare it would buy
  // nothing and cost a `new Date` per event in a decade-wide window.
  let latest: string | null = null;
  for (const event of parsed) {
    if (!latest || event.startsAt > latest) latest = event.startsAt;
  }
  return latest ? latest.slice(0, 10) : null;
}

/// Reads the text of an uploaded file, rejecting anything that is not a
/// calendar before a single byte of it is stored.
///
/// The same three questions [fetchFeed] asks of a response, minus the ones
/// about the network: is it small enough, and is it actually a VCALENDAR. A
/// household that picked the wrong thing out of the Files app — the PDF that
/// came in the same email, a photo — is told so here, on the step that asked
/// for it, rather than by an empty calendar a week later.
export function assertCalendarFile(text: unknown): string {
  if (typeof text !== "string" || !text.trim()) {
    throw new Error("Die Datei war leer.");
  }
  if (text.length > MAX_FEED_BYTES) {
    throw new Error("Diese Datei ist zu groß.");
  }
  if (!text.includes("BEGIN:VCALENDAR")) {
    throw new Error("Das ist keine Kalenderdatei. Bitte wähle eine .ics-Datei.");
  }
  return text;
}

// ---------------------------------------------------------------------------
// The sealed URLs
// ---------------------------------------------------------------------------
//
// `calendar_connection_secrets.feed_urls` is `{ "<feed id>": "<envelope>" }` —
// one AES-256-GCM envelope per feed rather than one over the whole map, so a
// re-pasted link is resealed on its own and every value gets its own IV.

/// The connection shape these helpers need, which is the subset every caller
/// already has. Structural rather than the `Connection` interface from
/// providers.ts: that module imports this one, and a type-only cycle between
/// them is the kind of thing that resolves fine until somebody adds a value
/// import and it doesn't.
export interface FeedConnection {
  id: string;
  config: Record<string, unknown>;
  selected_calendars: string[] | null;
  calendar_names?: Record<string, string> | null;
  calendar_owners?: Record<string, string> | null;
}

/// Opened URLs, per connection, for the life of one request.
///
/// Keyed on the Supabase client because `serviceClient()` mints a fresh one per
/// invocation — so this cache cannot outlive the request that filled it, which
/// is exactly the lifetime a decrypted bearer token should have. A refresh
/// reading a connection's twenty feeds opens the row once instead of twenty
/// times; a later request for the same household starts from ciphertext again.
const openedUrls = new WeakMap<SupabaseClient, Map<string, Record<string, string>>>();

/// The two sealed maps a feed's payload can live in. Same shape, same key, same
/// cipher; which one an id is in is decided by [FeedEntry.kind] and never by
/// looking.
type FeedColumn = "feed_urls" | "feed_files";

async function envelopes(
  db: SupabaseClient,
  connectionId: string,
  column: FeedColumn = "feed_urls",
): Promise<Record<string, string>> {
  // The two selects are spelled out rather than built from [column]: PostgREST
  // takes the column list as a literal and supabase-js types the result from
  // it, so a variable there costs the row's type and buys nothing. It also
  // keeps the file bodies out of the URL read, which is the point of having two
  // columns at all.
  const { data } = column === "feed_files"
    ? await db
      .from("calendar_connection_secrets")
      .select("feed_files")
      .eq("connection_id", connectionId)
      .maybeSingle()
    : await db
      .from("calendar_connection_secrets")
      .select("feed_urls")
      .eq("connection_id", connectionId)
      .maybeSingle();

  const raw = (data as Record<string, unknown> | null)?.[column];
  return raw && typeof raw === "object" && !Array.isArray(raw)
    ? raw as Record<string, string>
    : {};
}

/// Every feed URL on a connection, opened. Ids whose envelope will not open —
/// sealed under a key that has since been dropped from CALENDAR_SECRET_KEY_RETIRED
/// — are simply absent, which the caller reports as that one calendar failing
/// rather than the account being broken.
export async function feedUrls(
  db: SupabaseClient,
  connectionId: string,
): Promise<Record<string, string>> {
  let perConnection = openedUrls.get(db);
  if (!perConnection) openedUrls.set(db, perConnection = new Map());

  const hit = perConnection.get(connectionId);
  if (hit) return hit;

  const out: Record<string, string> = {};
  for (const [id, envelope] of Object.entries(await envelopes(db, connectionId))) {
    const url = await open(envelope);
    if (url) out[id] = url;
  }

  perConnection.set(connectionId, out);
  return out;
}

/// One feed's URL, or null when there is nothing openable under that id.
export async function feedUrlOf(
  db: SupabaseClient,
  connectionId: string,
  feedId: string,
): Promise<string | null> {
  return (await feedUrls(db, connectionId))[feedId] ?? null;
}

function forget(db: SupabaseClient, connectionId: string): void {
  openedUrls.get(db)?.delete(connectionId);
}

/// Seals one URL under the active key and files it against [feedId], dropping
/// any id in [keep] that is not listed there any more.
///
/// Read-modify-write on the jsonb, like the `config` update it sits beside. Two
/// members adding a link to one account in the same second is the race, and it
/// costs the second link — the same outcome the existing `config` write already
/// has, and not worth an RPC to close.
export async function putFeedUrl(
  db: SupabaseClient,
  connectionId: string,
  feedId: string,
  url: string,
  keep?: string[],
): Promise<void> {
  const current = await envelopes(db, connectionId);
  const next: Record<string, string> = {};
  for (const [id, envelope] of Object.entries(current)) {
    if (!keep || keep.includes(id)) next[id] = envelope;
  }
  next[feedId] = await sealFeedUrl(url);
  await setFeedUrls(db, connectionId, next);
}

/// Seals a URL without writing it anywhere.
///
/// Exists for the one caller that has no connection id yet: creating a link
/// account is an upsert that mints the row, and a row cannot be written before
/// we know the credential can be sealed at all. [seal] throws when
/// CALENDAR_SECRET_KEY is missing, so doing this first is what stops the
/// settings screen ever showing a "verbunden" account with nothing behind it.
export async function sealFeedUrl(url: string): Promise<string> {
  return await seal(url);
}

/// Replaces a connection's whole map of sealed URLs. The values are envelopes,
/// not plaintext — [sealFeedUrl] made them.
export async function setFeedUrls(
  db: SupabaseClient,
  connectionId: string,
  map: Record<string, string>,
): Promise<void> {
  await writeEnvelopes(db, connectionId, "feed_urls", map);
}

async function writeEnvelopes(
  db: SupabaseClient,
  connectionId: string,
  column: FeedColumn,
  map: Record<string, string>,
): Promise<void> {
  // The column is named rather than branched on: a ternary over two object
  // literals gives PostgREST's `upsert` a union it will not accept, because
  // each arm is missing the other's key. `FeedColumn` is what keeps this
  // honest — only the two names exist.
  const row: Record<string, unknown> = {
    connection_id: connectionId,
    updated_at: new Date().toISOString(),
    [column]: map,
  };

  const { error } = await db.from("calendar_connection_secrets").upsert(row);
  if (error) throw new Error(`${column} write failed: ${error.message}`);

  if (column === "feed_urls") forget(db, connectionId);
}

// ---------------------------------------------------------------------------
// The sealed files
// ---------------------------------------------------------------------------
//
// `calendar_connection_secrets.feed_files` is the same map for the calendars a
// household uploaded instead of linking. It is read one id at a time and never
// cached: a body is megabytes where a URL is a line, so opening all of them to
// serve one calendar would be the wrong trade in both directions.

/// One uploaded file's contents, or null when there is nothing openable under
/// that id.
export async function feedFileOf(
  db: SupabaseClient,
  connectionId: string,
  feedId: string,
): Promise<string | null> {
  const envelope = (await envelopes(db, connectionId, "feed_files"))[feedId];
  return envelope ? await open(envelope) : null;
}

/// Seals one file body under the active key and files it against [feedId],
/// dropping any id in [keep] that is not listed there any more.
export async function putFeedFile(
  db: SupabaseClient,
  connectionId: string,
  feedId: string,
  ics: string,
  keep?: string[],
): Promise<void> {
  const current = await envelopes(db, connectionId, "feed_files");
  const next: Record<string, string> = {};
  for (const [id, envelope] of Object.entries(current)) {
    if (!keep || keep.includes(id)) next[id] = envelope;
  }
  next[feedId] = await seal(ics);
  await writeEnvelopes(db, connectionId, "feed_files", next);
}

/// Seals a file body without writing it anywhere — the same reason
/// [sealFeedUrl] exists: a new connection is an upsert that mints the row, and
/// the row must never exist before we know the payload can be sealed at all.
export async function sealFeedFile(ics: string): Promise<string> {
  return await seal(ics);
}

export async function setFeedFiles(
  db: SupabaseClient,
  connectionId: string,
  map: Record<string, string>,
): Promise<void> {
  await writeEnvelopes(db, connectionId, "feed_files", map);
}

/// Keeps exactly [keep] and forgets the rest, so that removing an uploaded
/// calendar actually destroys the file rather than orphaning it in a column
/// nobody reads. The counterpart of [keepFeedUrls], and called beside it: a
/// connection can hold both kinds and a removal does not know which it had.
export async function keepFeedFiles(
  db: SupabaseClient,
  connectionId: string,
  keep: string[],
): Promise<void> {
  const current = await envelopes(db, connectionId, "feed_files");
  const next: Record<string, string> = {};
  for (const [id, envelope] of Object.entries(current)) {
    if (keep.includes(id)) next[id] = envelope;
  }
  if (Object.keys(next).length === Object.keys(current).length) return;

  await writeEnvelopes(db, connectionId, "feed_files", next);
}

/// Keeps exactly [keep] and forgets the rest. Called when a feed is removed, so
/// that dropping a link actually destroys the credential rather than orphaning
/// it in a column nobody reads.
export async function keepFeedUrls(
  db: SupabaseClient,
  connectionId: string,
  keep: string[],
): Promise<void> {
  const current = await envelopes(db, connectionId);
  const next: Record<string, string> = {};
  for (const [id, envelope] of Object.entries(current)) {
    if (keep.includes(id)) next[id] = envelope;
  }
  if (Object.keys(next).length === Object.keys(current).length) return;

  await setFeedUrls(db, connectionId, next);
}

// ---------------------------------------------------------------------------
// Moving the old plaintext URLs out of `config`
// ---------------------------------------------------------------------------

/// Seals any pre-sealing feed on this connection and rewires everything that
/// pointed at it by URL. Returns the connection as it now stands, so the caller
/// can go on using the value it already had.
///
/// A no-op — and one cheap `Array.isArray` — for every connection that is not a
/// link connection, which is why it is safe to call at the top of the read path.
///
/// Not a SQL migration, because SQL cannot encrypt: CALENDAR_SECRET_KEY is a
/// function secret and deliberately never reaches the database. So the sealing
/// happens where the key is, on the first read after this deploy, and the
/// household notices nothing.
///
/// The order of the three writes is the whole safety argument. The sealed URL
/// is written **first**: if the process dies after it, `config` still holds the
/// plaintext and the next read migrates again from a known-good source. Strip
/// `config` first instead and a crash loses the family's calendars for good.
export async function migrateLegacyFeeds<T extends FeedConnection>(
  db: SupabaseClient,
  connection: T,
): Promise<T> {
  const legacy = legacyFeedsOf(connection.config);
  if (!legacy.length) return connection;

  const raw = connection.config.feeds as unknown[];
  const rewritten: FeedEntry[] = [];
  const idFor = new Map<string, string>();

  // The ids that were already sealed before this run. They go in every
  // keep-list below, so a half-migrated connection whose first entry is legacy
  // and whose second is already sealed does not prune the second one's envelope
  // on the way past.
  const alreadySealed = feedsOf(connection.config).map((f) => f.id);
  const minted: string[] = [];

  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;

    const already = (entry as FeedEntry).id;
    if (typeof already === "string" && already) {
      rewritten.push(entry as FeedEntry);
      continue;
    }

    const url = (entry as LegacyFeedEntry).url;
    if (typeof url !== "string" || !url.startsWith("https://")) continue;

    const id = crypto.randomUUID();
    const host = (entry as LegacyFeedEntry).host ?? hostOf(url);
    idFor.set(url, id);
    rewritten.push({
      id,
      name: (entry as LegacyFeedEntry).name?.trim() || host,
      host,
      added_at: (entry as LegacyFeedEntry).added_at,
    });

    minted.push(id);

    // One at a time, so a connection with five feeds that fails on the third
    // has the first two already sealed and finishes on the next read.
    await putFeedUrl(db, connection.id, id, url, [...alreadySealed, ...minted]);
  }

  const swap = (key: string) => idFor.get(key) ?? key;

  const selected = connection.selected_calendars === null
    ? null
    : connection.selected_calendars.map(swap);

  const names: Record<string, string> = {};
  for (const [key, value] of Object.entries(connection.calendar_names ?? {})) {
    names[swap(key)] = value;
  }

  const owners: Record<string, string> = {};
  for (const [key, value] of Object.entries(connection.calendar_owners ?? {})) {
    owners[swap(key)] = value;
  }

  const config = { ...connection.config, feeds: rewritten };

  const { error } = await db
    .from("calendar_connections")
    .update({
      config,
      selected_calendars: selected,
      calendar_names: names,
      calendar_owners: owners,
    })
    .eq("id", connection.id);
  if (error) throw new Error(`feed migration failed: ${error.message}`);

  // Last, and separately: the `calendars` rows keyed on the old external id.
  // Rewriting them rather than letting the stale sweep delete and re-create is
  // what keeps each calendar's colour, its position and the member it was
  // assigned to — a re-created row would come back as an unassigned calendar in
  // a different shade, which is a visible regression for a silent migration.
  for (const [url, id] of idFor) {
    await db
      .from("calendars")
      .update({ external_id: id })
      .eq("connection_id", connection.id)
      .eq("external_id", url);
  }

  console.log(
    `sealed ${idFor.size} feed url(s) on connection ${connection.id}: ` +
      [...idFor.keys()].map(redact).join(", "),
  );

  // Cast because a spread of `T` plus overrides is not provably `T` to the
  // compiler, only to the reader.
  return {
    ...connection,
    config,
    selected_calendars: selected,
    calendar_names: names,
    calendar_owners: owners,
  } as T;
}
