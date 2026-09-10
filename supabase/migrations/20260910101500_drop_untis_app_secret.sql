-- Aporah backend — the WebUntis app secret goes, and with it the last credential
-- this app held on a child's own school account.
--
-- 20260908153309 added `app_secret` and `auth_type = 'secret'` for the QR-code
-- route: Profil → Freigaben → "Zugriff über Untis Mobile" prints a base32 key,
-- Untis Mobile authenticates with a TOTP computed from it, and storing it let
-- this app read the timetable through Untis's JSON-RPC endpoint.
--
-- That route is now gone from the app. WebUntis is connected the way IServ is,
-- by the iCal subscription the pupil publishes under Freigaben, which is a
-- capability on one timetable rather than on the account behind it.
--
-- The trade, so that nobody re-adds this without knowing what they are buying:
-- the JSON-RPC route brought back Entfall and Vertretung as lesson status, the
-- whole school year rather than the feed's twelve weeks, and Hausaufgaben,
-- which the Board rendered. All three are gone. What is bought is that the app
-- holds no key that opens a child's WebUntis account, which for an app whose
-- users are children is the better side of the trade — and it retires a DSGVO
-- question (Art. 32, Art. 5 Abs. 1 lit. c) rather than answering it.
--
-- Nothing is lost in this database: no connection was ever made this way. The
-- statements below are written to be correct anyway, because a migration that
-- only works on an empty table is a migration that fails on the first restore
-- from a backup taken somewhere else.

-- ---------------------------------------------------------------------------
-- 1. The connections, if there are any
-- ---------------------------------------------------------------------------
--
-- Deleted rather than converted. There is nothing to convert them *to*: the
-- iCal URL is minted by a button in the pupil's own profile and cannot be
-- derived from the key, so the honest outcome is that the household connects
-- again. `calendar_connection_secrets` and `calendars` both cascade.

delete from public.calendar_connections where auth_type = 'secret';

-- ---------------------------------------------------------------------------
-- 2. The column
-- ---------------------------------------------------------------------------
--
-- Dropped, not merely stopped-writing-to. A sealed credential nobody reads is
-- still a sealed credential in a backup, and Art. 5 Abs. 1 lit. e has nothing
-- to say for keeping one whose purpose has ended.

alter table public.calendar_connection_secrets drop column app_secret;

comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens, CalDAV-Passwörter und die ICS-URLs per Link '
  'verbundener Kalender. Nur service_role, nur verschlüsselt (AES-256-GCM). '
  'Der aktive Schlüssel ist CALENDAR_SECRET_KEY; ausgemusterte Schlüssel '
  'bleiben in CALENDAR_SECRET_KEY_RETIRED lesbar, bis alle Werte neu '
  'versiegelt sind.';

-- ---------------------------------------------------------------------------
-- 3. The auth_type value
-- ---------------------------------------------------------------------------
--
-- Back to the three kinds the original migration named. Removing the value is
-- what makes the removal structural: a later `insert … auth_type = 'secret'` is
-- refused by Postgres rather than by somebody remembering this decision.

alter table public.calendar_connections
  drop constraint calendar_connections_auth_type_check;

alter table public.calendar_connections
  add constraint calendar_connections_auth_type_check
  check (auth_type in ('oauth', 'caldav', 'public'));

comment on column public.calendar_connections.auth_type is
  'Wie die Verbindung authentifiziert wird: ''oauth'' (Google, Outlook), '
  '''caldav'' (iCloud, IServ-Login) oder ''public'' (per Link abonnierte '
  'Kalender — IServ, WebUntis, beliebige ICS-Feeds). ''secret'' gab es für den '
  'WebUntis-QR-Code und ist entfallen, siehe 20260910101500.';
