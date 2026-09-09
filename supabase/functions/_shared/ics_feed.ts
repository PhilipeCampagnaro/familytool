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

import { parseIcs } from "./caldav.ts";
import { fetchUntrusted } from "./net.ts";
import type { SyncedEvent } from "./calendar.ts";

/// One pasted calendar, as it is stored in `calendar_connections.config.feeds`.
///
/// [url] is the identity: it becomes the `RemoteCalendar.externalId`, so it is
/// what `selected_calendars` ticks and what `calendar_names` names, and the
/// `calendars` row keyed on (connection_id, external_id) follows it.
export interface FeedEntry {
  url: string;
  name: string;
  host: string;
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
export function feedsOf(config: Record<string, unknown>): FeedEntry[] {
  const raw = config?.feeds;
  if (!Array.isArray(raw)) return [];

  const out: FeedEntry[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const url = (entry as FeedEntry).url;
    if (typeof url !== "string" || !url.startsWith("https://")) continue;
    const name = (entry as FeedEntry).name;
    out.push({
      url,
      name: typeof name === "string" && name.trim() ? name.trim() : hostOf(url),
      host: typeof (entry as FeedEntry).host === "string" ? (entry as FeedEntry).host : hostOf(url),
      added_at: (entry as FeedEntry).added_at,
    });
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
    throw new Error("Dieser Link ist nicht mehr gültig. Bitte erstelle ihn neu.");
  }
  if (res.status === 404) throw new Error("Unter diesem Link liegt kein Kalender.");
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
    throw new Error(
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
  const ics = await fetchFeed(url);
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
export async function probeFeed(url: string): Promise<{ name: string | null; events: number }> {
  const ics = await fetchFeed(url);
  const now = new Date();
  const from = new Date(now.getTime() - 400 * 86_400_000);
  const to = new Date(now.getTime() + 400 * 86_400_000);
  return { name: feedName(ics), events: parseIcs(ics, from, to).length };
}
