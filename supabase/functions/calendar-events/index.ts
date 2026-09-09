/// Read the household's external calendars — without storing any of them.
///
///   POST { }  -> { calendars: [...], events: [...], errors: [...] }
///
/// This replaces the old calendar-sync, and the difference is the entire point:
/// sync pulled every connected account into public.events and left it there.
/// This one asks the provider, hands the answer straight back to the app, and
/// keeps nothing. The offline copy lives in the device's cache, where it is
/// covered by the phone's own encryption and disappears when the app does.
///
/// What that buys, concretely: Aporah's database contains no doctor's
/// appointments, no interviews, no therapy sessions. There is nothing to leak in
/// a breach, nothing to hand over, nothing to delete on request beyond a token.
/// For a German family app that is not a nice-to-have.
///
/// Two things are still stored, deliberately:
///
///   * `public.calendars` rows for personal accounts — a calendar's *name*,
///     colour, position and whether it is selected. Household settings, not
///     content, and they have to survive a reinstall.
///   * `public.public_feeds` — Ferien and Abfall, which are municipal data
///     rather than personal data, and are shared by every household that wants
///     the same Bundesland or the same street. See _shared/feeds.ts.
///
/// Function secrets: CALENDAR_SECRET_KEY (+ the OAuth client secrets, for the
/// token refresh that happens here).

import { callerId, corsHeaders, fail, json, serviceClient } from "../_shared/http.ts";
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { membershipOf, type Provider, type RemoteCalendar, setStatus, syncWindow } from "../_shared/calendar.ts";
import {
  type Connection,
  listRemoteCalendars,
  readConnectionHomework,
  readRemoteEvents,
  ReconnectRequired,
} from "../_shared/providers.ts";
import { subscribedFeeds } from "../_shared/feeds.ts";
import { redact } from "../_shared/ics_feed.ts";

/// What the Flutter side reads. Snake_case because it lands in the same
/// CalendarSource.fromMap / CalendarEvent.fromMap the PostgREST rows do — one
/// parser, whether a calendar came from the database or from here.
interface WireCalendar {
  id: string;
  name: string;
  color: number;
  is_read_only: boolean;
  position: number;

  /// `'ferien'` / `'abfall'` for a public feed, absent for a personal account's
  /// calendar. Deliberately **not** `provider`: feeds stopped being a provider
  /// value when they moved to public_feeds, and putting one back on the wire
  /// would invite somebody to write it to `calendars.provider`.
  ///
  /// The app uses it to colour each Abfuhrtermin by its bin rather than paint a
  /// month of identical brown dots.
  feed_kind?: string;

  /// **Whose day this calendar belongs to** — the chip it appears under.
  ///
  /// This used to be the connection, so the row was one chip per account. It is
  /// the *person* now, and the difference is what makes the row usable in the
  /// households this app is for: four children at school is a dozen calendars
  /// and a dozen chips, where the same twelve as six faces is a row you can
  /// read. A parent with a work and a private calendar is one chip; so is a
  /// child with a Stundenplan and a Klausurplan.
  ///
  /// `'member:<uuid>'` for somebody with an account, `'person:<name>'` for a
  /// child who has none — most of them, since members join by e-mail invitation
  /// — and `'family'` for the shared calendars and the public feeds. See the
  /// migration for why both spellings of a person are needed.
  ///
  /// Emphatically **not** visibility: everyone in the household sees every
  /// calendar, and filtering to Alice still shows her the family dinner.
  group_id?: string;
  group_name?: string;

  /// The member behind a `'member:'` group, so the app can put their face on
  /// the chip from the roster it already holds. Absent for the other two kinds,
  /// which fall back to initials on a tone circle.
  owner_member_id?: string;
}

/// One homework, alongside the events rather than among them.
///
/// **Homework is not an event and must never become one.** A due date is not an
/// appointment: it has no time, it does not occupy the day, and twenty of them
/// in a week grid would bury the lessons they belong to. What the app does with
/// these is decorate the lesson named by [event_uid] and fill a list on Board —
/// both of which are views of the same fact, neither of which is a calendar
/// entry.
interface WireHomework {
  /// Stable across refreshes: the calendar plus Untis's own homework id.
  id: string;
  calendar_id: string;

  /// The lesson it is due in, as that event's `uid` — or null when the due date
  /// falls outside the fortnight most schools publish, which is roughly half of
  /// them at any moment. A null is a homework with no lesson on screen to
  /// decorate, not a failed match.
  event_uid: string | null;

  subject: string | null;
  teacher: string | null;
  /// `YYYY-MM-DD`. A date, with no time and no zone — see UntisHomework.
  due_on: string;
  text: string;
  remark: string | null;
  /// Ticked off by the pupil in Untis. Read-only, always.
  completed: boolean;
}

interface WireEvent {
  id: string;
  calendar_id: string;

  /// The provider's own identifier for this event, carried through so the app
  /// can hand it back to `calendar-write` when the user edits or deletes it.
  /// Aporah's own events have no uid — their `id` *is* the row.
  uid: string;

  /// The series this occurrence belongs to, or null for a one-off. The app
  /// shows "Wiederholt sich" off its presence and hands it back to
  /// `calendar-write` when the user changes or deletes the whole series.
  series_uid: string | null;

  title: string;
  starts_at: string;
  ends_at: string;
  all_day: boolean;
  location: string | null;
  notes: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const uid = await callerId(req);
  if (!uid) return fail("Nicht angemeldet.", 401);

  const db = serviceClient();
  const membership = await membershipOf(db, uid);
  if (!membership) return fail("Kein Haushalt gefunden.", 403);

  // Who the household's chips are, resolved once. Every calendar below is
  // labelled from this, so the row says "Papa" and "Alice" rather than
  // repeating a uuid the app would then have to look up itself.
  const owners = await ownerDirectory(db, membership.familyId);

  const calendars: WireCalendar[] = [];
  const events: WireEvent[] = [];
  const homework: WireHomework[] = [];
  const errors: Array<{ connection_id: string; error: string }> = [];

  // ---- Public feeds: Ferien, Abfall -----------------------------------------
  // First, and never allowed to fail the request: these are cached server-side
  // and cheap, and a family should still see their bin days when Google is down.
  try {
    for (const feed of await subscribedFeeds(db, membership.familyId)) {
      calendars.push({
        id: feed.id,
        name: feed.displayName,
        color: feed.displayColor | 0,
        is_read_only: true,
        position: feed.position,
        feed_kind: feed.kind,
        // Ferien and Abfall belong to everybody, so they sit under the family
        // chip rather than each taking a slot of their own in the row. They are
        // still separate calendars inside it, tickable one at a time.
        group_id: FAMILY_GROUP,
        group_name: owners.familyName,
      });
      for (const e of feed.events) events.push(toWire(feed.id, e));
    }
  } catch (e) {
    console.error(`feeds failed: ${(e as Error).message}`);
  }

  // ---- Personal accounts: Google, Outlook, iCloud, IServ ---------------------
  // The family filter is the whole tenant boundary — service_role sees every
  // row, so this scoping is what stops one household reading another's.
  const { data: connections } = await db
    .from("calendar_connections")
    .select(
      "id, family_id, provider, auth_type, external_account, display_name, config, selected_calendars, calendar_names, calendar_owners, is_read_only, created_by, owner_member_id, owner_label",
    )
    .eq("family_id", membership.familyId)
    .eq("status", "active");

  for (const connection of (connections ?? []) as unknown as Connection[]) {
    try {
      const { calendars: cals, events: evts, homework: hw } = await readConnection(db, connection, owners);
      calendars.push(...cals);
      events.push(...evts);
      homework.push(...hw);
    } catch (e) {
      const reconnect = e instanceof ReconnectRequired;
      // The message is rendered in the app, so it is German and says what to do
      // — never the provider's raw error, which can echo a token back.
      await setStatus(
        db,
        connection.id,
        reconnect ? "reconnect_required" : "error",
        reconnect
          ? "Die Verbindung ist abgelaufen. Bitte erneut verbinden."
          : "Der Kalender konnte nicht geladen werden.",
      );
      console.error(`read failed for ${connection.id}: ${(e as Error).message}`);
      errors.push({
        connection_id: connection.id,
        error: reconnect ? "reconnect_required" : "read_failed",
      });
    }
  }

  return json({ calendars, events, homework, errors });
});

async function readConnection(
  db: SupabaseClient,
  connection: Connection,
  owners: OwnerDirectory,
): Promise<{ calendars: WireCalendar[]; events: WireEvent[]; homework: WireHomework[] }> {
  const window = syncWindow();
  const remote = await listRemoteCalendars(db, connection);

  // null = the user has not opened the checklist yet, so read everything. An
  // empty array means they deselected everything, which is not the same.
  const wanted = connection.selected_calendars === null
    ? remote
    : remote.filter((c) => connection.selected_calendars!.includes(c.externalId));

  const calendars: WireCalendar[] = [];
  const events: WireEvent[] = [];

  // One calendar failing must not take the rest of the account with it. That
  // used to be academic — an OAuth token is good for every calendar it lists,
  // so they failed together or not at all — but a link connection holds several
  // independently revocable URLs, and a family that regenerates one IServ link
  // should not lose the other two while they are at it.
  //
  // A failed calendar is left out of the response rather than returned empty:
  // it reappears the moment it answers again, and an empty calendar that is
  // actually broken is the more misleading of the two. If *every* one failed,
  // the throw stands and the connection goes to `error` — see the caller.
  let failed = 0;
  let firstError: unknown;

  for (const [index, cal] of wanted.entries()) {
    try {
      const read = await readRemoteEvents(db, connection, cal, window);
      // After the read, so a calendar that cannot be reached does not get a row
      // written for it on the way past.
      const row = await upsertCalendar(db, connection, cal, index, owners);
      calendars.push(row);
      for (const e of read) events.push(toWire(row.id, e));
    } catch (e) {
      failed++;
      firstError ??= e;
      console.error(`calendar ${label(cal.externalId)} failed: ${(e as Error).message}`);
    }
  }

  if (failed && failed === wanted.length) throw firstError;

  // A calendar the user has since deselected, or that the provider no longer
  // offers, stops being ours to keep the settings for.
  const keep = wanted.map((c) => c.externalId);
  let stale = db.from("calendars").delete().eq("connection_id", connection.id);
  if (keep.length) stale = stale.not("external_id", "in", `(${keep.map(quote).join(",")})`);
  await stale;

  await db
    .from("calendar_connections")
    .update({ status: "active", status_detail: null, last_synced_at: new Date().toISOString() })
    .eq("id", connection.id);

  // After the calendars, and hung off the first of them: homework belongs to
  // the account's one timetable, and reading it is pointless if that calendar
  // did not come back. Non-fatal by construction — see readConnectionHomework.
  const homework: WireHomework[] = [];
  if (calendars.length) {
    const timetable = calendars[0].id;
    for (const h of await readConnectionHomework(db, connection, window)) {
      homework.push({
        id: `${timetable}:hw:${h.id}`,
        calendar_id: timetable,
        event_uid: h.eventUid,
        subject: h.subject,
        teacher: h.teacher,
        due_on: h.dueOn,
        text: h.text.slice(0, MAX_NOTES),
        remark: h.remark ? h.remark.slice(0, 300) : null,
        completed: h.completed,
      });
    }
  }

  return { calendars, events, homework };
}

/// A proxied event has no database row and therefore no id, but the Flutter side
/// needs a stable one for list keys and for the open-event sheet. The provider's
/// own uid plus the start time is exactly the identity the old reconcile used —
/// stable across fetches, and distinct per occurrence of a recurring series.
function toWire(
  calendarId: string,
  e: {
    uid: string;
    seriesUid?: string | null;
    title: string;
    startsAt: string;
    endsAt: string;
    allDay: boolean;
    location: string | null;
    notes: string | null;
  },
): WireEvent {
  return {
    id: `${calendarId}:${e.uid}:${e.startsAt}`,
    calendar_id: calendarId,
    uid: e.uid,
    series_uid: e.seriesUid ?? null,
    title: e.title.slice(0, 300),
    starts_at: e.startsAt,
    ends_at: e.endsAt,
    all_day: e.allDay,
    location: e.location,
    notes: e.notes ? e.notes.slice(0, MAX_NOTES) : e.notes,
  };
}

/// How much of an event's description travels to the phone.
///
/// `title` has been capped since this function was written; `notes` was not, and
/// it is the field that actually gets long. Google hands over the raw
/// `description`, which for anything with a Meet link or a corporate invite
/// template is routinely one to three kilobytes of boilerplate and HTML — per
/// event, on every refresh, for a window spanning years. On a household with one
/// work Google calendar in it, notes was the largest single thing in the
/// response by a wide margin, and none of it is on screen until somebody opens
/// that one event's detail sheet.
///
/// 2000 characters is past the length of any note a person types by hand and
/// well short of a generated invite footer. Outlook needed no cap and still
/// does not: Graph's `bodyPreview` is already capped at 255 upstream.
const MAX_NOTES = 2000;

function quote(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
}

/// A calendar's external id, safe to write to the log.
///
/// For Google and Outlook that id is an opaque handle and goes through as-is.
/// For a link connection it **is** the tokenised ICS URL — logging it would put
/// a working school-calendar credential into the function logs, where it long
/// outlives the error it was meant to explain. `redact` keeps the host and six
/// characters of the token, which is enough to tell two feeds of the same school
/// apart and not enough to fetch either.
///
/// The old `slice(0, 60)` only ever truncated it, which happened to cut most
/// IServ URLs mid-token and was mistaken for a redaction.
function label(externalId: string): string {
  return /^https?:\/\//i.test(externalId) ? redact(externalId) : externalId.slice(0, 60);
}

// ---------------------------------------------------------------------------
// Who a calendar belongs to
// ---------------------------------------------------------------------------

/// The chip everything shared sits under: the household itself.
const FAMILY_GROUP = "family";

/// The household's names, for labelling the chip row.
interface OwnerDirectory {
  familyName: string;
  /// user id -> display name, for everybody in the household.
  members: Map<string, string>;
}

/// One read of the roster per request, rather than one per calendar.
///
/// A failure here is survivable and deliberately survived: without names every
/// calendar falls back to the family chip, which is the row this app had before
/// people were in it. Losing a household's calendars because a display name
/// could not be read would be the wrong trade by a wide margin.
async function ownerDirectory(db: SupabaseClient, familyId: string): Promise<OwnerDirectory> {
  const fallback = { familyName: "Familie", members: new Map<string, string>() };
  try {
    const [family, members] = await Promise.all([
      db.from("families").select("name").eq("id", familyId).maybeSingle(),
      db.from("family_members").select("user_id, profiles(display_name)").eq("family_id", familyId),
    ]);

    const names = new Map<string, string>();
    for (const row of (members.data ?? []) as Array<{ user_id: string; profiles?: { display_name?: string } | null }>) {
      const name = row.profiles?.display_name?.trim();
      if (name) names.set(row.user_id, name);
    }

    return {
      familyName: (family.data?.name as string | undefined)?.trim() || fallback.familyName,
      members: names,
    };
  } catch (e) {
    console.error(`owner directory failed: ${(e as Error).message}`);
    return fallback;
  }
}

/// Which chip a calendar belongs under, and what that chip is called.
///
/// The three cases are the migration's three, in the order they take precedence:
/// a member with an account, a person without one, and — when neither is set —
/// the household. A member id we cannot put a name to is treated as no member at
/// all rather than shown as a uuid: somebody removed from the household leaves
/// their calendars behind, and those belong to the family now.
function groupFor(
  ownerMemberId: string | null | undefined,
  ownerLabel: string | null | undefined,
  owners: OwnerDirectory,
): { group_id: string; group_name: string; owner_member_id?: string } {
  if (ownerMemberId) {
    const name = owners.members.get(ownerMemberId);
    if (name) {
      return { group_id: `member:${ownerMemberId}`, group_name: name, owner_member_id: ownerMemberId };
    }
  }

  const label = ownerLabel?.trim();
  if (label) return { group_id: `person:${label.toLowerCase()}`, group_name: label };

  return { group_id: FAMILY_GROUP, group_name: owners.familyName };
}

// ---------------------------------------------------------------------------
// Calendar metadata
// ---------------------------------------------------------------------------

/// Default ARGB per provider. Only used the first time a calendar appears —
/// recolouring one in the app must survive the next read, so the update below
/// never touches `color`.
const PROVIDER_COLOR: Record<Provider, number> = {
  google: 0xff4285f4,
  outlook: 0xff0078d4,
  icloud: 0xff8e8e93,
  iserv: 0xff2e7d32,
  webuntis: 0xffe8590c,
};

/// A calendar's default colour: the provider's, shifted a little per position
/// inside its account.
///
/// One hue per account is what makes the grouped chips legible — every dot on
/// Alice's three IServ calendars reads as "school", and the shade says which of
/// the three. Painting a whole account in one flat colour instead would make a
/// month of Aufgaben and Klausuren indistinguishable, which is exactly the
/// question a Klausurplan exists to answer.
///
/// Only ever the *default*: recolouring a calendar in the app must survive the
/// next read, so the update path below never touches `color`.
function defaultColor(provider: Provider, index: number): number {
  const base = PROVIDER_COLOR[provider];
  if (index <= 0) return base | 0;

  // How far towards white each successive calendar sits. The steps shrink as
  // they go, because an even ramp cannot do both jobs at once: the gap between
  // an account's first two calendars has to be obvious at the size of a 9pt
  // dot — which is all most households will ever have — while the fifth still
  // has to be a colour rather than a pale wash on a white sheet. A flat 14%
  // step satisfied the second and lost the first: IServ green at one step was
  // #4b8f4f against #2e7d32, a difference you had to be told about to see.
  const STEPS = [0, 0.26, 0.44, 0.58, 0.7];
  const t = STEPS[Math.min(index, STEPS.length - 1)];
  const mix = (channel: number) => Math.round(channel + (255 - channel) * t);

  const r = mix((base >> 16) & 0xff);
  const g = mix((base >> 8) & 0xff);
  const b = mix(base & 0xff);
  return ((0xff << 24) | (r << 16) | (g << 8) | b) | 0;
}

async function upsertCalendar(
  db: SupabaseClient,
  connection: Connection,
  remote: RemoteCalendar,
  index: number,
  owners: OwnerDirectory,
): Promise<WireCalendar> {
  const readOnly = connection.is_read_only || remote.readOnly;

  // What the household called this calendar when it picked it, falling back to
  // what the provider calls it. The two are not in competition: the name lives
  // on the connection because it is chosen before any `calendars` row exists,
  // and this is the one place it is carried across — so Kalender's chips and the
  // Settings list say the same word without the app merging two sources.
  const chosen = connection.calendar_names?.[remote.externalId]?.trim();
  const name = chosen && chosen.length ? chosen : remote.name;

  const { data: existing } = await db
    .from("calendars")
    .select("id, name, color, is_read_only, position, owner_member_id, owner_label")
    .eq("connection_id", connection.id)
    .eq("external_id", remote.externalId)
    .maybeSingle();

  if (existing) {
    // Whose calendar this is: the household's own per-calendar choice where
    // they have made one, and otherwise whatever the row already says. The
    // second half is what keeps an edit: a household that moved the shared
    // calendar off Papa and onto the family did that once, and re-reading the
    // account must not undo it every hour.
    const chosen = chosenOwner(connection, remote.externalId);
    const ownerMemberId = chosen ? chosen.member_id : (existing.owner_member_id as string | null);
    const ownerLabel = chosen ? chosen.label : (existing.owner_label as string | null);

    // Name follows the household's own choice, and the provider's only where
    // there isn't one; colour, position and visibility belong to the user.
    // Overwriting those on every read is the kind of thing that makes a family
    // stop trusting a calendar.
    const patch: Record<string, unknown> = {};
    if (existing.name !== name) patch.name = name;
    if (existing.is_read_only !== readOnly) patch.is_read_only = readOnly;
    if (ownerMemberId !== (existing.owner_member_id as string | null)) patch.owner_member_id = ownerMemberId;
    if (ownerLabel !== (existing.owner_label as string | null)) patch.owner_label = ownerLabel;
    if (Object.keys(patch).length) await db.from("calendars").update(patch).eq("id", existing.id);

    return {
      id: existing.id,
      name,
      color: existing.color as number,
      is_read_only: readOnly,
      position: (existing.position as number) ?? 0,
      ...groupFor(ownerMemberId, ownerLabel, owners),
    };
  }

  const owner = chosenOwner(connection, remote.externalId) ?? {
    member_id: connection.owner_member_id ?? null,
    label: connection.owner_label ?? null,
  };

  // `| 0` wraps the ARGB value into a signed 32-bit integer, which is what the
  // column is. Without it every colour with alpha 0xff overflows.
  const color = defaultColor(connection.provider, index);

  const { data: created, error } = await db
    .from("calendars")
    .insert({
      family_id: connection.family_id,
      name,
      provider: connection.provider,
      color,
      is_read_only: readOnly,
      external_id: remote.externalId,
      connection_id: connection.id,
      // A connected calendar belongs to whoever connected the account, and
      // lands family-visible: it is the household's calendar, and hiding it by
      // default would just look broken.
      owner_id: connection.created_by ?? await anyAdmin(db, connection.family_id),
      visibility: "family",
      // Whose day it is, seeded from the account and editable per calendar
      // afterwards. For a school connection this is the child the QR code was
      // scanned for, so their timetable is theirs without anybody opening a
      // settings screen. Not visibility — see the migration.
      owner_member_id: owner.member_id,
      owner_label: owner.label,
    })
    .select("id, position")
    .single();

  if (error || !created) throw new Error(`calendar insert failed: ${error?.message}`);
  return {
    id: created.id,
    name,
    color,
    is_read_only: readOnly,
    position: (created.position as number) ?? 0,
    ...groupFor(owner.member_id, owner.label, owners),
  };
}

/// The household's explicit choice for one calendar, or null when they have not
/// made one and the account's default stands.
///
/// `calendar_connections.calendar_owners` maps the provider's own calendar id to
/// one of three strings, with `"*"` standing for every calendar on the account —
/// the whole-connection row in Settings, which is what a feed and a
/// single-calendar account are shown as.
///
/// Client-written, so nothing here is trusted: an unknown member id resolves to
/// no member at all in `groupFor`, and a label is trimmed to the 60 characters
/// the column's check constraint accepts rather than left to raise.
function chosenOwner(
  connection: Connection,
  externalId: string,
): { member_id: string | null; label: string | null } | null {
  const map = connection.calendar_owners;
  if (!map || typeof map !== "object") return null;

  const raw = map[externalId] ?? map["*"];
  if (typeof raw !== "string" || !raw.length) return null;

  if (raw === FAMILY_GROUP) return { member_id: null, label: null };
  if (raw.startsWith("member:")) {
    const id = raw.slice("member:".length).trim();
    return id ? { member_id: id, label: null } : null;
  }
  if (raw.startsWith("person:")) {
    const label = raw.slice("person:".length).trim().slice(0, 60);
    return label ? { member_id: null, label } : null;
  }
  return null;
}

/// calendars.owner_id is not null, but a connection's created_by goes null if
/// that account is deleted. The household's first admin inherits the calendar,
/// mirroring what reassign_content_on_member_removal does for everything else.
async function anyAdmin(db: SupabaseClient, familyId: string): Promise<string> {
  const { data } = await db
    .from("family_members")
    .select("user_id")
    .eq("family_id", familyId)
    .eq("role", "admin")
    .order("joined_at")
    .limit(1)
    .single();

  if (!data) throw new Error("no admin to own the calendar");
  return data.user_id;
}
