/// A small CalDAV client — enough of RFC 4791 for iCloud and IServ, which is the
/// same protocol twice and therefore one module.
///
/// Three calls make up the whole thing:
///
///   discover()   PROPFIND current-user-principal -> PROPFIND calendar-home-set
///   collections() PROPFIND Depth:1 on the home, keeping VEVENT collections
///   readEvents()  REPORT calendar-query with a time-range, then parse the ICS
///
/// Credentials travel as HTTP Basic and never leave the server. Two details that
/// look like superstition and are not: iCloud's partition hosts reject requests
/// without a User-Agent (Deno's fetch sends none), and iCloud wraps calendar-data
/// in CDATA while everyone else XML-escapes it inline.

import ICAL from "npm:ical.js@2";
import { fetchUntrusted } from "./net.ts";

export interface Collection {
  url: string;
  name: string;
  readOnly: boolean;
}

export interface ParsedEvent {
  uid: string;
  title: string;
  notes: string | null;
  location: string | null;
  startsAt: string;
  endsAt: string;
  allDay: boolean;
  href: string | null;
  etag: string | null;
}

const USER_AGENT = "Aporah/1.0 (CalDAV)";

const PROVIDER_BASE: Record<string, string> = {
  icloud: "https://caldav.icloud.com",
};

const PROP_PRINCIPAL =
  `<d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>`;

const PROP_HOME =
  `<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` +
  `<d:prop><c:calendar-home-set/></d:prop></d:propfind>`;

const PROP_COLLECTIONS =
  `<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` +
  `<d:prop><d:resourcetype/><d:displayname/><d:current-user-privilege-set/>` +
  `<c:supported-calendar-component-set/></d:prop></d:propfind>`;

function basic(user: string, password: string): string {
  return "Basic " + btoa(`${user}:${password}`);
}

/// Server URL for a provider: fixed for iCloud, user-supplied for IServ (already
/// SSRF-checked by the caller before it gets here).
export function baseUrl(provider: string, server: string): string {
  const base = (PROVIDER_BASE[provider] || server || "").trim().replace(/\/+$/, "");
  if (!base) throw new Error("Es fehlt die Serveradresse.");
  return base;
}

async function propfind(
  url: string,
  user: string,
  password: string,
  body: string,
  depth: "0" | "1",
): Promise<{ status: number; xml: string; finalUrl: string }> {
  const res = await fetchUntrusted(url, {
    method: "PROPFIND",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "application/xml; charset=utf-8",
      "User-Agent": USER_AGENT,
      Depth: depth,
    },
    body,
  });
  return { status: res.status, xml: await res.text(), finalUrl: res.url || url };
}

// WebDAV responses come back with whatever namespace prefix the server likes
// (d:, D:, none), so every match below is prefix-agnostic. Parsing this with a
// real XML parser was tried in the old app and abandoned: the payload we need is
// an opaque iCalendar blob inside a text node, and the DOM added nothing.

function tagContent(xml: string, tag: string): string | null {
  const re = new RegExp(`<(?:[\\w-]+:)?${tag}[^>]*>([\\s\\S]*?)</(?:[\\w-]+:)?${tag}>`, "i");
  return xml.match(re)?.[1] ?? null;
}

function firstHref(xml: string): string | null {
  const inner = tagContent(xml, "href");
  return inner ? decodeXml(inner.trim()) : null;
}

function decodeXml(s: string): string {
  return s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function resolve(href: string, base: string): string {
  try {
    return new URL(href, base).toString();
  } catch {
    return href;
  }
}

function responses(xml: string): string[] {
  return xml.split(/<(?:[\w-]+:)?response[\s>]/i).slice(1);
}

/// The account's calendar-home-set URL. Doubles as credential validation: this
/// is what a connect flow calls to find out whether the password works.
export async function discover(
  provider: string,
  server: string,
  user: string,
  password: string,
): Promise<string> {
  const base = baseUrl(provider, server);

  let principal: string | null = null;
  let from = base;

  // Some servers answer at the root, some only under /.well-known/caldav
  // (RFC 6764). IServ instances vary by version, which is why this is a loop
  // rather than a constant — nobody should ever have to paste a DAV path.
  for (const url of [`${base}/`, `${base}/.well-known/caldav`]) {
    const res = await propfind(url, user, password, PROP_PRINCIPAL, "0");
    if (res.status === 401) throw new Error("Benutzername oder Passwort ist falsch.");
    if (res.status < 200 || res.status >= 300) continue;

    const block = tagContent(res.xml, "current-user-principal");
    const href = block ? firstHref(block) : firstHref(res.xml);
    if (href) {
      principal = resolve(href, res.finalUrl);
      from = res.finalUrl;
      break;
    }
  }

  if (!principal) throw new Error("Für dieses Konto wurde kein Kalender gefunden.");

  const home = await propfind(principal, user, password, PROP_HOME, "0");
  if (home.status === 401) throw new Error("Benutzername oder Passwort ist falsch.");

  const block = tagContent(home.xml, "calendar-home-set");
  const href = block ? firstHref(block) : null;
  if (!href) throw new Error("Für dieses Konto wurde kein Kalender gefunden.");

  return resolve(href, home.finalUrl || from);
}

async function collectionsAt(url: string, user: string, password: string): Promise<Collection[]> {
  const res = await propfind(url, user, password, PROP_COLLECTIONS, "1");
  if (res.status === 401) throw new Error("Benutzername oder Passwort ist falsch.");
  if (res.status < 200 || res.status >= 300) {
    // A non-multistatus answer is a failure, not "this account has no
    // calendars". Reporting it as the latter is how a broken server used to
    // present as an empty, silently useless connection.
    console.error(`caldav PROPFIND ${res.status}`);
    throw new Error(`Die Kalenderliste konnte nicht geladen werden (HTTP ${res.status}).`);
  }

  const out: Collection[] = [];
  for (const block of responses(res.xml)) {
    if (!/<(?:[\w-]+:)?calendar[\s/>]/i.test(block)) continue;

    // When a server declares its supported components, require VEVENT — that is
    // what filters out the address books and task lists sharing the home set.
    // iCloud writes the attribute single-quoted, others double: accept either.
    const comps = tagContent(block, "supported-calendar-component-set");
    if (comps && !/name\s*=\s*['"]?VEVENT/i.test(comps)) continue;

    const href = firstHref(block);
    if (!href) continue;

    const collUrl = resolve(href, res.finalUrl);
    if (trimSlash(collUrl) === trimSlash(url)) continue; // the home set itself

    const privileges = tagContent(block, "current-user-privilege-set") ?? "";
    out.push({
      url: collUrl,
      name: decodeXml((tagContent(block, "displayname") ?? "").trim()),
      // Absent privileges means the server did not say; assume writable and let
      // the PUT fail loudly rather than hiding a usable calendar.
      readOnly: privileges.length > 0 && !/<(?:[\w-]+:)?write[-\s/>]/i.test(privileges),
    });
  }
  return out;
}

function trimSlash(url: string): string {
  return url.replace(/\/+$/, "");
}

function parentOf(url: string): string | null {
  try {
    const u = new URL(url);
    const parts = trimSlash(u.pathname).split("/");
    parts.pop();
    u.pathname = parts.join("/") + "/";
    return u.toString();
  } catch {
    return null;
  }
}

/// Every VEVENT collection the account can read.
///
/// `deep` exists for IServ, which runs DAViCal: the calendars a school actually
/// cares about — the school-wide `+public` feed, class and group calendars — are
/// NOT in the pupil's own calendar-home-set. They live under sibling principals
/// one path segment up. Without this pass an IServ connection lists the child's
/// empty personal calendar and nothing else, which is the single most confusing
/// thing the old app shipped.
export async function collections(
  homeUrl: string,
  user: string,
  password: string,
  deep = false,
): Promise<Collection[]> {
  const byUrl = new Map<string, Collection>();
  for (const c of await collectionsAt(homeUrl, user, password)) {
    byUrl.set(trimSlash(c.url), c);
  }

  if (deep) {
    const root = parentOf(homeUrl);
    if (root) {
      const siblings = (await childCollections(root, user, password).catch(() => []))
        .filter((p) => trimSlash(p) !== trimSlash(homeUrl))
        .slice(0, 50); // a DAViCal root can hold every account in the school

      const found = await Promise.all(
        siblings.map((p) => collectionsAt(p, user, password).catch(() => [])),
      );
      for (const list of found) {
        for (const c of list) byUrl.set(trimSlash(c.url), { ...c, readOnly: true });
      }
    }
  }

  return [...byUrl.values()];
}

async function childCollections(url: string, user: string, password: string): Promise<string[]> {
  const body = `<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>`;
  const res = await propfind(url, user, password, body, "1");
  if (res.status < 200 || res.status >= 300) return [];

  const out: string[] = [];
  for (const block of responses(res.xml)) {
    const href = firstHref(block);
    if (!href) continue;
    const child = resolve(href, res.finalUrl);
    if (trimSlash(child) !== trimSlash(url)) out.push(child);
  }
  return out;
}

function caldavTime(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/// Events of one collection within a window, already expanded and normalised.
export async function readEvents(
  collectionUrl: string,
  user: string,
  password: string,
  from: Date,
  to: Date,
): Promise<ParsedEvent[]> {
  const body =
    `<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` +
    `<d:prop><d:getetag/><c:calendar-data/></d:prop>` +
    `<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">` +
    `<c:time-range start="${caldavTime(from)}" end="${caldavTime(to)}"/>` +
    `</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>`;

  const res = await fetchUntrusted(collectionUrl, {
    method: "REPORT",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "application/xml; charset=utf-8",
      "User-Agent": USER_AGENT,
      Depth: "1",
    },
    body,
  });

  const xml = await res.text();
  if (!res.ok) {
    console.error(`caldav REPORT ${res.status}`);
    return [];
  }

  const out: ParsedEvent[] = [];
  for (const block of responses(xml)) {
    const raw = tagContent(block, "calendar-data");
    if (!raw) continue;

    const cdata = raw.trim().match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
    const ics = (cdata ? cdata[1] : decodeXml(raw)).trim();
    if (!ics.includes("BEGIN:VEVENT")) continue;

    const href = firstHref(block);
    const etag = (tagContent(block, "getetag") ?? "").trim() || null;

    for (const ev of parseIcs(ics, from, to)) {
      out.push({
        ...ev,
        href: href ? resolve(href, res.url || collectionUrl) : null,
        etag,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

/// One event as Aporah writes it. Wall-clock fields rather than instants: a
/// German family types "14:00", and `TZID=Europe/Berlin` is what preserves that
/// through a DST change. Converting to UTC here would pin the offset that
/// happened to apply on the day it was typed.
export interface CalDavEventInput {
  uid: string;
  title: string;
  /// YYYY-MM-DD.
  date: string;
  /// HH:MM, or null for an all-day event.
  time: string | null;
  /// YYYY-MM-DD. **Exclusive** for an all-day event, the way iCalendar means it.
  endDate: string;
  /// HH:MM, or null for an all-day event.
  endTime: string | null;
  location?: string | null;
  notes?: string | null;
}

/// RFC 5545 §3.3.11: comma, semicolon, backslash and newline are the four
/// characters that end a property value early if left alone.
function icsEscape(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/// The iCalendar for one event — the exact counterpart of [parseIcs], and
/// exported so the pair can be round-tripped without a server.
export function buildVEvent(ev: CalDavEventInput): string {
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const compact = (d: string) => d.replace(/-/g, "");
  const timed = ev.time !== null && ev.endTime !== null;

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Aporah//Calendar//DE",
    "CALSCALE:GREGORIAN",
  ];
  // A TZID reference without the matching VTIMEZONE is exactly the bug the read
  // path has a fallback for. Since we are the ones emitting it, ship it.
  if (timed) lines.push(...BERLIN_VTIMEZONE);

  lines.push(
    "BEGIN:VEVENT",
    `UID:${ev.uid}`,
    `DTSTAMP:${stamp}`,
    `SUMMARY:${icsEscape(ev.title)}`,
  );

  if (timed) {
    const hm = (t: string) => t.replace(":", "") + "00";
    lines.push(
      `DTSTART;TZID=Europe/Berlin:${compact(ev.date)}T${hm(ev.time!)}`,
      `DTEND;TZID=Europe/Berlin:${compact(ev.endDate)}T${hm(ev.endTime!)}`,
    );
  } else {
    lines.push(
      `DTSTART;VALUE=DATE:${compact(ev.date)}`,
      `DTEND;VALUE=DATE:${compact(ev.endDate)}`,
    );
  }

  if (ev.notes) lines.push(`DESCRIPTION:${icsEscape(ev.notes)}`);
  if (ev.location) lines.push(`LOCATION:${icsEscape(ev.location)}`);
  lines.push("END:VEVENT", "END:VCALENDAR");

  return lines.join("\r\n") + "\r\n";
}

/// PUTs a complete VCALENDAR at an exact resource URL — creating it if the href
/// is new, replacing it in place if it is not.
export async function putEvent(
  href: string,
  user: string,
  password: string,
  ev: CalDavEventInput,
): Promise<void> {
  const res = await fetchUntrusted(href, {
    method: "PUT",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "text/calendar; charset=utf-8",
      "User-Agent": USER_AGENT,
    },
    body: buildVEvent(ev),
  });
  if (!res.ok) throw new Error(`CalDAV PUT ${res.status}`);
}

/// Creates an event inside a collection, naming the resource after its UID.
export async function createEvent(
  collectionUrl: string,
  user: string,
  password: string,
  ev: CalDavEventInput,
): Promise<void> {
  await putEvent(`${trimSlash(collectionUrl)}/${ev.uid}.ics`, user, password, ev);
}

/// Locates the resource holding `uid` inside one collection.
///
/// Our own events are named `<uid>.ics`, but events created in Apple Calendar or
/// on an IServ web UI are not, so guessing the href only works for half of them.
/// A UID `prop-filter` is the RFC answer; iCloud honours it unreliably, which is
/// what [scanForUid] is for.
export async function findEventHref(
  collectionUrl: string,
  user: string,
  password: string,
  uid: string,
): Promise<string | null> {
  const body =
    `<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` +
    `<d:prop><d:getetag/></d:prop>` +
    `<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">` +
    `<c:prop-filter name="UID"><c:text-match collation="i;octet">${escapeXml(uid)}</c:text-match>` +
    `</c:prop-filter></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>`;

  const res = await fetchUntrusted(collectionUrl, {
    method: "REPORT",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "application/xml; charset=utf-8",
      "User-Agent": USER_AGENT,
      Depth: "1",
    },
    body,
  });

  if (res.ok) {
    const xml = await res.text();
    for (const block of responses(xml)) {
      const href = firstHref(block);
      if (href) return resolve(href, res.url || collectionUrl);
    }
  }
  return await scanForUid(collectionUrl, user, password, uid);
}

/// Fallback for [findEventHref]: read the collection over a wide window and
/// match the UID out of the returned iCalendar ourselves. Slower, but it is the
/// same request shape [readEvents] already makes, so it always sees what we see.
async function scanForUid(
  collectionUrl: string,
  user: string,
  password: string,
  uid: string,
): Promise<string | null> {
  const now = new Date();
  const from = new Date(Date.UTC(now.getUTCFullYear() - 2, 0, 1));
  const to = new Date(Date.UTC(now.getUTCFullYear() + 3, 0, 1));

  const body =
    `<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">` +
    `<d:prop><d:getetag/><c:calendar-data/></d:prop>` +
    `<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">` +
    `<c:time-range start="${caldavTime(from)}" end="${caldavTime(to)}"/>` +
    `</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>`;

  const res = await fetchUntrusted(collectionUrl, {
    method: "REPORT",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "application/xml; charset=utf-8",
      "User-Agent": USER_AGENT,
      Depth: "1",
    },
    body,
  });
  if (!res.ok) return null;

  const xml = await res.text();
  for (const block of responses(xml)) {
    const raw = tagContent(block, "calendar-data");
    if (!raw) continue;
    const cdata = raw.trim().match(/^<!\[CDATA\[([\s\S]*?)\]\]>$/);
    const ics = (cdata ? cdata[1] : decodeXml(raw)).trim();
    // Unfold RFC 5545 continuation lines before reading UID, or a long one
    // arrives split across two physical lines and never matches.
    const found = ics.replace(/\r?\n[ \t]/g, "").match(/^UID:(.*)$/im);
    if (found && found[1].trim() === uid) {
      const href = firstHref(block);
      if (href) return resolve(href, res.url || collectionUrl);
    }
  }
  return null;
}

/// Deletes one event resource. Already-gone counts as success — the user asked
/// for it not to be there.
export async function deleteEvent(href: string, user: string, password: string): Promise<void> {
  const res = await fetchUntrusted(href, {
    method: "DELETE",
    headers: { Authorization: basic(user, password), "User-Agent": USER_AGENT },
  });
  if (!res.ok && res.status !== 404 && res.status !== 410) {
    throw new Error(`CalDAV DELETE ${res.status}`);
  }
}

function escapeXml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// ---------------------------------------------------------------------------
// iCalendar
// ---------------------------------------------------------------------------

/// A VCALENDAR referencing `TZID=Europe/Berlin` without shipping the matching
/// VTIMEZONE is common, and ical.js then resolves the wall-clock components in
/// the RUNTIME zone — UTC on Edge Functions — shifting every German event by an
/// hour in winter and two in summer. This is the safety net; embedded VTIMEZONEs
/// still win, because they are registered per blob before parsing.
const BERLIN_VTIMEZONE = [
  "BEGIN:VTIMEZONE",
  "TZID:Europe/Berlin",
  "BEGIN:DAYLIGHT",
  "TZOFFSETFROM:+0100",
  "TZOFFSETTO:+0200",
  "TZNAME:CEST",
  "DTSTART:19700329T020000",
  "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU",
  "END:DAYLIGHT",
  "BEGIN:STANDARD",
  "TZOFFSETFROM:+0200",
  "TZOFFSETTO:+0100",
  "TZNAME:CET",
  "DTSTART:19701025T030000",
  "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU",
  "END:STANDARD",
  "END:VTIMEZONE",
];

let berlinRegistered = false;

function registerBerlin(): void {
  if (berlinRegistered) return;
  berlinRegistered = true;
  try {
    if (ICAL.TimezoneService.has("Europe/Berlin")) return;
    const cal = new ICAL.Component(
      ICAL.parse(
        ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Aporah//TZ//EN", ...BERLIN_VTIMEZONE, "END:VCALENDAR"]
          .join("\r\n"),
      ),
    );
    const vtz = cal.getFirstSubcomponent("vtimezone");
    // ical.js's own types declare register(tzid, Timezone) but ship a signature
    // that says otherwise; the two-argument call is what the library documents
    // and what works at runtime.
    // deno-lint-ignore no-explicit-any
    if (vtz) (ICAL.TimezoneService.register as any)("Europe/Berlin", new ICAL.Timezone(vtz));
  } catch {
    // A missing fallback is not worth failing a sync over.
  }
}

// deno-lint-ignore no-explicit-any
function registerEmbedded(component: any): void {
  try {
    for (const vtz of component.getAllSubcomponents("vtimezone")) {
      try {
        const tzid = vtz.getFirstPropertyValue("tzid");
        if (tzid && !ICAL.TimezoneService.has(tzid)) {
          // deno-lint-ignore no-explicit-any
          (ICAL.TimezoneService.register as any)(tzid, new ICAL.Timezone(vtz));
        }
      } catch { /* one malformed VTIMEZONE must not sink the blob */ }
    }
  } catch { /* no VTIMEZONE at all */ }
}

/// Parses one iCalendar blob into occurrences inside the window. Recurring
/// series are expanded here rather than stored as a rule, because the Kalender
/// screen reads plain rows out of public.events and knows nothing about RRULE.
export function parseIcs(ics: string, from: Date, to: Date): Omit<ParsedEvent, "href" | "etag">[] {
  const out: Omit<ParsedEvent, "href" | "etag">[] = [];

  try {
    const component = new ICAL.Component(ICAL.parse(ics));
    registerBerlin();
    registerEmbedded(component);

    for (const vevent of component.getAllSubcomponents("vevent")) {
      try {
        const event = new ICAL.Event(vevent);

        // deno-lint-ignore no-explicit-any
        const build = (start: any): Omit<ParsedEvent, "href" | "etag"> | null => {
          const startDate = start?.toJSDate?.();
          if (!startDate) return null;

          let endDate: Date | null = null;
          try {
            const seconds = event.duration?.toSeconds?.();
            if (seconds && seconds > 0) endDate = new Date(startDate.getTime() + seconds * 1000);
            else if (event.endDate) endDate = event.endDate.toJSDate();
          } catch { /* fall through to the default below */ }

          const allDay = start?.isDate === true;
          if (!endDate) {
            endDate = new Date(startDate.getTime() + (allDay ? 86_400_000 : 3_600_000));
          }

          return {
            uid: event.uid || crypto.randomUUID(),
            title: (event.summary || "").trim() || "Ohne Titel",
            notes: event.description || null,
            location: event.location || null,
            startsAt: startDate.toISOString(),
            endsAt: endDate.toISOString(),
            allDay,
          };
        };

        if (event.isRecurring()) {
          const iterator = event.iterator(event.startDate);
          let next;
          let guard = 0;
          while ((next = iterator.next()) && guard++ < 750) {
            const at = next.toJSDate();
            if (at > to) break;
            if (at < from) continue;
            const built = build(next);
            if (built) out.push(built);
          }
        } else {
          const at = event.startDate?.toJSDate?.();
          if (at && at >= from && at <= to) {
            const built = build(event.startDate);
            if (built) out.push(built);
          }
        }
      } catch { /* one malformed VEVENT must not sink the collection */ }
    }
  } catch { /* one malformed VCALENDAR must not sink the sync */ }

  return out;
}
