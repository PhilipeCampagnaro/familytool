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
  readRemoteEvents,
  ReconnectRequired,
} from "../_shared/providers.ts";
import { subscribedFeeds } from "../_shared/feeds.ts";

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
}

interface WireEvent {
  id: string;
  calendar_id: string;

  /// The provider's own identifier for this event, carried through so the app
  /// can hand it back to `calendar-write` when the user edits or deletes it.
  /// Aporah's own events have no uid — their `id` *is* the row.
  uid: string;

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

  const calendars: WireCalendar[] = [];
  const events: WireEvent[] = [];
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
      "id, family_id, provider, auth_type, external_account, display_name, config, selected_calendars, is_read_only, created_by",
    )
    .eq("family_id", membership.familyId)
    .eq("status", "active");

  for (const connection of (connections ?? []) as unknown as Connection[]) {
    try {
      const { calendars: cals, events: evts } = await readConnection(db, connection);
      calendars.push(...cals);
      events.push(...evts);
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

  return json({ calendars, events, errors });
});

async function readConnection(
  db: SupabaseClient,
  connection: Connection,
): Promise<{ calendars: WireCalendar[]; events: WireEvent[] }> {
  const window = syncWindow();
  const remote = await listRemoteCalendars(db, connection);

  // null = the user has not opened the checklist yet, so read everything. An
  // empty array means they deselected everything, which is not the same.
  const wanted = connection.selected_calendars === null
    ? remote
    : remote.filter((c) => connection.selected_calendars!.includes(c.externalId));

  const calendars: WireCalendar[] = [];
  const events: WireEvent[] = [];

  for (const cal of wanted) {
    const row = await upsertCalendar(db, connection, cal);
    calendars.push(row);
    for (const e of await readRemoteEvents(db, connection, cal, window)) {
      events.push(toWire(row.id, e));
    }
  }

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

  return { calendars, events };
}

/// A proxied event has no database row and therefore no id, but the Flutter side
/// needs a stable one for list keys and for the open-event sheet. The provider's
/// own uid plus the start time is exactly the identity the old reconcile used —
/// stable across fetches, and distinct per occurrence of a recurring series.
function toWire(
  calendarId: string,
  e: { uid: string; title: string; startsAt: string; endsAt: string; allDay: boolean; location: string | null; notes: string | null },
): WireEvent {
  return {
    id: `${calendarId}:${e.uid}:${e.startsAt}`,
    calendar_id: calendarId,
    uid: e.uid,
    title: e.title.slice(0, 300),
    starts_at: e.startsAt,
    ends_at: e.endsAt,
    all_day: e.allDay,
    location: e.location,
    notes: e.notes,
  };
}

function quote(value: string): string {
  return `"${value.replace(/"/g, '""')}"`;
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
};

async function upsertCalendar(
  db: SupabaseClient,
  connection: Connection,
  remote: RemoteCalendar,
): Promise<WireCalendar> {
  const readOnly = connection.is_read_only || remote.readOnly;

  const { data: existing } = await db
    .from("calendars")
    .select("id, name, color, is_read_only, position")
    .eq("connection_id", connection.id)
    .eq("external_id", remote.externalId)
    .maybeSingle();

  if (existing) {
    // Name follows the provider; colour, position and visibility belong to the
    // user. Overwriting those on every read is the kind of thing that makes a
    // family stop trusting a calendar.
    if (existing.name !== remote.name || existing.is_read_only !== readOnly) {
      await db
        .from("calendars")
        .update({ name: remote.name, is_read_only: readOnly })
        .eq("id", existing.id);
    }
    return {
      id: existing.id,
      name: remote.name,
      color: existing.color as number,
      is_read_only: readOnly,
      position: (existing.position as number) ?? 0,
    };
  }

  // `| 0` wraps the ARGB value into a signed 32-bit integer, which is what the
  // column is. Without it every colour with alpha 0xff overflows.
  const color = PROVIDER_COLOR[connection.provider] | 0;

  const { data: created, error } = await db
    .from("calendars")
    .insert({
      family_id: connection.family_id,
      name: remote.name,
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
    })
    .select("id, position")
    .single();

  if (error || !created) throw new Error(`calendar insert failed: ${error?.message}`);
  return {
    id: created.id,
    name: remote.name,
    color,
    is_read_only: readOnly,
    position: (created.position as number) ?? 0,
  };
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
