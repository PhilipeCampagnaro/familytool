/// Write one event back to a connected calendar — the counterpart of
/// calendar-events.
///
///   POST { action: 'create'|'update'|'delete', calendar_id, uid?, title?,
///          all_day, date, time, end_date, end_time, location?, notes? }
///     -> { ok: true, uid }
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
  findEventHref,
  putEvent,
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
}

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

  try {
    const written = await write(
      db,
      connection,
      calendar.external_id as string,
      action,
      eventUid,
      draft,
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
  };
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
function write(
  db: SupabaseClient,
  connection: Connection,
  externalId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
): Promise<string> {
  switch (connection.provider) {
    case "google":
      return writeGoogle(db, connection, externalId, action, uid, draft);
    case "outlook":
      return writeOutlook(db, connection, externalId, action, uid, draft);
    case "icloud":
    case "iserv":
      return writeCalDav(db, connection, externalId, action, uid, draft);
  }
}

async function writeGoogle(
  db: SupabaseClient,
  connection: Connection,
  calendarId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
): Promise<string> {
  const token = await accessToken(db, connection);
  const base = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`;
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };

  if (action === "delete") {
    const res = await fetch(`${base}/${encodeURIComponent(uid)}`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
    // 410 Gone means somebody else already deleted it, which is the outcome
    // asked for.
    if (!res.ok && res.status !== 404 && res.status !== 410) {
      throw new Error(`google delete ${res.status}`);
    }
    return uid;
  }

  const e = draft!;
  const timed = e.time !== null;
  const payload = {
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

  const res = await fetch(
    action === "create" ? base : `${base}/${encodeURIComponent(uid)}`,
    { method: action === "create" ? "POST" : "PATCH", headers, body: JSON.stringify(payload) },
  );
  if (res.status === 401) throw new ReconnectRequired("google 401");
  if (!res.ok) throw new Error(`google ${action} ${res.status}`);

  const created = await res.json();
  return typeof created.id === "string" ? created.id : uid;
}

async function writeOutlook(
  db: SupabaseClient,
  connection: Connection,
  calendarId: string,
  action: Action,
  uid: string,
  draft: Draft | null,
): Promise<string> {
  const token = await accessToken(db, connection);
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  // Graph event ids are unique across the mailbox, so update and delete address
  // /me/events directly — only a create needs to name the calendar.
  const existing = `https://graph.microsoft.com/v1.0/me/events/${encodeURIComponent(uid)}`;

  if (action === "delete") {
    const res = await fetch(existing, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok && res.status !== 404 && res.status !== 410) {
      throw new Error(`outlook delete ${res.status}`);
    }
    return uid;
  }

  const e = draft!;
  const timed = e.time !== null;
  const payload = {
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

  const res = await fetch(
    action === "create"
      ? `https://graph.microsoft.com/v1.0/me/calendars/${encodeURIComponent(calendarId)}/events`
      : existing,
    { method: action === "create" ? "POST" : "PATCH", headers, body: JSON.stringify(payload) },
  );
  if (res.status === 401) throw new ReconnectRequired("graph 401");
  if (!res.ok) throw new Error(`outlook ${action} ${res.status}`);

  const created = await res.json();
  return typeof created.id === "string" ? created.id : uid;
}

async function writeCalDav(
  db: SupabaseClient,
  connection: Connection,
  collectionUrl: string,
  action: Action,
  uid: string,
  draft: Draft | null,
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

  if (action === "delete") {
    await deleteCalDav(href, user, password);
  } else {
    await putEvent(href, user, password, toCalDav(uid, draft!));
  }
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
  };
}
