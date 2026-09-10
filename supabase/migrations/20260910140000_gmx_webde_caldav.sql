-- Aporah backend — GMX and WEB.DE, the two mailboxes half of Germany already has.
--
-- ---------------------------------------------------------------------------
-- Why these two, and why they are one thing
-- ---------------------------------------------------------------------------
--
-- Google and Apple are not where a German family's calendar necessarily lives.
-- GMX and WEB.DE are, and they are the same system wearing two brands: both are
-- 1&1 Mail & Media, both run the same CalDAV server ("begenda"), both answer at
-- `https://caldav.<brand>/begenda/dav/<address>/calendar`, and both return the
-- same nginx and the same Basic realm. So this is one provider implementation
-- and two rows in a base-URL table, not two integrations.
--
-- They need no OAuth registration, no vendor approval and no new mechanism:
-- a fixed server address plus a username and password is exactly the shape
-- iCloud already has, which is why `calendar-caldav` grew a list where it had a
-- pair of literal comparisons and nothing else moved.
--
-- ---------------------------------------------------------------------------
-- They are writable, and that is the point
-- ---------------------------------------------------------------------------
--
-- `is_read_only` is false for both, as for iCloud. A pasted ICS feed can only
-- be read; a CalDAV account can be written, so `calendar-write` reaches these
-- through the same `writeCalDav` it uses for iCloud. An appointment made in
-- Aporah lands in the household's real GMX calendar and therefore on the other
-- parent's phone — which is the entire reason a family connects an account
-- rather than subscribing to a feed.
--
-- ---------------------------------------------------------------------------
-- The password
-- ---------------------------------------------------------------------------
--
-- CalDAV authenticates every request with the password, so there is no token to
-- exchange it for and nothing shorter-lived to hold instead: connecting one of
-- these means storing it. It goes where the iCloud and IServ passwords already
-- go — `calendar_connection_secrets.caldav_password`, AES-256-GCM under
-- CALENDAR_SECRET_KEY, in a table with no policy and every privilege revoked
-- from `authenticated` and `anon`, opened only inside a function for the length
-- of one request.
--
-- The app asks for an *application-specific* password, which both brands mint
-- under Sicherheit → Zwei-Faktor-Authentifizierung. It is worth asking for even
-- though the account password usually works: an app password is revocable on
-- its own, and it is the difference between holding a key to a calendar and
-- holding a key to somebody's whole mailbox.

alter table public.calendar_connections
  drop constraint calendar_connections_provider_check;

-- 'ferien' and 'abfall' stay out, as they have since 20260804090000: they are
-- public_feeds + family_feeds, shared per Bundesland or address, and are not
-- connections at all.
alter table public.calendar_connections
  add constraint calendar_connections_provider_check
  check (provider in (
    'google', 'outlook', 'icloud', 'iserv', 'webuntis', 'ical', 'gmx', 'webde'
  ));

alter table public.calendars
  drop constraint calendars_provider_check;

alter table public.calendars
  add constraint calendars_provider_check
  check (provider in (
    'google', 'icloud', 'outlook', 'iserv', 'webuntis', 'ical', 'gmx', 'webde'
  ));

comment on column public.calendar_connections.provider is
  'Der Anbieter hinter der Verbindung. "ical" ist der anbieterlose Fall: ein '
  'beliebiger abonnierbarer ICS-Link oder eine hochgeladene .ics-Datei. "gmx" '
  'und "webde" sind derselbe CalDAV-Server unter zwei Marken (1&1 Mail & '
  'Media) und verhalten sich wie iCloud: feste Serveradresse, Anmeldung mit '
  'Benutzername und Passwort, schreibbar.';
