-- Aporah backend — WebUntis connected by its app secret instead of a link.
--
-- The pasted-link route (20260908132737) stands and stays reachable, because a
-- link needs nothing of anybody. But WebUntis, unlike IServ, has a first-class
-- credential for exactly this: a pupil's own profile — Freigaben → "Zugriff
-- über Untis Mobile" → Zugangsdaten anzeigen — mints a QR code carrying the
-- school, the login and a base32 **app secret**, and that secret is what Untis
-- Mobile itself authenticates with. A TOTP computed from it replaces the
-- password entirely.
--
-- Three things follow, and they are why this is worth a schema change rather
-- than leaving well alone:
--
--   1. We never hold the password. The secret is revocable from the page that
--      made it, without touching the account, and it grants nothing but read
--      access to that one pupil's own data.
--   2. It survives 2FA. The old `authenticate` call over jsonrpc.do is refused
--      outright for accounts with 2FA on — so a password login would break in
--      precisely the schools that took security seriously.
--   3. The timetable arrives as structured lessons — subject, teacher and room
--      in separate fields, plus a status code for Entfall and Vertretung. An
--      ICS feed is flat text in which a cancelled lesson looks like a lesson,
--      which is the one thing a family most needs to see.
--
-- Two additions, and deliberately nothing else. No new provider value:
-- 'webuntis' already exists and this is the same provider reached a second way,
-- exactly as IServ is both 'caldav' and 'public'. `auth_type` is what tells
-- them apart, which is what that column has been for since the first migration.

-- ---------------------------------------------------------------------------
-- auth_type
-- ---------------------------------------------------------------------------

alter table public.calendar_connections
  drop constraint calendar_connections_auth_type_check;

alter table public.calendar_connections
  add constraint calendar_connections_auth_type_check
  check (auth_type in ('oauth', 'caldav', 'public', 'secret'));

-- The pairing `auth_type = 'public'` implies `is_read_only` is untouched and
-- still correct: 'secret' is not 'public', and a WebUntis connection is written
-- read-only for its own reason — a school timetable is somebody else's system
-- of record, and Untis offers no write API worth having.

comment on column public.calendar_connections.auth_type is
  'Wie der Server die Verbindung anspricht: oauth (Google, Outlook), '
  'caldav (iCloud, IServ-Login), public (per Link verbundene Schulkalender, '
  'ohne Zugangsdaten) oder secret (WebUntis-App-Schlüssel, TOTP statt Passwort).';

-- ---------------------------------------------------------------------------
-- The secret itself
-- ---------------------------------------------------------------------------
--
-- Its own column rather than a second tenant in `caldav_password`. The two are
-- not the same kind of thing — one is a password replayed over HTTP Basic, the
-- other is TOTP seed material — and a column whose name lies is how a later
-- reader ends up sending one where the other belongs.
--
-- No grant is needed: `revoke all on public.calendar_connection_secrets from
-- authenticated, anon` in the original migration is table-level, so a new
-- column is already unreachable. It is stored sealed (AES-256-GCM,
-- CALENDAR_SECRET_KEY) like everything else in here.

alter table public.calendar_connection_secrets
  add column app_secret text;

comment on column public.calendar_connection_secrets.app_secret is
  'Der WebUntis-App-Schlüssel (base32), verschlüsselt. Aus ihm wird bei jedem '
  'Abruf ein TOTP berechnet — es wird nie ein Passwort gespeichert.';

comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens, CalDAV-Passwörter und WebUntis-App-Schlüssel. '
  'Nur service_role, nur verschlüsselt (AES-256-GCM, Schlüssel CALENDAR_SECRET_KEY '
  'in den Function-Secrets).';

-- `config` gains the WebUntis fields — server, school, the pupil's element id.
-- None of them is a secret: they are printed under the QR code in plain text
-- and answer nothing without the key.

comment on column public.calendar_connections.config is
  'Nicht-geheime Einstellungen: CalDAV-home_url, IServ-Serveradresse, '
  'Abfall-Konfiguration, für per Link verbundene Schulkalender die Liste "feeds" '
  '([{url, name, host, added_at}]) und für WebUntis server/school/student_id. '
  'Nur service_role schreibt hier — `authenticated` hat kein UPDATE-Recht auf '
  'dieser Spalte.';
