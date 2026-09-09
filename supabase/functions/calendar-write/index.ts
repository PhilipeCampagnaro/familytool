/// Write one event back to a connected calendar — the counterpart of
/// calendar-events.
///
///   POST { action: 'create'|'update'|'delete', calendar_id, uid?, title?,
///          all_day, date, time, end_date, end_time, location?, notes?,
///          repeat?, scope?, series_uid?, occurrence_date?, occurrence_time? }
///     -> { ok: true, uid }
///
/// `repeat` creates a series; the last five fields are how a change to one that
/// already exists says which occurrences it reaches. Google and Graph address an
/// occurrence and its series by two different ids, so there `scope` picks one of
/// `uid` and `series_uid`. iCalendar gives them the same UID, so on CalDAV the
/// occurrence has to be named by the moment it starts at — see the "Writing one
/// occurrence of a series" block in `_shared/caldav.ts`.
///
/// Reading through to the provider without being able to write back makes
/// Aporah a viewer. A family that plans an appointment here expects it in the
/// Google calendar on the parent's phone, not only in this app.
///
/// **Nothing written here is stored.** The event goes to Google, Outlook or the
/// CalDAV server, and comes back on the next `calendar-events` read like any
/// other event of theirs. That is the same trade as the read path: the account
/// stays the system of record and Aporah keeps no copy.
///
/// Events on Aporah's own calendar do not come through here at all — they are
/// ordinary `public.events` rows the client writes over PostgREST under RLS.
/// This function exists precisely for the calendars we have no rows for.
///
/// Times are wall-clock in Europe/Berlin rather than instants. A German family
/// types "14:00" and means 14:00 whatever the offset was on the day they typed
/// it; converting to UTC in the app would freeze that offset across a DST
/// boundary.
///
/// Function secrets: CALENDAR_SECRET_KEY (+ the OAuth client secrets, for the
/// token refresh that happens here).

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { membershipOf } from "../_shared/calendar.ts";
import { fetchWithTimeout } from "../_shared/net.ts";
import {
  accessToken,
  caldavCredentials,
  type Connection,
  ReconnectRequired,
} from "../_shared/providers.ts";
import {
  type CalDavEventInput,
  createEvent as createCalDav,
  deleteEvent as deleteCalDav,
  editSeries,
  excludeOccurrence,
  findEventHref,
  icsIsRecurring,
  type Occurrence,
  overrideOccurrence,
  putEvent,
  putIcs,
  readEventIcs,
} from "../_shared/caldav.ts";

const TZ = "Europe/Berlin";

type Action = "create" | "update" | "delete";

/// The event as the user typed it. `endDate` is **exclusive** for an all-day
/// event, matching iCalendar, Google and our own model.
interface Draft {
  title: string;
  date: string;
  time: string | null;
  endDate: string;
  endTime: string | null;
  location: string;
  notes: string;

  /// How often it comes round, or null when the client said nothing about
  /// repetition — which on an update means "leave the rule exactly as it is",
  /// not "stop repeating". The app omits the key rather than sending a null for
  /// precisely that reason: it is shown expanded occurrences and never the rule
  /// behind them, so it is in no position to restate one.
  repeat: Repeat | null;
}

/// The rule as the app states it: a frequency, how many of them apart, and where
/// it stops. [weekday] is `1` for Monday through `7` for Sunday and rides along
/// for Graph alone, which will not infer a weekly pattern's day from the start.
interface Repeat {
  freq: "daily" | "weekly" | "monthly" | "yearly";
  interval: number;
  /// YYYY-MM-DD, the last day the series may land on, **inclusive**. Null for a
  /// rule with no end.
  until: string | null;
  weekday: number;
}

/// Which occurrences a change reaches. Only ever asked of a repeating
/// appointment; a one-off is `single` and the distinction never comes up.
type Scope = "single" | "series";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const action = body.action;
  if (action !== "create" && action !== "update" && action !== "delete") {
    return fail("Unbekannte Aktion.");
  }

  const calendarId = typeof body.calendar_id === "string" ? body.calendar_id : "";
  if (!calendarId) return fail("Kein Kalender ausgewählt.");

  const eventUid = typeof body.uid === "string" ? body.uid.trim() : "";
  if (action !== "create" && !eventUid) return fail("Der Termin ist unbekannt.");

  // Family scoping is the whole tenant boundary here: service_role sees every
  // calendar, so this filter is what stops one household writing into another's.
  const { data: calendar } = await db
    .from("calendars")
    .select("id, family_id, provider, external_id, is_read_only, connection_id")
    .eq("id", calendarId)
    .eq("family_id", membership.familyId)
    .maybeSingle();

  if (!calendar) return fail("Dieser Kalender gehört nicht zu eurem Haushalt.", 403);
  if (calendar.provider === "aporah") {
    // Not a permission problem — a routing one. Own events never come here.
    return fail("Dieser Kalender wird direkt gespeichert.", 400);
  }
  if (calendar.is_read_only || !calendar.connection_id || !calendar.external_id) {
    return fail("In diesen Kalender kann Aporah nicht schreiben.", 403);
  }

  const { data: connectionRow } = await db
    .from("calendar_connections")
    .select(
      "id, family_id, provider, auth_type, external_account, display_name, config, selected_calendars, is_read_only, created_by",
    )
    .eq("id", calendar.connection_id)
    .eq("family_id", membership.familyId)
    .maybeSingle();

  if (!connectionRow) return fail("Die Verbindung wurde nicht gefunden.", 404);
  const connection = connectionRow as unknown as Connection;

  let draft: Draft | null = null;
  if (action !== "delete") {
    try {
      draft = parseDraft(body);
    } catch (e) {
      return fail((e as Error).message);
    }
  }

  const scope: Scope = body.scope === "series" ? "series" : "single";
  const seriesUid = typeof body.series_uid === "string" ? body.series_uid.trim() : "";
  const occurrence = parseOccurrence(body);

  try {
    const written = await write(
      db,
      connection,
      calendar.external_id as string,
      action,
      eventUid,
      draft,
      { scope, seriesUid, occurrence },
    );
    return json({ ok: true, uid: written });
  } catch (e) {
    if (e instanceof ReconnectRequired) {
      return fail("Die Verbindung ist abgelaufen. Bitte erneut verbinden.", 409);
    }
    // The provider's raw error can echo a token or an address back; log it, and
    // tell the user something they can act on.
    console.error(`calendar-write ${action} failed: ${(e as Error).message}`);
    return fail("Der Termin konnte nicht im verbundenen Kalender gespeichert werden.", 502);
  }
});

// ---------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const TIME = /^\d{2}:\d{2}$/;

function parseDraft(body: Record<string, unknown>): Draft {
  const title = String(body.title ?? "").trim();
  if (!title) throw new Error("Der Termin braucht einen Titel.");

  const date = String(body.date ?? "");
  if (!DATE.test(date)) throw new Error("Das Datum fehlt.");

  const allDay = body.all_day === true;
  const time = allDay ? null : asTime(body.time);
  const endTime = allDay ? null : asTime(body.end_time);
  if (!allDay && (time === null || endTime === null)) throw new Error("Die Uhrzeit fehlt.");

  let endDate = DATE.test(String(body.end_date ?? "")) ? String(body.end_date) : date;
  let end = endTime;

  // An all-day event's end is exclusive, so a single day ends the next morning.
  // The form sends it that way; this is the guard against a client that does
  // not, which would otherwise produce a zero-length event — Graph rejects one
  // outright and Google silently rounds it, which is worse.
  if (allDay && endDate <= date) {
    endDate = addDays(date, 1);
  } else if (!allDay && `${endDate}T${end}` <= `${date}T${time}`) {
    endDate = date;
    end = addHour(time!);
    if (end <= time!) endDate = addDays(date, 1);
  }

  return {
    title: title.slice(0, 300),
    date,
    time,
    endDate,
    endTime: end,
    location: String(body.location ?? "").trim().slice(0, 300),
    notes: String(body.notes ?? "").trim().slice(0, 2000),
    repeat: parseRepeat(body.repeat),
  };
}

const FREQS = ["daily", "weekly", "monthly", "yearly"] as const;

/// The rule, or null where there is none — a missing key and a malformed one
/// both mean "say nothing about repetition", which on an update is what leaves
/// an existing rule alone.
function parseRepeat(raw: unknown): Repeat | null {
  if (!raw || typeof raw !== "object") return null;
  const r = raw as Record<string, unknown>;

  const freq = FREQS.find((f) => f === r.freq);
  if (!freq) return null;

  // Capped rather than rejected: an interval is a convenience, and no rule the
  // app can produce goes past 2.
  const interval = Math.min(Math.max(Math.round(Number(r.interval) || 1), 1), 52);
  const until = DATE.test(String(r.until ?? "")) ? String(r.until) : null;
  const weekday = Math.min(Math.max(Math.round(Number(r.weekday) || 1), 1), 7);

  return { freq, interval, until, weekday };
}

/// Which occurrence of a series a change is aimed at, as the wall-clock start
/// the app showed the user. Absent for a create, and for every one-off.
function parseOccurrence(body: Record<string, unknown>): Occurrence | null {
  const date = String(body.occurrence_date ?? "");
  if (!DATE.test(date)) return null;
  return { date, time: asTime(body.occurrence_time) };
}

/// The rule as RFC 5545 writes it, without the `RRULE:` name — what Google and
/// a CalDAV server both take.
///
/// `UNTIL` is inclusive and has to match `DTSTART`'s value type: a DATE for an
/// all-day series, and for a timed one a UTC instant — the end of the last day,
/// in Berlin, expressed in UTC, so the final occurrence is kept whatever the
/// offset is on that date.
function rruleFor(repeat: Repeat, allDay: boolean): string {
  const parts = [`FREQ=${repeat.freq.toUpperCase()}`];
  if (repeat.interval > 1) parts.push(`INTERVAL=${repeat.interval}`);
  if (repeat.until) {
    parts.push(`UNTIL=${allDay ? compact(repeat.until) : endOfDayUtc(repeat.until)}`);
  }
  return parts.join(";");
}

function compact(date: string): string {
  return date.replace(/-/g, "");
}

/// `20261109T215959Z` — one second before midnight in Berlin on [date].
function endOfDayUtc(date: string): string {
  const [y, m, d] = date.split("-").map(Number);
  // The offset is looked up *at* the moment being converted rather than assumed,
  // which is the whole point: a series ending in November and one ending in
  // August do not have the same last second.
  const guess = Date.UTC(y, m - 1, d, 23, 59, 59);
  const at = new Date(guess - berlinOffset(new Date(guess)));
  return at.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/// How far Berlin is ahead of UTC at [at], in milliseconds. Read out of the
/// runtime's own zone data rather than hardcoded, so the DST rule is the
/// current one and not a copy of it.
function berlinOffset(at: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TZ,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(at);

  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  const asUtc = Date.UTC(
    get("year"),
    get("month") - 1,
    get("day"),
    get("hour") % 24,
    get("minute"),
    get("second"),
  );
  return asUtc - at.getTime();
}

function asTime(raw: unknown): string | null {
  const value = String(raw ?? "");
  return TIME.test(value) ? value : null;
}

/// One hour later on the same clock, wrapping past midnight — the caller checks
/// for the wrap and rolls the date itself.
function addHour(time: string): string {
  const [h, m] = time.split(":").map(Number);
  return `${String((h + 1) % 24).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Returns the provider's id for the event — the same value that comes back as
/// `uid` on the next read, so the client can edit what it just created without
/// waiting for a refresh.
/// Everything the two answers to "nur dieser Termin oder die ganze Serie?" need
/// in order to be addressable. All three are absent on a create and on a
/// one-off, where the question never arises.
interface Target {
  scope: Scope;
  seriesUid: string;
  occurrence: Occurrence | null;
}

function write(
  db: SupabaseClient,
  connection: Connection,
  externalId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
  target: Target,
): Promise<string> {
  switch (connection.provider) {
    case "google":
      return writeGoogle(db, connection, externalId, action, uid, draft, target);
    case "outlook":
      return writeOutlook(db, connection, externalId, action, uid, draft, target);
    case "icloud":
    case "iserv":
      // A link-connected school calendar is a one-way ICS feed with no
      // addressable resource to PUT to. Unreachable in practice — every one is
      // written `is_read_only`, and the guard above turns that away with a
      // message the user can act on — but the switch has to stay exhaustive,
      // and an accidental route into a CalDAV PUT with no credentials is worth
      // naming rather than letting the type checker infer it away.
      if (connection.auth_type === "public") {
        throw new Error("link feed is not writable");
      }
      return writeCalDav(db, connection, externalId, action, uid, draft, target);
    case "webuntis":
      throw new Error("webuntis is not writable");
  }
}

/// Google addresses an occurrence and its series separately — an expanded
/// instance has its own id, and `recurringEventId` names the event the rule
/// lives on — so both answers are a PATCH or a DELETE, only of different ids.
async function writeGoogle(
  db: SupabaseClient,
  connection: Connection,
  calendarId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
  target: Target,
): Promise<string> {
  const token = await accessToken(db, connection);
  const base = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`;
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  const id = seriesOrOccurrence(uid, target);

  if (action === "delete") {
    const res = await fetchWithTimeout(`${base}/${encodeURIComponent(id)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
    // 410 Gone means somebody else already deleted it, which is the outcome
    // asked for.
    if (!res.ok && res.status !== 404 && res.status !== 410) {
      throw new Error(`google delete ${res.status}`);
    }
    return id;
  }

  const e = draft!;
  const timed = e.time !== null;
  const payload: Record<string, unknown> = {
    summary: e.title,
    location: e.location || null,
    description: e.notes || null,
    start: timed
      ? { dateTime: `${e.date}T${e.time}:00`, timeZone: TZ, date: null }
      : { date: e.date, dateTime: null, timeZone: null },
    end: timed
      ? { dateTime: `${e.endDate}T${e.endTime}:00`, timeZone: TZ, date: null }
      : { date: e.endDate, dateTime: null, timeZone: null },
  };
  // Present only when there is a rule to state. A PATCH is a merge, so leaving
  // the key out keeps whatever rule the event already had — sending a null
  // would strip it and quietly turn a whole series into one appointment.
  if (e.repeat) payload.recurrence = [`RRULE:${rruleFor(e.repeat, !timed)}`];

  const res = await fetchWithTimeout(
    action === "create" ? base : `${base}/${encodeURIComponent(id)}`,
    { method: action === "create" ? "POST" : "PATCH", headers, body: JSON.stringify(payload) },
  );
  if (res.status === 401) throw new ReconnectRequired("google 401");
  if (!res.ok) throw new Error(`google ${action} ${res.status}`);

  const created = await res.json();
  return typeof created.id === "string" ? created.id : id;
}

/// The id a change is aimed at: the series where the user asked for all of it,
/// the occurrence otherwise. Falls back to the occurrence when no series id came
/// along, which is any event that does not repeat.
function seriesOrOccurrence(uid: string, target: Target): string {
  return target.scope === "series" && target.seriesUid ? target.seriesUid : uid;
}

/// Graph, like Google, hands out an id per occurrence and names the series in
/// `seriesMasterId`, so the two answers are again the same call on two ids.
async function writeOutlook(
  db: SupabaseClient,
  connection: Connection,
  calendarId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
  target: Target,
): Promise<string> {
  const token = await accessToken(db, connection);
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  // Graph event ids are unique across the mailbox, so update and delete address
  // /me/events directly — only a create needs to name the calendar.
  const id = seriesOrOccurrence(uid, target);
  const existing = `https://graph.microsoft.com/v1.0/me/events/${encodeURIComponent(id)}`;

  if (action === "delete") {
    const res = await fetchWithTimeout(existing, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok && res.status !== 404 && res.status !== 410) {
      throw new Error(`outlook delete ${res.status}`);
    }
    return id;
  }

  const e = draft!;
  const timed = e.time !== null;
  const payload: Record<string, unknown> = {
    subject: e.title,
    isAllDay: !timed,
    location: { displayName: e.location },
    body: { contentType: "text", content: e.notes },
    start: timed
      ? { dateTime: `${e.date}T${e.time}:00`, timeZone: TZ }
      : { dateTime: `${e.date}T00:00:00`, timeZone: TZ },
    end: timed
      ? { dateTime: `${e.endDate}T${e.endTime}:00`, timeZone: TZ }
      : { dateTime: `${e.endDate}T00:00:00`, timeZone: TZ },
  };
  // Same reasoning as Google's `recurrence`: omitted, not nulled, so a PATCH
  // that says nothing about repetition changes nothing about it.
  if (e.repeat) payload.recurrence = graphRecurrence(e.repeat, e.date);

  const res = await fetchWithTimeout(
    action === "create"
      ? `https://graph.microsoft.com/v1.0/me/calendars/${encodeURIComponent(calendarId)}/events`
      : existing,
    { method: action === "create" ? "POST" : "PATCH", headers, body: JSON.stringify(payload) },
  );
  if (res.status === 401) throw new ReconnectRequired("graph 401");
  if (!res.ok) throw new Error(`outlook ${action} ${res.status}`);

  const created = await res.json();
  return typeof created.id === "string" ? created.id : id;
}

const GRAPH_DAYS = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
];

/// Graph is the one provider that will not take an RRULE. It wants the same rule
/// as a pattern and a range, and unlike iCalendar it infers nothing from the
/// start: a weekly pattern with no `daysOfWeek` is rejected, and a monthly one
/// needs the day spelled out. [start] is the event's own first day, which is
/// where both of those come from.
function graphRecurrence(repeat: Repeat, start: string): Record<string, unknown> {
  const [, month, day] = start.split("-").map(Number);

  const pattern: Record<string, unknown> = { interval: repeat.interval };
  switch (repeat.freq) {
    case "daily":
      pattern.type = "daily";
      break;
    case "weekly":
      pattern.type = "weekly";
      pattern.daysOfWeek = [GRAPH_DAYS[repeat.weekday - 1]];
      break;
    case "monthly":
      pattern.type = "absoluteMonthly";
      pattern.dayOfMonth = day;
      break;
    case "yearly":
      pattern.type = "absoluteYearly";
      pattern.dayOfMonth = day;
      pattern.month = month;
      break;
  }

  return {
    pattern,
    range: repeat.until
      // Graph's endDate is a date and inclusive, which is exactly what the app
      // means by "endet am" — no conversion, unlike the RRULE the other two get.
      ? { type: "endDate", startDate: start, endDate: repeat.until, recurrenceTimeZone: TZ }
      : { type: "noEnd", startDate: start, recurrenceTimeZone: TZ },
  };
}

/// The one provider where a series and its occurrences are the same resource,
/// so "nur dieser Termin" cannot be a different URL — it is an EXDATE or a
/// RECURRENCE-ID override written into the ICS that is already there.
///
/// **This function used to PUT a freshly built single VEVENT over whatever it
/// found.** On a repeating appointment that replaced the series with one date:
/// changing the time of one football training deleted the rest of the term. So
/// nothing is written blind any more — the resource is read first, and a
/// recurring one is amended rather than replaced.
async function writeCalDav(
  db: SupabaseClient,
  connection: Connection,
  collectionUrl: string,
  action: Action,
  uid: string,
  draft: Draft | null,
  target: Target,
): Promise<string> {
  const { user, password } = await caldavCredentials(db, connection);

  if (action === "create") {
    const fresh = crypto.randomUUID();
    await createCalDav(collectionUrl, user, password, toCalDav(fresh, draft!));
    return fresh;
  }

  // An event created in Apple Calendar is not named `<uid>.ics`, so the href has
  // to be looked up rather than guessed.
  const href = await findEventHref(collectionUrl, user, password, uid);
  if (!href) {
    // Deleting something already gone is the outcome asked for; editing it is
    // not, and silently recreating it elsewhere would be worse than failing.
    if (action === "delete") return uid;
    throw new Error("caldav event not found");
  }

  const ics = await readEventIcs(href, user, password);

  // Nothing repeating in front of us: the resource is gone, unreadable, or holds
  // a plain appointment. The straight replace is right for all three.
  if (!ics || !icsIsRecurring(ics)) {
    if (action === "delete") await deleteCalDav(href, user, password);
    else await putEvent(href, user, password, toCalDav(uid, draft!));
    return uid;
  }

  if (target.scope === "series") {
    if (action === "delete") {
      await deleteCalDav(href, user, password);
      return uid;
    }
    const next = editSeries(ics, toCalDav(uid, draft!));
    if (!next) throw new Error("caldav series edit failed");
    await putIcs(href, user, password, next);
    return uid;
  }

  // One occurrence of a series, which is only addressable by the moment it
  // starts at. Without that there is no safe move: replacing the resource would
  // take the series with it, so this fails and says nothing was saved rather
  // than doing something larger than what was asked.
  const occurrence = target.occurrence;
  if (!occurrence) throw new Error("caldav occurrence unknown");

  const next = action === "delete"
    ? excludeOccurrence(ics, occurrence)
    : overrideOccurrence(ics, occurrence, toCalDav(uid, draft!));
  if (!next) throw new Error(`caldav occurrence ${action} failed`);
  await putIcs(href, user, password, next);
  return uid;
}

function toCalDav(uid: string, e: Draft): CalDavEventInput {
  return {
    uid,
    title: e.title,
    date: e.date,
    time: e.time,
    endDate: e.endDate,
    endTime: e.endTime,
    location: e.location || null,
    notes: e.notes || null,
    rrule: e.repeat ? rruleFor(e.repeat, e.time === null) : null,
  };
}
