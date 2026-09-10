-- Aporah backend — a pasted ICS link is a credential, so store it like one.
--
-- 20260908155018 and 20260909101500 both closed *grants* around the feed URL:
-- `calendars` lost every privilege, `calendar_connections.config` came off the
-- authenticated select list. Both migrations wrote the same paragraph about why
-- the URL matters — it needs no login, works from any machine on earth, and is
-- revoked only by the pupil regenerating it in IServ or WebUntis — and neither
-- drew the conclusion that follows from it: the thing was still sitting in the
-- database in plain text.
--
-- Every other credential in this app is sealed. An OAuth refresh token, a
-- CalDAV password and a WebUntis app key are AES-256-GCM envelopes in
-- `calendar_connection_secrets` under CALENDAR_SECRET_KEY, which lives in the
-- function secrets and never reaches Postgres. The argument for that is the
-- second barrier: a database dump, a leaked service_role key or a mis-scoped
-- backup yields ciphertext. A tokenised school feed is the same kind of thing —
-- it is a child's timetable, readable by anyone holding the string — and it had
-- only the first barrier.
--
-- So the URL moves here, and `config.feeds` keeps `[{id, name, host,
-- added_at}]` where `id` is an opaque uuid. That id is what becomes
-- `calendars.external_id`, what `selected_calendars` ticks and what
-- `calendar_names` and `calendar_owners` key on — three columns the household
-- can read, which until now held the token itself.
--
-- ---------------------------------------------------------------------------
-- The column
-- ---------------------------------------------------------------------------
--
-- `{feed id: envelope}` rather than one envelope over the whole map: a
-- re-pasted link is resealed on its own, each value gets its own IV, and a
-- single unopenable value costs one calendar instead of the account.
--
-- No grant is needed. `revoke all on public.calendar_connection_secrets from
-- authenticated, anon` in 20260803101000 is table-level, so a new column is
-- unreachable the moment it exists — the same reason 20260908153309 needed none
-- for `app_secret`.

alter table public.calendar_connection_secrets
  add column feed_urls jsonb not null default '{}'::jsonb;

comment on column public.calendar_connection_secrets.feed_urls is
  'Die per Link verbundenen Schulkalender: {"<feed-id>": "<Chiffrat>"}. Jede '
  'ICS-URL ist ein tokenisierter Zugangsschlüssel und einzeln verschlüsselt '
  '(AES-256-GCM, CALENDAR_SECRET_KEY). Die feed-id ist die undurchsichtige '
  'Kennung aus calendar_connections.config.feeds.';

comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens, CalDAV-Passwörter, WebUntis-App-Schlüssel und die '
  'ICS-URLs per Link verbundener Schulkalender. Nur service_role, nur '
  'verschlüsselt (AES-256-GCM). Der aktive Schlüssel ist CALENDAR_SECRET_KEY; '
  'ausgemusterte Schlüssel bleiben in CALENDAR_SECRET_KEY_RETIRED lesbar, bis '
  'alle Werte neu versiegelt sind.';

-- ---------------------------------------------------------------------------
-- What happens to the rows that are already here
-- ---------------------------------------------------------------------------
--
-- Not in SQL, because SQL cannot encrypt: CALENDAR_SECRET_KEY is a function
-- secret and is deliberately unreachable from the database, which is the whole
-- point of holding it there. Writing a plpgsql backfill would mean handing
-- Postgres the key, i.e. undoing the protection in the act of applying it.
--
-- So the sealing happens where the key already is. `migrateLegacyFeeds` in
-- `_shared/ics_feed.ts` runs at the top of every `calendar-events` read and on
-- both `calendar-link` writes: it mints an id per legacy feed, seals the URL
-- into `feed_urls`, rewrites `config.feeds`, remaps `selected_calendars`,
-- `calendar_names` and `calendar_owners`, and updates the `calendars` rows that
-- were keyed on the URL. The household notices nothing — not a reconnect
-- prompt, not a lost colour, not a re-picked calendar.
--
-- The order of those writes is the safety argument: the sealed URL is written
-- first, so a crash mid-migration leaves the plaintext in `config` and the next
-- read starts over from a known-good source. Stripping `config` first would
-- lose a family's school calendars outright.
--
-- `feedsOf` refuses to read a legacy entry at all, so there is no path by which
-- an un-migrated feed hands its URL onward to `calendars.external_id` again —
-- the worst an un-migrated connection can do is show no calendars until the
-- migration runs, which is the same read that would have run anyway.
--
-- 20260910071500 is the follow-up that removes anything still left, once this
-- has had a chance to run.

comment on column public.calendar_connections.config is
  'Verbindungsdaten, die keine Zugangsdaten im engeren Sinn sind, aber '
  'trotzdem NICHT an den Client gehören: CalDAV-home_url, IServ-Serveradresse, '
  'Abfall-Konfiguration, WebUntis server/school/student_id — und für per Link '
  'verbundene Schulkalender die Liste "feeds" ([{id, name, host, added_at}]). '
  'Die zugehörigen ICS-URLs stehen NICHT hier, sondern verschlüsselt in '
  'calendar_connection_secrets.feed_urls; "id" ist eine undurchsichtige uuid. '
  'Nur service_role liest und schreibt hier; `authenticated` hat auf dieser '
  'Spalte weder SELECT noch UPDATE.';

comment on column public.calendars.external_id is
  'Die Kennung des Kalenders beim Anbieter. Bei per Link verbundenen '
  'Schulkalendern ist das eine undurchsichtige uuid — früher stand hier die '
  'tokenisierte ICS-URL selbst, siehe 20260910070000. `authenticated` hat auf '
  'dieser Tabelle weiterhin keinerlei Rechte: die App liest Kalender '
  'ausschließlich über die Edge Function `calendar-events`, die `external_id` '
  'bewusst nicht mitschickt.';
