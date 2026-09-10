/// What a school feed actually looks like on the wire, and what we make of it.
///
/// These run against `parseIcs` — the same function every pasted link, every
/// CalDAV collection and every Ferien feed goes through — with a synthetic
/// WebUntis timetable, because the real one cannot be committed: it is reached
/// by a URL that is itself a credential, and a captured copy would name a real
/// child, their class and where they are at 08:00 on a Tuesday.
///
/// Run with: deno test supabase/functions/_shared/ics_feed_test.ts
///
/// The shape below is WebUntis's "Standard" iCal format:
/// `https://<server>/WebUntis/Ical.do?school=…&id=…&token=…` answers a plain
/// VCALENDAR of one VEVENT per lesson, SUMMARY carrying the subject and the
/// teacher, LOCATION the room, and DTSTART/DTEND in the school's own timezone.

import { assertEquals } from "jsr:@std/assert@1";
import { parseIcs } from "./caldav.ts";
import { feedName } from "./ics_feed.ts";

const WINDOW_FROM = new Date("2026-09-01T00:00:00Z");
const WINDOW_TO = new Date("2026-09-30T00:00:00Z");

function parse(ics: string) {
  return parseIcs(ics, WINDOW_FROM, WINDOW_TO);
}

/// One VCALENDAR with the cases a real timetable mixes: an ordinary lesson, a
/// second subject, a room change written the way Untis writes one, a cancelled
/// lesson, a UTC timestamp, and a folded, escaped DESCRIPTION.
const WEBUNTIS_FEED = [
  "BEGIN:VCALENDAR",
  "VERSION:2.0",
  "PRODID:-//Untis GmbH//WebUntis//DE",
  "CALSCALE:GREGORIAN",
  "X-WR-CALNAME:Stundenplan 8b",
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
  // An ordinary lesson, in the school's own zone.
  "BEGIN:VEVENT",
  "UID:lesson-1@webuntis",
  "DTSTART;TZID=Europe/Berlin:20260907T080000",
  "DTEND;TZID=Europe/Berlin:20260907T084500",
  "SUMMARY:Mathematik BAU",
  "LOCATION:R204",
  "END:VEVENT",
  // A different subject the same morning.
  "BEGIN:VEVENT",
  "UID:lesson-2@webuntis",
  "DTSTART;TZID=Europe/Berlin:20260907T085000",
  "DTEND;TZID=Europe/Berlin:20260907T093500",
  "SUMMARY:Deutsch KLE",
  "LOCATION:R107",
  "END:VEVENT",
  // A room change, with the note folded across lines and its commas escaped —
  // RFC 5545 says a folded line continues after CRLF plus one space.
  "BEGIN:VEVENT",
  "UID:lesson-3@webuntis",
  "DTSTART;TZID=Europe/Berlin:20260908T100000",
  "DTEND;TZID=Europe/Berlin:20260908T104500",
  "SUMMARY:Physik HRT",
  "LOCATION:Labor 2",
  "DESCRIPTION:Raumänderung: statt R204\\, jetzt Labor 2. Bitte Kittel mitbrin",
  " gen\\; Schutzbrille liegt bereit.",
  "END:VEVENT",
  // Cancelled. Untis strips these from its own feed, but IServ and generic
  // feeds do not, and a cancelled lesson drawn as a lesson is the one outcome
  // that misleads a parent.
  "BEGIN:VEVENT",
  "UID:lesson-4@webuntis",
  "DTSTART;TZID=Europe/Berlin:20260908T110000",
  "DTEND;TZID=Europe/Berlin:20260908T114500",
  "SUMMARY:Sport WEB",
  "LOCATION:Turnhalle",
  "STATUS:CANCELLED",
  "END:VEVENT",
  // A UTC timestamp, which is what an Elternabend entry tends to carry.
  "BEGIN:VEVENT",
  "UID:evening-1@webuntis",
  "DTSTART:20260909T170000Z",
  "DTEND:20260909T183000Z",
  "SUMMARY:Elternabend 8b",
  "LOCATION:Aula",
  "END:VEVENT",
  "END:VCALENDAR",
].join("\r\n");

Deno.test("WebUntis feed: lessons come through, cancelled ones do not", () => {
  const events = parse(WEBUNTIS_FEED);
  const titles = events.map((e) => e.title).sort();

  assertEquals(titles, [
    "Deutsch KLE",
    "Elternabend 8b",
    "Mathematik BAU",
    "Physik HRT",
  ]);
});

Deno.test("WebUntis feed: a lesson in the school's zone lands at the right hour", () => {
  const first = parse(WEBUNTIS_FEED).find((e) => e.uid === "lesson-1@webuntis");
  // 08:00 Berlin in September is CEST, so 06:00 UTC. Getting this wrong by an
  // hour is the failure that makes a timetable look almost right.
  assertEquals(first?.startsAt, "2026-09-07T06:00:00.000Z");
  assertEquals(first?.endsAt, "2026-09-07T06:45:00.000Z");
  assertEquals(first?.allDay, false);
});

Deno.test("WebUntis feed: a UTC timestamp is taken as written", () => {
  const evening = parse(WEBUNTIS_FEED).find((e) => e.uid === "evening-1@webuntis");
  assertEquals(evening?.startsAt, "2026-09-09T17:00:00.000Z");
});

Deno.test("WebUntis feed: room, and a folded escaped note, survive", () => {
  const physics = parse(WEBUNTIS_FEED).find((e) => e.uid === "lesson-3@webuntis");
  assertEquals(physics?.location, "Labor 2");
  assertEquals(
    physics?.notes,
    "Raumänderung: statt R204, jetzt Labor 2. Bitte Kittel mitbringen; Schutzbrille liegt bereit.",
  );
});

Deno.test("WebUntis feed: the calendar names itself", () => {
  assertEquals(feedName(WEBUNTIS_FEED), "Stundenplan 8b");
});

Deno.test("a cancelled occurrence of a series drops that date only", () => {
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Aporah//test//EN",
    "BEGIN:VEVENT",
    "UID:weekly@webuntis",
    "DTSTART:20260907T060000Z",
    "DTEND:20260907T064500Z",
    "RRULE:FREQ=WEEKLY;COUNT=3",
    "SUMMARY:Informatik",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:weekly@webuntis",
    "RECURRENCE-ID:20260914T060000Z",
    "DTSTART:20260914T060000Z",
    "DTEND:20260914T064500Z",
    "SUMMARY:Informatik",
    "STATUS:CANCELLED",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");

  const starts = parse(ics).map((e) => e.startsAt).sort();
  assertEquals(starts, ["2026-09-07T06:00:00.000Z", "2026-09-21T06:00:00.000Z"]);
});

Deno.test("an empty but valid calendar is zero events, not an error", () => {
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Untis GmbH//WebUntis//DE",
    "X-WR-CALNAME:Klausuren",
    "END:VCALENDAR",
  ].join("\r\n");

  assertEquals(parse(ics).length, 0);
  assertEquals(feedName(ics), "Klausuren");
});

Deno.test("malformed input yields nothing rather than throwing", () => {
  assertEquals(parse("not a calendar at all").length, 0);
  assertEquals(parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:broken").length, 0);
});

Deno.test("one unreadable VEVENT does not take the readable ones with it", () => {
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Aporah//test//EN",
    "BEGIN:VEVENT",
    "UID:good@webuntis",
    "DTSTART:20260907T060000Z",
    "DTEND:20260907T064500Z",
    "SUMMARY:Chemie",
    "END:VEVENT",
    "BEGIN:VEVENT",
    "UID:bad@webuntis",
    "DTSTART;TZID=Nowhere/Invented:20260907T080000",
    "SUMMARY:Kaputt",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");

  const titles = parse(ics).map((e) => e.title);
  assertEquals(titles.includes("Chemie"), true);
});

Deno.test("an event with no SUMMARY still has a title", () => {
  const ics = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Aporah//test//EN",
    "BEGIN:VEVENT",
    "UID:nameless@webuntis",
    "DTSTART:20260907T060000Z",
    "DTEND:20260907T064500Z",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");

  assertEquals(parse(ics)[0].title, "Ohne Titel");
});
