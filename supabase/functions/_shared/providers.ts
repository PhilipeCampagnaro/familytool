/// Reading a connected personal account: Google, Outlook, and the two CalDAV
/// servers (iCloud, IServ).
///
/// Everything here is a **read through to the provider**. Nothing in this file
/// writes an event anywhere. That is the point: a personal calendar holds
/// personal data in the strict sense — a therapy appointment, a lawyer, an
/// interview — and Aporah has no business keeping a copy of it on a server in
/// order to draw a month grid. The account stays the system of record, the
/// device keeps the offline copy, and the only thing we store is the token
/// needed to ask again.
///
/// Split out of the old calendar-sync, which pulled all of this into
/// public.events. The listing and reading code is unchanged; what went away is
/// the reconcile that followed it.

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { open } from "./secrets.ts";
import {
  freshAccessToken,
  type Provider,
  type RemoteCalendar,
  type SyncedEvent,
} from "./calendar.ts";
import { collections, readEvents } from "./caldav.ts";
import { feedsOf, readFeedEvents } from "./ics_feed.ts";
import {
  login as untisLogin,
  normaliseConfig as normaliseUntis,
  readHomework as untisHomework,
  readTimetable,
  UNTIS_TIMETABLE,
  type UntisConfig,
  type UntisHomework,
} from "./untis.ts";
import { fetchWithTimeout } from "./net.ts";

/// Signals "the user has to do something" as opposed to "this failed, try
/// later". Only the former flips a connection to reconnect_required.
export class ReconnectRequired extends Error {}

export interface Connection {
  id: string;
  family_id: string;
  provider: Provider;
  auth_type: string;
  external_account: string;
  display_name: string;
  config: Record<string, unknown>;
  selected_calendars: string[] | null;

  /// external_id -> the name this household gave that calendar in the setup
  /// sheet. Absent, or absent for one id, means the provider's own name stands.
  ///
  /// Optional rather than nullable: only `calendar-events` selects it, because
  /// it is the only function that writes a `calendars` row. Reading and writing
  /// events never needs to know what the household calls the thing.
  calendar_names?: Record<string, string> | null;

  is_read_only: boolean;
  created_by: string | null;

  /// Whose day the calendars from this account belong to — the default a new
  /// `calendars` row starts with. **Not a visibility field:** everyone in the
  /// household sees every calendar regardless. See the migration.
  ///
  /// `owner_label` covers the person who has no account to be a member of, which
  /// for a school connection is most children. Both null means the household.
  ///
  /// Optional for the same reason as `calendar_names`: only `calendar-events`
  /// reads them, because it is the only function that writes a `calendars` row.
  owner_member_id?: string | null;
  owner_label?: string | null;

  /// external_id -> whose that one calendar is, overriding the two fields
  /// above for it. `"family"`, `"member:<user_id>"` or `"person:<Name>"`, with
  /// `"*"` standing for every calendar on the account.
  ///
  /// The household's own choice, made per calendar in Settings, because one
  /// Apple ID routinely carries the family's calendar and one parent's work
  /// calendar — see the migration.
  calendar_owners?: Record<string, string> | null;
}

// ---------------------------------------------------------------------------
// Providers — listing
// ---------------------------------------------------------------------------

export async function listRemoteCalendars(
  db: SupabaseClient,
  connection: Connection,
): Promise<RemoteCalendar[]> {
  switch (connection.provider) {
    case "google": {
      const token = await accessToken(db, connection);
      return await listGoogle(token);
    }
    case "outlook": {
      const token = await accessToken(db, connection);
      return await listOutlook(token);
    }
    case "webuntis":
      // Two routes, told apart by `auth_type` exactly as IServ's are. 'secret'
      // is the app-secret login, where a pupil has one timetable and there is
      // nothing to enumerate; 'public' is the pasted-link kind.
      if (connection.auth_type === "secret") return untisTimetable(connection);
      return linkedFeeds(connection);
    case "icloud":
    case "iserv": {
      // An IServ connection is one of two quite different things, and
      // `auth_type` is what tells them apart: 'public' is the pasted-link kind,
      // which has no credential and nothing to discover, and 'caldav' is the
      // older login kind that still enumerates collections.
      if (connection.auth_type === "public") return linkedFeeds(connection);

      const { user, password, home } = await caldavCredentials(db, connection);
      const found = await collections(home, user, password, connection.provider === "iserv");
      return found.map((c) => ({
        externalId: c.url,
        name: c.name || c.url,
        readOnly: c.readOnly,
      }));
    }
  }
}

/// The one calendar a WebUntis login offers.
///
/// A constant rather than a listing, because a pupil has exactly one timetable:
/// asking Untis what calendars this account has would be a round trip whose
/// answer we already know. The household's own name for it wins where it has
/// given one — `calendar-untis` writes that at connect time, so it is set from
/// the first sync onwards.
function untisTimetable(connection: Connection): RemoteCalendar[] {
  return [{
    externalId: UNTIS_TIMETABLE,
    name: connection.calendar_names?.[UNTIS_TIMETABLE]?.trim() || "Stundenplan",
    readOnly: true,
  }];
}

/// The pasted feeds on a link connection, as sub-calendars.
///
/// The URL is the `externalId`, so a feed the user removes in Settings stops
/// being listed here, `calendar-events` finds it missing from the wanted set,
/// and its `calendars` row is deleted by the stale sweep that already runs —
/// no extra removal path.
function linkedFeeds(connection: Connection): RemoteCalendar[] {
  return feedsOf(connection.config).map((f) => ({
    externalId: f.url,
    name: f.name,
    readOnly: true,
  }));
}

export async function accessToken(db: SupabaseClient, connection: Connection): Promise<string> {
  const token = await freshAccessToken(db, connection.id, connection.provider);
  if (!token) throw new ReconnectRequired("no usable access token");
  return token;
}

export async function caldavCredentials(db: SupabaseClient, connection: Connection) {
  const { data } = await db
    .from("calendar_connection_secrets")
    .select("caldav_password")
    .eq("connection_id", connection.id)
    .maybeSingle();

  const password = await open(data?.caldav_password);
  const home = typeof connection.config.home_url === "string" ? connection.config.home_url : "";
  if (!password || !home) throw new ReconnectRequired("no usable CalDAV credentials");

  return { user: connection.external_account, password, home };
}

/// The four fields a WebUntis read needs, from `config` plus the sealed secret.
///
/// A key that will not unseal — written under a rotated CALENDAR_SECRET_KEY, or
/// simply absent — is a ReconnectRequired rather than an error, because the fix
/// is the user showing us the QR code again and that is precisely what the
/// reconnect_required status asks for.
export async function untisCredentials(
  db: SupabaseClient,
  connection: Connection,
): Promise<UntisConfig> {
  const { data } = await db
    .from("calendar_connection_secrets")
    .select("app_secret")
    .eq("connection_id", connection.id)
    .maybeSingle();

  const secret = await open(data?.app_secret);
  const config = secret
    ? normaliseUntis({
      server: connection.config.server as string | undefined,
      school: connection.config.school as string | undefined,
      // The login is the second half of `external_account` — school/user — and
      // is read from there rather than duplicated into config.
      user: connection.external_account.split("/").slice(1).join("/"),
      secret,
    })
    : null;

  if (!config) throw new ReconnectRequired("no usable WebUntis credentials");
  return config;
}

/// The homework a connection carries, or nothing at all.
///
/// Only WebUntis has any, and only over the app secret — a pasted ICS link is
/// flat text with no such thing in it. Everything else answers `[]` so the
/// caller can ask every connection without knowing which is which.
///
/// **Never allowed to fail a refresh.** Homework is an extra on top of the
/// timetable, and a school that has the module switched off, or switches it off
/// mid-term, must not cost the family their lessons. The error is logged and
/// the calendars come back regardless.
export async function readConnectionHomework(
  db: SupabaseClient,
  connection: Connection,
  window: { from: Date; to: Date },
): Promise<UntisHomework[]> {
  if (connection.provider !== "webuntis" || connection.auth_type !== "secret") return [];

  try {
    // A second login rather than the one `readRemoteEvents` just made: sessions
    // are not passed between provider calls, and a WebUntis login is one round
    // trip against a fortnight of timetable that has to be fetched anyway.
    const config = await untisCredentials(db, connection);
    return await untisHomework(config, await untisLogin(config), window);
  } catch (e) {
    console.error(`homework failed for ${connection.id}: ${(e as Error).message}`);
    return [];
  }
}

async function listGoogle(token: string): Promise<RemoteCalendar[]> {
  const out: RemoteCalendar[] = [];
  let pageToken: string | undefined;
  let guard = 0;

  do {
    const url = new URL("https://www.googleapis.com/calendar/v3/users/me/calendarList");
    url.searchParams.set("maxResults", "250");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const res = await fetchWithTimeout(url, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 401 || res.status === 403) {
      // 403 here is almost always a connection made before the calendarlist
      // scope was requested. Reconnecting is the fix, and it is what the
      // reconnect_required status asks the user to do.
      throw new ReconnectRequired(`calendarList ${res.status}`);
    }
    if (!res.ok) throw new Error(`calendarList ${res.status}`);

    const body = await res.json();
    for (const item of body.items ?? []) {
      if (!item.id) continue;
      // Calendars the user has already hidden in Google's own UI stay hidden.
      if (item.selected === false) continue;
      out.push({
        externalId: item.id,
        name: (item.summaryOverride || item.summary || item.id).trim(),
        readOnly: item.accessRole === "reader" || item.accessRole === "freeBusyReader",
      });
    }
    pageToken = body.nextPageToken;
  } while (pageToken && guard++ < 20);

  return out;
}

/// One page of a Microsoft Graph collection. `@odata.nextLink` is absent on the
/// last page, which is what ends both pagination loops below.
interface GraphPage<T> {
  value?: T[];
  "@odata.nextLink"?: string;
}

async function listOutlook(token: string): Promise<RemoteCalendar[]> {
  const out: RemoteCalendar[] = [];
  let next: string | undefined =
    "https://graph.microsoft.com/v1.0/me/calendars?$select=id,name,canEdit&$top=100";
  let guard = 0;

  do {
    const res = await fetchWithTimeout(next, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 401 || res.status === 403) throw new ReconnectRequired(`calendars ${res.status}`);
    if (!res.ok) throw new Error(`calendars ${res.status}`);

    // Annotated rather than inferred: `next` is assigned out of `body`, which
    // comes from a fetch of `next`, and TypeScript refuses to walk that circle
    // on its own.
    const body: GraphPage<{ id?: string; name?: string; canEdit?: boolean }> = await res.json();
    for (const item of body.value ?? []) {
      if (!item.id) continue;
      out.push({ externalId: item.id, name: (item.name || item.id).trim(), readOnly: !item.canEdit });
    }
    next = body["@odata.nextLink"];
  } while (next && guard++ < 20);

  return out;
}

// ---------------------------------------------------------------------------
// Providers — reading
// ---------------------------------------------------------------------------

export async function readRemoteEvents(
  db: SupabaseClient,
  connection: Connection,
  calendar: RemoteCalendar,
  window: { from: Date; to: Date },
): Promise<SyncedEvent[]> {
  switch (connection.provider) {
    case "google":
      return await readGoogle(await accessToken(db, connection), calendar.externalId, window);
    case "outlook":
      return await readOutlook(await accessToken(db, connection), calendar.externalId, window);
    case "webuntis": {
      if (connection.auth_type !== "secret") {
        return await readFeedEvents(calendar.externalId, window);
      }
      // One login per refresh. Untis sessions expire after ~10 minutes idle and
      // there is nothing to keep between reads, so the TOTP is computed fresh
      // rather than a cookie stored — which also means a revoked key stops
      // working at the next refresh instead of whenever a cached session ran
      // out.
      const config = await untisCredentials(db, connection);
      return await readTimetable(config, await untisLogin(config), window);
    }
    case "icloud":
    case "iserv": {
      // Same fork as the listing above: a link connection's externalId *is* the
      // feed URL, so reading it is one GET and no credential.
      if (connection.auth_type === "public") {
        return await readFeedEvents(calendar.externalId, window);
      }

      const { user, password } = await caldavCredentials(db, connection);
      const parsed = await readEvents(calendar.externalId, user, password, window.from, window.to);
      return parsed.map((p) => ({
        uid: p.uid,
        seriesUid: p.seriesUid,
        title: p.title,
        notes: p.notes,
        location: p.location,
        startsAt: p.startsAt,
        endsAt: p.endsAt,
        allDay: p.allDay,
        href: p.href,
        etag: p.etag,
      }));
    }
  }
}

async function readGoogle(
  token: string,
  calendarId: string,
  window: { from: Date; to: Date },
): Promise<SyncedEvent[]> {
  const out: SyncedEvent[] = [];
  let pageToken: string | undefined;
  let guard = 0;

  do {
    const url = new URL(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`,
    );
    url.searchParams.set("timeMin", window.from.toISOString());
    url.searchParams.set("timeMax", window.to.toISOString());
    // Expand recurring series into instances. Everything downstream — the
    // reconcile, the events table, the Kalender screen — works in occurrences.
    url.searchParams.set("singleEvents", "true");
    url.searchParams.set("orderBy", "startTime");
    url.searchParams.set("maxResults", "2500");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const res = await fetchWithTimeout(url, { headers: { Authorization: `Bearer ${token}` } });
    if (res.status === 401) throw new ReconnectRequired("events 401");
    // One calendar can vanish between the listing and the read (unsubscribed a
    // second ago). That is not a reason to fail the other eleven.
    if (res.status === 403 || res.status === 404) return out;
    if (!res.ok) throw new Error(`events ${res.status}`);

    const body = await res.json();
    for (const item of body.items ?? []) {
      if (item.status === "cancelled") continue;

      const allDay = !!item.start?.date && !item.start?.dateTime;
      const start = item.start?.dateTime ?? item.start?.date;
      const end = item.end?.dateTime ?? item.end?.date;
      if (!start) continue;

      out.push({
        // The per-instance id, not iCalUID: iCalUID is shared by every
        // occurrence of a series and would collapse them all into one row.
        uid: item.id,
        // Present on an instance of a recurring event and nothing else, which
        // makes it both the series' address and the flag that there is one.
        seriesUid: typeof item.recurringEventId === "string" ? item.recurringEventId : null,
        title: (item.summary ?? "").trim() || "Ohne Titel",
        notes: item.description ?? null,
        location: item.location ?? null,
        startsAt: new Date(start).toISOString(),
        endsAt: new Date(end ?? start).toISOString(),
        allDay,
        etag: item.etag ?? null,
      });
    }
    pageToken = body.nextPageToken;
  } while (pageToken && guard++ < 20);

  return out;
}

async function readOutlook(
  token: string,
  calendarId: string,
  window: { from: Date; to: Date },
): Promise<SyncedEvent[]> {
  const out: SyncedEvent[] = [];
  let next: string | undefined =
    `https://graph.microsoft.com/v1.0/me/calendars/${encodeURIComponent(calendarId)}/calendarView` +
    `?startDateTime=${encodeURIComponent(window.from.toISOString())}` +
    `&endDateTime=${encodeURIComponent(window.to.toISOString())}` +
    "&$top=500&$select=id,subject,bodyPreview,location,start,end,isAllDay,isCancelled" +
    ",type,seriesMasterId";
  let guard = 0;

  const toIso = (value: string | null | undefined): string | null =>
    value ? new Date(value.endsWith("Z") ? value : `${value}Z`).toISOString() : null;

  do {
    const res = await fetchWithTimeout(next, {
      headers: {
        Authorization: `Bearer ${token}`,
        // Graph otherwise answers in the mailbox's own zone and does not always
        // say which one. Pinning UTC removes the guesswork.
        Prefer: 'outlook.timezone="UTC"',
      },
    });
    if (res.status === 401) throw new ReconnectRequired("calendarView 401");
    if (res.status === 403 || res.status === 404) return out;
    if (!res.ok) throw new Error(`calendarView ${res.status}`);

    const body: GraphPage<{
      id: string;
      subject?: string;
      bodyPreview?: string;
      location?: { displayName?: string };
      start?: { dateTime?: string };
      end?: { dateTime?: string };
      isAllDay?: boolean;
      isCancelled?: boolean;
      type?: string;
      seriesMasterId?: string;
    }> = await res.json();
    for (const item of body.value ?? []) {
      if (item.isCancelled) continue;
      const start = toIso(item.start?.dateTime);
      if (!start) continue;

      out.push({
        uid: item.id,
        // Graph fills this in on an `occurrence` and an `exception`; a
        // `singleInstance` has neither the field nor a series behind it.
        seriesUid: typeof item.seriesMasterId === "string" ? item.seriesMasterId : null,
        title: (item.subject ?? "").trim() || "Ohne Titel",
        notes: item.bodyPreview ?? null,
        location: item.location?.displayName ?? null,
        startsAt: start,
        endsAt: toIso(item.end?.dateTime) ?? start,
        allDay: !!item.isAllDay,
      });
    }
    next = body["@odata.nextLink"];
  } while (next && guard++ < 20);

  return out;
}
