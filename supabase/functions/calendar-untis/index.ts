/// Connect a WebUntis timetable with the pupil's app secret.
///
///   POST { action: 'check', qr }                     -> { ok, student, school, lessons }
///   POST { action: 'check', server, school, user, secret }
///   POST { action: 'add',   ...same..., pupil, member_id }
///                                                    -> { connection_id, external_id, name }
///
/// The credential comes off the QR code under Profil → Freigaben → "Zugriff
/// über Untis Mobile", or is typed from the four lines printed beneath it. It is
/// not a password: it is the TOTP seed Untis Mobile uses, revocable on its own
/// and worth nothing outside webuntis.com.
///
/// Why a function rather than a client insert, for the third time in this
/// codebase and for the same two reasons:
///
///   1. `authenticated` holds no INSERT grant on `calendar_connections` and no
///      access at all to `calendar_connection_secrets`. A credential must never
///      be written by a client that could then read it back.
///   2. Logging in *is* the connect. A wrong key, a revoked one, a school that
///      turned mobile access off — each fails here, before a row exists, so
///      "verbunden" keeps meaning "we reached it just now".
///
/// Function secrets: CALENDAR_SECRET_KEY.

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import { seal } from "../_shared/secrets.ts";
import { membershipOf } from "../_shared/calendar.ts";
import {
  login,
  normaliseConfig,
  parseUntisQr,
  readTimetable,
  UNTIS_TIMETABLE,
  type UntisConfig,
} from "../_shared/untis.ts";

/// How far ahead the check looks when counting lessons for "24 Stunden
/// gefunden". Schools publish a fortnight or so; asking for much more says
/// nothing extra and costs a bigger response.
const PROBE_DAYS = 14;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  let body: {
    action?: string;
    qr?: string;
    server?: string;
    school?: string;
    user?: string;
    secret?: string;
    /// The child whose timetable this is — what the household typed, not what
    /// Untis calls them. The calendar's name and the person chips both come out
    /// of it; see the add branch.
    pupil?: string;
    /// That child's user id, when they are a member of the household. Verified
    /// against the roster before it is stored.
    member_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return fail("Ungültige Anfrage.");
  }

  const action = body.action ?? "add";
  if (action !== "check" && action !== "add") return fail("Unbekannte Aktion.");

  // Scanned or typed, both end up as the same four fields. A QR code that is
  // some *other* app's is the common mis-scan, and it is worth its own line —
  // "das ist kein WebUntis-Code" is actionable where "ungültig" is not.
  const config = body.qr?.trim()
    ? parseUntisQr(body.qr)
    : normaliseConfig({
      server: body.server,
      school: body.school,
      user: body.user,
      secret: body.secret,
    });

  if (!config) {
    return fail(
      body.qr?.trim()
        ? "Dieser QR-Code gehört nicht zu WebUntis."
        : "Bitte Schule, Benutzer und Schlüssel angeben.",
    );
  }

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);
  if (membership.role === "kid") return fail("Kinder können keine Kalender verbinden.", 403);

  // The login is the check, and it runs on `add` too rather than trusting the
  // one the check step already did: the sheet may have sat open for a while,
  // and a key revoked in between must not leave a connection behind that has
  // never worked.
  let session;
  let lessons: number;
  try {
    session = await login(config);
    lessons = await countLessons(config, session);
  } catch (e) {
    // These messages are written German and user-facing at the point they are
    // thrown, for the same reason the CalDAV ones are.
    return fail((e as Error).message, 400);
  }

  if (action === "check") {
    return json({
      ok: true,
      student: session.displayName,
      school: session.schoolName,
      lessons,
    });
  }

  // **The household names the child, not the calendar.**
  //
  // The setup step used to ask for a calendar name and get "Stundenplan Alice"
  // — a string the calendar could show and nothing else could reason about.
  // Asking whose timetable it is instead gets "Alice", out of which the calendar
  // name falls for free *and* which the filter rows on Kalender and Board are
  // built from. One field, one answer, two uses. A household with four children
  // at school is the case this exists for: four accounts that know which child
  // they belong to are four faces in a row, where four calendar names are four
  // strings nobody can group by.
  const pupil = body.pupil?.trim().slice(0, 60) ?? "";
  const name = pupil ? `Stundenplan ${pupil}` : "Stundenplan";

  // The child as a *member* where they have an account, and as a plain name
  // where they do not — which is most of them, since members join by e-mail
  // invitation and a ten-year-old rarely has one. Checked against the roster
  // rather than trusted: a client that sent somebody else's user id would
  // otherwise file this child's timetable under them.
  let ownerMemberId: string | null = null;
  if (typeof body.member_id === "string" && body.member_id) {
    const { data: member } = await db
      .from("family_members")
      .select("user_id")
      .eq("family_id", membership.familyId)
      .eq("user_id", body.member_id)
      .maybeSingle();
    ownerMemberId = member ? body.member_id : null;
  }

  // Sealed before the connection row is written, never after. seal() throws
  // when CALENDAR_SECRET_KEY is missing, and doing it second leaves exactly the
  // row this whole flow exists to prevent: one the settings screen calls
  // "verbunden" that holds no credential and can never sync.
  let sealedSecret: string;
  try {
    sealedSecret = await seal(config.secret);
  } catch (e) {
    console.error("untis seal failed", (e as Error).message);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  // school/user, not the pupil's name: two children at one school are two
  // logins and must be two connections, and a name is not unique enough to
  // carry that weight.
  const account = `${config.school}/${config.user}`;

  const { data: connection, error } = await db
    .from("calendar_connections")
    .upsert({
      family_id: membership.familyId,
      provider: "webuntis",
      auth_type: "secret",
      external_account: account,
      display_name: `WebUntis · ${session.displayName}`,
      // Everything here is printed in plain text under the QR code and answers
      // nothing without the key, which is why it lives in the household-readable
      // column and the key does not.
      config: {
        server: config.server,
        school: config.school,
        student_id: session.studentId,
        student_name: session.displayName,
        school_name: session.schoolName,
      },
      // A pupil has one timetable. There is nothing to enumerate and therefore
      // nothing to pick, so the choice is made here rather than shown.
      selected_calendars: [UNTIS_TIMETABLE],
      calendar_names: { [UNTIS_TIMETABLE]: name },
      // Somebody else's system of record. Writing to it is not a feature we are
      // missing; it is one we refuse.
      is_read_only: true,
      status: "active",
      status_detail: null,
      created_by: uid,
      // Whose day this is. Not who may see it — every calendar in Aporah
      // belongs to the whole household, and this one is read by everybody
      // exactly as before.
      owner_member_id: ownerMemberId,
      owner_label: ownerMemberId ? null : (pupil || null),
    }, { onConflict: "family_id,provider,external_account" })
    .select("id")
    .single();

  if (error || !connection) {
    console.error("untis connection upsert failed", error?.message);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  const { error: secretError } = await db
    .from("calendar_connection_secrets")
    .upsert({
      connection_id: connection.id,
      app_secret: sealedSecret,
      updated_at: new Date().toISOString(),
    }, { onConflict: "connection_id" });

  if (secretError) {
    console.error("untis secret upsert failed", secretError.message);
    return fail("Die Verbindung konnte nicht gespeichert werden.", 500);
  }

  // No `studentId`. It is the school's own identifier for a child, and a
  // function log has a retention we do not set and cannot purge on an Art. 17
  // request. The school stays — it is what tells us "this school's WebUntis is
  // refusing everyone" rather than "one family mistyped something" — and the
  // family id is our own opaque key, which is what a support request arrives
  // with anyway.
  console.log(`connected webuntis ${config.school} for family ${membership.familyId}`);

  return json({ connection_id: connection.id, external_id: UNTIS_TIMETABLE, name, lessons });
});

/// How many lessons the next fortnight holds — the number the naming step
/// shows, and the proof that this account has a timetable at all rather than
/// merely a login that works.
async function countLessons(
  config: UntisConfig,
  session: Awaited<ReturnType<typeof login>>,
): Promise<number> {
  const from = new Date();
  from.setUTCHours(0, 0, 0, 0);
  const to = new Date(from.getTime() + PROBE_DAYS * 86_400_000);
  const events = await readTimetable(config, session, { from, to });
  return events.length;
}
