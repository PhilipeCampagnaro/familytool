-- Aporah backend — take `config` away from the client, and make key rotation
-- something that can actually be done.
--
-- ---------------------------------------------------------------------------
-- 1. calendar_connections.config is household-readable and holds bearer tokens
-- ---------------------------------------------------------------------------
--
-- 20260908155018 made exactly this argument about `calendars.external_id` and
-- revoked the grant. The same reasoning applies verbatim one table over, and was
-- missed: for a school calendar connected by a pasted link, `config.feeds` is
-- `[{url, name, host, added_at}]` and that `url` is the **tokenised ICS URL** —
-- a bearer capability that needs no login, works from any machine on earth, and
-- is revoked only by the pupil regenerating it in IServ or WebUntis.
--
-- 20260908132737 called the exposure "a considered trade: the only people who
-- can read it are the members already looking at the events it returns". That is
-- the argument the lock-down migration rejected, and it is no better here.
-- Seeing events inside the app is scoped, revocable, and ends when someone
-- leaves the household. Holding the URL is none of those three: it outlives the
-- membership, travels off the device, and cannot be withdrawn by us at all.
--
-- The household includes the `kid` role. On a school connection the token is
-- very often that child's own timetable — but `config` is per connection, not
-- per child, so one member reading the column gets **every** sibling's feed.
--
-- `grant select on public.calendar_connections` in 20260803101000 was
-- table-wide, so every column came with it, including ones added afterwards.
-- The fix is the column list that was always meant: everything except `config`.
-- Nothing is lost — no Flutter code path reads it. The repository selects a
-- fixed list (`calendar_connection_repository.dart`) that never included
-- `config`, calendars reach the app from `calendar-events`, and the `config`
-- field on the Dart model is filled from Edge Function responses (the Abfall
-- coverage check), never from PostgREST.

revoke select on public.calendar_connections from authenticated;

grant select (
  id, family_id, provider, auth_type, external_account, display_name,
  selected_calendars, is_read_only, status, status_detail, last_synced_at,
  created_by, position, created_at, updated_at, calendar_names,
  owner_member_id, owner_label, calendar_owners
) on public.calendar_connections to authenticated;

-- The old comment called this column "Nicht-geheime Einstellungen", which was
-- true when it held CalDAV home URLs and Abfall config and stopped being true
-- the moment link-connected feeds moved in. A column comment that lies is how a
-- later reader ends up logging it or adding it back to a select list.
comment on column public.calendar_connections.config is
  'Verbindungsdaten, die keine Zugangsdaten im engeren Sinn sind, aber '
  'trotzdem NICHT an den Client gehören: CalDAV-home_url, IServ-Serveradresse, '
  'Abfall-Konfiguration, WebUntis server/school/student_id — und für per Link '
  'verbundene Schulkalender die Liste "feeds" ([{url, name, host, added_at}]), '
  'deren URL ein tokenisierter Zugangsschlüssel ist. Nur service_role liest und '
  'schreibt hier; `authenticated` hat auf dieser Spalte weder SELECT noch UPDATE.';

-- ---------------------------------------------------------------------------
-- 2. Key rotation
-- ---------------------------------------------------------------------------
--
-- No schema change: the envelope in `_shared/secrets.ts` is self-describing and
-- AES-GCM's tag makes trial decryption unambiguous — a wrong key fails the tag
-- check rather than returning plausible garbage. So rotation is a *deploy*, not
-- a migration: the new key goes in CALENDAR_SECRET_KEY, the old one joins
-- CALENDAR_SECRET_KEY_RETIRED, and every stored credential keeps opening while
-- new ones seal under the new key.
--
-- This comment exists because the table comment previously implied a single
-- immutable key, and `docs/ported-features.md` said "generate once, never rotate
-- casually" — which in practice meant never, including after an incident, which
-- is the one moment Art. 32 DSGVO expects a key to be replaceable.

comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens, CalDAV-Passwörter und WebUntis-App-Schlüssel. '
  'Nur service_role, nur verschlüsselt (AES-256-GCM). Der aktive Schlüssel ist '
  'CALENDAR_SECRET_KEY; ausgemusterte Schlüssel bleiben in '
  'CALENDAR_SECRET_KEY_RETIRED lesbar, bis alle Werte neu versiegelt sind.';
