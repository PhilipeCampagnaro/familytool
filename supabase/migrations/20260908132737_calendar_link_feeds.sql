-- Aporah backend — school calendars connected by a pasted link.
--
-- Why this exists at all: every IServ connection this app made over CalDAV came
-- back empty, and the reason turned out to be structural rather than a bug in
-- the client. IServ's *plugin* calendars — Aufgaben, Klausuren, Geburtstage —
-- are module-generated views, not CalDAV collections, so PROPFIND enumeration
-- cannot see them at any depth. The only collections it does find are the
-- pupil's own (empty) home and `+public`, the school-wide feed, which for a
-- normal Gymnasium is several hundred events about every class but the one the
-- child is actually in.
--
-- What IServ *does* offer is a per-plugin link share: a tokenised ICS URL the
-- user creates in Kalender → Einstellungen → Plugins, which needs no login and
-- returns exactly the events that matter. There is no API to enumerate or mint
-- those URLs — the user pastes each one. WebUntis works identically (Profil →
-- Datenzugriff → "Kalender publizieren" mints an `Ical.do?school=…&token=…`
-- URL), which is why one mechanism now serves both.
--
-- Two things get added, and deliberately nothing else:
--
--   1. 'webuntis' as a provider value on both tables.
--   2. Nothing for IServ. `auth_type = 'public'` with `is_read_only = true` was
--      already legal for it — the existing check `auth_type <> 'public' or
--      is_read_only` was written for exactly this shape — so the link flow
--      needs no schema change on the provider it was invented for.
--
-- The feed URLs live in `calendar_connections.config` under `feeds`, which is
-- household-readable. That is a considered choice rather than an oversight: the
-- URL is a bearer capability, but the only people who can read the column are
-- the household members who are already looking at the events it returns, and
-- `config` has no INSERT/UPDATE grant for `authenticated`, so a member can read
-- one and never add one. Minting a feed stays a service_role act in
-- `calendar-link`, which first proves the URL answers with real events.

-- ---------------------------------------------------------------------------
-- Providers
-- ---------------------------------------------------------------------------

alter table public.calendar_connections
  drop constraint calendar_connections_provider_check;

-- Note what is NOT in this list: 'ferien' and 'abfall'. They were valid provider
-- values in the original migration and were deliberately removed by
-- 20260804090000_public_feeds.sql when the two feeds moved to public_feeds +
-- family_feeds. Copying the *original* definition here and adding one value to
-- it would have quietly reinstated both.
alter table public.calendar_connections
  add constraint calendar_connections_provider_check
  check (provider in ('google', 'outlook', 'icloud', 'iserv', 'webuntis'));

-- `calendars.provider` names only what can produce a calendar row, so the two
-- feed kinds stay out of it — they moved to public_feeds and are not providers
-- any more. See 20260805182949_drop_own_calendar.sql.
alter table public.calendars
  drop constraint calendars_provider_check;

alter table public.calendars
  add constraint calendars_provider_check
  check (provider in ('google', 'icloud', 'outlook', 'iserv', 'webuntis'));

comment on column public.calendar_connections.config is
  'Nicht-geheime Einstellungen: CalDAV-home_url, IServ-Serveradresse, Abfall-Konfiguration, '
  'und für per Link verbundene Schulkalender die Liste "feeds" '
  '([{url, name, host, added_at}]). Nur service_role schreibt hier — '
  '`authenticated` hat kein UPDATE-Recht auf dieser Spalte.';
