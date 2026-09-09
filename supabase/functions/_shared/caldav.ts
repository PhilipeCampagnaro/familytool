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
  /// Set on every occurrence of a recurring event, to the same value as [uid] —
  /// unlike Google and Graph, iCalendar gives a series and its occurrences one
  /// identity, and the occurrence is told apart by its RECURRENCE-ID.
  seriesUid: string | null;
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

  /// The recurrence rule's value, already formatted and **without** the
  /// `RRULE:` name — `FREQ=WEEKLY;INTERVAL=2;UNTIL=20261109T215959Z`. Null for
  /// an appointment that happens once, which is most of them.
  rrule?: string | null;
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

  // After DTSTART/DTEND, which is what the rule is anchored to: RFC 5545 does
  // not care about property order, but every ICS a human ever reads has it this
  // way round.
  if (ev.rrule) lines.push(`RRULE:${ev.rrule}`);
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
  await putIcs(href, user, password, buildVEvent(ev));
}

/// The same PUT with the body already written — for a resource that is being
/// *amended* rather than replaced, which is every change to one occurrence of a
/// series.
export async function putIcs(
  href: string,
  user: string,
  password: string,
  ics: string,
): Promise<void> {
  const res = await fetchUntrusted(href, {
    method: "PUT",
    headers: {
      Authorization: basic(user, password),
      "Content-Type": "text/calendar; charset=utf-8",
      "User-Agent": USER_AGENT,
    },
    body: ics,
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

// ---------------------------------------------------------------------------
// Writing one occurrence of a series
// ---------------------------------------------------------------------------
//
// Google and Graph hand out an addressable id per occurrence, so there "nur
// dieser Termin" is a PATCH like any other. iCalendar does not: a series and
// every one of its occurrences share a UID, and the only thing that tells them
// apart is a RECURRENCE-ID. So the three answers a user can give have to be
// written into the resource itself — an EXDATE for a cancelled Monday, an
// override VEVENT for a moved one, the master's own fields for the whole series
// — which means reading the ICS first and putting a modified one back.
//
// This used to be a `putEvent` of a freshly built single VEVENT over whatever
// was there. On a recurring appointment that replaced the series with one date:
// a family that changed the time of one football training lost the rest of the
// term, silently, and found out weeks later.
//
// The surgery goes through ical.js rather than through the text, because the
// value that has to match is not a string but a moment in a particular shape —
// a DATE, a `TZID=`-qualified wall clock, or a UTC instant, whichever the master
// itself uses — and line folding has to survive it.

/// One occurrence, as the app knows it: the wall-clock start it is shown at.
export interface Occurrence {
  /// YYYY-MM-DD.
  date: string;
  /// HH:MM, or null for an all-day series.
  time: string | null;
}

/// GETs one event resource. Null when it is gone, which for a delete is the
/// outcome asked for.
export async function readEventIcs(
  href: string,
  user: string,
  password: string,
): Promise<string | null> {
  const res = await fetchUntrusted(href, {
    method: "GET",
    headers: {
      Authorization: basic(user, password),
      "User-Agent": USER_AGENT,
      Accept: "text/calendar",
    },
  });
  if (res.status === 404 || res.status === 410) return null;
  if (!res.ok) throw new Error(`CalDAV GET ${res.status}`);
  const body = await res.text();
  return body.includes("BEGIN:VEVENT") ? body : null;
}

/// The parsed blob plus the master VEVENT — the one without a RECURRENCE-ID,
/// which is the series itself.
// deno-lint-ignore no-explicit-any
function openIcs(ics: string): { root: any; master: any } | null {
  try {
    const root = new ICAL.Component(ICAL.parse(ics));
    registerBerlin();
    registerEmbedded(root);
    registerOffsetZones(root);
    const master = root.getAllSubcomponents("vevent")
      // deno-lint-ignore no-explicit-any
      .find((v: any) => !v.hasProperty("recurrence-id"));
    return master ? { root, master } : null;
  } catch {
    return null;
  }
}

/// Whether this resource holds a repeating appointment. Asked of the ICS rather
/// than trusted from the client: the app only knows that an occurrence *came
/// from* a series, and what matters here is what the server actually holds.
export function icsIsRecurring(ics: string): boolean {
  const open = openIcs(ics);
  return !!open && open.master.hasProperty("rrule");
}

/// The occurrence's start in the shape the master's own DTSTART uses, so an
/// EXDATE or a RECURRENCE-ID written from it is comparable to the moments the
/// rule generates.
///
/// The app always sends Berlin wall clock — that is what it showed the user —
/// and this is where it is put back into the master's terms: left as a DATE for
/// an all-day series, converted to UTC where the master is in UTC, and moved
/// into the master's own zone where it names one.
// deno-lint-ignore no-explicit-any
function occurrenceTime(master: any, occ: Occurrence): any {
  const [year, month, day] = occ.date.split("-").map(Number);
  const dtstart = master.getFirstProperty("dtstart");
  const reference = dtstart?.getFirstValue();

  if (!occ.time || reference?.isDate === true) {
    return ICAL.Time.fromData({ year, month, day, isDate: true });
  }

  const [hour, minute] = occ.time.split(":").map(Number);
  const berlin = ICAL.TimezoneService.get("Europe/Berlin") ?? ICAL.Timezone.localTimezone;
  const local = new ICAL.Time(
    { year, month, day, hour, minute, second: 0, isDate: false },
    berlin,
  );

  const tzid = dtstart?.getParameter("tzid");
  if (typeof tzid === "string" && tzid !== "Europe/Berlin") {
    const zone = ICAL.TimezoneService.get(tzid);
    if (zone) return local.convertToZone(zone);
  }
  // No TZID and not floating means UTC — the form iCloud and most servers store
  // a timed event in.
  if (!tzid && reference?.zone === ICAL.Timezone.utcTimezone) {
    return local.convertToZone(ICAL.Timezone.utcTimezone);
  }
  return local;
}

/// A property carrying one moment, with the TZID parameter the value needs.
///
/// ical.js writes the value in the zone the [ICAL.Time] holds but does not add
/// the parameter that names it, and a `20260914T170000` with no TZID is a
/// floating time every client resolves in its own zone.
// deno-lint-ignore no-explicit-any
function timeProperty(name: string, time: any): any {
  const prop = new ICAL.Property(name);
  // No `VALUE=DATE` here: `setValue` writes it for a date-valued time, and
  // setting it as well emits the parameter twice.
  const tzid = time.zone?.tzid;
  if (!time.isDate && tzid && tzid !== "UTC" && tzid !== "floating") {
    prop.setParameter("tzid", tzid);
  }
  prop.setValue(time);
  return prop;
}

/// The blob with one occurrence taken out of the series — "nur dieser Termin"
/// on a delete.
///
/// An EXDATE rather than a DELETE of the resource, which is what would remove
/// every other Monday too. Any override already written for that day goes with
/// it: a moved occurrence that has since been cancelled must not come back as
/// its own appointment.
export function excludeOccurrence(ics: string, occ: Occurrence): string | null {
  const open = openIcs(ics);
  if (!open) return null;

  const at = occurrenceTime(open.master, occ);
  open.master.addProperty(timeProperty("exdate", at));

  // deno-lint-ignore no-explicit-any
  for (const vevent of open.root.getAllSubcomponents("vevent") as any[]) {
    const rid = vevent.getFirstPropertyValue("recurrence-id");
    if (rid && sameMoment(rid, at)) open.root.removeSubcomponent(vevent);
  }
  return open.root.toString();
}

/// The blob with one occurrence given its own values — "nur dieser Termin" on an
/// edit.
///
/// A second VEVENT under the same UID, carrying the RECURRENCE-ID of the slot it
/// replaces. Written fresh each time: an occurrence already overridden is
/// dropped first, so editing the same Monday twice leaves one override rather
/// than two claiming the same slot.
export function overrideOccurrence(
  ics: string,
  occ: Occurrence,
  ev: CalDavEventInput,
): string | null {
  const open = openIcs(ics);
  if (!open) return null;

  const at = occurrenceTime(open.master, occ);
  // deno-lint-ignore no-explicit-any
  for (const vevent of open.root.getAllSubcomponents("vevent") as any[]) {
    const rid = vevent.getFirstPropertyValue("recurrence-id");
    if (rid && sameMoment(rid, at)) open.root.removeSubcomponent(vevent);
  }

  // Built through [buildVEvent] so the override says exactly what a one-off
  // written by this app says — same escaping, same DTSTART/DTEND forms — and
  // then lifted out of its VCALENDAR wrapper and given its RECURRENCE-ID.
  const wrapper = new ICAL.Component(
    ICAL.parse(buildVEvent({ ...ev, uid: open.master.getFirstPropertyValue("uid") ?? ev.uid, rrule: null })),
  );
  const override = wrapper.getFirstSubcomponent("vevent");
  if (!override) return null;
  override.addProperty(timeProperty("recurrence-id", at));

  open.root.addSubcomponent(override);
  return open.root.toString();
}

/// The blob with the series' own fields changed and its rule left alone —
/// "ganze Serie" on an edit.
///
/// The master is edited in place rather than rebuilt, because everything this
/// does not touch is worth keeping: the RRULE, every EXDATE for a Monday the
/// family has already cancelled, and every override for one they moved.
///
/// [ev.rrule] replaces the rule only when the caller has one to set; a null
/// leaves the existing rule exactly where it is, which is what an edit that says
/// nothing about repetition should do.
///
/// **Exceptions are moved with the series.** An EXDATE and a RECURRENCE-ID both
/// name a slot the rule generates, so shifting DTSTART by an hour leaves every
/// one of them pointing at a moment that no longer exists: the cancelled Monday
/// silently comes back and the moved one detaches into a stray VEVENT. Adding
/// the same delta to each keeps them attached — the family said that Monday was
/// off, and moving training an hour later does not put it back on. An override's
/// *own* times are left alone, because they were typed for that day rather than
/// derived from the series.
export function editSeries(ics: string, ev: CalDavEventInput): string | null {
  const open = openIcs(ics);
  if (!open) return null;
  const { master } = open;

  const timed = ev.time !== null && ev.endTime !== null;
  const berlin = ICAL.TimezoneService.get("Europe/Berlin") ?? ICAL.Timezone.localTimezone;

  // deno-lint-ignore no-explicit-any
  const moment = (date: string, time: string | null): any => {
    const [year, month, day] = date.split("-").map(Number);
    if (!timed || time === null) return ICAL.Time.fromData({ year, month, day, isDate: true });
    const [hour, minute] = time.split(":").map(Number);
    return new ICAL.Time({ year, month, day, hour, minute, second: 0, isDate: false }, berlin);
  };

  const before = master.getFirstProperty("dtstart")?.getFirstValue();
  const after = moment(ev.date, ev.time);
  let delta = 0;
  try {
    delta = Math.round((after.toJSDate().getTime() - before.toJSDate().getTime()) / 1000);
  } catch { /* an unreadable DTSTART leaves the exceptions where they are */ }

  master.removeAllProperties("dtstart");
  master.removeAllProperties("dtend");
  master.removeAllProperties("duration");
  master.addProperty(timeProperty("dtstart", after));
  master.addProperty(timeProperty("dtend", moment(ev.endDate, ev.endTime)));

  const set = (name: string, value: string | null) => {
    master.removeAllProperties(name);
    if (value) master.addPropertyWithValue(name, value);
  };
  set("summary", ev.title);
  set("location", ev.location ?? null);
  set("description", ev.notes ?? null);
  if (ev.rrule) set("rrule", ev.rrule);

  // Bumped so a server that compares them can see this is the newer version.
  // Through ICAL.Time rather than a formatted string, which ical.js would take
  // as a text value and write back unquoted and unparseable.
  master.removeAllProperties("dtstamp");
  master.addPropertyWithValue("dtstamp", ICAL.Time.fromJSDate(new Date(), true));

  if (delta !== 0) {
    // deno-lint-ignore no-explicit-any
    const excluded: any[] = [];
    // deno-lint-ignore no-explicit-any
    for (const prop of master.getAllProperties("exdate") as any[]) {
      for (const value of prop.getValues()) excluded.push(shiftBy(value, delta));
    }
    master.removeAllProperties("exdate");
    for (const at of excluded) master.addProperty(timeProperty("exdate", at));

    // deno-lint-ignore no-explicit-any
    for (const vevent of open.root.getAllSubcomponents("vevent") as any[]) {
      const rid = vevent.getFirstProperty("recurrence-id");
      if (!rid) continue;
      const at = shiftBy(rid.getFirstValue(), delta);
      vevent.removeAllProperties("recurrence-id");
      vevent.addProperty(timeProperty("recurrence-id", at));
    }
  }

  return open.root.toString();
}

/// [time] moved by [seconds]. A DATE moves in whole days — adding seconds to one
/// is how a date-valued EXDATE ends up carrying a time nothing matches.
// deno-lint-ignore no-explicit-any
function shiftBy(time: any, seconds: number): any {
  try {
    const next = time.clone();
    next.addDuration(
      time.isDate
        ? ICAL.Duration.fromSeconds(Math.round(seconds / 86_400) * 86_400)
        : ICAL.Duration.fromSeconds(seconds),
    );
    return next;
  } catch {
    return time;
  }
}

/// Two moments are the same slot. Compared as instants rather than as strings,
/// so a RECURRENCE-ID stored in UTC still matches one written with a TZID.
// deno-lint-ignore no-explicit-any
function sameMoment(a: any, b: any): boolean {
  try {
    return a.toJSDate().getTime() === b.toJSDate().getTime();
  } catch {
    return false;
  }
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

/// A TZID that is not a zone name but a bare UTC offset: `TZID="+02:00"`.
const OFFSET_TZID = /^["']?([+-])(\d{2}):?(\d{2})["']?$/;

/// IServ's plugin feeds write `DTSTART;TZID="+02:00":20260908T113000` and ship
/// no VTIMEZONE at all. ical.js finds no zone by that name, falls back to
/// *floating*, and resolves the wall clock in the runtime zone — UTC on Edge
/// Functions. An 11:30 Klassenarbeit then lands at 11:30Z, i.e. 13:30 in
/// Germany: every event two hours late in summer, one in winter.
///
/// So the offset in the name is taken at face value and registered as a
/// fixed-offset zone. That is sound here rather than merely expedient: IServ
/// emits the offset that actually applied on the day of the event (+02:00 in
/// September, +01:00 in November), so there is no DST rule left to get wrong.
///
/// Every zone is registered before any VEVENT is read, because ical.js resolves
/// a TZID at property-access time and a zone registered halfway through the
/// loop would fix the second half of a feed and not the first.
// deno-lint-ignore no-explicit-any
function registerOffsetZones(component: any): void {
  try {
    for (const vevent of component.getAllSubcomponents("vevent")) {
      for (const name of ["dtstart", "dtend"]) {
        try {
          const tzid = vevent.getFirstProperty(name)?.getParameter("tzid");
          if (typeof tzid !== "string" || ICAL.TimezoneService.has(tzid)) continue;

          const match = OFFSET_TZID.exec(tzid);
          if (!match) continue;

          const offset = `${match[1]}${match[2]}${match[3]}`;
          const vtz = new ICAL.Component(ICAL.parse([
            "BEGIN:VTIMEZONE",
            `TZID:${tzid}`,
            "BEGIN:STANDARD",
            "DTSTART:19700101T000000",
            `TZOFFSETFROM:${offset}`,
            `TZOFFSETTO:${offset}`,
            `TZNAME:${tzid}`,
            "END:STANDARD",
            "END:VTIMEZONE",
          ].join("\r\n")));
          // deno-lint-ignore no-explicit-any
          (ICAL.TimezoneService.register as any)(tzid, new ICAL.Timezone(vtz));
        } catch { /* one odd TZID must not sink the blob */ }
      }
    }
  } catch { /* no VEVENTs to look at */ }
}

/// Parses one iCalendar blob into occurrences inside the window. Recurring
/// series are expanded here rather than passed on as a rule, because nothing
/// downstream — the wire, the device cache, the Kalender screen — knows what an
/// RRULE is.
///
/// **An override is folded into its master, not parsed beside it.** A series
/// somebody has moved one day of carries a second VEVENT with the same UID and
/// a RECURRENCE-ID, and the flat loop this used to be emitted that *and* the
/// occurrence the rule still generates: the changed Monday twice, once at each
/// time. `relateException` is what joins them, and since Aporah's own
/// "nur dieser Termin" edits are written as exactly that kind of override, every
/// one of them would otherwise show double the moment it was saved.
export function parseIcs(ics: string, from: Date, to: Date): Omit<ParsedEvent, "href" | "etag">[] {
  const out: Omit<ParsedEvent, "href" | "etag">[] = [];

  try {
    const component = new ICAL.Component(ICAL.parse(ics));
    registerBerlin();
    registerEmbedded(component);
    registerOffsetZones(component);

    const vevents = component.getAllSubcomponents("vevent");
    const overrides = vevents.filter((v) => v.hasProperty("recurrence-id"));
    const masters = vevents.filter((v) => !v.hasProperty("recurrence-id"));

    // An override whose master is somewhere else — a server may split a series
    // across resources — has nothing to fold into and stands as its own
    // appointment rather than being dropped.
    const claimed = new Set(masters.map((v) => v.getFirstPropertyValue("uid")));
    const roots = [
      ...masters,
      ...overrides.filter((v) => !claimed.has(v.getFirstPropertyValue("uid"))),
    ];

    for (const vevent of roots) {
      try {
        const event = new ICAL.Event(vevent);
        for (const ex of overrides) {
          if (ex === vevent || ex.getFirstPropertyValue("uid") !== event.uid) continue;
          // An override we cannot place — a RECURRENCE-ID in a zone this blob
          // never declared — is skipped rather than allowed to sink the series.
          try {
            event.relateException(ex);
          } catch { /* left to the rule that generated the occurrence */ }
        }

        const recurring = event.isRecurring();

        // deno-lint-ignore no-explicit-any
        const build = (start: any, end: any, item: any): Omit<ParsedEvent, "href" | "etag"> | null => {
          const startDate = start?.toJSDate?.();
          if (!startDate) return null;

          let endDate: Date | null = null;
          try {
            if (end?.toJSDate) endDate = end.toJSDate();
            else {
              const seconds = item.duration?.toSeconds?.();
              if (seconds && seconds > 0) endDate = new Date(startDate.getTime() + seconds * 1000);
              else if (item.endDate) endDate = item.endDate.toJSDate();
            }
          } catch { /* fall through to the default below */ }

          const allDay = start?.isDate === true;
          if (!endDate) {
            endDate = new Date(startDate.getTime() + (allDay ? 86_400_000 : 3_600_000));
          }

          const uid = item.uid || event.uid || crypto.randomUUID();
          return {
            uid,
            seriesUid: recurring ? uid : null,
            title: (item.summary || "").trim() || "Ohne Titel",
            notes: item.description || null,
            location: item.location || null,
            startsAt: startDate.toISOString(),
            endsAt: endDate.toISOString(),
            allDay,
          };
        };

        if (recurring) {
          const iterator = event.iterator(event.startDate);
          let next;
          let guard = 0;
          while ((next = iterator.next()) && guard++ < 750) {
            const at = next.toJSDate();
            if (at > to) break;
            if (at < from) continue;
            // Not the rule's own occurrence but whatever stands at that slot:
            // an overridden Monday answers with the override's title and times,
            // and a slot the series no longer has is not reached at all,
            // because the iterator honours EXDATE.
            let details;
            try {
              details = event.getOccurrenceDetails(next);
            } catch { /* an override we cannot read must not lose the slot */ }
            const built = details
              ? build(details.startDate, details.endDate, details.item ?? event)
              : build(next, null, event);
            if (built) out.push(built);
          }
        } else {
          const at = event.startDate?.toJSDate?.();
          if (at && at >= from && at <= to) {
            const built = build(event.startDate, event.endDate, event);
            if (built) out.push(built);
          }
        }
      } catch { /* one malformed VEVENT must not sink the collection */ }
    }
  } catch { /* one malformed VCALENDAR must not sink the sync */ }

  return out;
}
