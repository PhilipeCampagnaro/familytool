/// WebUntis, read through the app secret rather than a pasted link.
///
/// A student's own profile — Freigaben → "Zugriff über Untis Mobile" →
/// Zugangsdaten anzeigen — mints a QR code holding the school, the login and a
/// base32 **app secret**. That secret is what Untis Mobile itself authenticates
/// with: a TOTP is computed from it and sent instead of a password. Three
/// consequences, all of them the reason this file exists next to the pasted
/// link rather than replacing nothing:
///
///   1. We never hold the password. The secret is revocable on its own, from
///      the same page that made it, without changing the account.
///   2. It works on accounts with 2FA. Plain `authenticate` over jsonrpc.do is
///      refused for those, so a password login would fail exactly where a
///      school has taken security seriously.
///   3. The timetable arrives as **structured lessons** — subject, teacher and
///      room as separate fields, plus a status code — where the ICS feed is
///      flat text in which a cancelled lesson looks like a lesson.
///
/// The secret only ever leaves for Untis: [assertUntisHost] pins the request to
/// webuntis.com. A pasted "server" is otherwise an arbitrary outbound target
/// that we would be handing a live credential to.

import { assertPublicHost, fetchWithTimeout } from "./net.ts";
import type { SyncedEvent } from "./calendar.ts";

/// What a connection needs to reach one student's timetable. Everything but
/// [secret] is stored in `calendar_connections.config`; the secret is sealed in
/// `calendar_connection_secrets`.
export interface UntisConfig {
  /// The bare host out of the QR code — "kgs-stuhr-brinkum.webuntis.com".
  server: string;
  /// The school's short name, as the `school` query parameter wants it. Plain,
  /// **not** base64: the base64 form is what the `schoolname` cookie carries,
  /// and passing it here answers `invalid schoolname`.
  school: string;
  /// The login the QR code names — a long digit string for a pupil.
  user: string;
  secret: string;
}

/// The one sub-calendar a WebUntis account offers. There is nothing to
/// enumerate — a pupil has exactly one timetable — so this is a constant rather
/// than a listing, and it is what `selected_calendars` and `calendar_names` are
/// keyed by.
export const UNTIS_TIMETABLE = "timetable";

/// A logged-in WebUntis session: the cookie header to repeat, and who it turned
/// out to belong to.
export interface UntisSession {
  cookie: string;
  studentId: number;
  displayName: string;
  schoolName: string;
}

// ---------------------------------------------------------------------------
// The QR code
// ---------------------------------------------------------------------------

/// Reads the `untis://setschool?...` payload the QR code carries.
///
/// The same four fields are printed as text under the code, so a household that
/// cannot scan can type them; this is the scan path, and [normaliseConfig] is
/// what both end up going through.
export function parseUntisQr(raw: string): UntisConfig | null {
  const trimmed = raw.trim();
  if (!/^untis:\/\//i.test(trimmed)) return null;

  // `untis://setschool?...` is not a hierarchical URL any parser will agree
  // about — "setschool" lands in the host on some and the path on others — so
  // only the query is taken, from the first `?`.
  const query = trimmed.slice(trimmed.indexOf("?") + 1);
  if (!query || query === trimmed) return null;

  const params = new URLSearchParams(query);
  return normaliseConfig({
    server: params.get("url") ?? "",
    school: params.get("school") ?? "",
    user: params.get("user") ?? "",
    secret: params.get("key") ?? "",
  });
}

/// Trims and shapes what the user scanned or typed, or returns null when one of
/// the four is missing. Does not prove any of it works — [login] is what does
/// that, and it is the only thing that may.
export function normaliseConfig(raw: Partial<UntisConfig>): UntisConfig | null {
  // Users paste "https://kgs-stuhr-brinkum.webuntis.com/" as readily as the
  // bare host the QR code prints.
  const server = (raw.server ?? "")
    .trim()
    .replace(/^https?:\/\//i, "")
    .replace(/\/.*$/, "")
    .toLowerCase();

  const school = (raw.school ?? "").trim();
  const user = (raw.user ?? "").trim();
  const secret = (raw.secret ?? "").trim().replace(/\s+/g, "").toUpperCase();

  if (!server || !school || !user || !secret) return null;
  return { server, school, user, secret };
}

/// WebUntis is Untis GmbH's own hosting, and every instance lives under
/// webuntis.com. Pinning to it is what keeps the app secret from being sent
/// wherever a typed "server" points — this credential is live, and unlike the
/// pasted-link route there is something here worth stealing.
export async function assertUntisHost(server: string): Promise<void> {
  if (!/^[a-z0-9-]+(\.[a-z0-9-]+)*\.webuntis\.com$/.test(server)) {
    throw new Error("Das ist keine WebUntis-Adresse.");
  }
  await assertPublicHost(server);
}

// ---------------------------------------------------------------------------
// TOTP
// ---------------------------------------------------------------------------

/// The six digits Untis Mobile sends in place of a password: RFC 6238 over the
/// base32 secret, SHA-1, 30-second steps.
export async function untisOtp(secret: string, at = Date.now()): Promise<number> {
  const key = await crypto.subtle.importKey(
    "raw",
    base32(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );

  const counter = new Uint8Array(8);
  new DataView(counter.buffer).setBigUint64(0, BigInt(Math.floor(at / 30_000)));

  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, counter));
  const offset = mac[mac.length - 1] & 0x0f;
  const truncated = ((mac[offset] & 0x7f) << 24) |
    (mac[offset + 1] << 16) |
    (mac[offset + 2] << 8) |
    mac[offset + 3];

  return truncated % 1_000_000;
}

const BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

function base32(value: string): Uint8Array<ArrayBuffer> {
  const clean = value.replace(/=+$/, "").toUpperCase();
  const out = new Uint8Array(new ArrayBuffer(Math.floor((clean.length * 5) / 8)));

  let bits = 0;
  let buffer = 0;
  let at = 0;

  for (const char of clean) {
    const index = BASE32.indexOf(char);
    if (index < 0) throw new Error("Der Zugangsschlüssel ist unvollständig.");
    buffer = (buffer << 5) | index;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out[at++] = (buffer >> bits) & 0xff;
    }
  }

  if (!at) throw new Error("Der Zugangsschlüssel ist unvollständig.");
  return out;
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// Authenticates and returns the session cookie plus who it belongs to.
///
/// This *is* the connect check: a wrong secret, a school that has turned the
/// mobile access off, a login that no longer exists — all of them fail here,
/// before anything is stored, which is what lets "verbunden" keep meaning "we
/// reached it just now".
export async function login(config: UntisConfig): Promise<UntisSession> {
  await assertUntisHost(config.server);

  const url = `https://${config.server}/WebUntis/jsonrpc_intern.do` +
    `?m=getUserData2017&school=${encodeURIComponent(config.school)}&v=i2.2`;

  const res = await fetchWithTimeout(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({
      id: "aporah",
      method: "getUserData2017",
      jsonrpc: "2.0",
      params: [{
        auth: {
          clientTime: Date.now(),
          user: config.user,
          otp: await untisOtp(config.secret),
        },
      }],
    }),
  });

  // Read the body before looking at the status, because the status alone
  // misreports the most common mistake there is: a school short name that does
  // not exist answers **404** with a perfectly good JSON-RPC error saying
  // exactly that. Giving up on `!res.ok` turned "diese Schule gibt es nicht"
  // into "WebUntis war nicht erreichbar", which sends somebody to check their
  // wifi over a typo in a field they are looking at.
  const body = await res.json().catch(() => null);
  if (!body) throw new Error("WebUntis war nicht erreichbar.");

  if (body.error) {
    // -8500 invalid schoolname, -8504 bad credentials. Both are things the user
    // can fix on the form they are looking at, so both get said plainly.
    const code = body.error.code;
    if (code === -8500) throw new Error("Diese Schule gibt es auf dem Server nicht.");
    throw new Error("Die Zugangsdaten wurden nicht akzeptiert. Bitte den QR-Code neu anzeigen lassen.");
  }

  const user = body.result?.userData;
  const studentId = Number(user?.elemId);
  if (!user || !Number.isFinite(studentId) || studentId <= 0) {
    throw new Error("Zu diesen Zugangsdaten gehört kein Stundenplan.");
  }

  // `elemType` is STUDENT for a pupil's own account, which is the only kind
  // whose timetable is the one a family wants. A teacher's or a secretary's
  // account authenticates perfectly well and would then sync a staff timetable.
  if (user.elemType && user.elemType !== "STUDENT") {
    throw new Error("Diese Zugangsdaten gehören nicht zu einem Schülerkonto.");
  }

  const cookies = res.headers.getSetCookie?.() ?? [];
  const jar = cookies
    .map((c) => c.split(";", 1)[0].trim())
    .filter((c) => /^(JSESSIONID|schoolname|Tenant-Id)=/i.test(c));

  if (!jar.length) throw new Error("WebUntis hat keine Sitzung eröffnet.");

  return {
    cookie: jar.join("; "),
    studentId,
    displayName: (user.displayName as string | undefined)?.trim() || config.user,
    schoolName: (user.schoolName as string | undefined)?.trim() || config.school,
  };
}

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

/// One lesson as `getTimetable` returns it. Every field but `id`/`date` is
/// optional in practice, which is why nothing below indexes without checking.
interface Period {
  id?: number;
  date?: number;
  startTime?: number;
  endTime?: number;
  /// Absent for a normal lesson; "cancelled" or "irregular" otherwise. The one
  /// thing the ICS feed cannot tell us.
  code?: string;
  activityType?: string;
  substText?: string;
  info?: string;
  lstext?: string;
  /// The ids matter as much as the names here: they are what a homework is
  /// joined to its lesson by. See [readHomework].
  su?: Array<{ id?: number; name?: string; longname?: string }>;
  te?: Array<{ id?: number; name?: string; longname?: string }>;
  ro?: Array<{ name?: string; longname?: string }>;
  kl?: Array<{ name?: string }>;
}

/// The student's lessons in a window, as events.
///
/// Read straight through, like every other provider in this app: nothing is
/// stored on our side, and a lesson moved in Untis this morning is moved here on
/// the next refresh.
export async function readTimetable(
  config: UntisConfig,
  session: UntisSession,
  window: { from: Date; to: Date },
): Promise<SyncedEvent[]> {
  const periods = await fetchPeriods(config, session, window);
  const out: SyncedEvent[] = [];

  for (const period of periods) {
    const event = toEvent(period);
    if (event) out.push(event);
  }
  return out;
}

/// `getTimetable`, unmapped.
///
/// Split out of [readTimetable] because [readHomework] needs the *periods* and
/// not the events: a homework is tied to its lesson by the subject and teacher
/// **ids**, and [toEvent] has by then flattened both into display text. Matching
/// "Biologie" against "BI" and "Lehrkraft: Hülss" against "Hülss (HÜL)" is the
/// kind of string work that goes wrong the first time a school spells something
/// differently.
async function fetchPeriods(
  config: UntisConfig,
  session: UntisSession,
  window: { from: Date; to: Date },
): Promise<Period[]> {
  const res = await fetchWithTimeout(
    `https://${config.server}/WebUntis/jsonrpc.do?school=${encodeURIComponent(config.school)}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Cookie": session.cookie,
      },
      body: JSON.stringify({
        id: "aporah",
        method: "getTimetable",
        jsonrpc: "2.0",
        params: {
          options: {
            element: { id: session.studentId, type: 5 },
            startDate: compact(window.from),
            endDate: compact(window.to),
            showSubstText: true,
            showInfo: true,
            showLsText: true,
            subjectFields: ["id", "name", "longname"],
            teacherFields: ["id", "name", "longname"],
            roomFields: ["id", "name"],
            klasseFields: ["id", "name"],
          },
        },
      }),
    },
  );

  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`timetable ${res.status}`);
  }

  const body = await res.json().catch(() => null);
  // -7002 "no such element" and the various "no right for" codes are the
  // school's own rights configuration, not something a refresh will fix.
  if (body?.error) throw new Error(`timetable ${body.error.code}: ${body.error.message}`);

  return Array.isArray(body?.result) ? body.result : [];
}

// ---------------------------------------------------------------------------
// Homework
// ---------------------------------------------------------------------------

/// One homework, as the app renders it.
///
/// **Dates, not instants.** A homework is due *on a day* — there is no hour to
/// get wrong and therefore no timezone to convert, which is why these stay
/// `YYYY-MM-DD` strings while a lesson becomes a UTC instant. Turning a due date
/// into midnight-somewhere is how it ends up a day early for half the year.
export interface UntisHomework {
  /// Untis's own id. Stable across refreshes, so the app can key rows on it.
  id: number;
  /// The lesson's subject short name — "MA", "BI". Occasionally empty: about a
  /// fifth of lessons come back without one, which is what [teacher] is for.
  subject: string | null;
  /// "Meyer (MYE)" — the homework payload carries the full name *and* the
  /// Kürzel, where the timetable only ever sends the Kürzel. The nicer of the
  /// two sources for anything a person reads.
  teacher: string | null;
  /// The day it was set, and the day it is due, both `YYYY-MM-DD`.
  assignedOn: string;
  dueOn: string;
  text: string;
  remark: string | null;
  /// Ticked off by the pupil **in Untis**. Their own state, not ours — we show
  /// it and never write it, so there is exactly one truth about whether the
  /// Vokabeln are learnt.
  completed: boolean;
  /// The `uid` of the lesson this is due in, when one could be found — the same
  /// `untis-<periodId>` the timetable event carries, so the app can decorate
  /// that event without repeating the match.
  ///
  /// Null whenever the due date falls outside the fortnight the school
  /// publishes, which is the common case rather than an error.
  eventUid: string | null;
}

/// How much of the caller's window the homework endpoint is actually asked for.
///
/// **A year or more comes back empty.** Not an error, not a 4xx: HTTP 200 with
/// `homeworks: []`, which is indistinguishable from a school that sets no
/// homework and is exactly how this shipped looking like it worked. Probed
/// against a live school on 2026-09-09: a 330-day range returns 21 homeworks, a
/// 365-day range returns none, with nothing else changed.
///
/// So the range is narrowed here rather than at the call site. Every caller
/// passes `syncWindow()`, which spans six months back and eighteen forward
/// because that is the right window for *appointments* — and a due date
/// eighteen months out does not exist. Thirty days back is more overdue
/// homework than any Board wants to show, six months forward covers a term, and
/// the 210-day span it adds up to sits comfortably inside the limit.
///
/// Narrowed rather than replaced: a caller asking for less than this still gets
/// less.
function homeworkWindow(window: { from: Date; to: Date }): { from: Date; to: Date } {
  const day = 86_400_000;
  const now = Date.now();
  return {
    from: new Date(Math.max(window.from.getTime(), now - 30 * day)),
    to: new Date(Math.min(window.to.getTime(), now + 180 * day)),
  };
}

/// The student's homework in a window, each tied to the lesson it is due in.
///
/// Two reads: the homework list, and the timetable it is matched against. The
/// second is the price of the `eventUid` — Untis's homework payload names a
/// `lessonId` that is in a different namespace from anything `getTimetable`
/// returns, so there is no id to join on and the match has to be made out of
/// what both sides *do* agree on: the day, the subject and the teacher.
export async function readHomework(
  config: UntisConfig,
  session: UntisSession,
  window: { from: Date; to: Date },
): Promise<UntisHomework[]> {
  const asked = homeworkWindow(window);

  const res = await fetchWithTimeout(
    `https://${config.server}/WebUntis/api/homeworks/lessons` +
      `?startDate=${compact(asked.from)}&endDate=${compact(asked.to)}`,
    { headers: { "Accept": "application/json", "Cookie": session.cookie } },
  );

  if (!res.ok) {
    await res.body?.cancel();
    throw new Error(`homework ${res.status}`);
  }

  const body = await res.json().catch(() => null);
  const data = body?.data;
  const rows: HomeworkRow[] = Array.isArray(data?.homeworks) ? data.homeworks : [];
  if (!rows.length) return [];

  // Three lookup tables the payload ships alongside the homework itself.
  const subjectOf = new Map<number, string>();
  for (const l of (data.lessons ?? []) as Array<{ id?: number; subject?: string }>) {
    if (l.id != null) subjectOf.set(l.id, (l.subject ?? "").trim());
  }
  const teacherName = new Map<number, string>();
  for (const t of (data.teachers ?? []) as Array<{ id?: number; name?: string }>) {
    if (t.id != null) teacherName.set(t.id, (t.name ?? "").trim());
  }
  // `records` is the join table: which teacher set which homework.
  const teacherOf = new Map<number, number>();
  for (const r of (data.records ?? []) as Array<{ homeworkId?: number; teacherId?: number }>) {
    if (r.homeworkId != null && r.teacherId != null) teacherOf.set(r.homeworkId, r.teacherId);
  }

  // Only fetched once there is homework to match, and only across the days the
  // homework actually falls on.
  const periods = await fetchPeriods(config, session, asked).catch(() => [] as Period[]);

  const out: UntisHomework[] = [];
  for (const row of rows) {
    if (row.id == null || !row.dueDate || !row.text?.trim()) continue;

    const teacherId = teacherOf.get(row.id) ?? null;
    const subject = subjectOf.get(row.lessonId ?? -1) || null;

    out.push({
      id: row.id,
      subject,
      teacher: teacherId == null ? null : teacherName.get(teacherId) || null,
      assignedOn: isoDate(row.date ?? row.dueDate),
      dueOn: isoDate(row.dueDate),
      text: row.text.trim(),
      remark: row.remark?.trim() || null,
      completed: row.completed === true,
      eventUid: matchLesson(periods, row.dueDate, subject, teacherId),
    });
  }
  return out;
}

interface HomeworkRow {
  id?: number;
  lessonId?: number;
  date?: number;
  dueDate?: number;
  text?: string;
  remark?: string;
  completed?: boolean;
}

/// Which lesson on [date] a homework belongs to, as an event uid.
///
/// **Subject first, teacher as the tie-break and the fallback**, which is the
/// order the data asks for rather than a preference:
///
///   * A teacher is not enough on their own. A Klassenlehrerin takes several
///     subjects, so her id can hit four of the six periods in a day where the
///     subject narrows it to the right one.
///   * The subject is not always there. Roughly a fifth of lessons come back
///     with an empty `subject`, and for those the teacher is the only thing
///     left to match on.
///   * A substituted lesson keeps its subject and swaps its teacher, so
///     matching on the teacher first would lose exactly the lessons where
///     something unusual is happening.
///
/// A Doppelstunde matches twice; the earlier period wins, because that is when
/// the homework is handed in.
function matchLesson(
  periods: Period[],
  date: number,
  subject: string | null,
  teacherId: number | null,
): string | null {
  const sameDay = periods.filter((p) => p.date === date && p.id != null);
  if (!sameDay.length) return null;

  const bySubject = subject
    ? sameDay.filter((p) => (p.su?.[0]?.name ?? "").trim() === subject)
    : [];
  const byTeacher = teacherId == null
    ? []
    : sameDay.filter((p) => (p.te ?? []).some((t) => t.id === teacherId));

  // Both agreeing is the normal case and the most certain; then the subject on
  // its own; then the teacher, for the lessons that never named a subject.
  const both = bySubject.filter((p) => byTeacher.includes(p));
  const candidates = both.length ? both : bySubject.length ? bySubject : byTeacher;
  if (!candidates.length) return null;

  const earliest = candidates.reduce((a, b) => ((a.startTime ?? 0) <= (b.startTime ?? 0) ? a : b));
  return `untis-${earliest.id}`;
}

/// `20260910` -> `"2026-09-10"`.
function isoDate(compactDate: number): string {
  const text = String(compactDate);
  return `${text.slice(0, 4)}-${text.slice(4, 6)}-${text.slice(6, 8)}`;
}

function toEvent(period: Period): SyncedEvent | null {
  if (!period.id || !period.date || period.startTime == null || period.endTime == null) {
    return null;
  }

  const startsAt = berlinInstant(period.date, period.startTime);
  const endsAt = berlinInstant(period.date, period.endTime);
  if (!startsAt || !endsAt) return null;

  const subject = first(period.su) || period.activityType || "Unterricht";
  const room = first(period.ro, "name");
  const teacher = first(period.te);

  // The status belongs in the title, because the title is all a week grid shows.
  // German, like everything else Untis sends: the subjects are "Mathematik" and
  // the teachers are Kürzel, so a translated marker would be the odd one out.
  const title = switchCode(period.code, subject);

  const notes = [
    teacher ? `Lehrkraft: ${teacher}` : null,
    first(period.kl, "name") ? `Klasse: ${first(period.kl, "name")}` : null,
    period.substText?.trim() || null,
    period.info?.trim() || null,
    period.lstext?.trim() || null,
  ].filter((line): line is string => !!line);

  return {
    // The period id is stable across refreshes and unique per lesson slot, so
    // this is the same uid tomorrow — which is what makes the read an upsert
    // rather than a fresh pile of duplicates every hour.
    uid: `untis-${period.id}`,
    title,
    notes: notes.length ? notes.join("\n") : null,
    location: room,
    startsAt,
    endsAt,
    allDay: false,
  };
}

function switchCode(code: string | undefined, subject: string): string {
  if (code === "cancelled") return `${subject} (Entfall)`;
  if (code === "irregular") return `${subject} (Vertretung)`;
  return subject;
}

function first(
  list: Array<{ name?: string; longname?: string }> | undefined,
  prefer: "name" | "longname" = "longname",
): string | null {
  const entry = list?.[0];
  if (!entry) return null;
  const value = prefer === "longname" ? entry.longname || entry.name : entry.name || entry.longname;
  return value?.trim() || null;
}

/// `20260908` — the date format both timetable endpoints want.
function compact(date: Date): number {
  return Number(
    `${date.getUTCFullYear()}` +
      `${String(date.getUTCMonth() + 1).padStart(2, "0")}` +
      `${String(date.getUTCDate()).padStart(2, "0")}`,
  );
}

/// Turns Untis's `20260908` + `1130` into an instant.
///
/// Those two numbers are a **wall clock in the school's own timezone** and carry
/// no offset at all, so reading them as UTC would put every German lesson an
/// hour early in winter and two in summer — the same trap the IServ feeds set
/// with their bare-offset TZID, and the reason this converts rather than
/// concatenating a "Z" onto the end.
function berlinInstant(date: number, time: number): string | null {
  const year = Math.floor(date / 10000);
  const month = Math.floor(date / 100) % 100;
  const day = date % 100;
  const hour = Math.floor(time / 100);
  const minute = time % 100;

  if (!year || !month || !day || hour > 23 || minute > 59) return null;

  // Read the wall clock as if it were UTC, then step back by whatever Berlin
  // was offset by at that moment. Applying the offset twice — once at the naive
  // instant, once at the corrected one — is what gets the two hours a year
  // right where the correction crosses the DST switch itself.
  const naive = Date.UTC(year, month - 1, day, hour, minute);
  const once = naive - berlinOffsetMs(new Date(naive));
  const twice = naive - berlinOffsetMs(new Date(once));
  return new Date(twice).toISOString();
}

const BERLIN = new Intl.DateTimeFormat("en-GB", {
  timeZone: "Europe/Berlin",
  hour12: false,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});

/// How far ahead of UTC Berlin was at [instant], in milliseconds.
function berlinOffsetMs(instant: Date): number {
  const parts = BERLIN.formatToParts(instant);
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? 0);
  const local = Date.UTC(
    get("year"),
    get("month") - 1,
    get("day"),
    // en-GB renders midnight as 24 rather than 00 in some ICU versions.
    get("hour") % 24,
    get("minute"),
    get("second"),
  );
  return local - Math.floor(instant.getTime() / 1000) * 1000;
}
