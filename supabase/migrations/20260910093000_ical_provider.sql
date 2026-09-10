-- Aporah backend — WebUntis moves to its iCal link, and any feed can be pasted.
--
-- ---------------------------------------------------------------------------
-- 1. WebUntis is a link provider now
-- ---------------------------------------------------------------------------
--
-- No schema change is needed for that, which is the point worth recording:
-- `auth_type = 'public'` with `is_read_only = true` has been legal for WebUntis
-- since 20260908132737, because the link mechanism was built for both schools
-- at once. What changes is which route the app offers first.
--
-- Why: WebUntis's own "Kalender publizieren" mints
-- `https://<server>/WebUntis/Ical.do?school=…&id=…&token=…`, a subscription URL
-- that tracks the timetable as it changes. Connecting through it means this app
-- stores a feed URL — sealed, revocable from the page that made it, good for
-- one pupil's timetable and nothing else — instead of the app secret, which is
-- TOTP seed material for that pupil's WebUntis account. For a family app whose
-- users are children, holding the smaller thing is worth a real feature cost.
--
-- The cost, since it should be written down where the trade is: the iCal feed
-- carries lessons and no homework, Untis strips cancelled lessons from it
-- deliberately (they broke Google Calendar), and it spans about one week back
-- to twelve weeks forward rather than the school year. The app-secret route
-- still exists for the households that want those things — demoted to a row at
-- the bottom of the WebUntis page, exactly where IServ's CalDAV login sits, and
-- for the same reason: it is the answer to a real question that most people
-- should not be asked.
--
-- ---------------------------------------------------------------------------
-- 2. 'ical' — any published feed
-- ---------------------------------------------------------------------------
--
-- The link mechanism has no school in it. It fetches an ICS URL, proves it
-- returns a VCALENDAR, seals the URL and re-reads it on every refresh. IServ
-- and WebUntis are that plus a name and a set of instructions, because finding
-- the link is the entire difficulty for a parent. `ical` is the same thing for
-- the Verein's fixture list, the Kita's closing days, the shared work calendar
-- — anything a family can already subscribe to in a calendar app.
--
-- It gets no `auth_type` of its own: 'public' with `is_read_only = true` is the
-- pairing the original check constraint already required, and a subscribed feed
-- is read-only by nature — there is no addressable resource behind an event in
-- it to PUT to.

alter table public.calendar_connections
  drop constraint calendar_connections_provider_check;

-- 'ferien' and 'abfall' stay out, as they have since 20260804090000: they are
-- public_feeds + family_feeds now, shared per Bundesland or address, and are
-- not connections at all. Copying an older definition and adding one value is
-- how they would come back by accident.
alter table public.calendar_connections
  add constraint calendar_connections_provider_check
  check (provider in ('google', 'outlook', 'icloud', 'iserv', 'webuntis', 'ical'));

alter table public.calendars
  drop constraint calendars_provider_check;

alter table public.calendars
  add constraint calendars_provider_check
  check (provider in ('google', 'icloud', 'outlook', 'iserv', 'webuntis', 'ical'));

comment on column public.calendar_connections.provider is
  'Der Anbieter hinter der Verbindung. "ical" ist der anbieterlose Fall: ein '
  'beliebiger abonnierbarer ICS-Link. Er teilt sich die gesamte Mechanik mit '
  'iserv/webuntis (auth_type = ''public'', is_read_only, URL verschlüsselt in '
  'calendar_connection_secrets.feed_urls) — nur Name und Anleitung fehlen ihm.';
