-- Aporah backend — a calendar you were handed as a file, not as a link.
--
-- ---------------------------------------------------------------------------
-- Why
-- ---------------------------------------------------------------------------
--
-- 20260910093000 made `ical` a provider: paste any published ICS URL and the
-- app re-reads it on every refresh. That covers everything a family can already
-- subscribe to — and misses the case that sent us here. A German waste vendor
-- outside the six families in `_shared/abfall.ts` typically offers a *download*
-- and no subscription URL at all: the household ends up with `abfuhr2027.ics`
-- in their downloads folder and nothing to paste. The same is true of a Verein
-- that mails round a fixture list and of half the Kitas in the country.
--
-- Telling those households "your calendar is the wrong shape" is not an answer
-- when the file in their hand contains exactly the events we would have
-- fetched.
--
-- ---------------------------------------------------------------------------
-- What it costs, said plainly
-- ---------------------------------------------------------------------------
--
-- This app does not store anybody's calendar. Google, Outlook, iCloud, IServ
-- and every pasted link are proxied on each read and never materialised —
-- `public.events` is empty and unreachable, and 20260805182949 removed the
-- possibility of an own calendar on purpose.
--
-- An uploaded file is the one thing that cannot work that way, because there is
-- no server on the other end to proxy to. So the bytes are kept. What is
-- preserved is everything else about the arrangement:
--
--   * The file is the *source*, not a cache of a source. It is parsed on every
--     refresh inside `calendar-events`, exactly like a fetched feed, and no
--     VEVENT it contains is ever written to a row. There is still no table in
--     this database with somebody's appointments in it.
--   * It is read-only and unwritable. `auth_type = 'public'` with
--     `is_read_only` is the pairing the check constraint already forces, so
--     `calendar-write` has nothing to target and never offers it.
--   * It is not shareable outward. `shareable_kind` names no calendar and this
--     changes nothing about that.
--
-- And it is sealed. The argument in 20260910070000 was that a tokenised feed
-- URL is a credential and deserves a second barrier behind the revoked grants;
-- an uploaded file is *the calendar the URL would have pointed at*, which is
-- strictly the larger thing to lose. It would be incoherent to encrypt the
-- pointer and leave the contents in plain text beside it.
--
-- ---------------------------------------------------------------------------
-- The column
-- ---------------------------------------------------------------------------
--
-- `feed_files` sits beside `feed_urls` and is shaped identically —
-- `{"<feed id>": "<envelope>"}`, one AES-256-GCM envelope per feed under
-- CALENDAR_SECRET_KEY — so the same helpers serve both and a feed is a URL
-- feed or a file feed depending on which map its id is in. `config.feeds` says
-- which, in a `kind` the reader can trust: an entry without one is a URL feed,
-- which is every entry that exists today.
--
-- A separate column rather than a marker inside `feed_urls`, because the values
-- are not the same kind of thing and the table comment should not have to lie
-- about it. Also because the read paths differ: `feed_urls` is opened for every
-- feed on a connection at once (twenty short strings), while a file body is
-- megabyte-scale and is opened only for the one calendar being read.
--
-- No grant is needed. `revoke all on public.calendar_connection_secrets from
-- authenticated, anon` in 20260803101000 is table-level, so a new column is
-- unreachable the moment it exists — the same reason `app_secret` and
-- `feed_urls` needed none.

alter table public.calendar_connection_secrets
  add column feed_files jsonb not null default '{}'::jsonb;

comment on column public.calendar_connection_secrets.feed_files is
  'Hochgeladene Kalenderdateien: {"<feed-id>": "<Chiffrat>"}. Der Inhalt der '
  '.ics-Datei, einzeln verschlüsselt (AES-256-GCM, CALENDAR_SECRET_KEY), und '
  'bei jeder Aktualisierung neu geparst — es wird kein Termin daraus in eine '
  'Tabelle geschrieben. Die feed-id ist die undurchsichtige Kennung aus '
  'calendar_connections.config.feeds, wo kind = ''file'' diese Feeds von den '
  'per Link verbundenen unterscheidet.';

-- Without the WebUntis app key, which 20260910101500 deleted along with the
-- QR-code route it belonged to.
comment on table public.calendar_connection_secrets is
  'OAuth-Refresh-Tokens, CalDAV-Passwörter, die ICS-URLs per Link verbundener '
  'Kalender und die Inhalte hochgeladener Kalenderdateien. Nur service_role, '
  'nur verschlüsselt (AES-256-GCM). Der aktive Schlüssel ist '
  'CALENDAR_SECRET_KEY; ausgemusterte Schlüssel bleiben in '
  'CALENDAR_SECRET_KEY_RETIRED lesbar, bis alle Werte neu versiegelt sind.';
